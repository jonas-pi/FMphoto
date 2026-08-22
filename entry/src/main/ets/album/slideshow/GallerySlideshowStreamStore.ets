import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryGetListData, GalleryListItem } from '../../model/FnApiTypes';
import { AppSession } from '../../auth/AppSession';
import { FnHttpClient } from '../../network/FnHttpClient';
import { DATE_FEED_BATCH } from '../galleryAlbumTab/GalleryAlbumTabConstants';
import { fmtDayEnd, fmtDayStart, TimelineDayModel } from '../galleryAlbumTab/GalleryAlbumTabTypes';
import {
  buildGallerySlideshowTimelineIndex,
  GallerySlideshowTimelineIndex,
  locateSlideshowGlobalIndex
} from './GallerySlideshowTimelineIndex';
import { filterGallerySlideshowItems, gallerySlideshowStableItemKey, shuffleGallerySlideshowEntries } from './GallerySlideshowMedia';
import { loadSmartCategoryGalleryItems } from '../SmartCategoryMagicSearch';
import {
  GallerySlideshowConfig,
  GallerySlideshowPlaylistEntry,
  GallerySlideshowScope,
  GallerySlideshowScopeKind
} from './GallerySlideshowTypes';
import {
  slideshowLogAcceptSkip,
  slideshowLogPick,
  slideshowLogRandomMiss,
  slideshowLogResolve,
  slideshowLogResolveFail
} from './GallerySlideshowTrace';

const DOMAIN = 0xFF00;
const TAG = 'GallerySlideshow';

/** 启动时先解析的条数，保证秒开 */
export const GALLERY_SLIDESHOW_START_BATCH: number = 28;
/** 播放中提前补货的条数 */
export const GALLERY_SLIDESHOW_PREFETCH_BATCH: number = 16;
/** 剩余不足该值时触发补货 */
export const GALLERY_SLIDESHOW_PREFETCH_THRESHOLD: number = 5;
/** 单次随机去重最大尝试倍数（按「解析次数」计，不再一次性预占） */
const PICK_ATTEMPT_FACTOR: number = 14;
/** 记住已播 id，降低短期重复 */
const SEEN_KEY_CAP: number = 1200;
/** 并行解析上限 */
const RESOLVE_CONCURRENCY: number = 4;

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

function itemSeenKey(item: GalleryListItem): string {
  return gallerySlideshowStableItemKey(item);
}

function usedKeyOf(globalIdx: number): string {
  return `${globalIdx}`;
}

/** nextUnusedGlobalIndex 的返回值：viaCode 1=random 2=stride 0=none */
class SlideshowUnusedPick {
  globalIdx: number = -1;
  viaCode: number = 0;
}

export class GallerySlideshowStreamStore {
  private static active: boolean = false;
  private static scope: GallerySlideshowScope | null = null;
  private static config: GallerySlideshowConfig | null = null;
  private static index: GallerySlideshowTimelineIndex | null = null;
  private static seen: Set<string> = new Set();
  /** 字符串键，避免 ArkTS Set<number> 在部分机型上 has/add 不可靠 */
  private static usedGlobals: Set<string> = new Set();
  private static prefetching: boolean = false;
  /** SMART_CATEGORY：扁平结果缓存，按 globalIndex 直接取下标 */
  private static flatResolveItems: GalleryListItem[] = [];
  /** 按「天+页 offset」缓存，一次请求对准下标，避免从 0 连拉几百页 */
  private static dayPageCache: Map<string, GalleryListItem[]> = new Map();
  /** 同一页并发解析共用一个请求 */
  private static dayPageInflight: Map<string, Promise<GalleryListItem[]>> = new Map();

  static isActive(): boolean {
    return GallerySlideshowStreamStore.active;
  }

  static getLibraryTotalCount(): number {
    const index = GallerySlideshowStreamStore.index;
    if (index === null) {
      return 0;
    }
    return index.totalCount;
  }

