import {
  GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_BOTTOM_VP,
  GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_LEFT_VP,
  GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_RIGHT_VP,
  GALLERY_HOME_NAV_CHIP_FONT_VP,
  GALLERY_HOME_NAV_CHIP_HEIGHT_VP,
  GALLERY_HOME_NAV_CHIP_PAD_H_VP,
  GALLERY_HOME_NAV_CHIP_RADIUS_VP
} from '../../common/GalleryButtonStyles';

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
    Button() {
      Text(label)
        .fontSize(GALLERY_HOME_NAV_CHIP_FONT_VP)
        .fontColor($r('app.color.text_primary'))
    }
    .height(GALLERY_HOME_NAV_CHIP_HEIGHT_VP)
    .padding({ left: GALLERY_HOME_NAV_CHIP_PAD_H_VP, right: GALLERY_HOME_NAV_CHIP_PAD_H_VP })
    .borderRadius(GALLERY_HOME_NAV_CHIP_RADIUS_VP)
    .backgroundColor($r('app.color.card_background'))
    .margin({ right: 8, bottom: 8 })
    .visibility(this.hidden ? Visibility.Hidden : Visibility.Visible)
    .enabled(!this.hidden)
    .onClick(action)
  }

  build() {
    Flex({
      direction: FlexDirection.Row,
      wrap: FlexWrap.Wrap,
      justifyContent: FlexAlign.Start,
      alignItems: ItemAlign.Center
    }) {
      this.chip('媒体分类', this.onOpenMediaCategory)
      this.chip('智能分类', this.onOpenSmartCategory)
      this.chip('人物', this.onOpenPerson)
      this.chip('最近添加', this.onOpenRecent)
      this.chip('收藏', this.onOpenCollect)
      this.chip('回收站', this.onOpenRecycleBin)
    }
    .width('100%')
    .padding({
      left: GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_LEFT_VP,
      right: GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_RIGHT_VP,
      bottom: GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_BOTTOM_VP
    })
  }
}
