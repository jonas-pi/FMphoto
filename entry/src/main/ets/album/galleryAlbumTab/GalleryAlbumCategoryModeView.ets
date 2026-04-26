import { MediaCategoryItem } from '../../model/FnApiTypes';
import { FnFullLoadingMask } from '../../common/FnUiCommon';
import { FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { GalleryNetworkThumb, nasUrl, trimThumbPixCacheForList } from '../GalleryAlbumCommon';

@Component
export struct GalleryAlbumCategoryModeView {
  @Prop baseUrl: string = '';
  @Prop contentInsetTopVp: number = 0;
  @Prop contentInsetBottomVp: number = 0;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop opening: boolean = false;
  @Prop items: MediaCategoryItem[] = [];
  @Prop modeSwitchOpacity: number = 1;
  @Prop modeSwitchOffsetY: number = 0;
  @State private categoryThumbLoadingPaused: boolean = false;
  private categoryThumbResumeTimer: number = -1;

  getCategoryTitle: (item: MediaCategoryItem) => string = (_: MediaCategoryItem) => '';
  getCategoryCount: (item: MediaCategoryItem) => number = (_: MediaCategoryItem) => 0;
  getCategoryCover: (item: MediaCategoryItem) => string = (_: MediaCategoryItem) => '';
  onOpenCategory: (item: MediaCategoryItem) => void = (_: MediaCategoryItem) => {};

  aboutToAppear(): void {
    this.categoryThumbLoadingPaused = false;
  }

  aboutToDisappear(): void {
    this.clearCategoryThumbResumeTimer();
    this.recycleThumbCache(true);
  }

  private recycleThumbCache(aggressive: boolean = false): void {
    trimThumbPixCacheForList(this.items.length, aggressive);
  }

  private clearCategoryThumbResumeTimer(): void {
    if (this.categoryThumbResumeTimer >= 0) {
      clearTimeout(this.categoryThumbResumeTimer);
      this.categoryThumbResumeTimer = -1;
    }
  }

  private onGridScrollStateChange(scrollState: ScrollState): void {
    if (scrollState !== ScrollState.Idle) {
      this.clearCategoryThumbResumeTimer();
      if (!this.categoryThumbLoadingPaused) {
        this.categoryThumbLoadingPaused = true;
      }
      this.recycleThumbCache(false);
      return;
    }
    this.clearCategoryThumbResumeTimer();
    this.categoryThumbResumeTimer = setTimeout((): void => {
      this.categoryThumbResumeTimer = -1;
      this.categoryThumbLoadingPaused = false;
    }, 96);
  }

  build() {
    Column() {
      if (this.loading) {
        Row() {
          LoadingProgress().width(28).height(28)
          Text('媒体分类加载中…').fontSize(14).fontColor($r('app.color.text_secondary')).margin({ left: 10 })
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
        Stack({ alignContent: Alignment.Center }) {
          Grid() {
            ForEach(this.items, (cat: MediaCategoryItem, idx: number) => {
              GridItem() {
                Column({ space: 8 }) {
                  GalleryNetworkThumb({
                    uri: nasUrl(this.baseUrl, this.getCategoryCover(cat)),
                    isVideo: false,
                    isGif: false,
                    paused: this.categoryThumbLoadingPaused,
                  })
                    .width('100%')
                    .aspectRatio(1)
                  Text(this.getCategoryTitle(cat))
                    .fontSize(13)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(`${this.getCategoryCount(cat)} 项`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }
                .width('100%')
                .padding({ left: 2, right: 2, bottom: 8 })
                .onClick((): void => {
                  this.onOpenCategory(cat);
                })
              }
            }, (cat: MediaCategoryItem, i: number) => `mc_${i}_${this.getCategoryTitle(cat)}`)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .cachedCount(4)
          .onDidScroll((_offset: number, scrollState: ScrollState): void => {
            this.onGridScrollStateChange(scrollState);
          })
          .width('100%')
          .height('100%')
          .padding({
            left: 12,
            right: 12,
            top: this.contentInsetTopVp + 8,
            bottom: this.contentInsetBottomVp + 12
          })
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)

          if (this.opening) {
            FnFullLoadingMask({ text: '加载中…' })
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
