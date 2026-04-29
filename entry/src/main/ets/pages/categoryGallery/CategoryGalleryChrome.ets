import {
  FN_FLOATING_TOP_BOTTOM_GAP_VP,
  FN_FLOATING_TOP_CONTROL_SIZE_VP,
  FN_FLOATING_TOP_MARGIN_VP,
  FN_FLOATING_TOP_TITLE_STACK_GAP_VP,
  FnFloatingTopPillButton
} from '../../common/FnUiCommon';
import {
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_SUBTITLE_FONT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from '../../common/GalleryTopBarLayout';
import { FN_UI_FADE_TOGGLE_CURVE, FN_UI_FADE_TOGGLE_DURATION } from '../../common/FnMotion';

@Component
export struct CategoryGalleryChrome {
  @Prop selectionMode: boolean = false;
  @Prop selectedCount: number = 0;
  @Prop title: string = '';
  @Prop totalCount: number = 0;
  @Prop topSafeInsetVp: number = 0;

  onCancelSelection: () => void = () => {};
  onBack: () => void = () => {};
  onToggleMode: () => void = () => {};

  private titleText(): string {
    if (this.selectionMode) {
      return `\u5df2\u9009\u62e9 ${this.selectedCount} \u9879`;
    }
    return this.title.length > 0 ? this.title : '\u5a92\u4f53\u5206\u7c7b';
  }

  private countText(): string {
    return `${this.totalCount} \u9879`;
  }

  build() {
    Column() {
      Row() {
        Row() {
          if (this.selectionMode) {
            FnFloatingTopPillButton({
              text: $r('app.string.gallery_batch_cancel'),
              action: this.onCancelSelection
            })
          } else {
            FnFloatingTopPillButton({
              text: '返回',
              action: this.onBack
            })
          }
        }
        .layoutWeight(1)
        .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
        .justifyContent(FlexAlign.Start)

        Column({ space: FN_FLOATING_TOP_TITLE_STACK_GAP_VP }) {
          Text(this.titleText())
            .fontSize(this.selectionMode ? GALLERY_TOP_BAR_SUBTITLE_FONT_VP : GALLERY_TOP_BAR_TITLE_FONT_VP)
            .fontWeight(this.selectionMode ? FontWeight.Medium : FontWeight.Bold)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor($r('app.color.text_primary'))

          if (!this.selectionMode) {
            Text(this.countText())
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(2)
        .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Row() {
          FnFloatingTopPillButton({
            text: this.selectionMode ? '完成' : $r('app.string.gallery_multiselect'),
            action: this.onToggleMode
          })
        }
        .layoutWeight(1)
        .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
      .alignItems(VerticalAlign.Center)
      .padding({ left: GALLERY_TOP_BAR_PAD_LEFT_VP, right: GALLERY_TOP_BAR_PAD_RIGHT_VP })
    }
    .width('100%')
    .margin({
      top: FN_FLOATING_TOP_MARGIN_VP + this.topSafeInsetVp,
      bottom: FN_FLOATING_TOP_BOTTOM_GAP_VP
    })
    .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })
  }
}
