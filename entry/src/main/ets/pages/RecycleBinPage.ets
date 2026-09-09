/**
 * 相册回收站：列表 + 多选恢复（GET recycle-bin/list，POST recycle-bin/restore）
 * 多选手势与图库主时间线一致：每行 Row + LongPress + Pan 划选 + 命中矩形缓存。
 */
import { common } from '@kit.AbilityKit';
import { UIContext, window } from '@kit.ArkUI';
import { AppSession, FN_MEDIA_BASE_URL } from '../auth/AppSession';
import {
  GalleryNetworkThumb,
  nasUrl,
  trimThumbPixCacheForList
} from '../album/GalleryAlbumCommon';
import {
  RecycleBinRowBlock,
  RecycleBinRowBlockCell,
  recycleBinBuildRowBlocks
} from './recycleBinPage/RecycleBinListModel';
import { RecycleBinSession } from './recycleBinPage/RecycleBinSession';
import { RbThumbHitRect } from './recycleBinPage/RecycleBinTypes';
import {
  FN_WINDOW_WIDTH_BP_KEY,
  fnAdaptiveGridColumns,
  fnClampGridColumns
} from '../common/FnWindowBreakpoint';
import { fnApplyImmersiveSystemBarColors } from '../common/FnSplashTheme';
import { FN_SYSTEM_TOP_INSET_VP_KEY, fnPublishSystemAvoidArea } from '../common/FnSystemAvoidArea';
import { RecycleBinListItem } from '../model/FnApiTypes';
import {
  FnFullLoadingMask,
  FnHdsPillButton,
  FnInlineLoading,
  FnStateText
} from '../common/FnUiCommon';
import { GALLERY_BATCH_BAR_TOTAL_HEIGHT_VP } from '../common/GalleryButtonStyles';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import {
  recycleBinConfirmBatchDownload,
  recycleBinConfirmRestore,
  recycleBinLoadAll,
  RecycleBinActionsHost
} from './recycleBinPage/RecycleBinActions';
import { gallerySelectionContainsLive } from '../album/livephoto/LivePhotoDetect';
import {
  askLivePhotoSaveChoice,
  LivePhotoSaveActionSheet,
  LivePhotoSaveChoice,
  LIVE_PHOTO_PRIVILEGE_SHEET_TITLE
} from '../album/livephoto/LivePhotoSaveActionSheet';
import { FnHdsChoiceSheet, fnHdsFitContentSheetOptions, fnHdsSaveButtonSheetOptions } from '../common/FnHdsOverlay';
import { GALLERY_PREVIEW_OPENING_KEY } from '../album/GalleryPreviewEntryGate';
import {
  GALLERY_PREVIEW_HERO_ACTIVE_KEY,
  GALLERY_PREVIEW_SOURCE_RECYCLE_ID,
  gallerySharedTransitionId
} from '../album/GallerySharedTransition';
import { GalleryPreviewOpeningMask } from '../album/GalleryPreviewOpeningMask';
import { GalleryAlbumNavigation } from '../album/GalleryAlbumNavigation';
import {
  gallerySlideAutoScrollIsRunning,
  gallerySlideAutoScrollOnListDidScroll
} from '../album/GallerySlideAutoScroll';
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
  GALLERY_GRID_SEQUENCE_LONG_PRESS_MS
} from '../album/GalleryGridSlideTouch';
import { RecycleBinBatchBar } from './recycleBinPage/RecycleBinBatchBar';
import { GalleryGridChrome } from '../album/galleryList/GalleryGridChrome';
import {
  GalleryListBackStep,
  galleryListPopOrRouterBack,
  galleryListTryConsumeOverlays
} from '../album/galleryList/GalleryListBack';
import {
  GALLERY_SELECTION_SCOPE_RECYCLE,
  GalleryAlbumSelectionOverlay,
  galleryAlbumSyncSelectionVisualState
} from '../album/galleryAlbumTab/GalleryAlbumSelectionOverlay';
import {
  recycleBinGalleryListForSelection,
  recycleBinBeginSlideSelectGesture,
  recycleBinBeginSlideSelectGestureAtWindowPx,
  recycleBinDomId,
  recycleBinEndSlideSelectGesture,
  recycleBinExitSelection,
  recycleBinNumericIdOf,
  recycleBinOnCellClick,
  recycleBinOnSlidePanUpdate,
  recycleBinOnSlideTouchMoveWindow,
  recycleBinOnThumbLongPress,
  recycleBinPickThumbFlatForRow,
  recycleBinReadGestureFingerWindow,
  recycleBinRecordThumbRect,
  recycleBinSelectedIdStrings,
  recycleBinThumbRelOf,
  recycleBinToggleToolbarMode,
  RECYCLE_BIN_LIST_DOM_ID,
  RecycleBinSelectionHost
} from './recycleBinPage/RecycleBinSelectionController';

