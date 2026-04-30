/**
 * 通用 UI 组件。
 * - FnTopBar: 统一子页面顶栏，与图库首页 1-2-1 布局和 36vp 按钮对齐
 * - FnPrimaryButton/FnSecondaryButton: 统一主次按钮样式
 * - FnFullLoadingMask: 统一全屏阻断式加载遮罩
 */

import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier, window } from '@kit.ArkUI';
import {
  BlurStrategy,
  DividerMode,
  HdsTabs,
  HdsTabsFloatingStyle,
  hdsMaterial,
  SystemMaterialParams
} from '@kit.UIDesignKit';

import {
  GALLERY_TOP_BAR_BUTTON_FONT_VP,
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_ROW_HEIGHT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from './GalleryTopBarLayout';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from './FnImmersiveSettings';

export const FN_FLOATING_TOP_MARGIN_VP: number = 8;
export const FN_FLOATING_TOP_BOTTOM_GAP_VP: number = 6;
export const FN_FLOATING_TOP_CONTROL_SIZE_VP: number = 40;
export const FN_FLOATING_TOP_CONTROL_RADIUS_VP: number = FN_FLOATING_TOP_CONTROL_SIZE_VP / 2;
export const FN_FLOATING_TOP_PILL_MIN_WIDTH_VP: number = 62;
export const FN_FLOATING_TOP_META_FONT_VP: number = 11;
export const FN_FLOATING_TOP_TITLE_STACK_GAP_VP: number = 1;
export const FN_FLOATING_TOP_TOTAL_HEIGHT_VP: number =
  FN_FLOATING_TOP_MARGIN_VP + FN_FLOATING_TOP_CONTROL_SIZE_VP + FN_FLOATING_TOP_BOTTOM_GAP_VP;
export const FN_BOTTOM_DOCK_SIDE_PADDING_VP: number = 14;
export const FN_BOTTOM_DOCK_SIDE_GAP_VP: number = 10;
export const FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP: number = 54;
export const FN_BOTTOM_DOCK_CENTER_HEIGHT_VP: number = 54;
export const FN_BOTTOM_DOCK_CENTER_RADIUS_VP: number = 27;
export const FN_BOTTOM_DOCK_ITEM_RADIUS_VP: number = 16;
export const FN_BOTTOM_DOCK_ICON_SIZE_VP: number = 19;
export const FN_BOTTOM_DOCK_LABEL_SIZE_VP: number = 11;
export const FN_BOTTOM_DOCK_INNER_PADDING_H_VP: number = 5;
export const FN_BOTTOM_DOCK_INNER_SPACE_VP: number = 6;
export const FN_BOTTOM_DOCK_ITEM_HEIGHT_VP: number = FN_BOTTOM_DOCK_CENTER_HEIGHT_VP - 8;
export const FN_BOTTOM_DOCK_BASE_GAP_VP: number = 16;

export function fnBottomDockBottomGap(bottomSafeInsetVp: number): number {
  const liftedGap = FN_BOTTOM_DOCK_BASE_GAP_VP + (FN_BOTTOM_DOCK_CENTER_HEIGHT_VP / 4);
  return Math.max(liftedGap, bottomSafeInsetVp + liftedGap);
}

export function fnImmersiveBackgroundEffect(strong: boolean = false, color?: ResourceColor): BackgroundEffectOptions {
  return {
    radius: strong ? 32 : 26,
    saturation: strong ? 1.32 : 1.22,
    brightness: strong ? 1.1 : 1.06,
    color: color ?? (strong ? $r('app.color.immersive_panel_strong_bg') : $r('app.color.immersive_panel_bg')),
    adaptiveColor: AdaptiveColor.DEFAULT
  };
}

export function fnHdsImmersiveSystemMaterialEffect(): SystemMaterialParams {
  // @SuppressWarnings compatibility
  let materialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.IMMERSIVE;
  // @SuppressWarnings compatibility
  let materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
  try {
    // @SuppressWarnings compatibility
    const materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
    // @SuppressWarnings compatibility
    if (materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) < 0) {
      // @SuppressWarnings compatibility
      materialType = hdsMaterial.MaterialType.ADAPTIVE;
      // @SuppressWarnings compatibility
      materialLevel = hdsMaterial.MaterialLevel.SMOOTH;
    }
  } catch (_e) {
    // @SuppressWarnings compatibility
    materialType = hdsMaterial.MaterialType.ADAPTIVE;
    // @SuppressWarnings compatibility
    materialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  }
  return { materialType: materialType, materialLevel: materialLevel };
}

