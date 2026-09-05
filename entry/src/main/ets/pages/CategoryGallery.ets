/**
 * 媒体分类浏览页：展示某一分类（照片/视频/动图等）内所有媒体，
 * 按日期降序分组，列数随窗口宽度断点变化；长按 + 滑动连选、批量下载/删除（与图库主时间线交互一致）。
 */
import { UIContext, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryListItem } from '../model/FnApiTypes';
import {
  GalleryNetworkThumb,
  isGifItem,
  isVideoItem,
  nasUrl,
  pickThumb,
  thumbIdentityOfItem,
  trimThumbPixCacheForList
} from '../album/GalleryAlbumCommon';
import { gallerySelectionContainsLive, isLivePhotoItem } from '../album/livephoto/LivePhotoDetect';
import {
  askLivePhotoSaveChoice,
  LivePhotoSaveActionSheet,
  LivePhotoSaveChoice,
  LIVE_PHOTO_PRIVILEGE_SHEET_TITLE
} from '../album/livephoto/LivePhotoSaveActionSheet';
import { FnHdsChoiceSheet, fnHdsFitContentSheetOptions, fnHdsSaveButtonSheetOptions } from '../common/FnHdsOverlay';
import { galleryItemsMatchingSelectedIds } from '../album/GalleryBatchDownload';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import { GalleryPreviewNavStore } from '../album/GalleryPreviewNavStore';
import { GALLERY_PREVIEW_OPENING_KEY } from '../album/GalleryPreviewEntryGate';
import {
  GALLERY_PREVIEW_HERO_ACTIVE_KEY,
  GALLERY_PREVIEW_SOURCE_CATEGORY_ID,
  gallerySharedTransitionId
} from '../album/GallerySharedTransition';
import { GalleryPreviewOpeningMask } from '../album/GalleryPreviewOpeningMask';
import { GalleryAlbumNavigation } from '../album/GalleryAlbumNavigation';
import { gallerySlideAutoScrollOnListDidScroll } from '../album/GallerySlideAutoScroll';
import { GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE } from '../album/GallerySlidePick';
import {
  galleryGridArmInitialSlide,
  galleryGridCanStartSecondaryPan,
  galleryGridClearInitialSlide,
  galleryGridHandleListTouch,
  galleryGridHandleRowTouch,
  galleryGridOnSecondaryPanFinish,
  galleryGridOnSecondaryPanStart,
  galleryGridOnSequenceLongPress,
  galleryGridOnSequencePanFinish,
  galleryGridResetTouchTracking,
  galleryGridSlideLog,
  galleryGridShouldUpdateSecondaryPan,
  galleryGridShouldUpdateSequencePan,
  GalleryGridSlideTouchHost,
  GalleryGridSlideTouchSession,
  GALLERY_GRID_SEQUENCE_LONG_PRESS_MS
} from '../album/GalleryGridSlideTouch';
import { AppSession, FN_MEDIA_BASE_URL } from '../auth/AppSession';
import { FnListDataSource } from '../common/FnListDataSource';
import {
  FN_WINDOW_WIDTH_BP_KEY,
  fnAdaptiveGridColumns,
  fnClampGridColumns,
  fnGridColumnIndexes
} from '../common/FnWindowBreakpoint';
import { fnApplyImmersiveSystemBarColors } from '../common/FnSplashTheme';
import { FN_SYSTEM_TOP_INSET_VP_KEY, fnPublishSystemAvoidArea } from '../common/FnSystemAvoidArea';
import { FnFullLoadingMask, FnStateText } from '../common/FnUiCommon';
import { GALLERY_BATCH_BAR_TOTAL_HEIGHT_VP } from '../common/GalleryButtonStyles';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import { GalleryAlbumBatchActionBar } from '../album/GalleryAlbumBatchActionBar';
import {
  GALLERY_SELECTION_SCOPE_CATEGORY,
  GalleryAlbumSelectionOverlay,
  galleryAlbumSyncSelectionVisualState
} from '../album/galleryAlbumTab/GalleryAlbumSelectionOverlay';
import {
  categoryGalleryApplyDeleteSyncIfNeeded,
  categoryGalleryConfirmBatchDelete,
  categoryGalleryConfirmBatchDownload,
  categoryGalleryRebuildByFlatItems,
  CategoryGalleryBatchActionsHost
} from './categoryGallery/CategoryGalleryBatchActions';
import { CategoryGalleryChrome } from './categoryGallery/CategoryGalleryChrome';
import {
  gallerySlideshowLaunchForItems,
  gallerySlideshowLaunchForPerson,
  gallerySlideshowLaunchForSmartCategory
} from '../album/slideshow/GallerySlideshowLauncher';
import {
  GallerySlideshowConfig,
  GallerySlideshowScope,
  GallerySlideshowScopeKind,
  gallerySlideshowScopeLabel
} from '../album/slideshow/GallerySlideshowTypes';
import { GallerySlideshowSettingsSheet } from '../album/slideshow/GallerySlideshowSettingsSheet';
import {
  categoryGalleryBeginSlideSelectGesture,
  categoryGalleryBeginSlideSelectGestureAtWindowPx,
  CATEGORY_GALLERY_LIST_DOM_ID,
  categoryGalleryDomId,
  categoryGalleryEndSlideSelectGesture,
  categoryGalleryExitSelection,
  categoryGalleryFlatPos,
  categoryGalleryItemIdOf,
  categoryGalleryOnCellClick,
  categoryGalleryOnSlidePanUpdate,
  categoryGalleryOnSlideTouchMoveWindow,
  categoryGalleryOnThumbLongPress,
  categoryGalleryPickFlatForRow,
  categoryGalleryReadGestureFingerWindow,
  categoryGalleryRecordThumbRect,
  categoryGalleryRowGlobalStartFlat,
  categoryGalleryToggleToolbarMode,
  CategoryGallerySelectionHost
} from './categoryGallery/CategoryGallerySelectionController';
import {
  buildCategoryGalleryViewData,
  CgThumbHitRect,
  DayGroup,
  RowModel
} from './categoryGallery/CategoryGalleryTypes';

interface CategoryGalleryListBlock {
  key: string;
  isHeader: boolean;
  groupIdx: number;
  label?: string;
  row?: RowModel;
}

const CATEGORY_GALLERY_CONTENT_INSET_TOP_VP: number = 68;
const CATEGORY_GALLERY_BACKGROUND_APPEND_BATCH_ITEMS: number = 240;
const CATEGORY_GALLERY_STORE_SYNC_INTERVAL_MS: number = 96;
const CATEGORY_GALLERY_RECENT_STREAM_DEFER_MS: number = 160;
const CATEGORY_GALLERY_RECENT_STREAM_MIN_APPEND_DELTA: number = 288;
const CATEGORY_GALLERY_RECENT_STREAM_MIN_APPLY_GAP_MS: number = 180;
const CATEGORY_GALLERY_RECENT_STREAM_IDLE_RESUME_MS: number = 180;
const DOMAIN = 0xFF00;
const TAG = 'GalleryDiag';