const RECYCLE_BIN_BASE_COLUMNS: number = 4;

@Entry
@Component
struct RecycleBinPage {
  private albumNavigationMode: boolean = false;
  @StorageProp(FN_MEDIA_BASE_URL) private baseUrl: string = '';
  @State private loading: boolean = false;
  @State private restoring: boolean = false;
  @State private rbBatchDownloading: boolean = false;
  @State private rbBackgroundLoading: boolean = false;
  @State private error: string = '';
  @State @Watch('onItemsChanged') private items: RecycleBinListItem[] = [];
  @State private selectionMode: boolean = false;
  @State private selectedCount: number = 0;
  @State private selectionHasLivePhoto: boolean = false;
  @State private liveSaveSheetVisible: boolean = false;
  @State private choiceSheetVisible: boolean = false;
  @State private choiceSheetTitle: string = '';
  @State private choiceSheetButtons: string[] = [];
  @State private rbSlideGestureActive: boolean = false;
  @State private rbScrollEnabled: boolean = true;
  @State private rbThumbLoadingPaused: boolean = false;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(GALLERY_PREVIEW_OPENING_KEY) private previewOpening: boolean = false;
  @StorageProp(GALLERY_PREVIEW_HERO_ACTIVE_KEY) private previewHeroActive: boolean = false;
  @StorageProp(FN_WINDOW_WIDTH_BP_KEY) @Watch('onWindowWidthBpChanged') private windowWidthBp: number =
    WidthBreakpoint.WIDTH_SM;
  @State private columnsPerRow: number = RECYCLE_BIN_BASE_COLUMNS;

  private session: RecycleBinSession = new RecycleBinSession();
  private slideTouchHostCache: GalleryGridSlideTouchHost | undefined = undefined;
  private selectionHostCache: RecycleBinSelectionHost | undefined = undefined;
  private actionsHostCache: RecycleBinActionsHost | undefined = undefined;
  private albumBackHandlerToken: number = 0;

  onBackPress(): boolean {
    const overlaySteps: GalleryListBackStep[] = [
      new GalleryListBackStep(this.choiceSheetVisible, (): void => {
        this.completeChoice(-1);
      }),
      new GalleryListBackStep(this.liveSaveSheetVisible, (): void => {
        this.completeLivePhotoSave('cancel');
      }),
      new GalleryListBackStep(this.selectionMode, (): void => {
        this.exitSelection();
      })
    ];
    if (galleryListTryConsumeOverlays(overlaySteps)) {
      return true;
    }
    this.navigateBack();
    return true;
  }

  private navigateBack(): void {
    galleryListPopOrRouterBack(this.albumNavigationMode, (): void => {
      this.getUIContext().getRouter().back();
    });
  }

