/**
 * 备份 / 同步设置独立页。子页用组件内栈返回，栈底再退出本页。
 */
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AlbumBackupPageBack, AlbumBackupSyncSheet } from '../sync/AlbumBackupSyncSheet';
import { fnApplyImmersiveSystemBarColors } from '../common/FnSplashTheme';
import { FN_SYSTEM_TOP_INSET_VP_KEY, fnPublishSystemAvoidArea } from '../common/FnSystemAvoidArea';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import { FN_RESOLVED_PAGE_BG_KEY } from '../common/FnThemeColors';

@Entry
@Component
struct AlbumBackupSyncPage {
  @StorageProp(FN_RESOLVED_PAGE_BG_KEY) private pageBg: string = '#FFF4F7FB';
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;

  aboutToAppear(): void {
    this.applySystemBarTheme();
  }

  onPageShow(): void {
    this.applySystemBarTheme();
  }

  onColorModeChanged(): void {
    this.applySystemBarTheme();
  }

  onBackPress(): boolean {
    AlbumBackupPageBack.pop();
    return true;
  }

  private applySystemBarTheme(): void {
    try {
      const dark = this.colorMode === 1;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window): void => {
        fnPublishSystemAvoidArea(win, this.getUIContext());
        fnApplyImmersiveSystemBarColors(win, dark);
      }).catch((_e: Error): void => {});
    } catch (_e) {
    }
  }

  build() {
    Column() {
      AlbumBackupSyncSheet({
        onCloseSheet: (): void => {
          this.getUIContext().getRouter().back();
        }
      })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.systemTopInsetVp })
    .backgroundColor(this.pageBg)
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 12, y: 0 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: -8, y: 0 });
  }
}
