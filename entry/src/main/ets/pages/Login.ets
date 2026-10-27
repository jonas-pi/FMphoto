/**
 * NAS 登录：FN ID / IP 共用一栏，另留公网域名。
 * 填 FN ID 时经 FN Connect 补齐全部通道；直连 IP 按内网/外网只探测对应通道。
 * 经 fnOS WebSocket 主通道（wss …/websocket?type=main）
 * getRSAPub → encrypted(user.login)；会话持久化 token 与 wsSignKeyB64（后续 WS 帧 HMAC 用）
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagMaskUrl, fnDiagRecord, fnDiagError, fnDiagTiming } from '../common/FnDiagLog';
import { openFeedbackPage } from './FeedbackPage';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';
import { CertPolicy } from '../network/CertPolicy';
import {
  classifyDirectNasAddress,
  DirectNasAddressSlots,
  fnWebViewBaseUrl,
  isIpLiteralHost,
  normalizeUserServerUrl,
  parseNormalizedBaseUrl
} from '../network/ServerUrl';
import {
  LOGIN_ENDPOINT_PREF_AUTO,
  LOGIN_ENDPOINT_PREF_BANDWIDTH,
  LOGIN_ENDPOINT_PREF_LATENCY,
  LOGIN_ENDPOINT_PREF_PUBLIC,
  LoginEndpointSelectionResult,
  orderedWsLoginServers,
  resolveLoginRedirectServer,
  selectAmongEndpointPool
} from '../network/LoginEndpointSelector';
import { isFnRelayBaseUrl, lookupFnConnect, FnConnectLookupResult, FnIdOrHostParts, splitFnIdOrHostInput } from '../network/FnConnectApi';
import { preferPublicEndpointUrl } from '../network/PublicDns';
import { fnWs2faVerify, fnWsLogin, FnWsLoginResult, shouldTryNextLoginEndpoint } from '../network/FnWsLogin';
import { AppSession } from '../auth/AppSession';
import { openPrivacyPolicyPage } from '../auth/PrivacyConsentNav';
import { loadAlbumBackupSettings } from '../sync/AlbumBackupSettings';
import { LoginFormDefaults, LoginSavedUser, SessionPreferences, StoredSession, upsertSavedUser } from '../auth/SessionPreferences';
import { nasFallbackIdentity, usableNasMachineId } from '../album/GalleryAutoSyncScope';
import { GalleryTimelineRefreshStore } from '../album/GalleryTimelineRefreshStore';
import { stopGalleryVideoLanPrefetch } from '../album/GalleryVideoLanPrefetch';
import { FnLoginPrimaryButton, FnLoginSecondaryButton } from '../common/FnLoginButtons';
import { FnLoginRoutePrefSegment } from '../common/FnLoginRoutePrefSegment';
import { FnLoginTextField } from '../common/FnLoginTextField';
import { fnApplyImmersiveSystemBarColors, fnRestoreAppSystemBars } from '../common/FnSplashTheme';
import {
  FN_LOGIN_PANEL_RADIUS_VP_KEY,
  FN_NAV_INDICATOR_INSET_VP_KEY,
  FN_SYSTEM_BOTTOM_INSET_VP_KEY,
  FN_SYSTEM_TOP_INSET_VP_KEY,
  fnPublishSystemAvoidArea
} from '../common/FnSystemAvoidArea';
import { fnHdsBindMenuOptions } from '../common/FnHdsOverlay';
import {
  FN_LOGIN_EXIT_FADE_CURVE,
  FN_LOGIN_EXIT_FADE_MS,
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import { FN_SHARE_INBOX_VERSION_KEY } from '../album/share/GalleryShareInbox';
import { galleryShareTryConsume } from '../album/share/GalleryShareConsume';
import { FN_RESOLVED_PAGE_BG_KEY, FN_RESOLVED_ACCENT_KEY,
  fnResolvedTextPrimary,
  FN_RESOLVED_TEXT_PRIMARY_KEY,
  fnResolvedTextSecondary,
  FN_RESOLVED_TEXT_SECONDARY_KEY} from '../common/FnThemeColors';

const LOGIN_DOMAIN = 0xFF00;
const LOGIN_TAG = 'Login';
const LOGIN_CARD_RADIUS_FALLBACK_VP: number = 24;
const LOGIN_FIELD_HEIGHT_VP: number = 44;
const LOGIN_HERO_ICON_VP: number = 72;
/** 前景卡片相对状态栏 / 小白条的额外留白，上下共用 */
const LOGIN_PANEL_EDGE_GAP_VP: number = 12;
/**
 * 键盘高度变化小于该值不重排。
 * 输入法候选栏增减这类微调，不值得触发一次面板重排（上架要求点击响应 ≤250ms）。
 * 注意：这滤不掉数字键盘↔全键盘的切换——那种高度差是几十 vp，本来就该重排。
 */
const LOGIN_KEYBOARD_INSET_EPSILON_VP: number = 8;

/** avoidAreaChange 回调载荷：只取软键盘区（TYPE_KEYBOARD） */
interface FnLoginAvoidAreaInfo {
  type: window.AvoidAreaType;
  area: window.AvoidArea;
}

/**
 * 日志脱敏：把消息里的裸主机名 / IP 掩掉。
 * 服务端返回的提示里常带地址（如「请检查 192.168.1.10 是否可达」），不能原样落盘。
 */
function fnLoginMaskHosts(text: string): string {
  let out: string = text.replace(/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?/g, '<ipv4>');
  out = out.replace(/[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d+)?/g, '<host>');
  return out;
}

/**
 * WS 登录的停止原因分类，供耗时埋点用。
 * 只看结果与文案，不含主机名；分类顺序与 FnWsLogin 内部判定保持一致。
 */
