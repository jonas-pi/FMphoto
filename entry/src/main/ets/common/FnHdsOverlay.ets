/**
 * 弹出层走华为官方能力，不要自绘玻璃底：
 * - 半模态 bindSheet：backgroundColor Transparent + systemMaterial（官方沉浸光感示例）
 * - 菜单 bindMenu / bindContextMenu + Menu / MenuItem（菜单默认支持沉浸光感）
 * - 有 systemMaterial 时不要再叠 blurStyle / 不透明底，否则材质会被盖住
 */
import { uiMaterial } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';
import {
  fnCanUseHdsImmersive,
  fnCurrentSdkApiVersion,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from './FnImmersiveSettings';

/** ArkUI 组件级 systemMaterial（bindSheet / bindMenu）起始 API */
const FN_ARKUI_SYSTEM_MATERIAL_API: number = 26;

let cachedSheetMaterial: uiMaterial.Material | undefined = undefined;
let cachedMenuMaterial: uiMaterial.Material | undefined = undefined;
let cachedInputMaterial: uiMaterial.Material | undefined = undefined;
let cachedLoginCardMaterial: uiMaterial.Material | undefined = undefined;
let cachedLoginInputMaterial: uiMaterial.Material | undefined = undefined;
let cachedLoginSecondaryButtonMaterial: uiMaterial.Material | undefined = undefined;
let cachedSegmentMaterial: uiMaterial.Material | undefined = undefined;

function fnCanUseArkUiSystemMaterial(): boolean {
  return fnCurrentSdkApiVersion() >= FN_ARKUI_SYSTEM_MATERIAL_API;
}

export function fnArkUiSupportsSystemMaterial(): boolean {
  return fnCanUseArkUiSystemMaterial();
}

function fnCreateInteractiveImmersiveMaterial(
  style: uiMaterial.ImmersiveStyle,
  materialColor?: ResourceColor
): uiMaterial.Material {
  // @SuppressWarnings compatibility
  const options: uiMaterial.ImmersiveOptions = {
    style: style,
    interactive: true,
    applyShadow: true,
    lightEffect: { color: undefined }
  };
  if (materialColor !== undefined) {
    options.materialColor = materialColor;
  }
  return new uiMaterial.ImmersiveMaterial(options);
}

export function fnHdsSheetBackgroundColor(_canUseHds: boolean): ResourceColor {
  return Color.Transparent;
}

/**
 * 仅 API 26 以下回退：官方旧示例用 BlurStyle.Thick。
 * API 26+ 必须返回 undefined，避免模糊盖住 systemMaterial。
 */
export function fnHdsSheetBlurStyle(): BlurStyle | undefined {
  if (fnCanUseArkUiSystemMaterial()) {
    return undefined;
  }
  return BlurStyle.Thick;
}

/** 官方 bindSheet 示例：ULTRA_THICK + 透明底 */
export function fnHdsSheetSystemMaterial(): uiMaterial.Material | undefined {
  if (!fnCanUseArkUiSystemMaterial()) {
    return undefined;
  }
  if (cachedSheetMaterial === undefined) {
    // 官方 bindSheet 示例用 ULTRA_THICK；补 lightEffect 才有触摸流光（沉浸光感）
    // @SuppressWarnings compatibility
    cachedSheetMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THICK,
      lightEffect: { color: undefined }
    });
  }
  return cachedSheetMaterial;
}

/** 官方沉浸光感文档：搜索框 / 输入框适用 THIN + 按压光效 */
export function fnHdsInputSystemMaterial(): uiMaterial.Material | undefined {
  if (!fnCanUseArkUiSystemMaterial()) {
    return undefined;
  }
  if (cachedInputMaterial === undefined) {
    cachedInputMaterial = fnCreateInteractiveImmersiveMaterial(uiMaterial.ImmersiveStyle.THIN);
  }
  return cachedInputMaterial;
}

/** 登录输入框：THIN + 实色底，官方搜索/输入框推荐样式 */
export function fnHdsLoginInputSystemMaterial(): uiMaterial.Material | undefined {
  if (!fnCanUseArkUiSystemMaterial()) {
    return undefined;
  }
  if (cachedLoginInputMaterial === undefined) {
    cachedLoginInputMaterial = fnCreateInteractiveImmersiveMaterial(
      uiMaterial.ImmersiveStyle.THIN,
      $r('app.color.login_input_fill')
    );
  }
  return cachedLoginInputMaterial;
}

