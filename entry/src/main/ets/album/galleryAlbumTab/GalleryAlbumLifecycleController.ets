import { GalleryHomeTimelineCache } from '../GalleryHomeTimelineCache';
import { gallerySetAlbumBackHandler } from '../GalleryAlbumHardwareBack';
import { GalleryTimelineRefreshStore } from '../GalleryTimelineRefreshStore';
import { trimThumbPixCacheForList } from '../GalleryAlbumCommon';
import { playGalleryEnterSelectionHaptic } from '../GallerySelectionHaptic';
import { galleryAlbumSetGallerySelectedIdsState } from './GalleryAlbumSelectionSupport';
import {
  galleryAlbumApplyMainTimelineCacheSnapshot,
  galleryAlbumBuildMainTimelineCacheSnapshot
} from './GalleryAlbumCacheSnapshot';
import {
  GalleryAlbumLoadOrchestratorHost,
  galleryAlbumBootstrap,
  galleryAlbumOnTabVisibleAgain,
  galleryAlbumPumpLoad
} from './GalleryAlbumLoadOrchestrator';
import { galleryAlbumRebuildFlow } from './GalleryAlbumFlowLogic';
import { GalleryAlbumVisibleLoadHost } from './GalleryAlbumVisibleLoadController';
import { SelectionGestureControllerHost } from './SelectionGestureController';
import {
  TimelineGestureControllerHost,
  timelineGestureCancelListSettledTimer,
  timelineGestureRefreshVisualPlaceholderMode
} from './TimelineGestureController';
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
  asSelectionGestureHost(): SelectionGestureControllerHost;
  asTimelineGestureHost(): TimelineGestureControllerHost;
  asLoadOrchestratorHost(): GalleryAlbumLoadOrchestratorHost;
  asVisibleLoadHost(): GalleryAlbumVisibleLoadHost;
}

export function galleryAlbumOnEpochChange(host: GalleryAlbumLifecycleHost): void {
  setTimeout((): void => {
    galleryAlbumRequestBootstrap(host, false);
  }, 0);
}

export function galleryAlbumOnPageShowSignal(host: GalleryAlbumLifecycleHost): void {
  galleryAlbumOnTabVisibleAgain(host.asLoadOrchestratorHost());
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
  galleryAlbumApplyMainTimelineCacheSnapshot(host.asLoadOrchestratorHost(), snap);
  host.loadGen++;
  galleryAlbumRebuildFlow(host.asVisibleLoadHost());
  setTimeout((): void => {
    galleryAlbumPumpLoad(host.asLoadOrchestratorHost());
  }, 0);
  return true;
}

export function galleryAlbumAboutToAppear(host: GalleryAlbumLifecycleHost): void {
  host.lastHomeSurface = host.homeSurface;
  host.onSearchModeVisibilityChange(host.inSearchMode);
  host.notifySelectionDockStateChange();
  host.syncHomeSurface(false);
  host.refreshRootPhotosScrollTitle();
  host.ensureAlbumsHomeSupplementaryData();
  host.personOpening = false;
  host.categoryOpening = false;
  host.recentOpening = false;
  host.collectOpening = false;
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
  timelineGestureCancelListSettledTimer(host.asTimelineGestureHost());
  host.isDraggingOrFling = false;
  host.timelineReleaseAwaitVisibleCallback = false;
  host.invalidateNavigationGuard();
  host.pumpEpoch++;
  timelineGestureRefreshVisualPlaceholderMode(host.asTimelineGestureHost());
  gallerySetAlbumBackHandler(null);
  const snap = galleryAlbumBuildMainTimelineCacheSnapshot(host.asLoadOrchestratorHost());
  if (snap !== null) {
    GalleryHomeTimelineCache.save(host.baseUrl, snap);
  }
  trimThumbPixCacheForList(host.currentThumbHeavyItemCount(), true);
}

export function galleryAlbumOnPageShow(host: GalleryAlbumLifecycleHost): void {
  galleryAlbumOnTabVisibleAgain(host.asLoadOrchestratorHost());
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
      void galleryAlbumBootstrap(host.asLoadOrchestratorHost());
    }, GALLERY_BOOTSTRAP_DEBOUNCE_MS);
    return;
  }
  void galleryAlbumBootstrap(host.asLoadOrchestratorHost());
}

export function galleryAlbumEnterGallerySelectionModeFromToolbar(host: GalleryAlbumLifecycleHost): void {
  if (host.gallerySelectionMode) {
    return;
  }
  playGalleryEnterSelectionHaptic();
  host.setGallerySelectionModeState(true);
  host.galleryTimelineRefreshing = false;
  galleryAlbumSetGallerySelectedIdsState(host.asSelectionGestureHost(), []);
}
