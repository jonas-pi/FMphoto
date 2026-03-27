/**
 * NAS 登录：仅通过 fnOS WebSocket 主通道（wss …/websocket?type=main）
 * getRSAPub → encrypted(user.login)；会话持久化 token 与 wsSignKeyB64（后续 WS 帧 HMAC 用）
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { FnHttpClient } from '../network/FnHttpClient';
import { CertPolicy } from '../network/CertPolicy';
import { fnWebViewBaseUrl, normalizeServerUrl } from '../network/ServerUrl';
import { fnWsLogin } from '../network/FnWsLogin';
import { AppSession } from '../auth/AppSession';
import { SessionPreferences, StoredSession } from '../auth/SessionPreferences';
import { FnPrimaryButton } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';

const LOGIN_DOMAIN = 0xFF00;
const LOGIN_TAG = 'Login';

@Entry
@Component
struct Login {
  @State private domainInput: string = '';
  @State private username: string = '';
  @State private password: string = '';
  @State private useHttps: boolean = true;
  @State private loading: boolean = false;
  @State private errorText: string = '';
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;

  onPageShow(): void {
    this.applySystemBarTheme();
  }

  onColorModeChanged(): void {
    this.applySystemBarTheme();
  }

  private applySystemBarTheme(): void {
    try {
      const dark = this.colorMode === 1;
      const bg = dark ? '#FF1C1C1E' : '#FFF5F5F5';
      const content = dark ? '#FFFFFFFF' : '#FF000000';
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win): void => {
        win.setWindowSystemBarProperties({
          statusBarColor: bg, navigationBarColor: bg,
          statusBarContentColor: content, navigationBarContentColor: content
        }).catch((_e: Error): void => {});
      }).catch((_e: Error): void => {});
    } catch (_e) {}
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void SessionPreferences.loadLoginFormDefaults(ctx).then((d) => {
      if (d.domainInput.length > 0) {
        this.domainInput = d.domainInput;
      }
      if (d.username.length > 0) {
        this.username = d.username;
      }
      if (d.password.length > 0) {
        this.password = d.password;
      }
      this.useHttps = d.useHttps;
    });
  }

  /** 保存会话并进入主页 */
  private async persistSessionAndGoHome(
    ctx: common.UIAbilityContext,
    base: string,
    user: string,
    pass: string,
    token: string,
    wsSignKeyB64: string,
    longTokenFromWs?: string
  ): Promise<void> {
    /** 内置 Web 固定 https:5667，与登录 base 可能不同，一并加入信任列表（自签证书） */
    CertPolicy.addTrusted(fnWebViewBaseUrl(base));
    const client = new FnHttpClient(base, token);
    let longTok = longTokenFromWs !== undefined && longTokenFromWs.length > 0 ? longTokenFromWs : '';
    if (longTok.length === 0) {
      try {
        longTok = await client.fetchFnosLongTokenProbe(14000);
      } catch (e) {
        hilog.warn(LOGIN_DOMAIN, LOGIN_TAG, 'fetchFnosLongTokenProbe: %{public}s', String(e));
        longTok = '';
      }
    }
    const stored: StoredSession = {
      baseUrl: base,
      token: token,
      account: user,
      domainInput: this.domainInput.trim(),
      useHttps: this.useHttps,
      albumParentGuid: '',
      trustedHosts: CertPolicy.dumpAll(),
      fnosLongToken: longTok,
      loginViaWebSocket: true,
      wsSignKeyB64: wsSignKeyB64
    };

    let existing: StoredSession | null = null;
    try {
      existing = await SessionPreferences.load(ctx);
    } catch (_e) {
      existing = null;
    }
    if (existing !== null && existing.albumParentGuid.length > 0) {
      stored.albumParentGuid = existing.albumParentGuid;
    }

    try {
      await SessionPreferences.save(ctx, stored, pass);
    } catch (e) {
      hilog.error(LOGIN_DOMAIN, LOGIN_TAG, 'SessionPreferences.save: %{public}s', String(e));
      this.errorText = '保存登录信息失败，请检查存储权限后重试';
      return;
    }
    AppSession.apply(stored);
    // 跳转前清空密码框，降低系统根据「提交后仍带密文的输入框」关联保险箱更新提示的概率
    this.password = '';
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/Home' }).catch(() => {
    });
  }

  /** 仅 WebSocket 登录 */
  private async attemptLoginWebSocketOnly(
    ctx: common.UIAbilityContext,
    server: string,
    user: string,
    pass: string
  ): Promise<void> {
    const trusted = CertPolicy.isTrusted(server);
    const wsRes = await fnWsLogin(server, user, pass, trusted);
    if (wsRes.success === true && wsRes.token !== undefined && wsRes.token.length > 0) {
      hilog.info(LOGIN_DOMAIN, LOGIN_TAG, 'login via WebSocket ok');
      const sk = wsRes.signKeyB64 !== undefined && wsRes.signKeyB64.length > 0 ? wsRes.signKeyB64 : '';
      const lt = wsRes.longToken !== undefined && wsRes.longToken.length > 0 ? wsRes.longToken : undefined;
      await this.persistSessionAndGoHome(ctx, server, user, pass, wsRes.token, sk, lt);
      return;
    }
    if (wsRes.certificateError === true && !trusted) {
      try {
        const dlg = await this.getUIContext().getPromptAction().showDialog({
          title: '证书不可信',
          message:
            'WebSocket（WSS）无法校验服务器证书。是否信任当前地址并继续？信任后将仅重试 WebSocket 登录。',
          buttons: [
            { text: '取消', color: '#99000000' },
            { text: '信任并继续', color: '#FF2563EB' }
          ]
        });
        if (dlg.index === 1) {
          CertPolicy.addTrusted(server);
          CertPolicy.addTrusted(fnWebViewBaseUrl(server));
          await this.attemptLoginWebSocketOnly(ctx, server, user, pass);
        } else {
          this.errorText = '已取消信任证书';
        }
      } catch (_e) {
        this.errorText = '已取消信任证书';
      }
      return;
    }
    this.errorText =
      wsRes.message !== undefined && wsRes.message.length > 0 ? wsRes.message : 'WebSocket 登录失败';
    if (this.errorText.length > 0) {
      hilog.warn(LOGIN_DOMAIN, LOGIN_TAG, 'WS login: %{public}s', this.errorText);
    }
  }

  private async onLoginClick(): Promise<void> {
    this.errorText = '';
    const server = normalizeServerUrl(this.domainInput, this.useHttps);
    if (server.length === 0 || this.username.trim().length === 0 || this.password.length === 0) {
      this.errorText = '请填写服务器地址、用户名和密码';
      return;
    }
    this.loading = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await this.attemptLoginWebSocketOnly(ctx, server, this.username.trim(), this.password);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(LOGIN_DOMAIN, LOGIN_TAG, 'login flow: %{public}s', msg.length > 0 ? msg : 'unknown');
      this.errorText = msg.length > 0 ? `请求异常：${msg}` : '网络异常';
    } finally {
      this.loading = false;
    }
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text($r('app.string.login_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .margin({ top: 48, bottom: 8 })

        TextInput({ placeholder: $r('app.string.hint_server'), text: this.domainInput })
          .enableAutoFill(false)
          .onChange((v: string) => {
            this.domainInput = v;
          })
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.radius_medium'))
          .padding({ left: 12, right: 12 })

        Row() {
          Text($r('app.string.use_https'))
            .fontSize(16)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.useHttps })
            .selectedColor($r('app.color.brand_primary'))
            .onChange((on: boolean) => {
              this.useHttps = on;
            })
        }
        .width('100%')

        /**
         * 用户名与密码须同时关闭自动填充，否则系统仍把二者识别为「可接入密码保险箱」的登录表单，
         * 在 replaceUrl 跳转后易误判为凭据变更而弹「更新密码保险箱」（见官方说明：
         * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/passwordvault-save-acc-password ）。
         * 本应用凭据由 SessionPreferences 自行持久化，不依赖系统保险箱填充。
         */
        TextInput({ placeholder: $r('app.string.hint_username'), text: this.username })
          .type(InputType.USER_NAME)
          .enableAutoFill(false)
          .onChange((v: string) => {
            this.username = v;
          })
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.radius_medium'))
          .padding({ left: 12, right: 12 })

        TextInput({ placeholder: $r('app.string.hint_password'), text: this.password })
          .type(InputType.Password)
          .enableAutoFill(false)
          .onChange((v: string) => {
            this.password = v;
          })
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.radius_medium'))
          .padding({ left: 12, right: 12 })

        if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontColor(Color.Red)
            .fontSize(14)
            .width('100%')
        }

        FnPrimaryButton({ text: this.loading ? $r('app.string.logging_in') : $r('app.string.login_action') })
          .width('100%')
          .enabled(!this.loading)
          .onClick((): void => {
            void this.onLoginClick();
          })

        Text($r('app.string.fnid_hint'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 24 })
      }
      .padding({ left: 24, right: 24, bottom: 32 })
      .constraintSize({ minHeight: '100%' })
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 0, y: 16 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: 0, y: -8 });
  }
}
