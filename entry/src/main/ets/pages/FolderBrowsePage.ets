import { UIContext } from '@kit.ArkUI';
import { FN_MEDIA_BASE_URL } from '../auth/AppSession';
import {
  FolderViewCoverItem,
  GalleryListItem
} from '../model/FnApiTypes';
import {
  GalleryNetworkThumb,
  isGifItem,
  isVideoItem,
  nasUrl,
  pickThumb,
  trimThumbPixCacheForList
} from '../album/GalleryAlbumCommon';
import { isLivePhotoItem } from '../album/livephoto/LivePhotoDetect';
import {
  askLivePhotoSaveChoice,
  LivePhotoSaveActionSheet,
  LivePhotoSaveChoice,
  LIVE_PHOTO_PRIVILEGE_SHEET_TITLE
} from '../album/livephoto/LivePhotoSaveActionSheet';
import { FnHdsChoiceSheet, fnHdsFitContentSheetOptions, fnHdsSaveButtonSheetOptions } from '../common/FnHdsOverlay';
import { GalleryAlbumNavigation } from '../album/GalleryAlbumNavigation';
import { GalleryPreviewNavStore } from '../album/GalleryPreviewNavStore';
import { GALLERY_PREVIEW_OPENING_KEY } from '../album/GalleryPreviewEntryGate';
import {
  GALLERY_PREVIEW_HERO_ACTIVE_KEY,
  GALLERY_PREVIEW_SOURCE_FOLDER_ID,
  gallerySharedSourceDomId
} from '../album/GallerySharedTransition';
import { GalleryPreviewOpeningMask } from '../album/GalleryPreviewOpeningMask';
import { GalleryAlbumBatchActionBar } from '../album/GalleryAlbumBatchActionBar';
import {
  GALLERY_SELECTION_SCOPE_FOLDER,
  GalleryAlbumSelectionOverlay,
  galleryAlbumSyncSelectionVisualState
} from '../album/galleryAlbumTab/GalleryAlbumSelectionOverlay';
import { gallerySlideshowLaunchForItems } from '../album/slideshow/GallerySlideshowLauncher';
import {
  GallerySlideshowConfig,
  GallerySlideshowScope,
  GallerySlideshowScopeKind,
  gallerySlideshowScopeLabel
} from '../album/slideshow/GallerySlideshowTypes';
import { GallerySlideshowSettingsSheet } from '../album/slideshow/GallerySlideshowSettingsSheet';
import { FnListDataSource } from '../common/FnListDataSource';
import { FN_SYSTEM_TOP_INSET_VP_KEY } from '../common/FnSystemAvoidArea';
import { FN_WINDOW_WIDTH_BP_KEY, fnAdaptiveGridColumns, fnClampGridColumns } from '../common/FnWindowBreakpoint';
import { FnFullLoadingMask, FnInlineLoading, FnStateText } from '../common/FnUiCommon';
import { GALLERY_BATCH_BAR_TOTAL_HEIGHT_VP } from '../common/GalleryButtonStyles';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import { gallerySlideAutoScrollIsRunning, gallerySlideAutoScrollOnListDidScroll } from '../album/GallerySlideAutoScroll';
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
  galleryGridSlideLog,
  galleryGridShouldUpdateSecondaryPan,
  galleryGridShouldUpdateSequencePan,
  GalleryGridSlideTouchHost,
  GalleryGridSlideTouchSession,
  GALLERY_GRID_SEQUENCE_LONG_PRESS_MS
} from '../album/GalleryGridSlideTouch';
import {
  FOLDER_BROWSE_BASE_COLUMNS,
  FOLDER_BROWSE_KIND_MEDIA,
  FOLDER_BROWSE_LIST_DOM_ID,
  FolderBrowseFolderItem,
  FolderBrowseGridItem,
  FolderBrowseFingerWindowPoint,
  FolderBrowseRowBlock,
  FolderBrowseRowBlockCell,
  FolderBrowseThumbHitRect
} from './folderBrowsePage/FolderBrowseTypes';
import {
  folderBrowseApplyCoverUris,
  folderBrowseBuildGrid,
  folderBrowseCoverDirNames,
  folderBrowseCoverDirNamesFallback,
  folderBrowseIsOsRootPath,
  folderBrowseLabelOf,
  folderBrowseLandingStack,
  folderBrowseMediaId,
  folderBrowsePathAllowed,
  folderBrowseSelectionHasFolder,
  folderBrowseSelectionIdOf
} from './folderBrowsePage/FolderBrowseLogic';
import { GalleryGridChrome } from '../album/galleryList/GalleryGridChrome';
import {
  GalleryListBackStep,
  galleryListPopOrRouterBack,
  galleryListTryConsumeOverlays
} from '../album/galleryList/GalleryListBack';
import { FolderBrowseNavStore } from './folderBrowsePage/FolderBrowseNavStore';
import {
  folderBrowseConfirmBatchDelete,
  folderBrowseConfirmBatchDownload,
  FolderBrowseBatchActionsHost
} from './folderBrowsePage/FolderBrowseBatchActions';
import {
  folderBrowseFetchCoverBatch,
  folderBrowseLoadCurrent,
  folderBrowseLoadMoreMedia,
  FolderBrowseDataLoaderHost
} from './folderBrowsePage/FolderBrowseDataLoader';
import {
  folderBrowseBeginSlideSelectGesture,
  folderBrowseBeginSlideSelectGestureAtWindowPx,
  folderBrowseDomId,
  folderBrowseEndSlideSelectGesture,
  folderBrowseExitSelection,
  folderBrowseOnCellClick,
  folderBrowseOnSlidePanUpdate,
  folderBrowseOnSlideTouchMoveWindow,
  folderBrowseOnThumbLongPress,
  folderBrowsePickThumbFlatForRow,
  folderBrowseReadGestureFingerWindow,
  folderBrowseRecordThumbRect,
  folderBrowseToggleToolbarMode,
  FolderBrowseSelectionHost
} from './folderBrowsePage/FolderBrowseSelectionController';

