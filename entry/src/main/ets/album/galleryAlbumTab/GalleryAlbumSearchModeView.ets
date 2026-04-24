import { GalleryListItem } from '../../model/FnApiTypes';
import { FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { GalleryNetworkThumb, isGifItem, isVideoItem, nasUrl, pickThumb } from '../GalleryAlbumCommon';
import { GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE, GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE } from '../GallerySlidePick';
import { GalleryFingerWindowPoint } from './GalleryAlbumTabTypes';
import { GalleryAlbumBatchActionBar } from './GalleryAlbumBatchActionBar';

@Component
export struct GalleryAlbumSearchModeView {
  @Prop baseUrl: string = '';
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop searchResults: GalleryListItem[] = [];
  @Prop gallerySelectionMode: boolean = false;
  @Prop gallerySelectedCount: number = 0;
  @Prop galleryBatchDownloading: boolean = false;
  @Prop galleryBatchDeleting: boolean = false;
  @Prop galleryMainListScrollEnabled: boolean = true;
  @Prop gallerySlideGestureActive: boolean = false;
  @Prop modeSwitchOpacity: number = 1;
  @Prop modeSwitchOffsetY: number = 0;

  itemIdOf: (item: GalleryListItem) => string = (_: GalleryListItem) => '';
  isGalleryIdSelected: (id: string) => boolean = (_: string) => false;
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

  private searchRowCount(): number {
    return Math.ceil(this.searchResults.length / 3);
  }

  private searchRowIndices(): number[] {
    const rows: number[] = [];
    for (let i = 0; i < this.searchRowCount(); i++) {
      rows.push(i);
    }
    return rows;
  }

  @Builder
  private buildSearchGridThumbCell(item: GalleryListItem, flatIndex: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      GalleryNetworkThumb({
        uri: nasUrl(this.baseUrl, pickThumb(item)),
        isVideo: isVideoItem(item),
        isGif: isGifItem(item),
      })
        .width('100%')
        .aspectRatio(1)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#55000000')
        .opacity(this.gallerySelectionMode && this.isGalleryIdSelected(this.itemIdOf(item)) ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
        .animation({ duration: 0, curve: Curve.Linear })
      Row() {
        Blank().layoutWeight(1)
        Column() {
          if (this.isGalleryIdSelected(this.itemIdOf(item))) {
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
    if (rowIdx * 3 + col >= this.searchResults.length) {
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
                      const xPx = vp2px(pt.x);
                      const yPx = vp2px(pt.y);
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
                      const xPx = vp2px(pt.x);
                      const yPx = vp2px(pt.y);
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
            }, (rowIdx: number) => `srrow_${rowIdx}`)
            ListItem() {
              Column() {
                Blank()
                  .width('100%')
                  .height(this.gallerySelectionMode && this.gallerySelectedCount > 0 ? 88 : 32)
              }
              .width('100%')
            }
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(6)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
          .divider({ strokeWidth: 0 })
          .enableScrollInteraction(this.galleryMainListScrollEnabled)
          .onDidScroll((_offset: number, _scrollState: ScrollState): void => {
            if (!this.gallerySlideGestureActive && !this.galleryMainListScrollEnabled) {
              this.ensureMainListScrollEnabled();
            }
            if (!this.gallerySlideGestureActive) {
              this.clearSearchThumbHitBounds();
            }
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
