/**
 * NAS 登录：FN ID（FN Connect 解析公网/内网）或内网 IP 共用一栏，公网域名可选；
 * 经 fnOS WebSocket 主通道（wss …/websocket?type=main）
 * getRSAPub → encrypted(user.login)；会话持久化 token 与 wsSignKeyB64（后续 WS 帧 HMAC 用）
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { FnHttpClient } from '../network/FnHttpClient';
import { CertPolicy } from '../network/CertPolicy';
import { fnWebViewBaseUrl, normalizeServerUrl } from '../network/ServerUrl';
import {
  LOGIN_ENDPOINT_PREF_AUTO,
  LOGIN_ENDPOINT_PREF_BANDWIDTH,
  LOGIN_ENDPOINT_PREF_LAN,
  LOGIN_ENDPOINT_PREF_LATENCY,
  LOGIN_ENDPOINT_PREF_PUBLIC,
  selectAmongEndpoints
} from '../network/LoginEndpointSelector';
import { extractFnId, isFnId, isFnRelayBaseUrl, lookupFnConnect } from '../network/FnConnectApi';
import { preferPublicEndpointUrl, resolvePublicDomainToIpBaseUrl } from '../network/PublicDns';
import { isIpLiteralHost, parseNormalizedBaseUrl } from '../network/ServerUrl';
import { fnWs2faVerify, fnWsLogin } from '../network/FnWsLogin';
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
  @State private fnIdInput: string = '';
  @State private domainInput: string = '';
  @State private endpointPreference: string = LOGIN_ENDPOINT_PREF_AUTO;
  @State private username: string = '';
  @State private password: string = '';
  @State private useHttps: boolean = true;
  @State private loading: boolean = false;
  @State private errorText: string = '';
  @State private probeSummary: string = '';
  /** 密码校验通过，等待第二步 OTP */
  @State private show2faStep: boolean = false;
  @State private otpCode: string = '';
  @State private trustDevice: boolean = true;
  private pendingAccessToken: string = '';
  private pendingDeviceId: string = '';
  private pendingServer: string = '';
  private pendingUser: string = '';
  private pendingPass: string = '';
  /** 登录成功后写入会话的可切换地址（规范化 baseUrl） */
  private pendingEndpointPublicUrl: string = '';
  private pendingEndpointPublicDomainUrl: string = '';
  private pendingEndpointPublicIpUrl: string = '';
  private pendingEndpointLanUrl: string = '';
  private pendingEndpointRelayUrl: string = '';
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
      // 共用栏：优先 FN ID，否则回填旧版内网 IP
      if (d.fnIdInput.length > 0) {
        this.fnIdInput = d.fnIdInput;
      } else if (d.lanInput.length > 0) {
        this.fnIdInput = d.lanInput;
      }
      if (d.domainInput.length > 0) {
        this.domainInput = d.domainInput;
      }
      if (d.loginEndpointPreference.length > 0) {
        this.endpointPreference = d.loginEndpointPreference;
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

  /**
   * 共用输入栏：纯 FN ID / fnos.net 形态 → FN Connect；其余按内网地址。
   * @returns [fnId, lanRaw]
   */
  private parseSharedHostInput(raw: string): [string, string] {
    const t = raw.trim();
    if (t.length === 0) {
      return ['', ''];
    }
    if (isFnId(t)) {
      return [t, ''];
    }
    const id = extractFnId(t);
    if (id.length > 0 && t.toLowerCase().indexOf('fnos.net') >= 0) {
      return [id, ''];
    }
    return ['', t];
  }

  /** 保存会话并进入主页 */
  private async persistSessionAndGoHome(
    ctx: common.UIAbilityContext,
    base: string,
    user: string,
    pass: string,
    token: string,
    wsSignKeyB64: string,
    openApiAuthxKey: string,
    openApiAuthxSecret: string,
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
    const sharedParsed = this.parseSharedHostInput(this.fnIdInput);
    const stored: StoredSession = {
      baseUrl: base,
      token: token,
      account: user,
      fnIdInput: sharedParsed[0],
      domainInput: this.domainInput.trim(),
      lanInput: sharedParsed[1],
      endpointPublicUrl: this.pendingEndpointPublicUrl,
      endpointPublicDomainUrl: this.pendingEndpointPublicDomainUrl,
      endpointPublicIpUrl: this.pendingEndpointPublicIpUrl,
      endpointLanUrl: this.pendingEndpointLanUrl,
      endpointRelayUrl: this.pendingEndpointRelayUrl,
      loginEndpointPreference: this.endpointPreference,
      useHttps: this.useHttps,
      albumParentGuid: '',
      trustedHosts: CertPolicy.dumpAll(),
      fnosLongToken: longTok,
      loginViaWebSocket: true,
      wsSignKeyB64: wsSignKeyB64,
      // Authx 改为登录后动态注入：此处持久化用于冷启动恢复，避免源码硬编码。
      openApiAuthxKey: openApiAuthxKey,
      openApiAuthxSecret: openApiAuthxSecret
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

  private async finishWsLoginSuccess(
    ctx: common.UIAbilityContext,
    server: string,
    user: string,
    pass: string,
    token: string,
    signKeyB64: string,
    longToken?: string
  ): Promise<void> {
    if (signKeyB64.length === 0) {
      this.errorText = '登录成功但未拿到签名密钥，请重试';
      return;
    }
    await this.persistSessionAndGoHome(ctx, server, user, pass, token, signKeyB64, token, signKeyB64, longToken);
  }

  /** 仅 WebSocket 登录 */
  private async attemptLoginWebSocketOnly(
    ctx: common.UIAbilityContext,
    server: string,
    user: string,
    pass: string
  ): Promise<void> {
    const trusted = CertPolicy.isTrusted(server);
    const deviceId = await SessionPreferences.ensureWsDeviceId(ctx);
    const wsRes = await fnWsLogin(server, user, pass, trusted, deviceId);
    if (wsRes.success === true && wsRes.token !== undefined && wsRes.token.length > 0) {
      hilog.info(LOGIN_DOMAIN, LOGIN_TAG, 'login via WebSocket ok');
      const sk = wsRes.signKeyB64 !== undefined && wsRes.signKeyB64.length > 0 ? wsRes.signKeyB64 : '';
      const lt = wsRes.longToken !== undefined && wsRes.longToken.length > 0 ? wsRes.longToken : undefined;
      await this.finishWsLoginSuccess(ctx, server, user, pass, wsRes.token, sk, lt);
      return;
    }
    if (wsRes.requires2fa === true) {
      const at = wsRes.accessToken !== undefined ? wsRes.accessToken : '';
      if (at.length === 0) {
        this.errorText = '需要双重验证但未收到挑战令牌，请重试';
        return;
      }
      this.pendingAccessToken = at;
      this.pendingDeviceId = deviceId;
      this.pendingServer = server;
      this.pendingUser = user;
      this.pendingPass = pass;
      this.show2faStep = true;
      this.otpCode = '';
      this.errorText = '';
      hilog.info(LOGIN_DOMAIN, LOGIN_TAG, 'login requires 2FA');
      return;
    }
    if (wsRes.requires2faSetup === true) {
      this.errorText =
        wsRes.message !== undefined && wsRes.message.length > 0
          ? wsRes.message
          : '该账号需在飞牛网页端先绑定双重验证';
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

  private describeLoginError(err: Object | Error | string | undefined | null): string {
    if (err === undefined || err === null) {
      return '';
    }
    if (typeof err === 'string') {
      return err.trim();
    }
    if (err instanceof Error) {
      const msg = err.message !== undefined ? err.message.trim() : '';
      if (msg.length > 0) {
        return msg;
      }
      const name = err.name !== undefined ? err.name.trim() : '';
      if (name.length > 0) {
        return name;
      }
    }
    const rec = err as Record<string, Object | undefined>;
    const fields = ['message', 'msg', 'reason', 'errMsg', 'details', 'detail'];
    for (let i = 0; i < fields.length; i++) {
      const raw = rec[fields[i]];
      if (typeof raw === 'string') {
        const text = raw.trim();
        if (text.length > 0) {
          return text;
        }
      }
    }
    try {
      const json = JSON.stringify(err);
      if (json !== undefined) {
        const text = json.trim();
        if (text.length > 0 && text !== '{}') {
          return text;
        }
      }
    } catch (_e) {
    }
    const fallback = String(err).trim();
    return fallback !== '[object Object]' ? fallback : '';
  }

  private async onLoginClick(): Promise<void> {
    this.errorText = '';
    this.probeSummary = '';
    const sharedRaw = this.fnIdInput.trim();
    const publicDomainRaw = this.domainInput.trim();
    const sharedParsed = this.parseSharedHostInput(sharedRaw);
    const fnId = sharedParsed[0];
    const lanRaw = sharedParsed[1];
    const hasAddr = fnId.length > 0 || publicDomainRaw.length > 0 || lanRaw.length > 0;
    if (!hasAddr || this.username.trim().length === 0 || this.password.length === 0) {
      this.errorText = '请填写 FN ID / 内网 IP 或公网域名，以及用户名和密码';
      return;
    }
    this.loading = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      this.show2faStep = false;
      this.pendingAccessToken = '';
      this.pendingDeviceId = '';
      this.pendingEndpointPublicUrl = '';
      this.pendingEndpointPublicDomainUrl = '';
      this.pendingEndpointPublicIpUrl = '';
      this.pendingEndpointLanUrl = '';
      this.pendingEndpointRelayUrl = '';

      let fnSummary = '';

      // 可选公网域名；误填 FN Connect 门户时忽略
      if (publicDomainRaw.length > 0) {
        const domainUrl = normalizeServerUrl(publicDomainRaw, this.useHttps);
        if (domainUrl.length > 0 && !isFnRelayBaseUrl(domainUrl)) {
          const hostParts = parseNormalizedBaseUrl(domainUrl);
          const host = hostParts !== null ? hostParts.host : '';
          if (host.length > 0 && isIpLiteralHost(host)) {
            this.pendingEndpointPublicIpUrl = domainUrl;
          } else {
            this.pendingEndpointPublicDomainUrl = domainUrl;
            this.pendingEndpointPublicIpUrl = await resolvePublicDomainToIpBaseUrl(domainUrl);
          }
        }
      }

      if (lanRaw.length > 0) {
        this.pendingEndpointLanUrl = normalizeServerUrl(lanRaw, this.useHttps);
      }

      // FN ID：FN Connect 补齐公网 / 内网；手填域名优先于云端 DDNS
      if (fnId.length > 0) {
        const looked = await lookupFnConnect(fnId, this.useHttps);
        const hasAny = looked.publicDomainServer.length > 0 || looked.publicIpServer.length > 0 ||
          looked.lanServer.length > 0;
        if (!looked.ok || !hasAny) {
          this.errorText = looked.message.length > 0 ? looked.message : 'FN ID 解析失败';
          return;
        }
        if (this.pendingEndpointPublicDomainUrl.length === 0 && looked.publicDomainServer.length > 0) {
          this.pendingEndpointPublicDomainUrl = looked.publicDomainServer;
        }
        if (this.pendingEndpointPublicIpUrl.length === 0 && looked.publicIpServer.length > 0) {
          this.pendingEndpointPublicIpUrl = looked.publicIpServer;
        }
        if (this.pendingEndpointLanUrl.length === 0 && looked.lanServer.length > 0) {
          this.pendingEndpointLanUrl = looked.lanServer;
        }
        fnSummary = looked.summary;
      }

      this.pendingEndpointPublicUrl = preferPublicEndpointUrl(
        this.pendingEndpointPublicDomainUrl,
        this.pendingEndpointPublicIpUrl
      );
      this.pendingEndpointRelayUrl = '';

      const selected = await selectAmongEndpoints(
        this.pendingEndpointPublicDomainUrl,
        this.pendingEndpointPublicIpUrl,
        this.pendingEndpointLanUrl,
        '',
        this.endpointPreference
      );
      if (selected.server.length === 0) {
        this.errorText = '请填写可用的 FN ID / 内网 IP 或公网域名';
        return;
      }
      if (selected.preferredPublicUrl.length > 0) {
        this.pendingEndpointPublicUrl = selected.preferredPublicUrl;
      }
      if (fnSummary.length > 0 && selected.summary.length > 0) {
        this.probeSummary = `${fnSummary}；${selected.summary}`;
      } else if (fnSummary.length > 0) {
        this.probeSummary = fnSummary;
      } else {
        this.probeSummary = selected.summary;
      }
      await this.attemptLoginWebSocketOnly(ctx, selected.server, this.username.trim(), this.password);
    } catch (e) {
      const msg = this.describeLoginError(e);
      hilog.error(LOGIN_DOMAIN, LOGIN_TAG, 'login flow: %{public}s', msg.length > 0 ? msg : 'unknown');
      this.errorText = msg.length > 0 ? `请求异常：${msg}` : '网络异常';
    } finally {
      this.loading = false;
    }
  }

  private async on2faVerifyClick(): Promise<void> {
    this.errorText = '';
    const code = this.otpCode.trim();
    if (!/^\d{6}$/.test(code)) {
      this.errorText = '请输入身份验证器中的 6 位动态验证码';
      return;
    }
    if (this.pendingAccessToken.length === 0 || this.pendingServer.length === 0 || this.pendingDeviceId.length === 0) {
      this.errorText = '验证会话已失效，请返回重新登录';
      this.show2faStep = false;
      return;
    }
    this.loading = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const trusted = CertPolicy.isTrusted(this.pendingServer);
    try {
      const wsRes = await fnWs2faVerify(
        this.pendingServer,
        this.pendingAccessToken,
        code,
        this.trustDevice,
        trusted,
        this.pendingDeviceId
      );
      if (wsRes.success === true && wsRes.token !== undefined && wsRes.token.length > 0) {
        const sk = wsRes.signKeyB64 !== undefined && wsRes.signKeyB64.length > 0 ? wsRes.signKeyB64 : '';
        const lt = wsRes.longToken !== undefined && wsRes.longToken.length > 0 ? wsRes.longToken : undefined;
        await this.finishWsLoginSuccess(ctx, this.pendingServer, this.pendingUser, this.pendingPass, wsRes.token, sk, lt);
        return;
      }
      if (wsRes.certificateError === true && !trusted) {
        this.errorText = '证书不可信，请先在登录步骤信任服务器地址';
        return;
      }
      this.errorText =
        wsRes.message !== undefined && wsRes.message.length > 0 ? wsRes.message : '双重验证失败';
    } catch (e) {
      const msg = this.describeLoginError(e);
      this.errorText = msg.length > 0 ? `请求异常：${msg}` : '网络异常';
    } finally {
      this.loading = false;
    }
  }

  private onBackFrom2fa(): void {
    this.show2faStep = false;
    this.otpCode = '';
    this.pendingAccessToken = '';
    this.pendingDeviceId = '';
    this.errorText = '';
  }

  private endpointPreferenceLabel(value: string): string {
    if (value === LOGIN_ENDPOINT_PREF_PUBLIC) {
      return '公网';
    }
    if (value === LOGIN_ENDPOINT_PREF_LAN) {
      return '内网';
    }
    if (value === LOGIN_ENDPOINT_PREF_BANDWIDTH) {
      return '带宽';
    }
    if (value === LOGIN_ENDPOINT_PREF_LATENCY) {
      return '延迟';
    }
    return '自动';
  }

  @Builder
  private endpointPreferenceTab(value: string) {
    Column() {
      Text(this.endpointPreferenceLabel(value))
        .fontSize(13)
        .fontWeight(this.endpointPreference === value ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.endpointPreference === value ? Color.White : $r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(17)
    .backgroundColor(this.endpointPreference === value ? $r('app.color.brand_primary') : Color.Transparent)
    .enabled(!this.show2faStep && !this.loading)
    .onClick((): void => {
      this.endpointPreference = value;
    })
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text($r('app.string.login_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .margin({ top: 48, bottom: 8 })

        TextInput({ placeholder: $r('app.string.hint_fnid'), text: this.fnIdInput })
          .enableAutoFill(false)
          .enableKeyboardOnFocus(false)
          .onChange((v: string) => {
            this.fnIdInput = v;
          })
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.radius_medium'))
          .padding({ left: 12, right: 12 })
          .enabled(!this.show2faStep)

        Text($r('app.string.fnid_hint'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        TextInput({ placeholder: $r('app.string.hint_public_domain'), text: this.domainInput })
          .enableAutoFill(false)
          .enableKeyboardOnFocus(false)
          .onChange((v: string) => {
            this.domainInput = v;
          })
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.radius_medium'))
          .padding({ left: 12, right: 12 })
          .enabled(!this.show2faStep)

        Text($r('app.string.public_domain_hint'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

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

        Column({ space: 10 }) {
          Text($r('app.string.login_route_pref_title'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)

          Row({ space: 2 }) {
            this.endpointPreferenceTab(LOGIN_ENDPOINT_PREF_AUTO)
            this.endpointPreferenceTab(LOGIN_ENDPOINT_PREF_LAN)
            this.endpointPreferenceTab(LOGIN_ENDPOINT_PREF_PUBLIC)
            this.endpointPreferenceTab(LOGIN_ENDPOINT_PREF_LATENCY)
            this.endpointPreferenceTab(LOGIN_ENDPOINT_PREF_BANDWIDTH)
          }
          .width('100%')
          .padding(3)
          .borderRadius(20)
          .backgroundColor($r('app.color.card_background'))
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
          .enableKeyboardOnFocus(false)
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
          .enableKeyboardOnFocus(false)
          .onChange((v: string) => {
            this.password = v;
          })
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.radius_medium'))
          .padding({ left: 12, right: 12 })
          .enabled(!this.show2faStep)

        if (this.show2faStep) {
          Text($r('app.string.twofa_step_hint'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')

          TextInput({ placeholder: $r('app.string.hint_otp'), text: this.otpCode })
            .type(InputType.Number)
            .maxLength(6)
            .enableAutoFill(false)
            .enableKeyboardOnFocus(false)
            .onChange((v: string) => {
              this.otpCode = v.replace(/[^\d]/g, '').substring(0, 6);
            })
            .width('100%')
            .height(44)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius($r('app.float.radius_medium'))
            .padding({ left: 12, right: 12 })

          Row() {
            Text($r('app.string.trust_device'))
              .fontSize(15)
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.trustDevice })
              .selectedColor($r('app.color.brand_primary'))
              .onChange((on: boolean) => {
                this.trustDevice = on;
              })
          }
          .width('100%')
        }

        if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontColor(Color.Red)
            .fontSize(14)
            .width('100%')
        }

        if (this.probeSummary.length > 0) {
          Text(this.probeSummary)
            .fontColor($r('app.color.text_secondary'))
            .fontSize(13)
            .width('100%')
        }

        if (this.show2faStep) {
          FnPrimaryButton({
            text: this.loading ? $r('app.string.verifying_2fa') : $r('app.string.verify_2fa'),
            action: (): void => {
              void this.on2faVerifyClick();
            }
          })
            .width('100%')
            .enabled(!this.loading)

          Button($r('app.string.back_to_password_step'))
            .type(ButtonType.Normal)
            .width('100%')
            .height(44)
            .backgroundColor($r('app.color.card_background'))
            .fontColor($r('app.color.text_secondary'))
            .enabled(!this.loading)
            .onClick((): void => {
              this.onBackFrom2fa();
            })
        } else {
          FnPrimaryButton({
            text: this.loading ? $r('app.string.logging_in') : $r('app.string.login_action'),
            action: (): void => {
              void this.onLoginClick();
            }
          })
            .width('100%')
            .enabled(!this.loading)
        }
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