@Entry
@Component
struct FolderBrowsePage {
  private albumNavigationMode: boolean = false;
  @StorageProp(FN_MEDIA_BASE_URL) private baseUrl: string = '';
  @StorageProp(FN_WINDOW_WIDTH_BP_KEY) @Watch('onWindowWidthBpChanged') private windowWidthBp: number =
    WidthBreakpoint.WIDTH_SM;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(GALLERY_PREVIEW_OPENING_KEY) private previewOpening: boolean = false;
  @StorageProp(GALLERY_PREVIEW_HERO_ACTIVE_KEY) private previewHeroActive: boolean = false;
  @State private loading: boolean = false;
  @State private loadingMore: boolean = false;
  @State private error: string = '';
  @State private title: string = '文件夹';
  @State private thumbLoadingPaused: boolean = false;
  @State private gridItems: FolderBrowseGridItem[] = [];
  @State private columnsPerRow: number = FOLDER_BROWSE_BASE_COLUMNS;
  @State private selectionMode: boolean = false;
  @State private selectedCount: number = 0;
  @State private hasFolderSelected: boolean = false;
  @State private moreMenuExpanded: boolean = false;
  @State private canGoUpFolder: boolean = false;
  @State private slideshowSettingsVisible: boolean = false;
  @State private slideshowPreparing: boolean = false;
  @State private batchDeleting: boolean = false;
  @State private batchDownloading: boolean = false;
  @State private liveSaveSheetVisible: boolean = false;
  @State private choiceSheetVisible: boolean = false;
  @State private choiceSheetTitle: string = '';
  @State private choiceSheetButtons: string[] = [];
  @State private fbSlideGestureActive: boolean = false;
  @State private fbScrollEnabled: boolean = true;
  private readonly rowSource: FnListDataSource<FolderBrowseRowBlock> = new FnListDataSource<FolderBrowseRowBlock>();
  private listScroller: Scroller = new Scroller();
  private pathStack: string[] = [];
  /** 当前所在的相册授权根；空路径仅表示“已配置文件夹”虚拟根层。 */
  private entryFloorPath: string = '';
  private lockToEntry: boolean = false;
  private entryFloorResolved: boolean = true;
  private allowedRootPaths: string[] = [];
  private folderChanging: boolean = false;
  private folders: FolderBrowseFolderItem[] = [];
  private mediaItems: GalleryListItem[] = [];
  private selectedIds: string[] = [];
  private mediaOffset: number = 0;
  private mediaHasMore: boolean = false;
  private loadGen: number = 0;
  private albumBackHandlerToken: number = 0;
  private thumbResumeTimer: number = -1;
  private slideshowRequestSeq: number = 0;
  private liveSaveResolver: ((choice: LivePhotoSaveChoice) => void) | undefined = undefined;
  private choiceSheetResolver: ((index: number) => void) | undefined = undefined;
  private fbLongPressIgnoreUntil: number = 0;
  private fbThumbHitBounds: Map<string, FolderBrowseThumbHitRect> = new Map();
  private fbSlideRefX: number = 0;
  private fbSlideRefY: number = 0;
  private fbSlideHasRef: boolean = false;
  private fbSlideAnchorFlat: number = -1;
  private fbSlideUnionBase: string[] = [];
  private fbSlideLastEndFlat: number = -1;
  private fbSlideLastAppliedEndFlat: number = -99999;
  private slideTouch: GalleryGridSlideTouchSession = new GalleryGridSlideTouchSession();

  onBackPress(): boolean {
    this.handleBack();
    return true;
  }

  private handleBack(): void {
    const overlaySteps: GalleryListBackStep[] = [
      new GalleryListBackStep(this.liveSaveSheetVisible, (): void => {
        this.completeLivePhotoSave('cancel');
      }),
      new GalleryListBackStep(this.choiceSheetVisible, (): void => {
        this.completeChoice(-1);
      }),
      new GalleryListBackStep(this.slideshowSettingsVisible, (): void => {
        this.dismissSlideshowSettings();
      }),
      new GalleryListBackStep(this.moreMenuExpanded, (): void => {
        this.dismissMoreMenu();
      }),
      new GalleryListBackStep(this.selectionMode, (): void => {
        this.exitSelection();
      })
    ];
    if (galleryListTryConsumeOverlays(overlaySteps)) {
      return;
    }
    // 返回只离开本页；目录上一级交给顶栏按钮，避免从详情路径进来后被一层层退回。
    this.navigateOut();
  }

  private navigateOut(): void {
    galleryListPopOrRouterBack(this.albumNavigationMode, (): void => {
      this.getUIContext().getRouter().back();
    });
  }

