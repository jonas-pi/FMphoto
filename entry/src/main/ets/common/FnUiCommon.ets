/**
 * 通用 UI 组件。
 * - FnTopBar: 统一子页面顶栏，与图库首页 1-2-1 布局和 36vp 按钮对齐
 * - FnPrimaryButton/FnSecondaryButton: 统一主次按钮样式
 * - FnFullLoadingMask: 统一全屏阻断式加载遮罩
 */

import { LengthMetrics, SymbolGlyphModifier } from '@kit.ArkUI';
import {
  hdsEffect,
  HdsNavigationBackgroundStyle,
  HdsTabsFloatingStyle,
  PaddingOptions,
  ScrollEffectOptions,
  ScrollEffectType
} from '@kit.UIDesignKit';
// @SuppressWarnings compatibility
import { hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';

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
import { FN_SYSTEM_TOP_INSET_VP_KEY } from './FnSystemAvoidArea';

export const FN_FLOATING_TOP_MARGIN_VP: number = 8;
export const FN_FLOATING_TOP_BOTTOM_GAP_VP: number = 6;
export const FN_FLOATING_TOP_CONTROL_SIZE_VP: number = 40;
export const FN_FLOATING_TOP_CONTROL_RADIUS_VP: number = FN_FLOATING_TOP_CONTROL_SIZE_VP / 2;
export const FN_FLOATING_TOP_PILL_MIN_WIDTH_VP: number = 62;
export const FN_FLOATING_TOP_META_FONT_VP: number = 11;
export const FN_FLOATING_TOP_TITLE_STACK_GAP_VP: number = 1;
/** 官方 HdsNavigation MINI 标题栏内容区高度，顶栏统一对齐该高度 */
export const FN_HDS_NAV_CHROME_HEIGHT_VP: number = 56;
export const FN_FLOATING_TOP_TOTAL_HEIGHT_VP: number = FN_HDS_NAV_CHROME_HEIGHT_VP;
/**
 * HdsNavigation 菜单/返回按钮背板。
 * 保持透明，由 systemMaterialEffect 出与底栏同系的半透明深色沉浸材质；
 * 勿叠浅灰（灰底）或高不透明度深色（不透）。
 */
export function fnHdsChromeButtonBackgroundColor(): ResourceColor {
  return Color.Transparent;
}

/** 顶栏按钮图标/文字色（跟底栏侧钮一致，走主题主色） */
export function fnHdsChromeButtonForegroundColor(): ResourceColor {
  return $r('app.color.icon_primary');
}

/** 无沉浸光感时的顶栏按钮背板（浅灰玻璃） */
export function fnHdsChromeButtonFallbackBackgroundColor(): ResourceColor {
  return $r('app.color.gallery_material_surface_bg');
}

/**
 * 顶端初始样式：透明、无模糊。
 * 勿用于 scrollEffectStyle：强制 blurRadius 0 会让离开顶端后模糊无法保持。
 */
export function fnHdsNavChromeBackgroundStyle(): HdsNavigationBackgroundStyle {
  return {
    backgroundColor: Color.Transparent,
    blurRadius: 0,
    maskExtraHeight: 0
  };
}

/**
 * 离开顶端后的标题栏背板。
 * blurRadius 用官方 scrollEffectStyle 默认 16（带 systemMaterialEffect 时系统默认是 12）。
 * 叠一层半透明色：官方 GRADIENT_BLUR 滚动后默认 #99000000，这里按浅色白霜 / 深色黑罩各取约 1/3 透明度，避免整条实心底。
 */
export function fnHdsNavChromeScrolledBackgroundStyle(): HdsNavigationBackgroundStyle {
  return {
    backgroundColor: $r('app.color.gallery_nav_scrolled_bg'),
    blurRadius: 16
  };
}

/**
 * 官方 HdsNavigation titleBar.padding：用 float 资源，避免 LengthMetrics.vp
 * 被 Native 先当 Resource 解析而打出 ParseTitleBarPadding FAILED。
 * 左右与多选 / 搜索 / 更多离屏边距统一。
 */
export function fnHdsNavTitleBarPadding(): PaddingOptions {
  return {
    start: LengthMetrics.resource($r('app.float.hds_title_bar_padding_horizontal')),
    end: LengthMetrics.resource($r('app.float.hds_title_bar_padding_horizontal'))
  };
}

/**
 * 官方：按内容区总偏移在 originalStyle → scrollEffectStyle 之间线性过渡。
 * 起止偏移走 HDS 默认值，不传 LengthMetrics.vp，避免 ParseScrollEffect resource parsed FAILED。
 */
export function fnHdsNavChromeScrollEffectOpts(): ScrollEffectOptions {
  return {
    enableScrollEffect: true,
    // @SuppressWarnings compatibility
    scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
  };
}
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
/** 顶栏按钮开启态（对齐 sys.color.ohos_id_color_activated 语义）背景叠色 */
const FN_FLOATING_BUTTON_ACTIVE_LIGHT_COLOR: string = '#334A8BFF';
const FN_FLOATING_BUTTON_ACTIVE_BORDER_COLOR: string = '#664A8BFF';

export function fnFloatingButtonActiveLightColor(
  active: boolean,
  base: ResourceColor = $r('app.color.gallery_material_surface_bg')
): ResourceColor {
  return active ? FN_FLOATING_BUTTON_ACTIVE_LIGHT_COLOR : base;
}

export function fnFloatingButtonActiveFontColor(
  active: boolean,
  prominent: boolean,
  base: ResourceColor
): ResourceColor {
  if (active || prominent) {
    return $r('sys.color.ohos_id_color_activated');
  }
  return base;
}

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

/**
 * 悬浮底栏统一配置。
 * 必须显式设置 barWidth / barSideMargin：未设置时系统默认单页签 76vp、侧边距 16vp，
 * 在「中栏 + 侧钮」Row 布局里会把右侧控件挤出屏幕（鸿蒙 7 上更明显）。
 * adaptToHandedness 固定关闭，避免智感握姿把胶囊栏整体右偏。
 */
export function fnHdsImmersiveTabsFloatingStyle(
  barHeight: number,
  width: Length = '100%',
  lightColor: ResourceColor = Color.Transparent,
  barBottomMargin: number = 0,
  barSideMargin: number = 0
): HdsTabsFloatingStyle {
  return {
    barWidth: {
      smallWidth: width,
      mediumWidth: width,
      largeWidth: width
    },
    barSideMargin: barSideMargin,
    barBottomMargin: barBottomMargin,
    // @SuppressWarnings compatibility
    adaptToHandedness: false,
    // 官方 gradientMask 默认深色 #99000000、高度=栏高+16，overlay 上会铺成黑矩形。
    // 关闭遮罩不能省略字段（省略即走默认），须显式全透明；maskHeight 不能为 0。
    gradientMask: {
      maskColor: '#00000000',
      maskHeight: barHeight > 0 ? 1 : 1
    },
    lightColor: lightColor,
    // @SuppressWarnings compatibility
    systemMaterialEffect: fnHdsImmersiveSystemMaterialEffect()
  };
}

/** 离中胶囊给果冻膨胀留的四周余量。容器必须比栏身大，且不能 clip。 */
export const FN_HDS_CAPSULE_JELLY_VP: number = 12;

export function fnHdsCapsuleOverlayWidth(barWidth: number): number {
  return barWidth + FN_HDS_CAPSULE_JELLY_VP * 2;
}

export function fnHdsCapsuleOverlayHeight(barHeight: number): number {
  return barHeight + FN_HDS_CAPSULE_JELLY_VP * 2;
}

/**
 * 官方悬浮页签：HdsTabs 必须铺满宿主（width/height 100%），栏身由 barWidth + barBottomMargin 定位。
 * 缩成 54vp 小盒子时，systemMaterialEffect 会铺成矩形阴影。
 */
export function fnHdsDockTabsFloatingStyle(
  barWidth: Length,
  barBottomMargin: number,
  barSideMargin: number = 0
): HdsTabsFloatingStyle {
  return {
    barWidth: {
      smallWidth: barWidth,
      mediumWidth: barWidth,
      largeWidth: barWidth
    },
    barSideMargin: barSideMargin,
    barBottomMargin: barBottomMargin,
    // @SuppressWarnings compatibility
    adaptToHandedness: false,
    gradientMask: {
      maskColor: '#00000000',
      maskHeight: 1
    },
    // @SuppressWarnings compatibility
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
  @Prop prominent: boolean = false;
  @Prop active: boolean = false;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  @State private isPressed: boolean = false;
  @State private pressShadowType: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;
  action: () => void = () => {};
  private lastActionAt: number = 0;

  private shapeRadius(): number {
    return this.radiusValue >= 0 ? this.radiusValue : this.heightValue / 2;
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

  private resolvedFontColor(): ResourceColor {
    return fnFloatingButtonActiveFontColor(this.active, this.prominent, this.fontColorValue);
  }

  private resolvedLightColor(): ResourceColor {
    return fnFloatingButtonActiveLightColor(this.active, this.lightColorValue);
  }

  private resolvedBorderColor(): ResourceColor {
    return this.active ? FN_FLOATING_BUTTON_ACTIVE_BORDER_COLOR : $r('app.color.immersive_panel_border');
  }

  private onPressTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.isPressed = true;
      this.pressShadowType = hdsEffect.PressShadowType.BLEND_WHITE;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.isPressed = false;
      this.pressShadowType = hdsEffect.PressShadowType.NONE;
    }
  }

  @Builder
  private glassLayer() {
    if (this.shouldUseHds()) {
      // 官方 FAQ：不透明底/渐变/自定义阴影会盖住沉浸材质；与系统 Menu 一样走透明 + ULTRA_THICK
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .borderRadius(this.shapeRadius())
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
    } else {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.resolvedLightColor())
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect())
        .linearGradient(fnLiquidGlassGradient(false, this.isPressed, this.active))
        .borderRadius(this.shapeRadius())
        .borderWidth(1)
        .borderColor(this.resolvedBorderColor())
        .shadow({ radius: 12, color: '#18000000', offsetX: 0, offsetY: 4 })
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private labelContent() {
    Row() {
      Text(this.text)
        .fontSize(this.fontSizeValue)
        .fontWeight(this.active || this.prominent ? FontWeight.Bold : this.fontWeightValue)
        .fontColor(this.resolvedFontColor())
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
      this.glassLayer()
      this.labelContent()
    }
    .width(this.widthValue)
    .height(this.heightValue)
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(this.pressShadowType)
      .buildEffect())
    .onTouch((event: TouchEvent): void => {
      this.onPressTouch(event);
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
  @Prop active: boolean = false;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  @State private isPressed: boolean = false;
  @State private pressShadowType: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;
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

  private resolvedFontColor(): ResourceColor {
    return fnFloatingButtonActiveFontColor(this.active, false, this.fontColorValue);
  }

  private resolvedLightColor(): ResourceColor {
    return fnFloatingButtonActiveLightColor(this.active, this.lightColorValue);
  }

  private resolvedBorderColor(): ResourceColor {
    return this.active ? FN_FLOATING_BUTTON_ACTIVE_BORDER_COLOR : $r('app.color.immersive_panel_border');
  }

  private onPressTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.isPressed = true;
      this.pressShadowType = hdsEffect.PressShadowType.BLEND_WHITE;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.isPressed = false;
      this.pressShadowType = hdsEffect.PressShadowType.NONE;
    }
  }

  @Builder
  private glassLayer() {
    if (this.shouldUseHds()) {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .borderRadius(this.shapeRadius())
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
    } else {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.resolvedLightColor())
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect())
        .linearGradient(fnLiquidGlassGradient(false, this.isPressed, this.active))
        .borderRadius(this.shapeRadius())
        .borderWidth(1)
        .borderColor(this.resolvedBorderColor())
        .shadow({ radius: 12, color: '#18000000', offsetX: 0, offsetY: 4 })
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private symbolContent() {
    Row() {
      SymbolGlyph(this.symbol)
        .fontSize(this.fontSizeValue)
        .fontColor([this.resolvedFontColor()])
    }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      this.glassLayer()
      this.symbolContent()
    }
    .width(this.widthValue)
    .height(this.heightValue)
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(this.pressShadowType)
      .buildEffect())
    .onTouch((event: TouchEvent): void => {
      this.onPressTouch(event);
    })
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
  private glassLayer() {
    if (this.shouldUseHds()) {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .borderRadius(this.shapeRadius())
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
    } else {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.lightColorValue)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect())
        .linearGradient(fnLiquidGlassGradient(false))
        .borderRadius(this.shapeRadius())
        .borderWidth(1)
        .borderColor($r('app.color.immersive_panel_border'))
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
    }
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
      this.glassLayer()
      this.labelContent()
    }
    .width(this.widthValue)
    .height(this.heightValue)
    .hitTestBehavior(HitTestMode.None)
  }
}

