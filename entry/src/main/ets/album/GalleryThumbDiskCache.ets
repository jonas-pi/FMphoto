/**
 * 缩略图磁盘缓存：把鉴权下载的 JPEG 落到应用 cacheDir，进程重启后无需再走网络。
 *
 * 鸿蒙依据：
 * - Image 内置缓存（setImageCacheCount / setImageFileCacheSize）只覆盖 Image(网络 URL)；
 *   本应用网格走鉴权 HTTP + PixelMap，官方建议「数量较多时用 HTTP 预下载并由应用侧管理」。
 * - 长列表 cachedCount 建议约为可视条数 n/2；未设置时默认等于可视节点数、上限 16。
 * - 日视图约 3 列 × 6 行 = 18 张可视，再加 cachedCount=3 行预加载 ≈ 9 张，合计约 27 张。
 *   首屏磁盘只固化 [18, 36] 区间，避免整库落盘。
 * - 相册页封面数量少且常驻，全部落盘。
 */
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';

const DOMAIN = 0xFF00;
const TAG = 'ThumbDisk';

/** 不写磁盘 */
export const THUMB_DISK_NONE: number = 0;
/** 时间线首屏（含少量预加载带） */
export const THUMB_DISK_FIRST_SCREEN: number = 1;
/** 相册页封面 */
export const THUMB_DISK_ALBUM_COVER: number = 2;
/** 缩略图三层缓存失效后递增，供 @StorageProp 驱动组件重载 */
export const GALLERY_THUMB_CACHE_EPOCH_KEY: string = 'galleryThumbCacheEpoch';

/** 日视图约一屏 18 张；低于此值仍补到一屏下限 */
export const THUMB_DISK_FIRST_SCREEN_MIN: number = 18;
/** 两屏上限，与官方「网络图 cachedCount 可大于 n/2、但过大伤首屏」一致 */
export const THUMB_DISK_FIRST_SCREEN_MAX: number = 36;
/** 相册封面数量远小于网格，给足余量即可 */
const THUMB_DISK_ALBUM_COVER_MAX: number = 80;
const THUMB_DISK_MAX_FILE_BYTES: number = 4 * 1024 * 1024;
const THUMB_DISK_DIR_NAME: string = 'gallery_thumbs';

class ThumbDiskStat {
  name: string = '';
  path: string = '';
  mtimeMs: number = 0;
}

export class GalleryThumbDiskCache {
  private static cacheDir: string = '';
  private static dirReady: boolean = false;
  private static firstScreenLocked: boolean = false;
  private static readonly firstScreenKeys: Set<string> = new Set();
  private static readonly albumCoverKeys: Set<string> = new Set();
  private static readonly inflightPut: Map<string, Promise<void>> = new Map();
  /** NAS 数据变更时递增；异步清盘完成前 tryRead 直接 miss，避免读到旧 JPEG。 */
  static generation: number = 0;
  private static purgeGen: number = 0;
  private static diskReadyGen: number = 0;

  /** Ability 启动时注入 cacheDir；mkdir 延迟到首次读写。 */
  static init(cacheDir: string): void {
    const trimmed = cacheDir.trim();
    if (trimmed.length <= 0) {
      return;
    }
    GalleryThumbDiskCache.cacheDir = trimmed;
  }

  /**
   * 首屏落盘张数：可视行 × 列 + 最多 3 行预加载，再夹到 [18, 36]。
   * cachedCount 与 List 日/月/年设置对齐（3 / 8 / 14），但磁盘不跟月/年把预加载扩到整屏。
   */
  static recommendedFirstScreenCount(columns: number, listCachedCount: number): number {
    const cols = Math.max(1, Math.floor(columns));
    const visibleRows = 6;
    const preloadRows = Math.min(3, Math.max(0, Math.floor(listCachedCount)));
    const raw = cols * (visibleRows + preloadRows);
    if (raw < THUMB_DISK_FIRST_SCREEN_MIN) {
      return THUMB_DISK_FIRST_SCREEN_MIN;
    }
    if (raw > THUMB_DISK_FIRST_SCREEN_MAX) {
      return THUMB_DISK_FIRST_SCREEN_MAX;
    }
    return raw;
  }

