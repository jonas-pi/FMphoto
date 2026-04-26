import { GalleryListItem } from '../../model/FnApiTypes';
import { FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { GalleryNetworkThumb, isGifItem, isVideoItem, nasUrl, pickThumb, trimThumbPixCacheForList } from '../GalleryAlbumCommon';
import { GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE, GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE } from '../GallerySlidePick';
import { GalleryFingerWindowPoint } from './GalleryAlbumTabTypes';
import { GalleryAlbumBatchActionBar } from './GalleryAlbumBatchActionBar';

const GALLERY_SEARCH_INITIAL_RENDER_COUNT = 120;
const GALLERY_SEARCH_APPEND_RENDER_COUNT = 90;
const GALLERY_SEARCH_APPEND_PREFETCH_ROWS = 8;
const GALLERY_SEARCH_LIST_CACHED_COUNT = 3;
const GALLERY_SEARCH_THUMB_RESUME_DELAY_MS = 96;

@Component
export struct GalleryAlbumSearchModeView {
  @Prop baseUrl: string = '';
  @Prop contentInsetTopVp: number = 0;
  @Prop contentInsetBottomVp: number = 0;
  @Prop @Watch('onLoadingChanged') loading: boolean = false;
  @Prop error: string = '';
  @Prop @Watch('onSearchResultsChanged') searchResults: GalleryListItem[] = [];
  @Prop gallerySelectionMode: boolean = false;
  @Prop gallerySelectedCount: number = 0;
  @Prop gallerySelectedIds: string[] = [];
  @Prop galleryBatchDownloading: boolean = false;
  @Prop galleryBatchDeleting: boolean = false;
  @Prop galleryMainListScrollEnabled: boolean = true;
  @Prop gallerySlideGestureActive: boolean = false;
  @Prop modeSwitchOpacity: number = 1;
  @Prop modeSwitchOffsetY: number = 0;

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
  ensureMainListScrollEnabled: () => void = () => {};
  clearSearchThumbHitBounds: () => void = () => {};
  onBatchDownload: () => void = () => {};
  onBatchDelete: () => void = () => {};
  @State private renderedSearchCount: number = 0;
  @State private searchThumbLoadingPaused: boolean = false;
  private searchAppendTimer: number = -1;
  private searchThumbResumeTimer: number = -1;
  private searchLastVisibleIndex: number = -1;

  private currentRenderedCount(): number {
    return Math.min(this.renderedSearchCount, this.searchResults.length);
  }

  private hasMoreSearchResults(): boolean {
    return this.currentRenderedCount() < this.searchResults.length;
  }

  private searchVisibleCount(): number {
    return this.currentRenderedCount();
  }

  private searchRowCount(): number {
    return Math.ceil(this.searchVisibleCount() / 3);
  }

  private currentRenderedRowCount(): number {
    return Math.ceil(this.currentRenderedCount() / 3);
  }

  private searchRowIndices(): number[] {
    const rows: number[] = [];
    for (let i = 0; i < this.searchRowCount(); i++) {
      rows.push(i);
    }
    return rows;
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

  private searchRowStableKey(rowIdx: number): string {
    const start = rowIdx * 3;
    const keys: string[] = [];
    for (let i = 0; i < 3; i++) {
      keys.push(this.searchItemStableKey(this.searchResults[start + i], start + i));
    }
    return `srrow_${rowIdx}_${keys.join('__')}`;
  }

  private isItemSelected(item: GalleryListItem): boolean {
    const id = this.itemIdOf(item);
    return id.length > 0 && this.gallerySelectedIds.indexOf(id) >= 0;
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
      return;
    }
    this.renderedSearchCount = Math.min(this.searchResults.length, GALLERY_SEARCH_INITIAL_RENDER_COUNT);
  }

  private onSearchResultsChanged(): void {
    this.resetRenderedSearchResults();
  }

  private onLoadingChanged(): void {
    if (this.loading) {
      this.resetRenderedSearchResults();
      return;
    }
    if (this.renderedSearchCount <= 0 && this.searchResults.length > 0) {
      this.resetRenderedSearchResults();
    }
  }

  aboutToAppear(): void {
    this.resetRenderedSearchResults();
  }

  aboutToDisappear(): void {
    this.clearSearchAppendTimer();
    this.clearSearchThumbResumeTimer();
    this.searchThumbLoadingPaused = false;
    this.recycleThumbCache(true);
  }

  private ensureRenderedSearchCount(targetCount: number): void {
    const nextCount = Math.min(this.searchResults.length, Math.max(0, targetCount));
    if (nextCount > this.renderedSearchCount) {
      this.renderedSearchCount = nextCount;
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

  @Builder
  private buildSearchGridThumbCell(item: GalleryListItem, flatIndex: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      GalleryNetworkThumb({
        uri: nasUrl(this.baseUrl, pickThumb(item)),
        isVideo: isVideoItem(item),
        isGif: isGifItem(item),
        paused: this.searchThumbLoadingPaused,
      })
        .width('100%')
        .aspectRatio(1)
      Column()
        .width('100%')
        .aspectRatio(1)
        .backgroundColor('#55000000')
        .opacity(this.gallerySelectionMode && this.isItemSelected(item) ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
        .animation({ duration: 0, curve: Curve.Linear })
      Row() {
        Blank().layoutWeight(1)
        Column() {
          if (this.isItemSelected(item)) {
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
      .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
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
  private searchCellSlot(rowIdx: number, col: number) {
    if (rowIdx * 3 + col >= this.searchVisibleCount()) {
      Blank().layoutWeight(1).aspectRatio(1)
    } else {
      this.buildSearchGridThumbCell(this.searchResults[rowIdx * 3 + col], rowIdx * 3 + col);
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
        .padding({ top: 40 })
      } else if (this.error.length > 0) {
        Text(this.error)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 40, left: 24, right: 24 })
      } else {
        Column() {
          List() {
            if (this.contentInsetTopVp > 0) {
              ListItem() {
                Column()
                  .width('100%')
                  .height(this.contentInsetTopVp)
              }
            }
            ForEach(this.searchRowIndices(), (rowIdx: number) => {
              ListItem() {
                Row({ space: 2 }) {
                  this.searchCellSlot(rowIdx, 0)
                  this.searchCellSlot(rowIdx, 1)
                  this.searchCellSlot(rowIdx, 2)
                }
                .width('100%')
                .padding({ left: 2, right: 2, top: 1, bottom: 1 })
                .parallelGesture(GestureGroup(GestureMode.Parallel,
                  LongPressGesture({ repeat: false, duration: 420 })
                    .onAction((ev: GestureEvent): void => {
                      this.endGallerySlideSelectGesture();
                      const pt = this.readGestureFingerWindow(ev);
                      if (pt === null) {
                        return;
                      }
                      const xPx = this.vpToPx(pt.x);
                      const yPx = this.vpToPx(pt.y);
                      const rowStart = rowIdx * 3;
                      const fi = this.pickSearchThumbFlatForRow(rowStart, xPx, yPx);
                      if (fi < 0 || fi >= this.searchResults.length) {
                        return;
                      }
                      const longPressItem = this.searchResults[fi];
                      this.onGalleryThumbLongPress(longPressItem);
                      if (!this.gallerySelectionMode) {
                        return;
                      }
                      if (this.gallerySlideGestureActive) {
                        return;
                      }
                      this.beginGallerySlideSelectGesture(ev, longPressItem, fi);
                    }),
                  PanGesture({
                    fingers: 1,
                    direction: this.gallerySlideGestureActive ? PanDirection.All : PanDirection.Horizontal,
                    distance: this.gallerySlideGestureActive ? GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE :
                      GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE
                  })
                    .onActionStart((ev: GestureEvent): void => {
                      if (!this.gallerySelectionMode) {
                        return;
                      }
                      if (this.gallerySlideGestureActive) {
                        this.endGallerySlideSelectGesture();
                      }
                      const pt = this.readGestureFingerWindow(ev);
                      if (pt === null) {
                        return;
                      }
                      const xPx = this.vpToPx(pt.x);
                      const yPx = this.vpToPx(pt.y);
                      const rowStart = rowIdx * 3;
                      const fi = this.pickSearchThumbFlatForRow(rowStart, xPx, yPx);
                      if (fi < 0 || fi >= this.searchResults.length) {
                        return;
                      }
                      this.beginGallerySlideSelectGesture(ev, this.searchResults[fi], fi);
                    })
                    .onActionUpdate((ev: GestureEvent): void => {
                      this.onGallerySlidePanUpdate(ev);
                    })
                    .onActionEnd((): void => {
                      this.endGallerySlideSelectGesture();
                    })
                    .onActionCancel((): void => {
                      this.endGallerySlideSelectGesture();
                    })
                ))
                .onGestureJudgeBegin((gestureInfo: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
                  if (gestureInfo.type !== GestureControl.GestureType.PAN_GESTURE) {
                    return GestureJudgeResult.CONTINUE;
                  }
                  if (!this.gallerySelectionMode) {
                    return GestureJudgeResult.REJECT;
                  }
                  return GestureJudgeResult.CONTINUE;
                })
              }
              .draggable(false)
            }, (rowIdx: number) => this.searchRowStableKey(rowIdx))
            ListItem() {
              Column() {
                Blank()
                  .width('100%')
                  .height((this.gallerySelectionMode && this.gallerySelectedCount > 0 ? 88 : 32) +
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
                  bottom: (this.gallerySelectionMode && this.gallerySelectedCount > 0 ? 8 : 16) +
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
          .cachedCount(GALLERY_SEARCH_LIST_CACHED_COUNT)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
          .divider({ strokeWidth: 0 })
          .enableScrollInteraction(this.galleryMainListScrollEnabled)
          .onScrollIndex((firstIdx: number, lastIdx: number, centerIdx: number): void => {
            this.onSearchScrollIndex(firstIdx, lastIdx, centerIdx);
          })
          .onDidScroll((_offset: number, scrollState: ScrollState): void => {
            this.onSearchScrollStateChange(scrollState);
          })

          if (this.gallerySelectionMode && this.gallerySelectedCount > 0) {
            GalleryAlbumBatchActionBar({
              downloading: this.galleryBatchDownloading,
              deleting: this.galleryBatchDeleting,
              onDownload: this.onBatchDownload,
              onDelete: this.onBatchDelete
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .opacity(this.modeSwitchOpacity)
    .translate({ x: 0, y: this.modeSwitchOffsetY })
    .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
  }
}
