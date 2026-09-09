import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../../auth/AppSession';
import { GalleryListItem } from '../../model/FnApiTypes';
import { CategoryGalleryNavStore } from '../../album/CategoryGalleryNavStore';
import { nasUrl, pickThumb } from '../../album/GalleryAlbumCommon';
import { fnClampGridColumns } from '../../common/FnWindowBreakpoint';
import { categoryGalleryItemIdOf } from './CategoryGallerySelectionController';
import { CategoryGalleryListBlock } from './CategoryGalleryListModel';

export const CATEGORY_GALLERY_BACKGROUND_APPEND_BATCH_ITEMS: number = 240;
export const CATEGORY_GALLERY_STORE_SYNC_INTERVAL_MS: number = 96;
export const CATEGORY_GALLERY_RECENT_STREAM_DEFER_MS: number = 160;
export const CATEGORY_GALLERY_RECENT_STREAM_MIN_APPEND_DELTA: number = 288;
export const CATEGORY_GALLERY_RECENT_STREAM_MIN_APPLY_GAP_MS: number = 180;
export const CATEGORY_GALLERY_RECENT_STREAM_IDLE_RESUME_MS: number = 180;

const DOMAIN = 0xFF00;
const TAG = 'GalleryDiag';

export interface CategoryGalleryDataSyncHost {
  cgPageActive: boolean;
  pageSessionToken: number;
  pageSourceKind: string;
  pageCategoryKey: string;
  pageFolderPath: string;
  pageUseCreatedAtGrouping: boolean;
  baseUrl: string;
  title: string;
  heroImageUri: string;
  baseColumnsPerRow: number;
  columnsPerRow: number;
  flatItems: GalleryListItem[];
  totalCount: number;
  cgBackgroundLoading: boolean;
  listBlocks: CategoryGalleryListBlock[];
  cgObservedStoreVersion: number;
  cgPendingStoreSync: boolean;
  cgLastSnapshotApplyAtMs: number;
  cgSlideGestureActive: boolean;
  cgThumbLoadingPaused: boolean;
  cgDeferredSnapshotApplyTimer: number;
  cgStorePollTimer: number;
  cgDeferredBackgroundLoadTimer: number;
  resolvedColumns(): number;
  rebuildByFlatItems(): void;
  recycleThumbCache(aggressive: boolean): void;
  isRecentAddedStreamingMode(): boolean;
}

export function categoryGalleryAppendItemsDeduped(
  seenIds: Set<string>,
  incoming: GalleryListItem[],
  pendingAppendItems: GalleryListItem[]
): GalleryListItem[] {
  const appendItems: GalleryListItem[] = [];
  for (let i = 0; i < incoming.length; i++) {
    const one = incoming[i];
    const id = categoryGalleryItemIdOf(one);
    if (id.length > 0 && seenIds.has(id)) {
      continue;
    }
    if (id.length > 0) {
      seenIds.add(id);
    }
    appendItems.push(one);
  }
  if (appendItems.length <= 0) {
    return pendingAppendItems;
  }
  return pendingAppendItems.concat(appendItems);
}

