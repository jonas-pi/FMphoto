import {
  GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_LEFT_VP,
  GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_RIGHT_VP,
  GALLERY_HOME_NAV_CHIP_PAD_H_VP,
  GALLERY_HOME_NAV_CHIP_RADIUS_VP
} from '../../common/GalleryButtonStyles';
import { FN_UI_FADE_TOGGLE_CURVE, FN_UI_FADE_TOGGLE_DURATION } from '../../common/FnMotion';

const GALLERY_HOME_ENTRY_CHIP_HEIGHT_VP: number = 30;
const GALLERY_HOME_ENTRY_CHIP_FONT_VP: number = 12;
const GALLERY_HOME_ENTRY_CHIP_WIDTH_VP: number = 88;
const GALLERY_HOME_ENTRY_STRIP_GAP_VP: number = 8;
const GALLERY_HOME_ENTRY_STRIP_EDGE_GAP_VP: number = 2;
const GALLERY_HOME_ENTRY_STRIP_RADIUS_VP: number = 20;
const GALLERY_HOME_ENTRY_STRIP_PAD_Y_VP: number = 5;

@Component
export struct GalleryAlbumEntryChips {
  @Prop hidden: boolean = false;

  onOpenMediaCategory: () => void = () => {};
  onOpenSmartCategory: () => void = () => {};
  onOpenPerson: () => void = () => {};
  onOpenRecent: () => void = () => {};
  onOpenCollect: () => void = () => {};
  onOpenRecycleBin: () => void = () => {};

  @Builder
  private chip(label: string, action: () => void) {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Column() {
        Text(label)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .fontSize(GALLERY_HOME_ENTRY_CHIP_FONT_VP)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width(GALLERY_HOME_ENTRY_CHIP_WIDTH_VP)
    .height(GALLERY_HOME_ENTRY_CHIP_HEIGHT_VP)
    .padding({ left: GALLERY_HOME_NAV_CHIP_PAD_H_VP, right: GALLERY_HOME_NAV_CHIP_PAD_H_VP, top: 0, bottom: 0 })
    .borderRadius(GALLERY_HOME_NAV_CHIP_RADIUS_VP)
    .backgroundColor($r('app.color.gallery_material_surface_bg'))
    .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
    .onClick(action)
  }

  build() {
    if (this.hidden) {
      Blank().height(0)
    } else {
      Scroll() {
        Row({ space: GALLERY_HOME_ENTRY_STRIP_GAP_VP }) {
          this.chip('\u5a92\u4f53\u5206\u7c7b', this.onOpenMediaCategory)
          this.chip('\u667a\u80fd\u5206\u7c7b', this.onOpenSmartCategory)
          this.chip('\u4eba\u7269', this.onOpenPerson)
          this.chip('\u6700\u8fd1\u6dfb\u52a0', this.onOpenRecent)
          this.chip('\u6536\u85cf', this.onOpenCollect)
          this.chip('\u56de\u6536\u7ad9', this.onOpenRecycleBin)
        }
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: GALLERY_HOME_ENTRY_STRIP_EDGE_GAP_VP, right: GALLERY_HOME_ENTRY_STRIP_EDGE_GAP_VP })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(GALLERY_HOME_ENTRY_CHIP_HEIGHT_VP + GALLERY_HOME_ENTRY_STRIP_PAD_Y_VP * 2)
      .padding({
        left: GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_LEFT_VP,
        right: GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_RIGHT_VP,
        top: GALLERY_HOME_ENTRY_STRIP_PAD_Y_VP,
        bottom: GALLERY_HOME_ENTRY_STRIP_PAD_Y_VP
      })
      .backgroundColor($r('app.color.gallery_material_shell_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .borderRadius(GALLERY_HOME_ENTRY_STRIP_RADIUS_VP)
      .border({ width: 1, color: $r('app.color.gallery_material_shell_border') })
      .shadow({ radius: 16, color: '#12001A33', offsetX: 0, offsetY: 6 })
      .margin({ left: 10, right: 10, bottom: 8 })
      .clip(true)
      .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })
    }
  }
}
