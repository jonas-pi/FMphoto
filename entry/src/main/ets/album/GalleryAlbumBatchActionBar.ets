import {
  GALLERY_BATCH_ACTION_HEIGHT_VP,
  GALLERY_BATCH_BAR_PAD_BOTTOM_VP,
  GALLERY_BATCH_BAR_PAD_LEFT_VP,
  GALLERY_BATCH_BAR_PAD_RIGHT_VP,
  GALLERY_BATCH_BAR_PAD_TOP_VP,
  GALLERY_BATCH_BAR_SPACE_VP,
  GALLERY_BATCH_DESTRUCTIVE_BG
} from '../common/GalleryButtonStyles';
import {
  fnImmersiveBackgroundEffect,
  fnImmersivePointLightSourceEffect,
  fnImmersiveTouchPressed,
  fnLiquidGlassGradient
} from '../common/FnUiCommon';

@Component
export struct GalleryAlbumBatchActionBar {
  @Prop downloading: boolean = false;
  @Prop deleting: boolean = false;
  @State private pressedKey: string = '';

  onDownload: () => void = () => {};
  onDelete: () => void = () => {};

  private syncPressed(key: string, event: TouchEvent): void {
    const pressed = fnImmersiveTouchPressed(event);
    if (pressed === undefined) {
      return;
    }
    if (pressed) {
      this.pressedKey = key;
    } else if (this.pressedKey === key) {
      this.pressedKey = '';
    }
  }

  build() {
    Row({ space: GALLERY_BATCH_BAR_SPACE_VP }) {
      Button($r('app.string.gallery_batch_download'), { type: ButtonType.Capsule, stateEffect: false })
        .layoutWeight(1)
        .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
        .fontColor($r('app.color.button_secondary_fg'))
        .backgroundColor($r('app.color.button_secondary_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect())
        .linearGradient(fnLiquidGlassGradient(false, this.pressedKey === 'download'))
        .borderRadius(GALLERY_BATCH_ACTION_HEIGHT_VP / 2)
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })
        .visualEffect(fnImmersivePointLightSourceEffect(false, this.pressedKey === 'download'))
        .shadow({ radius: 14, color: '#14001A33', offsetX: 0, offsetY: 6 })
        .clip(true)
        .enabled(!this.downloading)
        .onTouch((event: TouchEvent): void => {
          this.syncPressed('download', event);
        })
        .onClick(this.onDownload)
      Button($r('app.string.gallery_batch_delete'), { type: ButtonType.Capsule, stateEffect: false })
        .layoutWeight(1)
        .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
        .fontColor(Color.White)
        .backgroundColor(GALLERY_BATCH_DESTRUCTIVE_BG)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect(true, '#33E11D48'))
        .linearGradient(fnLiquidGlassGradient(true, this.pressedKey === 'delete'))
        .borderRadius(GALLERY_BATCH_ACTION_HEIGHT_VP / 2)
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })
        .visualEffect(fnImmersivePointLightSourceEffect(true, this.pressedKey === 'delete'))
        .shadow({ radius: 18, color: '#40E11D48', offsetX: 0, offsetY: 8 })
        .clip(true)
        .enabled(!this.deleting)
        .onTouch((event: TouchEvent): void => {
          this.syncPressed('delete', event);
        })
        .onClick(this.onDelete)
    }
    .width('100%')
    .padding({
      left: GALLERY_BATCH_BAR_PAD_LEFT_VP,
      right: GALLERY_BATCH_BAR_PAD_RIGHT_VP,
      top: GALLERY_BATCH_BAR_PAD_TOP_VP,
      bottom: GALLERY_BATCH_BAR_PAD_BOTTOM_VP
    })
    .backgroundColor(Color.Transparent)
  }
}