/** 登录前景整块：ULTRA_THICK，不赋不透明色，让材质滤镜模糊并折射背后蓝圆 */
export function fnHdsLoginCardSystemMaterial(): uiMaterial.Material | undefined {
  if (!fnCanUseArkUiSystemMaterial()) {
    return undefined;
  }
  if (cachedLoginCardMaterial === undefined) {
    cachedLoginCardMaterial = fnCreateInteractiveImmersiveMaterial(
      uiMaterial.ImmersiveStyle.ULTRA_THICK
    );
  }
  return cachedLoginCardMaterial;
}

/** 登录次按钮：与输入框同系实底 + 按压形变/光感 */
export function fnHdsLoginSecondaryButtonSystemMaterial(): uiMaterial.Material | undefined {
  if (!fnCanUseArkUiSystemMaterial()) {
    return undefined;
  }
  if (cachedLoginSecondaryButtonMaterial === undefined) {
    cachedLoginSecondaryButtonMaterial = fnCreateInteractiveImmersiveMaterial(
      uiMaterial.ImmersiveStyle.REGULAR,
      $r('app.color.login_input_fill')
    );
  }
  return cachedLoginSecondaryButtonMaterial;
}

/** 分段选择容器：REGULAR + 与输入框同系实色底 */
export function fnHdsSegmentSystemMaterial(): uiMaterial.Material | undefined {
  if (!fnCanUseArkUiSystemMaterial()) {
    return undefined;
  }
  if (cachedSegmentMaterial === undefined) {
    cachedSegmentMaterial = fnCreateInteractiveImmersiveMaterial(
      uiMaterial.ImmersiveStyle.REGULAR,
      $r('app.color.login_input_fill')
    );
  }
  return cachedSegmentMaterial;
}

/** 官方 bindMenu 示例：THICK */
export function fnHdsMenuSystemMaterial(): uiMaterial.Material | undefined {
  if (!fnCanUseArkUiSystemMaterial()) {
    return undefined;
  }
  if (cachedMenuMaterial === undefined) {
    // @SuppressWarnings compatibility
    cachedMenuMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THICK
    });
  }
  return cachedMenuMaterial;
}

export function fnHdsSheetOptions(
  title: ResourceStr,
  onDisappear: () => void,
  height: SheetSize | Length = SheetSize.FIT_CONTENT
): SheetOptions {
  const options: SheetOptions = {
    height: height,
    title: { title: title },
    showClose: true,
    dragBar: true,
    preferType: SheetType.BOTTOM,
    backgroundColor: Color.Transparent,
    onDisappear: onDisappear
  };
  const material = fnCanUseHdsImmersive() ? fnHdsSheetSystemMaterial() : undefined;
  if (material !== undefined) {
    // @SuppressWarnings compatibility
    options.systemMaterial = material;
  } else {
    options.blurStyle = BlurStyle.Thick;
  }
  return options;
}

export function fnHdsFitContentSheetOptions(title: ResourceStr, onDisappear: () => void): SheetOptions {
  return fnHdsSheetOptions(title, onDisappear, SheetSize.FIT_CONTENT);
}

/**
 * 固定中等高度半模态：不上滑换挡，无拖拽条；内容区自行滚动。
 */
export function fnHdsFixedMediumSheetOptions(title: ResourceStr, onDisappear: () => void): SheetOptions {
  const options = fnHdsSheetOptions(title, onDisappear, SheetSize.MEDIUM);
  options.dragBar = false;
  return options;
}

/**
 * 内容可滚动的底部半模态：官方 arkts-sheet-page 用 SheetSize 档位，不写百分比高度。
 * 默认 MEDIUM，可上滑 LARGE；List/Scroll 需配 nestedScroll PARENT_FIRST / SELF_FIRST。
 */
export function fnHdsMediumDetentSheetOptions(title: ResourceStr, onDisappear: () => void): SheetOptions {
  const options = fnHdsSheetOptions(title, onDisappear, SheetSize.MEDIUM);
  options.detents = [SheetSize.MEDIUM, SheetSize.LARGE];
  return options;
}

