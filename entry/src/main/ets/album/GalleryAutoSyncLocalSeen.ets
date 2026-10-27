/**
 * 本机已见照片快照。按账号和 NAS 分文件，和同步账本同一份身份。
 *
 * 第一次扫描只记下「确认 NAS 上已经有」的照片，不上传（官方客户端往往已经传过）；
 * NAS 上没有的会留在待同步里，第一次扫描后就该由用户/后台同步流程处理。
 * 之后只有新增或改过的照片才拿去和 NAS 去重。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagError, fnDiagRecord } from '../common/FnDiagLog';
import { dropUnscopedSyncFiles, gallerySyncScopeToken } from './GalleryAutoSyncScope';
import { LocalPhotoEntry } from './GalleryAutoSyncService';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncSeen';
/** 文件不存在（ENOENT）；其它错误码都算「读不了」。 */
const SEEN_ENOENT = 13900002;

export class LocalSeenDiff {
  /** 还没有快照：本次只建立基线，added 为空。 */
  freshBaseline: boolean = false;
  /** 快照读坏了：这一轮不比对也不写回，避免把已见记录清空。 */
  readFailed: boolean = false;
  added: LocalPhotoEntry[] = [];
  baselineCount: number = 0;
}

/** 快照读取结果：必须区分「文件不存在」与「读失败」，前者才能建基线。 */
interface SeenSnapshot {
  state: 'missing' | 'ok' | 'failed';
  keys: Set<string>;
}

function seenKey(photo: LocalPhotoEntry): string {
  const size = Number.isFinite(photo.fileSize) ? Math.floor(photo.fileSize) : 0;
  const mtime = Number.isFinite(photo.dateModifiedMs) ? Math.floor(photo.dateModifiedMs) : 0;
  return `${encodeURIComponent(photo.uri)}\t${size}\t${mtime}`;
}

export class GalleryAutoSyncLocalSeen {
  /** 最近一次读快照失败的原因；用于说明「已见记录被清空」的后果。 */
  private static lastReadError: Object | Error | null = null;

  private static filePath(ctx: common.UIAbilityContext): string {
    return `${ctx.filesDir}/auto_sync_seen_v2_${gallerySyncScopeToken()}.txt`;
  }

  /**
   * 只有 ENOENT（13900002）才算「文件不存在」，才允许建立基线；
   * 其它 stat 错误说明读不了文件，必须按读失败处理。
   */
  private static async statState(path: string): Promise<'exists' | 'missing' | 'error'> {
    try {
      await fileIo.stat(path);
      return 'exists';
    } catch (e) {
      const code = (e as BusinessError).code;
      if (code === SEEN_ENOENT) {
        return 'missing';
      }
      fnDiagError(TAG, 'seen snapshot stat failed', e);
      return 'error';
    }
  }

  private static async readSnapshot(ctx: common.UIAbilityContext): Promise<SeenSnapshot> {
    await dropUnscopedSyncFiles(ctx);
    const path = GalleryAutoSyncLocalSeen.filePath(ctx);
    const st = await GalleryAutoSyncLocalSeen.statState(path);
    if (st === 'missing') {
      return { state: 'missing', keys: new Set<string>() };
    }
    if (st === 'error') {
      return { state: 'failed', keys: new Set<string>() };
    }
    try {
      const text = await fileIo.readText(path);
      const lines = text.split('\n');
      if (lines.length === 0 || lines[0].trim() !== 'v1') {
        // 文件在但内容不是 v1：当作首次运行，重建基线
        fnDiagRecord('W', TAG, 'seen snapshot header invalid, rebuild baseline');
        return { state: 'missing', keys: new Set<string>() };
      }
      const keys = new Set<string>();
      for (let i = 1; i < lines.length; i++) {
        const line = lines[i].trim();
        if (line.length > 0) {
          keys.add(line);
        }
      }
      return { state: 'ok', keys: keys };
    } catch (e) {
      GalleryAutoSyncLocalSeen.lastReadError = e;
      fnDiagError(TAG, 'seen snapshot read failed', e);
      return { state: 'failed', keys: new Set<string>() };
    }
  }

