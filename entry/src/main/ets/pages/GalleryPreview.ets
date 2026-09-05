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
import { curves, display, UIContext, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { GalleryPreviewSlide } from '../album/GalleryPreviewSlide';
import { GalleryPreviewNavStore } from '../album/GalleryPreviewNavStore';
import { setGalleryPreviewOpening } from '../album/GalleryPreviewEntryGate';
import {
  addGalleryPreviewDismissListener,
  addGalleryPreviewDetailsFitListener,
  galleryDetailsMediumHeightVp,
  GalleryPreviewTranslateYUpdater,
  GalleryPreviewOpacityUpdater,
  GALLERY_ANIMATOR_FRAME_RATE,
  GALLERY_SHEET_SPRING_DAMPING,
  GALLERY_SHEET_SPRING_STIFFNESS,
  GALLERY_VERTICAL_VELOCITY_THRESHOLD,
  getGalleryPreviewDetailsFitNormVel,
  getGalleryPreviewDetailsSheetHeight,
  getGalleryPreviewDismissProgress,
  isGalleryPreviewDetailsAvoidAnimating,
  removeGalleryPreviewDismissListener,
  removeGalleryPreviewDetailsFitListener,
  resetGalleryPreviewDetailsFit,
  setGalleryPreviewDetailsAvoidAnimating,
  setGalleryPreviewDetailsAvoidVelocity,
  setGalleryPreviewDetailsFitNormVel,
  setGalleryPreviewDetailsSheetHeight,
  setGalleryPreviewDismissProgress,
  takeGalleryPreviewDetailsAvoidVelocity
} from '../album/GalleryPreviewVerticalGesture';
import {
  GALLERY_SCRIM_FADE_DELAY,
  GALLERY_SCRIM_FADE_DURATION,
  GALLERY_SHARED_TRANSITION_CURVE,
  GALLERY_SHARED_TRANSITION_DURATION,
  scheduleGalleryPreviewHeroInactive
} from '../album/GallerySharedTransition';
import {
  GallerySlideshowStreamStore
} from '../album/slideshow/GallerySlideshowStreamStore';
import { GallerySlideshowPlaylistEntry } from '../album/slideshow/GallerySlideshowTypes';
import { gallerySlideshowStableItemKey } from '../album/slideshow/GallerySlideshowMedia';
import { slideshowLogAppend, slideshowLogPage, slideshowLogPrefetch } from '../album/slideshow/GallerySlideshowTrace';
import { GalleryListItem, GalleryPhotoDetailData, PersonInPhotoItem } from '../model/FnApiTypes';
import { isVideoItem, trimThumbPixCache } from '../album/GalleryAlbumCommon';
import { isLivePhotoItem } from '../album/livephoto/LivePhotoDetect';
import {
  askLivePhotoSaveChoice,
  LivePhotoSaveActionSheet,
  LivePhotoSaveChoice,
  LIVE_PHOTO_PRIVILEGE_SHEET_TITLE
} from '../album/livephoto/LivePhotoSaveActionSheet';
import { AppSession, FN_MEDIA_BASE_URL } from '../auth/AppSession';
import { fnApplyImmersiveSystemBarColors } from '../common/FnSplashTheme';
import {
  FN_SYSTEM_BOTTOM_INSET_VP_KEY,
  FN_SYSTEM_TOP_INSET_VP_KEY,
  fnPublishSystemAvoidArea
} from '../common/FnSystemAvoidArea';
import { FnHdsChoiceSheet, fnHdsFitContentSheetOptions, fnHdsSaveButtonSheetOptions } from '../common/FnHdsOverlay';
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
import {
  galleryPreviewCurrentHasOriginal,
  galleryPreviewFavoriteStarTint,
  galleryPreviewStarFilled,
  galleryPreviewTitleCounter
} from './galleryPreview/GalleryPreviewDetailsLogic';
import {
  setGalleryPreviewDetailsCover,
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
  /** 预览背景遮罩：共享元素展开完成后再淡入，收回完成后再淡出 */
  @State private scrimOpacity: number = 0;
  @State private loadOriginalToken: number = 0;
  @State private downloading: boolean = false;
  @State private liveSaveSheetVisible: boolean = false;
  @State private choiceSheetVisible: boolean = false;
  @State private choiceSheetTitle: string = '';
  @State private choiceSheetButtons: string[] = [];
  @State private downloadProgressPct: number = 0;
  @State private downloadProgressKnown: boolean = false;
  @State private sharing: boolean = false;
  /** 页内详情是否展开。 */
  @State private deleting: boolean = false;
  @State private detailsVisible: boolean = false;
  @State private previewViewportH: number = 780;
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
  /** Router 下层可能停止绘制，使用进入预览前的页面快照稳定呈现“浮在图库上方”的效果。 */
  private sourcePageSnapshot: PixelMap | undefined = undefined;
  /** 快照中源缩略图的占位矩形（vp），只覆盖快照副本，不触碰真实图库节点。 */
  private sourcePlaceholderX: number = 0;
  private sourcePlaceholderY: number = 0;
  private sourcePlaceholderW: number = 0;
  private sourcePlaceholderH: number = 0;
  private swiperCtrl: SwiperController = new SwiperController();
  private collectSyncGen: number = 0;
  private slideshowEnabled: boolean = false;
  private slideshowIntervalMs: number = 5000;
  private slideshowLibraryTotal: number = 0;
  private slideshowGlobalIndices: number[] = [];
  private slideshowTimerId: number = -1;
  /** 详情打开期间视频已播完：关详情后再切页，避免半模态还在就自动划走 */
  private slideshowAdvancePending: boolean = false;
  /** 官方：Swiper+LazyForEach 禁止在 onChange 里刷新子页，补货须推迟 */
  private slideshowPrefetchTimer: number = -1;
  /** 切页日志：上一张全局下标 / 稳定键，用于识别顺延与重复 */
  private lastLoggedSlideshowGlobal: number = -1;
  private lastLoggedSlideshowKey: string = '';
  private chromeRevealTimer: number = -1;
  private heroScrimEntered: boolean = false;
  private choiceSheetResolver: ((index: number) => void) | undefined = undefined;
  private liveSaveResolver: ((choice: LivePhotoSaveChoice) => void) | undefined = undefined;
  /** 当前页内详情动画终点，用于避免重复提交相同弹簧。 */
  private detailsAvoidTargetVp: number = -1;

  onPageShow(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar(true);
    this.playHeroScrimEnterIfNeeded();
    if (this.slideshowEnabled) {
      this.armSlideshowTimer();
    }
  }

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar(false);
  }

  onBackPress(): boolean {
    if (this.choiceSheetVisible) {
      this.completeChoice(-1);
      return true;
    }
    if (this.liveSaveSheetVisible) {
      this.completeLivePhotoSave('cancel');
      return true;
    }
    if (this.detailsVisible) {
      this.closeDetailsPanel();
      return true;
    }
    this.navigateBack();
    return true;
  }

  private navigateBack(): void {
    void restoreGalleryPreviewPortrait(this.getUIContext());
    if (!this.slideshowEnabled) {
      this.clearChromeRevealTimer();
      setGalleryPreviewToolbarVisible(false);
      this.getUIContext().animateTo({
        duration: GALLERY_SCRIM_FADE_DURATION,
        delay: GALLERY_SCRIM_FADE_DELAY,
        curve: GALLERY_SHARED_TRANSITION_CURVE
      }, (): void => {
        this.scrimOpacity = 0;
      });
    }
    this.getUIContext().getRouter().back();
  }

  aboutToAppear(): void {
    this.sourcePageSnapshot = GalleryPreviewNavStore.sourcePageSnapshot;
    const uiCtx = this.getUIContext();
    this.sourcePlaceholderX = uiCtx.px2vp(GalleryPreviewNavStore.sourcePlaceholderX);
    this.sourcePlaceholderY = uiCtx.px2vp(GalleryPreviewNavStore.sourcePlaceholderY);
    this.sourcePlaceholderW = uiCtx.px2vp(GalleryPreviewNavStore.sourcePlaceholderW);
    this.sourcePlaceholderH = uiCtx.px2vp(GalleryPreviewNavStore.sourcePlaceholderH);
    this.baseUrl = GalleryPreviewNavStore.baseUrl;
    this.previewItems = GalleryPreviewNavStore.items.slice();
    this.itemSource.reloadAll(this.previewItems);
    this.totalCount = this.previewItems.length;
    this.swiperIndex = GalleryPreviewNavStore.startIndex;
    this.isDarkTheme = this.colorMode === 1;
    this.initPreviewViewportH();
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
    this.armChromeReveal();
    if (this.slideshowEnabled) {
      this.scrimOpacity = 1;
      this.heroScrimEntered = true;
    }
    setGalleryPreviewOpening(false);
    if (this.slideshowEnabled) {
      this.logSlideshowPage();
      this.maybePrefetchSlideshowItems();
    }
  }

  private clearSlideshowTimer(): void {
    if (this.slideshowTimerId >= 0) {
      clearTimeout(this.slideshowTimerId);
      this.slideshowTimerId = -1;
    }
  }

  private clearSlideshowPrefetchTimer(): void {
    if (this.slideshowPrefetchTimer >= 0) {
      clearTimeout(this.slideshowPrefetchTimer);
      this.slideshowPrefetchTimer = -1;
    }
  }

  private scheduleSlideshowPrefetch(): void {
    this.clearSlideshowPrefetchTimer();
    this.slideshowPrefetchTimer = setTimeout((): void => {
      this.slideshowPrefetchTimer = -1;
      this.maybePrefetchSlideshowItems();
    }, 0);
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
          this.clearSlideshowTimer();
          return;
        }
        this.appendSlideshowEntries(entries);
        const next = this.swiperIndex + 1;
        if (next < this.totalCount) {
          this.swiperIndex = next;
          this.swiperCtrl.changeIndex(next, true);
          this.maybePrefetchSlideshowItems();
        } else {
          this.clearSlideshowTimer();
        }
      });
      return;
    }
    // 没有更多不重复的片子：停在最后一张，不要绕回第一张
    this.clearSlideshowTimer();
  }

  private maybePrefetchSlideshowItems(): void {
    if (!this.slideshowEnabled || !GallerySlideshowStreamStore.isActive()) {
      return;
    }
    const remaining = this.totalCount - this.swiperIndex - 1;
    if (!GallerySlideshowStreamStore.shouldPrefetch(remaining)) {
      return;
    }
    slideshowLogPrefetch(remaining, this.swiperIndex, this.totalCount, 0);
    void GallerySlideshowStreamStore.prefetchAppend((entries: GallerySlideshowPlaylistEntry[]): void => {
      this.appendSlideshowEntries(entries);
    });
  }

  private appendSlideshowEntries(entries: GallerySlideshowPlaylistEntry[]): void {
    if (entries.length === 0) {
      return;
    }
    const seenKeys: Set<string> = new Set();
    const seenGlobals: Set<number> = new Set();
    for (let i = 0; i < this.previewItems.length; i++) {
      const key = gallerySlideshowStableItemKey(this.previewItems[i]);
      if (key.length > 0) {
        seenKeys.add(key);
      }
    }
    for (let i = 0; i < this.slideshowGlobalIndices.length; i++) {
      seenGlobals.add(this.slideshowGlobalIndices[i]);
    }
    const unique: GallerySlideshowPlaylistEntry[] = [];
    let dropGlobal = 0;
    let dropKey = 0;
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      if (seenGlobals.has(entry.globalIndex)) {
        dropGlobal++;
        continue;
      }
      const key = gallerySlideshowStableItemKey(entry.item);
      if (key.length > 0 && seenKeys.has(key)) {
        dropKey++;
        continue;
      }
      unique.push(entry);
      seenGlobals.add(entry.globalIndex);
      if (key.length > 0) {
        seenKeys.add(key);
      }
    }
    if (unique.length === 0) {
      slideshowLogAppend(entries.length, 0, dropGlobal, dropKey, this.previewItems.length,
        this.slideshowGlobalIndices.length);
      return;
    }
    const items: GalleryListItem[] = [];
    for (let i = 0; i < unique.length; i++) {
      items.push(unique[i].item);
      this.slideshowGlobalIndices.push(unique[i].globalIndex);
    }
    // itemSource.items 与 previewItems 是同一引用，appendItems 已经 push，这里不能再 push
    const before = this.previewItems.length;
    this.itemSource.appendItems(items);
    if (this.previewItems.length === before) {
      for (let i = 0; i < items.length; i++) {
        this.previewItems.push(items[i]);
      }
    }
    this.totalCount = this.previewItems.length;
    GallerySlideshowStreamStore.rememberEntries(unique);
    slideshowLogAppend(entries.length, unique.length, dropGlobal, dropKey, this.previewItems.length,
      this.slideshowGlobalIndices.length);
  }

  /** 记录当前页：标题回退、全局下标顺延、稳定键重复 */
  private logSlideshowPage(): void {
    if (!this.slideshowEnabled) {
      return;
    }
    const item = this.currentItem();
    const key = item !== null ? gallerySlideshowStableItemKey(item) : '';
    const globalIdx = this.slideshowGlobalIndexAt(this.swiperIndex);
    const fallback = globalIdx < 0;
    const sequential = globalIdx >= 0 && this.lastLoggedSlideshowGlobal >= 0 &&
      globalIdx === this.lastLoggedSlideshowGlobal + 1;
    const duplicateKey = key.length > 0 && key === this.lastLoggedSlideshowKey;
    slideshowLogPage(
      this.swiperIndex,
      globalIdx,
      key,
      this.previewItems.length,
      this.slideshowGlobalIndices.length,
      fallback,
      sequential,
      duplicateKey
    );
    this.lastLoggedSlideshowGlobal = globalIdx;
    this.lastLoggedSlideshowKey = key;
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
    // 详情打开时真正停表，关详情后再重新计时
    if (this.detailsVisible) {
      return;
    }
    // 视频播着时不按间隔切页，等播完或手动划走
    if (this.currentItemIsVideo()) {
      return;
    }
    this.slideshowTimerId = setTimeout((): void => {
      this.slideshowTimerId = -1;
      if (this.shouldPauseSlideshow()) {
        this.armSlideshowTimer();
        return;
      }
      if (this.currentItemIsVideo()) {
        return;
      }
      this.advanceSlideshow();
      this.armSlideshowTimer();
    }, this.slideshowIntervalMs);
  }

  /** 打开详情：清掉当前间隔，避免后台空转到期后又切页 */
  private pauseSlideshowForDetails(): void {
    this.clearSlideshowTimer();
  }

  /** 关闭详情：若视频已在详情里播完则立刻切页，否则重新开始当前间隔 */
  private resumeSlideshowAfterDetails(): void {
    if (!this.slideshowEnabled) {
      return;
    }
    if (this.slideshowAdvancePending) {
      this.slideshowAdvancePending = false;
      this.advanceSlideshow();
    }
    this.armSlideshowTimer();
  }

  private onSlideshowVideoEnded(): void {
    if (!this.slideshowEnabled) {
      return;
    }
    if (this.shouldPauseSlideshow()) {
      this.slideshowAdvancePending = true;
      return;
    }
    this.advanceSlideshow();
    this.armSlideshowTimer();
  }

  aboutToDisappear(): void {
    this.clearSlideshowTimer();
    this.clearSlideshowPrefetchTimer();
    this.clearChromeRevealTimer();
    this.slideshowAdvancePending = false;
    this.detailsVisible = false;
    resetGalleryPreviewDetailsFit();
    setGalleryPreviewDetailsCover(false);
    setGalleryPreviewDismissProgress(0);
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
    scheduleGalleryPreviewHeroInactive();
    setGalleryPreviewToolbarVisible(true);
    resetGalleryPreviewVideoChrome();
    void restoreGalleryPreviewPortrait(this.getUIContext());
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

  private clearChromeRevealTimer(): void {
    if (this.chromeRevealTimer < 0) {
      return;
    }
    clearTimeout(this.chromeRevealTimer);
    this.chromeRevealTimer = -1;
  }

  private armChromeReveal(): void {
    this.clearChromeRevealTimer();
    if (this.slideshowEnabled) {
      setGalleryPreviewToolbarVisible(false);
      return;
    }
    setGalleryPreviewToolbarVisible(false);
    this.chromeRevealTimer = setTimeout((): void => {
      this.chromeRevealTimer = -1;
      setGalleryPreviewToolbarVisible(true);
    }, GALLERY_SHARED_TRANSITION_DURATION);
  }

  private playHeroScrimEnterIfNeeded(): void {
    if (this.slideshowEnabled || this.heroScrimEntered) {
      return;
    }
    this.heroScrimEntered = true;
    this.getUIContext().animateTo({
      duration: GALLERY_SCRIM_FADE_DURATION,
      delay: GALLERY_SCRIM_FADE_DELAY,
      curve: GALLERY_SHARED_TRANSITION_CURVE
    }, (): void => {
      this.scrimOpacity = 1;
    });
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

  private currentIsLivePhoto(): boolean {
    const item = this.currentItem();
    return item !== null && isLivePhotoItem(item);
  }

  private titleCounter(): string {
    if (this.slideshowEnabled && this.slideshowLibraryTotal > 0) {
      const globalIdx = this.slideshowGlobalIndexAt(this.swiperIndex);
      if (globalIdx >= 0) {
        return galleryPreviewTitleCounter(globalIdx, this.slideshowLibraryTotal);
      }
      // 全局下标缺失时不要用播放队列序号冒充时间轴位置（会显示成 45/总数 顺延）
      return `- / ${this.slideshowLibraryTotal}`;
    }
    return galleryPreviewTitleCounter(this.swiperIndex, this.totalCount);
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

  private syncPreviewDetailsLayout(): void {
    this.animateDetailsHeight(this.detailsVisible ?
      galleryDetailsMediumHeightVp(this.previewViewportH) : 0);
  }

  private initPreviewViewportH(): void {
    try {
      const d = display.getDefaultDisplaySync();
      const h = this.getUIContext().px2vp(d.height);
      if (h > 1) {
        this.previewViewportH = h;
      }
    } catch (_e) {
    }
  }

  /**
   * 官方：自定义 createAnimator.onFrame 在 UI 线程算曲线会丢帧（最佳实践对比 9.2% vs 0）。
   * 只写一次终点高度，照片和页内详情分别在渲染线程使用同一弹簧插值。
   * 文档：bpta-fair-use-animation、arkts-attribute-animation-apis、arkts-spring-curve
   */
  private animateDetailsHeight(targetVp: number): void {
    const from = getGalleryPreviewDetailsSheetHeight();
    const to = Math.max(0, targetVp);
    if (Math.abs(this.detailsAvoidTargetVp - to) < 0.5 && isGalleryPreviewDetailsAvoidAnimating()) {
      return;
    }
    const delta = to - from;
    const absVel = takeGalleryPreviewDetailsAvoidVelocity();
    const normVel = Math.abs(delta) > 1 ? absVel / delta : 0;
    setGalleryPreviewDetailsFitNormVel(normVel);
    this.detailsAvoidTargetVp = to;
    setGalleryPreviewDetailsAvoidAnimating(true);
    setGalleryPreviewDetailsSheetHeight(to);
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
    setGalleryPreviewDetailsCover(true);
    // 详情不是退出手势，遮罩必须保持完全不透明，否则半模态上方会露出图库快照。
    setGalleryPreviewDismissProgress(0);
    galleryPreviewOpenDetailsPanel(this.asActionsHost());
  }

  private revealPreviewChrome(): void {
    setGalleryPreviewDetailsCover(false);
    setGalleryPreviewDismissProgress(0);
    setGalleryPreviewToolbarVisible(true);
  }

  private closeDetailsPanel(): void {
    this.revealPreviewChrome();
    galleryPreviewCloseDetailsPanel(this.asActionsHost());
  }

  private openFolderFromDetailPath(): void {
    galleryPreviewOpenFolderFromDetailPath(this.asActionsHost());
  }

  private async onPersonInPhotoClick(p: PersonInPhotoItem): Promise<void> {
    await galleryPreviewOnPersonInPhotoClick(this.asActionsHost(), p);
  }

  private askChoice(title: string, buttons: string[]): Promise<number> {
    if (this.choiceSheetVisible) {
      return Promise.resolve(-1);
    }
    return new Promise<number>((resolve: (index: number) => void) => {
      this.choiceSheetTitle = title;
      this.choiceSheetButtons = buttons;
      this.choiceSheetResolver = resolve;
      this.choiceSheetVisible = true;
    });
  }

  private completeChoice(index: number): void {
    const resolver = this.choiceSheetResolver;
    this.choiceSheetResolver = undefined;
    this.choiceSheetVisible = false;
    if (resolver !== undefined) {
      resolver(index);
    }
  }

  private askLivePhotoSave(): Promise<LivePhotoSaveChoice> {
    return askLivePhotoSaveChoice(
      (title: string, buttons: string[]): Promise<number> => this.askChoice(title, buttons),
      (): Promise<boolean> => this.askLivePhotoPrivilege()
    );
  }

  private askLivePhotoPrivilege(): Promise<boolean> {
    if (this.liveSaveSheetVisible) {
      return Promise.resolve(false);
    }
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      this.liveSaveResolver = (choice: LivePhotoSaveChoice): void => {
        resolve(choice === 'privilege');
      };
      this.liveSaveSheetVisible = true;
    });
  }

  private completeLivePhotoSave(choice: LivePhotoSaveChoice): void {
    const resolver = this.liveSaveResolver;
    this.liveSaveResolver = undefined;
    this.liveSaveSheetVisible = false;
    if (resolver !== undefined) {
      resolver(choice);
    }
  }

  private downloadCurrentImage(): void {
    galleryPreviewDownloadCurrentImage(this.asActionsHost(), false);
  }

  private onDownloadTapped(): void {
    if (this.downloading || this.liveSaveSheetVisible || this.choiceSheetVisible) {
      return;
    }
    if (this.currentIsLivePhoto()) {
      void this.downloadLiveWithMenu();
      return;
    }
    this.downloadCurrentImage();
  }

  private async downloadLiveWithMenu(): Promise<void> {
    const choice = await this.askLivePhotoSave();
    if (choice === 'cancel') {
      return;
    }
    galleryPreviewDownloadCurrentImage(this.asActionsHost(), choice === 'privilege');
  }

  @Builder
  private liveSaveSheetBuilder() {
    LivePhotoSaveActionSheet({
      onSelect: (choice: LivePhotoSaveChoice): void => {
        this.completeLivePhotoSave(choice);
      }
    })
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
        const wasVisible = self.detailsVisible;
        self.detailsVisible = v;
        self.syncPreviewDetailsLayout();
        if (!self.slideshowEnabled || wasVisible === v) {
          return;
        }
        if (v) {
          self.pauseSlideshowForDetails();
        } else {
          self.resumeSlideshowAfterDetails();
        }
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
      askChoice(title: string, buttons: string[]): Promise<number> { return self.askChoice(title, buttons); }
    }
    return new PreviewActionsHostBridge();
  }

  @Builder
  private choiceSheetBuilder() {
    FnHdsChoiceSheet({
      buttons: this.choiceSheetButtons,
      onSelect: (index: number): void => {
        this.completeChoice(index);
      }
    })
  }

  build() {
    Stack() {
      // 上滑详情或静止预览时的稳定底色，确保上一级页面绝不会穿透。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.pageBg())
        .hitTestBehavior(HitTestMode.None)

      if (!this.slideshowEnabled && this.sourcePageSnapshot !== undefined) {
        // 快照始终保留在遮罩下方；下滑只降低遮罩透明度即可稳定露出原页面。
        // 上滑时 dismissProgress 固定为 0，完全不透明的遮罩会继续盖住快照。
        Image(this.sourcePageSnapshot)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .syncLoad(true)
          .draggable(false)
          .hitTestBehavior(HitTestMode.None)

        if (this.sourcePlaceholderW > 0 && this.sourcePlaceholderH > 0) {
          // 官方一镜到底：底图中的源位置为空，只保留上层共享元素这一张图片。
          Column()
            .width(this.sourcePlaceholderW)
            .height(this.sourcePlaceholderH)
            .position({ x: this.sourcePlaceholderX, y: this.sourcePlaceholderY })
            .backgroundColor(this.pageBg())
            .hitTestBehavior(HitTestMode.None)
        }
      }

      GalleryPreviewScrim({
        color: this.pageBg(),
        baseOpacity: this.scrimOpacity
      })

      if (this.totalCount > 0) {
        Swiper(this.swiperCtrl) {
          LazyForEach(this.itemSource, (item: GalleryListItem, idx: number) => {
            GalleryPreviewSlide({
              baseUrl: this.baseUrl,
              item: item,
              loadOriginalToken: this.loadOriginalToken,
              originalPreviewEnabled: idx === this.swiperIndex && this.originalPreviewEnabled,
              active: idx === this.swiperIndex,
              enableSharedTransition: !this.slideshowEnabled,
              autoStartVideo: this.slideshowEnabled,
              videoBottomPadding: this.videoControlsBottomPadding(),
              detailsShowing: this.detailsVisible,
              allowVerticalGesture: true,
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
              onVerticalDismiss: (): void => {
                if (this.detailsVisible) {
                  this.closeDetailsPanel();
                  return;
                }
                this.navigateBack();
              },
              onVerticalDetails: (): void => {
                this.openDetailsPanel();
              },
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
              },
              onSlideshowVideoEnded: (): void => {
                this.onSlideshowVideoEnded();
              }
            })
          }, (item: GalleryListItem, i: number) => {
            const key = gallerySlideshowStableItemKey(item);
            return key.length > 0 ? `gp_${key}_${i}` : `gp_${i}`;
          })
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
        .backgroundColor(Color.Transparent)
        .id('gallery_preview_swiper')
        .onClick((): void => {
          // 详情已经改为页内面板，不再有系统 bindSheet 蒙层代为关闭。
          // 此时点击上方图片应优先收回详情，关闭后下一次点击再恢复工具栏切换行为。
          if (this.detailsVisible) {
            this.closeDetailsPanel();
            return;
          }
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
          setGalleryPreviewDismissProgress(0);
          this.originalPreviewEnabled = false;
          this.originalShowing = false;
          setGalleryPreviewToolbarVisible(!this.slideshowEnabled);
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
          if (this.detailsVisible) {
            this.openDetailsPanel();
          }
          if (this.slideshowEnabled) {
            this.logSlideshowPage();
            this.armSlideshowTimer();
            this.scheduleSlideshowPrefetch();
          }
        })
        .onAreaChange((_old, area): void => {
          const h = area.height as number;
          if (h > 1 && Math.abs(h - this.previewViewportH) > 0.5) {
            this.previewViewportH = h;
          }
        })
      } else {
        FnStateText({
          text: '暂无预览',
          topOffsetVp: this.systemTopInsetVp + FN_FLOATING_TOP_TOTAL_HEIGHT_VP
        })
      }

      GalleryPreviewInlineDetails({
        expandedHeight: galleryDetailsMediumHeightVp(this.previewViewportH),
        visible: this.detailsVisible,
        panelBg: this.pageBg(),
        detailsLoading: this.detailsLoading,
        detailsError: this.detailsError,
        detailsData: this.detailsData,
        personsInPhoto: this.personsInPhoto,
        folderOpening: this.folderOpening,
        personOpening: this.personOpening,
        onClose: (): void => {
          this.closeDetailsPanel();
        },
        onPersonClick: (p: PersonInPhotoItem): void => {
          void this.onPersonInPhotoClick(p);
        },
        onFolderClick: (): void => {
          this.openFolderFromDetailPath();
        }
      })

      GalleryPreviewChrome({
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
          this.onDownloadTapped();
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

      Column()
        .width(1)
        .height(1)
        .bindSheet(this.liveSaveSheetVisible, this.liveSaveSheetBuilder, fnHdsSaveButtonSheetOptions(
          LIVE_PHOTO_PRIVILEGE_SHEET_TITLE,
          (): void => {
            this.completeLivePhotoSave('cancel');
          }
        ))
      Column()
        .width(1)
        .height(1)
        .bindSheet(this.choiceSheetVisible, this.choiceSheetBuilder, fnHdsFitContentSheetOptions(
          this.choiceSheetTitle,
          (): void => {
            this.completeChoice(-1);
          }
        ))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    if (this.slideshowEnabled || GalleryPreviewNavStore.slideshow.enabled) {
      PageTransitionEnter({ duration: FN_PREVIEW_PAGE_ENTER_DURATION, curve: FN_PREVIEW_PAGE_ENTER_CURVE })
        .opacity(0)
        .scale({ x: 0.95, y: 0.95 })
      PageTransitionExit({ duration: FN_PREVIEW_PAGE_EXIT_DURATION, curve: FN_PREVIEW_PAGE_EXIT_CURVE })
        .opacity(0)
        .scale({ x: 0.95, y: 0.95 })
    } else {
      // 官方一镜到底：页面本身 None/0，位置与大小只由 sharedTransition 驱动
      PageTransitionEnter({ type: RouteType.None, duration: 0 })
      PageTransitionExit({ type: RouteType.None, duration: 0 })
    }
  }
}

/**
 * 系统相册式页内详情：与照片处于同一个 Stack，不使用系统半模态。
 * 面板高度和照片让位共用全局详情高度，因此跟手、松手吸附和返回动画不会产生缝隙。
 */
@Component
struct GalleryPreviewInlineDetails {
  @Prop expandedHeight: number = 0;
  @Prop visible: boolean = false;
  @Prop panelBg: ResourceColor = Color.White;
  @Prop detailsLoading: boolean = false;
  @Prop detailsError: string = '';
  @Prop detailsData: GalleryPhotoDetailData | undefined = undefined;
  @Prop personsInPhoto: PersonInPhotoItem[] = [];
  @Prop folderOpening: boolean = false;
  @Prop personOpening: boolean = false;
  onClose: () => void = () => {};
  onPersonClick: (p: PersonInPhotoItem) => void = (_p: PersonInPhotoItem): void => {};
  onFolderClick: () => void = () => {};

  private translateUpdater: GalleryPreviewTranslateYUpdater = new GalleryPreviewTranslateYUpdater();
  private dragStartHeight: number = 0;
  private readonly onDetailsHeightChanged = (): void => {
    this.syncPanelPosition();
  };

  aboutToAppear(): void {
    addGalleryPreviewDetailsFitListener(this.onDetailsHeightChanged);
    this.syncPanelPosition(false);
  }

  aboutToDisappear(): void {
    removeGalleryPreviewDetailsFitListener(this.onDetailsHeightChanged);
  }

  private syncPanelPosition(allowAnimation: boolean = true): void {
    const height = Math.max(0, Math.min(this.expandedHeight, getGalleryPreviewDetailsSheetHeight()));
    const targetY = this.expandedHeight - height;
    if (!allowAnimation || !isGalleryPreviewDetailsAvoidAnimating()) {
      this.translateUpdater.apply(targetY);
      return;
    }
    const velocity = getGalleryPreviewDetailsFitNormVel();
    const curve = Math.abs(velocity) > 0.02 ?
      curves.interpolatingSpring(
        velocity,
        1,
        GALLERY_SHEET_SPRING_STIFFNESS,
        GALLERY_SHEET_SPRING_DAMPING
      ) :
      curves.springMotion(0.347, 1.0, 0.25);
    this.getUIContext().animateTo({
      curve: curve,
      expectedFrameRateRange: GALLERY_ANIMATOR_FRAME_RATE
    }, (): void => {
      this.translateUpdater.apply(targetY);
    });
  }

  private beginHeaderDrag(): void {
    this.dragStartHeight = getGalleryPreviewDetailsSheetHeight();
    setGalleryPreviewDetailsAvoidAnimating(false);
  }

  private updateHeaderDrag(offsetY: number): void {
    const next = Math.max(0, Math.min(this.expandedHeight, this.dragStartHeight - offsetY));
    setGalleryPreviewDetailsSheetHeight(next);
  }

  private finishHeaderDrag(velocityY: number): void {
    const current = getGalleryPreviewDetailsSheetHeight();
    if (current < this.expandedHeight * 0.72 || velocityY > GALLERY_VERTICAL_VELOCITY_THRESHOLD) {
      setGalleryPreviewDetailsAvoidVelocity(-Math.max(0, velocityY));
      this.onClose();
      return;
    }
    const delta = this.expandedHeight - current;
    const heightVelocity = -velocityY;
    setGalleryPreviewDetailsFitNormVel(Math.abs(delta) > 1 ? heightVelocity / delta : 0);
    setGalleryPreviewDetailsAvoidAnimating(true);
    setGalleryPreviewDetailsSheetHeight(this.expandedHeight);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.visible) {
        // 页内详情没有系统 Sheet 蒙层，显式覆盖上方图片区：
        // 单击直接收回；下滑与面板标题共用同一高度状态，保持照片让位和面板移动同步跟手。
        // 详情固定占视口 60%，因此剩余图片区为顶部 40%；底部内容面板后绘制，不受该层影响。
        Column()
          .width('100%')
          .height('40%')
          .position({ x: 0, y: 0 })
          .onClick((): void => {
            this.onClose();
          })
          .gesture(
            PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 2 })
              .onActionStart((): void => {
                this.beginHeaderDrag();
              })
              .onActionUpdate((event: GestureEvent): void => {
                this.updateHeaderDrag(event.offsetY);
              })
              .onActionEnd((event: GestureEvent): void => {
                this.finishHeaderDrag(event.velocityY);
              })
              .onActionCancel((): void => {
                this.finishHeaderDrag(0);
              })
          )
      }

      Column() {
        Column()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor($r('app.color.text_secondary'))
          .opacity(0.45)
          .margin({ top: 8, bottom: 6 })

        Row() {
          Text('照片详情')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(44)
        .padding({ left: 16, right: 16 })
        .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 2 })
            .onActionStart((): void => {
              this.beginHeaderDrag();
            })
            .onActionUpdate((event: GestureEvent): void => {
              this.updateHeaderDrag(event.offsetY);
            })
            .onActionEnd((event: GestureEvent): void => {
              this.finishHeaderDrag(event.velocityY);
            })
            .onActionCancel((): void => {
              this.finishHeaderDrag(0);
            })
        )

        GalleryPreviewDetailsSheet({
          detailsLoading: this.detailsLoading,
          detailsError: this.detailsError,
          detailsData: this.detailsData,
          personsInPhoto: this.personsInPhoto,
          folderOpening: this.folderOpening,
          personOpening: this.personOpening,
          onPersonClick: this.onPersonClick,
          onFolderClick: this.onFolderClick
        })
          .layoutWeight(1)
      }
      .width('100%')
      .height(this.expandedHeight)
      .backgroundColor(this.panelBg)
      .attributeModifier(this.translateUpdater)
      .enabled(this.visible)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

@Component
struct GalleryPreviewScrim {
  @Prop color: ResourceColor = Color.Black;
  @Prop @Watch('onScrimInputsChanged') baseOpacity: number = 0;
  private opacityUpdater: GalleryPreviewOpacityUpdater = new GalleryPreviewOpacityUpdater();
  private readonly onDismissProgress = (_progress: number): void => {
    this.applyScrimOpacity();
  };

  aboutToAppear(): void {
    addGalleryPreviewDismissListener(this.onDismissProgress);
    this.applyScrimOpacity();
  }

  aboutToDisappear(): void {
    removeGalleryPreviewDismissListener(this.onDismissProgress);
  }

  onScrimInputsChanged(): void {
    this.applyScrimOpacity();
  }

  private applyScrimOpacity(): void {
    const opacity = this.baseOpacity * (1 - getGalleryPreviewDismissProgress());
    this.opacityUpdater.apply(opacity);
  }

  build() {
    Column()
    .width('100%')
    .height('100%')
    .backgroundColor(this.color)
    .attributeModifier(this.opacityUpdater)
    .hitTestBehavior(HitTestMode.None)
  }
}
