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

@Component
export struct RecycleBinChrome {
  @Prop selectionMode: boolean = false;
  @Prop selectedCount: number = 0;

  onCancelSelection: () => void = () => {};
  onBack: () => void = () => {};
  onToggleMode: () => void = () => {};

  build() {
    Row() {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Button($r('app.string.gallery_batch_cancel'), { type: ButtonType.Capsule, stateEffect: true })
            .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
            .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
            .backgroundColor($r('app.color.button_primary_bg'))
            .fontColor($r('app.color.button_primary_fg'))
            .visibility(this.selectionMode ? Visibility.Visible : Visibility.Hidden)
            .onClick(this.onCancelSelection)
          Button('返回', { type: ButtonType.Capsule, stateEffect: true })
            .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
            .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
            .backgroundColor($r('app.color.button_secondary_bg'))
            .fontColor($r('app.color.button_secondary_fg'))
            .visibility(this.selectionMode ? Visibility.Hidden : Visibility.Visible)
            .onClick(this.onBack)
        }
      }
      .layoutWeight(1)
      .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
      .justifyContent(FlexAlign.Start)

      Text(this.selectionMode ? `已选 ${this.selectedCount} 项` : '回收站')
        .layoutWeight(2)
        .fontSize(this.selectionMode ? GALLERY_TOP_BAR_SUBTITLE_FONT_VP : GALLERY_TOP_BAR_TITLE_FONT_VP)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor($r('app.color.text_primary'))

      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Button(this.selectionMode ? '完成' : $r('app.string.gallery_multiselect'), { type: ButtonType.Capsule, stateEffect: true })
            .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
            .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
            .backgroundColor($r('app.color.button_secondary_bg'))
            .fontColor($r('app.color.button_secondary_fg'))
            .onClick(this.onToggleMode)
        }
      }
      .layoutWeight(1)
      .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .padding({
      left: GALLERY_TOP_BAR_PAD_LEFT_VP,
      right: GALLERY_TOP_BAR_PAD_RIGHT_VP,
      top: GALLERY_TOP_BAR_PAD_TOP_VP,
      bottom: GALLERY_TOP_BAR_PAD_BOTTOM_VP
    })
    .alignItems(VerticalAlign.Center)
  }
}