function fnWsStopReason(r: FnWsLoginResult): string {
  if (r.success === true) {
    return 'ok';
  }
  if (r.requires2fa === true) {
    return 'need2fa';
  }
  if (r.requires2faSetup === true) {
    return 'need2faSetup';
  }
  if (r.certificateError === true) {
    return 'cert';
  }
  const m: string = (r.message !== undefined ? r.message : '').toLowerCase();
  // 与 FnWsLogin.isRetryableRelayWsFailure 的判定口径保持一致：
  // 2FA 路径的文案是「双重验证超时」，不是「WebSocket 登录超时」。
  if (m.indexOf('websocket 登录超时') >= 0 || m.indexOf('双重验证超时') >= 0) {
    return 'timeout';
  }
  if (m.indexOf('无法连接') >= 0 || m.indexOf('连接失败') >= 0 || m.indexOf('打开失败') >= 0) {
    return 'connectFail';
  }
  if (m.indexOf('找不到') >= 0 || m.indexOf('host') >= 0 || m.indexOf('dns') >= 0) {
    return 'dns';
  }
  if (m.indexOf('密码') >= 0 || m.indexOf('登录失败') >= 0) {
    return 'authFail';
  }
  return 'other';
}

@Entry
@Component
struct Login {
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @StorageProp(FN_RESOLVED_TEXT_SECONDARY_KEY) private themeTextSecondary: string = '';
  @StorageProp(FN_RESOLVED_PAGE_BG_KEY) private pageBg: string = '#FFF4F7FB';
  @StorageProp(FN_RESOLVED_ACCENT_KEY) private accent: string = '#FF4A8BFF';
  @State private fnIdInput: string = '';
  @State private domainInput: string = '';
  @State private endpointPreference: string = LOGIN_ENDPOINT_PREF_AUTO;
  @State private username: string = '';
  @State private password: string = '';
  @State private useHttps: boolean = true;
  @State private rememberPassword: boolean = false;
  @State private savedUsers: LoginSavedUser[] = [];
  @State private savedUserNames: string[] = [];
  @State private userMenuVisible: boolean = false;
  @State private rememberToggleGen: number = 0;
  @State private credentialGen: number = 0;
  @State private loading: boolean = false;
  @State private errorText: string = '';
  /** 表单默认值读完再挂输入框，避免 TextInput 先以空 seed 建好后回填不刷新 */
  @State private formReady: boolean = false;
  /** 登录页不随键盘上抬，避免点密码框时整页重布局叠在安全键盘切换上 */
  private loginKeyboardAvoidApplied: boolean = false;
  private previousKeyboardAvoid: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;
  /**
   * 软键盘遮挡高度（vp）。登录页自己订阅 avoidAreaChange 的 TYPE_KEYBOARD 取。
   * 不并入 fnBindSystemAvoidArea：那是全应用的状态栏/挖孔/导航条状态，
   * 其它页已经在吃系统避让，全局再发一份键盘高度会重复顶。
   */
  @State private keyboardInsetVp: number = 0;
  private keyboardAvoidBound: boolean = false;
  /** 订阅代次：防止退订后在途的 getLastWindow 回调把监听又挂回去 */
  private keyboardAvoidGeneration: number = 0;
  private keyboardAvoidCallback: ((info: FnLoginAvoidAreaInfo) => void) | null = null;
  private keyboardBoundWindow: window.Window | null = null;
  /** 密码校验通过，等待第二步 OTP */
  @State private show2faStep: boolean = false;
  /** 登录成功后淡出登录页，再进入首页。 */
  @State private loginFadeOpacity: number = 1;
  /** 防止重复触发登录跳转。 */
  private leavingToHome: boolean = false;
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
  @StorageProp(FN_LOGIN_PANEL_RADIUS_VP_KEY) private panelRadiusVp: number = LOGIN_CARD_RADIUS_FALLBACK_VP;
  @StorageProp(FN_SHARE_INBOX_VERSION_KEY) @Watch('onShareInboxVersionChanged') private shareInboxVersion: number = 0;

  onPageShow(): void {
    this.applyLoginKeyboardAvoid(true);
    this.bindKeyboardAvoidArea();
    this.applySystemBarTheme();
    this.tryConsumeShareInbox();
  }

  onPageHide(): void {
    this.applyLoginKeyboardAvoid(false);
    this.unbindKeyboardAvoidArea();
  }

  private onShareInboxVersionChanged(): void {
    this.tryConsumeShareInbox();
  }

  private tryConsumeShareInbox(): void {
    void galleryShareTryConsume(this.getUIContext(), (msg: string): void => {
      try {
        this.getUIContext().getPromptAction().showToast({ message: msg });
      } catch (_e) {
      }
    });
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
    this.applyLoginKeyboardAvoid(true);
    this.bindKeyboardAvoidArea();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void SessionPreferences.loadLoginFormDefaults(ctx).then((d) => {
      this.fnIdInput = this.combinedHostFieldFromDefaults(d);
      this.domainInput = d.domainInput;
      if (d.loginEndpointPreference.length > 0) {
        this.endpointPreference = d.loginEndpointPreference;
      }
      this.username = d.username;
      this.password = d.rememberPassword ? d.password : '';
      this.useHttps = d.useHttps;
      this.rememberPassword = d.rememberPassword;
      this.savedUsers = d.savedUsers;
      this.savedUserNames = this.namesFromUsers(d.savedUsers);
      this.formReady = true;
    }).catch((_e: Error) => {
      this.formReady = true;
    });
    setTimeout((): void => {
      this.tryConsumeShareInbox();
    }, 0);
  }

  aboutToDisappear(): void {
    this.applyLoginKeyboardAvoid(false);
    this.unbindKeyboardAvoidArea();
  }

  private applyLoginKeyboardAvoid(enable: boolean): void {
    try {
      const ui = this.getUIContext();
      if (enable) {
        if (!this.loginKeyboardAvoidApplied) {
          this.previousKeyboardAvoid = ui.getKeyboardAvoidMode();
          this.loginKeyboardAvoidApplied = true;
        }
        ui.setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
        return;
      }
      if (this.loginKeyboardAvoidApplied) {
        ui.setKeyboardAvoidMode(this.previousKeyboardAvoid);
        this.loginKeyboardAvoidApplied = false;
      }
    } catch (_e) {
    }
  }

