import { GalleryAlbumTopBar } from './GalleryAlbumTopBar';

@Component
export struct GalleryAlbumFloatingTopBarLayer {
  @Prop homeSurface: string = 'photos';
  @Prop inSearchMode: boolean = false;
  @Prop inCategoryMode: boolean = false;
  @Prop inSmartCategoryMode: boolean = false;
  @Prop inPersonMode: boolean = false;
  @Prop rootSurfaceTitle: string = '图库';
  @Prop gallerySelectionMode: boolean = false;
  @Prop gallerySelectedCount: number = 0;
  @Prop moreMenuExpanded: boolean = false;
  @Prop searchQuery: string = '';
  @Prop topSafeInsetVp: number = 0;
  @Prop pageShowSignal: number = 0;
  onSearchQueryChange: (value: string) => void = (_: string): void => {};
  onSearchSubmit: () => void = (): void => {};
  onOpenSearch: () => void = (): void => {};
  onStartUpload: () => void = (): void => {};
  onExitSelection: () => void = (): void => {};
  onEnterSelection: () => void = (): void => {};
  onBackToGallery: () => void = (): void => {};
  onShowMoreMenu: () => void = (): void => {};

  build() {
    Column() {
      GalleryAlbumTopBar({
        homeSurface: this.homeSurface,
        inSearchMode: this.inSearchMode,
        inCategoryMode: this.inCategoryMode,
        inSmartCategoryMode: this.inSmartCategoryMode,
        inPersonMode: this.inPersonMode,
        rootSurfaceTitle: this.rootSurfaceTitle,
        gallerySelectionMode: this.gallerySelectionMode,
        gallerySelectedCount: this.gallerySelectedCount,
        moreMenuExpanded: this.moreMenuExpanded,
        searchQuery: this.searchQuery,
        topSafeInsetVp: this.topSafeInsetVp,
        pageShowSignal: this.pageShowSignal,
        onSearchQueryChange: this.onSearchQueryChange,
        onSearchSubmit: this.onSearchSubmit,
        onOpenSearch: this.onOpenSearch,
        onStartUpload: this.onStartUpload,
        onExitSelection: this.onExitSelection,
        onEnterSelection: this.onEnterSelection,
        onBackToGallery: this.onBackToGallery,
        onShowMoreMenu: this.onShowMoreMenu
      })

      Blank()
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
