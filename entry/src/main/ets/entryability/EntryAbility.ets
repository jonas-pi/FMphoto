import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BackgroundKeepAliveController } from '../background/BackgroundKeepAliveController';
import {
  fnApplySplashWindowChrome
} from '../common/FnSplashTheme';
import {
  fnLoadImmersiveLightPreference,
  fnSetImmersiveLightEnabled
} from '../common/FnImmersiveSettings';

/** 应用日志域（与网络模块 FnHttp 同域便于筛选，取值需在 0x0～0xFFFF） */
const DOMAIN = 0xFF00;
const LOG_TAG = 'FNOSClient';
interface AbilityConfigUpdate {
  colorMode?: number;
}

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onCreate');
  }

  /** 系统深浅色模式切换时同步更新 AppStorage，使所有 @StorageProp('colorMode') 组件立即响应 */
  onConfigurationUpdate(newConfig: AbilityConfigUpdate): void {
    try {
      const dark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.set<number>('colorMode', dark ? 1 : 0);
      if (this.mainWindow !== null) {
        fnApplySplashWindowChrome(this.mainWindow, dark, true);
      }
      hilog.info(DOMAIN, LOG_TAG, 'onConfigurationUpdate colorMode=%{public}d', dark ? 1 : 0);
    } catch (_e) {}
  }

  onDestroy(): void {
    BackgroundKeepAliveController.onAbilityForegroundOrDestroy(this.context);
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onWindowStageCreate');

    // 在加载页面内容前初始化 colorMode，确保第一帧即可正确读取深浅色模式
    let dark = false;
    try {
      dark = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.setOrCreate<number>('colorMode', dark ? 1 : 0);
      fnSetImmersiveLightEnabled(true);
      void fnLoadImmersiveLightPreference(this.context);
      hilog.info(DOMAIN, LOG_TAG, 'initial colorMode=%{public}d', dark ? 1 : 0);
    } catch (_e) {}

    // 窗口背景与 startWindowBackground 一致，避免 StartWindow → 首帧之间露色
    windowStage.getMainWindow().then((mainWindow: window.Window): void => {
      this.mainWindow = mainWindow;
      // 首帧前即全屏无系统栏，与 StartWindow 居中基准一致
      fnApplySplashWindowChrome(mainWindow, dark, true);
    }).catch((_e: Error): void => {
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, LOG_TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, LOG_TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    this.mainWindow = null;
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    BackgroundKeepAliveController.onAbilityForegroundOrDestroy(this.context);
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onBackground');
    // 官方 Background Tasks Kit：短时挂起宽限 + 数据传输类长时任务（见 module backgroundModes）
    BackgroundKeepAliveController.onAbilityBackground(this.context);
  }
}