  static clear(): void {
    GallerySlideshowStreamStore.active = false;
    GallerySlideshowStreamStore.scope = null;
    GallerySlideshowStreamStore.config = null;
    GallerySlideshowStreamStore.index = null;
    GallerySlideshowStreamStore.seen.clear();
    GallerySlideshowStreamStore.usedGlobals.clear();
    GallerySlideshowStreamStore.prefetching = false;
    GallerySlideshowStreamStore.flatResolveItems = [];
    GallerySlideshowStreamStore.dayPageCache.clear();
    GallerySlideshowStreamStore.dayPageInflight.clear();
  }

  static rememberEntries(entries: GallerySlideshowPlaylistEntry[]): void {
    const items: GalleryListItem[] = [];
    for (let i = 0; i < entries.length; i++) {
      items.push(entries[i].item);
    }
    GallerySlideshowStreamStore.rememberItems(items);
  }

  static rememberItems(items: GalleryListItem[]): void {
    for (let i = 0; i < items.length; i++) {
      const key = itemSeenKey(items[i]);
      if (key.length === 0) {
        continue;
      }
      GallerySlideshowStreamStore.seen.add(key);
    }
    GallerySlideshowStreamStore.trimSeen();
  }

  private static trimSeen(): void {
    if (GallerySlideshowStreamStore.seen.size <= SEEN_KEY_CAP) {
      return;
    }
    const drop = GallerySlideshowStreamStore.seen.size - SEEN_KEY_CAP;
    const iter = GallerySlideshowStreamStore.seen.values();
    for (let i = 0; i < drop; i++) {
      const next = iter.next();
      if (next.done) {
        break;
      }
      GallerySlideshowStreamStore.seen.delete(next.value);
    }
  }

  static begin(
    scope: GallerySlideshowScope,
    config: GallerySlideshowConfig,
    index: GallerySlideshowTimelineIndex
  ): void {
    GallerySlideshowStreamStore.active = true;
    GallerySlideshowStreamStore.scope = scope;
    GallerySlideshowStreamStore.config = config;
    GallerySlideshowStreamStore.index = index;
    GallerySlideshowStreamStore.seen.clear();
    GallerySlideshowStreamStore.usedGlobals.clear();
    GallerySlideshowStreamStore.prefetching = false;
    GallerySlideshowStreamStore.dayPageCache.clear();
    GallerySlideshowStreamStore.dayPageInflight.clear();
    hilog.info(DOMAIN, TAG, 'begin total=%{public}d', index.totalCount);
  }

  private static personId(): string {
    const scope = GallerySlideshowStreamStore.scope;
    if (scope === null || scope.kind !== GallerySlideshowScopeKind.PERSON_ALBUM) {
      return '';
    }
    return scope.personId !== undefined ? scope.personId.trim() : '';
  }

  private static isSmartCategoryScope(): boolean {
    const scope = GallerySlideshowStreamStore.scope;
    return scope !== null && scope.kind === GallerySlideshowScopeKind.SMART_CATEGORY;
  }

  private static buildFlatTimelineIndex(totalCount: number): GallerySlideshowTimelineIndex {
    const out = new GallerySlideshowTimelineIndex();
    out.totalCount = Math.max(0, Math.floor(totalCount));
    return out;
  }

  private static usedHas(globalIdx: number): boolean {
    return GallerySlideshowStreamStore.usedGlobals.has(usedKeyOf(globalIdx));
  }

  private static usedAdd(globalIdx: number): void {
    GallerySlideshowStreamStore.usedGlobals.add(usedKeyOf(globalIdx));
  }

  private static dayCacheKey(day: TimelineDayModel): string {
    return `${GallerySlideshowStreamStore.personId()}|${day.year}-${day.month}-${day.day}`;
  }

  private static dayPageSlotKey(day: TimelineDayModel, pageOff: number): string {
    return `${GallerySlideshowStreamStore.dayCacheKey(day)}|${pageOff}`;
  }