  private vpToPx(value: number): number {
    try {
      return this.getUIContext().vp2px(value);
    } catch (_e) {
      return value;
    }
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

  onColorModeChanged(): void {
    this.applySystemBar(false);
  }

  aboutToAppear(): void {
    this.albumNavigationMode = GalleryAlbumNavigation.isAvailable();
    this.columnsPerRow = fnAdaptiveGridColumns(RECYCLE_BIN_BASE_COLUMNS, this.windowWidthBp);
    this.applySystemBar(true);
    this.rbThumbLoadingPaused = false;
    this.rebuildRowBlocks();
    if (this.albumNavigationMode) {
      this.albumBackHandlerToken = GalleryAlbumNavigation.registerBackHandler((): boolean => {
        this.onBackPress();
        return true;
      });
    } else {
      const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
      if (rp !== undefined && rp['baseUrl'] !== undefined) {
        this.baseUrl = String(rp['baseUrl']);
      }
    }
    void this.loadAll();
  }

  aboutToDisappear(): void {
    GalleryAlbumNavigation.unregisterBackHandler(this.albumBackHandlerToken);
    this.clearRbThumbResumeTimer();
    recycleBinEndSlideSelectGesture(this.asSelectionHost());
    galleryGridResetTouchTracking(this.session.list.slideTouch);
    galleryAlbumSyncSelectionVisualState(false, [], GALLERY_SELECTION_SCOPE_RECYCLE);
    this.recycleThumbCache(true);
    this.session.list.rbRowBlocks = [];
    this.session.list.rbRowSource.reloadAll([]);
    const client = AppSession.getClient();
    if (client !== null) {
      client.cancelPendingRequests();
    }
  }

  onItemsChanged(): void {
    this.rebuildRowBlocks();
  }

  private onWindowWidthBpChanged(): void {
    const next = fnAdaptiveGridColumns(RECYCLE_BIN_BASE_COLUMNS, this.windowWidthBp);
    if (next === this.columnsPerRow) {
      return;
    }
    this.columnsPerRow = next;
    this.rebuildRowBlocks();
  }

  private setSelectionModeState(value: boolean): void {
    if (this.selectionMode === value) {
      return;
    }
    this.selectionMode = value;
    galleryAlbumSyncSelectionVisualState(
      this.selectionMode,
      recycleBinSelectedIdStrings(this.session.selection.selectedIds),
      GALLERY_SELECTION_SCOPE_RECYCLE
    );
  }

  private setSelectedIdsState(value: number[]): void {
    this.session.selection.selectedIds = value;
    const selected = recycleBinGalleryListForSelection(this.items, this.session.selection.selectedIds);
    this.selectionHasLivePhoto = gallerySelectionContainsLive(selected);
    galleryAlbumSyncSelectionVisualState(
      this.selectionMode,
      recycleBinSelectedIdStrings(this.session.selection.selectedIds),
      GALLERY_SELECTION_SCOPE_RECYCLE
    );
    if (this.selectedCount !== value.length) {
      this.selectedCount = value.length;
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {}
  }

  private rbDomId(flatIdx: number): string {
    return recycleBinDomId(flatIdx);
  }

  private exitSelection(): void {
    recycleBinExitSelection(this.asSelectionHost());
  }

  private toggleToolbarMode(): void {
    recycleBinToggleToolbarMode(this.asSelectionHost());
  }

  private numericIdOf(it: RecycleBinListItem): number {
    return recycleBinNumericIdOf(it);
  }

  private thumbRelOf(it: RecycleBinListItem): string {
    return recycleBinThumbRelOf(it);
  }

  private topHeroImageUri(): string {
    if (this.items.length === 0) {
      return '';
    }
    const rel = this.thumbRelOf(this.items[0]);
    return rel.length > 0 ? nasUrl(this.baseUrl, rel) : '';
  }

  private recordRbThumbRect(flatIdx: number): void {
    recycleBinRecordThumbRect(this.asSelectionHost(), flatIdx);
  }

  private readGestureFingerWindow(ev: GestureEvent) {
    return recycleBinReadGestureFingerWindow(ev);
  }

  private asSlideTouchHost(): GalleryGridSlideTouchHost {
    if (this.slideTouchHostCache !== undefined) {
      return this.slideTouchHostCache;
    }
    const self = this;
    class RecycleBinSlideTouchHostBridge implements GalleryGridSlideTouchHost {
      getUIContext(): UIContext { return self.getUIContext(); }
      isSelectionMode(): boolean { return self.selectionMode; }
      isSlideActive(): boolean { return self.rbSlideGestureActive; }
      endSlide(): void { self.endRbSlideSelectGesture(); }
      followSlideAtWindowPx(xPx: number, yPx: number): void { self.onRbSlideTouchMoveWindow(xPx, yPx); }
    }
    this.slideTouchHostCache = new RecycleBinSlideTouchHostBridge();
    return this.slideTouchHostCache;
  }

  private beginRbFirstSlideAtRow(rowStart: number, xPx: number, yPx: number): boolean {
    const fi = this.pickRbThumbFlatForRow(rowStart, xPx, yPx);
    if (fi < 0 || fi >= this.items.length) {
      return false;
    }
    const item = this.items[fi];
    if (!this.selectionMode) {
      this.onRbThumbLongPress(item, fi);
    }
    this.beginRbSlideSelectGestureAtWindowPx(fi, xPx, yPx);
    return true;
  }

  private pickRbThumbFlatForRow(rowStart: number, xPx: number, yPx: number): number {
    return recycleBinPickThumbFlatForRow(this.asSelectionHost(), rowStart, xPx, yPx);
  }

  private beginRbSlideSelectGesture(ev: GestureEvent, anchorFlat: number): void {
    recycleBinBeginSlideSelectGesture(this.asSelectionHost(), ev, anchorFlat);
  }

  private beginRbSlideSelectGestureAtWindowPx(anchorFlat: number, xPx: number, yPx: number): void {
    recycleBinBeginSlideSelectGestureAtWindowPx(this.asSelectionHost(), anchorFlat, xPx, yPx);
  }

  private endRbSlideSelectGesture(): void {
    recycleBinEndSlideSelectGesture(this.asSelectionHost());
  }

  private onRbSlidePanUpdate(ev: GestureEvent): void {
    recycleBinOnSlidePanUpdate(this.asSelectionHost(), ev);
  }

  private onRbSlideTouchMoveWindow(xPx: number, yPx: number): void {
    recycleBinOnSlideTouchMoveWindow(this.asSelectionHost(), xPx, yPx);
  }

  private onRbThumbLongPress(it: RecycleBinListItem, flatIdx: number): void {
    recycleBinOnThumbLongPress(this.asSelectionHost(), it, flatIdx);
  }

  private onCellClick(it: RecycleBinListItem, flatIdx: number): void {
    recycleBinOnCellClick(this.asSelectionHost(), it, flatIdx);
  }

  private buildRowBlocks(): RecycleBinRowBlock[] {
    return recycleBinBuildRowBlocks(this.items, this.columnsPerRow);
  }

  private rebuildRowBlocks(): void {
    this.session.list.rbRowBlocks = this.buildRowBlocks();
    this.session.list.rbRowSource.reloadAll(this.session.list.rbRowBlocks);
  }

  private rbCellAt(block: RecycleBinRowBlock, col: number): RecycleBinRowBlockCell | undefined {
    if (col < 0 || col >= block.cells.length) {
      return undefined;
    }
    return block.cells[col];
  }

  private rbCellHasItem(block: RecycleBinRowBlock, col: number): boolean {
    const cell = this.rbCellAt(block, col);
    return cell !== undefined && cell.item !== undefined && cell.flatIdx >= 0;
  }

  private rbCellItem(block: RecycleBinRowBlock, col: number): RecycleBinListItem {
    return this.rbCellAt(block, col)?.item as RecycleBinListItem;
  }

  private rbCellFlatIdx(block: RecycleBinRowBlock, col: number): number {
    return this.rbCellAt(block, col)?.flatIdx ?? -1;
  }

  private rbCellThumbRel(block: RecycleBinRowBlock, col: number): string {
    return this.rbCellAt(block, col)?.thumbRel ?? '';
  }

  private rbCellNumericId(block: RecycleBinRowBlock, col: number): number {
    return this.rbCellAt(block, col)?.numericId ?? -1;
  }

  private rbCellStableKey(block: RecycleBinRowBlock, col: number): string {
    const cell = this.rbCellAt(block, col);
    if (cell === undefined || cell.item === undefined || cell.flatIdx < 0) {
      return `rbcell_${block.rowIdx}_${col}_empty`;
    }
    const photoUUID = cell.item.photoUUID !== undefined ? String(cell.item.photoUUID).trim() : '';
    if (photoUUID.length > 0) {
      return `rbcell_${block.rowIdx}_${col}_uuid_${photoUUID}`;
    }
    if (cell.numericId >= 0) {
      return `rbcell_${block.rowIdx}_${col}_id_${cell.numericId}`;
    }
    return `rbcell_${block.rowIdx}_${col}_flat_${cell.flatIdx}`;
  }

  private async loadAll(): Promise<void> {
    await recycleBinLoadAll(this.asActionsHost());
  }

  private async confirmBatchDownloadRecycle(): Promise<void> {
    await recycleBinConfirmBatchDownload(this.asActionsHost());
  }

  private async confirmRestore(): Promise<void> {
    await recycleBinConfirmRestore(this.asActionsHost());
  }

  private clearRbThumbResumeTimer(): void {
    if (this.session.overlay.rbThumbResumeTimer >= 0) {
      clearTimeout(this.session.overlay.rbThumbResumeTimer);
      this.session.overlay.rbThumbResumeTimer = -1;
    }
  }

  private recycleThumbCache(aggressive: boolean = false): void {
    trimThumbPixCacheForList(this.items.length, aggressive);
  }

  private onListScrollStateChange(scrollState: ScrollState): void {
    if (!this.rbSlideGestureActive && !this.rbScrollEnabled) {
      this.rbScrollEnabled = true;
    }
    if (!this.rbSlideGestureActive) {
      this.session.selection.rbThumbHitBounds.clear();
    }
    if (scrollState !== ScrollState.Idle) {
      this.clearRbThumbResumeTimer();
      /*
       * 贴边划选期间保持缩略图管线开启，依靠 LazyForEach 的前方缓存行持续预取；
       * 普通快速滚动仍暂停，避免网络解码任务和滚动布局同时制造主线程压力。
       */
      if (gallerySlideAutoScrollIsRunning()) {
        this.rbThumbLoadingPaused = false;
        return;
      }
      if (!this.rbThumbLoadingPaused) {
        this.rbThumbLoadingPaused = true;
      }
      this.recycleThumbCache(false);
      return;
    }
    this.clearRbThumbResumeTimer();
    this.session.overlay.rbThumbResumeTimer = setTimeout((): void => {
      this.session.overlay.rbThumbResumeTimer = -1;
      this.rbThumbLoadingPaused = false;
    }, 96);
  }

  private asSelectionHost(): RecycleBinSelectionHost {
    if (this.selectionHostCache !== undefined) {
      return this.selectionHostCache;
    }
    const self = this;
    class RecycleBinSelectionHostBridge implements RecycleBinSelectionHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(v: string) { self.baseUrl = v; }

      get items(): RecycleBinListItem[] { return self.items; }
      set items(v: RecycleBinListItem[]) { self.items = v; }

      get columnsPerRow(): number { return self.columnsPerRow; }
      set columnsPerRow(v: number) { self.columnsPerRow = fnClampGridColumns(v); }

      get selectionMode(): boolean { return self.selectionMode; }
      set selectionMode(v: boolean) { self.setSelectionModeState(v); }

      get selectedIds(): number[] { return self.session.selection.selectedIds; }
      set selectedIds(v: number[]) { self.setSelectedIdsState(v); }

      get listScroller(): Scroller { return self.session.list.listScroller; }
      set listScroller(v: Scroller) { self.session.list.listScroller = v; }

      get listDomId(): string { return RECYCLE_BIN_LIST_DOM_ID; }
      set listDomId(_v: string) {}

      get rbSlideGestureActive(): boolean { return self.rbSlideGestureActive; }
      set rbSlideGestureActive(v: boolean) { self.rbSlideGestureActive = v; }

      get rbScrollEnabled(): boolean { return self.rbScrollEnabled; }
      set rbScrollEnabled(v: boolean) { self.rbScrollEnabled = v; }

      get rbLongPressIgnoreUntil(): number { return self.session.selection.rbLongPressIgnoreUntil; }
      set rbLongPressIgnoreUntil(v: number) { self.session.selection.rbLongPressIgnoreUntil = v; }

      get rbThumbHitBounds(): Map<string, RbThumbHitRect> { return self.session.selection.rbThumbHitBounds; }
      set rbThumbHitBounds(v: Map<string, RbThumbHitRect>) { self.session.selection.rbThumbHitBounds = v; }

      get rbSlideRefX(): number { return self.session.selection.rbSlideRefX; }
      set rbSlideRefX(v: number) { self.session.selection.rbSlideRefX = v; }

      get rbSlideRefY(): number { return self.session.selection.rbSlideRefY; }
      set rbSlideRefY(v: number) { self.session.selection.rbSlideRefY = v; }

      get rbSlideHasRef(): boolean { return self.session.selection.rbSlideHasRef; }
      set rbSlideHasRef(v: boolean) { self.session.selection.rbSlideHasRef = v; }

      get rbSlideAnchorFlat(): number { return self.session.selection.rbSlideAnchorFlat; }
      set rbSlideAnchorFlat(v: number) { self.session.selection.rbSlideAnchorFlat = v; }

      get rbSlideUnionBase(): number[] { return self.session.selection.rbSlideUnionBase; }
      set rbSlideUnionBase(v: number[]) { self.session.selection.rbSlideUnionBase = v; }

      get rbSlideLastEndFlat(): number { return self.session.selection.rbSlideLastEndFlat; }
      set rbSlideLastEndFlat(v: number) { self.session.selection.rbSlideLastEndFlat = v; }

      get rbSlideLastAppliedEndFlat(): number { return self.session.selection.rbSlideLastAppliedEndFlat; }
      set rbSlideLastAppliedEndFlat(v: number) { self.session.selection.rbSlideLastAppliedEndFlat = v; }

      toast(msg: string): void { self.toast(msg); }
    }
    this.selectionHostCache = new RecycleBinSelectionHostBridge();
    return this.selectionHostCache;
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
      this.session.overlay.liveSaveResolver = (choice: LivePhotoSaveChoice): void => {
        resolve(choice === 'privilege');
      };
      this.liveSaveSheetVisible = true;
    });
  }

  private completeLivePhotoSave(choice: LivePhotoSaveChoice): void {
    const resolver = this.session.overlay.liveSaveResolver;
    this.session.overlay.liveSaveResolver = undefined;
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

  private askChoice(title: string, buttons: string[]): Promise<number> {
    if (this.choiceSheetVisible) {
      return Promise.resolve(-1);
    }
    return new Promise<number>((resolve: (index: number) => void) => {
      this.choiceSheetTitle = title;
      this.choiceSheetButtons = buttons;
      this.session.overlay.choiceSheetResolver = resolve;
      this.choiceSheetVisible = true;
    });
  }

  private completeChoice(index: number): void {
    const resolver = this.session.overlay.choiceSheetResolver;
    this.session.overlay.choiceSheetResolver = undefined;
    this.choiceSheetVisible = false;
    if (resolver !== undefined) {
      resolver(index);
    }
  }

  private asActionsHost(): RecycleBinActionsHost {
    if (this.actionsHostCache !== undefined) {
      return this.actionsHostCache;
    }
    const self = this;
    class RecycleBinActionsHostBridge implements RecycleBinActionsHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(v: string) { self.baseUrl = v; }

      get loading(): boolean { return self.loading; }
      set loading(v: boolean) { self.loading = v; }

      get restoring(): boolean { return self.restoring; }
      set restoring(v: boolean) { self.restoring = v; }

      get rbBatchDownloading(): boolean { return self.rbBatchDownloading; }
      set rbBatchDownloading(v: boolean) { self.rbBatchDownloading = v; }

      get rbBackgroundLoading(): boolean { return self.rbBackgroundLoading; }
      set rbBackgroundLoading(v: boolean) { self.rbBackgroundLoading = v; }

      get error(): string { return self.error; }
      set error(v: string) { self.error = v; }

      get items(): RecycleBinListItem[] { return self.items; }
      set items(v: RecycleBinListItem[]) { self.items = v; }

      get selectedIds(): number[] { return self.session.selection.selectedIds; }
      set selectedIds(v: number[]) { self.setSelectedIdsState(v); }

      toast(msg: string): void { self.toast(msg); }
      exitSelection(): void { self.exitSelection(); }
      askLivePhotoSave(): Promise<LivePhotoSaveChoice> { return self.askLivePhotoSave(); }
      askChoice(title: string, buttons: string[]): Promise<number> { return self.askChoice(title, buttons); }
    }
    this.actionsHostCache = new RecycleBinActionsHostBridge();
    return this.actionsHostCache;
  }

  @Builder
  private thumbCell(it: RecycleBinListItem, flatIdx: number, thumbRel: string, nid: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (thumbRel.length > 0) {
        GalleryNetworkThumb({
          uri: nasUrl(this.baseUrl, thumbRel),
          isVideo: false,
          isGif: false,
          paused: this.rbThumbLoadingPaused,
          sharedTransitionId: nid >= 0 ? gallerySharedTransitionId(`${nid}`) : ''
        })
          .width('100%')
          .aspectRatio(1)
      } else {
        Column() {
          Text('—')
            .fontSize(22)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .aspectRatio(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.card_background'))
      }
      GalleryAlbumSelectionOverlay({
        itemId: nid >= 0 ? `${nid}` : '',
        visualScope: GALLERY_SELECTION_SCOPE_RECYCLE,
        selectionMode: this.selectionMode
      })
    }
    .layoutWeight(1)
    .aspectRatio(1)
    .id(this.rbDomId(flatIdx))
    .onAreaChange((): void => {
      this.recordRbThumbRect(flatIdx);
    })
    .onClick((): void => {
      this.onCellClick(it, flatIdx);
    })
  }

  @Builder
  private rbCellSlot(block: RecycleBinRowBlock, col: number) {
    if (!this.rbCellHasItem(block, col)) {
      Blank().layoutWeight(1).aspectRatio(1)
    } else {
      this.thumbCell(
        this.rbCellItem(block, col),
        this.rbCellFlatIdx(block, col),
        this.rbCellThumbRel(block, col),
        this.rbCellNumericId(block, col)
      )
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
      GalleryGridChrome({
        selectionMode: this.selectionMode,
        selectedCount: this.selectedCount,
        title: '回收站',
        fallbackTitle: '回收站',
        showCountSubtitle: false,
        topSafeInsetVp: this.systemTopInsetVp,
        useMoreMenu: false,
        scrollerList: [this.session.list.listScroller],
        onCancelSelection: (): void => {
          this.exitSelection();
        },
        onBack: (): void => {
          this.onBackPress();
        },
        onToggleMode: (): void => {
          this.toggleToolbarMode();
        }
      })
        .width('100%')

      if (this.loading) {
        FnInlineLoading({ text: '加载回收站…', topOffsetVp: 24 }).layoutWeight(1)
      } else if (this.error.length > 0) {
        Column({ space: 12 }) {
          FnStateText({ text: this.error, topOffsetVp: 24 })
          FnHdsPillButton({
            text: '刷新',
            widthValue: 104,
            heightValue: 40,
            fontSizeValue: 16,
            fontColorValue: $r('app.color.brand_primary'),
            action: (): void => {
              void this.loadAll();
            }
          })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.items.length === 0) {
        FnStateText({
          text: '回收站为空',
          topOffsetVp: 24
        }).layoutWeight(1)
      } else {
        Stack({ alignContent: Alignment.Bottom }) {
          Column() {
            List({ scroller: this.session.list.listScroller }) {
              LazyForEach(this.session.list.rbRowSource, (block: RecycleBinRowBlock) => {
                ListItem() {
                  Row({ space: 2 }) {
                    ForEach(block.cells, (_cell: RecycleBinRowBlockCell, col: number) => {
                      this.rbCellSlot(block, col)
                    }, (_cell: RecycleBinRowBlockCell, col: number) => this.rbCellStableKey(block, col))
                  }
                  .width('100%')
                  .padding({ left: 2, right: 2, top: 1, bottom: 1 })
                  .onTouch((event: TouchEvent): void => {
                    galleryGridHandleRowTouch(
                      this.session.list.slideTouch,
                      this.asSlideTouchHost(),
                      event,
                      (xPx: number, yPx: number): boolean => this.beginRbFirstSlideAtRow(block.rowStart, xPx, yPx)
                    );
                  })
                  .parallelGesture(GestureGroup(GestureMode.Parallel,
                    GestureGroup(GestureMode.Sequence,
                      LongPressGesture({ repeat: false, duration: GALLERY_GRID_SEQUENCE_LONG_PRESS_MS })
                        .onAction((ev: GestureEvent): void => {
                          if (!galleryGridOnSequenceLongPress(this.session.list.slideTouch, this.asSlideTouchHost())) {
                            return;
                          }
                          galleryGridClearInitialSlide(this.session.list.slideTouch);
                          this.endRbSlideSelectGesture();
                          const pt = this.readGestureFingerWindow(ev);
                          if (pt === null) {
                            return;
                          }
                          if (!this.beginRbFirstSlideAtRow(block.rowStart, this.vpToPx(pt.x), this.vpToPx(pt.y))) {
                            return;
                          }
                          galleryGridArmInitialSlide(this.session.list.slideTouch);
                        }),
                      PanGesture({
                        fingers: 1,
                        direction: PanDirection.All,
                        distance: GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE
                      })
                        .onActionUpdate((ev: GestureEvent): void => {
                          if (!galleryGridShouldUpdateSequencePan(this.session.list.slideTouch, this.asSlideTouchHost())) {
                            return;
                          }
                          this.onRbSlidePanUpdate(ev);
                        })
                        .onActionEnd((): void => {
                          galleryGridOnSequencePanFinish(this.session.list.slideTouch, this.asSlideTouchHost());
                        })
                        .onActionCancel((): void => {
                          galleryGridOnSequencePanFinish(this.session.list.slideTouch, this.asSlideTouchHost());
                        })
                    ),
                    PanGesture({
                      fingers: 1,
                      direction: PanDirection.Horizontal,
                      distance: GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE
                    })
                      .onActionStart((ev: GestureEvent): void => {
                        this.session.list.slideTouch.secondaryPanDriving = false;
                        if (!galleryGridCanStartSecondaryPan(this.session.list.slideTouch, this.asSlideTouchHost(), ev)) {
                          return;
                        }
                        const pt = this.readGestureFingerWindow(ev);
                        if (pt === null) {
                          galleryGridSlideLog('rb_sec_start_skip', 'reason=no_pointer');
                          return;
                        }
                        const xPx = this.vpToPx(pt.x);
                        const yPx = this.vpToPx(pt.y);
                        const fi = this.pickRbThumbFlatForRow(block.rowStart, xPx, yPx);
                        if (fi < 0 || fi >= this.items.length) {
                          galleryGridSlideLog('rb_sec_start_skip',
                            `reason=no_hit row=${block.rowStart} flat=${fi}` +
                              ` xy=${Math.round(xPx)},${Math.round(yPx)} total=${this.items.length}`);
                          return;
                        }
                        galleryGridSlideLog('rb_sec_start',
                          `flat=${fi} xy=${Math.round(xPx)},${Math.round(yPx)} selected=${this.session.selection.selectedIds.length}`);
                        galleryGridOnSecondaryPanStart(this.session.list.slideTouch);
                        this.beginRbSlideSelectGesture(ev, fi);
                      })
                      .onActionUpdate((ev: GestureEvent): void => {
                        if (!galleryGridShouldUpdateSecondaryPan(this.session.list.slideTouch, this.asSlideTouchHost())) {
                          return;
                        }
                        this.onRbSlidePanUpdate(ev);
                      })
                      .onActionEnd((): void => {
                        galleryGridOnSecondaryPanFinish(this.session.list.slideTouch, this.asSlideTouchHost());
                      })
                      .onActionCancel((): void => {
                        galleryGridOnSecondaryPanFinish(this.session.list.slideTouch, this.asSlideTouchHost());
                      })
                  ))
                }
                .draggable(false)
              }, (block: RecycleBinRowBlock) => block.key)
              ListItem() {
                Column() {
                  Blank()
                    .width('100%')
                    .height(this.selectionMode && this.selectedCount > 0 ? 80 : 32)
                }
                .width('100%')
              }
            }
            .width('100%')
            .layoutWeight(1)
            .id(RECYCLE_BIN_LIST_DOM_ID)
            .cachedCount(this.columnsPerRow >= 4 ? 2 : 3)
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
            .divider({ strokeWidth: 0 })
            .enableScrollInteraction(this.rbScrollEnabled)
            .onTouch((event: TouchEvent): void => {
              galleryGridHandleListTouch(this.session.list.slideTouch, this.asSlideTouchHost(), event);
            })
            .onDidScroll((offset: number, scrollState: ScrollState): void => {
              gallerySlideAutoScrollOnListDidScroll(offset, scrollState);
              this.onListScrollStateChange(scrollState);
            })

            if (this.rbBackgroundLoading) {
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
            RecycleBinBatchBar({
              downloading: this.rbBatchDownloading,
              restoring: this.restoring,
              onDownload: (): void => {
                void this.confirmBatchDownloadRecycle();
              },
              onRestore: (): void => {
                void this.confirmRestore();
              }
            })
              .width('100%')
              // HdsTabs 即使透明仍会参与命中，只保留底部按钮所需高度。
              .height(GALLERY_BATCH_BAR_TOTAL_HEIGHT_VP)
          }

          if (this.restoring || this.rbBatchDownloading) {
            FnFullLoadingMask({
              text: this.restoring ? '正在还原…' : '下载中…',
              topOffsetVp: 0
            })
          }
          if (this.previewOpening) {
            GalleryPreviewOpeningMask({ topOffsetVp: 0 })
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      Column()
        .width(1)
        .height(1)
        .bindSheet(this.liveSaveSheetVisible, this.liveSaveSheetBuilder, fnHdsSaveButtonSheetOptions(
          LIVE_PHOTO_PRIVILEGE_SHEET_TITLE,
          (): void => {
            this.completeLivePhotoSave('cancel');
          }
        ))
    }
    .width('100%')
    .height('100%')
    .id(GALLERY_PREVIEW_SOURCE_RECYCLE_ID)
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

@Builder
export function RecycleBinPageNavigationContent() {
  RecycleBinPage()
}
