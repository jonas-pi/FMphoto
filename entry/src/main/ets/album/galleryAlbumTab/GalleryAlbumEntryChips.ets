import {
  GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_BOTTOM_VP,
  GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_LEFT_VP,
  GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_RIGHT_VP,
  GALLERY_HOME_NAV_CHIP_FONT_VP,
  GALLERY_HOME_NAV_CHIP_HEIGHT_VP,
  GALLERY_HOME_NAV_CHIP_PAD_H_VP,
  GALLERY_HOME_NAV_CHIP_RADIUS_VP
} from '../../common/GalleryButtonStyles';

const GALLERY_HOME_ENTRY_STRIP_GAP_VP: number = 8;
const GALLERY_HOME_ENTRY_STRIP_EDGE_GAP_VP: number = 2;
const GALLERY_HOME_ENTRY_STRIP_MIN_CHIP_WIDTH_VP: number = 72;

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
      Text(label)
        .height('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Clip })
        .textAlign(TextAlign.Center)
        .fontSize(GALLERY_HOME_NAV_CHIP_FONT_VP)
        .fontColor($r('app.color.text_primary'))
    }
    .height(GALLERY_HOME_NAV_CHIP_HEIGHT_VP)
    .constraintSize({ minWidth: GALLERY_HOME_ENTRY_STRIP_MIN_CHIP_WIDTH_VP })
    .padding({ left: GALLERY_HOME_NAV_CHIP_PAD_H_VP, right: GALLERY_HOME_NAV_CHIP_PAD_H_VP })
    .borderRadius(GALLERY_HOME_NAV_CHIP_RADIUS_VP)
    .backgroundColor('#CCFFFFFF')
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .margin({ right: GALLERY_HOME_ENTRY_STRIP_GAP_VP })
    .onClick(action)
  }

  build() {
    if (this.hidden) {
      Blank().height(0)
    } else {
      Scroll() {
        Row() {
          Blank().width(GALLERY_HOME_ENTRY_STRIP_EDGE_GAP_VP)
          this.chip('媒体分类', this.onOpenMediaCategory)
          this.chip('智能分类', this.onOpenSmartCategory)
          this.chip('人物', this.onOpenPerson)
          this.chip('最近添加', this.onOpenRecent)
          this.chip('收藏', this.onOpenCollect)
          this.chip('回收站', this.onOpenRecycleBin)
        }
        .height(GALLERY_HOME_NAV_CHIP_HEIGHT_VP)
        .alignItems(VerticalAlign.Center)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(GALLERY_HOME_NAV_CHIP_HEIGHT_VP)
      .padding({
        left: GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_LEFT_VP,
        right: GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_RIGHT_VP,
        bottom: GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_BOTTOM_VP
      })
    }
  }
}
