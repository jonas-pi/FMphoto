import { UIContext } from '@kit.ArkUI';
import { AppSession } from '../../auth/AppSession';
import { AiPersonItem, GalleryListItem, MediaCategoryItem, SmartCategoryItem } from '../../model/FnApiTypes';
import { FN_GLOBAL_TAB_SWITCH_CURVE, FN_GLOBAL_TAB_SWITCH_DURATION } from '../../common/FnMotion';
import { GALLERY_TOP_BAR_FLOATING_TOTAL_HEIGHT_VP } from './GalleryAlbumTopBar';
import { loadMediaCategories as requestMediaCategories, loadPersons as requestPersons, loadSmartCategories as requestSmartCategories } from './GalleryAlbumModeLoaders';

export interface GalleryAlbumRootSurfaceHost {
  getUIContext(): UIContext;
  baseUrl: string;
  topSafeInsetVp: number;
  floatingDockInsetBottomVp: number;
  homeSurface: string;
  inSearchMode: boolean;
  inCategoryMode: boolean;
  inSmartCategoryMode: boolean;
  inPersonMode: boolean;
  moreMenuExpanded: boolean;
  categoryLoading: boolean;
  categoryError: string;
  categoryItems: MediaCategoryItem[];
  smartCategoryLoading: boolean;
  smartCategoryError: string;
  smartSceneItems: SmartCategoryItem[];
  smartInfoItems: SmartCategoryItem[];
  personLoading: boolean;
  personError: string;
  personItems: AiPersonItem[];
  searchLoading: boolean;
  searchError: string;
  searchResults: GalleryListItem[];
  categoryOpening: boolean;
  rootModeContentWidthVp: number;
  rootPhotosSurfaceTranslateX: number;
  rootAlbumsSurfaceTranslateX: number;
  rootSurfaceSwitchAnimating: boolean;
  rootSurfaceSwitchStartTimer: number;
  rootSurfaceSwitchTimer: number;
  rootSurfaceSwitchFrom: string;
  rootSurfaceSwitchTo: string;
  albumsHomeSmartPrefetchGen: number;
  albumsHomePersonPrefetchGen: number;
  albumsHomeMediaPrefetchGen: number;
  lastHomeSurface: string;
  dismissMoreMenu(): void;
  refreshRootPhotosScrollTitle(): void;
  notifySelectionDockStateChange(): void;
  exitGallerySelection(): void;
  playModeSwitchMotion(direction?: number): void;
  backToMain(animate: boolean): void;
  loadMediaCategories(): Promise<void>;
  toast(msg: string): void;
}

export function galleryAlbumIsPhotosHomeSurface(host: GalleryAlbumRootSurfaceHost): boolean {
  return host.homeSurface !== 'albums';
}

export function galleryAlbumIsAlbumsHomeSurface(host: GalleryAlbumRootSurfaceHost): boolean {
  return host.homeSurface === 'albums';
}

export function galleryAlbumAlbumsHomeSmartItems(host: GalleryAlbumRootSurfaceHost): SmartCategoryItem[] {
  return host.smartSceneItems.concat(host.smartInfoItems);
}

