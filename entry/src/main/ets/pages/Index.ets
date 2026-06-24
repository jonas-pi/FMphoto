/**
 * 启动页：与系统 StartWindow 视觉一致（纯色 + 居中图标），恢复会话后跳转。
 * startIcon.png 建议 ≤192px，系统按资源像素原尺寸居中绘制。
 */
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import { SessionPreferences } from '../auth/SessionPreferences';
import { CertPolicy } from '../network/CertPolicy';
import { FnImmersiveBackdrop } from '../common/FnUiCommon';
import { fnApplySplashWindowChrome, fnRestoreAppSystemBars } from '../common/FnSplashTheme';

@Entry
@Component
struct Index {
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @State private hint: string = '正在初始化…';
  @State @Watch('onPrivacyConsentRequiredChanged') private privacyConsentRequired: boolean = false;
  @State private privacyConsentSubmitting: boolean = false;
  @State private splashOpacity: number = 1.0;
  @State private splashLoadingVisible: boolean = false;

  aboutToAppear(): void {
    this.syncSplashWindowChrome();
    if (this.privacyConsentRequired) {
      return;
    }
    // 延迟显示 loading 指示器，避免与 StartWindow 视觉冲突
    setTimeout((): void => {
      this.splashLoadingVisible = true;
    }, 400);
    void this.bootstrapFlow();
  }

  private onColorModeChanged(): void {
    this.syncSplashWindowChrome();
  }

  private onPrivacyConsentRequiredChanged(): void {
    this.syncSplashWindowChrome();
  }

  /** 启动闪屏与 StartWindow 同几何：全屏无系统栏；隐私弹窗时恢复系统栏。 */
  private syncSplashWindowChrome(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const dark = this.colorMode === 1;
      const immersive = !this.privacyConsentRequired;
      window.getLastWindow(ctx).then((mainWindow: window.Window): void => {
        fnApplySplashWindowChrome(mainWindow, dark, immersive);
      }).catch((_e: Error): void => {
      });
    } catch (_e) {
    }
  }

  /** 启动流程：先取得隐私政策同意，再进入既有会话恢复逻辑。 */
  private async bootstrapFlow(): Promise<void> {
    const accepted = await this.ensurePrivacyConsentAccepted();
    if (!accepted) {
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

  /** Splash 淡出后跳转，消除与目标页的硬切跳变。 */
  private fadeSplashAndNavigate(url: string): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((mainWindow: window.Window): void => {
        fnRestoreAppSystemBars(mainWindow);
      }).catch((_e: Error): void => {
      });
    } catch (_e) {
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Linear }, (): void => {
      this.splashOpacity = 0.0;
    });
    setTimeout((): void => {
      this.getUIContext().getRouter().replaceUrl({ url: url }).catch((): void => {
      });
    }, 210);
  }

  /** 恢复会话并跳转登录或主页。 */
  private restoreSessionAndRoute(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSession.restore(ctx).then((s) => {
      if (s === null || s.token.length === 0) {
        void SessionPreferences.loadTrustedHostsSnapshot(ctx).then((hosts: string[]) => {
          CertPolicy.loadAll(hosts);
        });
        this.fadeSplashAndNavigate('pages/Login');
        return;
      }
      const client = AppSession.getClient();
      if (client === null) {
        void SessionPreferences.loadTrustedHostsSnapshot(ctx).then((hosts: string[]) => {
          CertPolicy.loadAll(hosts);
        });
        this.fadeSplashAndNavigate('pages/Login');
        return;
      }
      if (s.loginViaWebSocket === true) {
        this.fadeSplashAndNavigate('pages/Home');
        return;
      }
      client.getUserInfo(5000, 2).then((r) => {
        if (r.success) {
          this.fadeSplashAndNavigate('pages/Home');
        } else {
          SessionPreferences.clearToken(ctx).then(() => {
            AppSession.clear();
            void SessionPreferences.loadTrustedHostsSnapshot(ctx).then((hosts: string[]) => {
              CertPolicy.loadAll(hosts);
            });
            this.fadeSplashAndNavigate('pages/Login');
          });
        }
      });
    }).catch(() => {
      this.hint = '读取配置失败';
      void SessionPreferences.loadTrustedHostsSnapshot(ctx).then((hosts: string[]) => {
        CertPolicy.loadAll(hosts);
      });
      this.fadeSplashAndNavigate('pages/Login');
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
  private startWindowSplash() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.start_window_background'))

      Column({ space: 12 }) {
        Image($r('app.media.startIcon'))
          .objectFit(ImageFit.None)
          .interpolation(ImageInterpolation.High)
          .syncLoad(true)

        if (this.splashLoadingVisible) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color($r('app.color.text_secondary'))
        }
      }
    }
    .width('100%')
    .height('100%')
    .opacity(this.splashOpacity)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  build() {
    Stack() {
      if (this.privacyConsentRequired) {
        FnImmersiveBackdrop()

        Column() {
          this.privacyConsentPanel()
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        this.startWindowSplash()
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