export function categoryGalleryApplyNavStoreSnapshot(host: CategoryGalleryDataSyncHost): void {
  if (!host.cgPageActive) {
    return;
  }
  categoryGalleryClearDeferredSnapshotApplyTimer(host);
  host.pageSessionToken = CategoryGalleryNavStore.sessionToken;
  host.pageSourceKind = CategoryGalleryNavStore.sourceKind;
  host.pageCategoryKey = CategoryGalleryNavStore.categoryKey;
  host.pageFolderPath = CategoryGalleryNavStore.folderPath;
  host.pageUseCreatedAtGrouping = CategoryGalleryNavStore.useCreatedAtGrouping;
  host.baseUrl = CategoryGalleryNavStore.baseUrl;
  host.title = CategoryGalleryNavStore.title;
  host.heroImageUri = CategoryGalleryNavStore.heroImageUri;
  host.baseColumnsPerRow = fnClampGridColumns(CategoryGalleryNavStore.columnsPerRow);
  host.columnsPerRow = host.resolvedColumns();
  host.flatItems = CategoryGalleryNavStore.items.slice();
  host.totalCount = Math.max(CategoryGalleryNavStore.expectedTotalCount, host.flatItems.length);
  host.cgBackgroundLoading = CategoryGalleryNavStore.backgroundLoading;
  host.rebuildByFlatItems();
  host.cgObservedStoreVersion = CategoryGalleryNavStore.version;
  host.cgPendingStoreSync = false;
  host.cgLastSnapshotApplyAtMs = Date.now();
  if (host.isRecentAddedStreamingMode()) {
    hilog.warn(
      DOMAIN,
      TAG,
      'applyNavStoreSnapshot title=%{public}s flatItems=%{public}d totalCount=%{public}d storeItems=%{public}d listBlocks=%{public}d storeVersion=%{public}d backgroundLoading=%{public}s',
      host.title,
      host.flatItems.length,
      host.totalCount,
      CategoryGalleryNavStore.items.length,
      host.listBlocks.length,
      CategoryGalleryNavStore.version,
      host.cgBackgroundLoading ? 'true' : 'false'
    );
  }
  if (host.heroImageUri.length === 0 && host.flatItems.length > 0) {
    host.heroImageUri = nasUrl(host.baseUrl, pickThumb(host.flatItems[0]));
  }
}

export async function categoryGalleryLoadRemainingItems(
  host: CategoryGalleryDataSyncHost,
  token: number
): Promise<void> {
  if (!host.cgPageActive || token !== host.pageSessionToken) {
    return;
  }
  const categoryKey = host.pageCategoryKey;
  const hasPrefetch = CategoryGalleryNavStore.hasPrefetchedRemainder();
  if (categoryKey.length === 0 && !hasPrefetch) {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    return;
  }
  CategoryGalleryNavStore.setBackgroundLoading(token, true);
  const seenIds: Set<string> = new Set<string>();
  for (let i = 0; i < host.flatItems.length; i++) {
    seenIds.add(categoryGalleryItemIdOf(host.flatItems[i]));
  }
  const pageSize = 200;
  let pendingAppendItems: GalleryListItem[] = [];
  const flushPendingAppendItems = (): void => {
    if (!host.cgPageActive || pendingAppendItems.length <= 0) {
      return;
    }
    CategoryGalleryNavStore.appendItems(token, pendingAppendItems);
    pendingAppendItems = [];
  };
  hilog.warn(
    DOMAIN,
    TAG,
    'loadRemaining start token=%{public}d key=%{public}s flat=%{public}d prefetched=%{public}d searchFetched=%{public}d expected=%{public}d',
    token,
    categoryKey,
    host.flatItems.length,
    CategoryGalleryNavStore.prefetchedRemainder.length,
    CategoryGalleryNavStore.searchFetchedCount,
    CategoryGalleryNavStore.expectedTotalCount
  );
  try {
    while (host.cgPageActive &&
      token === CategoryGalleryNavStore.currentToken() &&
      CategoryGalleryNavStore.hasPrefetchedRemainder()) {
      const batch = CategoryGalleryNavStore.takePrefetchedBatch(CATEGORY_GALLERY_BACKGROUND_APPEND_BATCH_ITEMS);
      if (batch.length <= 0) {
        break;
      }
      pendingAppendItems = categoryGalleryAppendItemsDeduped(seenIds, batch, pendingAppendItems);
      if (pendingAppendItems.length >= CATEGORY_GALLERY_BACKGROUND_APPEND_BATCH_ITEMS) {
        flushPendingAppendItems();
      }
    }
    flushPendingAppendItems();
    if (categoryKey.length === 0) {
      return;
    }
    let offset = Math.max(CategoryGalleryNavStore.searchFetchedCount, CategoryGalleryNavStore.items.length);
    while (host.cgPageActive && token === CategoryGalleryNavStore.currentToken()) {
      const res = await client.getCategoryPhotos(categoryKey, pageSize, offset);
      if (!host.cgPageActive || token !== CategoryGalleryNavStore.currentToken()) {
        break;
      }
      if (!res.success || res.data === undefined || res.data.length === 0) {
        hilog.warn(
          DOMAIN,
          TAG,
          'loadRemaining api stop key=%{public}s offset=%{public}d ok=%{public}s count=%{public}d msg=%{public}s',
          categoryKey,
          offset,
          res.success ? 'true' : 'false',
          res.data !== undefined ? res.data.length : 0,
          res.message ?? ''
        );
        break;
      }
      const incoming = res.data;
      pendingAppendItems = categoryGalleryAppendItemsDeduped(seenIds, incoming, pendingAppendItems);
      if (pendingAppendItems.length >= CATEGORY_GALLERY_BACKGROUND_APPEND_BATCH_ITEMS) {
        flushPendingAppendItems();
      }
      offset += incoming.length > 0 ? incoming.length : pageSize;
      if (incoming.length < pageSize) {
        break;
      }
    }
    flushPendingAppendItems();
    hilog.warn(
      DOMAIN,
      TAG,
      'loadRemaining done token=%{public}d total=%{public}d expected=%{public}d',
      token,
      CategoryGalleryNavStore.items.length,
      CategoryGalleryNavStore.expectedTotalCount
    );
  } finally {
    CategoryGalleryNavStore.setBackgroundLoading(token, false);
  }
}