export function galleryAlbumEnsureAlbumsHomeSupplementaryData(host: GalleryAlbumRootSurfaceHost): void {
  const canSilentPrefetchMedia = galleryAlbumIsPhotosHomeSurface(host) &&
    !host.inSearchMode &&
    !host.inCategoryMode &&
    !host.inSmartCategoryMode &&
    !host.inPersonMode;
  if (!galleryAlbumIsAlbumsHomeSurface(host) && !canSilentPrefetchMedia) {
    return;
  }
  if (host.inSmartCategoryMode || host.inPersonMode) {
    return;
  }
  const needMediaPrefetch = host.categoryItems.length <= 0 && !host.categoryLoading;
  const needSmartPrefetch = galleryAlbumAlbumsHomeSmartItems(host).length <= 0 && !host.smartCategoryLoading;
  const needPersonPrefetch = host.personItems.length <= 0 && !host.personLoading;
  if (!needMediaPrefetch && !needSmartPrefetch && !needPersonPrefetch) {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    return;
  }
  if (needMediaPrefetch) {
    const mediaGen = ++host.albumsHomeMediaPrefetchGen;
    host.categoryLoading = true;
    host.categoryError = '';
    void (async (): Promise<void> => {
      const result = await requestMediaCategories(client);
      if (mediaGen !== host.albumsHomeMediaPrefetchGen) {
        return;
      }
      host.categoryItems = result.items;
      host.categoryError = result.error;
      host.categoryLoading = false;
    })();
  }
  if (needSmartPrefetch) {
    const gen = ++host.albumsHomeSmartPrefetchGen;
    host.smartCategoryLoading = true;
    host.smartCategoryError = '';
    void (async (): Promise<void> => {
      const result = await requestSmartCategories(client);
      if (gen !== host.albumsHomeSmartPrefetchGen) {
        return;
      }
      host.smartSceneItems = result.sceneItems;
      host.smartInfoItems = result.infoItems;
      host.smartCategoryError = result.error;
      host.smartCategoryLoading = false;
    })();
  }
  if (needPersonPrefetch) {
    const personGen = ++host.albumsHomePersonPrefetchGen;
    host.personLoading = true;
    host.personError = '';
    void (async (): Promise<void> => {
      const result = await requestPersons(client);
      if (personGen !== host.albumsHomePersonPrefetchGen) {
        return;
      }
      host.personItems = result.items;
      host.personError = result.error;
      host.personLoading = false;
    })();
  }
}

export function galleryAlbumOpenRecycleBinPage(host: GalleryAlbumRootSurfaceHost): void {
  host.getUIContext().getRouter().pushUrl({
    url: 'pages/RecycleBinPage',
    params: { baseUrl: host.baseUrl }
  }).catch((_e: Error): void => {
    host.toast('打开回收站失败');
  });
}

export function galleryAlbumOpenPersonPage(host: GalleryAlbumRootSurfaceHost): void {
  host.getUIContext().getRouter().pushUrl({
    url: 'pages/PersonPage',
    params: { baseUrl: host.baseUrl }
  }).catch((_e: Error): void => {
    host.toast('打开人物页失败');
  });
}

export function galleryAlbumOpenSmartCategoryPage(host: GalleryAlbumRootSurfaceHost): void {
  host.getUIContext().getRouter().pushUrl({
    url: 'pages/SmartCategoryPage',
    params: { baseUrl: host.baseUrl }
  }).catch((_e: Error): void => {
    host.toast('打开智能分类失败');
  });
}

export function galleryAlbumIsRootPhotosSurfaceVisible(host: GalleryAlbumRootSurfaceHost): boolean {
  return galleryAlbumIsPhotosHomeSurface(host) &&
    !host.inSearchMode &&
    !host.inCategoryMode &&
    !host.inSmartCategoryMode &&
    !host.inPersonMode;
}

export function galleryAlbumIsRootAlbumsSurfaceVisible(host: GalleryAlbumRootSurfaceHost): boolean {
  return galleryAlbumIsAlbumsHomeSurface(host) &&
    !host.inSearchMode &&
    host.inCategoryMode &&
    !host.inSmartCategoryMode &&
    !host.inPersonMode;
}

export function galleryAlbumShouldKeepAlbumsHomeMounted(_host: GalleryAlbumRootSurfaceHost): boolean {
  return true;
}

export function galleryAlbumIsRootSurfaceVisible(host: GalleryAlbumRootSurfaceHost): boolean {
  return galleryAlbumIsRootPhotosSurfaceVisible(host) || galleryAlbumIsRootAlbumsSurfaceVisible(host);
}

export function galleryAlbumClearRootSurfaceSwitchTimer(host: GalleryAlbumRootSurfaceHost): void {
  if (host.rootSurfaceSwitchStartTimer >= 0) {
    clearTimeout(host.rootSurfaceSwitchStartTimer);
    host.rootSurfaceSwitchStartTimer = -1;
  }
  if (host.rootSurfaceSwitchTimer >= 0) {
    clearTimeout(host.rootSurfaceSwitchTimer);
    host.rootSurfaceSwitchTimer = -1;
  }
}

export function galleryAlbumRootSurfaceSlideWidthVp(host: GalleryAlbumRootSurfaceHost): number {
  return host.rootModeContentWidthVp > 0 ? host.rootModeContentWidthVp : 360;
}