export function fnLiquidGlassGradient(
  strong: boolean = false,
  pressed: boolean = false,
  active: boolean = false
): LinearGradientOptions {
  return {
    angle: pressed ? 118 : 132,
    colors: [
      [active ? '#A8D4E8FF' : (strong ? '#B8FFFFFF' : '#82FFFFFF'), 0.00],
      [pressed ? '#58FFFFFF' : (active ? '#664A8BFF' : (strong ? '#3DFFFFFF' : '#26FFFFFF')), 0.22],
      [active ? '#334A8BFF' : '#12FFFFFF', 0.46],
      [pressed ? '#34FFFFFF' : '#18FFFFFF', 0.72],
      ['#00FFFFFF', 1.00]
    ]
  };
}

@Component
export struct FnFloatingTopPillButton {
  @Prop text: ResourceStr = '';
  @Prop prominent: boolean = false;
  @Prop active: boolean = false;
  action: () => void = () => {};

  build() {
    FnHdsPillButton({
      text: this.text,
      widthValue: FN_FLOATING_TOP_PILL_MIN_WIDTH_VP,
      heightValue: FN_FLOATING_TOP_CONTROL_SIZE_VP,
      radiusValue: FN_FLOATING_TOP_CONTROL_RADIUS_VP,
      fontSizeValue: GALLERY_TOP_BAR_BUTTON_FONT_VP,
      fontColorValue: $r('app.color.button_secondary_fg'),
      prominent: this.prominent,
      active: this.active,
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
      fontColorValue: this.fontColor,
      active: this.active,
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
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  onBack: (() => void) | undefined = undefined;
  onRightClick: (() => void) | undefined = undefined;

  private invokeBack(): void {
    if (this.onBack !== undefined) {
      this.onBack();
      return;
    }
    this.getUIContext().getRouter().back();
  }

  private invokeRight(): void {
    if (this.onRightClick !== undefined) {
      this.onRightClick();
    }
  }

  build() {
    Row() {
      Row() {
        FnFloatingTopPillButton({
          text: this.backText,
          action: (): void => {
            this.invokeBack();
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
          FnFloatingTopPillButton({
            text: this.rightText,
            action: (): void => {
              this.invokeRight();
            }
          })
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