  aboutToAppear(): void {
    this.albumNavigationMode = this.queryNavDestinationInfo() !== undefined &&
      GalleryAlbumNavigation.isAvailable();
    this.thumbLoadingPaused = false;
    this.columnsPerRow = fnAdaptiveGridColumns(FOLDER_BROWSE_BASE_COLUMNS, this.windowWidthBp);
    this.applyIncomingFolderPath();
    if (this.albumNavigationMode) {
      this.albumBackHandlerToken = GalleryAlbumNavigation.registerBackHandler((): boolean => {
        this.handleBack();
        return true;
      });
    } else {
      const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
      if (rp !== undefined && rp['baseUrl'] !== undefined) {
        this.baseUrl = String(rp['baseUrl']);
      }
    }
    void this.loadCurrent(true);
  }

  aboutToDisappear(): void {
    GalleryAlbumNavigation.unregisterBackHandler(this.albumBackHandlerToken);
    this.clearThumbResumeTimer();
    trimThumbPixCacheForList(this.gridItems.length, false);
    folderBrowseEndSlideSelectGesture(this.asSelectionHost());
    galleryAlbumSyncSelectionVisualState(false, [], GALLERY_SELECTION_SCOPE_FOLDER);
  }

  private applyIncomingFolderPath(): void {
    let incoming = FolderBrowseNavStore.consumePendingPath();
    FolderBrowseNavStore.consumeLockToEntry();
    if (incoming.length === 0) {
      const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
      if (rp !== undefined && rp['folderPath'] !== undefined) {
        incoming = String(rp['folderPath']);
      }
    }
    const landing = folderBrowseLandingStack(incoming);
    this.pathStack = landing;
    // 具体路径入口先锁住；loadCurrent 会用相册已配置根目录解析真正安全边界。
    this.lockToEntry = landing.length > 0;
    this.entryFloorPath = '';
    this.entryFloorResolved = !this.lockToEntry;
    this.syncFolderHierarchyState();
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {
    }
  }

  private currentPath(): string {
    if (this.pathStack.length === 0) {
      return '';
    }
    return this.pathStack[this.pathStack.length - 1];
  }

  private syncFolderHierarchyState(): void {
    if (this.pathStack.length === 0) {
      this.canGoUpFolder = false;
      return;
    }
    this.canGoUpFolder = !this.lockToEntry ||
      (this.entryFloorResolved && this.pathStack.length > 1);
  }

  private goUpFolder(): void {
    if (this.folderChanging || !this.canGoUpFolder || this.pathStack.length === 0) {
      return;
    }
    const nextStack = this.pathStack.slice(0, this.pathStack.length - 1);
    if (this.lockToEntry && nextStack.length === 0) {
      return;
    }
    this.folderChanging = true;
    this.pathStack = nextStack;
    this.syncFolderHierarchyState();
    void this.loadCurrent(true).finally((): void => {
      this.folderChanging = false;
    });
  }

  private syncTitle(): void {
    const path = this.currentPath();
    this.title = path.length === 0 ? '文件夹' : folderBrowseLabelOf(path);
  }

  private publishGrid(): void {
    const next = folderBrowseBuildGrid(this.folders, this.mediaItems);
    this.gridItems = next;
    this.rebuildRowBlocks();
  }

  private totalCount(): number {
    return this.gridItems.length;
  }

  private onWindowWidthBpChanged(): void {
    const next = fnAdaptiveGridColumns(FOLDER_BROWSE_BASE_COLUMNS, this.windowWidthBp);
    if (next === this.columnsPerRow) {
      return;
    }
    this.columnsPerRow = next;
    this.rebuildRowBlocks();
  }

  private rebuildRowBlocks(): void {
    const cols = fnClampGridColumns(this.columnsPerRow);
    const blocks: FolderBrowseRowBlock[] = [];
    const rowCount = Math.ceil(this.gridItems.length / cols);
    for (let rowIdx = 0; rowIdx < rowCount; rowIdx++) {
      const rowStart = rowIdx * cols;
      const cells: FolderBrowseRowBlockCell[] = [];
      let cellSig = '';
      for (let col = 0; col < cols; col++) {
        const flatIdx = rowStart + col;
        if (flatIdx >= this.gridItems.length) {
          const empty: FolderBrowseRowBlockCell = { flatIdx: -1 };
          cells.push(empty);
          cellSig += `_sk${col}`;
          continue;
        }
        const item = this.gridItems[flatIdx];
        const filled: FolderBrowseRowBlockCell = { flatIdx: flatIdx, item: item };
        cells.push(filled);
        cellSig += `_${item.key}_${item.coverUri}`;
      }
      const block: FolderBrowseRowBlock = {
        key: `fbrow_${rowIdx}${cellSig}`,
        rowIdx: rowIdx,
        rowStart: rowStart,
        cells: cells
      };
      blocks.push(block);
    }
    this.rowSource.reloadAll(blocks);
  }

  private clearThumbResumeTimer(): void {
    if (this.thumbResumeTimer >= 0) {
      clearTimeout(this.thumbResumeTimer);
      this.thumbResumeTimer = -1;
    }
  }

  private onGridScrollStateChange(scrollState: ScrollState): void {
    if (!this.fbSlideGestureActive && !this.fbScrollEnabled) {
      this.fbScrollEnabled = true;
    }
    if (!this.fbSlideGestureActive) {
      this.fbThumbHitBounds.clear();
    }
    if (scrollState !== ScrollState.Idle) {
      this.clearThumbResumeTimer();
      if (gallerySlideAutoScrollIsRunning()) {
        this.thumbLoadingPaused = false;
        return;
      }
      if (!this.thumbLoadingPaused) {
        this.thumbLoadingPaused = true;
      }
      trimThumbPixCacheForList(this.gridItems.length, false);
      return;
    }
    this.clearThumbResumeTimer();
    this.thumbResumeTimer = setTimeout((): void => {
      this.thumbResumeTimer = -1;
      this.thumbLoadingPaused = false;
    }, 96);
  }

