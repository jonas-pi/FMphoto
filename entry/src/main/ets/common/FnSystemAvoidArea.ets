import { display, UIContext, window } from '@kit.ArkUI';

/** 系统状态栏高度（vp），供各页 @StorageProp 共用 */
export const FN_SYSTEM_TOP_INSET_VP_KEY: string = 'fnSystemTopInsetVp';
/** 系统导航条/手势条高度（vp） */
export const FN_SYSTEM_BOTTOM_INSET_VP_KEY: string = 'fnSystemBottomInsetVp';
/** 横屏时左侧系统栏/挖孔宽度（vp） */
export const FN_SYSTEM_LEFT_INSET_VP_KEY: string = 'fnSystemLeftInsetVp';
/** 横屏时右侧系统栏/挖孔宽度（vp） */
export const FN_SYSTEM_RIGHT_INSET_VP_KEY: string = 'fnSystemRightInsetVp';

interface FnAvoidAreaChangeInfo {
  type: window.AvoidAreaType;
  area: window.AvoidArea;
}

let boundWindow: window.Window | null = null;
let boundCallback: ((info: FnAvoidAreaChangeInfo) => void) | null = null;
/** TYPE_SYSTEM 顶部高度（px），与挖孔区取较大值后写入 AppStorage */
let lastSystemTopPx: number = 0;
let lastSystemBottomPx: number = 0;
let lastSystemLeftPx: number = 0;
let lastSystemRightPx: number = 0;
/** TYPE_CUTOUT 顶部高度（px）。官方：摄像头挖孔默认不在避让区，需主动合并。 */
let lastCutoutTopPx: number = 0;
let lastCutoutLeftPx: number = 0;
let lastCutoutRightPx: number = 0;

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

function fnPublishTopBottomInsets(uiContext: UIContext | undefined): void {
  // 官方 immersive-window-feature：状态栏与挖孔顶边取较大值，避免前置摄像头挡住顶部内容
  fnWriteInsetVp(
    FN_SYSTEM_TOP_INSET_VP_KEY,
    fnPxToVp(Math.max(lastSystemTopPx, lastCutoutTopPx), uiContext)
  );
  // 底部避让在无导航条设备上可以为 0，需允许写回
  AppStorage.setOrCreate<number>(
    FN_SYSTEM_BOTTOM_INSET_VP_KEY,
    Math.max(0, fnPxToVp(lastSystemBottomPx, uiContext))
  );
}

function fnPublishSideInsets(uiContext: UIContext | undefined): void {
  // 横屏旋转后左右必须允许写回 0，不能沿用竖屏残留
  AppStorage.setOrCreate<number>(
    FN_SYSTEM_LEFT_INSET_VP_KEY,
    Math.max(0, fnPxToVp(Math.max(lastSystemLeftPx, lastCutoutLeftPx), uiContext))
  );
  AppStorage.setOrCreate<number>(
    FN_SYSTEM_RIGHT_INSET_VP_KEY,
    Math.max(0, fnPxToVp(Math.max(lastSystemRightPx, lastCutoutRightPx), uiContext))
  );
}

function fnApplySystemAvoidArea(area: window.AvoidArea, uiContext: UIContext | undefined): void {
  lastSystemTopPx = Math.max(0, area.topRect.height);
  lastSystemBottomPx = Math.max(0, area.bottomRect.height);
  lastSystemLeftPx = Math.max(0, area.leftRect.width);
  lastSystemRightPx = Math.max(0, area.rightRect.width);
  fnPublishTopBottomInsets(uiContext);
  fnPublishSideInsets(uiContext);
}

function fnApplyCutoutAvoidArea(area: window.AvoidArea, uiContext: UIContext | undefined): void {
  lastCutoutTopPx = Math.max(0, area.topRect.height);
  lastCutoutLeftPx = Math.max(0, area.leftRect.width);
  lastCutoutRightPx = Math.max(0, area.rightRect.width);
  fnPublishTopBottomInsets(uiContext);
  fnPublishSideInsets(uiContext);
}

/** 读取当前系统避让区并写入 AppStorage。 */
export function fnPublishSystemAvoidArea(win: window.Window, uiContext: UIContext | undefined = undefined): void {
  try {
    const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    fnApplySystemAvoidArea(systemArea, uiContext);
  } catch (_e) {
  }
  try {
    // 官方 ts-universal-attributes-expand-safe-area：未配 avoid_cutout 时页面默认不避让挖孔
    const cutoutArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
    fnApplyCutoutAvoidArea(cutoutArea, uiContext);
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
  if (AppStorage.get<number>(FN_SYSTEM_LEFT_INSET_VP_KEY) === undefined) {
    AppStorage.setOrCreate<number>(FN_SYSTEM_LEFT_INSET_VP_KEY, 0);
  }
  if (AppStorage.get<number>(FN_SYSTEM_RIGHT_INSET_VP_KEY) === undefined) {
    AppStorage.setOrCreate<number>(FN_SYSTEM_RIGHT_INSET_VP_KEY, 0);
  }
  fnUnbindSystemAvoidArea();
  fnPublishSystemAvoidArea(win);
  boundCallback = (info: FnAvoidAreaChangeInfo): void => {
    if (info.type === window.AvoidAreaType.TYPE_SYSTEM) {
      fnApplySystemAvoidArea(info.area, undefined);
      return;
    }
    if (info.type === window.AvoidAreaType.TYPE_CUTOUT) {
      fnApplyCutoutAvoidArea(info.area, undefined);
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