export function categoryGalleryClearDeferredSnapshotApplyTimer(host: CategoryGalleryDataSyncHost): void {
  if (host.cgDeferredSnapshotApplyTimer >= 0) {
    clearTimeout(host.cgDeferredSnapshotApplyTimer);
    host.cgDeferredSnapshotApplyTimer = -1;
  }
}

export function categoryGalleryScheduleDeferredSnapshotApply(
  host: CategoryGalleryDataSyncHost,
  delayMs: number = CATEGORY_GALLERY_RECENT_STREAM_DEFER_MS
): void {
  if (!host.cgPageActive || !host.isRecentAddedStreamingMode()) {
    return;
  }
  categoryGalleryClearDeferredSnapshotApplyTimer(host);
  host.cgDeferredSnapshotApplyTimer = setTimeout((): void => {
    host.cgDeferredSnapshotApplyTimer = -1;
    if (!host.cgPageActive) {
      return;
    }
    if (host.cgSlideGestureActive || host.cgThumbLoadingPaused) {
      host.cgPendingStoreSync = true;
      categoryGalleryScheduleDeferredSnapshotApply(host, CATEGORY_GALLERY_RECENT_STREAM_DEFER_MS);
      return;
    }
    if (host.cgObservedStoreVersion === CategoryGalleryNavStore.version) {
      host.cgPendingStoreSync = false;
      return;
    }
    categoryGalleryApplyNavStoreSnapshot(host);
    if (!host.cgBackgroundLoading) {
      host.recycleThumbCache(false);
    }
  }, Math.max(48, Math.floor(delayMs)));
}

export function categoryGalleryStopStoreObserver(host: CategoryGalleryDataSyncHost): void {
  if (host.cgStorePollTimer >= 0) {
    clearInterval(host.cgStorePollTimer);
    host.cgStorePollTimer = -1;
  }
  host.cgPendingStoreSync = false;
}

export function categoryGalleryStartStoreObserver(host: CategoryGalleryDataSyncHost): void {
  if (!host.cgPageActive) {
    return;
  }
  categoryGalleryStopStoreObserver(host);
  host.cgStorePollTimer = setInterval((): void => {
    if (!host.cgPageActive) {
      return;
    }
    categoryGallerySyncFromNavStore(host);
  }, CATEGORY_GALLERY_STORE_SYNC_INTERVAL_MS);
}