  static lockFirstScreen(cacheKeys: string[]): void {
    GalleryThumbDiskCache.firstScreenKeys.clear();
    for (let i = 0; i < cacheKeys.length; i++) {
      const key = cacheKeys[i];
      if (key.length > 0) {
        GalleryThumbDiskCache.firstScreenKeys.add(key);
      }
    }
    GalleryThumbDiskCache.firstScreenLocked = true;
  }

  /** 以当前封面集合替换旧集合，并删掉已不再使用的封面文件。 */
  static replaceAlbumCovers(cacheKeys: string[]): string[] {
    const next: Set<string> = new Set();
    for (let i = 0; i < cacheKeys.length; i++) {
      const key = cacheKeys[i];
      if (key.length > 0) {
        next.add(key);
      }
    }
    const removed: string[] = [];
    GalleryThumbDiskCache.albumCoverKeys.forEach((oldKey: string): void => {
      if (!next.has(oldKey)) {
        removed.push(oldKey);
      }
    });
    GalleryThumbDiskCache.albumCoverKeys.clear();
    next.forEach((key: string): void => {
      GalleryThumbDiskCache.albumCoverKeys.add(key);
    });
    for (let i = 0; i < removed.length; i++) {
      void GalleryThumbDiskCache.unlinkQuiet(
        GalleryThumbDiskCache.filePath(THUMB_DISK_ALBUM_COVER, removed[i])
      );
    }
    return removed;
  }

  /**
   * NAS 新增/删除/封面更新后丢弃磁盘 JPEG。
   * 立即抬升 generation，清盘异步进行；期间 tryRead 返回空，强制走网络。
   */
  static invalidateAll(): void {
    GalleryThumbDiskCache.generation++;
    GalleryThumbDiskCache.purgeGen = GalleryThumbDiskCache.generation;
    GalleryThumbDiskCache.firstScreenKeys.clear();
    GalleryThumbDiskCache.albumCoverKeys.clear();
    GalleryThumbDiskCache.firstScreenLocked = false;
    const gen = GalleryThumbDiskCache.purgeGen;
    void GalleryThumbDiskCache.purgeAllFiles(gen);
  }

  static isPurgeInFlight(): boolean {
    return GalleryThumbDiskCache.purgeGen !== GalleryThumbDiskCache.diskReadyGen;
  }

  /**
   * 解析是否应落盘。封面优先；已锁定的首屏集合次之；
   * 锁定前对先加载的缩略图做机会性收纳，避免首屏组件先于 lock 完成时漏写。
   */
  static resolveKind(cacheKey: string, requested: number): number {
    if (cacheKey.length <= 0) {
      return THUMB_DISK_NONE;
    }
    if (requested === THUMB_DISK_ALBUM_COVER || GalleryThumbDiskCache.albumCoverKeys.has(cacheKey)) {
      return THUMB_DISK_ALBUM_COVER;
    }
    if (requested === THUMB_DISK_FIRST_SCREEN || GalleryThumbDiskCache.firstScreenKeys.has(cacheKey)) {
      return THUMB_DISK_FIRST_SCREEN;
    }
    if (!GalleryThumbDiskCache.firstScreenLocked &&
      GalleryThumbDiskCache.firstScreenKeys.size < THUMB_DISK_FIRST_SCREEN_MAX) {
      GalleryThumbDiskCache.firstScreenKeys.add(cacheKey);
      return THUMB_DISK_FIRST_SCREEN;
    }
    return THUMB_DISK_NONE;
  }