export function fnHdsImmersiveTabsFloatingStyle(
  height: number,
  width: Length = '100%',
  lightColor: ResourceColor = $r('app.color.gallery_material_surface_bg')
): HdsTabsFloatingStyle {
  return {
    barWidth: {
      smallWidth: width,
      mediumWidth: width,
      largeWidth: width
    },
    barSideMargin: 0,
    barBottomMargin: 0,
    gradientMask: {
      maskColor: Color.Transparent,
      maskHeight: height
    },
    lightColor: lightColor,
    systemMaterialEffect: fnHdsImmersiveSystemMaterialEffect()
  };
}

export function fnHdsBottomDockActionTabStyle(
  icon: Resource,
  label: ResourceStr,
  color: ResourceColor = $r('app.color.brand_primary')
): BottomTabBarStyle {
  const tabSymbol: TabBarSymbol = {
    normal: new SymbolGlyphModifier(icon)
      .fontSize(FN_BOTTOM_DOCK_ICON_SIZE_VP + 5)
      .fontColor([color]),
    selected: new SymbolGlyphModifier(icon)
      .fontSize(FN_BOTTOM_DOCK_ICON_SIZE_VP + 5)
      .fontColor([color])
  };
  return new BottomTabBarStyle(tabSymbol, label)
    .labelStyle({
      font: { size: FN_BOTTOM_DOCK_LABEL_SIZE_VP, weight: FontWeight.Medium },
      selectedColor: color,
      unselectedColor: color
    })
    .iconStyle({
      selectedColor: color,
      unselectedColor: color
    })
    .padding({ left: 0, right: 0, top: 3, bottom: 2 })
    .layoutMode(LayoutMode.VERTICAL)
    .verticalAlign(VerticalAlign.Center)
    .symmetricExtensible(true);
}

@Component
export struct FnHdsPillButton {
  @Prop text: ResourceStr = '';
  @Prop widthValue: Length = FN_FLOATING_TOP_PILL_MIN_WIDTH_VP;
  @Prop heightValue: number = FN_FLOATING_TOP_CONTROL_SIZE_VP;
  @Prop radiusValue: number = -1;
  @Prop fontSizeValue: number = GALLERY_TOP_BAR_BUTTON_FONT_VP;
  @Prop fontColorValue: ResourceColor = $r('app.color.button_secondary_fg');
  @Prop fontWeightValue: FontWeight | number | string = FontWeight.Medium;
  @Prop lightColorValue: ResourceColor = $r('app.color.gallery_material_surface_bg');
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  @State private measuredWidthVp: number = 0;
  action: () => void = () => {};
  private lastActionAt: number = 0;

  private shapeRadius(): number {
    return this.radiusValue >= 0 ? this.radiusValue : this.heightValue / 2;
  }

  private materialWidth(): Length {
    return this.measuredWidthVp > 1 ? this.measuredWidthVp : this.widthValue;
  }

  private triggerAction(): void {
    const now = Date.now();
    if (now - this.lastActionAt < 80) {
      return;
    }
    this.lastActionAt = now;
    this.action();
  }

  private shouldUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  @Builder
  private blankTabBarContent() {
    Row()
      .width('100%')
      .height('100%')
  }

  @Builder
  private labelContent() {
    Row() {
      Text(this.text)
        .fontSize(this.fontSizeValue)
        .fontWeight(this.fontWeightValue)
        .fontColor(this.fontColorValue)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Clip })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 8 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      if (this.shouldUseHds()) {
        HdsTabs({ index: 0 }) {
          TabContent() {
            Column()
              .width('100%')
              .height('100%')
          }
          .tabBar(this.blankTabBarContent)
        }
        .width('100%')
        .height(this.heightValue)
        .barHeight(this.heightValue)
        .barOverlap(true)
        .vertical(false)
        .barPosition(BarPosition.End)
        .barWidth(this.materialWidth())
        // @SuppressWarnings compatibility
        .barFloatingStyle(fnHdsImmersiveTabsFloatingStyle(this.heightValue, this.materialWidth(), this.lightColorValue))
        .scrollable(false)
        .divider({ mode: DividerMode.NONE })
        .barBackgroundColor(Color.Transparent)
        .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: this.heightValue })
        .blurStrategy(BlurStrategy.ADAPTIVE)
        .borderRadius(this.shapeRadius())
        .clip(true)
        .onContentWillChange((_currentIndex: number, _comingIndex: number): boolean => {
          return false;
        })
        .onTabBarClick((_index: number): void => {
          this.triggerAction();
        })
      } else {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(this.lightColorValue)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .linearGradient(fnLiquidGlassGradient())
          .borderRadius(this.shapeRadius())
          .borderWidth(1)
          .borderColor($r('app.color.immersive_panel_border'))
          .shadow({ radius: 12, color: '#18000000', offsetX: 0, offsetY: 4 })
          .clip(true)
      }

      this.labelContent()
    }
    .width(this.widthValue)
    .height(this.heightValue)
    .onAreaChange((_old: Area, area: Area): void => {
      const width = area.width as number;
      if (width > 1 && Math.abs(width - this.measuredWidthVp) > 0.5) {
        this.measuredWidthVp = width;
      }
    })
    .onClick((): void => {
      this.triggerAction();
    })
  }
}

