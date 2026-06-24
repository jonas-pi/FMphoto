import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryGetListData, GalleryListItem, GalleryTimelineData } from '../../model/FnApiTypes';
import { AppSession } from '../../auth/AppSession';
import { FnHttpClient } from '../../network/FnHttpClient';
import { fmtDayEnd, fmtDayStart } from '../galleryAlbumTab/GalleryAlbumTabTypes';
import {
  buildGallerySlideshowTimelineIndex,
  GallerySlideshowTimelineIndex,
  locateSlideshowGlobalIndex
} from './GallerySlideshowTimelineIndex';
import { filterGallerySlideshowItems, shuffleGallerySlideshowEntries } from './GallerySlideshowMedia';
import { loadSmartCategoryGalleryItems } from '../SmartCategoryMagicSearch';
import {
  GallerySlideshowConfig,
  GallerySlideshowPlaylistEntry,
  GallerySlideshowScope,
  GallerySlideshowScopeKind
} from './GallerySlideshowTypes';

const DOMAIN = 0xFF00;
const TAG = 'GallerySlideshow';

/** 启动时先解析的条数，保证秒开 */
export const GALLERY_SLIDESHOW_START_BATCH: number = 28;
/** 播放中提前补货的条数 */
export const GALLERY_SLIDESHOW_PREFETCH_BATCH: number = 16;
/** 剩余不足该值时触发补货 */
export const GALLERY_SLIDESHOW_PREFETCH_THRESHOLD: number = 5;
/** 单次随机去重最大尝试倍数 */
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
  const norm = (v: string | number | undefined | null): string => {
    if (v === undefined || v === null) {
      return '';
    }
    return String(v).trim();
  };
  const uuid = norm(item.photoUUID);
  if (uuid.length > 0) {
    return `u:${uuid}`;
  }
  const id = norm(item.id);
  if (id.length > 0) {
    return `i:${id}`;
  }
  const path = norm(item.path);
  if (path.length > 0) {
    return `p:${path}`;
  }
  return '';
}

export class GallerySlideshowStreamStore {
  private static active: boolean = false;
  private static scope: GallerySlideshowScope | null = null;
  private static config: GallerySlideshowConfig | null = null;
  private static index: GallerySlideshowTimelineIndex | null = null;
  private static seen: Set<string> = new Set();
  private static prefetching: boolean = false;
  /** SMART_CATEGORY：扁平结果缓存，按 globalIndex 直接取下标 */
  private static flatResolveItems: GalleryListItem[] = [];

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
    GallerySlideshowStreamStore.prefetching = false;
    GallerySlideshowStreamStore.flatResolveItems = [];
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
    GallerySlideshowStreamStore.prefetching = false;
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

  private static async resolveAtGlobalIndex(
    client: FnHttpClient,
    globalIdx: number
  ): Promise<GalleryListItem | null> {
    if (GallerySlideshowStreamStore.isSmartCategoryScope()) {
      const flat = GallerySlideshowStreamStore.flatResolveItems;
      if (globalIdx < 0 || globalIdx >= flat.length) {
        return null;
      }
      return flat[globalIdx];
    }
    const index = GallerySlideshowStreamStore.index;
    if (index === null) {
      return null;
    }
    const located = locateSlideshowGlobalIndex(index, globalIdx);
    if (located === null) {
      return null;
    }
    const day = index.days[located.dayIdx];
    const st = fmtDayStart(day.year, day.month, day.day);
    const et = fmtDayEnd(day.year, day.month, day.day);
    const pid = GallerySlideshowStreamStore.personId();
    const res = pid.length > 0
      ? await client.getAiPersonPhotoList(pid, st, et, 1, located.dayOffset)
      : await client.getGalleryList(st, et, 1, located.dayOffset);
    if (!res.success || res.data === undefined) {
      return null;
    }
    const list = listFromData(res.data as GalleryGetListData);
    return list.length > 0 ? list[0] : null;
  }

  private static acceptItem(item: GalleryListItem, config: GallerySlideshowConfig): boolean {
    const filtered = filterGallerySlideshowItems([item], config);
    if (filtered.length === 0) {
      return false;
    }
    const key = itemSeenKey(item);
    if (key.length > 0 && GallerySlideshowStreamStore.seen.has(key)) {
      return false;
    }
    if (key.length > 0) {
      GallerySlideshowStreamStore.seen.add(key);
      GallerySlideshowStreamStore.trimSeen();
    }
    return true;
  }

  private static randomGlobalIndex(): number {
    const index = GallerySlideshowStreamStore.index;
    if (index === null || index.totalCount <= 0) {
      return 0;
    }
    return Math.floor(Math.random() * index.totalCount);
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
    const candidates: number[] = [];
    for (let i = 0; i < maxAttempts; i++) {
      candidates.push(GallerySlideshowStreamStore.randomGlobalIndex());
    }

    const out: GallerySlideshowPlaylistEntry[] = [];
    let cursor = 0;
    while (out.length < target && cursor < candidates.length) {
      const chunk: number[] = [];
      while (chunk.length < RESOLVE_CONCURRENCY && cursor < candidates.length && out.length < target) {
        chunk.push(candidates[cursor]);
        cursor++;
      }
      const tasks: Promise<GalleryListItem | null>[] = [];
      for (let i = 0; i < chunk.length; i++) {
        tasks.push(GallerySlideshowStreamStore.resolveAtGlobalIndex(client, chunk[i]));
      }
      const resolved = await Promise.all(tasks);
      for (let i = 0; i < resolved.length; i++) {
        const item = resolved[i];
        if (item === null) {
          continue;
        }
        if (!GallerySlideshowStreamStore.acceptItem(item, config)) {
          continue;
        }
        out.push(new GallerySlideshowPlaylistEntry(item, chunk[i]));
        if (out.length >= target) {
          break;
        }
      }
    }
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
      }
    } finally {
      GallerySlideshowStreamStore.prefetching = false;
    }
  }
}
