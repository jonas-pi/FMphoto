import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BackgroundKeepAliveController } from '../background/BackgroundKeepAliveController';

/** 应用日志域（与网络模块 FnHttp 同域便于筛选，取值需在 0x0～0xFFFF） */
const DOMAIN = 0xFF00;
const LOG_TAG = 'FNOSClient';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    BackgroundKeepAliveController.onAbilityForegroundOrDestroy(this.context);
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, LOG_TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, LOG_TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
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