@Component
export struct FnHdsSymbolButton {
  @Prop symbol: Resource = $r('sys.symbol.more');
  @Prop widthValue: Length = FN_FLOATING_TOP_CONTROL_SIZE_VP;
  @Prop heightValue: number = FN_FLOATING_TOP_CONTROL_SIZE_VP;
  @Prop radiusValue: number = -1;
  @Prop fontSizeValue: number = 17;
  @Prop fontColorValue: ResourceColor = $r('app.color.icon_primary');
  @Prop lightColorValue: ResourceColor = $r('app.color.gallery_material_surface_bg');
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  action: () => void = () => {};
  private lastActionAt: number = 0;

  private shapeRadius(): number {
    return this.radiusValue >= 0 ? this.radiusValue : Math.min(this.heightValue, this.numericWidth()) / 2;
  }

  private numericWidth(): number {
    return typeof this.widthValue === 'number' ? this.widthValue : this.heightValue;
  }

  private triggerAction(): void {
    const now = Date.now();
    if (now - this.lastActionAt < 80) {
      return;
    }
    this.lastActionAt = now;
    this.action();
  }

  private shouldUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  @Builder
  private tabBarContent() {
    Row() {
      SymbolGlyph(this.symbol)
        .fontSize(this.fontSizeValue)
        .fontColor([this.fontColorValue])
    }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
  }

  build() {
    Stack() {
      if (this.shouldUseHds()) {
        HdsTabs({ index: 0 }) {
          TabContent() {
            Column()
              .width('100%')
              .height('100%')
          }
          .tabBar(this.tabBarContent)
        }
        .width(this.widthValue)
        .height(this.heightValue)
        .barHeight(this.heightValue)
        .barOverlap(true)
        .vertical(false)
        .barPosition(BarPosition.End)
        .barWidth(this.widthValue)
        // @SuppressWarnings compatibility
        .barFloatingStyle(fnHdsImmersiveTabsFloatingStyle(this.heightValue, this.widthValue, this.lightColorValue))
        .scrollable(false)
        .divider({ mode: DividerMode.NONE })
        .barBackgroundColor(Color.Transparent)
        .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: this.heightValue })
        .blurStrategy(BlurStrategy.ADAPTIVE)
        .borderRadius(this.shapeRadius())
        .clip(true)
        .onContentWillChange((_currentIndex: number, _comingIndex: number): boolean => {
          return false;
        })
        .onTabBarClick((_index: number): void => {
          this.triggerAction();
        })
      } else {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(this.lightColorValue)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .linearGradient(fnLiquidGlassGradient())
          .borderRadius(this.shapeRadius())
          .borderWidth(1)
          .borderColor($r('app.color.immersive_panel_border'))
          .shadow({ radius: 12, color: '#18000000', offsetX: 0, offsetY: 4 })
          .clip(true)
      }

      if (!this.shouldUseHds()) {
        this.tabBarContent()
      }
    }
    .width(this.widthValue)
    .height(this.heightValue)
    .onClick((): void => {
      this.triggerAction();
    })
  }
}

@Component
export struct FnHdsTextPill {
  @Prop text: ResourceStr = '';
  @Prop widthValue: Length = FN_FLOATING_TOP_PILL_MIN_WIDTH_VP;
  @Prop heightValue: number = FN_FLOATING_TOP_CONTROL_SIZE_VP;
  @Prop radiusValue: number = -1;
  @Prop fontSizeValue: number = GALLERY_TOP_BAR_BUTTON_FONT_VP;
  @Prop fontColorValue: ResourceColor = $r('app.color.button_secondary_fg');
  @Prop fontWeightValue: FontWeight | number | string = FontWeight.Medium;
  @Prop lightColorValue: ResourceColor = $r('app.color.gallery_material_surface_bg');
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;

  private shapeRadius(): number {
    return this.radiusValue >= 0 ? this.radiusValue : this.heightValue / 2;
  }

