/**
 * 图库大图预览（独立页面）。
 *
 * 布局：顶栏（← | 计数 | 原图⊙ | ···）/ 全屏 Swiper / 底栏（分享 下载 收藏 删除）
 *
 * 注：分享功能使用 @kit.ShareKit（@hms.collaboration.systemShare）。
 * 该模块属 HarmonyOS HMS SDK，DevEco Studio + hvigor 编译时可正常解析；
 * Cursor/VS Code 静态分析器不包含 HMS SDK 路径，linter 会误报 MODULE_NOT_FOUND，
 * 这属 IDE 配置限制，不影响实际构建。
 */
import { UIContext, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { GalleryPreviewSlide } from '../album/GalleryPreviewSlide';
import { GalleryPreviewNavStore } from '../album/GalleryPreviewNavStore';
import {
  GallerySlideshowStreamStore
} from '../album/slideshow/GallerySlideshowStreamStore';
import { GallerySlideshowPlaylistEntry } from '../album/slideshow/GallerySlideshowTypes';
import { GalleryListItem, GalleryPhotoDetailData, PersonInPhotoItem } from '../model/FnApiTypes';
import { isVideoItem, trimThumbPixCache } from '../album/GalleryAlbumCommon';
import { AppSession, FN_MEDIA_BASE_URL } from '../auth/AppSession';
import { fnApplyImmersiveSystemBarColors } from '../common/FnSplashTheme';
import {
  FN_SYSTEM_BOTTOM_INSET_VP_KEY,
  FN_SYSTEM_TOP_INSET_VP_KEY,
  fnPublishSystemAvoidArea
} from '../common/FnSystemAvoidArea';
import {
  FN_FLOATING_TOP_TOTAL_HEIGHT_VP,
  fnBottomDockBottomGap,
  FnFullLoadingMask,
  FnStateText
} from '../common/FnUiCommon';
import {
  FN_PREVIEW_PAGE_ENTER_CURVE,
  FN_PREVIEW_PAGE_ENTER_DURATION,
  FN_PREVIEW_PAGE_EXIT_CURVE,
  FN_PREVIEW_PAGE_EXIT_DURATION,
  FN_SWIPER_CURVE,
  FN_SWIPER_DURATION
} from '../common/FnMotion';
import {
  GalleryPreviewActionsHost,
  galleryPreviewCloseDetailsPanel,
  galleryPreviewDeleteCurrentItem,
  galleryPreviewDownloadCurrentImage,
  galleryPreviewOnPersonInPhotoClick,
  galleryPreviewOpenDetailsPanel,
  galleryPreviewOpenFolderFromDetailPath,
  galleryPreviewRefreshCollectStateFromGetOne,
  galleryPreviewShareCurrentImage,
  galleryPreviewSyncCollectStateFromCurrentItem,
  galleryPreviewToggleFavorite
} from './galleryPreview/GalleryPreviewActions';
import { GalleryPreviewChrome } from './galleryPreview/GalleryPreviewChrome';
import { PreviewItemsDataSource } from './galleryPreview/GalleryPreviewDataSource';
import { GalleryPreviewDetailsSheet } from './galleryPreview/GalleryPreviewDetailsSheet';
import { LivePhotoSaveSheet } from '../album/livephoto/LivePhotoSave';
import { unlinkLivePhotoPair, LivePhotoPairFiles } from '../album/livephoto/LivePhotoSandbox';
import {
  galleryPreviewCurrentHasOriginal,
  galleryPreviewFavoriteStarTint,
  galleryPreviewStarFilled,
  galleryPreviewTitleCounter
} from './galleryPreview/GalleryPreviewDetailsLogic';
import {
  setGalleryPreviewToolbarVisible,
  toggleGalleryPreviewToolbarVisible
} from './galleryPreview/GalleryPreviewToolbarStore';
import {
  resetGalleryPreviewVideoChrome,
  restoreGalleryPreviewPortrait
} from './galleryPreview/GalleryPreviewVideoStore';

@Entry
@Component
struct GalleryPreview {
  @StorageProp(FN_MEDIA_BASE_URL) private baseUrl: string = '';
  @State private swiperIndex: number = 0;
  @State private swiperLocked: boolean = false;
  @State private pinchGestureActive: boolean = false;
  @State private previewZoomLocked: boolean = false;
  @State private totalCount: number = 0;
  @State private dismissDragProgress: number = 0;
  @State private loadOriginalToken: number = 0;
  @State private downloading: boolean = false;
  @State private downloadProgressPct: number = 0;
  @State private downloadProgressKnown: boolean = false;
  @State private sharing: boolean = false;
  @State private liveSaveVisible: boolean = false;
  /** 详情与实况保存共用一个 bindSheet；同一节点挂两个会互相挤掉，只剩闪一下 */
  @State private previewSheetVisible: boolean = false;
  @State private liveSaveImageUri: string = '';
  @State private liveSaveVideoUri: string = '';
  @State private liveSaveImagePath: string = '';
  @State private liveSaveVideoPath: string = '';
  @State private liveSaveTitle: string = '';
  @State private deleting: boolean = false;
  @State private detailsVisible: boolean = false;
  @State private detailsLoading: boolean = false;
  @State private detailsError: string = '';
  @State private detailsData: GalleryPhotoDetailData | undefined = undefined;
  @State private detailsPhotoId: string = '';
  @State private personsInPhoto: PersonInPhotoItem[] = [];
  @State private folderOpening: boolean = false;
  @State private personOpening: boolean = false;
  @State private favoriteToggling: boolean = false;
  @State private currentCollectState: number = -1;
  @State private bottomBarHeight: number = 80;
  @State private originalShowing: boolean = false;
  @State private originalPreviewEnabled: boolean = false;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(FN_SYSTEM_BOTTOM_INSET_VP_KEY) private systemBottomInsetVp: number = 0;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @State private isDarkTheme: boolean = false;

  private itemSource: PreviewItemsDataSource = new PreviewItemsDataSource();
  private previewItems: GalleryListItem[] = [];
  private swiperCtrl: SwiperController = new SwiperController();
  private collectSyncGen: number = 0;
  private slideshowEnabled: boolean = false;
  private slideshowIntervalMs: number = 5000;
  private slideshowLibraryTotal: number = 0;
  private slideshowGlobalIndices: number[] = [];
  private slideshowTimerId: number = -1;

  onPageShow(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar(true);
    if (this.slideshowEnabled) {
      this.armSlideshowTimer();
    }
  }

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar(false);
  }

  onBackPress(): boolean {
    this.navigateBack();
    return true;
  }

  private navigateBack(): void {
    void restoreGalleryPreviewPortrait(this.getUIContext());
    this.getUIContext().getRouter().back();
  }

  aboutToAppear(): void {
    this.baseUrl = GalleryPreviewNavStore.baseUrl;
    this.previewItems = GalleryPreviewNavStore.items.slice();
    this.itemSource.reloadAll(this.previewItems);
    this.totalCount = this.previewItems.length;
    this.swiperIndex = GalleryPreviewNavStore.startIndex;
    this.isDarkTheme = this.colorMode === 1;
    const routeParams = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
    if (routeParams !== undefined && routeParams['idx'] !== undefined) {
      const n = Number(routeParams['idx']);
      if (Number.isFinite(n) && n >= 0 && n < this.totalCount) {
        this.swiperIndex = Math.floor(n);
      }
    }
    this.syncCollectStateFromCurrentItem();
    void this.refreshCollectStateFromGetOne(this.currentItemId());
    this.slideshowEnabled = GalleryPreviewNavStore.slideshow.enabled;
    this.slideshowIntervalMs = GalleryPreviewNavStore.slideshow.intervalMs;
    this.slideshowLibraryTotal = GalleryPreviewNavStore.slideshow.libraryTotalCount;
    this.slideshowGlobalIndices = GalleryPreviewNavStore.slideshowGlobalIndices.slice();
    if (!this.slideshowEnabled && routeParams !== undefined && routeParams['slideshow'] === '1') {
      this.slideshowEnabled = true;
      if (this.slideshowIntervalMs <= 0) {
        this.slideshowIntervalMs = 5000;
      }
    }
    if (this.slideshowLibraryTotal <= 0 && GallerySlideshowStreamStore.isActive()) {
      this.slideshowLibraryTotal = GallerySlideshowStreamStore.getLibraryTotalCount();
    }
    // 工具栏显隐不进本页 @State，避免点击切换时整页（含 Swiper）重绘。
    setGalleryPreviewToolbarVisible(!this.slideshowEnabled);
    if (this.slideshowEnabled) {
      this.maybePrefetchSlideshowItems();
    }
  }

  private clearSlideshowTimer(): void {
    if (this.slideshowTimerId >= 0) {
      clearTimeout(this.slideshowTimerId);
      this.slideshowTimerId = -1;
    }
  }

  private shouldPauseSlideshow(): boolean {
    return this.pinchGestureActive || this.previewZoomLocked || this.detailsVisible ||
      this.downloading || this.sharing || this.deleting;
  }

  private advanceSlideshow(): void {
    if (!this.slideshowEnabled) {
      return;
    }
    if (this.swiperIndex + 1 < this.totalCount) {
      const next = this.swiperIndex + 1;
      this.swiperIndex = next;
      this.swiperCtrl.changeIndex(next, true);
      this.maybePrefetchSlideshowItems();
      return;
    }
    if (GallerySlideshowStreamStore.isActive()) {
      void GallerySlideshowStreamStore.prefetchAppend((entries: GallerySlideshowPlaylistEntry[]): void => {
        if (entries.length === 0) {
          return;
        }
        this.appendSlideshowEntries(entries);
        const next = this.swiperIndex + 1;
        if (next < this.totalCount) {
          this.swiperIndex = next;
          this.swiperCtrl.changeIndex(next, true);
          this.maybePrefetchSlideshowItems();
        }
      });
      return;
    }
    if (this.totalCount <= 1) {
      return;
    }
    this.swiperIndex = 0;
    this.swiperCtrl.changeIndex(0, true);
  }

  private maybePrefetchSlideshowItems(): void {
    if (!this.slideshowEnabled || !GallerySlideshowStreamStore.isActive()) {
      return;
    }
    const remaining = this.totalCount - this.swiperIndex - 1;
    if (!GallerySlideshowStreamStore.shouldPrefetch(remaining)) {
      return;
    }
    void GallerySlideshowStreamStore.prefetchAppend((entries: GallerySlideshowPlaylistEntry[]): void => {
      this.appendSlideshowEntries(entries);
    });
  }

  private appendSlideshowEntries(entries: GallerySlideshowPlaylistEntry[]): void {
    if (entries.length === 0) {
      return;
    }
    const items: GalleryListItem[] = [];
    for (let i = 0; i < entries.length; i++) {
      items.push(entries[i].item);
      this.slideshowGlobalIndices.push(entries[i].globalIndex);
    }
    for (let i = 0; i < items.length; i++) {
      this.previewItems.push(items[i]);
    }
    this.itemSource.appendItems(items);
    this.totalCount = this.previewItems.length;
    GallerySlideshowStreamStore.rememberEntries(entries);
  }

  private slideshowGlobalIndexAt(playlistIdx: number): number {
    if (playlistIdx < 0 || playlistIdx >= this.slideshowGlobalIndices.length) {
      return -1;
    }
    return this.slideshowGlobalIndices[playlistIdx];
  }

  private armSlideshowTimer(): void {
    this.clearSlideshowTimer();
    if (!this.slideshowEnabled || this.slideshowIntervalMs <= 0) {
      return;
    }
    if (this.totalCount <= 1 && !GallerySlideshowStreamStore.isActive()) {
      return;
    }
    this.slideshowTimerId = setTimeout((): void => {
      this.slideshowTimerId = -1;
      if (this.shouldPauseSlideshow()) {
        this.armSlideshowTimer();
        return;
      }
      this.advanceSlideshow();
      this.armSlideshowTimer();
    }, this.slideshowIntervalMs);
  }

  aboutToDisappear(): void {
    this.clearSlideshowTimer();
    this.detailsVisible = false;
    this.detailsLoading = false;
    this.detailsError = '';
    this.detailsData = undefined;
    this.detailsPhotoId = '';
    this.personsInPhoto = [];
    this.folderOpening = false;
    this.personOpening = false;
    this.downloadProgressPct = 0;
    this.downloadProgressKnown = false;
    trimThumbPixCache(24);
    const client = AppSession.getClient();
    if (client !== null) {
      client.cancelPendingRequests();
    }
    GalleryPreviewNavStore.clear();
    setGalleryPreviewToolbarVisible(true);
    resetGalleryPreviewVideoChrome();
    void restoreGalleryPreviewPortrait(this.getUIContext());
    this.syncPreviewSheetVisible();
  }

  private applySystemBar(relayout: boolean): void {
    try {
      const dark = this.colorMode === 1;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window): void => {
        if (relayout) {
          win.setWindowLayoutFullScreen(true).catch((_e: Error): void => {});
        }
        fnApplyImmersiveSystemBarColors(win, dark);
        fnPublishSystemAvoidArea(win, this.getUIContext());
      }).catch((_e: Error): void => {});
    } catch (_e) {}
  }

  private isDark(): boolean {
    return this.isDarkTheme;
  }

  private pageBg(): string {
    return this.isDark() ? '#FF000000' : '#FFF5F5F5';
  }

  private toolbarBg(): string {
    if (this.currentItemIsVideo()) {
      return this.isDark() ? '#CC000000' : '#F2F5F5F5';
    }
    return this.isDark() ? '#FF000000' : '#FFF5F5F5';
  }

  private fgColor(): ResourceColor {
    if (this.currentItemIsVideo()) {
      return this.isDark() ? Color.White : Color.Black;
    }
    return this.isDark() ? Color.White : Color.Black;
  }

  private btnBg(): string {
    if (this.currentItemIsVideo()) {
      return this.isDark() ? '#33FFFFFF' : '#22000000';
    }
    return this.isDark() ? '#33FFFFFF' : '#22000000';
  }

  private videoControlsBottomPadding(): number {
    // 始终传底栏占位高度；显隐由视频控件自己读 AppStorage，避免父页因工具栏重绘。
    return this.bottomBarHeight + fnBottomDockBottomGap(this.systemBottomInsetVp);
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {}
  }

  private currentItem(): GalleryListItem | null {
    if (this.totalCount === 0 || this.swiperIndex >= this.totalCount) {
      return null;
    }
    return this.itemSource.getData(this.swiperIndex);
  }

  private currentItemIsVideo(): boolean {
    const item = this.currentItem();
    return item !== null && isVideoItem(item);
  }

  private currentItemId(): string {
    const item = this.currentItem();
    if (item === null || item.id === undefined || item.id === null) {
      return '';
    }
    const id = String(item.id).trim();
    return id.length > 0 ? id : '';
  }

  private currentHasOriginal(): boolean {
    return galleryPreviewCurrentHasOriginal(this.currentItem());
  }

  private titleCounter(): string {
    if (this.slideshowEnabled && this.slideshowLibraryTotal > 0) {
      const globalIdx = this.slideshowGlobalIndexAt(this.swiperIndex);
      if (globalIdx >= 0) {
        return galleryPreviewTitleCounter(globalIdx, this.slideshowLibraryTotal);
      }
    }
    const displayTotal = this.slideshowEnabled && this.slideshowLibraryTotal > 0
      ? this.slideshowLibraryTotal
      : this.totalCount;
    return galleryPreviewTitleCounter(this.swiperIndex, displayTotal);
  }

  private starFilled(): boolean {
    return galleryPreviewStarFilled(
      this.currentCollectState,
      this.currentItemId(),
      this.detailsPhotoId,
      this.detailsData
    );
  }

  private favoriteStarTint(): ResourceColor {
    return galleryPreviewFavoriteStarTint();
  }

  private runScopedTask(task: () => void): void {
    try {
      this.getUIContext().runScopedTask(task);
    } catch (_e) {
      task();
    }
  }

  private syncSwiperLocked(): void {
    this.swiperLocked = this.pinchGestureActive || this.previewZoomLocked;
  }

  private toggleToolbar(): void {
    toggleGalleryPreviewToolbarVisible();
  }

  private syncPreviewSheetVisible(): void {
    this.previewSheetVisible = this.detailsVisible || this.liveSaveVisible;
  }

  private previewSheetTitle(): string {
    return this.liveSaveVisible ? '保存动态照片' : '照片详情';
  }

  private previewSheetHeight(): Length {
    if (this.liveSaveVisible) {
      return 220;
    }
    return '50%';
  }

  private toggleOriginalPreview(): void {
    if (!this.currentHasOriginal()) {
      return;
    }
    if (this.originalPreviewEnabled) {
      this.originalPreviewEnabled = false;
      this.originalShowing = false;
      return;
    }
    this.originalPreviewEnabled = true;
    this.loadOriginalToken++;
  }

  private syncCollectStateFromCurrentItem(): void {
    galleryPreviewSyncCollectStateFromCurrentItem(this.asActionsHost());
  }

  private async refreshCollectStateFromGetOne(photoId: string): Promise<void> {
    await galleryPreviewRefreshCollectStateFromGetOne(this.asActionsHost(), photoId);
  }

  private async toggleFavorite(): Promise<void> {
    await galleryPreviewToggleFavorite(this.asActionsHost());
  }

  private async deleteCurrentItem(): Promise<void> {
    this.originalPreviewEnabled = false;
    this.originalShowing = false;
    await galleryPreviewDeleteCurrentItem(this.asActionsHost());
  }

  private openDetailsPanel(): void {
    galleryPreviewOpenDetailsPanel(this.asActionsHost());
  }

  private closeDetailsPanel(): void {
    galleryPreviewCloseDetailsPanel(this.asActionsHost());
  }

  private openFolderFromDetailPath(): void {
    galleryPreviewOpenFolderFromDetailPath(this.asActionsHost());
  }

  private async onPersonInPhotoClick(p: PersonInPhotoItem): Promise<void> {
    await galleryPreviewOnPersonInPhotoClick(this.asActionsHost(), p);
  }

  private downloadCurrentImage(): void {
    galleryPreviewDownloadCurrentImage(this.asActionsHost());
  }

  private shareCurrentImage(): void {
    galleryPreviewShareCurrentImage(this.asActionsHost());
  }

  private asActionsHost(): GalleryPreviewActionsHost {
    const self = this;
    class PreviewActionsHostBridge implements GalleryPreviewActionsHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(v: string) { self.baseUrl = v; }

      get swiperIndex(): number { return self.swiperIndex; }
      set swiperIndex(v: number) { self.swiperIndex = v; }

      get totalCount(): number { return self.totalCount; }
      set totalCount(v: number) { self.totalCount = v; }

      get detailsVisible(): boolean { return self.detailsVisible; }
      set detailsVisible(v: boolean) {
        self.detailsVisible = v;
        self.syncPreviewSheetVisible();
      }

      get detailsLoading(): boolean { return self.detailsLoading; }
      set detailsLoading(v: boolean) { self.detailsLoading = v; }

      get detailsError(): string { return self.detailsError; }
      set detailsError(v: string) { self.detailsError = v; }

      get detailsData(): GalleryPhotoDetailData | undefined { return self.detailsData; }
      set detailsData(v: GalleryPhotoDetailData | undefined) { self.detailsData = v; }

      get detailsPhotoId(): string { return self.detailsPhotoId; }
      set detailsPhotoId(v: string) { self.detailsPhotoId = v; }

      get personsInPhoto(): PersonInPhotoItem[] { return self.personsInPhoto; }
      set personsInPhoto(v: PersonInPhotoItem[]) { self.personsInPhoto = v; }

      get folderOpening(): boolean { return self.folderOpening; }
      set folderOpening(v: boolean) { self.folderOpening = v; }

      get personOpening(): boolean { return self.personOpening; }
      set personOpening(v: boolean) { self.personOpening = v; }

      get favoriteToggling(): boolean { return self.favoriteToggling; }
      set favoriteToggling(v: boolean) { self.favoriteToggling = v; }

      get currentCollectState(): number { return self.currentCollectState; }
      set currentCollectState(v: number) { self.currentCollectState = v; }

      get originalShowing(): boolean { return self.originalShowing; }
      set originalShowing(v: boolean) { self.originalShowing = v; }

      get deleting(): boolean { return self.deleting; }
      set deleting(v: boolean) { self.deleting = v; }

      get downloading(): boolean { return self.downloading; }
      set downloading(v: boolean) { self.downloading = v; }

      get downloadProgressPct(): number { return self.downloadProgressPct; }
      set downloadProgressPct(v: number) { self.downloadProgressPct = v; }

      get downloadProgressKnown(): boolean { return self.downloadProgressKnown; }
      set downloadProgressKnown(v: boolean) { self.downloadProgressKnown = v; }

      get sharing(): boolean { return self.sharing; }
      set sharing(v: boolean) { self.sharing = v; }

      get liveSaveVisible(): boolean { return self.liveSaveVisible; }
      set liveSaveVisible(v: boolean) {
        self.liveSaveVisible = v;
        self.syncPreviewSheetVisible();
      }

      get liveSaveImageUri(): string { return self.liveSaveImageUri; }
      set liveSaveImageUri(v: string) { self.liveSaveImageUri = v; }

      get liveSaveVideoUri(): string { return self.liveSaveVideoUri; }
      set liveSaveVideoUri(v: string) { self.liveSaveVideoUri = v; }

      get liveSaveImagePath(): string { return self.liveSaveImagePath; }
      set liveSaveImagePath(v: string) { self.liveSaveImagePath = v; }

      get liveSaveVideoPath(): string { return self.liveSaveVideoPath; }
      set liveSaveVideoPath(v: string) { self.liveSaveVideoPath = v; }

      get liveSaveTitle(): string { return self.liveSaveTitle; }
      set liveSaveTitle(v: string) { self.liveSaveTitle = v; }

      get previewItems(): GalleryListItem[] { return self.previewItems; }
      set previewItems(v: GalleryListItem[]) { self.previewItems = v; }

      get itemSource(): PreviewItemsDataSource { return self.itemSource; }
      set itemSource(v: PreviewItemsDataSource) { self.itemSource = v; }

      get swiperCtrl(): SwiperController { return self.swiperCtrl; }
      set swiperCtrl(v: SwiperController) { self.swiperCtrl = v; }

      get collectSyncGen(): number { return self.collectSyncGen; }
      set collectSyncGen(v: number) { self.collectSyncGen = v; }

      currentItem(): GalleryListItem | null { return self.currentItem(); }
      currentItemId(): string { return self.currentItemId(); }
      toast(msg: string): void { self.toast(msg); }
      routerBack(): void { self.navigateBack(); }
    }
    return new PreviewActionsHostBridge();
  }

  @Builder
  private liveSaveSheetBuilder() {
    LivePhotoSaveSheet({
      imageUri: this.liveSaveImageUri,
      videoUri: this.liveSaveVideoUri,
      imagePath: this.liveSaveImagePath,
      videoPath: this.liveSaveVideoPath,
      saveTitle: this.liveSaveTitle,
      isDark: this.isDark(),
      onSaved: (): void => {
        this.toast('已保存为动态照片');
        this.closeLiveSaveSheet(true);
      },
      onFailed: (): void => {
        this.toast('动态效果未写入，请重试或仅保存封面');
        this.closeLiveSaveSheet(false);
      }
    })
  }

  private closeLiveSaveSheet(unlinkFiles: boolean): void {
    if (unlinkFiles) {
      const pair = new LivePhotoPairFiles();
      pair.imagePath = this.liveSaveImagePath;
      pair.videoPath = this.liveSaveVideoPath;
      void unlinkLivePhotoPair(pair);
    }
    this.liveSaveVisible = false;
    this.syncPreviewSheetVisible();
    this.liveSaveImageUri = '';
    this.liveSaveVideoUri = '';
    this.liveSaveImagePath = '';
    this.liveSaveVideoPath = '';
    this.liveSaveTitle = '';
  }

  @Builder
  private previewSheetBuilder() {
    if (this.liveSaveVisible) {
      this.liveSaveSheetBuilder()
    } else {
      this.detailsSheetBuilder()
    }
  }

  @Builder
  private detailsSheetBuilder() {
    GalleryPreviewDetailsSheet({
      isDark: this.isDark(),
      detailsLoading: this.detailsLoading,
      detailsError: this.detailsError,
      detailsData: this.detailsData,
      personsInPhoto: this.personsInPhoto,
      folderOpening: this.folderOpening,
      personOpening: this.personOpening,
      onPersonClick: (p: PersonInPhotoItem): void => {
        void this.onPersonInPhotoClick(p);
      },
      onFolderClick: (): void => {
        this.openFolderFromDetailPath();
      }
    })
  }

  build() {
    Stack() {
      if (this.totalCount > 0) {
        Swiper(this.swiperCtrl) {
          LazyForEach(this.itemSource, (item: GalleryListItem, idx: number) => {
            GalleryPreviewSlide({
              baseUrl: this.baseUrl,
              item: item,
              loadOriginalToken: this.loadOriginalToken,
              originalPreviewEnabled: idx === this.swiperIndex && this.originalPreviewEnabled,
              active: idx === this.swiperIndex,
              videoBottomPadding: this.videoControlsBottomPadding(),
              onZoomLockChange: (locked: boolean): void => {
                this.runScopedTask((): void => {
                  this.previewZoomLocked = locked;
                  this.syncSwiperLocked();
                });
              },
              onPinchGestureActiveChange: (active: boolean): void => {
                this.runScopedTask((): void => {
                  this.pinchGestureActive = active;
                  this.syncSwiperLocked();
                });
              },
              onRequestPageSwitch: (delta: number): void => {
                const targetIdx = this.swiperIndex + delta;
                if (targetIdx < 0 || targetIdx >= this.totalCount) {
                  return;
                }
                this.swiperCtrl.changeIndex(targetIdx, true);
              },
              onVerticalDragProgress: (p: number): void => {
                this.dismissDragProgress = Math.max(0, Math.min(1, p));
              },
              onVerticalDismiss: (): void => { this.navigateBack(); },
              onOriginalLoaded: (): void => {
                if (this.originalPreviewEnabled) {
                  this.originalShowing = true;
                }
              },
              onOriginalLoadFailed: (msg: string): void => {
                if (this.originalPreviewEnabled) {
                  this.originalPreviewEnabled = false;
                  this.originalShowing = false;
                  this.toast(msg);
                }
              }
            })
          }, (item: GalleryListItem, i: number) => `gp_${item.id}_${i}`)
        }
        .width('100%')
        .height('100%')
        .index(this.swiperIndex)
        .indicator(false)
        .loop(false)
        .duration(FN_SWIPER_DURATION)
        .curve(FN_SWIPER_CURVE)
        .cachedCount(1)
        .disableSwipe(this.swiperLocked)
        .id('gallery_preview_swiper')
        .onClick((): void => {
          if (this.currentItemIsVideo()) {
            return;
          }
          this.toggleToolbar();
        })
        .onGestureRecognizerJudgeBegin((
          _event: BaseGestureEvent,
          current: GestureRecognizer,
          _others: Array<GestureRecognizer>
        ): GestureJudgeResult => {
          if (!this.currentItemIsVideo()) {
            return GestureJudgeResult.CONTINUE;
          }
          const gestureType = current.getType();
          if (gestureType !== GestureControl.GestureType.TAP_GESTURE &&
            gestureType !== GestureControl.GestureType.LONG_PRESS_GESTURE) {
            return GestureJudgeResult.CONTINUE;
          }
          // 拒掉 Swiper 内置单击/长按，放行视频层自定义手势
          if (current.isBuiltIn()) {
            return GestureJudgeResult.REJECT;
          }
          const target = current.getEventTargetInfo();
          if (target !== undefined && target.getId() === 'gallery_preview_swiper') {
            return GestureJudgeResult.REJECT;
          }
          return GestureJudgeResult.CONTINUE;
        })
        .onChange((idx: number): void => {
          this.swiperIndex = idx;
          this.pinchGestureActive = false;
          this.previewZoomLocked = false;
          this.syncSwiperLocked();
          this.dismissDragProgress = 0;
          this.originalPreviewEnabled = false;
          this.originalShowing = false;
          setGalleryPreviewToolbarVisible(true);
          if (!this.currentItemIsVideo()) {
            resetGalleryPreviewVideoChrome();
            void restoreGalleryPreviewPortrait(this.getUIContext());
          }
          this.applySystemBar(false);
          const nextId = this.currentItemId();
          this.syncCollectStateFromCurrentItem();
          if (nextId.length > 0 && this.detailsPhotoId === nextId && this.detailsData !== undefined) {
            const collectState = this.detailsData.isCollect;
            if (collectState === 1) {
              this.currentCollectState = 1;
            } else if (collectState === 0) {
              this.currentCollectState = 0;
            }
          }
          void this.refreshCollectStateFromGetOne(nextId);
          if (this.slideshowEnabled) {
            this.armSlideshowTimer();
            this.maybePrefetchSlideshowItems();
          }
        })
      } else {
        FnStateText({
          text: '暂无预览',
          topOffsetVp: this.systemTopInsetVp + FN_FLOATING_TOP_TOTAL_HEIGHT_VP
        })
      }

      GalleryPreviewChrome({
        dismissDragProgress: this.dismissDragProgress,
        titleText: this.titleCounter(),
        toolbarBg: this.toolbarBg(),
        buttonBg: this.btnBg(),
        darkMaterial: this.isDark(),
        topSafeInsetVp: this.systemTopInsetVp,
        bottomSafeInsetVp: this.systemBottomInsetVp,
        fgColor: this.fgColor(),
        showOriginalAction: this.currentHasOriginal(),
        originalShowing: this.originalPreviewEnabled,
        detailsShowing: this.detailsVisible,
        sharing: this.sharing,
        downloading: this.downloading,
        downloadProgressPct: this.downloadProgressPct,
        downloadProgressKnown: this.downloadProgressKnown,
        deleting: this.deleting,
        favoriteToggling: this.favoriteToggling,
        starFilled: this.starFilled(),
        favoriteStarTint: this.favoriteStarTint(),
        onBack: (): void => {
          this.navigateBack();
        },
        onLoadOriginal: (): void => {
          this.toggleOriginalPreview();
        },
        onOpenDetails: (): void => {
          this.openDetailsPanel();
        },
        onShare: (): void => {
          this.shareCurrentImage();
        },
        onDownload: (): void => {
          this.downloadCurrentImage();
        },
        onFavorite: (): void => {
          void this.toggleFavorite();
        },
        onDelete: (): void => {
          void this.deleteCurrentItem();
        },
        onBottomBarHeightChange: (height: number): void => {
          this.bottomBarHeight = height;
        }
      })

      if (this.personOpening) {
        FnFullLoadingMask({
          text: '加载人物媒体中…',
          topOffsetVp: this.systemTopInsetVp + FN_FLOATING_TOP_TOTAL_HEIGHT_VP
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.previewSheetVisible, this.previewSheetBuilder, {
      height: this.previewSheetHeight(),
      title: { title: this.previewSheetTitle() },
      showClose: true,
      dragBar: true,
      backgroundColor: this.isDark() ? '#FF1C1C1E' : '#FFFFFFFF',
      onDisappear: (): void => {
        if (this.liveSaveVisible) {
          this.closeLiveSaveSheet(true);
        } else {
          this.closeDetailsPanel();
        }
      }
    })
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PREVIEW_PAGE_ENTER_DURATION, curve: FN_PREVIEW_PAGE_ENTER_CURVE })
      .opacity(0)
      .scale({ x: 0.95, y: 0.95 })
    PageTransitionExit({ duration: FN_PREVIEW_PAGE_EXIT_DURATION, curve: FN_PREVIEW_PAGE_EXIT_CURVE })
      .opacity(0)
      .scale({ x: 0.95, y: 0.95 })
  }
}
