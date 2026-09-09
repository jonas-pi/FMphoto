import { GalleryHomeTimelineCache } from '../GalleryHomeTimelineCache';
import { gallerySetAlbumBackHandler } from '../GalleryAlbumHardwareBack';
import { GalleryTimelineRefreshStore } from '../GalleryTimelineRefreshStore';
import { trimThumbPixCacheForList } from '../GalleryAlbumCommon';
import { playGalleryEnterSelectionHaptic } from '../GallerySelectionHaptic';
import { GalleryAlbumCommands } from './GalleryAlbumCommands';
import { GALLERY_BOOTSTRAP_DEBOUNCE_MS } from './GalleryAlbumTabConstants';

export interface GalleryAlbumLifecycleHost {
  baseUrl: string;
  homeSurface: string;
  inSearchMode: boolean;
  inCategoryMode: boolean;
  inSmartCategoryMode: boolean;
  inPersonMode: boolean;
  rootSurfaceSwitchAnimating: boolean;
  timelineReleaseAwaitVisibleCallback: boolean;
  lastHomeSurface: string;
  personOpening: boolean;
  categoryOpening: boolean;
  recentOpening: boolean;
  collectOpening: boolean;
  isDraggingOrFling: boolean;
  pumpEpoch: number;
  bootstrapDebounceTimer: number;
  galleryTimelineRefreshing: boolean;
  gallerySelectionMode: boolean;
  loadGen: number;
  currentThumbHeavyItemCount(): number;
  onSearchModeVisibilityChange(hiddenBottomNav: boolean): void;
  notifyHomeBottomDockVisibility(): void;
  notifySelectionDockStateChange(): void;
  syncHomeSurface(animate: boolean): void;
  refreshRootPhotosScrollTitle(): void;
  ensureAlbumsHomeSupplementaryData(): void;
  clearRootSurfaceSwitchTimer(): void;
  resetRootSurfaceSwitchTransforms(): void;
  dismissMoreMenu(): void;
  invalidateNavigationGuard(): void;
  tryConsumeSurfaceBack(): boolean;
  setGallerySelectionModeState(value: boolean): void;
  commands: GalleryAlbumCommands;
}

export function galleryAlbumOnEpochChange(host: GalleryAlbumLifecycleHost): void {
  setTimeout((): void => {
    galleryAlbumRequestBootstrap(host, false);
  }, 0);
}

export function galleryAlbumOnPageShowSignal(host: GalleryAlbumLifecycleHost): void {
  host.commands.onTabVisibleAgain();
  host.refreshRootPhotosScrollTitle();
  host.ensureAlbumsHomeSupplementaryData();
}

function tryRestoreMainTimelineSnapshot(host: GalleryAlbumLifecycleHost): boolean {
  if (host.inSearchMode || host.inCategoryMode || host.inSmartCategoryMode || host.inPersonMode) {
    return false;
  }
  const snap = GalleryHomeTimelineCache.tryTakeRestore(host.baseUrl, GalleryTimelineRefreshStore.version);
  if (snap === null) {
    return false;
  }
  host.commands.applyMainTimelineCacheSnapshot(snap);
  host.loadGen++;
  host.commands.rebuildFlow();
  setTimeout((): void => {
    host.commands.requestVisibleLoadImmediate();
  }, 0);
  return true;
}

export function galleryAlbumAboutToAppear(host: GalleryAlbumLifecycleHost): void {
  host.lastHomeSurface = host.homeSurface;
  host.personOpening = false;
  host.categoryOpening = false;
  host.recentOpening = false;
  host.collectOpening = false;
  host.syncHomeSurface(false);
  host.notifyHomeBottomDockVisibility();
  host.notifySelectionDockStateChange();
  host.refreshRootPhotosScrollTitle();
  host.ensureAlbumsHomeSupplementaryData();
  host.timelineReleaseAwaitVisibleCallback = false;
  gallerySetAlbumBackHandler((): boolean => host.tryConsumeSurfaceBack());
  setTimeout((): void => {
    if (tryRestoreMainTimelineSnapshot(host)) {
      return;
    }
    galleryAlbumRequestBootstrap(host, false);
  }, 0);
}

export function galleryAlbumAboutToDisappear(host: GalleryAlbumLifecycleHost): void {
  host.clearRootSurfaceSwitchTimer();
  host.rootSurfaceSwitchAnimating = false;
  host.resetRootSurfaceSwitchTransforms();
  host.onSearchModeVisibilityChange(false);
  host.dismissMoreMenu();
  host.notifySelectionDockStateChange();
  host.commands.cancelListSettledTimer();
  host.isDraggingOrFling = false;
  host.timelineReleaseAwaitVisibleCallback = false;
  host.invalidateNavigationGuard();
  host.pumpEpoch++;
  host.commands.refreshVisualPlaceholderMode();
  gallerySetAlbumBackHandler(null);
  const snap = host.commands.buildMainTimelineCacheSnapshot();
  if (snap !== null) {
    GalleryHomeTimelineCache.save(host.baseUrl, snap);
  }
  trimThumbPixCacheForList(host.currentThumbHeavyItemCount(), true);
}

export function galleryAlbumOnPageShow(host: GalleryAlbumLifecycleHost): void {
  host.commands.onTabVisibleAgain();
}

export function galleryAlbumClearBootstrapDebounceTimer(host: GalleryAlbumLifecycleHost): void {
  if (host.bootstrapDebounceTimer >= 0) {
    try {
      clearTimeout(host.bootstrapDebounceTimer);
    } catch (_e) {
    }
    host.bootstrapDebounceTimer = -1;
  }
}

export function galleryAlbumRequestBootstrap(host: GalleryAlbumLifecycleHost, debounced: boolean): void {
  galleryAlbumClearBootstrapDebounceTimer(host);
  if (debounced) {
    host.bootstrapDebounceTimer = setTimeout((): void => {
      host.bootstrapDebounceTimer = -1;
      void host.commands.bootstrap();
    }, GALLERY_BOOTSTRAP_DEBOUNCE_MS);
    return;
  }
  void host.commands.bootstrap();
}

export function galleryAlbumEnterGallerySelectionModeFromToolbar(host: GalleryAlbumLifecycleHost): void {
  if (host.gallerySelectionMode) {
    return;
  }
  playGalleryEnterSelectionHaptic();
  host.setGallerySelectionModeState(true);
  host.galleryTimelineRefreshing = false;
  host.commands.setGallerySelectedIds([]);
}