  private shouldUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  @Builder
  private blankTabBarContent() {
    Row()
      .width('100%')
      .height('100%')
  }

  @Builder
  private labelContent() {
    Row() {
      Text(this.text)
        .fontSize(this.fontSizeValue)
        .fontWeight(this.fontWeightValue)
        .fontColor(this.fontColorValue)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 8 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      if (this.shouldUseHds()) {
        HdsTabs({ index: 0 }) {
          TabContent() {
            Column()
              .width('100%')
              .height('100%')
          }
          .tabBar(this.blankTabBarContent)
        }
        .width('100%')
        .height(this.heightValue)
        .barHeight(this.heightValue)
        .barOverlap(true)
        .vertical(false)
        .barPosition(BarPosition.End)
        .barWidth(this.widthValue)
        // @SuppressWarnings compatibility
        .barFloatingStyle(fnHdsImmersiveTabsFloatingStyle(this.heightValue, this.widthValue, this.lightColorValue))
        .scrollable(false)
        .divider({ mode: DividerMode.NONE })
        .barBackgroundColor(Color.Transparent)
        .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: this.heightValue })
        .blurStrategy(BlurStrategy.ADAPTIVE)
        .borderRadius(this.shapeRadius())
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
      } else {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(this.lightColorValue)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .linearGradient(fnLiquidGlassGradient())
          .borderRadius(this.shapeRadius())
          .borderWidth(1)
          .borderColor($r('app.color.immersive_panel_border'))
          .clip(true)
          .hitTestBehavior(HitTestMode.None)
      }

      this.labelContent()
    }
    .width(this.widthValue)
    .height(this.heightValue)
    .hitTestBehavior(HitTestMode.None)
  }
}

export function fnLiquidGlassGradient(strong: boolean = false, pressed: boolean = false): LinearGradientOptions {
  return {
    angle: pressed ? 118 : 132,
    colors: [
      [strong ? '#B8FFFFFF' : '#82FFFFFF', 0.00],
      [pressed ? '#58FFFFFF' : (strong ? '#3DFFFFFF' : '#26FFFFFF'), 0.22],
      ['#12FFFFFF', 0.46],
      [pressed ? '#34FFFFFF' : '#18FFFFFF', 0.72],
      ['#00FFFFFF', 1.00]
    ]
  };
}

@Component
export struct FnFloatingTopPillButton {
  @Prop text: ResourceStr = '';
  @Prop prominent: boolean = false;
  action: () => void = () => {};

  build() {
    FnHdsPillButton({
      text: this.text,
      widthValue: FN_FLOATING_TOP_PILL_MIN_WIDTH_VP,
      heightValue: FN_FLOATING_TOP_CONTROL_SIZE_VP,
      radiusValue: FN_FLOATING_TOP_CONTROL_RADIUS_VP,
      fontSizeValue: GALLERY_TOP_BAR_BUTTON_FONT_VP,
      fontColorValue: this.prominent ? $r('app.color.brand_primary') : $r('app.color.button_secondary_fg'),
      action: this.action
    })
  }
}

@Component
export struct FnFloatingTopCircleButton {
  @Prop symbol: Resource = $r('sys.symbol.more');
  @Prop active: boolean = false;
  @Prop fontColor: ResourceColor = $r('app.color.icon_primary');
  @Prop activeBg: ResourceColor = $r('app.color.brand_primary');
  action: () => void = () => {};

  build() {
    FnHdsSymbolButton({
      symbol: this.symbol,
      widthValue: FN_FLOATING_TOP_CONTROL_SIZE_VP,
      heightValue: FN_FLOATING_TOP_CONTROL_SIZE_VP,
      radiusValue: FN_FLOATING_TOP_CONTROL_RADIUS_VP,
      fontSizeValue: 17,
      fontColorValue: this.active ? this.activeBg : this.fontColor,
      action: this.action
    })
  }
}

@Component
export struct FnTopBar {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop backText: string = '返回';
  @Prop rightText: string = '';
  @State private systemTopInsetVp: number = 0;

  private pxToVp(value: number): number {
    try {
      return this.getUIContext().px2vp(value);
    } catch (_e) {
      return value;
    }
  }

