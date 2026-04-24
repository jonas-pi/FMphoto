import {
  GALLERY_BATCH_ACTION_HEIGHT_VP,
  GALLERY_BATCH_BAR_PAD_BOTTOM_VP,
  GALLERY_BATCH_BAR_PAD_LEFT_VP,
  GALLERY_BATCH_BAR_PAD_RIGHT_VP,
  GALLERY_BATCH_BAR_PAD_TOP_VP,
  GALLERY_BATCH_BAR_SPACE_VP
} from '../../common/GalleryButtonStyles';

@Component
export struct RecycleBinBatchBar {
  @Prop downloading: boolean = false;
  @Prop restoring: boolean = false;

  onDownload: () => void = () => {};
  onRestore: () => void = () => {};

  build() {
    Row({ space: GALLERY_BATCH_BAR_SPACE_VP }) {
      Button($r('app.string.gallery_batch_download'), { type: ButtonType.Capsule, stateEffect: true })
        .layoutWeight(1)
        .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.card_background'))
        .enabled(!this.downloading)
        .onClick(this.onDownload)
      Button('还原', { type: ButtonType.Capsule, stateEffect: true })
        .layoutWeight(1)
        .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
        .fontColor(Color.White)
        .backgroundColor($r('app.color.brand_primary'))
        .enabled(!this.restoring)
        .onClick(this.onRestore)
    }
    .width('100%')
    .padding({
      left: GALLERY_BATCH_BAR_PAD_LEFT_VP,
      right: GALLERY_BATCH_BAR_PAD_RIGHT_VP,
      top: GALLERY_BATCH_BAR_PAD_TOP_VP,
      bottom: GALLERY_BATCH_BAR_PAD_BOTTOM_VP
    })
    .backgroundColor($r('app.color.page_background'))
  }
}
