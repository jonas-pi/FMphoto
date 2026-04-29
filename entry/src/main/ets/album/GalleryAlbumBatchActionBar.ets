import { BlurStrategy, DividerMode, HdsTabs } from '@kit.UIDesignKit';
import {
  GALLERY_BATCH_BAR_PAD_BOTTOM_VP,
  GALLERY_BATCH_BAR_PAD_TOP_VP
} from '../common/GalleryButtonStyles';
import {
  fnHdsBottomDockActionTabStyle,
  fnHdsImmersiveTabsFloatingStyle,
  FN_BOTTOM_DOCK_CENTER_HEIGHT_VP,
  FN_BOTTOM_DOCK_CENTER_RADIUS_VP,
  FN_BOTTOM_DOCK_SIDE_PADDING_VP
} from '../common/FnUiCommon';

const GALLERY_BATCH_ACTION_DOCK_WIDTH_VP: number = 228;

@Component
export struct GalleryAlbumBatchActionBar {
  @Prop downloading: boolean = false;
  @Prop deleting: boolean = false;

  onDownload: () => void = () => {};
  onDelete: () => void = () => {};

  private actionColor(busy: boolean, destructive: boolean = false): ResourceColor {
    if (busy) {
      return $r('app.color.text_secondary');
    }
    return destructive ? '#E11D48' : $r('app.color.brand_primary');
  }

  private onBatchHdsAction(index: number): void {
    if (index === 0) {
      if (!this.downloading) {
        this.onDownload();
      }
      return;
    }
    if (!this.deleting) {
      this.onDelete();
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
        $r('sys.symbol.trash'),
        $r('app.string.gallery_batch_delete'),
        this.actionColor(this.deleting, true)
      ))
    }
    .width(GALLERY_BATCH_ACTION_DOCK_WIDTH_VP)
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barHeight(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barWidth(GALLERY_BATCH_ACTION_DOCK_WIDTH_VP)
    .barFloatingStyle(fnHdsImmersiveTabsFloatingStyle(
      FN_BOTTOM_DOCK_CENTER_HEIGHT_VP,
      GALLERY_BATCH_ACTION_DOCK_WIDTH_VP,
      $r('app.color.gallery_material_surface_bg')
    ))
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
    Row() {
      this.batchHdsTabs()
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
