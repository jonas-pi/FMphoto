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

@Entry
@Component
struct Index {
  @State private busy: boolean = true;
  @State private hint: string = '正在初始化…';

  aboutToAppear(): void {
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
    Column() {
      Text('FNOS')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 80, bottom: 8 })
      if (this.busy) {
        LoadingProgress().width(48).height(48).margin({ top: 120 })
        Text(this.hint)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE }).opacity(0);
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE }).opacity(0);
  }
}
