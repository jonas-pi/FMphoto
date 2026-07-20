/**
 * 拉取 NAS 全库媒体指纹（original_name + size + mtime），供本地同步去重。
 * 分页遍历时间轴各日条目，避免只对比 UI 已加载的一页数据。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryGetListData, GalleryListItem, GalleryTimelineData } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import {
  buildNasDedupeIndex,
  cloneNasDedupeIndex,
  emptyNasDedupeIndex,
  NasDedupeIndex
} from './GalleryAutoSyncOfficialFingerprint';
import { DATE_FEED_BATCH, DAY_MAX_ROUNDS } from './galleryAlbumTab/GalleryAlbumTabConstants';
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
/** 按天拉取 NAS 列表的并发上限，避免全串行过慢、又不过度打满接口。 */
const NAS_DAY_FETCH_CONCURRENCY: number = 3;

function listFromData(data: GalleryGetListData | undefined): GalleryListItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  const raw = data.list ?? data.items ?? data.photos ?? data.records;
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw as GalleryListItem[];
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
  private static loadingPromise: Promise<NasDedupeIndex> | null = null;

  static invalidate(): void {
    GalleryAutoSyncNasIndex.index = emptyNasDedupeIndex();
    GalleryAutoSyncNasIndex.cachedAt = 0;
    GalleryAutoSyncNasIndex.loadingPromise = null;
  }

  static isFresh(force: boolean): boolean {
    if (force) {
      return false;
    }
    if (GalleryAutoSyncNasIndex.cachedAt <= 0) {
      return false;
    }
    return Date.now() - GalleryAutoSyncNasIndex.cachedAt < CACHE_TTL_MS;
  }

  /**
   * 获取 NAS 全库去重索引；force=true 时强制重新拉取。
   * 并发请求会复用同一 in-flight Promise，避免返回空索引。
   */
  static async getIndex(client: FnHttpClient, force: boolean = false): Promise<NasDedupeIndex> {
    if (!force && GalleryAutoSyncNasIndex.isFresh(false)) {
      return cloneNasDedupeIndex(GalleryAutoSyncNasIndex.index);
    }
    if (GalleryAutoSyncNasIndex.loadingPromise !== null) {
      const shared = await GalleryAutoSyncNasIndex.loadingPromise;
      if (!force) {
        return cloneNasDedupeIndex(shared);
      }
    }
    const task = GalleryAutoSyncNasIndex.loadIndex(client);
    GalleryAutoSyncNasIndex.loadingPromise = task;
    try {
      return await task;
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

  private static async loadIndex(client: FnHttpClient): Promise<NasDedupeIndex> {
    try {
      const timeline = await client.getGalleryTimeline();
      if (!timeline.success || timeline.data === undefined) {
        hilog.warn(DOMAIN, TAG, 'timeline failed: %{public}s', timeline.message ?? '');
        return cloneNasDedupeIndex(GalleryAutoSyncNasIndex.index);
      }
      const items = await GalleryAutoSyncNasIndex.fetchAllTimelineItems(client, timeline.data);
      const built = buildNasDedupeIndex(items);
      GalleryAutoSyncNasIndex.index = built;
      GalleryAutoSyncNasIndex.cachedAt = Date.now();
      hilog.info(
        DOMAIN,
        TAG,
        'nas index items=%{public}d fingerprints=%{public}d nameSize=%{public}d',
        items.length,
        built.fingerprints.size,
        built.nameSizeKeys.size
      );
      return cloneNasDedupeIndex(built);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'loadIndex failed: %{public}s', String(e));
      return cloneNasDedupeIndex(GalleryAutoSyncNasIndex.index);
    }
  }

  private static async fetchDayPages(
    client: FnHttpClient,
    day: TimelineDayModel,
    target: GalleryListItem[]
  ): Promise<void> {
    const st = fmtDayStart(day.year, day.month, day.day);
    const et = fmtDayEnd(day.year, day.month, day.day);
    let dayOffset = 0;
    let rounds = 0;
    while (rounds < DAY_MAX_ROUNDS) {
      const res = await client.getGalleryList(st, et, DATE_FEED_BATCH, dayOffset);
      if (!res.success || res.data === undefined) {
        break;
      }
      const list = listFromData(res.data as GalleryGetListData);
      if (list.length === 0) {
        break;
      }
      for (let i = 0; i < list.length; i++) {
        target.push(list[i]);
      }
      dayOffset += list.length;
      rounds++;
      if (list.length < DATE_FEED_BATCH) {
        break;
      }
    }
  }

  private static async fetchAllTimelineItems(
    client: FnHttpClient,
    timeline: GalleryTimelineData
  ): Promise<GalleryListItem[]> {
    const out: GalleryListItem[] = [];
    const days = collectTimelineDays(timeline);
    for (let i = 0; i < days.length; i += NAS_DAY_FETCH_CONCURRENCY) {
      const chunkEnd: number = Math.min(i + NAS_DAY_FETCH_CONCURRENCY, days.length);
      const tasks: Promise<GalleryListItem[]>[] = [];
      for (let j = i; j < chunkEnd; j++) {
        const day = days[j];
        tasks.push((async (): Promise<GalleryListItem[]> => {
          const part: GalleryListItem[] = [];
          await GalleryAutoSyncNasIndex.fetchDayPages(client, day, part);
          return part;
        })());
      }
      const parts: GalleryListItem[][] = await Promise.all(tasks);
      for (let p = 0; p < parts.length; p++) {
        const part = parts[p];
        for (let k = 0; k < part.length; k++) {
          out.push(part[k]);
        }
      }
    }
    return out;
  }
}
