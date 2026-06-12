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
  @State private privacyConsentRequired: boolean = false;
  @State private privacyConsentSubmitting: boolean = false;

  aboutToAppear(): void {
    if (this.privacyConsentRequired) {
      return;
    }
    void this.bootstrapFlow();
  }

  /** 启动流程：先取得隐私政策同意，再进入既有会话恢复逻辑。 */
  private async bootstrapFlow(): Promise<void> {
    const accepted = await this.ensurePrivacyConsentAccepted();
    if (!accepted) {
      this.busy = false;
      return;
    }
    this.restoreSessionAndRoute();
  }

  /** 首次启动隐私政策确认：同意前不恢复会话、不进入登录页。 */
  private async ensurePrivacyConsentAccepted(): Promise<boolean> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const accepted = await SessionPreferences.isPrivacyPolicyAccepted(ctx);
      if (accepted) {
        return true;
      }
      this.privacyConsentRequired = true;
      this.hint = '请先阅读并同意隐私政策';
      return false;
    } catch (_e) {
      this.privacyConsentRequired = true;
      this.hint = '请先阅读并同意隐私政策';
      return false;
    }
  }

  private openPrivacyPolicy(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/PrivacyPolicy' }).catch((): void => {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.privacy_consent_open_failed'),
          duration: 2500
        });
      } catch (_e) {
      }
    });
  }

  private async agreePrivacyConsent(): Promise<void> {
    if (this.privacyConsentSubmitting) {
      return;
    }
    this.privacyConsentSubmitting = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await SessionPreferences.setPrivacyPolicyAccepted(ctx, true);
      this.privacyConsentRequired = false;
      this.busy = true;
      this.hint = '正在初始化…';
      this.restoreSessionAndRoute();
    } catch (_e) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.privacy_consent_save_failed'),
          duration: 2500
        });
      } catch (_ignored) {
      }
    } finally {
      this.privacyConsentSubmitting = false;
    }
  }

  private async rejectPrivacyConsent(): Promise<void> {
    this.hint = '未同意隐私政策，应用已退出';
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await ctx.terminateSelf();
    } catch (_e) {
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

  @Builder
  private privacyConsentPanel() {
    Column({ space: 16 }) {
      Text($r('app.string.privacy_consent_title'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)

      Text($r('app.string.privacy_consent_message'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .lineHeight(21)

      Button($r('app.string.privacy_consent_view'))
        .width('100%')
        .height(42)
        .fontSize(15)
        .fontColor($r('app.color.brand_primary'))
        .backgroundColor('#1A2563EB')
        .borderRadius(14)
        .onClick((): void => {
          this.openPrivacyPolicy();
        })

      Row({ space: 12 }) {
        Button($r('app.string.privacy_consent_disagree'))
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor('#FFFF3B30')
          .backgroundColor('#1AFF3B30')
          .borderRadius(14)
          .enabled(!this.privacyConsentSubmitting)
          .onClick((): void => {
            void this.rejectPrivacyConsent();
          })

        Button($r('app.string.privacy_consent_agree'))
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(14)
          .enabled(!this.privacyConsentSubmitting)
          .onClick((): void => {
            void this.agreePrivacyConsent();
          })
      }
      .width('100%')
    }
    .width('88%')
    .padding({ left: 22, right: 22, top: 24, bottom: 22 })
    .backgroundColor($r('app.color.immersive_panel_bg'))
    .borderRadius(24)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
    .shadow({ radius: 28, color: '#16002B55', offsetX: 0, offsetY: 12 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private launchStatusPanel() {
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

  build() {
    Stack() {
      FnImmersiveBackdrop()

      Column() {
        if (this.privacyConsentRequired) {
          this.privacyConsentPanel()
        } else {
          this.launchStatusPanel()
        }
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
