import { BlurStrategy, DividerMode, HdsTabs } from '@kit.UIDesignKit';
import {
  GALLERY_BATCH_BAR_PAD_BOTTOM_VP,
  GALLERY_BATCH_BAR_PAD_TOP_VP
} from '../../common/GalleryButtonStyles';
import {
  fnHdsBottomDockActionTabStyle,
  fnHdsImmersiveSystemMaterialEffect,
  FN_BOTTOM_DOCK_CENTER_HEIGHT_VP,
  FN_BOTTOM_DOCK_CENTER_RADIUS_VP,
  FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP,
  FN_BOTTOM_DOCK_SIDE_GAP_VP,
  FN_BOTTOM_DOCK_SIDE_PADDING_VP
} from '../../common/FnUiCommon';

@Component
export struct RecycleBinBatchBar {
  @Prop downloading: boolean = false;
  @Prop restoring: boolean = false;

  onDownload: () => void = () => {};
  onRestore: () => void = () => {};

  private actionColor(busy: boolean): ResourceColor {
    return busy ? $r('app.color.text_secondary') : $r('app.color.brand_primary');
  }

  private onBatchHdsAction(index: number): void {
    if (index === 0) {
      if (!this.downloading) {
        this.onDownload();
      }
      return;
    }
    if (!this.restoring) {
      this.onRestore();
    }
  }

  @Builder
  private batchHdsTabs() {
    HdsTabs({ index: 0 }) {
      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(fnHdsBottomDockActionTabStyle(
        $r('sys.symbol.download'),
        $r('app.string.gallery_batch_download'),
        this.actionColor(this.downloading)
      ))

      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(fnHdsBottomDockActionTabStyle(
        $r('sys.symbol.arrow_counterclockwise'),
        '\u8fd8\u539f',
        this.actionColor(this.restoring)
      ))
    }
    .width('100%')
    .layoutWeight(1)
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barHeight(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barFloatingStyle({
      barBottomMargin: 0,
      gradientMask: {
        maskColor: Color.Transparent,
        maskHeight: FN_BOTTOM_DOCK_CENTER_HEIGHT_VP
      },
      lightColor: $r('app.color.gallery_material_surface_bg'),
      systemMaterialEffect: fnHdsImmersiveSystemMaterialEffect()
    })
    .scrollable(false)
    .divider({ mode: DividerMode.NONE })
    .barBackgroundColor(Color.Transparent)
    .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: FN_BOTTOM_DOCK_CENTER_HEIGHT_VP })
    .blurStrategy(BlurStrategy.ADAPTIVE)
    .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
    .clip(true)
    .onContentWillChange((_currentIndex: number, _comingIndex: number): boolean => {
      return false;
    })
    .onTabBarClick((index: number): void => {
      this.onBatchHdsAction(index);
    })
  }

  build() {
    Row({ space: FN_BOTTOM_DOCK_SIDE_GAP_VP }) {
      Blank()
        .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
        .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)

      this.batchHdsTabs()

      Blank()
        .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
        .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
    }
    .width('100%')
    .padding({
      left: FN_BOTTOM_DOCK_SIDE_PADDING_VP,
      right: FN_BOTTOM_DOCK_SIDE_PADDING_VP,
      top: GALLERY_BATCH_BAR_PAD_TOP_VP,
      bottom: GALLERY_BATCH_BAR_PAD_BOTTOM_VP
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
  }
}
