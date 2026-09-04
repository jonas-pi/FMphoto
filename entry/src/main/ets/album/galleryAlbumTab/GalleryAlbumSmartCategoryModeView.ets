import { SmartCategoryItem } from '../../model/FnApiTypes';
import { FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { GalleryNetworkThumb, nasUrl, trimThumbPixCacheForList } from '../GalleryAlbumCommon';
import { FN_WINDOW_WIDTH_BP_KEY, fnAdaptiveGridColumns } from '../../common/FnWindowBreakpoint';
import { smartCategoryCustomIdOf, smartCategoryIsCustom, smartCategoryMonogram } from '../SmartCategoryLayoutPreferences';
import { playGalleryDragSortHaptic } from '../GallerySelectionHaptic';

@Component
export struct GalleryAlbumSmartCategoryModeView {
  @Prop baseUrl: string = '';
  @Prop contentInsetTopVp: number = 0;
  @Prop contentInsetBottomVp: number = 0;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop sceneItems: SmartCategoryItem[] = [];
  @Prop infoItems: SmartCategoryItem[] = [];
  @Prop customItems: SmartCategoryItem[] = [];
  @Prop countVersion: number = 0;
  @Prop modeSwitchOpacity: number = 1;
  @Prop modeSwitchOffsetY: number = 0;
  @State private smartThumbLoadingPaused: boolean = false;
  @State private reorderActive: boolean = false;
  @StorageProp(FN_WINDOW_WIDTH_BP_KEY) private windowWidthBp: number = WidthBreakpoint.WIDTH_SM;
  private smartThumbResumeTimer: number = -1;

  getCategoryName: (item: SmartCategoryItem) => string = (_: SmartCategoryItem) => '';
  getCategoryCover: (item: SmartCategoryItem) => string = (_: SmartCategoryItem) => '';
  getCategoryCount: (item: SmartCategoryItem) => number = (_: SmartCategoryItem) => 0;
  onRunSearch: (keyword: string) => void = (_: string) => {};
  onReorderScene: (from: number, to: number) => void = (_from: number, _to: number) => {};
  onReorderInfo: (from: number, to: number) => void = (_from: number, _to: number) => {};
  onReorderCustom: (from: number, to: number) => void = (_from: number, _to: number) => {};

  aboutToAppear(): void {
    this.smartThumbLoadingPaused = false;
  }

  aboutToDisappear(): void {
    this.clearSmartThumbResumeTimer();
  }

  private totalSmartItemCount(): number {
    return this.sceneItems.length + this.infoItems.length + this.customItems.length;
  }

  private recycleThumbCache(aggressive: boolean = false): void {
    trimThumbPixCacheForList(this.totalSmartItemCount(), aggressive);
  }

  private clearSmartThumbResumeTimer(): void {
    if (this.smartThumbResumeTimer >= 0) {
      clearTimeout(this.smartThumbResumeTimer);
      this.smartThumbResumeTimer = -1;
    }
  }

  private setReorderActive(active: boolean): void {
    if (this.reorderActive !== active) {
      this.reorderActive = active;
    }
  }

  private onListScrollStateChange(scrollState: ScrollState): void {
    if (scrollState !== ScrollState.Idle) {
      this.clearSmartThumbResumeTimer();
      if (!this.smartThumbLoadingPaused) {
        this.smartThumbLoadingPaused = true;
      }
      this.recycleThumbCache(false);
      return;
    }
    this.clearSmartThumbResumeTimer();
    this.smartThumbResumeTimer = setTimeout((): void => {
      this.smartThumbResumeTimer = -1;
      this.smartThumbLoadingPaused = false;
    }, 96);
  }

  private itemStableKey(item: SmartCategoryItem, prefix: string): string {
    const customId = smartCategoryCustomIdOf(item);
    if (customId.length > 0) {
      return `${prefix}_c_${customId}`;
    }
    return `${prefix}_n_${this.getCategoryName(item)}`;
  }

  @Builder
  private categoryThumb(item: SmartCategoryItem) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.getCategoryCover(item).length > 0) {
        GalleryNetworkThumb({
          uri: nasUrl(this.baseUrl, this.getCategoryCover(item)),
          isVideo: false,
          isGif: false,
          paused: this.smartThumbLoadingPaused,
        })
          .width('100%')
          .height('100%')
          .draggable(false)
      } else {
        Text(smartCategoryMonogram(item))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .aspectRatio(1)
    .borderRadius(12)
    .clip(true)
    .backgroundColor($r('app.color.gallery_material_surface_bg'))
  }

  @Builder
  private headerMyCategories() {
    Text('我的分类')
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .padding({ left: 2, right: 2, top: 8, bottom: 8 })
  }

  @Builder
  private headerSceneCategories() {
    Text('场景事物')
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .padding({ left: 2, right: 2, top: 8, bottom: 8 })
  }

  @Builder
  private headerInfoCategories() {
    Text('资料记录')
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .padding({ left: 2, right: 2, top: 16, bottom: 8 })
  }

  @Builder
  private browseCard(item: SmartCategoryItem) {
    Column({ space: 8 }) {
      this.categoryThumb(item)
      Text(this.getCategoryName(item))
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.getCategoryCount(item) > 0
        ? `${this.getCategoryCount(item)} 项`
        : (smartCategoryIsCustom(item) ? '自定义' : '0 项'))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding({ left: 2, right: 2, bottom: 8 })
    .onClick((): void => {
      if (this.reorderActive) {
        return;
      }
      this.onRunSearch(this.getCategoryName(item));
    })
  }

  build() {
    Column() {
      if (this.loading) {
        Row() {
          LoadingProgress().width(28).height(28)
          Text('智能分类加载中…').fontSize(14).fontColor($r('app.color.text_secondary')).margin({ left: 10 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: this.contentInsetTopVp + 40 })
      } else if (this.error.length > 0 && this.totalSmartItemCount() <= 0) {
        Text(this.error)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: this.contentInsetTopVp + 40, left: 24, right: 24 })
      } else {
        List({ space: 8 }) {
          if (this.customItems.length > 0) {
            ListItemGroup({ header: this.headerMyCategories }) {
            }
            ForEach(this.customItems, (item: SmartCategoryItem) => {
              ListItem() {
                this.browseCard(item)
              }
            }, (item: SmartCategoryItem) => this.itemStableKey(item, 'sc_custom'))
              .onMove((from: number, to: number): void => {
                this.onReorderCustom(from, to);
              }, {
                onLongPress: (_index: number): void => {
                  playGalleryDragSortHaptic();
                  this.setReorderActive(true);
                },
                onDragStart: (_index: number): void => {
                  this.setReorderActive(true);
                },
                onDrop: (_index: number): void => {
                  this.setReorderActive(false);
                }
              })
          }
          if (this.sceneItems.length > 0) {
            ListItemGroup({ header: this.headerSceneCategories }) {
            }
            ForEach(this.sceneItems, (item: SmartCategoryItem) => {
              ListItem() {
                this.browseCard(item)
              }
            }, (item: SmartCategoryItem) => this.itemStableKey(item, 'sc_scene'))
              .onMove((from: number, to: number): void => {
                this.onReorderScene(from, to);
              }, {
                onLongPress: (_index: number): void => {
                  playGalleryDragSortHaptic();
                  this.setReorderActive(true);
                },
                onDragStart: (_index: number): void => {
                  this.setReorderActive(true);
                },
                onDrop: (_index: number): void => {
                  this.setReorderActive(false);
                }
              })
          }
          if (this.infoItems.length > 0) {
            ListItemGroup({ header: this.headerInfoCategories }) {
            }
            ForEach(this.infoItems, (item: SmartCategoryItem) => {
              ListItem() {
                this.browseCard(item)
              }
            }, (item: SmartCategoryItem) => this.itemStableKey(item, 'sc_info'))
              .onMove((from: number, to: number): void => {
                this.onReorderInfo(from, to);
              }, {
                onLongPress: (_index: number): void => {
                  playGalleryDragSortHaptic();
                  this.setReorderActive(true);
                },
                onDragStart: (_index: number): void => {
                  this.setReorderActive(true);
                },
                onDrop: (_index: number): void => {
                  this.setReorderActive(false);
                }
              })
          }
        }
        .lanes(fnAdaptiveGridColumns(3, this.windowWidthBp), 8)
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, bottom: this.contentInsetBottomVp + 12 })
        .margin({ top: this.contentInsetTopVp })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .divider({ strokeWidth: 0 })
        .onDidScroll((_offset: number, scrollState: ScrollState): void => {
          this.onListScrollStateChange(scrollState);
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .opacity(this.modeSwitchOpacity)
    .translate({ x: this.modeSwitchOffsetY, y: 0 })
    .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
  }
}
