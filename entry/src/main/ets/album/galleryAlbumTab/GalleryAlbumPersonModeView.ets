import { AiPersonItem } from '../../model/FnApiTypes';
import { FnFullLoadingMask } from '../../common/FnUiCommon';
import { FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { GalleryNetworkThumb, nasUrl } from '../GalleryAlbumCommon';
import { FN_WINDOW_WIDTH_BP_KEY, fnAdaptiveGridColumns, fnRepeatFrTemplate } from '../../common/FnWindowBreakpoint';
import { FnListDataSource } from '../../common/FnListDataSource';

@Component
export struct GalleryAlbumPersonModeView {
  @Prop baseUrl: string = '';
  @Prop contentInsetTopVp: number = 0;
  @Prop contentInsetBottomVp: number = 0;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop opening: boolean = false;
  @Prop @Watch('onItemsChanged') items: AiPersonItem[] = [];
  @Prop modeSwitchOpacity: number = 1;
  @Prop modeSwitchOffsetY: number = 0;
  @StorageProp(FN_WINDOW_WIDTH_BP_KEY) private windowWidthBp: number = WidthBreakpoint.WIDTH_SM;
  private readonly personSource: FnListDataSource<AiPersonItem> = new FnListDataSource<AiPersonItem>();

  getPersonName: (item: AiPersonItem) => string = (_: AiPersonItem) => '';
  getPersonFace: (item: AiPersonItem) => string = (_: AiPersonItem) => '';
  getPersonIdentity: (item: AiPersonItem) => string = (_: AiPersonItem) => '';
  getPersonStatText: (item: AiPersonItem) => string = (_: AiPersonItem) => '';
  onOpenPerson: (item: AiPersonItem) => void = (_: AiPersonItem) => {};

  aboutToAppear(): void {
    this.personSource.reloadAll(this.items);
  }

  onItemsChanged(): void {
    this.personSource.reloadAll(this.items);
  }

  build() {
    Column() {
      if (this.loading) {
        Row() {
          LoadingProgress().width(28).height(28)
          Text('人物加载中…').fontSize(14).fontColor($r('app.color.text_secondary')).margin({ left: 10 })
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
        Grid() {
          LazyForEach(this.personSource, (item: AiPersonItem) => {
            GridItem() {
              Column({ space: 8 }) {
                GalleryNetworkThumb({
                  uri: nasUrl(this.baseUrl, this.getPersonFace(item)),
                  paused: false,
                  fadeInEnabled: false,
                  cacheIdentity: this.getPersonIdentity(item),
                  cacheRank: 3
                })
                  .width('100%')
                  .aspectRatio(1)
                  .borderRadius(999)
                  .clip(true)
                Text(this.getPersonName(item))
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Text(this.getPersonStatText(item))
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
              .width('100%')
              .padding({ left: 2, right: 2, bottom: 8 })
              .onClick((): void => {
                this.onOpenPerson(item);
              })
            }
          }, (item: AiPersonItem) => {
            const identity = this.getPersonIdentity(item);
            return identity.length > 0 ? `person_${identity}` : this.getPersonName(item);
          })
        }
        .columnsTemplate(fnRepeatFrTemplate(fnAdaptiveGridColumns(3, this.windowWidthBp)))
        .columnsGap(8)
        .rowsGap(8)
        .cachedCount(4)
        .width('100%')
        .layoutWeight(1)
        .padding({
          left: 12,
          right: 12,
          top: 8,
          bottom: this.contentInsetBottomVp + 12
        })
        .margin({ top: this.contentInsetTopVp })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        if (this.opening) {
          FnFullLoadingMask({ text: '加载人物媒体中…', topOffsetVp: this.contentInsetTopVp })
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .opacity(this.modeSwitchOpacity)
    .translate({ x: this.modeSwitchOffsetY, y: 0 })
    .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
  }
}