  private syncSystemTopInset(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win): void => {
        try {
          const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
          this.systemTopInsetVp = Math.max(0, this.pxToVp(area.topRect.height));
        } catch (_e) {
          this.systemTopInsetVp = 0;
        }
      }).catch((_e: Error): void => {
        this.systemTopInsetVp = 0;
      });
    } catch (_e) {
      this.systemTopInsetVp = 0;
    }
  }

  aboutToAppear(): void {
    this.syncSystemTopInset();
  }

  build() {
    Row() {
      Row() {
        FnFloatingTopPillButton({
          text: this.backText,
          action: (): void => {
            this.getUIContext().getRouter().back();
          }
        })
      }
      .layoutWeight(1)
      .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
      .justifyContent(FlexAlign.Start)

      Column({ space: FN_FLOATING_TOP_TITLE_STACK_GAP_VP }) {
        Text(this.title)
          .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.text_primary'))

        Text(this.subtitle.length > 0 ? this.subtitle : ' ')
          .fontSize(FN_FLOATING_TOP_META_FONT_VP)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.text_secondary'))
          .opacity(this.subtitle.length > 0 ? 1 : 0)
      }
        .layoutWeight(2)
        .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

      Row() {
        if (this.rightText.length > 0) {
          Text(this.rightText)
            .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
    .alignItems(VerticalAlign.Center)
    .padding({ left: GALLERY_TOP_BAR_PAD_LEFT_VP, right: GALLERY_TOP_BAR_PAD_RIGHT_VP })
    .margin({
      top: this.systemTopInsetVp + FN_FLOATING_TOP_MARGIN_VP,
      bottom: FN_FLOATING_TOP_BOTTOM_GAP_VP
    })
  }
}

@Component
export struct FnPrimaryButton {
  @Prop text: ResourceStr = '';
  action: () => void = () => {};

  build() {
    FnHdsPillButton({
      text: this.text,
      widthValue: '100%',
      heightValue: 40,
      fontSizeValue: 16,
      fontColorValue: $r('app.color.brand_primary'),
      action: this.action
    })
  }
}

@Component
export struct FnSecondaryButton {
  @Prop text: ResourceStr = '';
  action: () => void = () => {};

  build() {
    FnHdsPillButton({
      text: this.text,
      widthValue: '100%',
      heightValue: 40,
      fontSizeValue: 16,
      fontColorValue: $r('app.color.button_secondary_fg'),
      action: this.action
    })
  }
}

@Component
export struct FnImmersiveBackdrop {
  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))

      Column() {
        Row() {
          Column()
            .width(240)
            .height(240)
            .borderRadius(120)
            .backgroundColor($r('app.color.immersive_glow_primary'))
            .opacity(0.55)
            .shadow({ radius: 70, color: $r('app.color.immersive_glow_primary'), offsetX: 0, offsetY: 0 })

          Row()
            .layoutWeight(1)

          Column()
            .width(180)
            .height(180)
            .borderRadius(90)
            .backgroundColor($r('app.color.immersive_glow_secondary'))
            .opacity(0.42)
            .shadow({ radius: 56, color: $r('app.color.immersive_glow_secondary'), offsetX: 0, offsetY: 0 })
        }
        .width('100%')
        .padding({ left: 24, right: 12, top: 18 })

        Row()
          .layoutWeight(1)

        Row() {
          Row()
            .layoutWeight(1)

          Column()
            .width(220)
            .height(220)
            .borderRadius(110)
            .backgroundColor($r('app.color.immersive_glow_tertiary'))
            .opacity(0.34)
            .shadow({ radius: 64, color: $r('app.color.immersive_glow_tertiary'), offsetX: 0, offsetY: 0 })
        }
        .width('100%')
        .padding({ right: 18, bottom: 72 })
      }
      .width('100%')
      .height('100%')

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.immersive_halo_soft'))
        .opacity(0.78)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}

@Component
export struct FnFullLoadingMask {
  @Prop topOffsetVp: number = 0;
  @Prop text: string = '加载中...';

  build() {
    Column({ space: 10 }) {
      LoadingProgress().width(48).height(48).color(Color.White)
      Text(this.text).fontSize(14).fontColor(Color.White)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: this.topOffsetVp })
    .backgroundColor($r('app.color.overlay_mask'))
    .hitTestBehavior(HitTestMode.Block)
  }
}

@Component
export struct FnInlineLoading {
  @Prop topOffsetVp: number = 0;
  @Prop text: string = '加载中...';

  build() {
    Row({ space: 10 }) {
      LoadingProgress().width(28).height(28)
      Text(this.text).fontSize(14).fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: this.topOffsetVp })
  }
}

@Component
export struct FnStateText {
  @Prop text: string = '';
  @Prop isError: boolean = false;
  @Prop topOffsetVp: number = 0;

  build() {
    Text(this.text)
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 24, right: 24, top: this.topOffsetVp + 40 })
      .textAlign(TextAlign.Center)
      .fontSize(14)
      .fontColor(this.isError ? '#FFE0483E' : $r('app.color.text_secondary'))
  }
}