  private async loadCurrent(reset: boolean): Promise<void> {
    await folderBrowseLoadCurrent(this.asDataLoaderHost(), reset);
  }

  private async loadCovers(gen: number, currentPath: string): Promise<void> {
    if (this.folders.length === 0) {
      return;
    }
    let names: string[] = folderBrowseCoverDirNames(this.folders, currentPath);
    let allCovers: FolderViewCoverItem[] = await folderBrowseFetchCoverBatch(currentPath, names);
    if (gen !== this.loadGen) {
      return;
    }
    if (allCovers.length === 0) {
      names = folderBrowseCoverDirNamesFallback(this.folders, currentPath);
      allCovers = await folderBrowseFetchCoverBatch(currentPath, names);
      if (gen !== this.loadGen) {
        return;
      }
    }
    if (allCovers.length === 0) {
      return;
    }
    folderBrowseApplyCoverUris(this.folders, allCovers, names);
    this.publishGrid();
  }

  private async loadMoreMedia(): Promise<void> {
    await folderBrowseLoadMoreMedia(this.asDataLoaderHost());
  }

  private enterFolder(path: string): void {
    const next = path.trim();
    if (this.folderChanging || next.length === 0 || folderBrowseIsOsRootPath(next)) {
      this.toast('无法打开该文件夹');
      return;
    }
    if (this.lockToEntry) {
      if (this.currentPath().length === 0) {
        if (this.allowedRootPaths.indexOf(next) < 0) {
          this.toast('无权访问该目录');
          return;
        }
        this.entryFloorPath = next;
      } else if (!folderBrowsePathAllowed(next, this.entryFloorPath)) {
        this.toast('无权访问该目录');
        return;
      }
    }
    if (next === this.currentPath()) {
      return;
    }
    this.folderChanging = true;
    this.pathStack = this.pathStack.concat([next]);
    this.syncFolderHierarchyState();
    void this.loadCurrent(true).finally((): void => {
      this.folderChanging = false;
    });
  }

  private openMedia(index: number): void {
    if (index < 0 || index >= this.mediaItems.length) {
      this.toast('无法预览该项');
      return;
    }
    GalleryPreviewNavStore.openPreview(
      this.getUIContext(),
      this.baseUrl,
      this.mediaItems,
      index,
      GALLERY_PREVIEW_SOURCE_FOLDER_ID
    );
  }

  private setSelectionModeState(value: boolean): void {
    if (this.selectionMode === value) {
      return;
    }
    this.selectionMode = value;
    galleryAlbumSyncSelectionVisualState(this.selectionMode, this.selectedIds, GALLERY_SELECTION_SCOPE_FOLDER);
  }

  private setSelectedIds(ids: string[]): void {
    this.selectedIds = ids;
    this.selectedCount = ids.length;
    this.hasFolderSelected = folderBrowseSelectionHasFolder(ids);
    galleryAlbumSyncSelectionVisualState(this.selectionMode, ids, GALLERY_SELECTION_SCOPE_FOLDER);
  }

  private enterSelection(): void {
    if (this.selectionMode) {
      return;
    }
    this.setSelectionModeState(true);
    this.setSelectedIds(this.selectedIds);
  }

  private exitSelection(): void {
    folderBrowseExitSelection(this.asSelectionHost());
  }

  private toggleToolbarMode(): void {
    folderBrowseToggleToolbarMode(this.asSelectionHost());
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
    this.enterSelection();
  }

  private canStartSlideshow(): boolean {
    return this.mediaItems.length > 0 || this.mediaHasMore;
  }

  private openSlideshowSettings(): void {
    this.dismissMoreMenu();
    if (!this.canStartSlideshow()) {
      this.toast('暂无可播放媒体');
      return;
    }
    this.slideshowSettingsVisible = true;
  }

  private dismissSlideshowSettings(): void {
    this.slideshowSettingsVisible = false;
  }

  private slideshowScope(): GallerySlideshowScope {
    const scope: GallerySlideshowScope = {
      kind: GallerySlideshowScopeKind.FLAT_ITEMS,
      scopeLabel: this.title
    };
    return scope;
  }

  private async waitForAllMedia(isActive: () => boolean): Promise<void> {
    let guard = 0;
    while (this.mediaHasMore && isActive() && guard < 40) {
      const before = this.mediaOffset;
      await this.loadMoreMedia();
      if (this.mediaOffset <= before) {
        break;
      }
      guard++;
    }
  }

  private async startFolderSlideshow(config: GallerySlideshowConfig): Promise<void> {
    if (this.slideshowPreparing || !this.canStartSlideshow()) {
      return;
    }
    this.slideshowPreparing = true;
    const seq = ++this.slideshowRequestSeq;
    const isActive = (): boolean => seq === this.slideshowRequestSeq;
    try {
      await this.waitForAllMedia(isActive);
      if (!isActive()) {
        return;
      }
      await gallerySlideshowLaunchForItems(
        this.getUIContext(),
        this.baseUrl,
        this.mediaItems,
        config,
        (msg: string): void => {
          this.toast(msg);
        },
        isActive,
        this.title
      );
      if (isActive()) {
        this.slideshowSettingsVisible = false;
      }
    } finally {
      if (isActive()) {
        this.slideshowPreparing = false;
      }
    }
  }

