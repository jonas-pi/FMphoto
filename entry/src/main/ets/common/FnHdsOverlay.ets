/**
 * 弹出层走华为官方能力：
 * - 半模态 bindSheet：Transparent + systemMaterial（官方沉浸光感）
 * - 菜单：HarmonyOS 7 / API 26 默认改为透明模糊；高端机 ImmersiveMaterial
 *   还会把 backgroundColor 盖成透明，视频 XComponent 采空即全透明。
 *   官方适配：Material.empty 关掉该菜单沉浸材质，再显式设色 + BlurStyle.NONE。
 */
import { uiMaterial } from '@kit.ArkUI';
import { fnCurrentSdkApiVersion } from './FnImmersiveSettings';

/** ArkUI 组件级 systemMaterial（bindSheet / bindMenu）起始 API */
const FN_ARKUI_SYSTEM_MATERIAL_API: number = 26;

let cachedSheetMaterial: uiMaterial.Material | undefined = undefined;

function fnCanUseArkUiSystemMaterial(): boolean {
  return fnCurrentSdkApiVersion() >= FN_ARKUI_SYSTEM_MATERIAL_API;
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
    // @SuppressWarnings compatibility
    cachedSheetMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THICK
    });
  }
  return cachedSheetMaterial;
}

/**
 * 关掉菜单上的沉浸材质。ENABLE / 系统沉浸光感开启后，材质优先级高于开发者背景色。
 * 文档：arkts-apis-uimaterial Material.empty；ContextMenuOptions.systemMaterial 26.0.0。
 */
export function fnHdsMenuSystemMaterial(): uiMaterial.Material | undefined {
  if (!fnCanUseArkUiSystemMaterial()) {
    return undefined;
  }
  return uiMaterial.Material.empty;
}

/**
 * cl.arkui.1：统一渲染下 bindMenu / bindContextMenu 默认透明 + 模糊。
 * 要实底须显式 backgroundColor + BlurStyle.NONE；API 26+ 再设 Material.empty，
 * 避免高端机把背景色恢复为透明。
 */
function fnHdsFillMenuBackdrop(options: ContextMenuOptions): void {
  options.backgroundBlurStyle = BlurStyle.NONE;
  options.backgroundColor = $r('app.color.gallery_menu_backdrop');
  const material = fnHdsMenuSystemMaterial();
  if (material !== undefined) {
    // @SuppressWarnings compatibility
    options.systemMaterial = material;
  }
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
  const material = fnHdsSheetSystemMaterial();
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
 * 内容可滚动的底部半模态：官方 arkts-sheet-page 用 SheetSize 档位，不写百分比高度。
 * 默认 MEDIUM，可上滑 LARGE；List/Scroll 需配 nestedScroll PARENT_FIRST / SELF_FIRST。
 */
export function fnHdsMediumDetentSheetOptions(title: ResourceStr, onDisappear: () => void): SheetOptions {
  const options = fnHdsSheetOptions(title, onDisappear, SheetSize.MEDIUM);
  options.detents = [SheetSize.MEDIUM, SheetSize.LARGE];
  return options;
}

/**
 * 图库详情半模态：官方 BOTTOM + MEDIUM/LARGE 档位跟手。
 * 底部弹窗默认不允许下层交互、显示蒙层；点击剩余区即点击遮罩，立刻离场。
 * 不要 enableOutsideInteractive=true：会关掉蒙层，点击落到预览还要等双击识别，收回会慢半拍。
 * 蒙层透明，剩余区照片仍由半模态叠层遮挡，不额外压暗。
 * 文档：ts-universal-attributes-sheet-transition（enableOutsideInteractive / maskColor）
 */
export function fnHdsGalleryDetailsSheetOptions(
  title: ResourceStr,
  onDisappear: () => void,
  onHeightDidChange: (heightPx: number) => void
): SheetOptions {
  const options = fnHdsSheetOptions(title, onDisappear, SheetSize.MEDIUM);
  options.detents = [SheetSize.MEDIUM, SheetSize.LARGE];
  options.maskColor = Color.Transparent;
  options.onHeightDidChange = onHeightDidChange;
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
  fnHdsFillMenuBackdrop(options);
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
  fnHdsFillMenuBackdrop(options);
  return options;
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
        Row() {
          Text(label)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          if (this.selectedIndex === idx) {
            SymbolGlyph($r('sys.symbol.checkmark'))
              .fontSize(18)
              .fontColor([$r('sys.color.ohos_id_color_activated')])
          }
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .onClick((): void => {
          this.onSelect(idx);
        })
      }, (label: string, idx: number) => `hds_choice_${idx}_${label}`)
    }
    .width('100%')
    .padding({ top: 4, bottom: 16 })
    .backgroundColor(Color.Transparent)
  }
}