  private static async fetchDayPage(
    client: FnHttpClient,
    day: TimelineDayModel,
    offset: number
  ): Promise<GalleryListItem[]> {
    const st = fmtDayStart(day.year, day.month, day.day);
    const et = fmtDayEnd(day.year, day.month, day.day);
    const pid = GallerySlideshowStreamStore.personId();
    const res = pid.length > 0
      ? await client.getAiPersonPhotoList(pid, st, et, DATE_FEED_BATCH, offset)
      : await client.getGalleryList(st, et, DATE_FEED_BATCH, offset, 'index');
    if (!res.success || res.data === undefined) {
      return [];
    }
    return listFromData(res.data as GalleryGetListData);
  }

  /** 按页 offset 取一天中的一批，并发相同页只打一次网 */
  private static loadDayPage(
    client: FnHttpClient,
    day: TimelineDayModel,
    pageOff: number
  ): Promise<GalleryListItem[]> {
    const slotKey = GallerySlideshowStreamStore.dayPageSlotKey(day, pageOff);
    const cached = GallerySlideshowStreamStore.dayPageCache.get(slotKey);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    const pending = GallerySlideshowStreamStore.dayPageInflight.get(slotKey);
    if (pending !== undefined) {
      return pending;
    }
    const task = GallerySlideshowStreamStore.fetchDayPage(client, day, pageOff)
      .then((page: GalleryListItem[]): GalleryListItem[] => {
        GallerySlideshowStreamStore.dayPageCache.set(slotKey, page);
        GallerySlideshowStreamStore.dayPageInflight.delete(slotKey);
        return page;
      });
    GallerySlideshowStreamStore.dayPageInflight.set(slotKey, task);
    return task;
  }

  private static async resolveAtGlobalIndex(
    client: FnHttpClient,
    globalIdx: number
  ): Promise<GalleryListItem | null> {
    if (GallerySlideshowStreamStore.isSmartCategoryScope()) {
      const flat = GallerySlideshowStreamStore.flatResolveItems;
      if (globalIdx < 0 || globalIdx >= flat.length) {
        slideshowLogResolveFail(globalIdx, 'flat_oob');
        return null;
      }
      const item = flat[globalIdx];
      slideshowLogResolve(globalIdx, 'flat', globalIdx, itemSeenKey(item), true, flat.length);
      return item;
    }
    const index = GallerySlideshowStreamStore.index;
    if (index === null) {
      slideshowLogResolveFail(globalIdx, 'no_index');
      return null;
    }
    const located = locateSlideshowGlobalIndex(index, globalIdx);
    if (located === null) {
      slideshowLogResolveFail(globalIdx, 'locate');
      return null;
    }
    const day = index.days[located.dayIdx];
    const need = located.dayOffset;
    if (need < 0) {
      slideshowLogResolveFail(globalIdx, 'neg_off');
      return null;
    }
    const pageOff = Math.floor(need / DATE_FEED_BATCH) * DATE_FEED_BATCH;
    const slotKey = GallerySlideshowStreamStore.dayPageSlotKey(day, pageOff);
    const cacheHit = GallerySlideshowStreamStore.dayPageCache.get(slotKey) !== undefined;
    const page = await GallerySlideshowStreamStore.loadDayPage(client, day, pageOff);
    const local = need - pageOff;
    if (local >= page.length) {
      slideshowLogResolveFail(globalIdx, `day_off_${need}_got_${page.length}_at_${pageOff}`);
      return null;
    }
    const item = page[local];
    slideshowLogResolve(
      globalIdx,
      `${day.year}-${day.month}-${day.day}`,
      need,
      itemSeenKey(item),
      cacheHit,
      page.length
    );
    return item;
  }

