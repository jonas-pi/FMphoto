import { window } from '@kit.ArkUI';

/** 与 entry 模块 color.json 里 start_window_background 保持一致 */
export const FN_START_WINDOW_BG_LIGHT: string = '#FFF4F7FB';
export const FN_START_WINDOW_BG_DARK: string = '#FF000000';

export function fnIsDarkColorMode(colorMode: number | undefined): boolean {
  return colorMode === 1;
}

export function fnSplashWindowBackgroundHex(isDark: boolean): string {
  return isDark ? FN_START_WINDOW_BG_DARK : FN_START_WINDOW_BG_LIGHT;
}

export function fnApplySplashWindowBackground(mainWindow: window.Window, isDark: boolean): void {
  try {
    mainWindow.setWindowBackgroundColor(fnSplashWindowBackgroundHex(isDark));
  } catch (_e) {
  }
}

/**
 * 与系统 StartWindow 对齐：全屏、隐藏系统栏，图标按整窗几何中心绘制（非安全区内居中）。
 * @param immersive true=启动闪屏；false=隐私弹窗等需显示状态栏的场景
 */
export function fnApplySplashWindowChrome(mainWindow: window.Window, isDark: boolean, immersive: boolean): void {
  fnApplySplashWindowBackground(mainWindow, isDark);
  try {
    if (immersive) {
      mainWindow.setWindowLayoutFullScreen(true).catch((_e: Error): void => {
      });
      fnSetSplashSystemBarsVisible(mainWindow, false);
    } else {
      fnSetSplashSystemBarsVisible(mainWindow, true);
      const content = isDark ? '#FFFFFFFF' : '#FF000000';
      const bg = fnSplashWindowBackgroundHex(isDark);
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: bg,
        navigationBarColor: bg,
        statusBarContentColor: content,
        navigationBarContentColor: content
      }).catch((_e: Error): void => {
      });
    }
  } catch (_e) {
  }
}

/** API 12+：替代已废弃的 setWindowSystemBarEnable */
function fnSetSplashSystemBarsVisible(mainWindow: window.Window, visible: boolean): void {
  mainWindow.setSpecificSystemBarEnabled('status', visible).catch((_e: Error): void => {
  });
  mainWindow.setSpecificSystemBarEnabled('navigationIndicator', visible).catch((_e: Error): void => {
  });
}
