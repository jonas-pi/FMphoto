import { GalleryListItem } from '../../model/FnApiTypes';
import { GalleryFlowNode, GalleryWaterFlowDataSource } from '../GalleryFlowDataSource';
import {
  GalleryNetworkThumb,
  GalleryStaticThumbPlaceholder,
  GalleryThumbSkeleton,
  isGifItem,
  isVideoItem,
  nasUrl,
  pickThumb
} from '../GalleryAlbumCommon';
import { GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE, GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE } from '../GallerySlidePick';
import { GALLERY_TIMELINE_REFRESH_OFFSET_VP } from './GalleryAlbumTabConstants';
import { GalleryFingerWindowPoint, YearMarker } from './GalleryAlbumTabTypes';
import { GalleryAlbumBatchActionBar } from './GalleryAlbumBatchActionBar';
import { GalleryAlbumTimelineSidebar } from './GalleryAlbumTimelineSidebar';

const GALLERY_MAIN_LIST_CACHED_COUNT: number = 3;
const GALLERY_MAIN_TOUCH_LONG_PRESS_MS: number = 380;
const GALLERY_MAIN_TOUCH_SLOP_VP: number = 10;

@Component
export struct GalleryAlbumMainModeView {
  @Prop baseUrl: string = '';
  @Prop bootLoading: boolean = false;
  @Prop loadError: string = '';
  @Prop footText: string = '';
  @Prop contentInsetTopVp: number = 0;
  @Prop contentInsetBottomVp: number = 0;
  @Prop galleryTimelineRefreshing: boolean = false;
  @Prop gallerySelectionMode: boolean = false;
  @Prop gallerySelectedCount: number = 0;
  @Prop gallerySelectedIds: string[] = [];
  @Prop showBatchActionBar: boolean = true;
  @Prop galleryBatchDownloading: boolean = false;
  @Prop galleryBatchDeleting: boolean = false;
  @Prop galleryMainListScrollEnabled: boolean = true;
  @Prop gallerySlideGestureActive: boolean = false;
  @Prop galleryLongPressIgnoreClickUntil: number = 0;
  @Prop timelineSidebarDragging: boolean = false;
  @Prop isDraggingOrFling: boolean = false;
  @Prop sectionsLength: number = 0;
  @Prop orderedDaysLength: number = 0;
  @Prop timelineExpandedChrome: boolean = false;
  @Prop timelineScrollRailOnly: boolean = false;
  @Prop timelineYearMarkers: YearMarker[] = [];
  @Prop timelineScrubPillLabel: string = '';
  @Prop timelineBarVisible: boolean = false;
  @Prop timelinePressing: boolean = false;
  @Prop timelineLongPressExpanded: boolean = false;
  @Prop timelineIndicatorY: number = 0;
  @Prop timelineSliderRatio: number = 0;

  scrollerRef: Scroller = new Scroller();
  flowDataSource: GalleryWaterFlowDataSource = new GalleryWaterFlowDataSource();
  private galleryInitialSlidePending: boolean = false;
  private galleryTouchDownActive: boolean = false;
  private galleryTouchPendingLongPress: boolean = false;
  private galleryTouchLongPressTimer: number = -1;
  private galleryTouchStartX: number = 0;
  private galleryTouchStartY: number = 0;
  private galleryTouchLastX: number = 0;
  private galleryTouchLastY: number = 0;