export function categoryGallerySyncFromNavStore(host: CategoryGalleryDataSyncHost): void {
  if (!host.cgPageActive || host.pageSessionToken !== CategoryGalleryNavStore.sessionToken) {
    return;
  }
  if (host.cgObservedStoreVersion === CategoryGalleryNavStore.version) {
    return;
  }
  const recentAddedStreaming = host.isRecentAddedStreamingMode();
  const navStoreHasAppendItems = CategoryGalleryNavStore.items.length > host.flatItems.length;
  const allowAppendSyncWhilePaused = false;
  const appendDelta = Math.max(0, CategoryGalleryNavStore.items.length - host.flatItems.length);
  const applyGapMs = Date.now() - host.cgLastSnapshotApplyAtMs;
  const shouldCoalesceRecentAppend =
    recentAddedStreaming &&
    navStoreHasAppendItems &&
    CategoryGalleryNavStore.backgroundLoading &&
    (appendDelta < CATEGORY_GALLERY_RECENT_STREAM_MIN_APPEND_DELTA ||
      applyGapMs < CATEGORY_GALLERY_RECENT_STREAM_MIN_APPLY_GAP_MS);
  if (recentAddedStreaming) {
    hilog.warn(
      DOMAIN,
      TAG,
      'syncFromNavStore storeVersion=%{public}d observedVersion=%{public}d storeItems=%{public}d flatItems=%{public}d navStoreHasAppend=%{public}s paused=%{public}s slideActive=%{public}s allowAppendWhilePaused=%{public}s',
      CategoryGalleryNavStore.version,
      host.cgObservedStoreVersion,
      CategoryGalleryNavStore.items.length,
      host.flatItems.length,
      navStoreHasAppendItems ? 'true' : 'false',
      host.cgThumbLoadingPaused ? 'true' : 'false',
      host.cgSlideGestureActive ? 'true' : 'false',
      allowAppendSyncWhilePaused ? 'true' : 'false'
    );
  }
  if (host.cgSlideGestureActive || (host.cgThumbLoadingPaused && (!allowAppendSyncWhilePaused || !navStoreHasAppendItems))) {
    host.totalCount = Math.max(
      CategoryGalleryNavStore.expectedTotalCount,
      host.totalCount,
      host.flatItems.length,
      CategoryGalleryNavStore.items.length
    );
    host.cgBackgroundLoading = CategoryGalleryNavStore.backgroundLoading;
    host.cgPendingStoreSync = true;
    if (recentAddedStreaming) {
      categoryGalleryScheduleDeferredSnapshotApply(host);
      hilog.warn(
        DOMAIN,
        TAG,
        'syncDeferred totalCount=%{public}d backgroundLoading=%{public}s pending=%{public}s',
        host.totalCount,
        host.cgBackgroundLoading ? 'true' : 'false',
        host.cgPendingStoreSync ? 'true' : 'false'
      );
    }
    return;
  }
  if (shouldCoalesceRecentAppend) {
    host.totalCount = Math.max(
      CategoryGalleryNavStore.expectedTotalCount,
      host.totalCount,
      host.flatItems.length,
      CategoryGalleryNavStore.items.length
    );
    host.cgBackgroundLoading = CategoryGalleryNavStore.backgroundLoading;
    host.cgPendingStoreSync = true;
    categoryGalleryScheduleDeferredSnapshotApply(host);
    hilog.warn(
      DOMAIN,
      TAG,
      'syncCoalesced totalCount=%{public}d appendDelta=%{public}d applyGapMs=%{public}d pending=%{public}s',
      host.totalCount,
      appendDelta,
      applyGapMs,
      host.cgPendingStoreSync ? 'true' : 'false'
    );
    return;
  }
  categoryGalleryApplyNavStoreSnapshot(host);
  if (!host.cgBackgroundLoading) {
    host.recycleThumbCache(false);
  }
}
