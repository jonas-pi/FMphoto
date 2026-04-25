import { AiPersonItem } from '../../model/FnApiTypes';
import { FnFullLoadingMask } from '../../common/FnUiCommon';
import { FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { GalleryNetworkThumb, nasUrl, trimThumbPixCacheForList } from '../GalleryAlbumCommon';

@Component
export struct GalleryAlbumPersonModeView {
  @Prop baseUrl: string = '';
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop opening: boolean = false;
  @Prop items: AiPersonItem[] = [];
  @Prop modeSwitchOpacity: number = 1;
  @Prop modeSwitchOffsetY: number = 0;
  @State private personThumbLoadingPaused: boolean = false;
  private personThumbResumeTimer: number = -1;

  getPersonName: (item: AiPersonItem) => string = (_: AiPersonItem) => '';
  getPersonFace: (item: AiPersonItem) => string = (_: AiPersonItem) => '';
  getPersonStatText: (item: AiPersonItem) => string = (_: AiPersonItem) => '';
  onOpenPerson: (item: AiPersonItem) => void = (_: AiPersonItem) => {};

  aboutToAppear(): void {
    this.personThumbLoadingPaused = false;
  }

  aboutToDisappear(): void {
    this.clearPersonThumbResumeTimer();
    this.recycleThumbCache(true);
  }

  private recycleThumbCache(aggressive: boolean = false): void {
    trimThumbPixCacheForList(this.items.length, aggressive);
  }

  private clearPersonThumbResumeTimer(): void {
    if (this.personThumbResumeTimer >= 0) {
      clearTimeout(this.personThumbResumeTimer);
      this.personThumbResumeTimer = -1;
    }
  }

  private onGridScrollStateChange(scrollState: ScrollState): void {
    if (scrollState !== ScrollState.Idle) {
      this.clearPersonThumbResumeTimer();
      if (!this.personThumbLoadingPaused) {
        this.personThumbLoadingPaused = true;
      }
      this.recycleThumbCache(false);
      return;
    }
    this.clearPersonThumbResumeTimer();
    this.personThumbResumeTimer = setTimeout((): void => {
      this.personThumbResumeTimer = -1;
      this.personThumbLoadingPaused = false;
    }, 96);
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
        .padding({ top: 40 })
      } else if (this.error.length > 0) {
        Text(this.error)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 40, left: 24, right: 24 })
      } else {
        Grid() {
          ForEach(this.items, (item: AiPersonItem, idx: number) => {
            GridItem() {
              Column({ space: 8 }) {
                GalleryNetworkThumb({
                  uri: nasUrl(this.baseUrl, this.getPersonFace(item)),
                  paused: this.personThumbLoadingPaused
                })
                  .width('100%')
                  .aspectRatio(1)
                  .borderRadius(12)
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
          }, (_item: AiPersonItem, i: number) => `person_${i}`)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .cachedCount(6)
        .onDidScroll((_offset: number, scrollState: ScrollState): void => {
          this.onGridScrollStateChange(scrollState);
        })
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 8, bottom: 10 })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        if (this.opening) {
          FnFullLoadingMask({ text: '加载人物媒体中…' })
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .opacity(this.modeSwitchOpacity)
    .translate({ x: 0, y: this.modeSwitchOffsetY })
    .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
  }
}