  itemIdOf: (item: GalleryListItem) => string = (_: GalleryListItem) => '';
  galleryThumbDomId: (photoId: string) => string = (_: string) => '';
  recordGalleryThumbRectFromDom: (photoId: string, domId: string) => void = (_: string, __: string) => {};
  onGalleryThumbTap: (item: GalleryListItem, flatIndex: number) => void = (_: GalleryListItem, __: number) => {};
  galleryFlowLazyKey: (node: GalleryFlowNode) => string = (_: GalleryFlowNode) => '';
  getFlatItems: () => GalleryListItem[] = () => [];
  endGallerySlideSelectGesture: () => void = () => {};
  readGestureFingerWindow: (ev: GestureEvent) => GalleryFingerWindowPoint | null = (_: GestureEvent) => null;
  pickGalleryThumbFlatUnderPoint: (xPx: number, yPx: number) => number = (_: number, __: number) => -1;
  pickGalleryThumbFlatForRowOrCache: (node: GalleryFlowNode, xPx: number, yPx: number) => number =
    (_: GalleryFlowNode, __: number, ___: number) => -1;
  onGalleryThumbLongPress: (item: GalleryListItem) => void = (_: GalleryListItem) => {};
  beginGallerySlideSelectGesture: (ev: GestureEvent, item: GalleryListItem, anchorFlat: number) => void =
    (_: GestureEvent, __: GalleryListItem, ___: number) => {};
  beginGallerySlideSelectGestureAtWindowPx: (item: GalleryListItem, anchorFlat: number, xPx: number, yPx: number) => void =
    (_: GalleryListItem, __: number, ___: number, ____: number) => {};
  onGallerySlidePanUpdate: (ev: GestureEvent) => void = (_: GestureEvent) => {};
  onGallerySlideTouchMoveWindow: (xPx: number, yPx: number) => void = (_: number, __: number) => {};
  onListScrollIndex: (firstIdx: number, lastIdx: number, centerIdx: number) => void =
    (_: number, __: number, ___: number) => {};
  onListDidScroll: (offset: number, scrollState: ScrollState) => void = (_: number, __: ScrollState) => {};
  onListVisibleContentChange: (start: VisibleListContentInfo, end: VisibleListContentInfo) => void =
    (_: VisibleListContentInfo, __: VisibleListContentInfo) => {};
  onRefreshOffsetChange: (offset: number) => void = (_: number) => {};
  onRefreshing: () => void = () => {};
  onBatchDownload: () => void = () => {};
  onBatchDelete: () => void = () => {};
  onTimelineSeekToCurrentRatio: () => void = () => {};
  onTimelineTrackHeightChange: (height: number) => void = (_: number) => {};
  onTimelineTouchStateChange: (event: TouchEvent) => void = (_: TouchEvent) => {};
  onTimelineLongPressExpand: () => void = () => {};
  onTimelinePanStart: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onTimelinePanUpdate: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onTimelinePanEnd: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onTimelinePanCancel: (event: GestureEvent) => void = (_: GestureEvent) => {};

  private showTimelineSidebar(): boolean {
    return this.sectionsLength > 0 || this.orderedDaysLength > 0;
  }

