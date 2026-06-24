import {
  fnImmersiveBackgroundEffect,
  fnLiquidGlassGradient,
  FN_FLOATING_TOP_TOTAL_HEIGHT_VP
} from '../../common/FnUiCommon';
import { GALLERY_TOP_BAR_PAD_RIGHT_VP } from '../../common/GalleryTopBarLayout';

@Component
export struct CategoryGalleryMoreMenu {
  @Prop expanded: boolean = false;
  @Prop topSafeInsetVp: number = 0;

  onDismiss: () => void = (): void => {};
  onEnterMultiselect: () => void = (): void => {};
  onOpenSlideshow: () => void = (): void => {};

  @Builder
  private menuRow(label: string, action: () => void) {
    Text(label)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .onClick(action)
  }

  build() {
    if (!this.expanded) {
      Blank()
    } else {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.onDismiss();
          })

        Column({ space: 4 }) {
          this.menuRow('多选', (): void => {
            this.onEnterMultiselect();
          })
          this.menuRow('幻灯片', (): void => {
            this.onOpenSlideshow();
          })
        }
        .width(196)
        .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        .backgroundColor($r('app.color.gallery_material_surface_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect())
        .linearGradient(fnLiquidGlassGradient())
        .borderRadius(22)
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })
        .shadow({ radius: 18, color: '#14001A33', offsetX: 0, offsetY: 8 })
        .clip(true)
        .margin({
          top: this.topSafeInsetVp + FN_FLOATING_TOP_TOTAL_HEIGHT_VP + 8,
          right: GALLERY_TOP_BAR_PAD_RIGHT_VP
        })
      }
      .width('100%')
      .height('100%')
    }
  }
}