  static async tryRead(cacheKey: string): Promise<ArrayBuffer | undefined> {
    if (cacheKey.length <= 0 || GalleryThumbDiskCache.cacheDir.length <= 0) {
      return undefined;
    }
    if (GalleryThumbDiskCache.isPurgeInFlight()) {
      return undefined;
    }
    const coverPath = GalleryThumbDiskCache.filePath(THUMB_DISK_ALBUM_COVER, cacheKey);
    const coverBuf = await GalleryThumbDiskCache.readFile(coverPath);
    if (coverBuf !== undefined) {
      return coverBuf;
    }
    return await GalleryThumbDiskCache.readFile(
      GalleryThumbDiskCache.filePath(THUMB_DISK_FIRST_SCREEN, cacheKey)
    );
  }

  static put(cacheKey: string, data: ArrayBuffer, kind: number): void {
    if (kind === THUMB_DISK_NONE || cacheKey.length <= 0 || data.byteLength <= 0) {
      return;
    }
    if (data.byteLength > THUMB_DISK_MAX_FILE_BYTES) {
      return;
    }
    // 清盘进行中写入会被 purge 删掉，等下一轮 ensurePersisted 再落盘
    if (GalleryThumbDiskCache.isPurgeInFlight()) {
      return;
    }
    const inflight = GalleryThumbDiskCache.inflightPut.get(cacheKey);
    if (inflight !== undefined) {
      return;
    }
    const gen = GalleryThumbDiskCache.generation;
    const job = GalleryThumbDiskCache.writeAndEvict(cacheKey, data, kind, gen);
    GalleryThumbDiskCache.inflightPut.set(cacheKey, job);
    void job.then((): void => {
      GalleryThumbDiskCache.inflightPut.delete(cacheKey);
    }).catch((): void => {
      GalleryThumbDiskCache.inflightPut.delete(cacheKey);
    });
  }

  /** 锁定/标记后补写尚未落盘的 JPEG，不解码，避免与网格 PixelMap 抢内存。 */
  static ensurePersisted(cacheKey: string, kind: number): void {
    if (kind === THUMB_DISK_NONE || cacheKey.length <= 0) {
      return;
    }
    void GalleryThumbDiskCache.ensurePersistedAsync(cacheKey, kind);
  }

  private static async ensurePersistedAsync(cacheKey: string, kind: number): Promise<void> {
    const gen = GalleryThumbDiskCache.generation;
    const idle = await GalleryThumbDiskCache.waitPurgeIdle(gen);
    if (!idle) {
      return;
    }
    const existed = await GalleryThumbDiskCache.tryRead(cacheKey);
    if (existed !== undefined) {
      return;
    }
    if (gen !== GalleryThumbDiskCache.generation) {
      return;
    }
    const url = GalleryThumbDiskCache.urlFromCacheKey(cacheKey);
    if (url.length <= 0) {
      return;
    }
    const client = AppSession.getClient();
    if (client === null) {
      return;
    }
    try {
      const buf = await client.fetchGalleryImageBuffer(url, 8000);
      if (buf !== undefined && buf.byteLength > 0 && gen === GalleryThumbDiskCache.generation) {
        GalleryThumbDiskCache.put(cacheKey, buf, kind);
      }
    } catch (_e) {
    }
  }

  private static urlFromCacheKey(cacheKey: string): string {
    const sep = cacheKey.indexOf('|');
    if (sep < 0 || sep + 1 >= cacheKey.length) {
      return cacheKey;
    }
    return cacheKey.substring(sep + 1);
  }

