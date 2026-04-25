import {
  GALLERY_TOP_BAR_BUTTON_FONT_VP,
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_ROW_HEIGHT_VP,
  GALLERY_TOP_BAR_SUBTITLE_FONT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from '../../common/GalleryTopBarLayout';
import { FN_UI_FADE_TOGGLE_CURVE, FN_UI_FADE_TOGGLE_DURATION } from '../../common/FnMotion';

const CATEGORY_GALLERY_SHELL_RADIUS_VP: number = 26;
const CATEGORY_GALLERY_SHELL_MARGIN_H_VP: number = 10;
const CATEGORY_GALLERY_SHELL_MARGIN_TOP_VP: number = 8;
const CATEGORY_GALLERY_ACTION_MIN_WIDTH_VP: number = 72;

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
          Stack({ alignContent: Alignment.Center }) {
            Button($r('app.string.gallery_batch_cancel'), { type: ButtonType.Capsule, stateEffect: true })
              .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .constraintSize({ minWidth: CATEGORY_GALLERY_ACTION_MIN_WIDTH_VP })
              .backgroundColor($r('app.color.button_primary_bg'))
              .fontColor($r('app.color.button_primary_fg'))
              .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
              .shadow({ radius: 12, color: '#16001A33', offsetX: 0, offsetY: 4 })
              .visibility(this.selectionMode ? Visibility.Visible : Visibility.Hidden)
              .onClick(this.onCancelSelection)
            Button('\u8fd4\u56de', { type: ButtonType.Capsule, stateEffect: true })
              .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .constraintSize({ minWidth: CATEGORY_GALLERY_ACTION_MIN_WIDTH_VP })
              .backgroundColor($r('app.color.gallery_material_surface_bg'))
              .fontColor($r('app.color.button_secondary_fg'))
              .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
              .shadow({ radius: 12, color: '#12001A33', offsetX: 0, offsetY: 4 })
              .visibility(this.selectionMode ? Visibility.Hidden : Visibility.Visible)
              .onClick(this.onBack)
          }
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.Start)

        Row() {
          Text(this.titleText())
            .fontSize(this.selectionMode ? GALLERY_TOP_BAR_SUBTITLE_FONT_VP : GALLERY_TOP_BAR_TITLE_FONT_VP)
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor($r('app.color.text_primary'))
        }
        .layoutWeight(2)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Button(this.selectionMode ? '\u5b8c\u6210' : $r('app.string.gallery_multiselect'), {
              type: ButtonType.Capsule,
              stateEffect: true
            })
              .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .constraintSize({ minWidth: CATEGORY_GALLERY_ACTION_MIN_WIDTH_VP })
              .backgroundColor($r('app.color.gallery_material_surface_bg'))
              .fontColor($r('app.color.button_secondary_fg'))
              .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
              .shadow({ radius: 12, color: '#12001A33', offsetX: 0, offsetY: 4 })
              .onClick(this.onToggleMode)
          }
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: GALLERY_TOP_BAR_PAD_LEFT_VP,
        right: GALLERY_TOP_BAR_PAD_RIGHT_VP,
        top: GALLERY_TOP_BAR_PAD_TOP_VP,
        bottom: this.selectionMode ? GALLERY_TOP_BAR_PAD_BOTTOM_VP : 6
      })

      Text(this.countText())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 18, right: 18, bottom: 10 })
        .visibility(this.selectionMode ? Visibility.Hidden : Visibility.Visible)
    }
    .width('100%')
    .backgroundColor($r('app.color.gallery_material_shell_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .borderRadius(CATEGORY_GALLERY_SHELL_RADIUS_VP)
    .border({ width: 1, color: $r('app.color.gallery_material_shell_border') })
    .shadow({ radius: 18, color: '#14001A33', offsetX: 0, offsetY: 8 })
    .margin({
      left: CATEGORY_GALLERY_SHELL_MARGIN_H_VP,
      right: CATEGORY_GALLERY_SHELL_MARGIN_H_VP,
      top: CATEGORY_GALLERY_SHELL_MARGIN_TOP_VP + this.topSafeInsetVp,
      bottom: 4
    })
    .clip(true)
    .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })
  }
}
