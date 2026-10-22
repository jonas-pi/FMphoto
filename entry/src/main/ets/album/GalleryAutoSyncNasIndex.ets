/**
 * 拉取 NAS 全库媒体元数据（original_name + size + mtime），供本地同步去重。
 * 分页遍历时间轴各日条目，避免只对比 UI 已加载的一页数据。
 * 扫完写入本机文件，下次在有效期内直接用，不再把时间轴按天重拉一遍。
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagError, fnDiagRecord } from '../common/FnDiagLog';
import { GalleryGetListData, GalleryListItem, GalleryTimelineData } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import {
  buildNasDedupeIndex,
  cloneNasDedupeIndex,
  emptyNasDedupeIndex,
  localPhotoNameSizeKey,
  localPhotoOfficialFingerprint,
  nasLivePhotoLikelyOnNas,
  officialNameSizeKey,
  officialOriginalNameKey,
  localPhotoSizeMtimeKey,
  NasDedupeIndex
} from './GalleryAutoSyncOfficialFingerprint';
import { LocalPhotoEntry } from './GalleryAutoSyncService';
import { galleryListFromData } from './GalleryListItemNormalize';
import { DAY_MAX_ROUNDS } from './galleryAlbumTab/GalleryAlbumTabConstants';
import {
  fmtDayEnd,
  fmtDayStart,
  parseTimelineDayCells,
  sortDaysDesc,
  TimelineDayModel
} from './galleryAlbumTab/GalleryAlbumTabTypes';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncNasIdx';
const CACHE_TTL_MS: number = 30 * 60 * 1000;
/** 落盘索引在这段时间内直接复用，避免每次扫描都把 NAS 时间轴按天重拉。 */
const DISK_TTL_MS: number = 24 * 60 * 60 * 1000;
const NAS_INDEX_FILE: string = 'auto_sync_nas_index_v1.txt';
/** 索引用的分页比界面时间轴更大，减少往返次数。 */
const NAS_INDEX_PAGE_SIZE: number = 100;
/** 按天拉取 NAS 列表的并发。对比阶段是网络往返，不是 CPU，线程帮不上忙。 */
const NAS_DAY_FETCH_CONCURRENCY: number = 8;

/** 按天拉取 NAS 媒体列表时的进度（doneDays ≤ totalDays）。 */
export type NasIndexDayProgress = (doneDays: number, totalDays: number) => void;

/** 某一天抓取的结果：complete=false 表示这一天没抓全。 */
interface NasIndexDayPart {
  items: GalleryListItem[];
  complete: boolean;
}

/** 全量抓取结果：只有 complete=true 才允许覆盖索引与磁盘缓存。 */
interface NasIndexFetch {
  items: GalleryListItem[];
  complete: boolean;
}

function listFromData(data: GalleryGetListData | undefined): GalleryListItem[] {
  return galleryListFromData(data);
}

function collectTimelineDays(timeline: GalleryTimelineData): TimelineDayModel[] {
  const raw = timeline.list ?? [];
  const rows: Array<Record<string, number | undefined>> = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (typeof item === 'object' && item !== null) {
      rows.push(item as Record<string, number | undefined>);
    }
  }
  return sortDaysDesc(parseTimelineDayCells(rows)).filter((day: TimelineDayModel): boolean => day.itemCount > 0);
}

export class GalleryAutoSyncNasIndex {
  private static index: NasDedupeIndex = emptyNasDedupeIndex();
  private static cachedAt: number = 0;
  private static diskValidUntil: number = 0;
  private static loadingPromise: Promise<NasDedupeIndex> | null = null;
  private static pendingDiscard: boolean = false;

  static invalidate(): void {
    GalleryAutoSyncNasIndex.index = emptyNasDedupeIndex();
    GalleryAutoSyncNasIndex.cachedAt = 0;
    GalleryAutoSyncNasIndex.diskValidUntil = 0;
    GalleryAutoSyncNasIndex.loadingPromise = null;
    GalleryAutoSyncNasIndex.pendingDiscard = true;
  }