  /** 返回空串表示可入队；否则为跳过原因 */
  private static skipReason(item: GalleryListItem, config: GallerySlideshowConfig): string {
    const filtered = filterGallerySlideshowItems([item], config);
    if (filtered.length === 0) {
      return 'filter';
    }
    const key = itemSeenKey(item);
    if (key.length > 0 && GallerySlideshowStreamStore.seen.has(key)) {
      return 'seen';
    }
    return '';
  }

  private static acceptItem(item: GalleryListItem, config: GallerySlideshowConfig): boolean {
    const reason = GallerySlideshowStreamStore.skipReason(item, config);
    if (reason.length > 0) {
      return false;
    }
    const key = itemSeenKey(item);
    if (key.length > 0) {
      GallerySlideshowStreamStore.seen.add(key);
      GallerySlideshowStreamStore.trimSeen();
    }
    return true;
  }

  /**
   * 取一个未用全局下标。先随机；连续未命中再用质数步长探测，
   * 禁止从 0 线性扫描（那会让标题变成 1、2、3… 顺延）。
   */
  private static nextUnusedGlobalIndex(): SlideshowUnusedPick {
    const out = new SlideshowUnusedPick();
    const index = GallerySlideshowStreamStore.index;
    if (index === null || index.totalCount <= 0) {
      return out;
    }
    const total = index.totalCount;
    if (GallerySlideshowStreamStore.usedGlobals.size >= total) {
      return out;
    }
    for (let i = 0; i < 48; i++) {
      const n = Math.floor(Math.random() * total);
      if (!GallerySlideshowStreamStore.usedHas(n)) {
        out.globalIdx = n;
        out.viaCode = 1;
        return out;
      }
    }
    slideshowLogRandomMiss(GallerySlideshowStreamStore.usedGlobals.size, total);
    // 从随机起点扫一遍，避免固定从 0 开始导致标题 1、2、3 顺延
    const start = Math.floor(Math.random() * total);
    for (let i = 0; i < total; i++) {
      let g = start + i;
      if (g >= total) {
        g = g - total;
      }
      if (!GallerySlideshowStreamStore.usedHas(g)) {
        out.globalIdx = g;
        out.viaCode = 2;
        return out;
      }
    }
    return out;
  }

  static async pickRandomBatch(count: number): Promise<GallerySlideshowPlaylistEntry[]> {
    const client = AppSession.getClient();
    const config = GallerySlideshowStreamStore.config;
    const index = GallerySlideshowStreamStore.index;
    if (client === null || config === null || index === null || index.totalCount <= 0) {
      return [];
    }
    const target = Math.max(1, Math.floor(count));
    const maxAttempts = Math.max(target * PICK_ATTEMPT_FACTOR, PICK_ATTEMPT_FACTOR);
    const out: GallerySlideshowPlaylistEntry[] = [];
    let attempts = 0;
    while (out.length < target && attempts < maxAttempts) {
      const chunk: number[] = [];
      while (chunk.length < RESOLVE_CONCURRENCY && out.length + chunk.length < target && attempts < maxAttempts) {
        const pick = GallerySlideshowStreamStore.nextUnusedGlobalIndex();
        const g = pick.globalIdx;
        const viaCode = pick.viaCode;
        attempts++;
        if (g < 0) {
          break;
        }
        GallerySlideshowStreamStore.usedAdd(g);
        chunk.push(g);
        const via = viaCode === 1 ? 'random' : (viaCode === 2 ? 'stride' : 'none');
        slideshowLogPick(via, g, GallerySlideshowStreamStore.usedGlobals.size, index.totalCount);
      }
      if (chunk.length === 0) {
        break;
      }
      const tasks: Promise<GalleryListItem | null>[] = [];
      for (let i = 0; i < chunk.length; i++) {
        tasks.push(GallerySlideshowStreamStore.resolveAtGlobalIndex(client, chunk[i]));
      }
      const resolved = await Promise.all(tasks);
      for (let i = 0; i < resolved.length; i++) {
        const item = resolved[i];
        const globalIdx = chunk[i];
        if (item === null) {
          continue;
        }
        const reason = GallerySlideshowStreamStore.skipReason(item, config);
        if (reason.length > 0) {
          slideshowLogAcceptSkip(globalIdx, itemSeenKey(item), reason);
          continue;
        }
        if (!GallerySlideshowStreamStore.acceptItem(item, config)) {
          continue;
        }
        out.push(new GallerySlideshowPlaylistEntry(item, globalIdx));
        if (out.length >= target) {
          break;
        }
      }
    }
    hilog.info(DOMAIN, TAG, 'pickRandomBatch want=%{public}d got=%{public}d attempts=%{public}d used=%{public}d',
      target, out.length, attempts, GallerySlideshowStreamStore.usedGlobals.size);
    return out;
  }