export function galleryAlbumIsRootPhotosSurfaceLayerVisible(host: GalleryAlbumRootSurfaceHost): boolean {
  return galleryAlbumIsRootPhotosSurfaceVisible(host) ||
    (host.rootSurfaceSwitchAnimating &&
      (host.rootSurfaceSwitchFrom === 'photos' || host.rootSurfaceSwitchTo === 'photos'));
}

export function galleryAlbumIsRootAlbumsSurfaceLayerVisible(host: GalleryAlbumRootSurfaceHost): boolean {
  return galleryAlbumIsRootAlbumsSurfaceVisible(host) ||
    (host.rootSurfaceSwitchAnimating &&
      (host.rootSurfaceSwitchFrom === 'albums' || host.rootSurfaceSwitchTo === 'albums'));
}

export function galleryAlbumRootPhotosSurfaceZIndex(host: GalleryAlbumRootSurfaceHost): number {
  if (host.rootSurfaceSwitchAnimating) {
    return host.rootSurfaceSwitchTo === 'photos' ? 2 : 1;
  }
  return galleryAlbumIsRootPhotosSurfaceVisible(host) ? 2 : 1;
}

export function galleryAlbumRootAlbumsSurfaceZIndex(host: GalleryAlbumRootSurfaceHost): number {
  if (host.rootSurfaceSwitchAnimating) {
    return host.rootSurfaceSwitchTo === 'albums' ? 2 : 1;
  }
  return galleryAlbumIsRootAlbumsSurfaceVisible(host) ? 2 : 1;
}

export function galleryAlbumResetRootSurfaceSwitchTransforms(host: GalleryAlbumRootSurfaceHost): void {
  host.rootPhotosSurfaceTranslateX = 0;
  host.rootAlbumsSurfaceTranslateX = 0;
}

export function galleryAlbumBeginRootSurfaceSwitch(
  host: GalleryAlbumRootSurfaceHost,
  prevSurface: string,
  nextSurface: string
): void {
  if ((prevSurface !== 'photos' && prevSurface !== 'albums') ||
    (nextSurface !== 'photos' && nextSurface !== 'albums') ||
    prevSurface === nextSurface) {
    galleryAlbumClearRootSurfaceSwitchTimer(host);
    host.rootSurfaceSwitchAnimating = false;
    galleryAlbumResetRootSurfaceSwitchTransforms(host);
    return;
  }
  const width = galleryAlbumRootSurfaceSlideWidthVp(host);
  galleryAlbumClearRootSurfaceSwitchTimer(host);
  host.rootSurfaceSwitchFrom = prevSurface;
  host.rootSurfaceSwitchTo = nextSurface;
  host.rootSurfaceSwitchAnimating = true;
  if (prevSurface === 'photos' && nextSurface === 'albums') {
    host.rootPhotosSurfaceTranslateX = 0;
    host.rootAlbumsSurfaceTranslateX = width;
  } else {
    host.rootPhotosSurfaceTranslateX = -width;
    host.rootAlbumsSurfaceTranslateX = 0;
  }
  host.rootSurfaceSwitchStartTimer = setTimeout((): void => {
    host.rootSurfaceSwitchStartTimer = -1;
    if (host.rootSurfaceSwitchFrom !== prevSurface || host.rootSurfaceSwitchTo !== nextSurface) {
      return;
    }
    host.getUIContext().animateTo(
      { duration: FN_GLOBAL_TAB_SWITCH_DURATION, curve: FN_GLOBAL_TAB_SWITCH_CURVE },
      (): void => {
        if (prevSurface === 'photos' && nextSurface === 'albums') {
          host.rootPhotosSurfaceTranslateX = -width;
          host.rootAlbumsSurfaceTranslateX = 0;
          return;
        }
        host.rootPhotosSurfaceTranslateX = 0;
        host.rootAlbumsSurfaceTranslateX = width;
      }
    );
    host.rootSurfaceSwitchTimer = setTimeout((): void => {
      host.rootSurfaceSwitchTimer = -1;
      if (host.rootSurfaceSwitchFrom !== prevSurface || host.rootSurfaceSwitchTo !== nextSurface) {
        return;
      }
      host.rootSurfaceSwitchAnimating = false;
      galleryAlbumResetRootSurfaceSwitchTransforms(host);
    }, FN_GLOBAL_TAB_SWITCH_DURATION + 32);
  }, 0);
}

