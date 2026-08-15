import { display, UIContext, window } from '@kit.ArkUI';

/** 系统状态栏高度（vp），供各页 @StorageProp 共用 */
export const FN_SYSTEM_TOP_INSET_VP_KEY: string = 'fnSystemTopInsetVp';
/** 系统导航条/手势条高度（vp） */
export const FN_SYSTEM_BOTTOM_INSET_VP_KEY: string = 'fnSystemBottomInsetVp';

interface FnAvoidAreaChangeInfo {
  type: window.AvoidAreaType;
  area: window.AvoidArea;
}

let boundWindow: window.Window | null = null;
let boundCallback: ((info: FnAvoidAreaChangeInfo) => void) | null = null;

function fnPxToVp(px: number, uiContext: UIContext | undefined): number {
  if (uiContext !== undefined) {
    try {
      return uiContext.px2vp(px);
    } catch (_e) {
    }
  }
  try {
    const density = display.getDefaultDisplaySync().densityPixels;
    if (density > 0) {
      return px / density;
    }
  } catch (_e) {
  }
  return px;
}

/** 主题切换瞬间避让区常为 0，已有有效值时不要清零。 */
function fnWriteInsetVp(key: string, value: number): void {
  const next = Math.max(0, value);
  if (next > 0) {
    AppStorage.setOrCreate<number>(key, next);
    return;
  }
  const prev = AppStorage.get<number>(key);
  if (prev === undefined) {
    AppStorage.setOrCreate<number>(key, 0);
  }
}

function fnApplySystemAvoidArea(area: window.AvoidArea, uiContext: UIContext | undefined): void {
  fnWriteInsetVp(FN_SYSTEM_TOP_INSET_VP_KEY, fnPxToVp(area.topRect.height, uiContext));
  // 底部避让在无导航条设备上可以为 0，需允许写回
  AppStorage.setOrCreate<number>(
    FN_SYSTEM_BOTTOM_INSET_VP_KEY,
    Math.max(0, fnPxToVp(area.bottomRect.height, uiContext))
  );
}

/** 读取当前系统避让区并写入 AppStorage。 */
export function fnPublishSystemAvoidArea(win: window.Window, uiContext: UIContext | undefined = undefined): void {
  try {
    const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    fnApplySystemAvoidArea(area, uiContext);
  } catch (_e) {
  }
}

/** 主窗口创建后订阅避让区变化，主题重绘后也能收回真实 inset。 */
export function fnBindSystemAvoidArea(win: window.Window): void {
  if (AppStorage.get<number>(FN_SYSTEM_TOP_INSET_VP_KEY) === undefined) {
    AppStorage.setOrCreate<number>(FN_SYSTEM_TOP_INSET_VP_KEY, 0);
  }
  if (AppStorage.get<number>(FN_SYSTEM_BOTTOM_INSET_VP_KEY) === undefined) {
    AppStorage.setOrCreate<number>(FN_SYSTEM_BOTTOM_INSET_VP_KEY, 0);
  }
  fnUnbindSystemAvoidArea();
  fnPublishSystemAvoidArea(win);
  boundCallback = (info: FnAvoidAreaChangeInfo): void => {
    if (info.type === window.AvoidAreaType.TYPE_SYSTEM) {
      fnApplySystemAvoidArea(info.area, undefined);
    }
  };
  try {
    win.on('avoidAreaChange', boundCallback);
    boundWindow = win;
  } catch (_e) {
    boundCallback = null;
    boundWindow = null;
  }
}

export function fnUnbindSystemAvoidArea(): void {
  if (boundWindow !== null && boundCallback !== null) {
    try {
      boundWindow.off('avoidAreaChange', boundCallback);
    } catch (_e) {
    }
  }
  boundWindow = null;
  boundCallback = null;
}