  static addLocalEntries(entries: LocalPhotoEntry[]): void {
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      const fingerprint = localPhotoOfficialFingerprint(entry);
      const sizeMtime = localPhotoSizeMtimeKey(entry);
      const nameSize = localPhotoNameSizeKey(entry);
      if (fingerprint.length > 0) {
        GalleryAutoSyncNasIndex.index.fingerprints.add(fingerprint);
      }
      if (sizeMtime.length > 0) {
        GalleryAutoSyncNasIndex.index.sizeMtimeKeys.add(sizeMtime);
      }
      if (nameSize.length > 0) {
        GalleryAutoSyncNasIndex.index.nameSizeKeys.add(nameSize);
      }
      const nameKey = officialOriginalNameKey(entry.fileName);
      if (nameKey.length > 0) {
        GalleryAutoSyncNasIndex.index.originalNames.add(nameKey);
      }
    }
  }

  static isFresh(force: boolean): boolean {
    if (force) {
      return false;
    }
    if (GalleryAutoSyncNasIndex.diskValidUntil > Date.now() && GalleryAutoSyncNasIndex.cachedAt > 0) {
      return true;
    }
    if (GalleryAutoSyncNasIndex.cachedAt <= 0) {
      return false;
    }
    return Date.now() - GalleryAutoSyncNasIndex.cachedAt < CACHE_TTL_MS;
  }

  /**
   * 获取 NAS 全库去重索引；force=true 时强制重新拉取。
   * 并发请求会复用同一 in-flight Promise，避免返回空索引。
   * 传入 ctx 时，先读本机已保存的索引，有效期内不再按天请求。
   */
  static async getIndex(
    client: FnHttpClient,
    force: boolean = false,
    ctx: common.UIAbilityContext | null = null,
    onDayProgress: NasIndexDayProgress | null = null
  ): Promise<NasDedupeIndex> {
    if (ctx !== null) {
      await GalleryAutoSyncNasIndex.ensureDisk(ctx);
    }
    if (!force && GalleryAutoSyncNasIndex.isFresh(false)) {
      return cloneNasDedupeIndex(GalleryAutoSyncNasIndex.index);
    }
    if (GalleryAutoSyncNasIndex.loadingPromise !== null) {
      const shared = await GalleryAutoSyncNasIndex.loadingPromise;
      if (!force) {
        return cloneNasDedupeIndex(shared);
      }
    }
    const task = GalleryAutoSyncNasIndex.loadIndex(client, onDayProgress);
    GalleryAutoSyncNasIndex.loadingPromise = task;
    try {
      const loaded = await task;
      if (ctx !== null && GalleryAutoSyncNasIndex.diskValidUntil > Date.now()) {
        await GalleryAutoSyncNasIndex.persist(ctx);
      }
      return loaded;
    } finally {
      if (GalleryAutoSyncNasIndex.loadingPromise === task) {
        GalleryAutoSyncNasIndex.loadingPromise = null;
      }
    }
  }

  /** @deprecated 使用 getIndex */
  static async getFingerprints(client: FnHttpClient, force: boolean = false): Promise<Set<string>> {
    const index = await GalleryAutoSyncNasIndex.getIndex(client, force);
    return index.fingerprints;
  }

  private static async loadIndex(
    client: FnHttpClient,
    onDayProgress: NasIndexDayProgress | null = null
  ): Promise<NasDedupeIndex> {
    let fetched: NasIndexFetch | null = null;
    try {
      const timeline = await client.getGalleryTimeline();
      if (!timeline.success || timeline.data === undefined) {
        hilog.warn(DOMAIN, TAG, 'timeline failed: %{public}s', timeline.message ?? '');
        return cloneNasDedupeIndex(GalleryAutoSyncNasIndex.index);
      }
      fetched = await GalleryAutoSyncNasIndex.fetchAllTimelineItems(client, timeline.data, onDayProgress);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'loadIndex failed: %{public}s', String(e));
      return cloneNasDedupeIndex(GalleryAutoSyncNasIndex.index);
    }
    if (fetched === null) {
      return cloneNasDedupeIndex(GalleryAutoSyncNasIndex.index);
    }
    if (!fetched.complete) {
      // 有某天没抓全：不要拿残缺结果覆盖内存索引，也不要续命 24 小时磁盘缓存。
      // 没有上一份完整索引时必须抛到比对侧（按比对失败结束），不能拿空索引关掉 NAS 去重。
      if (!GalleryAutoSyncNasIndex.nasIndexUsable()) {
        fnDiagRecord('E', TAG, 'nas index incomplete and no previous index');
        throw new Error('nas index incomplete');
      }
      fnDiagRecord('W', TAG, 'nas index incomplete, keep previous index');
      return cloneNasDedupeIndex(GalleryAutoSyncNasIndex.index);
    }
    try {
      const items = fetched.items;
      const built = buildNasDedupeIndex(items);
      GalleryAutoSyncNasIndex.index = built;
      GalleryAutoSyncNasIndex.cachedAt = Date.now();
      GalleryAutoSyncNasIndex.diskValidUntil = GalleryAutoSyncNasIndex.cachedAt + DISK_TTL_MS;
      hilog.info(
        DOMAIN,
        TAG,
        'nas index items=%{public}d fingerprints=%{public}d sizeMtime=%{public}d nameSize=%{public}d',
        items.length,
        built.fingerprints.size,
        built.sizeMtimeKeys.size,
        built.nameSizeKeys.size
      );
      return cloneNasDedupeIndex(built);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'loadIndex build failed: %{public}s', String(e));
      return cloneNasDedupeIndex(GalleryAutoSyncNasIndex.index);
    }
  }

  /**
   * 抓取某一天的 NAS 名单。
   * 返回 false 表示这一天没抓全（请求失败），调用方不得用残缺结果覆盖索引。
   */
  private static async fetchDayPages(
    client: FnHttpClient,
    day: TimelineDayModel,
    target: GalleryListItem[]
  ): Promise<boolean> {
    const st = fmtDayStart(day.year, day.month, day.day);
    const et = fmtDayEnd(day.year, day.month, day.day);
    let dayOffset = 0;
    let rounds = 0;
    while (rounds < DAY_MAX_ROUNDS) {
      const res = await client.getGalleryList(st, et, NAS_INDEX_PAGE_SIZE, dayOffset);
      if (!res.success || res.data === undefined) {
        // 这一天抓不全：返回 false，交给上层决定「保留上一份完整索引」
        const msg: string = (res.message ?? '').trim();
        fnDiagRecord('W', TAG, `day list failed ${day.year}-${day.month}-${day.day} ${msg.substring(0, 80)}`);
        return false;
      }
      const list = listFromData(res.data as GalleryGetListData);
      if (list.length === 0) {
        return true;
      }
      for (let i = 0; i < list.length; i++) {
        target.push(list[i]);
      }
      dayOffset += list.length;
      rounds++;
      if (list.length < NAS_INDEX_PAGE_SIZE) {
        return true;
      }
    }
    return true;
  }

  private static async fetchAllTimelineItems(
    client: FnHttpClient,
    timeline: GalleryTimelineData,
    onDayProgress: NasIndexDayProgress | null = null
  ): Promise<NasIndexFetch> {
    const out: GalleryListItem[] = [];
    let complete: boolean = true;
    const days = collectTimelineDays(timeline);
    const totalDays: number = days.length;
    if (onDayProgress !== null && totalDays > 0) {
      onDayProgress(0, totalDays);
    }
    let doneDays: number = 0;
    for (let i = 0; i < days.length; i += NAS_DAY_FETCH_CONCURRENCY) {
      const chunkEnd: number = Math.min(i + NAS_DAY_FETCH_CONCURRENCY, days.length);
      const tasks: Promise<NasIndexDayPart>[] = [];
      for (let j = i; j < chunkEnd; j++) {
        const day = days[j];
        tasks.push((async (): Promise<NasIndexDayPart> => {
          const part: GalleryListItem[] = [];
          const ok = await GalleryAutoSyncNasIndex.fetchDayPages(client, day, part);
          return { items: part, complete: ok };
        })());
      }
      const parts: NasIndexDayPart[] = await Promise.all(tasks);
      for (let p = 0; p < parts.length; p++) {
        const part = parts[p];
        for (let k = 0; k < part.items.length; k++) {
          out.push(part.items[k]);
        }
        if (!part.complete) {
          complete = false;
        }
      }
      doneDays = chunkEnd;
      if (onDayProgress !== null && totalDays > 0) {
        onDayProgress(doneDays, totalDays);
      }
    }
    return { items: out, complete: complete };
  }

  private static indexPath(ctx: common.UIAbilityContext): string {
    return `${ctx.filesDir}/${NAS_INDEX_FILE}`;
  }

  private static async ensureDisk(ctx: common.UIAbilityContext): Promise<void> {
    const path = GalleryAutoSyncNasIndex.indexPath(ctx);
    if (GalleryAutoSyncNasIndex.pendingDiscard) {
      GalleryAutoSyncNasIndex.pendingDiscard = false;
      await GalleryAutoSyncNasIndex.deleteFile(path);
      return;
    }
    if (GalleryAutoSyncNasIndex.isFresh(false)) {
      return;
    }
    try {
      const text = await fileIo.readText(path);
      GalleryAutoSyncNasIndex.applyDiskText(text);
    } catch (e) {
      fnDiagError(TAG, 'disk index read failed', e);
    }
  }

  private static applyDiskText(text: string): void {
    const lines = text.split('\n');
    if (lines.length === 0 || !lines[0].startsWith('v1 ')) {
      return;
    }
    const savedAt = Number(lines[0].substring(3).trim());
    if (!Number.isFinite(savedAt) || Date.now() - savedAt >= DISK_TTL_MS) {
      return;
    }
    const index = emptyNasDedupeIndex();
    let section = '';
    for (let i = 1; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      if (line === '@fp' || line === '@sm' || line === '@ns' || line === '@on') {
        section = line;
        continue;
      }
      if (section === '@fp') {
        index.fingerprints.add(line);
      } else if (section === '@sm') {
        index.sizeMtimeKeys.add(line);
      } else if (section === '@ns') {
        index.nameSizeKeys.add(line);
      } else if (section === '@on') {
        index.originalNames.add(line);
      }
    }
    index.nameSizeKeys.forEach((key: string): void => {
      const colon = key.lastIndexOf(':');
      if (colon > 0) {
        const namePart = key.substring(0, colon).trim();
        if (namePart.length > 0) {
          index.originalNames.add(namePart);
        }
      }
    });
    GalleryAutoSyncNasIndex.index = index;
    GalleryAutoSyncNasIndex.cachedAt = savedAt;
    GalleryAutoSyncNasIndex.diskValidUntil = savedAt + DISK_TTL_MS;
    hilog.info(
      DOMAIN,
      TAG,
      'nas index disk fingerprints=%{public}d ageMin=%{public}d',
      index.fingerprints.size,
      Math.floor((Date.now() - savedAt) / 60000)
    );
  }

  private static async persist(ctx: common.UIAbilityContext): Promise<void> {
    const index = GalleryAutoSyncNasIndex.index;
    const lines: string[] = [`v1 ${GalleryAutoSyncNasIndex.cachedAt}`, '@fp'];
    index.fingerprints.forEach((key: string): void => {
      lines.push(key);
    });
    lines.push('@sm');
    index.sizeMtimeKeys.forEach((key: string): void => {
      lines.push(key);
    });
    lines.push('@ns');
    index.nameSizeKeys.forEach((key: string): void => {
      lines.push(key);
    });
    lines.push('@on');
    index.originalNames.forEach((key: string): void => {
      lines.push(key);
    });
    const path = GalleryAutoSyncNasIndex.indexPath(ctx);
    try {
      const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, lines.join('\n'));
      } finally {
        await fileIo.close(file.fd);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'persist nas index failed: %{public}s', String(e));
    }
  }

  static nameSizeCount(): number {
    return GalleryAutoSyncNasIndex.index.nameSizeKeys.size;
  }

  static hasNameSize(fileName: string, fileSize: number): boolean {
    const key = officialNameSizeKey(fileName, fileSize);
    return key.length > 0 && GalleryAutoSyncNasIndex.index.nameSizeKeys.has(key);
  }

  static liveLikelyOnNas(fileName: string, localFileSize: number): boolean {
    return nasLivePhotoLikelyOnNas(GalleryAutoSyncNasIndex.index, fileName, localFileSize);
  }

  static nasIndexUsable(): boolean {
    const index = GalleryAutoSyncNasIndex.index;
    return index.nameSizeKeys.size > 0 || index.originalNames.size > 0 || index.fingerprints.size > 0;
  }

  static discardDisk(ctx: common.UIAbilityContext): Promise<void> {
    GalleryAutoSyncNasIndex.pendingDiscard = false;
    return GalleryAutoSyncNasIndex.deleteFile(GalleryAutoSyncNasIndex.indexPath(ctx));
  }

  private static async deleteFile(path: string): Promise<void> {
    try {
      await fileIo.unlink(path);
    } catch (_e) {
    }
  }
}
