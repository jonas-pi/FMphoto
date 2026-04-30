import { BlurStrategy, DividerMode, HdsTabs } from '@kit.UIDesignKit';
import {
  GALLERY_BATCH_BAR_PAD_BOTTOM_VP,
  GALLERY_BATCH_BAR_PAD_TOP_VP
} from '../common/GalleryButtonStyles';
import {
  fnHdsBottomDockActionTabStyle,
  fnHdsImmersiveTabsFloatingStyle,
  fnLiquidGlassGradient,
  FN_BOTTOM_DOCK_CENTER_HEIGHT_VP,
  FN_BOTTOM_DOCK_CENTER_RADIUS_VP,
  FN_BOTTOM_DOCK_ICON_SIZE_VP,
  FN_BOTTOM_DOCK_INNER_PADDING_H_VP,
  FN_BOTTOM_DOCK_INNER_SPACE_VP,
  FN_BOTTOM_DOCK_ITEM_HEIGHT_VP,
  FN_BOTTOM_DOCK_ITEM_RADIUS_VP,
  FN_BOTTOM_DOCK_LABEL_SIZE_VP,
  FN_BOTTOM_DOCK_SIDE_PADDING_VP
} from '../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../common/FnImmersiveSettings';

const GALLERY_BATCH_ACTION_DOCK_WIDTH_VP: number = 228;

@Component
export struct GalleryAlbumBatchActionBar {
  @Prop downloading: boolean = false;
  @Prop deleting: boolean = false;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;

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

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
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
    // @SuppressWarnings compatibility
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

  @Builder
  private batchFallbackAction(index: number, icon: Resource, label: ResourceStr, color: ResourceColor) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(FN_BOTTOM_DOCK_ICON_SIZE_VP + 5)
        .fontColor([color])

      Text(label)
        .fontSize(FN_BOTTOM_DOCK_LABEL_SIZE_VP)
        .fontWeight(FontWeight.Medium)
        .fontColor(color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(FN_BOTTOM_DOCK_ITEM_HEIGHT_VP)
    .borderRadius(FN_BOTTOM_DOCK_ITEM_RADIUS_VP)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      this.onBatchHdsAction(index);
    })
  }

  @Builder
  private batchFallbackTabs() {
    Row({ space: FN_BOTTOM_DOCK_INNER_SPACE_VP }) {
      this.batchFallbackAction(
        0,
        $r('sys.symbol.download'),
        $r('app.string.gallery_batch_download'),
        this.actionColor(this.downloading)
      )
      this.batchFallbackAction(
        1,
        $r('sys.symbol.trash'),
        $r('app.string.gallery_batch_delete'),
        this.actionColor(this.deleting, true)
      )
    }
    .width(GALLERY_BATCH_ACTION_DOCK_WIDTH_VP)
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .padding({ left: FN_BOTTOM_DOCK_INNER_PADDING_H_VP, right: FN_BOTTOM_DOCK_INNER_PADDING_H_VP })
    .backgroundColor($r('app.color.gallery_material_surface_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(fnLiquidGlassGradient())
    .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
    .shadow({ radius: 18, color: '#28000000', offsetX: 0, offsetY: 8 })
    .clip(true)
  }

  build() {
    Row() {
      if (this.canUseHds()) {
        this.batchHdsTabs()
      } else {
        this.batchFallbackTabs()
      }
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
