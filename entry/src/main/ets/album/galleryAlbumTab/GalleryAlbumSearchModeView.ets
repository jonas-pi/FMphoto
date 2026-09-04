import { GalleryListItem } from '../../model/FnApiTypes';
import { FnListDataSource } from '../../common/FnListDataSource';
import { FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { GalleryNetworkThumb, isGifItem, isVideoItem, nasUrl, pickThumb, trimThumbPixCacheForList } from '../GalleryAlbumCommon';
import { isLivePhotoItem } from '../livephoto/LivePhotoDetect';
import { gallerySharedTransitionId } from '../GallerySharedTransition';
import { GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE, GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE } from '../GallerySlidePick';
import { gallerySlideAutoScrollOnListDidScroll } from '../GallerySlideAutoScroll';
import { GalleryFingerWindowPoint } from './GalleryAlbumTabTypes';
import { GalleryAlbumBatchActionBar } from '../GalleryAlbumBatchActionBar';
import { GalleryAlbumSelectionOverlay, GALLERY_SELECTION_SCOPE_ALBUM } from './GalleryAlbumSelectionOverlay';
import { FN_WINDOW_WIDTH_BP_KEY, fnAdaptiveGridColumns } from '../../common/FnWindowBreakpoint';

const GALLERY_SEARCH_INITIAL_RENDER_COUNT = 120;
const GALLERY_SEARCH_APPEND_RENDER_COUNT = 90;
const GALLERY_SEARCH_APPEND_PREFETCH_ROWS = 8;
const GALLERY_SEARCH_LIST_CACHED_COUNT = 3;
const GALLERY_SEARCH_THUMB_RESUME_DELAY_MS = 96;
export const GALLERY_ALBUM_SEARCH_LIST_DOM_ID: string = 'gallery_album_search_list';

interface GallerySearchRowBlockCell {
  flatIdx: number;
  item?: GalleryListItem;
}

interface GallerySearchRowBlock {
  key: string;
  rowIdx: number;
  rowStart: number;
  cells: GallerySearchRowBlockCell[];
}

@Component
export struct GalleryAlbumSearchModeView {
  @Prop baseUrl: string = '';
  @Prop contentInsetTopVp: number = 0;
  @Prop contentInsetBottomVp: number = 0;
  @Prop @Watch('onLoadingChanged') loading: boolean = false;
  @Prop error: string = '';
  @Prop @Watch('onSearchResultsChanged') searchResults: GalleryListItem[] = [];
  @Prop gallerySelectionMode: boolean = false;
  @Prop galleryBatchDownloading: boolean = false;
  @Prop galleryBatchDeleting: boolean = false;
  @Prop galleryMainListScrollEnabled: boolean = true;
  @Prop gallerySlideGestureActive: boolean = false;
  @Prop galleryLongPressIgnoreClickUntil: number = 0;
  @Prop modeSwitchOpacity: number = 1;
  @Prop modeSwitchOffsetY: number = 0;
  /** 官方顶栏 bindToScrollable 联动沉浸滚动光感所需的 Scroller。 */
  scroller: Scroller = new Scroller();

  itemIdOf: (item: GalleryListItem) => string = (_: GalleryListItem) => '';
  searchThumbDomId: (flatIndex: number) => string = (_: number) => '';
  recordSearchThumbRect: (flatIndex: number) => void = (_: number) => {};
  onSearchThumbTap: (item: GalleryListItem, flatIndex: number) => void = (_: GalleryListItem, __: number) => {};
  readGestureFingerWindow: (ev: GestureEvent) => GalleryFingerWindowPoint | null = (_: GestureEvent) => null;
  pickSearchThumbFlatForRow: (rowStart: number, xPx: number, yPx: number) => number = (_a: number, _b: number, _c: number) => -1;
  onGalleryThumbLongPress: (item: GalleryListItem) => void = (_: GalleryListItem) => {};
  beginGallerySlideSelectGesture: (ev: GestureEvent, item: GalleryListItem, anchorFlat: number) => void =
    (_: GestureEvent, __: GalleryListItem, ___: number) => {};
  endGallerySlideSelectGesture: () => void = () => {};
  onGallerySlidePanUpdate: (ev: GestureEvent) => void = (_: GestureEvent) => {};
  onGallerySlideTouchMoveWindow: (xPx: number, yPx: number) => void = (_: number, __: number) => {};
  ensureMainListScrollEnabled: () => void = () => {};
  clearSearchThumbHitBounds: () => void = () => {};
  onBatchDownload: () => void = () => {};
  onBatchDelete: () => void = () => {};
  @State private renderedSearchCount: number = 0;
  @State private searchThumbLoadingPaused: boolean = false;
  @StorageProp(FN_WINDOW_WIDTH_BP_KEY) @Watch('onWindowWidthBpChanged') private windowWidthBp: number =
    WidthBreakpoint.WIDTH_SM;
  private searchAppendTimer: number = -1;
  private searchThumbResumeTimer: number = -1;
  private searchLastVisibleIndex: number = -1;
  private searchRowBlocks: GallerySearchRowBlock[] = [];
  private searchRowSource: FnListDataSource<GallerySearchRowBlock> = new FnListDataSource<GallerySearchRowBlock>();
  private galleryInitialSlidePending: boolean = false;

  private currentRenderedCount(): number {
    return Math.min(this.renderedSearchCount, this.searchResults.length);
  }

  private hasMoreSearchResults(): boolean {
    return this.currentRenderedCount() < this.searchResults.length;
  }

  private armInitialGallerySlideGesture(ev: GestureEvent, item: GalleryListItem, anchorFlat: number): void {
    this.galleryInitialSlidePending = true;
    this.beginGallerySlideSelectGesture(ev, item, anchorFlat);
  }

  private clearInitialGallerySlideGesture(): void {
    this.galleryInitialSlidePending = false;
  }

  private releaseScrollLockIfIdle(): void {
    if (!this.gallerySlideGestureActive && !this.galleryMainListScrollEnabled) {
      this.ensureMainListScrollEnabled();
    }
  }

  private searchGridColumns(): number {
    return fnAdaptiveGridColumns(3, this.windowWidthBp);
  }

  private currentRenderedRowCount(): number {
    return Math.ceil(this.currentRenderedCount() / this.searchGridColumns());
  }

  private normalizeSearchKeyPart(value: string | number | undefined | null): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value).trim();
  }

  private searchItemStableKey(item: GalleryListItem | undefined, flatIndex: number): string {
    if (item === undefined) {
      return `empty_${flatIndex}`;
    }
    const photoUUID = this.normalizeSearchKeyPart(item.photoUUID);
    if (photoUUID.length > 0) {
      return `uuid:${photoUUID}`;
    }
    const itemId = this.itemIdOf(item);
    if (itemId.length > 0) {
      return `id:${itemId}`;
    }
    const guid = this.normalizeSearchKeyPart(item.guid);
    if (guid.length > 0) {
      return `guid:${guid}`;
    }
    const path = this.normalizeSearchKeyPart(item.path);
    if (path.length > 0) {
      return `path:${path}`;
    }
    const originalUrl = this.normalizeSearchKeyPart(item.originalUrl);
    if (originalUrl.length > 0) {
      return `origin:${originalUrl}`;
    }
    const name = this.normalizeSearchKeyPart(item.fileName ?? item.filename ?? item.name ?? item.title);
    const time = this.normalizeSearchKeyPart(item.createdAt ?? item.dateTime);
    const thumb = pickThumb(item).trim();
    if (name.length > 0 || time.length > 0 || thumb.length > 0) {
      const parts: string[] = [];
      if (name.length > 0) {
        parts.push(`name:${name}`);
      }
      if (time.length > 0) {
        parts.push(`time:${time}`);
      }
      if (thumb.length > 0) {
        parts.push(`thumb:${thumb}`);
      }
      return parts.join('|');
    }
    return `idx:${flatIndex}`;
  }

  private buildSearchRowBlocks(): GallerySearchRowBlock[] {
    const blocks: GallerySearchRowBlock[] = [];
    const visibleCount = this.currentRenderedCount();
    const cols = this.searchGridColumns();
    const rowCount = Math.ceil(visibleCount / cols);
    for (let rowIdx = 0; rowIdx < rowCount; rowIdx++) {
      const rowStart = rowIdx * cols;
      const cells: GallerySearchRowBlockCell[] = [];
      const keys: string[] = [];
      for (let col = 0; col < cols; col++) {
        const flatIdx = rowStart + col;
        if (flatIdx >= visibleCount) {
          cells.push({ flatIdx: -1 });
          keys.push(`empty_${rowIdx}_${col}`);
          continue;
        }
        const item = this.searchResults[flatIdx];
        cells.push({
          flatIdx,
          item
        });
        keys.push(this.searchItemStableKey(item, flatIdx));
      }
      blocks.push({
        key: `srrow_${rowIdx}_${keys.join('__')}`,
        rowIdx,
        rowStart,
        cells
      });
    }
    return blocks;
  }

  private rebuildSearchRowBlocks(): void {
    this.searchRowBlocks = this.buildSearchRowBlocks();
    this.searchRowSource.reloadAll(this.searchRowBlocks);
  }

  private searchCellAt(block: GallerySearchRowBlock, col: number): GallerySearchRowBlockCell | undefined {
    if (col < 0 || col >= block.cells.length) {
      return undefined;
    }
    return block.cells[col];
  }

  private searchCellHasItem(block: GallerySearchRowBlock, col: number): boolean {
    const cell = this.searchCellAt(block, col);
    return cell !== undefined && cell.item !== undefined && cell.flatIdx >= 0;
  }

  private searchCellItem(block: GallerySearchRowBlock, col: number): GalleryListItem {
    return this.searchCellAt(block, col)?.item as GalleryListItem;
  }

  private searchCellFlatIdx(block: GallerySearchRowBlock, col: number): number {
    return this.searchCellAt(block, col)?.flatIdx ?? -1;
  }

  private searchCellStableKey(block: GallerySearchRowBlock, col: number): string {
    const cell = this.searchCellAt(block, col);
    if (cell === undefined || cell.item === undefined || cell.flatIdx < 0) {
      return `scell_${block.rowIdx}_${col}_empty`;
    }
    return `scell_${block.rowIdx}_${col}_${this.searchItemStableKey(cell.item, cell.flatIdx)}`;
  }

  private clearSearchAppendTimer(): void {
    if (this.searchAppendTimer >= 0) {
      clearTimeout(this.searchAppendTimer);
      this.searchAppendTimer = -1;
    }
  }

  private clearSearchThumbResumeTimer(): void {
    if (this.searchThumbResumeTimer >= 0) {
      clearTimeout(this.searchThumbResumeTimer);
      this.searchThumbResumeTimer = -1;
    }
  }

  private recycleThumbCache(aggressive: boolean = false): void {
    trimThumbPixCacheForList(this.currentRenderedCount(), aggressive);
  }

  private resetRenderedSearchResults(): void {
    this.clearSearchAppendTimer();
    this.clearSearchThumbResumeTimer();
    this.searchLastVisibleIndex = -1;
    this.searchThumbLoadingPaused = false;
    if (this.loading) {
      this.renderedSearchCount = 0;
      this.rebuildSearchRowBlocks();
      return;
    }
    this.renderedSearchCount = Math.min(this.searchResults.length, GALLERY_SEARCH_INITIAL_RENDER_COUNT);
    this.rebuildSearchRowBlocks();
  }

  private onSearchResultsChanged(): void {
    this.ensureMainListScrollEnabled();
    this.resetRenderedSearchResults();
  }

  private onWindowWidthBpChanged(): void {
    this.rebuildSearchRowBlocks();
  }

  private onLoadingChanged(): void {
    this.ensureMainListScrollEnabled();
    if (this.loading) {
      this.resetRenderedSearchResults();
      return;
    }
    if (this.renderedSearchCount <= 0 && this.searchResults.length > 0) {
      this.resetRenderedSearchResults();
    }
  }

  aboutToAppear(): void {
    this.ensureMainListScrollEnabled();
    this.resetRenderedSearchResults();
  }

  aboutToDisappear(): void {
    this.clearSearchAppendTimer();
    this.clearSearchThumbResumeTimer();
    this.searchThumbLoadingPaused = false;
    this.searchRowBlocks = [];
    this.searchRowSource.reloadAll([]);
    this.recycleThumbCache(true);
  }

  private ensureRenderedSearchCount(targetCount: number): void {
    const nextCount = Math.min(this.searchResults.length, Math.max(0, targetCount));
    if (nextCount > this.renderedSearchCount) {
      this.renderedSearchCount = nextCount;
      this.rebuildSearchRowBlocks();
    }
  }

  private appendSearchChunk(): void {
    this.ensureRenderedSearchCount(this.renderedSearchCount + GALLERY_SEARCH_APPEND_RENDER_COUNT);
  }

  private maybeAppendSearchChunkSoon(delayMs: number): void {
    if (this.loading || !this.hasMoreSearchResults() || this.searchAppendTimer >= 0) {
      return;
    }
    this.searchAppendTimer = setTimeout((): void => {
      this.searchAppendTimer = -1;
      if (this.loading || this.searchThumbLoadingPaused || !this.hasMoreSearchResults()) {
        return;
      }
      this.appendSearchChunk();
    }, delayMs);
  }

  private onSearchScrollIndex(_firstIdx: number, lastIdx: number, _centerIdx: number): void {
    this.searchLastVisibleIndex = lastIdx;
    if (this.hasMoreSearchResults() &&
      lastIdx >= this.currentRenderedRowCount() - GALLERY_SEARCH_APPEND_PREFETCH_ROWS) {
      this.maybeAppendSearchChunkSoon(0);
    }
  }

  private onSearchScrollStateChange(scrollState: ScrollState): void {
    if (!this.gallerySlideGestureActive && !this.galleryMainListScrollEnabled) {
      this.ensureMainListScrollEnabled();
    }
    if (!this.gallerySlideGestureActive) {
      this.clearSearchThumbHitBounds();
    }
    if (scrollState !== ScrollState.Idle) {
      this.clearSearchThumbResumeTimer();
      this.searchThumbLoadingPaused = true;
      this.recycleThumbCache(false);
      return;
    }
    this.clearSearchThumbResumeTimer();
    this.searchThumbResumeTimer = setTimeout((): void => {
      this.searchThumbResumeTimer = -1;
      this.searchThumbLoadingPaused = false;
      if (this.hasMoreSearchResults() &&
        this.searchLastVisibleIndex >= this.currentRenderedRowCount() - GALLERY_SEARCH_APPEND_PREFETCH_ROWS) {
        this.maybeAppendSearchChunkSoon(0);
      }
    }, GALLERY_SEARCH_THUMB_RESUME_DELAY_MS);
  }

  private vpToPx(value: number): number {
    try {
      return this.getUIContext().vp2px(value);
    } catch (_e) {
      return value;
    }
  }

  private readTouchFingerWindow(ev: TouchEvent): GalleryFingerWindowPoint | null {
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

  @Builder
  private buildSearchGridThumbCell(item: GalleryListItem, flatIndex: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      GalleryNetworkThumb({
        uri: nasUrl(this.baseUrl, pickThumb(item)),
        isVideo: isVideoItem(item),
        isGif: isGifItem(item),
        isLive: isLivePhotoItem(item),
        paused: this.searchThumbLoadingPaused,
        sharedTransitionId: gallerySharedTransitionId(this.itemIdOf(item))
      })
        .width('100%')
        .aspectRatio(1)
      GalleryAlbumSelectionOverlay({
        itemId: this.itemIdOf(item),
        visualScope: GALLERY_SELECTION_SCOPE_ALBUM,
        selectionMode: this.gallerySelectionMode
      })
    }
    .id(this.searchThumbDomId(flatIndex))
    .onAreaChange((): void => {
      this.recordSearchThumbRect(flatIndex);
    })
    .layoutWeight(1)
    .aspectRatio(1)
    .backgroundColor(Color.Transparent)
    .draggable(false)
    .onClick((): void => {
      this.onSearchThumbTap(item, flatIndex);
    })
  }

  @Builder
  private searchCellSlot(block: GallerySearchRowBlock, col: number) {
    if (!this.searchCellHasItem(block, col)) {
      Blank().layoutWeight(1).aspectRatio(1)
    } else {
      this.buildSearchGridThumbCell(this.searchCellItem(block, col), this.searchCellFlatIdx(block, col));
    }
  }

  build() {
    Column() {
      if (this.loading) {
        Row() {
          LoadingProgress().width(28).height(28)
          Text('AI 搜索中…').fontSize(14).fontColor($r('app.color.text_secondary')).margin({ left: 10 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: this.contentInsetTopVp + 40 })
      } else if (this.error.length > 0) {
        Text(this.error)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: this.contentInsetTopVp + 40, left: 24, right: 24 })
      } else {
        Stack() {
          Column() {
            // 顶栏/搜索框为浮层，用占位把列表视口压到控件下方，避免首行缩略图钻到背后
            Blank()
              .width('100%')
              .height(this.contentInsetTopVp)
            List({ scroller: this.scroller }) {
            LazyForEach(this.searchRowSource, (block: GallerySearchRowBlock) => {
              ListItem() {
                Row({ space: 2 }) {
                  ForEach(block.cells, (_cell: GallerySearchRowBlockCell, col: number) => {
                    this.searchCellSlot(block, col)
                  }, (_cell: GallerySearchRowBlockCell, col: number) => this.searchCellStableKey(block, col))
                }
                .width('100%')
                .padding({ left: 2, right: 2, top: 1, bottom: 1 })
                .onTouch((event: TouchEvent): void => {
                  this.releaseScrollLockIfIdle();
                  if (!this.gallerySlideGestureActive) {
                    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.clearInitialGallerySlideGesture();
                    }
                    return;
                  }
                  if (event.type === TouchType.Move) {
                    return;
                  }
                })
                .parallelGesture(GestureGroup(GestureMode.Parallel,
                  GestureGroup(GestureMode.Sequence,
                    LongPressGesture({ repeat: false, duration: 420 })
                      .onAction((ev: GestureEvent): void => {
                        this.clearInitialGallerySlideGesture();
                        this.endGallerySlideSelectGesture();
                        const pt = this.readGestureFingerWindow(ev);
                        if (pt === null) {
                          return;
                        }
                        const xPx = this.vpToPx(pt.x);
                        const yPx = this.vpToPx(pt.y);
                        const fi = this.pickSearchThumbFlatForRow(block.rowStart, xPx, yPx);
                        if (fi < 0 || fi >= this.searchResults.length) {
                          return;
                        }
                        const longPressItem = this.searchResults[fi];
                        if (!this.gallerySelectionMode) {
                          this.onGalleryThumbLongPress(longPressItem);
                        }
                        this.armInitialGallerySlideGesture(ev, longPressItem, fi);
                      }),
                    PanGesture({
                      fingers: 1,
                      direction: PanDirection.All,
                      distance: GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE
                    })
                      .onActionUpdate((ev: GestureEvent): void => {
                        if (!this.galleryInitialSlidePending || !this.gallerySlideGestureActive) {
                          return;
                        }
                        this.onGallerySlidePanUpdate(ev);
                      })
                      .onActionEnd((): void => {
                        this.clearInitialGallerySlideGesture();
                        this.endGallerySlideSelectGesture();
                      })
                      .onActionCancel((): void => {
                        this.clearInitialGallerySlideGesture();
                        this.endGallerySlideSelectGesture();
                      })
                  ),
                  PanGesture({
                    fingers: 1,
                    direction: PanDirection.Horizontal,
                    distance: this.gallerySelectionMode ? GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE :
                      GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE
                  })
                    .onActionStart((ev: GestureEvent): void => {
                      if (!this.gallerySelectionMode) {
                        return;
                      }
                      if (this.gallerySlideGestureActive || this.galleryInitialSlidePending) {
                        return;
                      }
                      const pt = this.readGestureFingerWindow(ev);
                      if (pt === null) {
                        return;
                      }
                      const xPx = this.vpToPx(pt.x);
                      const yPx = this.vpToPx(pt.y);
                      const fi = this.pickSearchThumbFlatForRow(block.rowStart, xPx, yPx);
                      if (fi < 0 || fi >= this.searchResults.length) {
                        return;
                      }
                      this.beginGallerySlideSelectGesture(ev, this.searchResults[fi], fi);
                    })
                    .onActionUpdate((ev: GestureEvent): void => {
                      this.onGallerySlidePanUpdate(ev);
                    })
                    .onActionEnd((): void => {
                      this.clearInitialGallerySlideGesture();
                      this.endGallerySlideSelectGesture();
                    })
                    .onActionCancel((): void => {
                      this.clearInitialGallerySlideGesture();
                      this.endGallerySlideSelectGesture();
                    })
                ))
              }
              .draggable(false)
            }, (block: GallerySearchRowBlock) => block.key)
            ListItem() {
              Column() {
                Blank()
                  .width('100%')
                  .height((this.gallerySelectionMode ? 88 : 32) +
                    (this.hasMoreSearchResults() ? 0 : this.contentInsetBottomVp))
              }
              .width('100%')
            }
            if (this.hasMoreSearchResults()) {
              ListItem() {
                Row({ space: 8 }) {
                  LoadingProgress()
                    .width(18)
                    .height(18)
                  Text('继续加载中...')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({
                  top: 8,
                  bottom: (this.gallerySelectionMode ? 8 : 16) +
                    this.contentInsetBottomVp
                })
                .onAppear((): void => {
                  this.maybeAppendSearchChunkSoon(0);
                })
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .clip(true)
          .id(GALLERY_ALBUM_SEARCH_LIST_DOM_ID)
          .cachedCount(this.searchGridColumns() >= 4 ? 2 : GALLERY_SEARCH_LIST_CACHED_COUNT)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
          .divider({ strokeWidth: 0 })
          .enableScrollInteraction(this.galleryMainListScrollEnabled)
          .onTouch((event: TouchEvent): void => {
            this.releaseScrollLockIfIdle();
            if (!this.gallerySlideGestureActive) {
              if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.clearInitialGallerySlideGesture();
              }
              return;
            }
            if (event.type === TouchType.Move) {
              return;
            }
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.clearInitialGallerySlideGesture();
              this.endGallerySlideSelectGesture();
            }
          })
          .onScrollIndex((firstIdx: number, lastIdx: number, centerIdx: number): void => {
            this.onSearchScrollIndex(firstIdx, lastIdx, centerIdx);
          })
          .onDidScroll((offset: number, scrollState: ScrollState): void => {
            gallerySlideAutoScrollOnListDidScroll(offset, scrollState);
            this.onSearchScrollStateChange(scrollState);
          })
          }
          .width('100%')
          .height('100%')
          .clip(true)

          if (this.gallerySelectionMode) {
            GalleryAlbumBatchActionBar({
              downloading: this.galleryBatchDownloading,
              deleting: this.galleryBatchDeleting,
              onDownload: this.onBatchDownload,
              onDelete: this.onBatchDelete
            })
              .width('100%')
              .height('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .opacity(this.modeSwitchOpacity)
    .translate({ x: this.modeSwitchOffsetY, y: 0 })
    .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
  }
}
