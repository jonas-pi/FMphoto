import { SmartCategoryItem } from '../../model/FnApiTypes';
import { FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { GalleryNetworkThumb, nasUrl } from '../GalleryAlbumCommon';

@Component
export struct GalleryAlbumSmartCategoryModeView {
  @Prop baseUrl: string = '';
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop sceneItems: SmartCategoryItem[] = [];
  @Prop infoItems: SmartCategoryItem[] = [];
  @Prop modeSwitchOpacity: number = 1;
  @Prop modeSwitchOffsetY: number = 0;

  getCategoryName: (item: SmartCategoryItem) => string = (_: SmartCategoryItem) => '';
  getCategoryCover: (item: SmartCategoryItem) => string = (_: SmartCategoryItem) => '';
  onRunSearch: (keyword: string) => void = (_: string) => {};

  @Builder
  private sectionGrid(items: SmartCategoryItem[], keyPrefix: string) {
    Grid() {
      ForEach(items, (item: SmartCategoryItem, idx: number) => {
        GridItem() {
          Column({ space: 8 }) {
            GalleryNetworkThumb({
              uri: nasUrl(this.baseUrl, this.getCategoryCover(item)),
              isVideo: false,
              isGif: false,
            })
              .width('100%')
              .aspectRatio(1)
            Text(this.getCategoryName(item))
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text('点击发起AI搜索')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .width('100%')
          .padding({ left: 2, right: 2, bottom: 8 })
          .onClick((): void => {
            this.onRunSearch(this.getCategoryName(item));
          })
        }
      }, (_item: SmartCategoryItem, i: number) => `${keyPrefix}_${i}`)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(8)
    .rowsGap(8)
    .cachedCount(4)
    .width('100%')
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
        .padding({ top: 40 })
      } else if (this.error.length > 0) {
        Text(this.error)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 40, left: 24, right: 24 })
      } else {
        List() {
          if (this.sceneItems.length > 0) {
            ListItem() {
              Text('场景事物')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            }
            ListItem() {
              Column() {
                this.sectionGrid(this.sceneItems, 'sc_scene')
              }
              .padding({ left: 12, right: 12 })
            }
          }
          if (this.infoItems.length > 0) {
            ListItem() {
              Text('资料记录')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .padding({ left: 14, right: 14, top: 16, bottom: 8 })
            }
            ListItem() {
              Column() {
                this.sectionGrid(this.infoItems, 'sc_info')
              }
              .padding({ left: 12, right: 12, bottom: 10 })
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .divider({ strokeWidth: 0 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .opacity(this.modeSwitchOpacity)
    .translate({ x: 0, y: this.modeSwitchOffsetY })
    .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
  }
}