  private static async writeAndEvict(cacheKey: string, data: ArrayBuffer, kind: number, gen: number): Promise<void> {
    if (gen !== GalleryThumbDiskCache.generation) {
      return;
    }
    const idle = await GalleryThumbDiskCache.waitPurgeIdle(gen);
    if (!idle) {
      return;
    }
    const ready = await GalleryThumbDiskCache.ensureDir();
    if (!ready || gen !== GalleryThumbDiskCache.generation) {
      return;
    }
    const path = GalleryThumbDiskCache.filePath(kind, cacheKey);
    const ok = await GalleryThumbDiskCache.writeFile(path, data);
    if (!ok) {
      return;
    }
    if (gen !== GalleryThumbDiskCache.generation) {
      await GalleryThumbDiskCache.unlinkQuiet(path);
      return;
    }
    await GalleryThumbDiskCache.evictIfNeeded(kind);
  }

  /** 清盘未完成时不要写新 JPEG，避免刚写入就被 purge 删掉。 */
  private static async waitPurgeIdle(gen: number): Promise<boolean> {
    let spins = 0;
    while (GalleryThumbDiskCache.isPurgeInFlight() &&
      gen === GalleryThumbDiskCache.generation &&
      spins < 50) {
      await GalleryThumbDiskCache.delayMs(20);
      spins++;
    }
    return gen === GalleryThumbDiskCache.generation && !GalleryThumbDiskCache.isPurgeInFlight();
  }

  private static delayMs(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }

  private static async unlinkQuiet(path: string): Promise<void> {
    try {
      await fileIo.unlink(path);
    } catch (_e) {
    }
  }

