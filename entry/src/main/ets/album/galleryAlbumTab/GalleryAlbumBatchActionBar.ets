import {
  GALLERY_BATCH_ACTION_HEIGHT_VP,
  GALLERY_BATCH_BAR_PAD_BOTTOM_VP,
  GALLERY_BATCH_BAR_PAD_LEFT_VP,
  GALLERY_BATCH_BAR_PAD_RIGHT_VP,
  GALLERY_BATCH_BAR_PAD_TOP_VP,
  GALLERY_BATCH_BAR_SPACE_VP,
  GALLERY_BATCH_DESTRUCTIVE_BG
} from '../../common/GalleryButtonStyles';

@Component
export struct GalleryAlbumBatchActionBar {
  @Prop downloading: boolean = false;
  @Prop deleting: boolean = false;

  onDownload: () => void = () => {};
  onDelete: () => void = () => {};

  build() {
    Row({ space: GALLERY_BATCH_BAR_SPACE_VP }) {
      Button($r('app.string.gallery_batch_download'), { type: ButtonType.Capsule, stateEffect: true })
        .layoutWeight(1)
        .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.card_background'))
        .enabled(!this.downloading)
        .onClick(this.onDownload)
      Button($r('app.string.gallery_batch_delete'), { type: ButtonType.Capsule, stateEffect: true })
        .layoutWeight(1)
        .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
        .fontColor(Color.White)
        .backgroundColor(GALLERY_BATCH_DESTRUCTIVE_BG)
        .enabled(!this.deleting)
        .onClick(this.onDelete)
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

