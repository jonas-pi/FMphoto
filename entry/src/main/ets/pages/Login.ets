/**
 * NAS 登录：FN ID（FN Connect 解析公网/内网/官方中继）或内网 IP 共用一栏，公网域名可选；
 * 经 fnOS WebSocket 主通道（wss …/websocket?type=main）
 * getRSAPub → encrypted(user.login)；会话持久化 token 与 wsSignKeyB64（后续 WS 帧 HMAC 用）
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { hdsEffect } from '@kit.UIDesignKit';
import { FnHttpClient } from '../network/FnHttpClient';
import { CertPolicy } from '../network/CertPolicy';
import { fnWebViewBaseUrl, normalizeServerUrl } from '../network/ServerUrl';
import {
  LOGIN_ENDPOINT_PREF_AUTO,
  selectAmongEndpointPool
} from '../network/LoginEndpointSelector';
import { extractFnId, isFnId, isFnRelayBaseUrl, lookupFnConnect } from '../network/FnConnectApi';
import { preferPublicEndpointUrl, resolvePublicDomainToIpBaseUrl } from '../network/PublicDns';
import { isIpLiteralHost, parseNormalizedBaseUrl } from '../network/ServerUrl';
import { fnWs2faVerify, fnWsLogin } from '../network/FnWsLogin';
import { AppSession } from '../auth/AppSession';
import { SessionPreferences, StoredSession } from '../auth/SessionPreferences';
import { FnLoginPrimaryButton, FnLoginSecondaryButton } from '../common/FnLoginButtons';
import { FnLoginRoutePrefSegment } from '../common/FnLoginRoutePrefSegment';
import { FnLoginTextField } from '../common/FnLoginTextField';
import { fnApplyImmersiveSystemBarColors, fnRestoreAppSystemBars } from '../common/FnSplashTheme';
import {
  FN_NAV_INDICATOR_INSET_VP_KEY,
  FN_SYSTEM_BOTTOM_INSET_VP_KEY,
  FN_SYSTEM_TOP_INSET_VP_KEY,
  fnPublishSystemAvoidArea
} from '../common/FnSystemAvoidArea';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';

const LOGIN_DOMAIN = 0xFF00;
const LOGIN_TAG = 'Login';
const LOGIN_CARD_RADIUS_VP: number = 24;
const LOGIN_FIELD_HEIGHT_VP: number = 44;
const LOGIN_HERO_ICON_VP: number = 72;
/** 前景卡片相对状态栏 / 小白条的额外留白，上下共用 */
const LOGIN_PANEL_EDGE_GAP_VP: number = 12;

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
  /** 表单默认值读完再挂输入框，避免 TextInput 先以空 seed 建好后回填不刷新 */
  @State private formReady: boolean = false;
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
  private pendingEndpointLanIpv6Url: string = '';
  private pendingEndpointPublicIpv6Url: string = '';
  private pendingEndpointRelayUrl: string = '';
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(FN_SYSTEM_BOTTOM_INSET_VP_KEY) private systemBottomInsetVp: number = 0;
  @StorageProp(FN_NAV_INDICATOR_INSET_VP_KEY) private navIndicatorInsetVp: number = 0;

  onPageShow(): void {
    this.applySystemBarTheme();
  }

  onColorModeChanged(): void {
    this.applySystemBarTheme();
  }

  private applySystemBarTheme(): void {
    try {
      const dark = this.colorMode === 1;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window): void => {
        fnRestoreAppSystemBars(win);
        fnPublishSystemAvoidArea(win, this.getUIContext());
        fnApplyImmersiveSystemBarColors(win, dark);
      }).catch((_e: Error): void => {});
    } catch (_e) {}
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void SessionPreferences.loadLoginFormDefaults(ctx).then((d) => {
      this.fnIdInput = d.fnIdInput.length > 0 ? d.fnIdInput : d.lanInput;
      this.domainInput = d.domainInput;
      if (d.loginEndpointPreference.length > 0) {
        this.endpointPreference = d.loginEndpointPreference;
      }
      this.username = d.username;
      this.useHttps = d.useHttps;
      this.formReady = true;
    }).catch((_e: Error) => {
      this.formReady = true;
    });
  }

  private loginBottomChromeInsetVp(): number {
    const chrome = Math.max(this.systemBottomInsetVp, this.navIndicatorInsetVp);
    return chrome > 0 ? chrome : 20;
  }

  /**
   * 共用输入栏：纯 FN ID / fnos.net / 5ddd.com 形态 → FN Connect；其余按内网地址。
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
    if (id.length > 0 && (t.toLowerCase().indexOf('fnos.net') >= 0 ||
      t.toLowerCase().indexOf('5ddd.com') >= 0)) {
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
      endpointLanIpv6Url: this.pendingEndpointLanIpv6Url,
      endpointPublicIpv6Url: this.pendingEndpointPublicIpv6Url,
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
      AppSession.setLoginPassword(pass);
      await SessionPreferences.saveLoginFormDefaults(ctx, {
        fnIdInput: this.fnIdInput.trim(),
        domainInput: stored.domainInput,
        lanInput: stored.lanInput,
        loginEndpointPreference: stored.loginEndpointPreference,
        username: stored.account,
        password: '',
        useHttps: stored.useHttps
      });
      await SessionPreferences.save(ctx, stored);
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
      this.pendingEndpointLanIpv6Url = '';
      this.pendingEndpointPublicIpv6Url = '';
      this.pendingEndpointRelayUrl = '';

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
        const lanUrl = normalizeServerUrl(lanRaw, this.useHttps);
        if (lanUrl.length > 0) {
          const lanParts = parseNormalizedBaseUrl(lanUrl);
          if (lanParts !== null && lanParts.useBracket) {
            this.pendingEndpointLanIpv6Url = lanUrl;
          } else {
            this.pendingEndpointLanUrl = lanUrl;
          }
        }
      }

      // FN ID：FN Connect 补齐公网 / 内网 V4/V6 以及官方中继；手填域名优先于云端 DDNS
      if (fnId.length > 0) {
        const looked = await lookupFnConnect(fnId, this.useHttps);
        const hasAny = looked.publicDomainServer.length > 0 || looked.publicIpServer.length > 0 ||
          looked.lanServer.length > 0 || looked.relayServer.length > 0;
        if (!looked.ok || !hasAny) {
          this.errorText = looked.message.length > 0 ? looked.message : 'FN ID 解析失败';
          return;
        }
        if (this.pendingEndpointPublicDomainUrl.length === 0 && looked.publicDomainServer.length > 0) {
          this.pendingEndpointPublicDomainUrl = looked.publicDomainServer;
        }
        if (this.pendingEndpointPublicIpUrl.length === 0 && looked.publicIpv4Server.length > 0) {
          this.pendingEndpointPublicIpUrl = looked.publicIpv4Server;
        }
        if (this.pendingEndpointPublicIpv6Url.length === 0 && looked.publicIpv6Server.length > 0) {
          this.pendingEndpointPublicIpv6Url = looked.publicIpv6Server;
        }
        if (this.pendingEndpointLanUrl.length === 0 && looked.lanIpv4Server.length > 0) {
          this.pendingEndpointLanUrl = looked.lanIpv4Server;
        }
        if (this.pendingEndpointLanIpv6Url.length === 0 && looked.lanIpv6Server.length > 0) {
          this.pendingEndpointLanIpv6Url = looked.lanIpv6Server;
        }
        if (looked.relayServer.length > 0) {
          this.pendingEndpointRelayUrl = looked.relayServer;
        }
      }

      this.pendingEndpointPublicUrl = preferPublicEndpointUrl(
        this.pendingEndpointPublicDomainUrl,
        this.pendingEndpointPublicIpUrl.length > 0 ?
          this.pendingEndpointPublicIpUrl : this.pendingEndpointPublicIpv6Url
      );

      const selected = await selectAmongEndpointPool({
        lanIpv4Url: this.pendingEndpointLanUrl,
        lanIpv6Url: this.pendingEndpointLanIpv6Url,
        publicDomainUrl: this.pendingEndpointPublicDomainUrl,
        publicIpv4Url: this.pendingEndpointPublicIpUrl,
        publicIpv6Url: this.pendingEndpointPublicIpv6Url,
        relayUrl: this.pendingEndpointRelayUrl
      }, this.endpointPreference);
      if (selected.server.length === 0 || !selected.selectedOk) {
        this.errorText = selected.summary.length > 0
          ? selected.summary
          : '公网、内网与官方中继均不可达';
        return;
      }
      if (selected.preferredPublicUrl.length > 0) {
        this.pendingEndpointPublicUrl = selected.preferredPublicUrl;
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

  @Builder
  private loginBackdrop() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .hitTestBehavior(HitTestMode.None)
  }

  /**
   * 蓝圆只做光源，不自绘 blur。泛光和边缘扭曲走 HDS 点光源；
   * 前景材质的 materialFilter 再把圆采样成光晕。
   */
  private loginGlowSourceEffect(color: ResourceColor, heightVp: number): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pointLight({
        options: {
          color: color,
          intensity: 0.92,
          height: heightVp,
          bloom: 0.88
        }
      })
      .buildEffect();
  }

  /** 前景玻璃板边缘接住蓝圆点光源，形成扭曲光线 */
  private loginForegroundIllumination(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pointLight({
        illuminatedType: hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER
      })
      .buildEffect();
  }

  @Builder
  private loginPanelGlow() {
    Stack() {
      Column()
        .width(180)
        .height(180)
        .borderRadius(90)
        .backgroundColor($r('app.color.login_glow_blue_core'))
        .opacity(0.9)
        .visualEffect(this.loginGlowSourceEffect($r('app.color.login_glow_blue_core'), 72))
        .position({ x: '6%', y: '8%' })

      Column()
        .width(150)
        .height(150)
        .borderRadius(75)
        .backgroundColor($r('app.color.login_glow_blue_soft'))
        .opacity(0.85)
        .visualEffect(this.loginGlowSourceEffect($r('app.color.login_glow_blue_soft'), 60))
        .position({ x: '52%', y: '28%' })

      Column()
        .width(130)
        .height(130)
        .borderRadius(65)
        .backgroundColor($r('app.color.brand_primary'))
        .opacity(0.78)
        .visualEffect(this.loginGlowSourceEffect($r('app.color.brand_primary'), 52))
        .position({ x: '18%', y: '58%' })
    }
    .width('100%')
    .height('100%')
    .borderRadius(LOGIN_CARD_RADIUS_VP)
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private loginField(
    text: string,
    placeholder: Resource,
    inputType: InputType,
    enabled: boolean,
    onChange: (value: string) => void,
    maxLength: number = -1
  ) {
    FnLoginTextField({
      seedText: text,
      placeholder: placeholder,
      inputType: inputType,
      fieldEnabled: enabled,
      maxLength: maxLength,
      onChange: onChange
    })
  }

  private loginPanelBackgroundEffect(): BackgroundEffectOptions {
    return {
      radius: 80,
      saturation: 1.4,
      brightness: 1.12,
      color: $r('app.color.login_card_fill'),
      adaptiveColor: AdaptiveColor.DEFAULT
    };
  }

  @Builder
  private loginForegroundPanel() {
    Stack() {
      this.loginPanelGlow()

      Column()
        .width('100%')
        .height('100%')
        .borderRadius(LOGIN_CARD_RADIUS_VP)
        .clip(true)
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(this.loginPanelBackgroundEffect())
        .visualEffect(this.loginForegroundIllumination())
        .hitTestBehavior(HitTestMode.None)

      Scroll() {
        Column({ space: 12 }) {
          this.loginHeroSection()
          this.loginFormBody()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 20 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.TopStart)
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .borderRadius(LOGIN_CARD_RADIUS_VP)
    .clip(false)
  }

  @Builder
  private loginFormBody() {
    Column({ space: 14 }) {
      if (!this.formReady) {
        Blank()
          .width('100%')
          .height(LOGIN_FIELD_HEIGHT_VP)
      } else {
      Column({ space: 14 }) {
      this.loginField(this.fnIdInput, $r('app.string.hint_fnid'), InputType.Normal, !this.show2faStep, (v: string) => {
        this.fnIdInput = v;
      })

      Text($r('app.string.fnid_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      this.loginField(this.domainInput, $r('app.string.hint_public_domain'), InputType.Normal, !this.show2faStep,
        (v: string) => {
          this.domainInput = v;
        })

      Text($r('app.string.public_domain_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Row() {
        Text($r('app.string.use_https'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.useHttps })
          .selectedColor($r('app.color.brand_primary'))
          .onChange((on: boolean) => {
            this.useHttps = on;
          })
      }
      .width('100%')
      .height(LOGIN_FIELD_HEIGHT_VP)
      .padding({ left: 4, right: 4 })

      FnLoginRoutePrefSegment({
        selectedValue: this.endpointPreference,
        disabled: this.show2faStep || this.loading,
        onValueChange: (value: string): void => {
          this.endpointPreference = value;
        }
      })

      /**
       * 用户名与密码须同时关闭自动填充，否则系统仍把二者识别为「可接入密码保险箱」的登录表单，
       * 在 replaceUrl 跳转后易误判为凭据变更而弹「更新密码保险箱」。
       * 本应用凭据由 SessionPreferences 自行持久化，不依赖系统保险箱填充。
       */
      this.loginField(this.username, $r('app.string.hint_username'), InputType.USER_NAME, true, (v: string) => {
        this.username = v;
      })

      this.loginField(this.password, $r('app.string.hint_password'), InputType.Password, !this.show2faStep,
        (v: string) => {
          this.password = v;
        })

      if (this.show2faStep) {
        Text($r('app.string.twofa_step_hint'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        this.loginField(this.otpCode, $r('app.string.hint_otp'), InputType.Number, true, (v: string) => {
          this.otpCode = v.replace(/[^\d]/g, '').substring(0, 6);
        }, 6)

        Row() {
          Text($r('app.string.trust_device'))
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.trustDevice })
            .selectedColor($r('app.color.brand_primary'))
            .onChange((on: boolean) => {
              this.trustDevice = on;
            })
        }
        .width('100%')
        .height(LOGIN_FIELD_HEIGHT_VP)
        .padding({ left: 4, right: 4 })
      }

      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontColor(Color.Red)
          .fontSize(14)
          .width('100%')
      }

      if (this.show2faStep) {
        FnLoginPrimaryButton({
          text: this.loading ? $r('app.string.verifying_2fa') : $r('app.string.verify_2fa'),
          buttonEnabled: !this.loading,
          action: (): void => {
            void this.on2faVerifyClick();
          }
        })

        FnLoginSecondaryButton({
          text: $r('app.string.back_to_password_step'),
          buttonEnabled: !this.loading,
          action: (): void => {
            this.onBackFrom2fa();
          }
        })
      } else {
        FnLoginPrimaryButton({
          text: this.loading ? $r('app.string.logging_in') : $r('app.string.login_action'),
          buttonEnabled: !this.loading,
          action: (): void => {
            void this.onLoginClick();
          }
        })
      }
      }
      .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private loginHeroSection() {
    Column({ space: 10 }) {
      Image($r('app.media.app_icon'))
        .width(LOGIN_HERO_ICON_VP)
        .height(LOGIN_HERO_ICON_VP)
        .borderRadius(18)

      Text($r('app.string.login_title'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')

      Text($r('app.string.EntryAbility_label'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.loginBackdrop()

      Column() {
        Blank().height(this.systemTopInsetVp + LOGIN_PANEL_EDGE_GAP_VP)
        Column() {
          this.loginForegroundPanel()
        }
        .width('100%')
        .layoutWeight(1)
        .constraintSize({ minHeight: 0 })
      }
      .padding({
        left: 20,
        right: 20,
        bottom: this.loginBottomChromeInsetVp() + LOGIN_PANEL_EDGE_GAP_VP
      })
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
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