export function galleryAlbumReturnToHomeSurfaceRoot(host: GalleryAlbumRootSurfaceHost, animate: boolean): void {
  if (galleryAlbumIsAlbumsHomeSurface(host)) {
    if (galleryAlbumIsRootAlbumsSurfaceVisible(host)) {
      galleryAlbumEnsureAlbumsHomeSupplementaryData(host);
      return;
    }
    host.exitGallerySelection();
    if (animate) {
      host.playModeSwitchMotion(1);
    }
    host.inSearchMode = false;
    host.inSmartCategoryMode = false;
    host.inPersonMode = false;
    host.inCategoryMode = true;
    host.categoryOpening = false;
    if (host.categoryItems.length <= 0 && !host.categoryLoading) {
      void host.loadMediaCategories();
    }
    galleryAlbumEnsureAlbumsHomeSupplementaryData(host);
    return;
  }
  if (host.inSearchMode || host.inCategoryMode || host.inSmartCategoryMode || host.inPersonMode) {
    host.backToMain(animate);
  }
}

export function galleryAlbumSyncHomeSurface(host: GalleryAlbumRootSurfaceHost, animate: boolean): void {
  galleryAlbumReturnToHomeSurfaceRoot(host, animate);
}

export function galleryAlbumShouldKeepRootPhotosMainMounted(host: GalleryAlbumRootSurfaceHost): boolean {
  return galleryAlbumIsRootPhotosSurfaceVisible(host) || galleryAlbumIsRootAlbumsSurfaceVisible(host);
}

export function galleryAlbumTryConsumeSurfaceBack(host: GalleryAlbumRootSurfaceHost): boolean {
  if (host.moreMenuExpanded) {
    host.dismissMoreMenu();
    return true;
  }
  if (!host.inSearchMode && !host.inCategoryMode && !host.inSmartCategoryMode && !host.inPersonMode) {
    return false;
  }
  galleryAlbumReturnToHomeSurfaceRoot(host, true);
  return true;
}

export function galleryAlbumOnHomeSurfaceChanged(host: GalleryAlbumRootSurfaceHost): void {
  const prevSurface = host.lastHomeSurface;
  const nextSurface = host.homeSurface;
  host.dismissMoreMenu();
  const switchingRootSurface = prevSurface !== nextSurface;
  if (switchingRootSurface) {
    galleryAlbumSyncHomeSurface(host, false);
    galleryAlbumBeginRootSurfaceSwitch(host, prevSurface, nextSurface);
  } else {
    galleryAlbumClearRootSurfaceSwitchTimer(host);
    host.rootSurfaceSwitchAnimating = false;
    galleryAlbumResetRootSurfaceSwitchTransforms(host);
    galleryAlbumSyncHomeSurface(host, true);
  }
  host.refreshRootPhotosScrollTitle();
  galleryAlbumEnsureAlbumsHomeSupplementaryData(host);
  host.notifySelectionDockStateChange();
  host.lastHomeSurface = nextSurface;
}

export function galleryAlbumOpenSearchPanel(host: GalleryAlbumRootSurfaceHost): void {
  host.dismissMoreMenu();
  host.exitGallerySelection();
  if (!host.inSearchMode) {
    host.playModeSwitchMotion(1);
  }
  host.inSearchMode = true;
  host.inCategoryMode = false;
  host.inSmartCategoryMode = false;
  host.inPersonMode = false;
  host.searchLoading = false;
  host.searchError = '';
  host.searchResults = [];
}

export function galleryAlbumToggleMoreMenu(host: GalleryAlbumRootSurfaceHost): void {
  host.moreMenuExpanded = !host.moreMenuExpanded;
}

export function galleryAlbumSecondaryModeContentInsetTopVp(host: GalleryAlbumRootSurfaceHost): number {
  return host.topSafeInsetVp + GALLERY_TOP_BAR_FLOATING_TOTAL_HEIGHT_VP;
}

export function galleryAlbumMainGalleryContentInsetTopVp(host: GalleryAlbumRootSurfaceHost): number {
  return galleryAlbumSecondaryModeContentInsetTopVp(host);
}

export function galleryAlbumCurrentBottomDockInsetVp(host: GalleryAlbumRootSurfaceHost): number {
  if (host.inSearchMode) {
    return 0;
  }
  return host.floatingDockInsetBottomVp;
}