  private removeMediaByIds(ids: string[]): void {
    const next: GalleryListItem[] = [];
    for (let i = 0; i < this.mediaItems.length; i++) {
      const id: string = folderBrowseMediaId(this.mediaItems[i]);
      let drop = false;
      for (let j = 0; j < ids.length; j++) {
        if (ids[j] === id) {
          drop = true;
          break;
        }
      }
      if (drop) {
        continue;
      }
      next.push(this.mediaItems[i]);
    }
    this.mediaItems = next;
    this.mediaOffset = this.mediaItems.length;
    this.publishGrid();
  }

  private vpToPx(value: number): number {
    try {
      return this.getUIContext().vp2px(value);
    } catch (_e) {
      return value;
    }
  }

  private asSlideTouchHost(): GalleryGridSlideTouchHost {
    const self = this;
    class FolderBrowseSlideTouchHostBridge implements GalleryGridSlideTouchHost {
      getUIContext(): UIContext { return self.getUIContext(); }
      isSelectionMode(): boolean { return self.selectionMode; }
      isSlideActive(): boolean { return self.fbSlideGestureActive; }
      endSlide(): void { folderBrowseEndSlideSelectGesture(self.asSelectionHost()); }
      followSlideAtWindowPx(xPx: number, yPx: number): void {
        folderBrowseOnSlideTouchMoveWindow(self.asSelectionHost(), xPx, yPx);
      }
    }
    return new FolderBrowseSlideTouchHostBridge();
  }