  static async loadTimelineIndex(
    scope: GallerySlideshowScope,
    preloadedItems?: GalleryListItem[]
  ): Promise<GallerySlideshowTimelineIndex | null> {
    const client = AppSession.getClient();
    if (client === null) {
      return null;
    }
    if (scope.kind === GallerySlideshowScopeKind.SMART_CATEGORY) {
      const keyword = scope.smartCategoryKeyword !== undefined ? scope.smartCategoryKeyword.trim() : '';
      if (keyword.length === 0) {
        return null;
      }
      let items: GalleryListItem[] = [];
      if (preloadedItems !== undefined && preloadedItems.length > 0) {
        items = preloadedItems.slice();
      } else {
        const loaded = await loadSmartCategoryGalleryItems(client, keyword);
        if (loaded.items.length === 0) {
          return null;
        }
        items = loaded.items;
      }
      GallerySlideshowStreamStore.flatResolveItems = items;
      return GallerySlideshowStreamStore.buildFlatTimelineIndex(items.length);
    }
    if (scope.kind === GallerySlideshowScopeKind.PERSON_ALBUM) {
      const personId = scope.personId !== undefined ? scope.personId.trim() : '';
      if (personId.length === 0) {
        return null;
      }
      const timeline = await client.getAiPersonPhotoTimeline(personId);
      if (!timeline.success || timeline.data === undefined) {
        return null;
      }
      return buildGallerySlideshowTimelineIndex(timeline.data);
    }
    const timeline = await client.getGalleryTimeline();
    if (!timeline.success || timeline.data === undefined) {
      return null;
    }
    return buildGallerySlideshowTimelineIndex(timeline.data);
  }

  static async buildStartPlaylist(): Promise<GallerySlideshowPlaylistEntry[]> {
    const batch = await GallerySlideshowStreamStore.pickRandomBatch(GALLERY_SLIDESHOW_START_BATCH);
    return shuffleGallerySlideshowEntries(batch);
  }

  static shouldPrefetch(remainingAhead: number): boolean {
    return GallerySlideshowStreamStore.active &&
      !GallerySlideshowStreamStore.prefetching &&
      remainingAhead <= GALLERY_SLIDESHOW_PREFETCH_THRESHOLD;
  }

  static async prefetchAppend(
    append: (entries: GallerySlideshowPlaylistEntry[]) => void
  ): Promise<void> {
    if (!GallerySlideshowStreamStore.active || GallerySlideshowStreamStore.prefetching) {
      return;
    }
    GallerySlideshowStreamStore.prefetching = true;
    try {
      const batch = await GallerySlideshowStreamStore.pickRandomBatch(GALLERY_SLIDESHOW_PREFETCH_BATCH);
      if (batch.length > 0) {
        append(shuffleGallerySlideshowEntries(batch));
        hilog.info(DOMAIN, TAG, 'prefetch append=%{public}d', batch.length);
      } else {
        hilog.warn(DOMAIN, TAG, 'prefetch empty used=%{public}d total=%{public}d',
          GallerySlideshowStreamStore.usedGlobals.size, GallerySlideshowStreamStore.getLibraryTotalCount());
      }
    } finally {
      GallerySlideshowStreamStore.prefetching = false;
    }
  }
}
