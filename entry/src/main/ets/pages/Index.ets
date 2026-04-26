/**
 * 启动页：恢复会话并校验 token，跳转登录或主页
 */
import { common } from '@kit.AbilityKit';
import { AppSession } from '../auth/AppSession';
import { SessionPreferences } from '../auth/SessionPreferences';
import { CertPolicy } from '../network/CertPolicy';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import { FnImmersiveBackdrop } from '../common/FnUiCommon';

@Entry
@Component
struct Index {
  @State private busy: boolean = true;
  @State private hint: string = '正在初始化…';

  aboutToAppear(): void {
    void this.bootstrapFlow();
  }

  /** 启动流程：先展示首次免责声明，再进入既有会话恢复逻辑。 */
  private async bootstrapFlow(): Promise<void> {
    const accepted = await this.ensureLegalNoticeAccepted();
    if (!accepted) {
      this.busy = false;
      return;
    }
    this.restoreSessionAndRoute();
  }

  /**
   * 首次启动醒目提示：
   * - 标题加入警示符号；
   * - 未同意时终止应用；
   * - 同意后仅记录一次，后续不重复打扰。
   */
  private async ensureLegalNoticeAccepted(): Promise<boolean> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const accepted = await SessionPreferences.isLegalNoticeAccepted(ctx);
      if (accepted) {
        return true;
      }
      const dlg = await this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.legal_notice_title'),
        message: $r('app.string.legal_notice_message'),
        buttons: [
          { text: $r('app.string.legal_notice_disagree'), color: '#FFFF3B30' },
          { text: $r('app.string.legal_notice_agree'), color: '#FF2563EB' }
        ]
      });
      if (dlg.index === 1) {
        await SessionPreferences.setLegalNoticeAccepted(ctx, true);
        return true;
      }
      this.hint = '未同意免责声明，应用已退出';
      try {
        await ctx.terminateSelf();
      } catch (_e) {
      }
      return false;
    } catch (_e) {
      // 若弹窗能力异常，避免阻塞启动。
      return true;
    }
  }

  /** 恢复会话并跳转登录或主页。 */
  private restoreSessionAndRoute(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSession.restore(ctx).then((s) => {
      if (s === null || s.token.length === 0) {
        void SessionPreferences.loadTrustedHostsSnapshot(ctx).then((hosts: string[]) => {
          CertPolicy.loadAll(hosts);
        });
        this.busy = false;
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
        });
        return;
      }
      const client = AppSession.getClient();
      if (client === null) {
        void SessionPreferences.loadTrustedHostsSnapshot(ctx).then((hosts: string[]) => {
          CertPolicy.loadAll(hosts);
        });
        this.busy = false;
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
        });
        return;
      }
      if (s.loginViaWebSocket === true) {
        this.busy = false;
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/Home' }).catch(() => {
        });
        return;
      }
      client.getUserInfo(5000, 2).then((r) => {
        if (r.success) {
          this.getUIContext().getRouter().replaceUrl({ url: 'pages/Home' }).catch(() => {
          });
        } else {
          SessionPreferences.clearToken(ctx).then(() => {
            AppSession.clear();
            void SessionPreferences.loadTrustedHostsSnapshot(ctx).then((hosts: string[]) => {
              CertPolicy.loadAll(hosts);
            });
            this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
            });
          });
        }
        this.busy = false;
      });
    }).catch(() => {
      this.hint = '读取配置失败';
      this.busy = false;
      void SessionPreferences.loadTrustedHostsSnapshot(ctx).then((hosts: string[]) => {
        CertPolicy.loadAll(hosts);
      });
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
      });
    });
  }

  build() {
    Stack() {
      FnImmersiveBackdrop()

      Column() {
        Column({ space: 14 }) {
          Text('FNOS')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))

          Text('沉浸光感相册')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))

          if (this.busy) {
            LoadingProgress().width(44).height(44).margin({ top: 18 })
            Text(this.hint)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .width('84%')
        .padding({ left: 24, right: 24, top: 28, bottom: 28 })
        .backgroundColor($r('app.color.immersive_panel_bg'))
        .borderRadius(28)
        .borderWidth(1)
        .borderColor($r('app.color.immersive_panel_border'))
        .shadow({ radius: 28, color: '#16002B55', offsetX: 0, offsetY: 12 })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE }).opacity(0);
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE }).opacity(0);
  }
}