/**
 * SaveButton 专用半模态：实底、无模糊/材质，避免安全控件授权失败。
 */
export function fnHdsSaveButtonSheetOptions(title: string, onDisappear: () => void): SheetOptions {
  return {
    height: SheetSize.FIT_CONTENT,
    title: {
      title: title,
      subtitle: '写入系统图库后可长按播放'
    },
    showClose: true,
    dragBar: true,
    preferType: SheetType.BOTTOM,
    backgroundColor: $r('app.color.page_background'),
    onDisappear: onDisappear
  };
}

/** bindMenu.keyboardAvoidMode 起始 API（官方示例 20） */
const FN_MENU_KEYBOARD_AVOID_API: number = 23;

export function fnHdsBindMenuOptions(
  placement: Placement,
  onDisappear?: () => void,
  onAppear?: () => void
): MenuOptions {
  const options: MenuOptions = {
    placement: placement
  };
  if (onDisappear !== undefined) {
    options.onDisappear = onDisappear;
  }
  if (onAppear !== undefined) {
    options.onAppear = onAppear;
  }
  const material = fnHdsMenuSystemMaterial();
  if (material !== undefined) {
    // @SuppressWarnings compatibility
    options.systemMaterial = material;
  }
  // 官方：输入法弹出时菜单与软键盘会互相顶布局。先收键盘再弹菜单，菜单本身不避让，
  // 避免 TRANSLATE_AND_RESIZE 与键盘收起动画抢位移。
  // 文档：ts-universal-attributes-menu 示例 20；bpta-keyboard-layout-adapt
  if (fnCurrentSdkApiVersion() >= FN_MENU_KEYBOARD_AVOID_API) {
    // @SuppressWarnings compatibility
    options.keyboardAvoidMode = MenuKeyboardAvoidMode.NONE;
  }
  return options;
}

export function fnHdsBindContextMenuOptions(
  placement: Placement,
  onAppear?: () => void,
  onDisappear?: () => void
): ContextMenuOptions {
  const options: ContextMenuOptions = {
    placement: placement
  };
  if (onAppear !== undefined) {
    options.onAppear = onAppear;
  }
  if (onDisappear !== undefined) {
    options.onDisappear = onDisappear;
  }
  const material = fnHdsMenuSystemMaterial();
  if (material !== undefined) {
    // @SuppressWarnings compatibility
    options.systemMaterial = material;
  }
  return options;
}

/**
 * 半模态选项行：文字居中；开启沉浸光感时走官方按压流光。
 */
@Component
struct FnHdsChoiceSheetItem {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  onSelect: () => void = (): void => {};
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  @State private pressShadowType: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;

  private shouldUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private onPressTouch(event: TouchEvent): void {
    if (!this.shouldUseHds()) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.pressShadowType = hdsEffect.PressShadowType.BLEND_WHITE;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.pressShadowType = hdsEffect.PressShadowType.NONE;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.label)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (this.selected) {
        Row() {
          Blank()
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(18)
            .fontColor([$r('sys.color.ohos_id_color_activated')])
        }
        .width('100%')
        .height('100%')
        .padding({ right: 4 })
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.Transparent)
    .onTouch((event: TouchEvent): void => {
      this.onPressTouch(event);
    })
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(this.pressShadowType)
      .buildEffect())
    .onClick((): void => {
      this.onSelect();
    })
  }
}

/**
 * 半模态选项列表。内容保持透明，材质由 bindSheet.systemMaterial 提供。
 */
@Component
export struct FnHdsChoiceSheet {
  @Prop buttons: string[] = [];
  @Prop selectedIndex: number = -1;

  onSelect: (index: number) => void = (_: number): void => {};

  build() {
    Column() {
      ForEach(this.buttons, (label: string, idx: number) => {
        FnHdsChoiceSheetItem({
          label: label,
          selected: this.selectedIndex === idx,
          onSelect: (): void => {
            this.onSelect(idx);
          }
        })
      }, (label: string, idx: number) => `hds_choice_${idx}_${label}`)
    }
    .width('100%')
    .padding({ top: 4, bottom: 16 })
    .backgroundColor(Color.Transparent)
  }
}