  /**
   * 登录页自行订阅软键盘避让区。
   *
   * 为什么不用系统自动避让：KeyboardAvoidMode.OFFSET 会在键盘弹出时整页上抬，
   * 实时模糊把点击响应拖到 600ms+，上架要求 ≤250ms（见 FnLoginTextField 头注释）。
   * 这里固定用 NONE（系统完全不做避让，键盘会盖住下半屏），改成自己抬面板：
   * 只改外层 Column 的 padding.bottom，面板与内部 Scroll 变矮，
   * 焦点输入框能滚到；背景层不动，也没有整页位移动画。
   *
   * 官方做法见 faqs-arkui-54（TYPE_KEYBOARD + margin 顶起底部组件）。
   */
  private bindKeyboardAvoidArea(): void {
    if (this.keyboardAvoidBound) {
      return;
    }
    // 代次：getLastWindow 是异步的，返回时可能已经退订过（页面已不可见），
    // 或被后一次订阅取代。代次不一致就不要再 on。
    const gen = ++this.keyboardAvoidGeneration;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window): void => {
        if (this.keyboardAvoidBound) {
          return;
        }
        if (gen !== this.keyboardAvoidGeneration) {
          return;
        }
        const cb = (data: FnLoginAvoidAreaInfo): void => {
          if (data.type !== window.AvoidAreaType.TYPE_KEYBOARD) {
            return;
          }
          this.applyKeyboardInset(data.area.bottomRect.height);
        };
        this.keyboardAvoidCallback = cb;
        this.keyboardBoundWindow = win;
        this.keyboardAvoidBound = true;
        try {
          win.on('avoidAreaChange', cb);
        } catch (_e) {
          this.keyboardAvoidBound = false;
          this.keyboardBoundWindow = null;
          this.keyboardAvoidCallback = null;
          return;
        }
        // 订阅生效前键盘可能已经弹着，先取一次当前高度兜底
        try {
          const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
          this.applyKeyboardInset(area.bottomRect.height);
        } catch (_e) {
        }
      }).catch((_e: Error): void => {});
    } catch (_e) {
    }
  }

  private unbindKeyboardAvoidArea(): void {
    // 代次 +1：在途的 getLastWindow 回调回来时作废，避免页面已不可见却又 on 一次
    this.keyboardAvoidGeneration++;
    if (this.keyboardBoundWindow !== null && this.keyboardAvoidCallback !== null) {
      try {
        // 必须传同一个函数引用：不带参数的 off('avoidAreaChange') 会摘掉全部监听，
        // 包括 fnBindSystemAvoidArea 注册的那个。
        this.keyboardBoundWindow.off('avoidAreaChange', this.keyboardAvoidCallback);
      } catch (_e) {
      }
    }
    this.keyboardBoundWindow = null;
    this.keyboardAvoidCallback = null;
    this.keyboardAvoidBound = false;
    this.keyboardInsetVp = 0;
  }

  /** 键盘高度（px）转 vp 并做抖动过滤。 */
  private applyKeyboardInset(px: number): void {
    const vp = this.pxToVp(px);
    const cur = this.keyboardInsetVp;
    // 弹出/收起一定要更新；两个非零值之间的小幅变化忽略
    if (vp > 0 && cur > 0 && Math.abs(vp - cur) < LOGIN_KEYBOARD_INSET_EPSILON_VP) {
      return;
    }
    this.keyboardInsetVp = vp > 0 ? vp : 0;
  }

  private pxToVp(px: number): number {
    try {
      return this.getUIContext().px2vp(px);
    } catch (_e) {
      return px;
    }
  }

  private loginPanelRadiusVp(): number {
    return this.panelRadiusVp > 0 ? this.panelRadiusVp : LOGIN_CARD_RADIUS_FALLBACK_VP;
  }

  private namesFromUsers(users: LoginSavedUser[]): string[] {
    const names: string[] = [];
    for (let i = 0; i < users.length; i++) {
      names.push(users[i].username);
    }
    return names;
  }

  private applySavedUserByIndex(idx: number): void {
    if (idx < 0 || idx >= this.savedUsers.length) {
      return;
    }
    const row = this.savedUsers[idx];
    this.userMenuVisible = false;
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (_e) {
    }
    this.username = row.username;
    this.rememberPassword = row.rememberPassword;
    this.password = row.rememberPassword ? row.password : '';
    this.rememberToggleGen = this.rememberToggleGen + 1;
    this.credentialGen = this.credentialGen + 1;
  }

  @Builder
  private savedUserMenuBuilder() {
    Menu() {
      ForEach(this.savedUserNames, (name: string, idx: number) => {
        MenuItem({ content: name })
          .onClick((): void => {
            this.applySavedUserByIndex(idx);
          })
      }, (name: string, idx: number) => `saved-user-${idx}-${name}`)
    }
  }

  private loginBottomChromeInsetVp(): number {
    const chrome = Math.max(this.systemBottomInsetVp, this.navIndicatorInsetVp);
    return chrome > 0 ? chrome : 20;
  }

  /**
   * 登录面板的底部留白。
   * 键盘弹起时用键盘高度（导航条/小白条已被键盘盖住，不再叠加 chrome inset），
   * 否则用系统导航条高度。
   *
   * 这里必须是外层 Column 的 padding，不能给面板加 margin：
   * 面板是 height('100%')，父容器是 layoutWeight(1) 的定高容器，
   * margin 会把面板顶出父容器，里面的 Scroll 视口不会变矮，输入框照样被遮。
   */
  private loginBottomInsetVp(): number {
    if (this.keyboardInsetVp > 0) {
      return this.keyboardInsetVp + LOGIN_PANEL_EDGE_GAP_VP;
    }
    return this.loginBottomChromeInsetVp() + LOGIN_PANEL_EDGE_GAP_VP;
  }

  /**
   * 仅识别 FN ID / 官方中继门户；其它输入不当作 FN Connect。
   */
  private parsedFnId(): string {
    return splitFnIdOrHostInput(this.fnIdInput).fnId;
  }

  /** FN ID 栏里误填的普通地址，按内网/外网/域名分流。 */
  private leftoverHostFromFnId(): string {
    const split: FnIdOrHostParts = splitFnIdOrHostInput(this.fnIdInput);
    if (split.fnId.length > 0) {
      return '';
    }
    return split.host;
  }

  /**
   * 手填地址会实际连到的 URL。没写端口时不追加端口。
   */
  private loginTargetPreview(): string {
    const slots: DirectNasAddressSlots = this.loginDirectSlots();
    const urls: string[] = [];
    const push = (raw: string): void => {
      const url = normalizeUserServerUrl(raw, this.useHttps);
      if (url.length === 0) {
        return;
      }
      for (let i = 0; i < urls.length; i++) {
        if (urls[i] === url) {
          return;
        }
      }
      urls.push(url);
    };
    push(slots.lan);
    push(slots.publicIpv4);
    push(slots.publicIpv6);
    push(slots.domain);
    if (urls.length === 0) {
      return '';
    }
    return `将连接 ${urls.join('、')}`;
  }

  /** 把共用栏直连地址分到探测槽；域名栏优先于共用栏里的主机名。 */
  private loginDirectSlots(): DirectNasAddressSlots {
    const slots: DirectNasAddressSlots = classifyDirectNasAddress(this.leftoverHostFromFnId(), this.useHttps);
    const typedDomain: string = this.domainInput.trim();
    if (typedDomain.length > 0) {
      slots.domain = typedDomain;
    }
    return slots;
  }

  /** 旧版拆栏回填：有 FN ID 显示 FN ID，否则把直连 IP 合回共用栏。 */
  private combinedHostFieldFromDefaults(d: LoginFormDefaults): string {
    if (d.fnIdInput.trim().length > 0) {
      return d.fnIdInput;
    }
    if (d.lanInput.trim().length > 0) {
      return d.lanInput;
    }
    if (d.publicIpInput.trim().length > 0) {
      return d.publicIpInput;
    }
    if (d.publicIpv6Input.trim().length > 0) {
      return d.publicIpv6Input;
    }
    return '';
  }

  private applyLanUrl(url: string): void {
    if (url.length === 0) {
      return;
    }
    const parts = parseNormalizedBaseUrl(url);
    if (parts !== null && parts.useBracket) {
      if (this.pendingEndpointLanIpv6Url.length === 0) {
        this.pendingEndpointLanIpv6Url = url;
      }
      return;
    }
    if (this.pendingEndpointLanUrl.length === 0) {
      this.pendingEndpointLanUrl = url;
    }
  }

  private applyPublicUrl(url: string): void {
    if (url.length === 0 || isFnRelayBaseUrl(url)) {
      return;
    }
    const parts = parseNormalizedBaseUrl(url);
    const host = parts !== null ? parts.host : '';
    if (host.length > 0 && isIpLiteralHost(host)) {
      if (parts !== null && parts.useBracket) {
        if (this.pendingEndpointPublicIpv6Url.length === 0) {
          this.pendingEndpointPublicIpv6Url = url;
        }
      } else if (this.pendingEndpointPublicIpUrl.length === 0) {
        this.pendingEndpointPublicIpUrl = url;
      }
      return;
    }
    if (this.pendingEndpointPublicDomainUrl.length === 0) {
      this.pendingEndpointPublicDomainUrl = url;
    }
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
    longTokenFromWs?: string,
    machineIdFromWs?: string
  ): Promise<void> {
    /** 图库与登录用同一条地址；https 会话时把该地址记入自签证书信任列表。 */
    CertPolicy.addTrusted(fnWebViewBaseUrl(base));
    let longTok = longTokenFromWs !== undefined && longTokenFromWs.length > 0 ? longTokenFromWs : '';
    const fnId = this.parsedFnId();
    const slots = this.loginDirectSlots();
    const stored: StoredSession = {
      baseUrl: base,
      token: token,
      account: user,
      fnIdInput: fnId,
      domainInput: slots.domain,
      lanInput: slots.lan,
      publicIpInput: slots.publicIpv4,
      publicIpv6Input: slots.publicIpv6,
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
      openApiAuthxSecret: openApiAuthxSecret,
      machineId: usableNasMachineId(machineIdFromWs !== undefined ? machineIdFromWs : '')
    };

    let existing: StoredSession | null = null;
    const loadT0 = Date.now();
    try {
      existing = await SessionPreferences.load(ctx);
      fnDiagTiming(LOGIN_TAG, 'prefsLoad', Date.now() - loadT0);
    } catch (_e) {
      fnDiagTiming(LOGIN_TAG, 'prefsLoad throw', Date.now() - loadT0);
      existing = null;
    }
    const accountChanged = existing === null || existing.account !== stored.account ||
      existing.baseUrl !== stored.baseUrl;
    if (accountChanged) {
      GalleryTimelineRefreshStore.bump();
      stopGalleryVideoLanPrefetch();
    }
    // 换账号不得沿用上一用户的相册根；同账号才保留，避免进错库再重拉。
    if (existing !== null && existing.albumParentGuid.length > 0 &&
      existing.account === stored.account && existing.baseUrl === stored.baseUrl) {
      stored.albumParentGuid = existing.albumParentGuid;
    }
    // 这次没问到机器码时，同一账号、同一入口才沿用上次的。换了 NAS 不能把旧编号带过去。
    if (stored.machineId.length === 0 && existing !== null && existing.account === stored.account &&
      nasFallbackIdentity(existing) === nasFallbackIdentity(stored)) {
      stored.machineId = usableNasMachineId(existing.machineId);
    }

    try {
      AppSession.setLoginPassword(pass);
      const formT0 = Date.now();
      await SessionPreferences.saveLoginFormDefaults(ctx, {
        fnIdInput: fnId,
        domainInput: stored.domainInput,
        lanInput: stored.lanInput,
        publicIpInput: stored.publicIpInput,
        publicIpv6Input: stored.publicIpv6Input,
        loginEndpointPreference: stored.loginEndpointPreference,
        username: stored.account,
        password: this.rememberPassword ? pass : '',
        useHttps: stored.useHttps,
        rememberPassword: this.rememberPassword,
        savedUsers: upsertSavedUser(this.savedUsers, stored.account, this.rememberPassword ? pass : '',
          this.rememberPassword)
      });
      fnDiagTiming(LOGIN_TAG, 'prefsSaveFormDefaults', Date.now() - formT0);
      // 口令单独封存一次：与上面 persistSavedUsersSealed 里的封存是同一份密码，
      // 两次 HUKS 会话 + 两次解封回环；单独计时以便确认是否值得合并。
      const pwdT0 = Date.now();
      await SessionPreferences.saveSessionPassword(ctx, pass);
      fnDiagTiming(LOGIN_TAG, 'prefsSaveSessionPassword', Date.now() - pwdT0);
      const saveT0 = Date.now();
      await SessionPreferences.save(ctx, stored);
      fnDiagTiming(LOGIN_TAG, 'prefsSaveSession', Date.now() - saveT0);
    } catch (e) {
      hilog.error(LOGIN_DOMAIN, LOGIN_TAG, 'SessionPreferences.save: %{public}s', String(e));
      fnDiagRecord('E', LOGIN_TAG, `SessionPreferences.save ${String(e)}`);
      this.errorText = '保存登录信息失败，请检查存储权限后重试';
      return;
    }
    AppSession.apply(stored);
    // 新登录没有 AppSession.restore 这一步，不主动加载的话备份设置缓存为空：
    // 「仅备份照片/使用流量备份/同步创建相册/重命名/目录偏好」会被当成默认值，
    // 要等下次冷启动才生效。这里登录成功后立刻读一次。
    const backupT0 = Date.now();
    try {
      await loadAlbumBackupSettings(ctx);
      fnDiagTiming(LOGIN_TAG, 'loadAlbumBackupSettings', Date.now() - backupT0);
    } catch (e) {
      fnDiagTiming(LOGIN_TAG, 'loadAlbumBackupSettings throw', Date.now() - backupT0);
      fnDiagError('Login', 'loadAlbumBackupSettings fail', e);
    }
    // 跳转前清空密码框，降低系统根据「提交后仍带密文的输入框」关联保险箱更新提示的概率
    this.password = '';
    this.leaveToHome();
  }

  /**
   * 登录完成 → 首页：先淡出登录表单，再跳转。
   * router.replaceUrl 是硬切，页面转场不一定生效，这里自己接一段淡出，
   * 首页侧再用 fromLogin 参数做入场动画（见 Home.onDidBuild）。
   */
  private leaveToHome(): void {
    if (this.leavingToHome) {
      return;
    }
    this.leavingToHome = true;
    this.getUIContext().animateTo({
      duration: FN_LOGIN_EXIT_FADE_MS,
      curve: FN_LOGIN_EXIT_FADE_CURVE
    }, (): void => {
      this.loginFadeOpacity = 0;
    });
    setTimeout((): void => {
      this.getUIContext().getRouter().replaceUrl({
        url: 'pages/Home',
        params: {
          fromLogin: true
        }
      }).catch((): void => {
        fnDiagRecord('E', LOGIN_TAG, 'navigate to home failed');
        // 跳转失败：表单已淡到透明，必须恢复显示并允许再次登录
        this.leavingToHome = false;
        this.getUIContext().animateTo({
          duration: FN_LOGIN_EXIT_FADE_MS,
          curve: FN_LOGIN_EXIT_FADE_CURVE
        }, (): void => {
          this.loginFadeOpacity = 1;
        });
        this.errorText = '进入首页失败，请重试';
      });
    }, FN_LOGIN_EXIT_FADE_MS + 20);
  }

  private async finishWsLoginSuccess(
    ctx: common.UIAbilityContext,
    server: string,
    user: string,
    pass: string,
    token: string,
    signKeyB64: string,
    longToken?: string,
    machineId?: string
  ): Promise<void> {
    if (signKeyB64.length === 0) {
      fnDiagRecord('E', LOGIN_TAG, 'ws login ok but sign key missing');
      this.errorText = '登录成功但未拿到签名密钥，请重试';
      return;
    }
    await this.persistSessionAndGoHome(
      ctx, server, user, pass, token, signKeyB64, token, signKeyB64, longToken, machineId);
  }

  /**
   * 仅 WebSocket 登录。
   * @returns true 调用方应停止（成功 / 2FA / 证书对话框 / 不可换路的错误）
   */
  private async attemptLoginWebSocketOnly(
    ctx: common.UIAbilityContext,
    server: string,
    user: string,
    pass: string,
    promptCert: boolean = true
  ): Promise<boolean> {
    const trusted = CertPolicy.isTrusted(server);
    const didT0 = Date.now();
    const deviceId = await SessionPreferences.ensureWsDeviceId(ctx);
    fnDiagTiming(LOGIN_TAG, 'ensureWsDeviceId', Date.now() - didT0);
    const wsT0 = Date.now();
    const wsRes = await fnWsLogin(server, user, pass, trusted, deviceId);
    fnDiagTiming(LOGIN_TAG, `wsLogin ${fnWsStopReason(wsRes)} ${fnDiagMaskUrl(server)}`, Date.now() - wsT0);
    if (wsRes.success === true && wsRes.token !== undefined && wsRes.token.length > 0) {
      hilog.info(LOGIN_DOMAIN, LOGIN_TAG, 'login via WebSocket ok %{public}s', fnDiagMaskUrl(server));
      const sk = wsRes.signKeyB64 !== undefined && wsRes.signKeyB64.length > 0 ? wsRes.signKeyB64 : '';
      const lt = wsRes.longToken !== undefined && wsRes.longToken.length > 0 ? wsRes.longToken : undefined;
      const mid = wsRes.machineId !== undefined ? wsRes.machineId : '';
      await this.finishWsLoginSuccess(ctx, server, user, pass, wsRes.token, sk, lt, mid);
      return true;
    }
    if (wsRes.requires2fa === true) {
      const at = wsRes.accessToken !== undefined ? wsRes.accessToken : '';
      if (at.length === 0) {
        fnDiagRecord('E', LOGIN_TAG, '2fa challenge token missing');
        this.errorText = '需要双重验证但未收到挑战令牌，请重试';
        return true;
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
      return true;
    }
    if (wsRes.requires2faSetup === true) {
      this.errorText =
        wsRes.message !== undefined && wsRes.message.length > 0
          ? wsRes.message
          : '该账号需在飞牛网页端先绑定双重验证';
      return true;
    }
    if (wsRes.certificateError === true && !trusted && promptCert) {
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
          return await this.attemptLoginWebSocketOnly(ctx, server, user, pass, true);
        }
        this.errorText = '已取消信任证书';
      } catch (e) {
        fnDiagRecord('W', LOGIN_TAG, `cert trust dialog error ${String(e)}`);
        this.errorText = '已取消信任证书';
      }
      return true;
    }
    this.errorText =
      wsRes.message !== undefined && wsRes.message.length > 0 ? wsRes.message : 'WebSocket 登录失败';
    if (this.errorText.length > 0) {
      hilog.warn(LOGIN_DOMAIN, LOGIN_TAG, 'WS login: %{public}s', fnLoginMaskHosts(this.errorText));
      fnDiagRecord('W', LOGIN_TAG, `WS login ${fnLoginMaskHosts(this.errorText)}`);
    }
    return !shouldTryNextLoginEndpoint(wsRes);
  }

  /**
   * 记录一步的耗时；异常也记录后原样抛出。
   * 登录链上每一步都是串行阻塞，埋点齐了才能判断慢在哪一环。
   */
  private async timedStep<T>(name: string, step: () => Promise<T>): Promise<T> {
    const t0 = Date.now();
    try {
      const r = await step();
      fnDiagTiming(LOGIN_TAG, name, Date.now() - t0);
      return r;
    } catch (e) {
      fnDiagTiming(LOGIN_TAG, `${name} throw`, Date.now() - t0);
      throw e as Error;
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
    const fnId: string = this.parsedFnId();
    const slots: DirectNasAddressSlots = this.loginDirectSlots();
    const lanRaw: string = slots.lan;
    const publicDomainRaw: string = slots.domain;
    const publicIpRaw: string = slots.publicIpv4;
    const publicIpv6Raw: string = slots.publicIpv6;
    const hasAddr = fnId.length > 0 || publicDomainRaw.length > 0 || lanRaw.length > 0 ||
      publicIpRaw.length > 0 || publicIpv6Raw.length > 0;
    if (!hasAddr || this.username.trim().length === 0 || this.password.length === 0) {
      this.errorText = '请填写 FN ID、IP 或公网域名，以及用户名和密码';
      return;
    }
    this.loading = true;
    const flowT0 = Date.now();
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

      if (publicDomainRaw.length > 0) {
        this.applyPublicUrl(normalizeUserServerUrl(publicDomainRaw, this.useHttps));
      }
      if (publicIpRaw.length > 0) {
        this.applyPublicUrl(normalizeUserServerUrl(publicIpRaw, this.useHttps));
      }
      if (publicIpv6Raw.length > 0) {
        this.applyPublicUrl(normalizeUserServerUrl(publicIpv6Raw, this.useHttps));
      }
      if (lanRaw.length > 0) {
        this.applyLanUrl(normalizeUserServerUrl(lanRaw, this.useHttps));
      }

      // 仅在填写了 FN ID 时走 FN Connect；手填地址优先于云端结果
      if (fnId.length > 0) {
        const looked = await this.timedStep('lookupFnConnect', (): Promise<FnConnectLookupResult> => {
          return lookupFnConnect(fnId, this.useHttps);
        });
        const hasAny = looked.publicDomainServer.length > 0 || looked.publicIpServer.length > 0 ||
          looked.lanServer.length > 0 || looked.relayServer.length > 0;
        if (!looked.ok || !hasAny) {
          const lookupMsg: string = looked.message.length > 0 ? looked.message : 'no endpoint';
          fnDiagRecord('E', LOGIN_TAG, `fn connect lookup failed ${fnLoginMaskHosts(lookupMsg)}`);
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

      const selected = await this.timedStep('selectAmongEndpointPool', (): Promise<LoginEndpointSelectionResult> => {
        return selectAmongEndpointPool({
          lanIpv4Url: this.pendingEndpointLanUrl,
          lanIpv6Url: this.pendingEndpointLanIpv6Url,
          publicDomainUrl: this.pendingEndpointPublicDomainUrl,
          publicIpv4Url: this.pendingEndpointPublicIpUrl,
          publicIpv6Url: this.pendingEndpointPublicIpv6Url,
          relayUrl: this.pendingEndpointRelayUrl
        }, this.endpointPreference);
      });
      if (selected.server.length === 0 || !selected.selectedOk) {
        fnDiagRecord('E', LOGIN_TAG, 'all endpoints unreachable');
        this.errorText = selected.summary.length > 0
          ? selected.summary
          : '已填写的地址均不可达';
        return;
      }
      if (selected.preferredPublicUrl.length > 0) {
        this.pendingEndpointPublicUrl = selected.preferredPublicUrl;
      }
      let extraRelay = '';
      if (this.endpointPreference === LOGIN_ENDPOINT_PREF_AUTO
        || this.endpointPreference === LOGIN_ENDPOINT_PREF_BANDWIDTH
        || this.endpointPreference === LOGIN_ENDPOINT_PREF_LATENCY
        || this.endpointPreference === LOGIN_ENDPOINT_PREF_PUBLIC
        || this.endpointPreference.length === 0) {
        extraRelay = this.pendingEndpointRelayUrl;
      }
      const servers = orderedWsLoginServers(selected, extraRelay);
      const redirectServer = await this.timedStep('resolveLoginRedirectServer', (): Promise<string> => {
        return resolveLoginRedirectServer(selected.server);
      });
      if (redirectServer.length > 0 && redirectServer !== selected.server) {
        for (let i = servers.length - 1; i >= 0; i--) {
          if (servers[i] === redirectServer) {
            servers.splice(i, 1);
          }
        }
        servers.unshift(redirectServer);
        fnDiagRecord('I', LOGIN_TAG,
          `login redirect ${fnDiagMaskUrl(selected.server)} -> ${fnDiagMaskUrl(redirectServer)}`);
      }
      const user = this.username.trim();
      const pass = this.password;
      for (let i = 0; i < servers.length; i++) {
        const last = i + 1 >= servers.length;
        hilog.info(LOGIN_DOMAIN, LOGIN_TAG, 'WS login try %{public}d/%{public}d %{public}s',
          i + 1, servers.length, fnDiagMaskUrl(servers[i]));
        fnDiagRecord('I', LOGIN_TAG,
          `WS login try ${i + 1}/${servers.length} ${fnDiagMaskUrl(servers[i])}`);
        const stop = await this.attemptLoginWebSocketOnly(ctx, servers[i], user, pass, last);
        if (stop) {
          return;
        }
      }
    } catch (e) {
      const msg = this.describeLoginError(e);
      const safeMsg: string = fnLoginMaskHosts(msg.length > 0 ? msg : 'unknown');
      hilog.error(LOGIN_DOMAIN, LOGIN_TAG, 'login flow: %{public}s', safeMsg);
      fnDiagRecord('E', LOGIN_TAG, `login flow ${safeMsg}`);
      this.errorText = msg.length > 0 ? `请求异常：${msg}` : '网络异常';
    } finally {
      fnDiagTiming(LOGIN_TAG, 'loginFlowTotal', Date.now() - flowT0);
      this.loading = false;
    }
  }

  private async on2faVerifyClick(): Promise<void> {
    this.errorText = '';
    const code = this.otpCode.trim();
    if (!/^\d{6}$/.test(code)) {
      fnDiagRecord('W', LOGIN_TAG, '2fa invalid');
      this.errorText = '请输入身份验证器中的 6 位动态验证码';
      return;
    }
    if (this.pendingAccessToken.length === 0 || this.pendingServer.length === 0 || this.pendingDeviceId.length === 0) {
      fnDiagRecord('W', LOGIN_TAG, '2fa expired');
      this.errorText = '验证会话已失效，请返回重新登录';
      this.show2faStep = false;
      return;
    }
    this.loading = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const trusted = CertPolicy.isTrusted(this.pendingServer);
    const faT0 = Date.now();
    try {
      const wsRes = await fnWs2faVerify(
        this.pendingServer,
        this.pendingAccessToken,
        code,
        this.trustDevice,
        trusted,
        this.pendingDeviceId
      );
      fnDiagTiming(LOGIN_TAG, `ws2faVerify ${fnWsStopReason(wsRes)}`, Date.now() - faT0);
      if (wsRes.success === true && wsRes.token !== undefined && wsRes.token.length > 0) {
        const sk = wsRes.signKeyB64 !== undefined && wsRes.signKeyB64.length > 0 ? wsRes.signKeyB64 : '';
        const lt = wsRes.longToken !== undefined && wsRes.longToken.length > 0 ? wsRes.longToken : undefined;
        const mid = wsRes.machineId !== undefined ? wsRes.machineId : '';
        await this.finishWsLoginSuccess(
          ctx, this.pendingServer, this.pendingUser, this.pendingPass, wsRes.token, sk, lt, mid);
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
      fnDiagRecord('E', LOGIN_TAG, `2fa verify error ${fnLoginMaskHosts(msg.length > 0 ? msg : 'unknown')}`);
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
      .backgroundColor(this.pageBg)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private loginPanelGlow() {
    Stack() {
      Column()
        .width(180)
        .height(180)
        .borderRadius(90)
        .backgroundColor($r('app.color.login_glow_blue_core'))
        .opacity(0.42)
        .position({ x: '6%', y: '8%' })

      Column()
        .width(150)
        .height(150)
        .borderRadius(75)
        .backgroundColor($r('app.color.login_glow_blue_soft'))
        .opacity(0.36)
        .position({ x: '52%', y: '28%' })

      Column()
        .width(130)
        .height(130)
        .borderRadius(65)
        .backgroundColor($r('app.color.brand_primary'))
        .opacity(0.28)
        .position({ x: '18%', y: '58%' })
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.loginPanelRadiusVp())
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

  @Builder
  private usernamePasswordFieldsEven() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Column() {
          FnLoginTextField({
            seedText: this.username,
            placeholder: $r('app.string.hint_username'),
            inputType: InputType.USER_NAME,
            fieldEnabled: true,
            onChange: (v: string): void => {
              this.username = v;
            }
          })
        }
        .layoutWeight(1)
        this.savedUserMenuButton()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      FnLoginTextField({
        seedText: this.password,
        placeholder: $r('app.string.hint_password'),
        inputType: InputType.Normal,
        maskAsPassword: true,
        fieldEnabled: !this.show2faStep,
        onChange: (v: string): void => {
          this.password = v;
        }
      })
    }
    .width('100%')
    .id('fn_login_creds_even')
  }

  @Builder
  private usernamePasswordFieldsOdd() {
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Column() {
          FnLoginTextField({
            seedText: this.username,
            placeholder: $r('app.string.hint_username'),
            inputType: InputType.USER_NAME,
            fieldEnabled: true,
            onChange: (v: string): void => {
              this.username = v;
            }
          })
        }
        .layoutWeight(1)
        this.savedUserMenuButton()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      FnLoginTextField({
        seedText: this.password,
        placeholder: $r('app.string.hint_password'),
        inputType: InputType.Normal,
        maskAsPassword: true,
        fieldEnabled: !this.show2faStep,
        onChange: (v: string): void => {
          this.password = v;
        }
      })
    }
    .width('100%')
    .id('fn_login_creds_odd')
  }

  @Builder
  private savedUserMenuButton() {
    if (this.savedUserNames.length > 0) {
      Button({ type: ButtonType.Normal, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(18)
          .fontColor([fnResolvedTextSecondary(this.themeTextSecondary)])
      }
      .width(LOGIN_FIELD_HEIGHT_VP)
      .height(LOGIN_FIELD_HEIGHT_VP)
      .borderRadius($r('app.float.radius_medium'))
      .borderWidth(1)
      .borderColor($r('app.color.login_input_border'))
      .backgroundColor($r('app.color.login_input_fill'))
      .enabled(!this.show2faStep)
      .bindMenu(this.userMenuVisible, this.savedUserMenuBuilder, fnHdsBindMenuOptions(
        Placement.BottomRight,
        (): void => {
          this.userMenuVisible = false;
        }
      ))
      .onClick((): void => {
        this.userMenuVisible = true;
      })
    }
  }

  @Builder
  private loginForegroundPanel() {
    Stack() {
      this.loginPanelGlow()

      Column()
        .width('100%')
        .height('100%')
        .borderRadius(this.loginPanelRadiusVp())
        .backgroundColor($r('app.color.login_card_fill'))
        .hitTestBehavior(HitTestMode.None)

      Column() {
        Scroll() {
          Column({ space: 12 }) {
            this.loginHeroSection()
            this.loginFormBody()
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .constraintSize({ minHeight: 0 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .nestedScroll({
          scrollForward: NestedScrollMode.SELF_ONLY,
          scrollBackward: NestedScrollMode.SELF_ONLY
        })
        .align(Alignment.TopStart)

        this.loginFormFooter()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.loginPanelRadiusVp())
    .clip(true)
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

      this.loginField(this.domainInput, $r('app.string.hint_public_domain'), InputType.Normal, !this.show2faStep,
        (v: string) => {
          this.domainInput = v;
        })

      Text($r('app.string.fnid_hint'))
        .fontSize(12)
        .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
        .width('100%')

      Row() {
        Text($r('app.string.use_https'))
          .fontSize(16)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.useHttps })
          .selectedColor(this.accent)
          .onChange((on: boolean) => {
            this.useHttps = on;
          })
      }
      .width('100%')
      .height(LOGIN_FIELD_HEIGHT_VP)
      .padding({ left: 4, right: 4 })

      if (this.loginTargetPreview().length > 0) {
        Text(this.loginTargetPreview())
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .width('100%')
          .lineHeight(18)
      }

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
      if ((this.credentialGen & 1) === 0) {
        this.usernamePasswordFieldsEven()
      } else {
        this.usernamePasswordFieldsOdd()
      }

      if (!this.show2faStep) {
        Row() {
          Text($r('app.string.save_password'))
            .fontSize(16)
            .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
          Blank()
          if ((this.rememberToggleGen & 1) === 0) {
            Toggle({ type: ToggleType.Switch, isOn: this.rememberPassword })
              .selectedColor(this.accent)
              .onChange((on: boolean) => {
                this.rememberPassword = on;
              })
          } else {
            Toggle({ type: ToggleType.Switch, isOn: this.rememberPassword })
              .selectedColor(this.accent)
              .onChange((on: boolean) => {
                this.rememberPassword = on;
              })
          }
        }
        .width('100%')
        .height(LOGIN_FIELD_HEIGHT_VP)
        .padding({ left: 4, right: 4 })
      }

      if (this.show2faStep) {
        Text($r('app.string.twofa_step_hint'))
          .fontSize(14)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .width('100%')

        this.loginField(this.otpCode, $r('app.string.hint_otp'), InputType.Number, true, (v: string) => {
          this.otpCode = v.replace(/[^\d]/g, '').substring(0, 6);
        }, 6)

        Row() {
          Text($r('app.string.trust_device'))
            .fontSize(15)
            .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.trustDevice })
            .selectedColor(this.accent)
            .onChange((on: boolean) => {
              this.trustDevice = on;
            })
        }
        .width('100%')
        .height(LOGIN_FIELD_HEIGHT_VP)
        .padding({ left: 4, right: 4 })
      }
      }
      .width('100%')
      }
    }
    .width('100%')
  }

  @Builder
  private loginFormFooter() {
    Column({ space: 10 }) {
      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontColor(Color.Red)
          .fontSize(13)
          .lineHeight(18)
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Text($r('app.string.diag_log_entry_title'))
        .fontSize(13)
        .fontColor(this.accent)
        .width('100%')
        .opacity(this.loading ? 0.45 : 1)
        .onClick((): void => {
          if (this.loading) {
            return;
          }
          openFeedbackPage(this.getUIContext());
        })

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
    .padding({ left: 20, right: 20, top: 4, bottom: 20 })
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
        .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        .textAlign(TextAlign.Center)
        .width('100%')

      Text($r('app.string.login_subtitle'))
        .fontSize(14)
        .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
        .textAlign(TextAlign.Center)
        .width('100%')

      Text($r('app.string.privacy_policy_title'))
        .fontSize(13)
        .fontColor(this.accent)
        .textAlign(TextAlign.Center)
        .width('100%')
        .onClick((): void => {
          openPrivacyPolicyPage(this.getUIContext());
        })
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
        bottom: this.loginBottomInsetVp()
      })
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      // 登录成功后淡出表单；背景保持不透明，避免跳转瞬间闪黑
      .opacity(this.loginFadeOpacity)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    if (this.leavingToHome) {
      // 跳首页时由 leaveToHome() 自己接管淡出，避免与页面级转场叠加成双重淡出
      PageTransitionEnter({ type: RouteType.None, duration: 0 })
      PageTransitionExit({ type: RouteType.None, duration: 0 })
    } else {
      PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
        .opacity(0)
        .translate({ x: 0, y: 28 });
      PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
        .opacity(0)
        .translate({ x: 0, y: -16 });
    }
  }
}
