import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BackgroundKeepAliveController } from '../background/BackgroundKeepAliveController';
import { GalleryThumbDiskCache } from '../album/GalleryThumbDiskCache';
import { ensureGalleryThumbCacheEpochStorage } from '../album/GalleryThumbPersist';
import {
  applyGalleryMemoryLevel,
  applyGalleryPerfImageCache,
  ensureGalleryPerfProfile,
  refreshGalleryPerfProfile
} from '../album/GalleryPerfProfile';
import { trimThumbPixCache } from '../album/GalleryAlbumCommon';
import {
  fnApplySplashWindowBackground,
  fnApplySplashWindowChrome,
  fnRestoreAppSystemBars
} from '../common/FnSplashTheme';
import { fnBindSystemAvoidArea, fnPublishSystemAvoidArea, fnUnbindSystemAvoidArea } from '../common/FnSystemAvoidArea';
import { fnBindWindowBreakpoint, fnEnsureWindowBreakpointStorage, fnUnbindWindowBreakpoint } from '../common/FnWindowBreakpoint';
import {
  fnLoadImmersiveLightPreference,
  fnSetImmersiveLightEnabled
} from '../common/FnImmersiveSettings';
import { FnTransferQueueStore } from '../common/FnTransferQueueStore';
import { GalleryShareInbox } from '../album/share/GalleryShareInbox';
import { ensureStarted, scheduleCheck, stop } from '../network/LoginEndpointAutoSwitch';

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
    ensureGalleryPerfProfile();
    GalleryThumbDiskCache.init(this.context.cacheDir);
    ensureGalleryThumbCacheEpochStorage();
    FnTransferQueueStore.ensureStorage();
    GalleryShareInbox.ensureStorage();
    fnEnsureWindowBreakpointStorage();
    ensureStarted(this.context);
    void GalleryShareInbox.ingestWant(want);
  }

  /** 应用已在前台时再次被系统分享拉起 */
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    void GalleryShareInbox.ingestWant(want);
  }

  /** 系统深浅色模式切换时同步更新 AppStorage，使所有 @StorageProp('colorMode') 组件立即响应 */
  onConfigurationUpdate(newConfig: AbilityConfigUpdate): void {
    try {
      const dark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.set<number>('colorMode', dark ? 1 : 0);
      if (this.mainWindow !== null) {
        // 只换窗体底色并保证系统栏仍可见；切勿再套启动闪屏的隐藏状态栏逻辑
        fnApplySplashWindowBackground(this.mainWindow, dark);
        fnRestoreAppSystemBars(this.mainWindow);
        fnPublishSystemAvoidArea(this.mainWindow);
      }
      hilog.info(DOMAIN, LOG_TAG, 'onConfigurationUpdate colorMode=%{public}d', dark ? 1 : 0);
    } catch (_e) {}
  }

  onDestroy(): void {
    stop();
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
      fnBindSystemAvoidArea(mainWindow);
      try {
        const ui = mainWindow.getUIContext();
        applyGalleryPerfImageCache(ui);
      } catch (_e) {
      }
    }).catch((_e: Error): void => {
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, LOG_TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      try {
        const win = windowStage.getMainWindowSync();
        this.mainWindow = win;
        fnBindWindowBreakpoint(win);
      } catch (_e) {
      }
      hilog.info(DOMAIN, LOG_TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    fnUnbindWindowBreakpoint();
    fnUnbindSystemAvoidArea();
    this.mainWindow = null;
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    BackgroundKeepAliveController.onAbilityForegroundOrDestroy(this.context);
    ensureStarted(this.context);
    scheduleCheck();
    refreshGalleryPerfProfile();
    this.applyPerfImageCacheIfReady();
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', 'Ability onBackground');
    // 官方 Background Tasks Kit：短时挂起宽限 + 数据传输类长时任务（见 module backgroundModes）
    BackgroundKeepAliveController.onAbilityBackground(this.context);
  }

  /**
   * 整机可用内存变化时降档并裁 PixelMap 缓存，不在此释放 UI 组件。
   */
  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    const keep = applyGalleryMemoryLevel(level);
    this.applyPerfImageCacheIfReady();
    if (keep >= 0) {
      trimThumbPixCache(keep);
    }
    hilog.info(DOMAIN, LOG_TAG, 'onMemoryLevel=%{public}d keep=%{public}d', level, keep);
  }

  private applyPerfImageCacheIfReady(): void {
    if (this.mainWindow === null) {
      return;
    }
    try {
      applyGalleryPerfImageCache(this.mainWindow.getUIContext());
    } catch (_e) {
    }
  }
}
