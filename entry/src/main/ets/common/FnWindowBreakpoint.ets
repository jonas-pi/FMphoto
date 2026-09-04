/**
 * 系统横向断点：Ability 监听窗口尺寸，页面用 @StorageProp 消费。
 * 键名与鸿蒙多设备适配文档一致（currentWidthBreakpoint / screenHeightVp）。
 */
import { window } from '@kit.ArkUI';

export const FN_WINDOW_WIDTH_BP_KEY: string = 'currentWidthBreakpoint';
export const FN_WINDOW_HEIGHT_VP_KEY: string = 'screenHeightVp';

const DEBOUNCE_MS: number = 150;

let boundWindow: window.Window | null = null;
let boundCallback: ((size: window.Size) => void) | null = null;
let debounceTimer: number = -1;

export function fnEnsureWindowBreakpointStorage(): void {
  if (AppStorage.get<number>(FN_WINDOW_WIDTH_BP_KEY) === undefined) {
    AppStorage.setOrCreate<number>(FN_WINDOW_WIDTH_BP_KEY, WidthBreakpoint.WIDTH_SM);
  }
  if (AppStorage.get<number>(FN_WINDOW_HEIGHT_VP_KEY) === undefined) {
    AppStorage.setOrCreate<number>(FN_WINDOW_HEIGHT_VP_KEY, 0);
  }
}

function fnPublishWindowBreakpoint(win: window.Window): void {
  try {
    const ui = win.getUIContext();
    const widthBp: WidthBreakpoint = ui.getWindowWidthBreakpoint();
    AppStorage.setOrCreate<number>(FN_WINDOW_WIDTH_BP_KEY, widthBp);
    const rect = win.getWindowProperties().windowRect;
    const heightVp: number = ui.px2vp(rect.height);
    AppStorage.setOrCreate<number>(FN_WINDOW_HEIGHT_VP_KEY, heightVp);
  } catch (_e) {
  }
}

function fnClearDebounceTimer(): void {
  if (debounceTimer >= 0) {
    clearTimeout(debounceTimer);
    debounceTimer = -1;
  }
}

export function fnBindWindowBreakpoint(win: window.Window): void {
  fnEnsureWindowBreakpointStorage();
  fnUnbindWindowBreakpoint();
  fnPublishWindowBreakpoint(win);
  boundCallback = (_size: window.Size): void => {
    fnClearDebounceTimer();
    debounceTimer = setTimeout((): void => {
      debounceTimer = -1;
      if (boundWindow !== null) {
        fnPublishWindowBreakpoint(boundWindow);
      }
    }, DEBOUNCE_MS);
  };
  try {
    win.on('windowSizeChange', boundCallback);
    boundWindow = win;
  } catch (_e) {
    boundCallback = null;
    boundWindow = null;
  }
}

export function fnUnbindWindowBreakpoint(): void {
  fnClearDebounceTimer();
  if (boundWindow !== null && boundCallback !== null) {
    try {
      boundWindow.off('windowSizeChange', boundCallback);
    } catch (_e) {
    }
  }
  boundWindow = null;
  boundCallback = null;
}

const FN_GRID_COLUMNS_MIN: number = 1;
const FN_GRID_COLUMNS_MAX: number = 8;

/** 分类/搜索/回收站等固定宫格：限制在合理列数内。 */
export function fnClampGridColumns(columns: number): number {
  const n = Math.floor(columns);
  if (n < FN_GRID_COLUMNS_MIN) {
    return 3;
  }
  if (n > FN_GRID_COLUMNS_MAX) {
    return FN_GRID_COLUMNS_MAX;
  }
  return n;
}

/** RESP-01：以直板机基线 N 列为起点，md=+1，lg/xl=+2。 */
export function fnAdaptiveGridColumns(baseColumns: number, widthBp: number): number {
  const base = Math.max(1, baseColumns);
  if (widthBp === WidthBreakpoint.WIDTH_LG || widthBp === WidthBreakpoint.WIDTH_XL) {
    return base + 2;
  }
  if (widthBp === WidthBreakpoint.WIDTH_MD) {
    return base + 1;
  }
  return base;
}

export function fnRepeatFrTemplate(columns: number): string {
  const n = Math.max(1, columns);
  let out = '1fr';
  for (let i = 1; i < n; i++) {
    out += ' 1fr';
  }
  return out;
}

export function fnGridColumnIndexes(columns: number): number[] {
  const n = Math.max(1, Math.floor(columns));
  const out: number[] = [];
  for (let i = 0; i < n; i++) {
    out.push(i);
  }
  return out;
}