@Entry
@Component
struct CategoryGallery {
  /** aboutToAppear 时根据 Home 的 NavPathStack 是否挂载自动判断，避免 @Entry 使用 @Prop。 */
  private albumNavigationMode: boolean = false;
  @State private groups: DayGroup[] = [];
  @State private title: string = '';
  @StorageProp(FN_MEDIA_BASE_URL) private baseUrl: string = '';
  @State private totalCount: number = 0;
  @State private heroImageUri: string = '';
  @State private columnsPerRow: number = 3;
  @StorageProp(FN_WINDOW_WIDTH_BP_KEY) @Watch('onWindowWidthBpChanged') private windowWidthBp: number =
    WidthBreakpoint.WIDTH_SM;
  private baseColumnsPerRow: number = 3;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @State private isDarkTheme: boolean = false;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(GALLERY_PREVIEW_OPENING_KEY) private previewOpening: boolean = false;
  @StorageProp(GALLERY_PREVIEW_HERO_ACTIVE_KEY) private previewHeroActive: boolean = false;
  private flatItems: GalleryListItem[] = [];
  private groupOffsets: number[] = [];
  private handledDeleteSyncVersion: number = 0;

  @State private selectionMode: boolean = false;
  private selectedIds: string[] = [];
  @State private selectedCount: number = 0;
  @State private cgSlideGestureActive: boolean = false;
  @State private cgScrollEnabled: boolean = true;
  @State private cgBatchDeleting: boolean = false;
  @State private cgBatchDownloading: boolean = false;
  @State private selectionHasLivePhoto: boolean = false;
  @State private liveSaveSheetVisible: boolean = false;
  @State private choiceSheetVisible: boolean = false;
  @State private choiceSheetTitle: string = '';
  @State private choiceSheetButtons: string[] = [];
  @State private cgThumbLoadingPaused: boolean = false;
  @State private cgBackgroundLoading: boolean = false;
  @State private moreMenuExpanded: boolean = false;
  @State private slideshowSettingsVisible: boolean = false;
  @State private slideshowPreparing: boolean = false;

  private cgLongPressIgnoreUntil: number = 0;
  /** 官方顶栏 bindToScrollable 联动沉浸滚动光感所需的 Scroller。 */
  private listScroller: Scroller = new Scroller();
  private listBlocks: Array<CategoryGalleryListBlock> = [];
  private listBlockSource: FnListDataSource<CategoryGalleryListBlock> =
    new FnListDataSource<CategoryGalleryListBlock>();
  private cgThumbHitBounds: Map<string, CgThumbHitRect> = new Map();
  private cgSlideRefX: number = 0;
  private cgSlideRefY: number = 0;
  private cgSlideHasRef: boolean = false;
  private cgSlideAnchorFlat: number = -1;
  private cgSlideUnionBase: string[] = [];
  private cgSlideLastEndFlat: number = -1;
  private cgSlideLastAppliedEndFlat: number = -99999;
  private cgObservedStoreVersion: number = -1;
  private cgPendingStoreSync: boolean = false;
  private cgStorePollTimer: number = -1;
  private cgThumbResumeTimer: number = -1;
  private cgDeferredBackgroundLoadTimer: number = -1;
  private cgDeferredSnapshotApplyTimer: number = -1;
  private cgLastSnapshotApplyAtMs: number = 0;
  /**
   * 页面活动标记必须使用普通字段，不能使用 @State。
   * 它只用于阻止已排入事件队列的定时器/网络回调在组件销毁后继续修改响应式状态。
   */
  private cgPageActive: boolean = false;
  /** 与主时间线共用的划选触摸会话，首次长按松手也必须能解锁滚动 */
  private slideTouch: GalleryGridSlideTouchSession = new GalleryGridSlideTouchSession();
  /** 本页打开时的会话 token，仅同步属于自己的 NavStore 更新。 */
  private pageSessionToken: number = -1;
  private pageSourceKind: string = '';
  private pageCategoryKey: string = '';
  private pageUseCreatedAtGrouping: boolean = false;
  private slideshowRequestSeq: number = 0;
  private albumBackHandlerToken: number = 0;

  private recycleThumbCache(aggressive: boolean = false): void {
    const recentAddedAggressive = this.isRecentAddedStreamingMode() &&
      (aggressive || this.cgBackgroundLoading || this.flatItems.length > 360);
    trimThumbPixCacheForList(this.flatItems.length, aggressive || recentAddedAggressive);
  }

  onBackPress(): boolean {
    this.navigateBack();
    return true;
  }

  onPageHide(): void {
    this.cgPageActive = false;
    this.stopStoreObserver();
    this.clearCgThumbResumeTimer();
    this.clearCgDeferredBackgroundLoadTimer();
    this.clearCgDeferredSnapshotApplyTimer();
  }

  private navigateBack(): void {
    if (this.choiceSheetVisible) {
      this.completeChoice(-1);
      return;
    }
    if (this.liveSaveSheetVisible) {
      this.completeLivePhotoSave('cancel');
      return;
    }
    if (this.slideshowSettingsVisible) {
      this.dismissSlideshowSettings();
      return;
    }
    if (this.moreMenuExpanded) {
      this.dismissMoreMenu();
      return;
    }
    if (this.selectionMode) {
      this.exitCgSelection();
      return;
    }
    if (!this.albumNavigationMode || !GalleryAlbumNavigation.pop()) {
      this.getUIContext().getRouter().back();
    }
  }

  private usesMoreMenuMode(): boolean {
    // 分类子页统一走「更多」：多选 + 幻灯片，幻灯片只播本页列表
    return true;
  }

  private dismissMoreMenu(): void {
    if (!this.moreMenuExpanded) {
      return;
    }
    this.moreMenuExpanded = false;
  }

  private toggleMoreMenu(): void {
    this.moreMenuExpanded = !this.moreMenuExpanded;
  }

  private enterMultiselectFromMoreMenu(): void {
    this.dismissMoreMenu();
    if (!this.selectionMode) {
      this.toggleToolbarMode();
    }
  }

  private openSlideshowSettings(): void {
    this.dismissMoreMenu();
    if (!this.canStartCategorySlideshow()) {
      this.toast('暂无可播放媒体');
      return;
    }
    this.slideshowSettingsVisible = true;
  }

  private dismissSlideshowSettings(): void {
    this.slideshowSettingsVisible = false;
  }

  /** 已画到屏幕上的列表；媒体分类等续拉场景只作兜底，不能当人物/搜索的全集 */
  private categorySlideshowItems(): GalleryListItem[] {
    if (this.pageSessionToken === CategoryGalleryNavStore.currentToken()) {
      const storeItems = CategoryGalleryNavStore.items;
      if (storeItems.length > this.flatItems.length) {
        return storeItems;
      }
    }
    return this.flatItems;
  }

  private categorySlideshowScope(): GallerySlideshowScope {
    if (this.pageSessionToken === CategoryGalleryNavStore.currentToken()) {
      if (CategoryGalleryNavStore.sourceKind === 'person') {
        const personId = CategoryGalleryNavStore.personId.trim();
        if (personId.length > 0) {
          return {
            kind: GallerySlideshowScopeKind.PERSON_ALBUM,
            personId: personId,
            personName: this.title
          };
        }
      }
      if (CategoryGalleryNavStore.sourceKind === 'smart-category') {
        const storedKw = CategoryGalleryNavStore.smartCategoryKeyword.trim();
        const keyword = storedKw.length > 0 ? storedKw : this.title.trim();
        if (keyword.length > 0) {
          return {
            kind: GallerySlideshowScopeKind.SMART_CATEGORY,
            smartCategoryKeyword: keyword
          };
        }
      }
    }
    return {
      kind: GallerySlideshowScopeKind.FLAT_ITEMS,
      scopeLabel: this.title
    };
  }

  private canStartCategorySlideshow(): boolean {
    const scope = this.categorySlideshowScope();
    if (scope.kind === GallerySlideshowScopeKind.PERSON_ALBUM) {
      return true;
    }
    if (scope.kind === GallerySlideshowScopeKind.SMART_CATEGORY) {
      return true;
    }
    return this.categorySlideshowItems().length > 0 || this.pageCategoryKey.length > 0;
  }

