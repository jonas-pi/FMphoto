/**
 * 拉取 NAS 全库媒体指纹（original_name + size + mtime），供本地同步去重。
 * 分页遍历时间轴各日条目，避免只对比 UI 已加载的一页数据。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryGetListData, GalleryListItem, GalleryTimelineData } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { buildNasOfficialFingerprints } from './GalleryAutoSyncOfficialFingerprint';
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
  private static fingerprints: Set<string> = new Set<string>();
  private static cachedAt: number = 0;
  private static loading: boolean = false;

  static invalidate(): void {
    GalleryAutoSyncNasIndex.fingerprints = new Set<string>();
    GalleryAutoSyncNasIndex.cachedAt = 0;
    GalleryAutoSyncNasIndex.loading = false;
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
   * 获取 NAS 全库指纹；force=true 时强制重新拉取。
   */
  static async getFingerprints(client: FnHttpClient, force: boolean = false): Promise<Set<string>> {
    if (!force && GalleryAutoSyncNasIndex.isFresh(false)) {
      return new Set<string>(GalleryAutoSyncNasIndex.fingerprints);
    }
    if (GalleryAutoSyncNasIndex.loading) {
      return new Set<string>(GalleryAutoSyncNasIndex.fingerprints);
    }
    GalleryAutoSyncNasIndex.loading = true;
    try {
      const timeline = await client.getGalleryTimeline();
      if (!timeline.success || timeline.data === undefined) {
        hilog.warn(DOMAIN, TAG, 'timeline failed: %{public}s', timeline.message ?? '');
        return new Set<string>(GalleryAutoSyncNasIndex.fingerprints);
      }
      const items = await GalleryAutoSyncNasIndex.fetchAllTimelineItems(client, timeline.data);
      const fps = buildNasOfficialFingerprints(items);
      GalleryAutoSyncNasIndex.fingerprints = fps;
      GalleryAutoSyncNasIndex.cachedAt = Date.now();
      hilog.info(DOMAIN, TAG, 'nas index items=%{public}d fingerprints=%{public}d', items.length, fps.size);
      return new Set<string>(fps);
    } finally {
      GalleryAutoSyncNasIndex.loading = false;
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
    for (let i = 0; i < days.length; i++) {
      await GalleryAutoSyncNasIndex.fetchDayPages(client, days[i], out);
    }
    return out;
  }
}