  private static async purgeAllFiles(gen: number): Promise<void> {
    const ready = await GalleryThumbDiskCache.ensureDir();
    if (!ready) {
      if (gen === GalleryThumbDiskCache.purgeGen) {
        GalleryThumbDiskCache.diskReadyGen = gen;
      }
      return;
    }
    let names: string[] = [];
    try {
      names = await fileIo.listFile(GalleryThumbDiskCache.dirPath());
    } catch (_e) {
      names = [];
    }
    const dir = GalleryThumbDiskCache.dirPath();
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      if (name.indexOf('fs_') !== 0 && name.indexOf('ac_') !== 0) {
        continue;
      }
      await GalleryThumbDiskCache.unlinkQuiet(`${dir}/${name}`);
    }
    if (gen === GalleryThumbDiskCache.purgeGen) {
      GalleryThumbDiskCache.diskReadyGen = gen;
    }
  }

  private static async ensureDir(): Promise<boolean> {
    if (GalleryThumbDiskCache.cacheDir.length <= 0) {
      return false;
    }
    if (GalleryThumbDiskCache.dirReady) {
      return true;
    }
    const dir = GalleryThumbDiskCache.dirPath();
    try {
      await fileIo.access(dir);
      GalleryThumbDiskCache.dirReady = true;
      return true;
    } catch (_e) {
    }
    try {
      await fileIo.mkdir(dir);
      GalleryThumbDiskCache.dirReady = true;
      return true;
    } catch (_e) {
      try {
        await fileIo.access(dir);
        GalleryThumbDiskCache.dirReady = true;
        return true;
      } catch (_e2) {
        hilog.warn(DOMAIN, TAG, 'mkdir thumb disk cache failed');
        return false;
      }
    }
  }

  private static dirPath(): string {
    return `${GalleryThumbDiskCache.cacheDir}/${THUMB_DISK_DIR_NAME}`;
  }

  private static filePath(kind: number, cacheKey: string): string {
    const prefix = kind === THUMB_DISK_ALBUM_COVER ? 'ac' : 'fs';
    return `${GalleryThumbDiskCache.dirPath()}/${prefix}_${GalleryThumbDiskCache.hashKey(cacheKey)}.img`;
  }

  private static hashKey(cacheKey: string): string {
    let hash = 0;
    for (let i = 0; i < cacheKey.length; i++) {
      hash = (hash * 131 + cacheKey.charCodeAt(i)) % 2147483647;
    }
    return `${cacheKey.length}_${hash}`;
  }

  private static async readFile(path: string): Promise<ArrayBuffer | undefined> {
    let fd = -1;
    try {
      // 文件不存在时 access 抛错且不走 stat/open，避免 file_api CheckFsStat / open -2
      await fileIo.access(path);
      const st = await fileIo.stat(path);
      const size = Math.floor(Number(st.size));
      if (size <= 0 || size > THUMB_DISK_MAX_FILE_BYTES) {
        return undefined;
      }
      const f = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      fd = f.fd;
      const buf = new ArrayBuffer(size);
      const n = await fileIo.read(fd, buf);
      if (n <= 0) {
        return undefined;
      }
      return buf;
    } catch (_e) {
      return undefined;
    } finally {
      if (fd >= 0) {
        try {
          await fileIo.close(fd);
        } catch (_e) {
        }
      }
    }
  }

  private static async writeFile(path: string, data: ArrayBuffer): Promise<boolean> {
    let fd = -1;
    try {
      const f = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fd = f.fd;
      await fileIo.write(fd, data);
      return true;
    } catch (_e) {
      return false;
    } finally {
      if (fd >= 0) {
        try {
          await fileIo.close(fd);
        } catch (_e) {
        }
      }
    }
  }

  private static async evictIfNeeded(kind: number): Promise<void> {
    const prefix = kind === THUMB_DISK_ALBUM_COVER ? 'ac_' : 'fs_';
    const maxKeep = kind === THUMB_DISK_ALBUM_COVER
      ? THUMB_DISK_ALBUM_COVER_MAX
      : THUMB_DISK_FIRST_SCREEN_MAX;
    const allow = kind === THUMB_DISK_ALBUM_COVER
      ? GalleryThumbDiskCache.albumCoverKeys
      : GalleryThumbDiskCache.firstScreenKeys;
    const stats = await GalleryThumbDiskCache.listPrefix(prefix);
    const stale: ThumbDiskStat[] = [];
    const kept: ThumbDiskStat[] = [];
    for (let i = 0; i < stats.length; i++) {
      const item = stats[i];
      if (GalleryThumbDiskCache.firstScreenLocked && kind === THUMB_DISK_FIRST_SCREEN) {
        if (!GalleryThumbDiskCache.nameMatchesAllow(item.name, allow, prefix)) {
          stale.push(item);
          continue;
        }
      }
      kept.push(item);
    }
    for (let i = 0; i < stale.length; i++) {
      try {
        await fileIo.unlink(stale[i].path);
      } catch (_e) {
      }
    }
    if (kept.length <= maxKeep) {
      return;
    }
    kept.sort((a: ThumbDiskStat, b: ThumbDiskStat): number => a.mtimeMs - b.mtimeMs);
    const overflow = kept.length - maxKeep;
    for (let i = 0; i < overflow; i++) {
      try {
        await fileIo.unlink(kept[i].path);
      } catch (_e) {
      }
    }
  }

  private static nameMatchesAllow(name: string, allow: Set<string>, prefix: string): boolean {
    if (allow.size <= 0) {
      return true;
    }
    let matched: boolean = false;
    allow.forEach((key: string): void => {
      const expect = `${prefix}${GalleryThumbDiskCache.hashKey(key)}.img`;
      if (name === expect) {
        matched = true;
      }
    });
    return matched;
  }

  private static async listPrefix(prefix: string): Promise<ThumbDiskStat[]> {
    const out: ThumbDiskStat[] = [];
    const dir = GalleryThumbDiskCache.dirPath();
    let names: string[] = [];
    try {
      names = await fileIo.listFile(dir);
    } catch (_e) {
      return out;
    }
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      if (name.indexOf(prefix) !== 0) {
        continue;
      }
      const path = `${dir}/${name}`;
      const item = new ThumbDiskStat();
      item.name = name;
      item.path = path;
      try {
        const st = await fileIo.stat(path);
        item.mtimeMs = st.mtime;
      } catch (_e) {
        item.mtimeMs = 0;
      }
      out.push(item);
    }
    return out;
  }
}