  private sleepMs(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }

  /** 媒体分类 / 最近添加等：等本页后台续拉结束，再拿场景内完整列表 */
  private async waitForCategorySceneItems(isActive: () => boolean): Promise<void> {
    this.ensureCategoryBackgroundLoad();
    let spins = 0;
    while (isActive() && spins < 6000) {
      if (this.pageSessionToken !== CategoryGalleryNavStore.currentToken()) {
        return;
      }
      if (!CategoryGalleryNavStore.backgroundLoading && !CategoryGalleryNavStore.hasPrefetchedRemainder()) {
        return;
      }
      await this.sleepMs(80);
      spins++;
    }
  }

  private async startCategorySlideshow(config: GallerySlideshowConfig): Promise<void> {
    if (this.slideshowPreparing || !this.canStartCategorySlideshow()) {
      return;
    }
    this.slideshowPreparing = true;
    const seq = ++this.slideshowRequestSeq;
    const isActive = (): boolean => seq === this.slideshowRequestSeq;
    const scope = this.categorySlideshowScope();
    const toast = (msg: string): void => {
      this.toast(msg);
    };
    try {
      if (scope.kind === GallerySlideshowScopeKind.PERSON_ALBUM) {
        const personId = scope.personId !== undefined ? scope.personId : '';
        const personName = scope.personName !== undefined ? scope.personName : this.title;
        await gallerySlideshowLaunchForPerson(
          this.getUIContext(),
          this.baseUrl,
          personId,
          personName,
          config,
          toast,
          isActive
        );
      } else if (scope.kind === GallerySlideshowScopeKind.SMART_CATEGORY) {
        const keyword = scope.smartCategoryKeyword !== undefined ? scope.smartCategoryKeyword : this.title;
        // 不传当前页截断列表，按关键词重拉该分类全集
        await gallerySlideshowLaunchForSmartCategory(
          this.getUIContext(),
          this.baseUrl,
          keyword,
          config,
          toast,
          isActive
        );
      } else {
        await this.waitForCategorySceneItems(isActive);
        if (!isActive()) {
          return;
        }
        await gallerySlideshowLaunchForItems(
          this.getUIContext(),
          this.baseUrl,
          this.categorySlideshowItems(),
          config,
          toast,
          isActive,
          this.title
        );
      }
      if (isActive()) {
        this.slideshowSettingsVisible = false;
      }
    } finally {
      if (isActive()) {
        this.slideshowPreparing = false;
      }
    }
  }

  private vpToPx(value: number): number {
    try {
      return this.getUIContext().vp2px(value);
    } catch (_e) {
      return value;
    }
  }

  private contentInsetTopVp(): number {
    // 顶栏高度与多选无关；不要绑 selectionMode，避免进多选时改 List.margin 把触摸掐断
    return this.systemTopInsetVp + CATEGORY_GALLERY_CONTENT_INSET_TOP_VP;
  }

  private isRecentAddedStreamingMode(): boolean {
    return this.pageUseCreatedAtGrouping && this.pageCategoryKey.length === 0;
  }

  private emptyStateText(): string {
    if (this.pageSourceKind === 'collect') {
      return '收藏夹为空';
    }
    if (this.pageSourceKind === 'recent') {
      return '最近添加为空';
    }
    return '暂无媒体';
  }

