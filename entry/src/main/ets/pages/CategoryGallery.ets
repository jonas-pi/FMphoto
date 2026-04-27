/**
 * 媒体分类浏览页：展示某一分类（照片/视频/动图等）内所有媒体，
 * 按日期降序分组，3 列网格；长按 + 滑动连选、批量下载/删除（与图库主时间线交互一致）。
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
  trimThumbPixCacheForList
} from '../album/GalleryAlbumCommon';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import { GalleryPreviewNavStore } from '../album/GalleryPreviewNavStore';
import { AppSession } from '../auth/AppSession';
import { FnListDataSource } from '../common/FnListDataSource';
import { FnFullLoadingMask, FnStateText } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import { GalleryAlbumBatchActionBar } from '../album/galleryAlbumTab/GalleryAlbumBatchActionBar';
import {
  categoryGalleryApplyDeleteSyncIfNeeded,
  categoryGalleryConfirmBatchDelete,
  categoryGalleryConfirmBatchDownload,
  categoryGalleryRebuildByFlatItems,
  CategoryGalleryBatchActionsHost
} from './categoryGallery/CategoryGalleryBatchActions';
import { CategoryGalleryChrome } from './categoryGallery/CategoryGalleryChrome';
import {
  categoryGalleryBeginSlideSelectGesture,
  categoryGalleryDomId,
  categoryGalleryEndSlideSelectGesture,
  categoryGalleryExitSelection,
  categoryGalleryFlatPos,
  categoryGalleryIsIdSelected,
  categoryGalleryItemIdOf,
  categoryGalleryOnCellClick,
  categoryGalleryOnSlidePanUpdate,
  categoryGalleryOnSlideTouchMoveWindow,
  categoryGalleryOnThumbLongPress,
  categoryGalleryPickFlatForRow,
  categoryGalleryReadGestureFingerWindow,
  categoryGalleryRecordThumbRect,
  categoryGalleryRowGlobalStartFlat,
  categoryGallerySlidePanDistance,
  categoryGalleryToggleToolbarMode,
  CategoryGallerySelectionHost
} from './categoryGallery/CategoryGallerySelectionController';
import {
  buildCategoryGalleryViewData,
  CgFingerWindowPoint,
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

const CATEGORY_GALLERY_CONTENT_INSET_TOP_NORMAL_VP: number = 68;
const CATEGORY_GALLERY_CONTENT_INSET_TOP_SELECTION_VP: number = 68;
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
  @State private groups: DayGroup[] = [];
  @State private title: string = '';
  @State private baseUrl: string = '';
  @State private totalCount: number = 0;
  @State private heroImageUri: string = '';
  @State private columnsPerRow: number = 3;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @State private isDarkTheme: boolean = false;
  @State private systemTopInsetVp: number = 0;
  private flatItems: GalleryListItem[] = [];
  private groupOffsets: number[] = [];
  private handledDeleteSyncVersion: number = 0;

  @State private selectionMode: boolean = false;
  @State private selectedIds: string[] = [];
  @State private cgSlideGestureActive: boolean = false;
  @State private cgScrollEnabled: boolean = true;
  @State private cgBatchDeleting: boolean = false;
  @State private cgBatchDownloading: boolean = false;
  @State private cgThumbLoadingPaused: boolean = false;
  @State private cgBackgroundLoading: boolean = false;

  private cgLongPressIgnoreUntil: number = 0;
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
  private cgInitialSlidePending: boolean = false;

  private recycleThumbCache(aggressive: boolean = false): void {
    const recentAddedAggressive = this.isRecentAddedStreamingMode() &&
      (aggressive || this.cgBackgroundLoading || this.flatItems.length > 360);
    trimThumbPixCacheForList(this.flatItems.length, aggressive || recentAddedAggressive);
  }

  onBackPress(): boolean {
    if (this.selectionMode) {
      this.exitCgSelection();
      return true;
    }
    this.getUIContext().getRouter().back();
    return true;
  }

  private vpToPx(value: number): number {
    try {
      return this.getUIContext().vp2px(value);
    } catch (_e) {
      return value;
    }
  }

  private pxToVp(value: number): number {
    try {
      return this.getUIContext().px2vp(value);
    } catch (_e) {
      return value;
    }
  }

  private contentInsetTopVp(): number {
    return this.systemTopInsetVp + (this.selectionMode
      ? CATEGORY_GALLERY_CONTENT_INSET_TOP_SELECTION_VP
      : CATEGORY_GALLERY_CONTENT_INSET_TOP_NORMAL_VP);
  }

  private isRecentAddedStreamingMode(): boolean {
    return CategoryGalleryNavStore.useCreatedAtGrouping && CategoryGalleryNavStore.categoryKey.length === 0;
  }

  private syncSystemAvoidArea(win: window.Window): void {
    try {
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.systemTopInsetVp = Math.max(0, this.pxToVp(area.topRect.height));
    } catch (_e) {
      this.systemTopInsetVp = 0;
    }
  }

  private applySystemBar(): void {
    try {
      const dark = this.isDarkTheme;
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

  onPageShow(): void {
    this.applyDeleteSyncIfNeeded();
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar();
  }

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar();
  }

  aboutToAppear(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.cgThumbLoadingPaused = false;
    this.applyNavStoreSnapshot();
    this.startStoreObserver();
    this.scheduleCategoryBackgroundLoad();
  }

  aboutToDisappear(): void {
    this.stopStoreObserver();
    this.clearCgThumbResumeTimer();
    this.clearCgDeferredBackgroundLoadTimer();
    this.clearCgDeferredSnapshotApplyTimer();
    this.recycleThumbCache(true);
    this.listBlocks = [];
    this.listBlockSource.reloadAll([]);
    const client = AppSession.getClient();
    if (client !== null) {
      client.cancelPendingRequests();
    }
    CategoryGalleryNavStore.clear();
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

  private exitCgSelection(): void {
    categoryGalleryExitSelection(this.asSelectionHost());
  }

  private toggleToolbarMode(): void {
    categoryGalleryToggleToolbarMode(this.asSelectionHost());
  }

  private isCgIdSelected(id: string): boolean {
    return categoryGalleryIsIdSelected(this.asSelectionHost(), id);
  }

  private recordCgThumbRect(flatIdx: number): void {
    categoryGalleryRecordThumbRect(this.asSelectionHost(), flatIdx);
  }

  private readGestureFingerWindow(ev: GestureEvent) {
    return categoryGalleryReadGestureFingerWindow(ev);
  }

  private readTouchFingerWindow(ev: TouchEvent): CgFingerWindowPoint | null {
    if (ev.touches === undefined || ev.touches.length < 1) {
      return null;
    }
    const f0 = ev.touches[0];
    const x = f0.windowX ?? f0.displayX ?? f0.x;
    const y = f0.windowY ?? f0.displayY ?? f0.y;
    if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
      return null;
    }
    return { x, y };
  }

  private pickCgFlatForRow(rowStart: number, xPx: number, yPx: number): number {
    return categoryGalleryPickFlatForRow(this.asSelectionHost(), rowStart, xPx, yPx);
  }

  private beginCgSlideSelectGesture(ev: GestureEvent, anchorFlat: number): void {
    categoryGalleryBeginSlideSelectGesture(this.asSelectionHost(), ev, anchorFlat);
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
    GalleryPreviewNavStore.openPreview(this.baseUrl, this.flatItems, flatIdx);
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
    if (!this.isRecentAddedStreamingMode()) {
      return;
    }
    this.clearCgDeferredSnapshotApplyTimer();
    this.cgDeferredSnapshotApplyTimer = setTimeout((): void => {
      this.cgDeferredSnapshotApplyTimer = -1;
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
      blocks.push({
        key: `h_${group.sortKey}`,
        isHeader: true,
        groupIdx: groupIdx,
        label: group.label
      });
      for (let rowIdx = 0; rowIdx < group.rows.length; rowIdx++) {
        const row = group.rows[rowIdx];
        const cellKeys: string[] = [];
        const cols = this.columnsPerRow === 4 ? 4 : 3;
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
    this.clearCgDeferredSnapshotApplyTimer();
    this.baseUrl = CategoryGalleryNavStore.baseUrl;
    this.title = CategoryGalleryNavStore.title;
    this.heroImageUri = CategoryGalleryNavStore.heroImageUri;
    this.columnsPerRow = CategoryGalleryNavStore.columnsPerRow === 4 ? 4 : 3;
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

  private async loadRemainingCategoryItems(token: number): Promise<void> {
    const categoryKey = CategoryGalleryNavStore.categoryKey;
    const expectedTotal = Math.max(CategoryGalleryNavStore.expectedTotalCount, this.flatItems.length);
    if (categoryKey.length === 0 || expectedTotal <= this.flatItems.length) {
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
    let offset = this.flatItems.length;
    let pendingAppendItems: GalleryListItem[] = [];
    const flushPendingAppendItems = (): void => {
      if (pendingAppendItems.length <= 0) {
        return;
      }
      CategoryGalleryNavStore.appendItems(token, pendingAppendItems);
      pendingAppendItems = [];
    };
    try {
      while (token === CategoryGalleryNavStore.currentToken() && offset < expectedTotal) {
        const res = await client.getCategoryPhotos(categoryKey, pageSize, offset);
        if (!res.success || res.data === undefined || res.data.length === 0) {
          break;
        }
        const incoming = res.data;
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
        if (appendItems.length > 0) {
          pendingAppendItems = pendingAppendItems.concat(appendItems);
          if (pendingAppendItems.length >= CATEGORY_GALLERY_BACKGROUND_APPEND_BATCH_ITEMS) {
            flushPendingAppendItems();
          }
        }
        offset += incoming.length > 0 ? incoming.length : pageSize;
        if (incoming.length < pageSize) {
          break;
        }
      }
      flushPendingAppendItems();
    } finally {
      CategoryGalleryNavStore.setBackgroundLoading(token, false);
    }
  }

  private ensureCategoryBackgroundLoad(): void {
    const token = CategoryGalleryNavStore.currentToken();
    if (CategoryGalleryNavStore.backgroundLoading) {
      return;
    }
    if (CategoryGalleryNavStore.categoryKey.length === 0) {
      return;
    }
    if (CategoryGalleryNavStore.expectedTotalCount <= this.flatItems.length) {
      return;
    }
    void this.loadRemainingCategoryItems(token);
  }

  private scheduleCategoryBackgroundLoad(): void {
    this.clearCgDeferredBackgroundLoadTimer();
    if (CategoryGalleryNavStore.categoryKey.length === 0) {
      return;
    }
    if (CategoryGalleryNavStore.expectedTotalCount <= this.flatItems.length) {
      return;
    }
    const delayMs = CategoryGalleryNavStore.categoryKey === 'photo' ? 240 : 96;
    this.cgDeferredBackgroundLoadTimer = setTimeout((): void => {
      this.cgDeferredBackgroundLoadTimer = -1;
      this.ensureCategoryBackgroundLoad();
    }, delayMs);
  }

  private stopStoreObserver(): void {
    if (this.cgStorePollTimer >= 0) {
      clearInterval(this.cgStorePollTimer);
      this.cgStorePollTimer = -1;
    }
  }

  private startStoreObserver(): void {
    this.stopStoreObserver();
    this.cgStorePollTimer = setInterval((): void => {
      this.syncFromNavStore();
    }, CATEGORY_GALLERY_STORE_SYNC_INTERVAL_MS);
  }

  private syncFromNavStore(): void {
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
      set columnsPerRow(v: number) { self.columnsPerRow = v === 4 ? 4 : 3; }

      get selectionMode(): boolean { return self.selectionMode; }
      set selectionMode(v: boolean) { self.selectionMode = v; }

      get selectedIds(): string[] { return self.selectedIds; }
      set selectedIds(v: string[]) { self.selectedIds = v; }

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

      get selectedIds(): string[] { return self.selectedIds; }
      set selectedIds(v: string[]) { self.selectedIds = v; }

      get cgBatchDeleting(): boolean { return self.cgBatchDeleting; }
      set cgBatchDeleting(v: boolean) { self.cgBatchDeleting = v; }

      get cgBatchDownloading(): boolean { return self.cgBatchDownloading; }
      set cgBatchDownloading(v: boolean) { self.cgBatchDownloading = v; }

      toast(msg: string): void { self.toast(msg); }
      exitSelection(): void { self.exitCgSelection(); }
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
        paused: this.cgThumbLoadingPaused,
      })
        .width('100%')
        .aspectRatio(1)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#55000000')
        .opacity(this.selectionMode && this.isCgIdSelected(this.itemIdOf(item)) ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
      Row() {
        Blank().layoutWeight(1)
        Column() {
          if (this.isCgIdSelected(this.itemIdOf(item))) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(24)
              .fontColor([$r('app.color.brand_primary')])
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          } else {
            Stack({ alignContent: Alignment.Center }) {
              Circle()
                .width(22)
                .height(22)
                .fill(Color.Transparent)
                .stroke(Color.White)
                .strokeWidth(2)
            }
            .width(24)
            .height(24)
          }
        }
        .padding({ top: 6, right: 6 })
      }
      .width('100%')
      .hitTestBehavior(HitTestMode.None)
      .visibility(this.selectionMode ? Visibility.Visible : Visibility.Hidden)
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
        if (!this.cgSlideGestureActive) {
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.clearInitialCgSlideGesture();
          }
          return;
        }
        if (event.type === TouchType.Move) {
          const pt = this.readTouchFingerWindow(event);
          if (pt === null) {
            return;
          }
          this.onCgSlideTouchMoveWindow(pt.x, pt.y);
        }
      })
      .parallelGesture(GestureGroup(GestureMode.Parallel,
        GestureGroup(GestureMode.Sequence,
          LongPressGesture({ repeat: false, duration: 420 })
            .onAction((ev: GestureEvent): void => {
              this.clearInitialCgSlideGesture();
              this.endCgSlideSelectGesture();
              const rowStart = this.rowGlobalStartFlat(groupIdx, row);
              const pt = this.readGestureFingerWindow(ev);
              if (pt === null) {
                return;
              }
              const xPx = this.vpToPx(pt.x);
              const yPx = this.vpToPx(pt.y);
              const fi = this.pickCgFlatForRow(rowStart, xPx, yPx);
              if (fi < 0 || fi >= this.flatItems.length) {
                return;
              }
              const longPressItem = this.flatItems[fi];
              const wasSelectionMode = this.selectionMode;
              this.onCgThumbLongPress(longPressItem, fi);
              if (!wasSelectionMode) {
                this.armInitialCgSlideGesture(ev, fi);
              }
            }),
          PanGesture({
            fingers: 1,
            direction: PanDirection.All,
            distance: categoryGallerySlidePanDistance(true)
          })
            .onActionUpdate((ev: GestureEvent): void => {
              if (!this.cgInitialSlidePending || !this.cgSlideGestureActive) {
                return;
              }
              this.onCgSlidePanUpdate(ev);
            })
            .onActionEnd((): void => {
              this.clearInitialCgSlideGesture();
              this.endCgSlideSelectGesture();
            })
            .onActionCancel((): void => {
              this.clearInitialCgSlideGesture();
              this.endCgSlideSelectGesture();
            })
        ),
        PanGesture({
          fingers: 1,
          direction: PanDirection.Horizontal,
          distance: categoryGallerySlidePanDistance(this.selectionMode)
        })
          .onActionStart((ev: GestureEvent): void => {
            if (!this.selectionMode) {
              return;
            }
            if (this.cgSlideGestureActive || this.cgInitialSlidePending) {
              return;
            }
            const rowStart = this.rowGlobalStartFlat(groupIdx, row);
            const pt = this.readGestureFingerWindow(ev);
            if (pt === null) {
              return;
            }
            const xPx = this.vpToPx(pt.x);
            const yPx = this.vpToPx(pt.y);
            const fi = this.pickCgFlatForRow(rowStart, xPx, yPx);
            if (fi < 0 || fi >= this.flatItems.length) {
              return;
            }
            this.beginCgSlideSelectGesture(ev, fi);
          })
          .onActionUpdate((ev: GestureEvent): void => {
            this.onCgSlidePanUpdate(ev);
          })
          .onActionEnd((): void => {
            this.clearInitialCgSlideGesture();
            this.endCgSlideSelectGesture();
          })
          .onActionCancel((): void => {
            this.clearInitialCgSlideGesture();
            this.endCgSlideSelectGesture();
          })
      ))
    }
    .draggable(false)
    .margin({ bottom: 2 })
  }

  private rowColumnIndexes(): number[] {
    return this.columnsPerRow === 4 ? [0, 1, 2, 3] : [0, 1, 2];
  }

  private rowCellAt(row: RowModel, col: number): GalleryListItem | undefined {
    return col >= 0 && col < row.cells.length ? row.cells[col] : undefined;
  }

  private armInitialCgSlideGesture(ev: GestureEvent, anchorFlat: number): void {
    this.cgInitialSlidePending = true;
    this.beginCgSlideSelectGesture(ev, anchorFlat);
  }

  private clearInitialCgSlideGesture(): void {
    this.cgInitialSlidePending = false;
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

      if (this.groups.length === 0) {
        FnStateText({ text: '暂无媒体' }).layoutWeight(1)
      } else {
        Stack() {
          Column() {
            List() {
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
                    .height(this.selectionMode && this.selectedIds.length > 0 ? 88 : 24)
                }
                .width('100%')
              }
            }
            .width('100%')
            .layoutWeight(1)
            .cachedCount(this.isRecentAddedStreamingMode() ? 1 : 3)
            .margin({ top: this.contentInsetTopVp() })
            .scrollBar(BarState.Auto)
            .backgroundColor(Color.Transparent)
            .edgeEffect(EdgeEffect.Spring)
            .divider({ strokeWidth: 0 })
            .enableScrollInteraction(this.cgScrollEnabled)
            .onTouch((event: TouchEvent): void => {
              if (!this.cgSlideGestureActive) {
                if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.clearInitialCgSlideGesture();
                }
                return;
              }
              if (event.type === TouchType.Move) {
                const pt = this.readTouchFingerWindow(event);
                if (pt === null) {
                  return;
                }
                this.onCgSlideTouchMoveWindow(pt.x, pt.y);
                return;
              }
              if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.clearInitialCgSlideGesture();
                this.endCgSlideSelectGesture();
              }
            })
            .onDidScroll((_offset: number, scrollState: ScrollState): void => {
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
              .padding({ top: 8, bottom: this.selectionMode && this.selectedIds.length > 0 ? 8 : 0 })
            }

            if (this.selectionMode && this.selectedIds.length > 0) {
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
            }
          }
          .width('100%')
          .height('100%')

          if (this.cgBatchDeleting || this.cgBatchDownloading) {
            FnFullLoadingMask({ text: this.cgBatchDeleting ? '移入回收站中…' : '下载中…' })
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      Column() {
        CategoryGalleryChrome({
          selectionMode: this.selectionMode,
          selectedCount: this.selectedIds.length,
          title: this.title,
          totalCount: this.totalCount,
          topSafeInsetVp: this.systemTopInsetVp,
          onCancelSelection: (): void => {
            this.exitCgSelection();
          },
          onBack: (): void => {
            this.getUIContext().getRouter().back();
          },
          onToggleMode: (): void => {
            this.toggleToolbarMode();
          }
        })

        Blank()
          .layoutWeight(1)
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 12, y: 0 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: -8, y: 0 });
  }
}
