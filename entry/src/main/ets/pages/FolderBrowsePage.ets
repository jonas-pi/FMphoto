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
import { FolderBrowseSession } from './folderBrowsePage/FolderBrowseSession';
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
  private session: FolderBrowseSession = new FolderBrowseSession();
  private slideTouchHostCache: GalleryGridSlideTouchHost | undefined = undefined;
  private selectionHostCache: FolderBrowseSelectionHost | undefined = undefined;
  private dataLoaderHostCache: FolderBrowseDataLoaderHost | undefined = undefined;
  private batchHostCache: FolderBrowseBatchActionsHost | undefined = undefined;
  private albumBackHandlerToken: number = 0;

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
    this.session.nav.pathStack = landing;
    // 具体路径入口先锁住；loadCurrent 会用相册已配置根目录解析真正安全边界。
    this.session.nav.lockToEntry = landing.length > 0;
    this.session.nav.entryFloorPath = '';
    this.session.nav.entryFloorResolved = !this.session.nav.lockToEntry;
    this.syncFolderHierarchyState();
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {
    }
  }

  private currentPath(): string {
    if (this.session.nav.pathStack.length === 0) {
      return '';
    }
    return this.session.nav.pathStack[this.session.nav.pathStack.length - 1];
  }

  private syncFolderHierarchyState(): void {
    if (this.session.nav.pathStack.length === 0) {
      this.canGoUpFolder = false;
      return;
    }
    this.canGoUpFolder = !this.session.nav.lockToEntry ||
      (this.session.nav.entryFloorResolved && this.session.nav.pathStack.length > 1);
  }

  private goUpFolder(): void {
    if (this.session.load.folderChanging || !this.canGoUpFolder || this.session.nav.pathStack.length === 0) {
      return;
    }
    const nextStack = this.session.nav.pathStack.slice(0, this.session.nav.pathStack.length - 1);
    if (this.session.nav.lockToEntry && nextStack.length === 0) {
      return;
    }
    this.session.load.folderChanging = true;
    this.session.nav.pathStack = nextStack;
    this.syncFolderHierarchyState();
    void this.loadCurrent(true).finally((): void => {
      this.session.load.folderChanging = false;
    });
  }

  private syncTitle(): void {
    const path = this.currentPath();
    this.title = path.length === 0 ? '文件夹' : folderBrowseLabelOf(path);
  }

  private publishGrid(): void {
    const next = folderBrowseBuildGrid(this.session.nav.folders, this.session.nav.mediaItems);
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
    this.session.overlay.rowSource.reloadAll(blocks);
  }

  private clearThumbResumeTimer(): void {
    if (this.session.overlay.thumbResumeTimer >= 0) {
      clearTimeout(this.session.overlay.thumbResumeTimer);
      this.session.overlay.thumbResumeTimer = -1;
    }
  }

  private onGridScrollStateChange(scrollState: ScrollState): void {
    if (!this.fbSlideGestureActive && !this.fbScrollEnabled) {
      this.fbScrollEnabled = true;
    }
    if (!this.fbSlideGestureActive) {
      this.session.selection.fbThumbHitBounds.clear();
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
    this.session.overlay.thumbResumeTimer = setTimeout((): void => {
      this.session.overlay.thumbResumeTimer = -1;
      this.thumbLoadingPaused = false;
    }, 96);
  }

  private async loadCurrent(reset: boolean): Promise<void> {
    await folderBrowseLoadCurrent(this.asDataLoaderHost(), reset);
  }

  private async loadCovers(gen: number, currentPath: string): Promise<void> {
    if (this.session.nav.folders.length === 0) {
      return;
    }
    let names: string[] = folderBrowseCoverDirNames(this.session.nav.folders, currentPath);
    let allCovers: FolderViewCoverItem[] = await folderBrowseFetchCoverBatch(currentPath, names);
    if (gen !== this.session.load.loadGen) {
      return;
    }
    if (allCovers.length === 0) {
      names = folderBrowseCoverDirNamesFallback(this.session.nav.folders, currentPath);
      allCovers = await folderBrowseFetchCoverBatch(currentPath, names);
      if (gen !== this.session.load.loadGen) {
        return;
      }
    }
    if (allCovers.length === 0) {
      return;
    }
    folderBrowseApplyCoverUris(this.session.nav.folders, allCovers, names);
    this.publishGrid();
  }

  private async loadMoreMedia(): Promise<void> {
    await folderBrowseLoadMoreMedia(this.asDataLoaderHost());
  }

  private enterFolder(path: string): void {
    const next = path.trim();
    if (this.session.load.folderChanging || next.length === 0 || folderBrowseIsOsRootPath(next)) {
      this.toast('无法打开该文件夹');
      return;
    }
    if (this.session.nav.lockToEntry) {
      if (this.currentPath().length === 0) {
        if (this.session.nav.allowedRootPaths.indexOf(next) < 0) {
          this.toast('无权访问该目录');
          return;
        }
        this.session.nav.entryFloorPath = next;
      } else if (!folderBrowsePathAllowed(next, this.session.nav.entryFloorPath)) {
        this.toast('无权访问该目录');
        return;
      }
    }
    if (next === this.currentPath()) {
      return;
    }
    this.session.load.folderChanging = true;
    this.session.nav.pathStack = this.session.nav.pathStack.concat([next]);
    this.syncFolderHierarchyState();
    void this.loadCurrent(true).finally((): void => {
      this.session.load.folderChanging = false;
    });
  }

  private openMedia(index: number): void {
    if (index < 0 || index >= this.session.nav.mediaItems.length) {
      this.toast('无法预览该项');
      return;
    }
    GalleryPreviewNavStore.openPreview(
      this.getUIContext(),
      this.baseUrl,
      this.session.nav.mediaItems,
      index,
      GALLERY_PREVIEW_SOURCE_FOLDER_ID
    );
  }

  private setSelectionModeState(value: boolean): void {
    if (this.selectionMode === value) {
      return;
    }
    this.selectionMode = value;
    galleryAlbumSyncSelectionVisualState(this.selectionMode, this.session.selection.selectedIds, GALLERY_SELECTION_SCOPE_FOLDER);
  }

  private setSelectedIds(ids: string[]): void {
    this.session.selection.selectedIds = ids;
    this.selectedCount = ids.length;
    this.hasFolderSelected = folderBrowseSelectionHasFolder(ids);
    galleryAlbumSyncSelectionVisualState(this.selectionMode, ids, GALLERY_SELECTION_SCOPE_FOLDER);
  }

  private enterSelection(): void {
    if (this.selectionMode) {
      return;
    }
    this.setSelectionModeState(true);
    this.setSelectedIds(this.session.selection.selectedIds);
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
    return this.session.nav.mediaItems.length > 0 || this.session.load.mediaHasMore;
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
    while (this.session.load.mediaHasMore && isActive() && guard < 40) {
      const before = this.session.load.mediaOffset;
      await this.loadMoreMedia();
      if (this.session.load.mediaOffset <= before) {
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
    const seq = ++this.session.overlay.slideshowRequestSeq;
    const isActive = (): boolean => seq === this.session.overlay.slideshowRequestSeq;
    try {
      await this.waitForAllMedia(isActive);
      if (!isActive()) {
        return;
      }
      await gallerySlideshowLaunchForItems(
        this.getUIContext(),
        this.baseUrl,
        this.session.nav.mediaItems,
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
    for (let i = 0; i < this.session.nav.mediaItems.length; i++) {
      const id: string = folderBrowseMediaId(this.session.nav.mediaItems[i]);
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
      next.push(this.session.nav.mediaItems[i]);
    }
    this.session.nav.mediaItems = next;
    this.session.load.mediaOffset = this.session.nav.mediaItems.length;
    this.publishGrid();
  }

  private removeFoldersByPaths(paths: string[]): void {
    if (paths.length === 0) {
      return;
    }
    const drop = new Set<string>();
    for (let i = 0; i < paths.length; i++) {
      if (paths[i].length > 0) {
        drop.add(paths[i]);
      }
    }
    const next: FolderBrowseFolderItem[] = [];
    for (let i = 0; i < this.session.nav.folders.length; i++) {
      const item = this.session.nav.folders[i];
      if (!drop.has(item.path)) {
        next.push(item);
      }
    }
    this.session.nav.folders = next;
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
    if (this.slideTouchHostCache !== undefined) {
      return this.slideTouchHostCache;
    }
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
    this.slideTouchHostCache = new FolderBrowseSlideTouchHostBridge();
    return this.slideTouchHostCache;
  }

  private asSelectionHost(): FolderBrowseSelectionHost {
    if (this.selectionHostCache !== undefined) {
      return this.selectionHostCache;
    }
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

      get selectedIds(): string[] { return self.session.selection.selectedIds; }
      set selectedIds(v: string[]) { self.setSelectedIds(v); }

      get listScroller(): Scroller { return self.session.overlay.listScroller; }
      set listScroller(v: Scroller) { self.session.overlay.listScroller = v; }

      get listDomId(): string { return FOLDER_BROWSE_LIST_DOM_ID; }
      set listDomId(_v: string) {}

      get fbSlideGestureActive(): boolean { return self.fbSlideGestureActive; }
      set fbSlideGestureActive(v: boolean) { self.fbSlideGestureActive = v; }

      get fbScrollEnabled(): boolean { return self.fbScrollEnabled; }
      set fbScrollEnabled(v: boolean) { self.fbScrollEnabled = v; }

      get fbLongPressIgnoreUntil(): number { return self.session.selection.fbLongPressIgnoreUntil; }
      set fbLongPressIgnoreUntil(v: number) { self.session.selection.fbLongPressIgnoreUntil = v; }

      get fbThumbHitBounds(): Map<string, FolderBrowseThumbHitRect> { return self.session.selection.fbThumbHitBounds; }
      set fbThumbHitBounds(v: Map<string, FolderBrowseThumbHitRect>) { self.session.selection.fbThumbHitBounds = v; }

      get fbSlideRefX(): number { return self.session.selection.fbSlideRefX; }
      set fbSlideRefX(v: number) { self.session.selection.fbSlideRefX = v; }

      get fbSlideRefY(): number { return self.session.selection.fbSlideRefY; }
      set fbSlideRefY(v: number) { self.session.selection.fbSlideRefY = v; }

      get fbSlideHasRef(): boolean { return self.session.selection.fbSlideHasRef; }
      set fbSlideHasRef(v: boolean) { self.session.selection.fbSlideHasRef = v; }

      get fbSlideAnchorFlat(): number { return self.session.selection.fbSlideAnchorFlat; }
      set fbSlideAnchorFlat(v: number) { self.session.selection.fbSlideAnchorFlat = v; }

      get fbSlideUnionBase(): string[] { return self.session.selection.fbSlideUnionBase; }
      set fbSlideUnionBase(v: string[]) { self.session.selection.fbSlideUnionBase = v; }

      get fbSlideLastEndFlat(): number { return self.session.selection.fbSlideLastEndFlat; }
      set fbSlideLastEndFlat(v: number) { self.session.selection.fbSlideLastEndFlat = v; }

      get fbSlideLastAppliedEndFlat(): number { return self.session.selection.fbSlideLastAppliedEndFlat; }
      set fbSlideLastAppliedEndFlat(v: number) { self.session.selection.fbSlideLastAppliedEndFlat = v; }

      toast(msg: string): void { self.toast(msg); }
      openMedia(index: number): void { self.openMedia(index); }
      enterFolder(path: string): void { self.enterFolder(path); }
    }
    this.selectionHostCache = new FolderBrowseSelectionHostBridge();
    return this.selectionHostCache;
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
    if (this.dataLoaderHostCache !== undefined) {
      return this.dataLoaderHostCache;
    }
    const self = this;
    class FolderBrowseDataLoaderHostBridge implements FolderBrowseDataLoaderHost {
      get loadGen(): number { return self.session.load.loadGen; }
      set loadGen(v: number) { self.session.load.loadGen = v; }

      get loading(): boolean { return self.loading; }
      set loading(v: boolean) { self.loading = v; }

      get loadingMore(): boolean { return self.loadingMore; }
      set loadingMore(v: boolean) { self.loadingMore = v; }

      get error(): string { return self.error; }
      set error(v: string) { self.error = v; }

      get selectionMode(): boolean { return self.selectionMode; }
      set selectionMode(v: boolean) { self.selectionMode = v; }

      get folders(): FolderBrowseFolderItem[] { return self.session.nav.folders; }
      set folders(v: FolderBrowseFolderItem[]) { self.session.nav.folders = v; }

      get mediaItems(): GalleryListItem[] { return self.session.nav.mediaItems; }
      set mediaItems(v: GalleryListItem[]) { self.session.nav.mediaItems = v; }

      get mediaOffset(): number { return self.session.load.mediaOffset; }
      set mediaOffset(v: number) { self.session.load.mediaOffset = v; }

      get mediaHasMore(): boolean { return self.session.load.mediaHasMore; }
      set mediaHasMore(v: boolean) { self.session.load.mediaHasMore = v; }

      get lockToEntry(): boolean { return self.session.nav.lockToEntry; }
      set lockToEntry(v: boolean) { self.session.nav.lockToEntry = v; }

      get entryFloorResolved(): boolean { return self.session.nav.entryFloorResolved; }
      set entryFloorResolved(v: boolean) { self.session.nav.entryFloorResolved = v; }

      get allowedRootPaths(): string[] { return self.session.nav.allowedRootPaths; }
      set allowedRootPaths(v: string[]) { self.session.nav.allowedRootPaths = v; }

      get entryFloorPath(): string { return self.session.nav.entryFloorPath; }
      set entryFloorPath(v: string) { self.session.nav.entryFloorPath = v; }

      get pathStack(): string[] { return self.session.nav.pathStack; }
      set pathStack(v: string[]) { self.session.nav.pathStack = v; }

      currentPath(): string { return self.currentPath(); }
      syncTitle(): void { self.syncTitle(); }
      exitSelection(): void { self.exitSelection(); }
      publishGrid(): void { self.publishGrid(); }
      navigateOut(): void { self.navigateOut(); }
      syncFolderHierarchyState(): void { self.syncFolderHierarchyState(); }
      loadCovers(gen: number, currentPath: string): void { void self.loadCovers(gen, currentPath); }
    }
    this.dataLoaderHostCache = new FolderBrowseDataLoaderHostBridge();
    return this.dataLoaderHostCache;
  }

  private asBatchActionsHost(): FolderBrowseBatchActionsHost {
    if (this.batchHostCache !== undefined) {
      return this.batchHostCache;
    }
    const self = this;
    class FolderBrowseBatchActionsHostBridge implements FolderBrowseBatchActionsHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(v: string) { self.baseUrl = v; }

      get mediaItems(): GalleryListItem[] { return self.session.nav.mediaItems; }
      set mediaItems(v: GalleryListItem[]) { self.session.nav.mediaItems = v; }

      get selectedIds(): string[] { return self.session.selection.selectedIds; }
      set selectedIds(v: string[]) { self.setSelectedIds(v); }

      get batchDeleting(): boolean { return self.batchDeleting; }
      set batchDeleting(v: boolean) { self.batchDeleting = v; }

      get batchDownloading(): boolean { return self.batchDownloading; }
      set batchDownloading(v: boolean) { self.batchDownloading = v; }

      toast(msg: string): void { self.toast(msg); }
      exitSelection(): void { self.exitSelection(); }
      currentPath(): string { return self.currentPath(); }
      removeMediaByIds(ids: string[]): void { self.removeMediaByIds(ids); }
      removeFoldersByPaths(paths: string[]): void { self.removeFoldersByPaths(paths); }
      askLivePhotoSave(): Promise<LivePhotoSaveChoice> { return self.askLivePhotoSave(); }
      askChoice(title: string, buttons: string[]): Promise<number> { return self.askChoice(title, buttons); }
    }
    this.batchHostCache = new FolderBrowseBatchActionsHostBridge();
    return this.batchHostCache;
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
          this.session.overlay.slideTouch,
          this.asSlideTouchHost(),
          event,
          (xPx: number, yPx: number): boolean => this.beginFirstSlideAtRow(block.rowStart, xPx, yPx)
        );
      })
      .parallelGesture(GestureGroup(GestureMode.Parallel,
        GestureGroup(GestureMode.Sequence,
          LongPressGesture({ repeat: false, duration: GALLERY_GRID_SEQUENCE_LONG_PRESS_MS })
            .onAction((ev: GestureEvent): void => {
              if (!galleryGridOnSequenceLongPress(this.session.overlay.slideTouch, this.asSlideTouchHost())) {
                return;
              }
              galleryGridClearInitialSlide(this.session.overlay.slideTouch);
              folderBrowseEndSlideSelectGesture(this.asSelectionHost());
              const pt: FolderBrowseFingerWindowPoint | null = folderBrowseReadGestureFingerWindow(ev);
              if (pt === null) {
                return;
              }
              if (!this.beginFirstSlideAtRow(block.rowStart, this.vpToPx(pt.x), this.vpToPx(pt.y))) {
                return;
              }
              galleryGridArmInitialSlide(this.session.overlay.slideTouch);
            }),
          PanGesture({
            fingers: 1,
            direction: PanDirection.All,
            distance: GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE
          })
            .onActionUpdate((ev: GestureEvent): void => {
              if (!galleryGridShouldUpdateSequencePan(this.session.overlay.slideTouch, this.asSlideTouchHost())) {
                return;
              }
              folderBrowseOnSlidePanUpdate(this.asSelectionHost(), ev);
            })
            .onActionEnd((): void => {
              galleryGridOnSequencePanFinish(this.session.overlay.slideTouch, this.asSlideTouchHost());
            })
            .onActionCancel((): void => {
              galleryGridOnSequencePanFinish(this.session.overlay.slideTouch, this.asSlideTouchHost());
            })
        ),
        PanGesture({
          fingers: 1,
          direction: PanDirection.Horizontal,
          distance: GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE
        })
          .onActionStart((ev: GestureEvent): void => {
            this.session.overlay.slideTouch.secondaryPanDriving = false;
            if (!galleryGridCanStartSecondaryPan(this.session.overlay.slideTouch, this.asSlideTouchHost(), ev)) {
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
              `flat=${fi} xy=${Math.round(xPx)},${Math.round(yPx)} selected=${this.session.selection.selectedIds.length}`);
            galleryGridOnSecondaryPanStart(this.session.overlay.slideTouch);
            folderBrowseBeginSlideSelectGesture(this.asSelectionHost(), ev, fi);
          })
          .onActionUpdate((ev: GestureEvent): void => {
            if (!galleryGridShouldUpdateSecondaryPan(this.session.overlay.slideTouch, this.asSlideTouchHost())) {
              return;
            }
            folderBrowseOnSlidePanUpdate(this.asSelectionHost(), ev);
          })
          .onActionEnd((): void => {
            galleryGridOnSecondaryPanFinish(this.session.overlay.slideTouch, this.asSlideTouchHost());
          })
          .onActionCancel((): void => {
            galleryGridOnSecondaryPanFinish(this.session.overlay.slideTouch, this.asSlideTouchHost());
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
          scrollerList: [this.session.overlay.listScroller],
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
              List({ scroller: this.session.overlay.listScroller }) {
                LazyForEach(this.session.overlay.rowSource, (block: FolderBrowseRowBlock) => {
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
                galleryGridHandleListTouch(this.session.overlay.slideTouch, this.asSlideTouchHost(), event);
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
                deleteEnabled: true,
                deletePermanent: this.hasFolderSelected,
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
                text: this.batchDeleting ?
                  (this.hasFolderSelected ? '删除中…' : '移入回收站中…') :
                  (this.hasFolderSelected ? '正在收集文件夹媒体…' : '下载中…'),
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