  private applySystemBar(relayout: boolean): void {
    try {
      const dark = this.isDarkTheme;
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

  onPageShow(): void {
    this.cgPageActive = true;
    this.startStoreObserver();
    this.applyDeleteSyncIfNeeded();
    this.syncFromNavStore();
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar(true);
  }

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar(false);
  }

  aboutToAppear(): void {
    // 必须先恢复活动状态，后续快照应用和后台加载才允许更新页面。
    this.cgPageActive = true;
    this.albumNavigationMode = GalleryAlbumNavigation.isAvailable();
    this.isDarkTheme = this.colorMode === 1;
    this.cgThumbLoadingPaused = false;
    this.applyNavStoreSnapshot();
    this.startStoreObserver();
    this.scheduleCategoryBackgroundLoad();
    // 自定义组件进入 NavDestination 时不会触发 Router 页级 onPageShow，需在这里补齐。
    if (this.albumNavigationMode) {
      this.applyDeleteSyncIfNeeded();
      this.syncFromNavStore();
      this.applySystemBar(true);
    }
    if (this.albumNavigationMode) {
      this.albumBackHandlerToken = GalleryAlbumNavigation.registerBackHandler((): boolean => {
        this.navigateBack();
        return true;
      });
    }
  }

  aboutToDisappear(): void {
    // 必须作为退出清理的第一步，封住已经进入事件队列、无法再由 clearTimeout 取消的回调。
    this.cgPageActive = false;
    GalleryAlbumNavigation.unregisterBackHandler(this.albumBackHandlerToken);
    this.slideshowRequestSeq++;
    this.stopStoreObserver();
    this.clearCgThumbResumeTimer();
    this.clearCgDeferredBackgroundLoadTimer();
    this.clearCgDeferredSnapshotApplyTimer();
    categoryGalleryEndSlideSelectGesture(this.asSelectionHost());
    galleryGridResetTouchTracking(this.slideTouch);
    galleryAlbumSyncSelectionVisualState(false, [], GALLERY_SELECTION_SCOPE_CATEGORY);
    this.recycleThumbCache(true);
    const client = AppSession.getClient();
    if (client !== null) {
      client.cancelPendingRequests();
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {}
  }

  private itemIdOf(it: GalleryListItem): string {
    return categoryGalleryItemIdOf(it);
  }

  private flatPos(groupIdx: number, idxInGroup: number): number {
    return categoryGalleryFlatPos(this.asSelectionHost(), groupIdx, idxInGroup);
  }

  private cgDomId(flatIdx: number): string {
    return categoryGalleryDomId(flatIdx);
  }

  private setSelectionModeState(value: boolean): void {
    if (this.selectionMode === value) {
      return;
    }
    this.selectionMode = value;
    galleryAlbumSyncSelectionVisualState(this.selectionMode, this.selectedIds, GALLERY_SELECTION_SCOPE_CATEGORY);
  }

  private setSelectedIdsState(value: string[]): void {
    this.selectedIds = value;
    const selected = galleryItemsMatchingSelectedIds(this.flatItems, this.selectedIds);
    this.selectionHasLivePhoto = gallerySelectionContainsLive(selected);
    galleryAlbumSyncSelectionVisualState(this.selectionMode, this.selectedIds, GALLERY_SELECTION_SCOPE_CATEGORY);
    if (this.selectedCount !== value.length) {
      this.selectedCount = value.length;
    }
  }

  private exitCgSelection(): void {
    categoryGalleryExitSelection(this.asSelectionHost());
  }

  private toggleToolbarMode(): void {
    if (!this.selectionMode) {
      this.dismissMoreMenu();
    }
    categoryGalleryToggleToolbarMode(this.asSelectionHost());
  }

  private recordCgThumbRect(flatIdx: number): void {
    categoryGalleryRecordThumbRect(this.asSelectionHost(), flatIdx);
  }

  private readGestureFingerWindow(ev: GestureEvent) {
    return categoryGalleryReadGestureFingerWindow(ev);
  }

  private asSlideTouchHost(): GalleryGridSlideTouchHost {
    const self = this;
    class CategoryGallerySlideTouchHostBridge implements GalleryGridSlideTouchHost {
      getUIContext(): UIContext { return self.getUIContext(); }
      isSelectionMode(): boolean { return self.selectionMode; }
      isSlideActive(): boolean { return self.cgSlideGestureActive; }
      endSlide(): void { self.endCgSlideSelectGesture(); }
      followSlideAtWindowPx(xPx: number, yPx: number): void { self.onCgSlideTouchMoveWindow(xPx, yPx); }
    }
    return new CategoryGallerySlideTouchHostBridge();
  }

  /** 未进多选的触摸/Sequence 长按：进入多选并按窗口坐标起划选 */
  private beginCgFirstSlideAtRow(groupIdx: number, row: RowModel, xPx: number, yPx: number): boolean {
    const rowStart = this.rowGlobalStartFlat(groupIdx, row);
    const fi = this.pickCgFlatForRow(rowStart, xPx, yPx);
    if (fi < 0 || fi >= this.flatItems.length) {
      return false;
    }
    const item = this.flatItems[fi];
    if (!this.selectionMode) {
      this.onCgThumbLongPress(item, fi);
    }
    this.beginCgSlideSelectGestureAtWindowPx(fi, xPx, yPx);
    return true;
  }

  private pickCgFlatForRow(rowStart: number, xPx: number, yPx: number): number {
    return categoryGalleryPickFlatForRow(this.asSelectionHost(), rowStart, xPx, yPx);
  }

  private beginCgSlideSelectGesture(ev: GestureEvent, anchorFlat: number): void {
    categoryGalleryBeginSlideSelectGesture(this.asSelectionHost(), ev, anchorFlat);
  }

  private beginCgSlideSelectGestureAtWindowPx(anchorFlat: number, xPx: number, yPx: number): void {
    categoryGalleryBeginSlideSelectGestureAtWindowPx(this.asSelectionHost(), anchorFlat, xPx, yPx);
  }

  private endCgSlideSelectGesture(): void {
    categoryGalleryEndSlideSelectGesture(this.asSelectionHost());
  }

  private onCgSlidePanUpdate(ev: GestureEvent): void {
    categoryGalleryOnSlidePanUpdate(this.asSelectionHost(), ev);
  }

  private onCgSlideTouchMoveWindow(xPx: number, yPx: number): void {
    categoryGalleryOnSlideTouchMoveWindow(this.asSelectionHost(), xPx, yPx);
  }

  private onCgThumbLongPress(item: GalleryListItem, flatIdx: number): void {
    categoryGalleryOnThumbLongPress(this.asSelectionHost(), item, flatIdx);
  }

  private openItemAtFlat(flatIdx: number): void {
    if (flatIdx < 0 || flatIdx >= this.flatItems.length) {
      return;
    }
    GalleryPreviewNavStore.openPreview(
      this.getUIContext(),
      this.baseUrl,
      this.flatItems,
      flatIdx,
      GALLERY_PREVIEW_SOURCE_CATEGORY_ID
    );
  }

  private onCgCellClick(item: GalleryListItem, flatIdx: number): void {
    categoryGalleryOnCellClick(this.asSelectionHost(), item, flatIdx);
  }

  private rowGlobalStartFlat(groupIdx: number, row: RowModel): number {
    return categoryGalleryRowGlobalStartFlat(this.asSelectionHost(), groupIdx, row);
  }

  private async confirmCgBatchDownload(): Promise<void> {
    await categoryGalleryConfirmBatchDownload(this.asBatchActionsHost());
  }

  private async confirmCgBatchDelete(): Promise<void> {
    await categoryGalleryConfirmBatchDelete(this.asBatchActionsHost());
  }

  private rebuildByFlatItems(): void {
    categoryGalleryRebuildByFlatItems(this.asBatchActionsHost());
    this.rebuildListBlocks();
    this.totalCount = Math.max(CategoryGalleryNavStore.expectedTotalCount, this.flatItems.length);
    if (this.heroImageUri.length === 0 && this.flatItems.length > 0) {
      this.heroImageUri = nasUrl(this.baseUrl, pickThumb(this.flatItems[0]));
    }
    this.recycleThumbCache(this.cgBackgroundLoading || this.flatItems.length > 720);
  }

  private applyDeleteSyncIfNeeded(): void {
    categoryGalleryApplyDeleteSyncIfNeeded(this.asBatchActionsHost());
  }

  private clearCgThumbResumeTimer(): void {
    if (this.cgThumbResumeTimer >= 0) {
      clearTimeout(this.cgThumbResumeTimer);
      this.cgThumbResumeTimer = -1;
    }
  }

  private clearCgDeferredBackgroundLoadTimer(): void {
    if (this.cgDeferredBackgroundLoadTimer >= 0) {
      clearTimeout(this.cgDeferredBackgroundLoadTimer);
      this.cgDeferredBackgroundLoadTimer = -1;
    }
  }

  private clearCgDeferredSnapshotApplyTimer(): void {
    if (this.cgDeferredSnapshotApplyTimer >= 0) {
      clearTimeout(this.cgDeferredSnapshotApplyTimer);
      this.cgDeferredSnapshotApplyTimer = -1;
    }
  }

  private scheduleCgDeferredSnapshotApply(delayMs: number = CATEGORY_GALLERY_RECENT_STREAM_DEFER_MS): void {
    if (!this.cgPageActive || !this.isRecentAddedStreamingMode()) {
      return;
    }
    this.clearCgDeferredSnapshotApplyTimer();
    this.cgDeferredSnapshotApplyTimer = setTimeout((): void => {
      this.cgDeferredSnapshotApplyTimer = -1;
      if (!this.cgPageActive) {
        return;
      }
      if (this.cgSlideGestureActive || this.cgThumbLoadingPaused) {
        this.cgPendingStoreSync = true;
        this.scheduleCgDeferredSnapshotApply(CATEGORY_GALLERY_RECENT_STREAM_DEFER_MS);
        return;
      }
      if (this.cgObservedStoreVersion === CategoryGalleryNavStore.version) {
        this.cgPendingStoreSync = false;
        return;
      }
      this.applyNavStoreSnapshot();
      if (!this.cgBackgroundLoading) {
        this.recycleThumbCache(false);
      }
    }, Math.max(48, Math.floor(delayMs)));
  }

  private buildListBlocks(): Array<CategoryGalleryListBlock> {
    const blocks: Array<CategoryGalleryListBlock> = [];
    for (let groupIdx = 0; groupIdx < this.groups.length; groupIdx++) {
      const group = this.groups[groupIdx];
      if (group.label.length > 0) {
        blocks.push({
          key: `h_${group.sortKey}`,
          isHeader: true,
          groupIdx: groupIdx,
          label: group.label
        });
      }
      for (let rowIdx = 0; rowIdx < group.rows.length; rowIdx++) {
        const row = group.rows[rowIdx];
        const cellKeys: string[] = [];
        const cols = fnClampGridColumns(this.columnsPerRow);
        for (let col = 0; col < cols; col++) {
          const item = this.rowCellAt(row, col);
          if (item === undefined) {
            cellKeys.push(`empty_${col}`);
            continue;
          }
          const id = this.itemIdOf(item);
          if (id.length > 0) {
            cellKeys.push(`id_${id}`);
            continue;
          }
          cellKeys.push(`flat_${this.flatPos(groupIdx, row.startIdx + col)}`);
        }
        blocks.push({
          key: `r_${group.sortKey}_${row.startIdx}_${cellKeys.join('__')}`,
          isHeader: false,
          groupIdx: groupIdx,
          row: row
        });
      }
    }
    return blocks;
  }

  private rebuildListBlocks(): void {
    this.listBlocks = this.buildListBlocks();
    this.listBlockSource.reloadAll(this.listBlocks);
  }

  private applyNavStoreSnapshot(): void {
    if (!this.cgPageActive) {
      return;
    }
    this.clearCgDeferredSnapshotApplyTimer();
    this.pageSessionToken = CategoryGalleryNavStore.sessionToken;
    this.pageSourceKind = CategoryGalleryNavStore.sourceKind;
    this.pageCategoryKey = CategoryGalleryNavStore.categoryKey;
    this.pageUseCreatedAtGrouping = CategoryGalleryNavStore.useCreatedAtGrouping;
    this.baseUrl = CategoryGalleryNavStore.baseUrl;
    this.title = CategoryGalleryNavStore.title;
    this.heroImageUri = CategoryGalleryNavStore.heroImageUri;
    this.baseColumnsPerRow = fnClampGridColumns(CategoryGalleryNavStore.columnsPerRow);
    this.columnsPerRow = this.resolvedColumns();
    this.flatItems = CategoryGalleryNavStore.items.slice();
    this.totalCount = Math.max(CategoryGalleryNavStore.expectedTotalCount, this.flatItems.length);
    this.cgBackgroundLoading = CategoryGalleryNavStore.backgroundLoading;
    this.rebuildByFlatItems();
    this.cgObservedStoreVersion = CategoryGalleryNavStore.version;
    this.cgPendingStoreSync = false;
    this.cgLastSnapshotApplyAtMs = Date.now();
    if (this.isRecentAddedStreamingMode()) {
      hilog.warn(
        DOMAIN,
        TAG,
        'applyNavStoreSnapshot title=%{public}s flatItems=%{public}d totalCount=%{public}d storeItems=%{public}d listBlocks=%{public}d storeVersion=%{public}d backgroundLoading=%{public}s',
        this.title,
        this.flatItems.length,
        this.totalCount,
        CategoryGalleryNavStore.items.length,
        this.listBlocks.length,
        CategoryGalleryNavStore.version,
        this.cgBackgroundLoading ? 'true' : 'false'
      );
    }
    if (this.heroImageUri.length === 0 && this.flatItems.length > 0) {
      this.heroImageUri = nasUrl(this.baseUrl, pickThumb(this.flatItems[0]));
    }
  }

  private appendCategoryItemsDeduped(
    token: number,
    seenIds: Set<string>,
    incoming: GalleryListItem[],
    pendingAppendItems: GalleryListItem[]
  ): GalleryListItem[] {
    const appendItems: GalleryListItem[] = [];
    for (let i = 0; i < incoming.length; i++) {
      const one = incoming[i];
      const id = this.itemIdOf(one);
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

  private async loadRemainingCategoryItems(token: number): Promise<void> {
    if (!this.cgPageActive || token !== this.pageSessionToken) {
      return;
    }
    const categoryKey = this.pageCategoryKey;
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
    for (let i = 0; i < this.flatItems.length; i++) {
      seenIds.add(this.itemIdOf(this.flatItems[i]));
    }
    const pageSize = 200;
    let pendingAppendItems: GalleryListItem[] = [];
    const flushPendingAppendItems = (): void => {
      if (!this.cgPageActive || pendingAppendItems.length <= 0) {
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
      this.flatItems.length,
      CategoryGalleryNavStore.prefetchedRemainder.length,
      CategoryGalleryNavStore.searchFetchedCount,
      CategoryGalleryNavStore.expectedTotalCount
    );
    try {
      while (this.cgPageActive &&
        token === CategoryGalleryNavStore.currentToken() &&
        CategoryGalleryNavStore.hasPrefetchedRemainder()) {
        const batch = CategoryGalleryNavStore.takePrefetchedBatch(CATEGORY_GALLERY_BACKGROUND_APPEND_BATCH_ITEMS);
        if (batch.length <= 0) {
          break;
        }
        pendingAppendItems = this.appendCategoryItemsDeduped(token, seenIds, batch, pendingAppendItems);
        if (pendingAppendItems.length >= CATEGORY_GALLERY_BACKGROUND_APPEND_BATCH_ITEMS) {
          flushPendingAppendItems();
        }
      }
      flushPendingAppendItems();
      if (categoryKey.length === 0) {
        return;
      }
      let offset = Math.max(CategoryGalleryNavStore.searchFetchedCount, CategoryGalleryNavStore.items.length);
      while (this.cgPageActive && token === CategoryGalleryNavStore.currentToken()) {
        const res = await client.getCategoryPhotos(categoryKey, pageSize, offset);
        if (!this.cgPageActive || token !== CategoryGalleryNavStore.currentToken()) {
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
        pendingAppendItems = this.appendCategoryItemsDeduped(token, seenIds, incoming, pendingAppendItems);
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

  private ensureCategoryBackgroundLoad(): void {
    const token = this.pageSessionToken;
    if (!this.cgPageActive || token < 0 || token !== CategoryGalleryNavStore.currentToken()) {
      return;
    }
    if (CategoryGalleryNavStore.backgroundLoading) {
      return;
    }
    if (this.pageCategoryKey.length === 0 && !CategoryGalleryNavStore.hasPrefetchedRemainder()) {
      return;
    }
    void this.loadRemainingCategoryItems(token);
  }

  private scheduleCategoryBackgroundLoad(): void {
    this.clearCgDeferredBackgroundLoadTimer();
    if (!this.cgPageActive ||
      (this.pageCategoryKey.length === 0 && !CategoryGalleryNavStore.hasPrefetchedRemainder())) {
      return;
    }
    const delayMs = this.pageCategoryKey === 'photo' ? 240 : 96;
    this.cgDeferredBackgroundLoadTimer = setTimeout((): void => {
      this.cgDeferredBackgroundLoadTimer = -1;
      if (!this.cgPageActive) {
        return;
      }
      this.ensureCategoryBackgroundLoad();
    }, delayMs);
  }

  private stopStoreObserver(): void {
    if (this.cgStorePollTimer >= 0) {
      clearInterval(this.cgStorePollTimer);
      this.cgStorePollTimer = -1;
    }
    this.cgPendingStoreSync = false;
  }

  private startStoreObserver(): void {
    if (!this.cgPageActive) {
      return;
    }
    this.stopStoreObserver();
    this.cgStorePollTimer = setInterval((): void => {
      if (!this.cgPageActive) {
        return;
      }
      this.syncFromNavStore();
    }, CATEGORY_GALLERY_STORE_SYNC_INTERVAL_MS);
  }

  private syncFromNavStore(): void {
    if (!this.cgPageActive || this.pageSessionToken !== CategoryGalleryNavStore.sessionToken) {
      return;
    }
    if (this.cgObservedStoreVersion === CategoryGalleryNavStore.version) {
      return;
    }
    const recentAddedStreaming = this.isRecentAddedStreamingMode();
    const navStoreHasAppendItems = CategoryGalleryNavStore.items.length > this.flatItems.length;
    const allowAppendSyncWhilePaused = false;
    const appendDelta = Math.max(0, CategoryGalleryNavStore.items.length - this.flatItems.length);
    const applyGapMs = Date.now() - this.cgLastSnapshotApplyAtMs;
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
        this.cgObservedStoreVersion,
        CategoryGalleryNavStore.items.length,
        this.flatItems.length,
        navStoreHasAppendItems ? 'true' : 'false',
        this.cgThumbLoadingPaused ? 'true' : 'false',
        this.cgSlideGestureActive ? 'true' : 'false',
        allowAppendSyncWhilePaused ? 'true' : 'false'
      );
    }
    if (this.cgSlideGestureActive || (this.cgThumbLoadingPaused && (!allowAppendSyncWhilePaused || !navStoreHasAppendItems))) {
      this.totalCount = Math.max(
        CategoryGalleryNavStore.expectedTotalCount,
        this.totalCount,
        this.flatItems.length,
        CategoryGalleryNavStore.items.length
      );
      this.cgBackgroundLoading = CategoryGalleryNavStore.backgroundLoading;
      this.cgPendingStoreSync = true;
      if (recentAddedStreaming) {
        this.scheduleCgDeferredSnapshotApply();
        hilog.warn(
          DOMAIN,
          TAG,
          'syncDeferred totalCount=%{public}d backgroundLoading=%{public}s pending=%{public}s',
          this.totalCount,
          this.cgBackgroundLoading ? 'true' : 'false',
          this.cgPendingStoreSync ? 'true' : 'false'
        );
      }
      return;
    }
    if (shouldCoalesceRecentAppend) {
      this.totalCount = Math.max(
        CategoryGalleryNavStore.expectedTotalCount,
        this.totalCount,
        this.flatItems.length,
        CategoryGalleryNavStore.items.length
      );
      this.cgBackgroundLoading = CategoryGalleryNavStore.backgroundLoading;
      this.cgPendingStoreSync = true;
      this.scheduleCgDeferredSnapshotApply();
      hilog.warn(
        DOMAIN,
        TAG,
        'syncCoalesced totalCount=%{public}d appendDelta=%{public}d applyGapMs=%{public}d pending=%{public}s',
        this.totalCount,
        appendDelta,
        applyGapMs,
        this.cgPendingStoreSync ? 'true' : 'false'
      );
      return;
    }
    this.applyNavStoreSnapshot();
    if (!this.cgBackgroundLoading) {
      this.recycleThumbCache(false);
    }
  }

  private onListScrollStateChange(scrollState: ScrollState): void {
    if (!this.cgSlideGestureActive && !this.cgScrollEnabled) {
      this.cgScrollEnabled = true;
    }
    if (!this.cgSlideGestureActive) {
      this.cgThumbHitBounds.clear();
    }
    if (scrollState !== ScrollState.Idle) {
      this.clearCgThumbResumeTimer();
      if (!this.cgThumbLoadingPaused) {
        this.cgThumbLoadingPaused = true;
      }
      this.recycleThumbCache(this.isRecentAddedStreamingMode() || this.flatItems.length > 720);
      return;
    }
    this.clearCgThumbResumeTimer();
    const resumeDelayMs = this.isRecentAddedStreamingMode() && (this.cgBackgroundLoading || this.flatItems.length > 720)
      ? CATEGORY_GALLERY_RECENT_STREAM_IDLE_RESUME_MS
      : CATEGORY_GALLERY_STORE_SYNC_INTERVAL_MS;
    this.cgThumbResumeTimer = setTimeout((): void => {
      this.cgThumbResumeTimer = -1;
      if (!this.cgPageActive) {
        return;
      }
      this.cgThumbLoadingPaused = false;
      this.recycleThumbCache(this.isRecentAddedStreamingMode() && this.flatItems.length > 720);
      if (this.cgPendingStoreSync) {
        if (this.isRecentAddedStreamingMode()) {
          this.scheduleCgDeferredSnapshotApply(48);
        } else {
          this.applyNavStoreSnapshot();
        }
      }
    }, resumeDelayMs);
  }

  private asSelectionHost(): CategoryGallerySelectionHost {
    const self = this;
    class CategoryGallerySelectionHostBridge implements CategoryGallerySelectionHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get flatItems(): GalleryListItem[] { return self.flatItems; }
      set flatItems(v: GalleryListItem[]) { self.flatItems = v; }

      get groupOffsets(): number[] { return self.groupOffsets; }
      set groupOffsets(v: number[]) { self.groupOffsets = v; }

      get columnsPerRow(): number { return self.columnsPerRow; }
      set columnsPerRow(v: number) { self.columnsPerRow = fnClampGridColumns(v); }

      get selectionMode(): boolean { return self.selectionMode; }
      set selectionMode(v: boolean) { self.setSelectionModeState(v); }

      get selectedIds(): string[] { return self.selectedIds; }
      set selectedIds(v: string[]) { self.setSelectedIdsState(v); }

      get listScroller(): Scroller { return self.listScroller; }
      set listScroller(v: Scroller) { self.listScroller = v; }

      get listDomId(): string { return CATEGORY_GALLERY_LIST_DOM_ID; }
      set listDomId(_v: string) {}

      get cgSlideGestureActive(): boolean { return self.cgSlideGestureActive; }
      set cgSlideGestureActive(v: boolean) { self.cgSlideGestureActive = v; }

      get cgScrollEnabled(): boolean { return self.cgScrollEnabled; }
      set cgScrollEnabled(v: boolean) { self.cgScrollEnabled = v; }

      get cgLongPressIgnoreUntil(): number { return self.cgLongPressIgnoreUntil; }
      set cgLongPressIgnoreUntil(v: number) { self.cgLongPressIgnoreUntil = v; }

      get cgThumbHitBounds(): Map<string, CgThumbHitRect> { return self.cgThumbHitBounds; }
      set cgThumbHitBounds(v: Map<string, CgThumbHitRect>) { self.cgThumbHitBounds = v; }

      get cgSlideRefX(): number { return self.cgSlideRefX; }
      set cgSlideRefX(v: number) { self.cgSlideRefX = v; }

      get cgSlideRefY(): number { return self.cgSlideRefY; }
      set cgSlideRefY(v: number) { self.cgSlideRefY = v; }

      get cgSlideHasRef(): boolean { return self.cgSlideHasRef; }
      set cgSlideHasRef(v: boolean) { self.cgSlideHasRef = v; }

      get cgSlideAnchorFlat(): number { return self.cgSlideAnchorFlat; }
      set cgSlideAnchorFlat(v: number) { self.cgSlideAnchorFlat = v; }

      get cgSlideUnionBase(): string[] { return self.cgSlideUnionBase; }
      set cgSlideUnionBase(v: string[]) { self.cgSlideUnionBase = v; }

      get cgSlideLastEndFlat(): number { return self.cgSlideLastEndFlat; }
      set cgSlideLastEndFlat(v: number) { self.cgSlideLastEndFlat = v; }

      get cgSlideLastAppliedEndFlat(): number { return self.cgSlideLastAppliedEndFlat; }
      set cgSlideLastAppliedEndFlat(v: number) { self.cgSlideLastAppliedEndFlat = v; }

      toast(msg: string): void { self.toast(msg); }
      openItemAtFlat(flatIdx: number): void { self.openItemAtFlat(flatIdx); }
    }
    return new CategoryGallerySelectionHostBridge();
  }

  private liveSaveResolver: ((choice: LivePhotoSaveChoice) => void) | undefined = undefined;
  private choiceSheetResolver: ((index: number) => void) | undefined = undefined;

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

  @Builder
  private liveSaveSheetBuilder() {
    LivePhotoSaveActionSheet({
      onSelect: (choice: LivePhotoSaveChoice): void => {
        this.completeLivePhotoSave(choice);
      }
    })
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

  @Builder
  private slideshowSettingsBuilder() {
    GallerySlideshowSettingsSheet({
      preparing: this.slideshowPreparing,
      onStart: (config: GallerySlideshowConfig): void => {
        void this.startCategorySlideshow(config);
      }
    })
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

  private asBatchActionsHost(): CategoryGalleryBatchActionsHost {
    const self = this;
    class CategoryGalleryBatchActionsHostBridge implements CategoryGalleryBatchActionsHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(v: string) { self.baseUrl = v; }

      get title(): string { return self.title; }
      set title(v: string) { self.title = v; }

      get groups(): DayGroup[] { return self.groups; }
      set groups(v: DayGroup[]) { self.groups = v; }

      get flatItems(): GalleryListItem[] { return self.flatItems; }
      set flatItems(v: GalleryListItem[]) { self.flatItems = v; }

      get groupOffsets(): number[] { return self.groupOffsets; }
      set groupOffsets(v: number[]) { self.groupOffsets = v; }

      get handledDeleteSyncVersion(): number { return self.handledDeleteSyncVersion; }
      set handledDeleteSyncVersion(v: number) { self.handledDeleteSyncVersion = v; }

      get columnsPerRow(): number { return self.columnsPerRow; }
      set columnsPerRow(v: number) { self.columnsPerRow = fnClampGridColumns(v); }

      get selectedIds(): string[] { return self.selectedIds; }
      set selectedIds(v: string[]) { self.setSelectedIdsState(v); }

      get cgBatchDeleting(): boolean { return self.cgBatchDeleting; }
      set cgBatchDeleting(v: boolean) { self.cgBatchDeleting = v; }

      get cgBatchDownloading(): boolean { return self.cgBatchDownloading; }
      set cgBatchDownloading(v: boolean) { self.cgBatchDownloading = v; }

      toast(msg: string): void { self.toast(msg); }
      exitSelection(): void { self.exitCgSelection(); }
      askLivePhotoSave(): Promise<LivePhotoSaveChoice> { return self.askLivePhotoSave(); }
      askChoice(title: string, buttons: string[]): Promise<number> { return self.askChoice(title, buttons); }
    }
    return new CategoryGalleryBatchActionsHostBridge();
  }

  @Builder
  private thumbCellWithFlat(item: GalleryListItem, flatIdx: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      GalleryNetworkThumb({
        uri: nasUrl(this.baseUrl, pickThumb(item)),
        isVideo: isVideoItem(item),
        isGif: isGifItem(item),
        isLive: isLivePhotoItem(item),
        paused: this.cgThumbLoadingPaused,
        cacheIdentity: thumbIdentityOfItem(item),
        cacheRank: 3,
        sharedTransitionId: gallerySharedTransitionId(this.itemIdOf(item))
      })
        .width('100%')
        .aspectRatio(1)
      GalleryAlbumSelectionOverlay({
        itemId: this.itemIdOf(item),
        visualScope: GALLERY_SELECTION_SCOPE_CATEGORY,
        selectionMode: this.selectionMode
      })
    }
    .width('100%')
    .layoutWeight(1)
    .aspectRatio(1)
    .id(this.cgDomId(flatIdx))
    .onAreaChange((): void => {
      this.recordCgThumbRect(flatIdx);
    })
    .onClick((): void => {
      this.onCgCellClick(item, flatIdx);
    })
  }

  @Builder
  private dayHeaderListItem(label: string) {
    ListItem() {
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, top: 14, bottom: 6 })
    }
  }

  @Builder
  private dayRowListItem(groupIdx: number, row: RowModel) {
    ListItem() {
      Row({ space: 2 }) {
        ForEach(this.rowColumnIndexes(), (col: number) => {
          this.dayRowCell(groupIdx, row, col)
        }, (col: number) => this.rowCellStableKey(groupIdx, row, col))
      }
      .width('100%')
      .padding({ left: 2, right: 2, top: 1, bottom: 1 })
      .onTouch((event: TouchEvent): void => {
        galleryGridHandleRowTouch(
          this.slideTouch,
          this.asSlideTouchHost(),
          event,
          (xPx: number, yPx: number): boolean => this.beginCgFirstSlideAtRow(groupIdx, row, xPx, yPx)
        );
      })
      .parallelGesture(GestureGroup(GestureMode.Parallel,
        GestureGroup(GestureMode.Sequence,
          LongPressGesture({ repeat: false, duration: GALLERY_GRID_SEQUENCE_LONG_PRESS_MS })
            .onAction((ev: GestureEvent): void => {
              if (!galleryGridOnSequenceLongPress(this.slideTouch, this.asSlideTouchHost())) {
                return;
              }
              galleryGridClearInitialSlide(this.slideTouch);
              this.endCgSlideSelectGesture();
              const pt = this.readGestureFingerWindow(ev);
              if (pt === null) {
                return;
              }
              if (!this.beginCgFirstSlideAtRow(groupIdx, row, this.vpToPx(pt.x), this.vpToPx(pt.y))) {
                return;
              }
              galleryGridArmInitialSlide(this.slideTouch);
            }),
          PanGesture({
            fingers: 1,
            direction: PanDirection.All,
            distance: GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE
          })
            .onActionUpdate((ev: GestureEvent): void => {
              if (!galleryGridShouldUpdateSequencePan(this.slideTouch, this.asSlideTouchHost())) {
                return;
              }
              this.onCgSlidePanUpdate(ev);
            })
            .onActionEnd((): void => {
              galleryGridOnSequencePanFinish(this.slideTouch, this.asSlideTouchHost());
            })
            .onActionCancel((): void => {
              galleryGridOnSequencePanFinish(this.slideTouch, this.asSlideTouchHost());
            })
        ),
        PanGesture({
          fingers: 1,
          direction: PanDirection.Horizontal,
          distance: GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE
        })
          .onActionStart((ev: GestureEvent): void => {
            this.slideTouch.secondaryPanDriving = false;
            if (!galleryGridCanStartSecondaryPan(this.slideTouch, this.asSlideTouchHost(), ev)) {
              return;
            }
            const pt = this.readGestureFingerWindow(ev);
            if (pt === null) {
              galleryGridSlideLog('cg_sec_start_skip', 'reason=no_pointer');
              return;
            }
            const xPx = this.vpToPx(pt.x);
            const yPx = this.vpToPx(pt.y);
            const fi = this.pickCgFlatForRow(this.rowGlobalStartFlat(groupIdx, row), xPx, yPx);
            if (fi < 0 || fi >= this.flatItems.length) {
              galleryGridSlideLog('cg_sec_start_skip',
                `reason=no_hit row=${this.rowGlobalStartFlat(groupIdx, row)} flat=${fi}` +
                  ` xy=${Math.round(xPx)},${Math.round(yPx)} total=${this.flatItems.length}`);
              return;
            }
            galleryGridSlideLog('cg_sec_start',
              `flat=${fi} xy=${Math.round(xPx)},${Math.round(yPx)} selected=${this.selectedIds.length}`);
            galleryGridOnSecondaryPanStart(this.slideTouch);
            this.beginCgSlideSelectGesture(ev, fi);
          })
          .onActionUpdate((ev: GestureEvent): void => {
            if (!galleryGridShouldUpdateSecondaryPan(this.slideTouch, this.asSlideTouchHost())) {
              return;
            }
            this.onCgSlidePanUpdate(ev);
          })
          .onActionEnd((): void => {
            galleryGridOnSecondaryPanFinish(this.slideTouch, this.asSlideTouchHost());
          })
          .onActionCancel((): void => {
            galleryGridOnSecondaryPanFinish(this.slideTouch, this.asSlideTouchHost());
          })
      ))
    }
    .draggable(false)
    .margin({ bottom: 2 })
  }

  private resolvedColumns(): number {
    return fnAdaptiveGridColumns(this.baseColumnsPerRow, this.windowWidthBp);
  }

  private onWindowWidthBpChanged(): void {
    const next = this.resolvedColumns();
    if (next === this.columnsPerRow) {
      return;
    }
    this.columnsPerRow = next;
    if (this.flatItems.length > 0) {
      this.rebuildByFlatItems();
    }
  }

  private rowColumnIndexes(): number[] {
    return fnGridColumnIndexes(this.columnsPerRow);
  }

  private rowCellAt(row: RowModel, col: number): GalleryListItem | undefined {
    return col >= 0 && col < row.cells.length ? row.cells[col] : undefined;
  }

  private rowCellStableKey(groupIdx: number, row: RowModel, col: number): string {
    const item = this.rowCellAt(row, col);
    if (item === undefined) {
      return `cg_cell_${groupIdx}_${row.startIdx}_${col}_empty`;
    }
    const id = this.itemIdOf(item);
    if (id.length > 0) {
      return `cg_cell_${groupIdx}_${row.startIdx}_${col}_id_${id}`;
    }
    return `cg_cell_${groupIdx}_${row.startIdx}_${col}_flat_${this.flatPos(groupIdx, row.startIdx + col)}`;
  }

  @Builder
  private dayRowCell(groupIdx: number, row: RowModel, col: number) {
    if (this.rowCellAt(row, col) !== undefined) {
      this.thumbCellWithFlat(
        this.rowCellAt(row, col) as GalleryListItem,
        this.flatPos(groupIdx, row.startIdx + col)
      )
    } else {
      Blank().layoutWeight(1).aspectRatio(1)
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
          // 顶栏走文档流，不要 Stack 浮层。HdsNavigation 叠在全屏上会把宫格命中区盖住，松手后滑不动、点不动。
          CategoryGalleryChrome({
            selectionMode: this.selectionMode,
            selectedCount: this.selectedCount,
            title: this.title,
            totalCount: this.totalCount,
            topSafeInsetVp: this.systemTopInsetVp,
            personAlbumMode: this.usesMoreMenuMode(),
            moreMenuExpanded: this.moreMenuExpanded,
            scrollerList: [this.listScroller],
            onCancelSelection: (): void => {
              this.exitCgSelection();
            },
            onBack: (): void => {
              this.navigateBack();
            },
            onToggleMode: (): void => {
              this.toggleToolbarMode();
            },
            onShowMoreMenu: (): void => {
              this.toggleMoreMenu();
            },
            onDismissMoreMenu: (): void => {
              this.dismissMoreMenu();
            },
            onEnterMultiselectFromMore: (): void => {
              this.enterMultiselectFromMoreMenu();
            },
            onOpenSlideshowFromMore: (): void => {
              this.openSlideshowSettings();
            }
          })
            .width('100%')

          if (this.groups.length === 0) {
            FnStateText({
              text: this.emptyStateText(),
              topOffsetVp: 24
            }).layoutWeight(1)
          } else {
            Stack({ alignContent: Alignment.Bottom }) {
              Column() {
                List({ scroller: this.listScroller }) {
                  LazyForEach(this.listBlockSource, (block: CategoryGalleryListBlock) => {
                    if (block.isHeader) {
                      this.dayHeaderListItem(block.label ?? '')
                    } else if (block.row !== undefined) {
                      this.dayRowListItem(block.groupIdx, block.row as RowModel)
                    }
                  }, (block: CategoryGalleryListBlock) => block.key)
                  if (this.cgBackgroundLoading) {
                    ListItem() {
                      Row({ space: 8 }) {
                        LoadingProgress()
                          .width(18)
                          .height(18)
                        Text('继续加载中')
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                      }
                      .width('100%')
                      .justifyContent(FlexAlign.Center)
                      .padding({ top: 8, bottom: 8 })
                    }
                  }
                  ListItem() {
                    Column() {
                      Blank()
                        .width('100%')
                        .height(this.selectionMode && this.selectedCount > 0 ? 88 : 24)
                    }
                    .width('100%')
                  }
                }
                .width('100%')
                .layoutWeight(1)
                .id(CATEGORY_GALLERY_LIST_DOM_ID)
                .cachedCount(this.isRecentAddedStreamingMode() ? 1 : (this.columnsPerRow >= 4 ? 2 : 3))
                .scrollBar(BarState.Auto)
                .backgroundColor(Color.Transparent)
                .edgeEffect(EdgeEffect.Spring)
                .divider({ strokeWidth: 0 })
                .enableScrollInteraction(this.cgScrollEnabled)
                .onTouch((event: TouchEvent): void => {
                  galleryGridHandleListTouch(this.slideTouch, this.asSlideTouchHost(), event);
                })
                .onDidScroll((offset: number, scrollState: ScrollState): void => {
                  gallerySlideAutoScrollOnListDidScroll(offset, scrollState);
                  this.onListScrollStateChange(scrollState);
                })

                if (false && this.cgBackgroundLoading) {
                  Row({ space: 8 }) {
                    LoadingProgress()
                      .width(18)
                      .height(18)
                    Text('继续加载中')
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                  .padding({ top: 8, bottom: this.selectionMode && this.selectedCount > 0 ? 8 : 0 })
                }
              }
              .width('100%')
              .height('100%')

              if (this.selectionMode && this.selectedCount > 0) {
                GalleryAlbumBatchActionBar({
                  downloading: this.cgBatchDownloading,
                  deleting: this.cgBatchDeleting,
                  onDownload: (): void => {
                    void this.confirmCgBatchDownload();
                  },
                  onDelete: (): void => {
                    void this.confirmCgBatchDelete();
                  }
                })
                  .width('100%')
                  // 只让底部按钮区域参与命中；全屏 HdsTabs 会吞掉列表后续所有触摸。
                  .height(GALLERY_BATCH_BAR_TOTAL_HEIGHT_VP)
              }

              if (this.cgBatchDeleting || this.cgBatchDownloading) {
                FnFullLoadingMask({
                  text: this.cgBatchDeleting ? '移入回收站中…' : '下载中…',
                  topOffsetVp: 0
                })
              }
            }
            .layoutWeight(1)
            .width('100%')
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))

      if (this.slideshowPreparing) {
        FnFullLoadingMask({
          text: '正在准备幻灯片...',
          topOffsetVp: this.contentInsetTopVp()
        })
          .width('100%')
          .height('100%')
          .zIndex(30)
      }
      if (this.previewOpening) {
        GalleryPreviewOpeningMask({ topOffsetVp: this.contentInsetTopVp() })
          .width('100%')
          .height('100%')
          .zIndex(30)
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
        .bindSheet(this.slideshowSettingsVisible, this.slideshowSettingsBuilder, fnHdsFitContentSheetOptions(
          gallerySlideshowScopeLabel(this.categorySlideshowScope()),
          (): void => {
            this.dismissSlideshowSettings();
          }
        ))
    }
    .width('100%')
    .height('100%')
    .id(GALLERY_PREVIEW_SOURCE_CATEGORY_ID)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.choiceSheetVisible, this.choiceSheetBuilder, fnHdsFitContentSheetOptions(
      this.choiceSheetTitle,
      (): void => {
        this.completeChoice(-1);
      }
    ))
  }

  pageTransition(): void {
    if (this.previewHeroActive) {
      PageTransitionEnter({ type: RouteType.None, duration: 0 })
      PageTransitionExit({ type: RouteType.None, duration: 0 })
    } else {
      PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
        .opacity(0)
        .translate({ x: 12, y: 0 });
      PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
        .opacity(0)
        .translate({ x: -8, y: 0 });
    }
  }
}

/** Home 的 NavDestination 复用页面内容；独立 Router 入口仍由 @Entry 保留。 */
@Builder
export function CategoryGalleryNavigationContent() {
  CategoryGallery()
}