  private isItemSelected(item: GalleryListItem): boolean {
    const id = this.itemIdOf(item);
    return id.length > 0 && this.gallerySelectedIds.indexOf(id) >= 0;
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

  private armInitialGallerySlideGesture(ev: GestureEvent, item: GalleryListItem, anchorFlat: number): void {
    this.galleryInitialSlidePending = true;
    this.beginGallerySlideSelectGesture(ev, item, anchorFlat);
  }

  private clearInitialGallerySlideGesture(): void {
    this.galleryInitialSlidePending = false;
  }

  private clearGalleryTouchLongPressTimer(): void {
    if (this.galleryTouchLongPressTimer >= 0) {
      clearTimeout(this.galleryTouchLongPressTimer);
      this.galleryTouchLongPressTimer = -1;
    }
  }

  private resetGalleryTouchTracking(): void {
    this.clearGalleryTouchLongPressTimer();
    this.galleryTouchDownActive = false;
    this.galleryTouchPendingLongPress = false;
  }

  private startGalleryTouchLongPress(pt: GalleryFingerWindowPoint): void {
    if (this.gallerySelectionMode || this.gallerySlideGestureActive) {
      return;
    }
    this.clearGalleryTouchLongPressTimer();
    this.galleryTouchDownActive = true;
    this.galleryTouchPendingLongPress = true;
    this.galleryTouchStartX = pt.x;
    this.galleryTouchStartY = pt.y;
    this.galleryTouchLastX = pt.x;
    this.galleryTouchLastY = pt.y;
    this.galleryTouchLongPressTimer = setTimeout((): void => {
      this.galleryTouchLongPressTimer = -1;
      if (!this.galleryTouchDownActive || !this.galleryTouchPendingLongPress ||
        this.gallerySelectionMode || this.gallerySlideGestureActive) {
        return;
      }
      const all = this.getFlatItems();
      const fi = this.pickGalleryThumbFlatUnderPoint(this.galleryTouchLastX, this.galleryTouchLastY);
      if (fi < 0 || fi >= all.length) {
        this.galleryTouchPendingLongPress = false;
        return;
      }
      const item = all[fi];
      this.onGalleryThumbLongPress(item);
      this.beginGallerySlideSelectGestureAtWindowPx(item, fi, this.galleryTouchLastX, this.galleryTouchLastY);
      this.galleryTouchPendingLongPress = false;
    }, GALLERY_MAIN_TOUCH_LONG_PRESS_MS);
  }

  private onMainListTouchEvent(event: TouchEvent): void {
    const pt = this.readTouchFingerWindow(event);
    if (event.type === TouchType.Down) {
      if (pt !== null) {
        this.startGalleryTouchLongPress(pt);
      } else {
        this.resetGalleryTouchTracking();
      }
      return;
    }
    if (this.gallerySlideGestureActive) {
      if (event.type === TouchType.Move) {
        if (pt === null) {
          return;
        }
        this.onGallerySlideTouchMoveWindow(pt.x, pt.y);
        return;
      }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.clearInitialGallerySlideGesture();
        this.endGallerySlideSelectGesture();
        this.resetGalleryTouchTracking();
      }
      return;
    }
    if (this.galleryTouchPendingLongPress && pt !== null && event.type === TouchType.Move) {
      this.galleryTouchLastX = pt.x;
      this.galleryTouchLastY = pt.y;
      const dx = pt.x - this.galleryTouchStartX;
      const dy = pt.y - this.galleryTouchStartY;
      const slopPx = this.vpToPx(GALLERY_MAIN_TOUCH_SLOP_VP);
      if ((dx * dx + dy * dy) > (slopPx * slopPx)) {
        this.resetGalleryTouchTracking();
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.clearInitialGallerySlideGesture();
      this.resetGalleryTouchTracking();
    }
  }

  @Builder
  private buildGalleryTimelineThumbCell(item: GalleryListItem, flatIndex: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      GalleryNetworkThumb({
        uri: nasUrl(this.baseUrl, pickThumb(item)),
        isVideo: isVideoItem(item),
        isGif: isGifItem(item),
        paused: this.timelineSidebarDragging || this.isDraggingOrFling
      })
        .width('100%')
        .aspectRatio(1)
      if (this.timelineSidebarDragging) {
        GalleryStaticThumbPlaceholder({
          animatePulse: this.timelineSidebarDragging
        })
          .width('100%')
          .aspectRatio(1)
          .hitTestBehavior(HitTestMode.None)
      }
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
    .id(this.itemIdOf(item).length > 0 ? this.galleryThumbDomId(this.itemIdOf(item)) : `gt_na_${flatIndex}`)
    .onAreaChange((): void => {
      const pid = this.itemIdOf(item);
      if (pid.length > 0) {
        this.recordGalleryThumbRectFromDom(pid, this.galleryThumbDomId(pid));
      }
    })
    .layoutWeight(1)
    .aspectRatio(1)
    .backgroundColor(Color.Transparent)
    .draggable(false)
    .onClick((): void => {
      this.onGalleryThumbTap(item, flatIndex);
    })
  }

  @Builder
  private buildFlowNode(node: GalleryFlowNode) {
    if (node.kind === 'month') {
      ListItem() {
        Text(`${node.year}年${node.month}月`)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 20, bottom: 4 })
      }
    } else if (node.kind === 'day') {
      ListItem() {
        Text(`${node.month}月${node.day}日`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 2, bottom: 4 })
      }
    } else {
      ListItem() {
        Row({ space: 2 }) {
          ForEach(node.rowSlotItems, (slot: GalleryListItem | null, k: number) => {
            if (slot !== null && slot !== undefined) {
              this.buildGalleryTimelineThumbCell(slot, node.rowSlotFlatIndices[k])
            } else {
              if (this.timelineSidebarDragging) {
                GalleryStaticThumbPlaceholder({
                  animatePulse: this.timelineSidebarDragging
                })
                  .layoutWeight(1)
                  .aspectRatio(1)
              } else {
                GalleryThumbSkeleton()
                  .layoutWeight(1)
                  .aspectRatio(1)
              }
            }
          }, (slot: GalleryListItem | null, k: number) => {
            if (slot !== null && slot !== undefined) {
              const id = this.itemIdOf(slot);
              if (id.length > 0) {
                return `ti_${node.key}_${k}_${id}`;
              }
              const fi = node.rowSlotFlatIndices[k];
              if (fi >= 0) {
                return `ti_${node.key}_${k}_f${fi}`;
              }
            }
            return `sk_${node.key}_${k}`;
          })
          if (node.rowSlotItems.length === 1) {
            Blank().layoutWeight(1)
            Blank().layoutWeight(1)
          }
          if (node.rowSlotItems.length === 2) {
            Blank().layoutWeight(1)
          }
        }
        .width('100%')
        .padding({ left: 2, right: 2, top: 1, bottom: 1 })
        .onTouch((event: TouchEvent): void => {
          if (!this.gallerySlideGestureActive) {
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.clearInitialGallerySlideGesture();
            }
            return;
          }
          if (event.type === TouchType.Move) {
            const pt = this.readTouchFingerWindow(event);
            if (pt === null) {
              return;
            }
            this.onGallerySlideTouchMoveWindow(pt.x, pt.y);
          }
        })
        .parallelGesture(GestureGroup(GestureMode.Parallel,
          GestureGroup(GestureMode.Sequence,
            LongPressGesture({ repeat: false, duration: 420 })
              .onAction((ev: GestureEvent): void => {
                if (this.gallerySlideGestureActive) {
                  return;
                }
                this.clearInitialGallerySlideGesture();
                this.endGallerySlideSelectGesture();
                const pt = this.readGestureFingerWindow(ev);
                if (pt === null) {
                  return;
                }
                const xPx = this.vpToPx(pt.x);
                const yPx = this.vpToPx(pt.y);
                const fi = this.pickGalleryThumbFlatForRowOrCache(node, xPx, yPx);
                if (fi < 0) {
                  return;
                }
                const all = this.getFlatItems();
                if (fi >= all.length) {
                  return;
                }
                const longPressItem = all[fi];
                const wasSelectionMode = this.gallerySelectionMode;
                this.onGalleryThumbLongPress(longPressItem);
                if (!wasSelectionMode) {
                  this.armInitialGallerySlideGesture(ev, longPressItem, fi);
                }
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
              const fi = this.pickGalleryThumbFlatForRowOrCache(node, xPx, yPx);
              if (fi < 0) {
                return;
              }
              const all = this.getFlatItems();
              if (fi >= all.length) {
                return;
              }
              this.beginGallerySlideSelectGesture(ev, all[fi], fi);
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
    }
  }

  build() {
    if (this.bootLoading) {
      Column({ space: 8 }) {
        ForEach([0, 1, 2, 3], (row: number) => {
          Row({ space: 8 }) {
            ForEach([0, 1, 2], (_: number) => {
              GalleryThumbSkeleton().layoutWeight(1)
            }, (n: number) => `sk_${row}_${n}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: row === 0 ? 24 : 0 })
        }, (r: number) => `skr_${r}`)
      }
      .width('100%')
    } else {
      Column() {
        if (this.loadError.length > 0) {
          Text(this.loadError)
            .fontSize(14)
            .fontColor(Color.Red)
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })
        }

        Column() {
          Stack({ alignContent: Alignment.TopEnd }) {
            Refresh({ refreshing: this.galleryTimelineRefreshing, offset: GALLERY_TIMELINE_REFRESH_OFFSET_VP, friction: 78 }) {
              List({ scroller: this.scrollerRef }) {
                if (this.contentInsetTopVp > 0) {
                  ListItem() {
                    Column()
                      .width('100%')
                      .height(this.contentInsetTopVp)
                  }
                }
                LazyForEach(this.flowDataSource, (node: GalleryFlowNode) => {
                  this.buildFlowNode(node)
                }, (node: GalleryFlowNode) => this.galleryFlowLazyKey(node))

                ListItem() {
                  Column({ space: 4 }) {
                    if (this.footText.length > 0) {
                      Text(this.footText)
                        .fontSize(12)
                        .fontColor($r('app.color.text_secondary'))
                        .width('100%')
                        .textAlign(TextAlign.Center)
                        .padding(12)
                    }
                    Blank().height((this.showBatchActionBar && this.gallerySelectionMode && this.gallerySelectedCount > 0 ? 88 : 32) +
                      this.contentInsetBottomVp)
                  }
                  .width('100%')
                }
              }
              .width('100%')
              .height('100%')
              .cachedCount(GALLERY_MAIN_LIST_CACHED_COUNT)
              .edgeEffect(EdgeEffect.Spring)
              .scrollBar(BarState.Off)
              .scrollBarColor(Color.Transparent)
              .scrollBarWidth(0)
              .divider({ strokeWidth: 0 })
              .enableScrollInteraction(this.galleryMainListScrollEnabled)
              .onTouch((event: TouchEvent): void => {
                this.onMainListTouchEvent(event);
              })
              .onScrollIndex(this.onListScrollIndex)
              .onDidScroll(this.onListDidScroll)
              .onScrollVisibleContentChange((start: VisibleListContentInfo, end: VisibleListContentInfo): void => {
                this.onListVisibleContentChange(start, end);
              })
            }
            .width('100%')
            .height('100%')
            .onOffsetChange(this.onRefreshOffsetChange)
            .pullToRefresh(!this.gallerySelectionMode)
            .onRefreshing(this.onRefreshing)

            if (this.showTimelineSidebar()) {
              GalleryAlbumTimelineSidebar({
                trackInsetTopVp: this.contentInsetTopVp,
                trackInsetBottomVp: this.contentInsetBottomVp,
                expandedChrome: this.timelineExpandedChrome,
                scrollRailOnly: this.timelineScrollRailOnly,
                yearMarkers: this.timelineYearMarkers,
                pillLabel: this.timelineScrubPillLabel,
                timelineSidebarDragging: this.timelineSidebarDragging,
                timelineBarVisible: this.timelineBarVisible,
                timelinePressing: this.timelinePressing,
                timelineLongPressExpanded: this.timelineLongPressExpanded,
                timelineIndicatorY: this.timelineIndicatorY,
                timelineSliderRatio: this.timelineSliderRatio,
                onSeekToCurrentRatio: this.onTimelineSeekToCurrentRatio,
                onTrackHeightChange: this.onTimelineTrackHeightChange,
                onTouchStateChange: this.onTimelineTouchStateChange,
                onLongPressExpand: this.onTimelineLongPressExpand,
                onPanStart: this.onTimelinePanStart,
                onPanUpdate: this.onTimelinePanUpdate,
                onPanEnd: this.onTimelinePanEnd,
                onPanCancel: this.onTimelinePanCancel
              })
            }
          }
          .width('100%')
          .layoutWeight(1)
          .clip(false)

          if (this.showBatchActionBar && this.gallerySelectionMode && this.gallerySelectedCount > 0) {
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
      .width('100%')
      .layoutWeight(1)
    }
  }
}
