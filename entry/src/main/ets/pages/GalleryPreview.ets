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
import { GalleryListItem, GalleryPhotoDetailData, PersonInPhotoItem } from '../model/FnApiTypes';
import { isVideoItem, trimThumbPixCache } from '../album/GalleryAlbumCommon';
import { AppSession } from '../auth/AppSession';
import { FnFullLoadingMask, FnStateText } from '../common/FnUiCommon';
import {
  FN_PREVIEW_PAGE_ENTER_CURVE,
  FN_PREVIEW_PAGE_ENTER_DURATION,
  FN_PREVIEW_PAGE_EXIT_CURVE,
  FN_PREVIEW_PAGE_EXIT_DURATION,
  FN_SWIPER_CURVE,
  FN_SWIPER_DURATION,
  FN_UI_FADE_TOGGLE_CURVE,
  FN_UI_FADE_TOGGLE_DURATION
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
import {
  galleryPreviewCurrentHasOriginal,
  galleryPreviewFavoriteStarTint,
  galleryPreviewStarFilled,
  galleryPreviewTitleCounter,
  galleryPreviewToolbarAlpha
} from './galleryPreview/GalleryPreviewDetailsLogic';

@Entry
@Component
struct GalleryPreview {
  @State private baseUrl: string = '';
  @State private swiperIndex: number = 0;
  @State private swiperLocked: boolean = false;
  @State private pinchGestureActive: boolean = false;
  @State private previewZoomLocked: boolean = false;
  @State private totalCount: number = 0;
  @State private dismissDragProgress: number = 0;
  @State private toolbarVisible: boolean = true;
  @State private loadOriginalToken: number = 0;
  @State private downloading: boolean = false;
  @State private downloadProgressPct: number = 0;
  @State private downloadProgressKnown: boolean = false;
  @State private sharing: boolean = false;
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
  @State private systemTopInsetVp: number = 0;
  @State private systemBottomInsetVp: number = 0;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @State private isDarkTheme: boolean = false;

  private itemSource: PreviewItemsDataSource = new PreviewItemsDataSource();
  private previewItems: GalleryListItem[] = [];
  private swiperCtrl: SwiperController = new SwiperController();
  private collectSyncGen: number = 0;

  onPageShow(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar();
  }

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar();
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
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
  }

  aboutToDisappear(): void {
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
  }

  private applySystemBar(): void {
    try {
      const dark = this.colorMode === 1;
      const content = dark ? '#FFFFFFFF' : '#FF000000';
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win): void => {
        win.setWindowLayoutFullScreen(true).catch((_e: Error): void => {});
        this.syncSystemAvoidArea(win);
        win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: content,
          navigationBarContentColor: content
        }).catch((_e: Error): void => {});
      }).catch((_e: Error): void => {});
    } catch (_e) {}
  }

  private isDark(): boolean {
    return this.isDarkTheme;
  }

  private pxToVp(value: number): number {
    try {
      return this.getUIContext().px2vp(value);
    } catch (_e) {
      return value;
    }
  }

  private syncSystemAvoidArea(win: window.Window): void {
    try {
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.systemTopInsetVp = Math.max(0, this.pxToVp(area.topRect.height));
      this.systemBottomInsetVp = Math.max(0, this.pxToVp(area.bottomRect.height));
    } catch (_e) {
      this.systemTopInsetVp = 0;
      this.systemBottomInsetVp = 0;
    }
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
    return galleryPreviewTitleCounter(this.swiperIndex, this.totalCount);
  }

  private toolbarAlpha(): number {
    return galleryPreviewToolbarAlpha(this.dismissDragProgress);
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
    this.getUIContext().animateTo({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE }, (): void => {
      this.toolbarVisible = !this.toolbarVisible;
    });
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
      set detailsVisible(v: boolean) { self.detailsVisible = v; }

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
      routerBack(): void { self.getUIContext().getRouter().back(); }
    }
    return new PreviewActionsHostBridge();
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
      },
      onClose: (): void => {
        this.closeDetailsPanel();
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
              videoBottomPadding: this.toolbarVisible ? this.bottomBarHeight : 0,
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
              onVerticalDismiss: (): void => { this.getUIContext().getRouter().back(); },
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
        .onClick((): void => {
          this.toggleToolbar();
        })
        .onChange((idx: number): void => {
          this.swiperIndex = idx;
          this.pinchGestureActive = false;
          this.previewZoomLocked = false;
          this.syncSwiperLocked();
          this.dismissDragProgress = 0;
          this.originalPreviewEnabled = false;
          this.originalShowing = false;
          if (!this.toolbarVisible) {
            this.getUIContext().animateTo({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE }, (): void => {
              this.toolbarVisible = true;
            });
          }
          this.applySystemBar();
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
        })
      } else {
        FnStateText({ text: '暂无预览' })
      }

      GalleryPreviewChrome({
        toolbarVisible: this.toolbarVisible,
        titleText: this.titleCounter(),
        toolbarBg: this.toolbarBg(),
        buttonBg: this.btnBg(),
        darkMaterial: this.isDark(),
        topSafeInsetVp: this.systemTopInsetVp,
        bottomSafeInsetVp: this.systemBottomInsetVp,
        fgColor: this.fgColor(),
        showOriginalAction: this.currentHasOriginal(),
        originalShowing: this.originalPreviewEnabled,
        sharing: this.sharing,
        downloading: this.downloading,
        downloadProgressPct: this.downloadProgressPct,
        downloadProgressKnown: this.downloadProgressKnown,
        deleting: this.deleting,
        favoriteToggling: this.favoriteToggling,
        starFilled: this.starFilled(),
        favoriteStarTint: this.favoriteStarTint(),
        onBack: (): void => {
          this.getUIContext().getRouter().back();
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
      .hitTestBehavior(this.toolbarVisible ? HitTestMode.Transparent : HitTestMode.None)
      .opacity(this.toolbarVisible ? this.toolbarAlpha() : 0)
      .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })

      if (this.personOpening) {
        FnFullLoadingMask({ text: '加载人物媒体中…' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.detailsVisible, this.detailsSheetBuilder, {
      height: '50%',
      showClose: false,
      dragBar: true,
      backgroundColor: this.isDark() ? '#FF1C1C1E' : '#FFFFFFFF',
      onDisappear: (): void => {
        this.closeDetailsPanel();
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