  private static async writeKeys(ctx: common.UIAbilityContext, keys: Set<string>): Promise<void> {
    const lines: string[] = ['v1'];
    keys.forEach((key: string): void => {
      lines.push(key);
    });
    const file = await fileIo.open(
      GalleryAutoSyncLocalSeen.filePath(ctx),
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    try {
      await fileIo.write(file.fd, lines.join('\n'));
    } finally {
      await fileIo.close(file.fd);
    }
  }

  static async diff(ctx: common.UIAbilityContext, photos: LocalPhotoEntry[]): Promise<LocalSeenDiff> {
    const result = new LocalSeenDiff();
    const snap = await GalleryAutoSyncLocalSeen.readSnapshot(ctx);
    if (snap.state === 'failed') {
      // 读不到就这一轮不比对、不写回：宁可本次不传，也不能把已见记录清空
      result.readFailed = true;
      result.baselineCount = 0;
      fnDiagRecord('W', TAG, 'seen diff skipped: snapshot unreadable');
      return result;
    }
    if (snap.state === 'missing') {
      // 首次运行：基线要精确，不能把本机图库一股脑记成「已见」。
      // 这里不落盘：把所有本机条目交给 NAS 比对（调用方 GalleryAutoSyncStore），
      // 只有「确认 NAS 上已经有（同名同大小）」的才写进基线；NAS 上没有的留在待同步里，
      // 等同步成功后再由 remember() 记入。这样首装的存量照片既不会重复传，也不会被漏掉。
      const candidates: LocalPhotoEntry[] = [];
      for (let i = 0; i < photos.length; i++) {
        if (photos[i].uri.length > 0) {
          candidates.push(photos[i]);
        }
      }
      result.freshBaseline = true;
      result.baselineCount = photos.length;
      result.added = candidates;
      hilog.info(DOMAIN, TAG, 'fresh baseline candidates=%{public}d', candidates.length);
      return result;
    }
    const known = snap.keys;
    const added: LocalPhotoEntry[] = [];
    for (let i = 0; i < photos.length; i++) {
      const photo = photos[i];
      if (photo.uri.length === 0) {
        continue;
      }
      if (!known.has(seenKey(photo))) {
        added.push(photo);
      }
    }
    result.added = added;
    result.baselineCount = known.size;
    hilog.info(DOMAIN, TAG, 'seen=%{public}d added=%{public}d', known.size, added.length);
    return result;
  }

  /**
   * 丢掉本机图库里已经没有的 URI。只在扫过全部相册之后调用。
   * 读失败时不写回，避免把快照盖成空的。
   */
  static async pruneAbsent(ctx: common.UIAbilityContext, liveUris: Set<string>): Promise<void> {
    const snap = await GalleryAutoSyncLocalSeen.readSnapshot(ctx);
    if (snap.state !== 'ok' || snap.keys.size === 0) {
      return;
    }
    const removed: string[] = [];
    snap.keys.forEach((key: string): void => {
      const tab = key.indexOf('\t');
      const encoded = tab >= 0 ? key.substring(0, tab) : key;
      let uri = '';
      try {
        uri = decodeURIComponent(encoded);
      } catch (_e) {
        removed.push(key);
        return;
      }
      if (!liveUris.has(uri)) {
        removed.push(key);
      }
    });
    if (removed.length === 0) {
      return;
    }
    for (let i = 0; i < removed.length; i++) {
      snap.keys.delete(removed[i]);
    }
    await GalleryAutoSyncLocalSeen.writeKeys(ctx, snap.keys);
    fnDiagRecord('I', TAG, `seen prune dropped=${removed.length} kept=${snap.keys.size}`);
  }

  /**
   * 把当前这些照片直接记成已见，不再和 NAS 核对。
   * 只用于用户在同步设置里点「忽略现有照片」：测试账号不能把已经在手机上的私有相册传上去。
   * 之后只有没出现在这份快照里的新照片或改过的照片才会进入待上传。
   * 读失败时抛出，不能用空快照把原来的记录盖掉。
   */
  static async ignoreCurrent(ctx: common.UIAbilityContext, photos: LocalPhotoEntry[]): Promise<number> {
    const snap = await GalleryAutoSyncLocalSeen.readSnapshot(ctx);
    if (snap.state === 'failed') {
      fnDiagRecord('W', TAG, 'ignore skipped: snapshot unreadable');
      throw new Error('seen snapshot unreadable');
    }
    const known = snap.keys;
    let added = 0;
    for (let i = 0; i < photos.length; i++) {
      if (photos[i].uri.length === 0) {
        continue;
      }
      const key = seenKey(photos[i]);
      if (!known.has(key)) {
        known.add(key);
        added++;
      }
    }
    if (added > 0 || snap.state === 'missing') {
      // 第一次忽略也要落盘。否则文件仍不存在，下次扫描会当成没有基线，把整库再拿去比对。
      await GalleryAutoSyncLocalSeen.writeKeys(ctx, known);
    }
    fnDiagRecord('I', TAG, `ignore current added=${added} total=${known.size}`);
    return known.size;
  }

  static async remember(ctx: common.UIAbilityContext, photos: LocalPhotoEntry[]): Promise<void> {
    if (photos.length === 0) {
      return;
    }
    const snap = await GalleryAutoSyncLocalSeen.readSnapshot(ctx);
    if (snap.state === 'failed') {
      // 读失败时不要用空集合写回，否则会把原已见记录整个盖掉
      fnDiagRecord('W', TAG, 'remember skipped: snapshot unreadable');
      return;
    }
    const known = snap.keys;
    let changed = false;
    for (let i = 0; i < photos.length; i++) {
      if (photos[i].uri.length === 0) {
        continue;
      }
      const key = seenKey(photos[i]);
      if (!known.has(key)) {
        known.add(key);
        changed = true;
      }
    }
    if (changed) {
      await GalleryAutoSyncLocalSeen.writeKeys(ctx, known);
    }
  }
}