  private asSelectionHost(): FolderBrowseSelectionHost {
    const self = this;
    class FolderBrowseSelectionHostBridge implements FolderBrowseSelectionHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(v: string) { self.baseUrl = v; }

      get gridItems(): FolderBrowseGridItem[] { return self.gridItems; }
      set gridItems(v: FolderBrowseGridItem[]) { self.gridItems = v; }

      get columnsPerRow(): number { return self.columnsPerRow; }
      set columnsPerRow(v: number) { self.columnsPerRow = fnClampGridColumns(v); }

      get selectionMode(): boolean { return self.selectionMode; }
      set selectionMode(v: boolean) { self.setSelectionModeState(v); }

      get selectedIds(): string[] { return self.selectedIds; }
      set selectedIds(v: string[]) { self.setSelectedIds(v); }

      get listScroller(): Scroller { return self.listScroller; }
      set listScroller(v: Scroller) { self.listScroller = v; }

      get listDomId(): string { return FOLDER_BROWSE_LIST_DOM_ID; }
      set listDomId(_v: string) {}

      get fbSlideGestureActive(): boolean { return self.fbSlideGestureActive; }
      set fbSlideGestureActive(v: boolean) { self.fbSlideGestureActive = v; }

      get fbScrollEnabled(): boolean { return self.fbScrollEnabled; }
      set fbScrollEnabled(v: boolean) { self.fbScrollEnabled = v; }

      get fbLongPressIgnoreUntil(): number { return self.fbLongPressIgnoreUntil; }
      set fbLongPressIgnoreUntil(v: number) { self.fbLongPressIgnoreUntil = v; }

      get fbThumbHitBounds(): Map<string, FolderBrowseThumbHitRect> { return self.fbThumbHitBounds; }
      set fbThumbHitBounds(v: Map<string, FolderBrowseThumbHitRect>) { self.fbThumbHitBounds = v; }

      get fbSlideRefX(): number { return self.fbSlideRefX; }
      set fbSlideRefX(v: number) { self.fbSlideRefX = v; }

      get fbSlideRefY(): number { return self.fbSlideRefY; }
      set fbSlideRefY(v: number) { self.fbSlideRefY = v; }

      get fbSlideHasRef(): boolean { return self.fbSlideHasRef; }
      set fbSlideHasRef(v: boolean) { self.fbSlideHasRef = v; }

      get fbSlideAnchorFlat(): number { return self.fbSlideAnchorFlat; }
      set fbSlideAnchorFlat(v: number) { self.fbSlideAnchorFlat = v; }

      get fbSlideUnionBase(): string[] { return self.fbSlideUnionBase; }
      set fbSlideUnionBase(v: string[]) { self.fbSlideUnionBase = v; }

      get fbSlideLastEndFlat(): number { return self.fbSlideLastEndFlat; }
      set fbSlideLastEndFlat(v: number) { self.fbSlideLastEndFlat = v; }

      get fbSlideLastAppliedEndFlat(): number { return self.fbSlideLastAppliedEndFlat; }
      set fbSlideLastAppliedEndFlat(v: number) { self.fbSlideLastAppliedEndFlat = v; }

      toast(msg: string): void { self.toast(msg); }
      openMedia(index: number): void { self.openMedia(index); }
      enterFolder(path: string): void { self.enterFolder(path); }
    }
    return new FolderBrowseSelectionHostBridge();
  }

  private beginFirstSlideAtRow(rowStart: number, xPx: number, yPx: number): boolean {
    const fi = folderBrowsePickThumbFlatForRow(this.asSelectionHost(), rowStart, xPx, yPx);
    if (fi < 0 || fi >= this.gridItems.length) {
      return false;
    }
    const item = this.gridItems[fi];
    if (!this.selectionMode) {
      folderBrowseOnThumbLongPress(this.asSelectionHost(), item, fi);
    }
    folderBrowseBeginSlideSelectGestureAtWindowPx(this.asSelectionHost(), fi, xPx, yPx);
    return true;
  }

  private asDataLoaderHost(): FolderBrowseDataLoaderHost {
    const self = this;
    class FolderBrowseDataLoaderHostBridge implements FolderBrowseDataLoaderHost {
      get loadGen(): number { return self.loadGen; }
      set loadGen(v: number) { self.loadGen = v; }

      get loading(): boolean { return self.loading; }
      set loading(v: boolean) { self.loading = v; }

      get loadingMore(): boolean { return self.loadingMore; }
      set loadingMore(v: boolean) { self.loadingMore = v; }

      get error(): string { return self.error; }
      set error(v: string) { self.error = v; }

      get selectionMode(): boolean { return self.selectionMode; }
      set selectionMode(v: boolean) { self.selectionMode = v; }

      get folders(): FolderBrowseFolderItem[] { return self.folders; }
      set folders(v: FolderBrowseFolderItem[]) { self.folders = v; }

      get mediaItems(): GalleryListItem[] { return self.mediaItems; }
      set mediaItems(v: GalleryListItem[]) { self.mediaItems = v; }

      get mediaOffset(): number { return self.mediaOffset; }
      set mediaOffset(v: number) { self.mediaOffset = v; }

      get mediaHasMore(): boolean { return self.mediaHasMore; }
      set mediaHasMore(v: boolean) { self.mediaHasMore = v; }

      get lockToEntry(): boolean { return self.lockToEntry; }
      set lockToEntry(v: boolean) { self.lockToEntry = v; }

      get entryFloorResolved(): boolean { return self.entryFloorResolved; }
      set entryFloorResolved(v: boolean) { self.entryFloorResolved = v; }

      get allowedRootPaths(): string[] { return self.allowedRootPaths; }
      set allowedRootPaths(v: string[]) { self.allowedRootPaths = v; }

      get entryFloorPath(): string { return self.entryFloorPath; }
      set entryFloorPath(v: string) { self.entryFloorPath = v; }

      get pathStack(): string[] { return self.pathStack; }
      set pathStack(v: string[]) { self.pathStack = v; }

      currentPath(): string { return self.currentPath(); }
      syncTitle(): void { self.syncTitle(); }
      exitSelection(): void { self.exitSelection(); }
      publishGrid(): void { self.publishGrid(); }
      navigateOut(): void { self.navigateOut(); }
      syncFolderHierarchyState(): void { self.syncFolderHierarchyState(); }
      loadCovers(gen: number, currentPath: string): void { void self.loadCovers(gen, currentPath); }
    }
    return new FolderBrowseDataLoaderHostBridge();
  }

  private asBatchActionsHost(): FolderBrowseBatchActionsHost {
    const self = this;
    class FolderBrowseBatchActionsHostBridge implements FolderBrowseBatchActionsHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(v: string) { self.baseUrl = v; }

      get mediaItems(): GalleryListItem[] { return self.mediaItems; }
      set mediaItems(v: GalleryListItem[]) { self.mediaItems = v; }

      get selectedIds(): string[] { return self.selectedIds; }
      set selectedIds(v: string[]) { self.setSelectedIds(v); }

      get batchDeleting(): boolean { return self.batchDeleting; }
      set batchDeleting(v: boolean) { self.batchDeleting = v; }

      get batchDownloading(): boolean { return self.batchDownloading; }
      set batchDownloading(v: boolean) { self.batchDownloading = v; }

      toast(msg: string): void { self.toast(msg); }
      exitSelection(): void { self.exitSelection(); }
      removeMediaByIds(ids: string[]): void { self.removeMediaByIds(ids); }
      askLivePhotoSave(): Promise<LivePhotoSaveChoice> { return self.askLivePhotoSave(); }
      askChoice(title: string, buttons: string[]): Promise<number> { return self.askChoice(title, buttons); }
    }
    return new FolderBrowseBatchActionsHostBridge();
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

  private liveFolderCoverUri(key: string): string {
    const list = this.gridItems;
    for (let i = 0; i < list.length; i++) {
      if (list[i].key === key) {
        return list[i].coverUri;
      }
    }
    return '';
  }

  private itemIsVideo(item: FolderBrowseGridItem): boolean {
    return item.media !== undefined && isVideoItem(item.media);
  }

  private itemIsGif(item: FolderBrowseGridItem): boolean {
    return item.media !== undefined && isGifItem(item.media);
  }

  private itemIsLive(item: FolderBrowseGridItem): boolean {
    return item.media !== undefined && isLivePhotoItem(item.media);
  }

  private mediaThumbUri(item: FolderBrowseGridItem): string {
    const media = item.media;
    if (media === undefined) {
      return '';
    }
    return nasUrl(this.baseUrl, pickThumb(media));
  }

  private mediaSharedId(item: FolderBrowseGridItem): string {
    const media = item.media;
    if (media === undefined) {
      return '';
    }
    const id = media.id;
    if (id === undefined || String(id).trim().length === 0) {
      return '';
    }
    return gallerySharedSourceDomId(String(id).trim());
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
        void this.startFolderSlideshow(config);
      }
    })
  }

  @Builder
  private folderTile(item: FolderBrowseGridItem, flatIdx: number) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (this.liveFolderCoverUri(item.key).length > 0) {
          GalleryNetworkThumb({
            uri: nasUrl(this.baseUrl, this.liveFolderCoverUri(item.key)),
            isVideo: false,
            isGif: false,
            sharedTransitionId: '',
            paused: this.thumbLoadingPaused,
            fadeInEnabled: false,
            debugLabel: '',
            cacheIdentity: `${item.key}_${this.liveFolderCoverUri(item.key)}`,
            cacheRank: 2
          })
            .width('100%')
            .aspectRatio(1)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.folder_fill'))
              .fontSize(36)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width('100%')
          .aspectRatio(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.folder_shell_bg'))
        }
        if (this.liveFolderCoverUri(item.key).length > 0) {
          Column() {
            Blank()
              .layoutWeight(1)
            Row() {
              SymbolGlyph($r('sys.symbol.folder_fill'))
                .fontSize(16)
                .fontColor([Color.White])
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              Blank()
            }
            .width('100%')
            .padding({ left: 8, right: 8, bottom: 8 })
          }
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 180,
            colors: [['#00000000', 0.0], ['#00000000', 0.42], ['#99000000', 1.0]]
          })
          .hitTestBehavior(HitTestMode.None)
          .align(Alignment.TopStart)
        }
        GalleryAlbumSelectionOverlay({
          itemId: folderBrowseSelectionIdOf(item),
          visualScope: GALLERY_SELECTION_SCOPE_FOLDER,
          selectionMode: this.selectionMode
        })
      }
      .width('100%')
      .aspectRatio(1)
      .borderRadius(12)
      .clip(true)
      .id(folderBrowseDomId(flatIdx))
      .onAreaChange((): void => {
        folderBrowseRecordThumbRect(this.asSelectionHost(), flatIdx);
      })
      .onClick((): void => {
        folderBrowseOnCellClick(this.asSelectionHost(), item, flatIdx);
      })

      Text(item.title)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 2, right: 2, bottom: 8 })
  }

  @Builder
  private mediaTile(item: FolderBrowseGridItem, flatIdx: number) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        GalleryNetworkThumb({
          uri: this.mediaThumbUri(item),
          isVideo: this.itemIsVideo(item),
          isGif: this.itemIsGif(item),
          isLive: this.itemIsLive(item),
          paused: this.thumbLoadingPaused,
          fadeInEnabled: false,
          cacheIdentity: item.key,
          cacheRank: 1,
          sharedTransitionId: this.mediaSharedId(item)
        })
          .width('100%')
          .aspectRatio(1)
        GalleryAlbumSelectionOverlay({
          itemId: folderBrowseSelectionIdOf(item),
          visualScope: GALLERY_SELECTION_SCOPE_FOLDER,
          selectionMode: this.selectionMode
        })
      }
      .width('100%')
      .aspectRatio(1)
      .borderRadius(12)
      .clip(true)
      .id(folderBrowseDomId(flatIdx))
      .onAreaChange((): void => {
        folderBrowseRecordThumbRect(this.asSelectionHost(), flatIdx);
      })
      .onClick((): void => {
        folderBrowseOnCellClick(this.asSelectionHost(), item, flatIdx);
      })

      Text(item.title)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 2, right: 2, bottom: 8 })
  }

  private rowCellHasItem(block: FolderBrowseRowBlock, col: number): boolean {
    if (col < 0 || col >= block.cells.length) {
      return false;
    }
    const cell: FolderBrowseRowBlockCell = block.cells[col];
    return cell.item !== undefined && cell.flatIdx >= 0;
  }

  private rowCellItem(block: FolderBrowseRowBlock, col: number): FolderBrowseGridItem {
    return block.cells[col].item as FolderBrowseGridItem;
  }

  private rowCellFlatIdx(block: FolderBrowseRowBlock, col: number): number {
    return block.cells[col].flatIdx;
  }

  private rowCellStableKey(block: FolderBrowseRowBlock, col: number): string {
    if (!this.rowCellHasItem(block, col)) {
      return `fbcell_${block.rowIdx}_${col}_empty`;
    }
    const item = this.rowCellItem(block, col);
    return `fbcell_${block.rowIdx}_${col}_${item.key}_${item.coverUri}`;
  }

  @Builder
  private cellSlot(block: FolderBrowseRowBlock, col: number) {
    if (!this.rowCellHasItem(block, col)) {
      Blank().layoutWeight(1).aspectRatio(1)
    } else if (this.rowCellItem(block, col).kind === FOLDER_BROWSE_KIND_MEDIA) {
      this.mediaTile(this.rowCellItem(block, col), this.rowCellFlatIdx(block, col))
    } else {
      this.folderTile(this.rowCellItem(block, col), this.rowCellFlatIdx(block, col))
    }
  }

  @Builder
  private rowListItem(block: FolderBrowseRowBlock) {
    ListItem() {
      Row({ space: 2 }) {
        ForEach(block.cells, (_cell: FolderBrowseRowBlockCell, col: number) => {
          this.cellSlot(block, col)
        }, (_cell: FolderBrowseRowBlockCell, col: number) => this.rowCellStableKey(block, col))
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 1, bottom: 1 })
      .onTouch((event: TouchEvent): void => {
        galleryGridHandleRowTouch(
          this.slideTouch,
          this.asSlideTouchHost(),
          event,
          (xPx: number, yPx: number): boolean => this.beginFirstSlideAtRow(block.rowStart, xPx, yPx)
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
              folderBrowseEndSlideSelectGesture(this.asSelectionHost());
              const pt: FolderBrowseFingerWindowPoint | null = folderBrowseReadGestureFingerWindow(ev);
              if (pt === null) {
                return;
              }
              if (!this.beginFirstSlideAtRow(block.rowStart, this.vpToPx(pt.x), this.vpToPx(pt.y))) {
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
              folderBrowseOnSlidePanUpdate(this.asSelectionHost(), ev);
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
            const pt: FolderBrowseFingerWindowPoint | null = folderBrowseReadGestureFingerWindow(ev);
            if (pt === null) {
              galleryGridSlideLog('fb_sec_start_skip', 'reason=no_pointer');
              return;
            }
            const xPx = this.vpToPx(pt.x);
            const yPx = this.vpToPx(pt.y);
            const fi = folderBrowsePickThumbFlatForRow(this.asSelectionHost(), block.rowStart, xPx, yPx);
            if (fi < 0 || fi >= this.gridItems.length) {
              galleryGridSlideLog('fb_sec_start_skip',
                `reason=no_hit row=${block.rowStart} flat=${fi}` +
                  ` xy=${Math.round(xPx)},${Math.round(yPx)} total=${this.gridItems.length}`);
              return;
            }
            galleryGridSlideLog('fb_sec_start',
              `flat=${fi} xy=${Math.round(xPx)},${Math.round(yPx)} selected=${this.selectedIds.length}`);
            galleryGridOnSecondaryPanStart(this.slideTouch);
            folderBrowseBeginSlideSelectGesture(this.asSelectionHost(), ev, fi);
          })
          .onActionUpdate((ev: GestureEvent): void => {
            if (!galleryGridShouldUpdateSecondaryPan(this.slideTouch, this.asSlideTouchHost())) {
              return;
            }
            folderBrowseOnSlidePanUpdate(this.asSelectionHost(), ev);
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
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        GalleryGridChrome({
          selectionMode: this.selectionMode,
          selectedCount: this.selectedCount,
          title: this.title,
          fallbackTitle: '文件夹',
          totalCount: this.totalCount(),
          topSafeInsetVp: this.systemTopInsetVp,
          useMoreMenu: true,
          moreMenuExpanded: this.moreMenuExpanded,
          showGoUp: true,
          canGoUp: this.canGoUpFolder,
          scrollerList: [this.listScroller],
          onCancelSelection: (): void => {
            this.exitSelection();
          },
          onBack: (): void => {
            this.handleBack();
          },
          onGoUp: (): void => {
            this.goUpFolder();
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

        if (this.loading) {
          FnInlineLoading({ text: '加载中…' })
            .layoutWeight(1)
        } else if (this.error.length > 0 && this.gridItems.length === 0) {
          FnStateText({ text: this.error })
            .layoutWeight(1)
        } else {
          Stack({ alignContent: Alignment.Bottom }) {
            Column() {
              List({ scroller: this.listScroller }) {
                LazyForEach(this.rowSource, (block: FolderBrowseRowBlock) => {
                  this.rowListItem(block)
                }, (block: FolderBrowseRowBlock) => block.key)
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
              .id(FOLDER_BROWSE_LIST_DOM_ID)
              .cachedCount(this.columnsPerRow >= 4 ? 2 : 3)
              .edgeEffect(EdgeEffect.Spring)
              .scrollBar(BarState.Auto)
              .divider({ strokeWidth: 0 })
              .enableScrollInteraction(this.fbScrollEnabled)
              .onTouch((event: TouchEvent): void => {
                galleryGridHandleListTouch(this.slideTouch, this.asSlideTouchHost(), event);
              })
              .onReachEnd((): void => {
                void this.loadMoreMedia();
              })
              .onDidScroll((offset: number, scrollState: ScrollState): void => {
                gallerySlideAutoScrollOnListDidScroll(offset, scrollState);
                this.onGridScrollStateChange(scrollState);
              })
            }
            .width('100%')
            .height('100%')

            if (this.selectionMode && this.selectedCount > 0) {
              GalleryAlbumBatchActionBar({
                downloading: this.batchDownloading,
                deleting: this.batchDeleting,
                deleteEnabled: !this.hasFolderSelected,
                onDownload: (): void => {
                  void folderBrowseConfirmBatchDownload(this.asBatchActionsHost());
                },
                onDelete: (): void => {
                  void folderBrowseConfirmBatchDelete(this.asBatchActionsHost());
                }
              })
                .width('100%')
                .height(GALLERY_BATCH_BAR_TOTAL_HEIGHT_VP)
            }

            if (this.batchDeleting || this.batchDownloading) {
              FnFullLoadingMask({
                text: this.batchDeleting ? '移入回收站中…' : (this.hasFolderSelected ? '正在收集文件夹媒体…' : '下载中…'),
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

      if (this.slideshowPreparing) {
        FnFullLoadingMask({
          text: '正在准备幻灯片...',
          topOffsetVp: 0
        })
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
          gallerySlideshowScopeLabel(this.slideshowScope()),
          (): void => {
            this.dismissSlideshowSettings();
          }
        ))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .id(GALLERY_PREVIEW_SOURCE_FOLDER_ID)
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
export function FolderBrowsePageNavigationContent() {
  FolderBrowsePage()
}

