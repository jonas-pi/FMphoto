/**
 * 运行时识别当前 NAS 连接（公网 / 内网），并支持在已登录状态下切换。
 * 中继暂不开放（官方隧道未对第三方提供可用 WSS）。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { SessionPreferences, StoredSession } from '../auth/SessionPreferences';
import { CertPolicy } from './CertPolicy';
import { FnHttpClient } from './FnHttpClient';
import { fnWsLogin } from './FnWsLogin';
import {
  LOGIN_ENDPOINT_PREF_LAN,
  LOGIN_ENDPOINT_PREF_PUBLIC,
  LOGIN_ENDPOINT_PREF_RELAY,
  LoginEndpointPool,
  selectAmongEndpointPool
} from './LoginEndpointSelector';
import { splitOrigin } from './fnHttpClient/FnHttpClientCommon';
import { preferPublicEndpointUrl } from './PublicDns';
import { isFnRelayBaseUrl as isFnRelayBaseUrlImpl, normalizeFnRelayBaseUrl } from './FnConnectApi';
import {
  fnWebViewBaseUrl,
  isIpLiteralHost,
  normalizeServerUrl,
  parseNormalizedBaseUrl
} from './ServerUrl';

const DOMAIN = 0xFF00;
const TAG = 'LoginEndpointSwitch';

export const ENDPOINT_KIND_SINGLE = 'single';
export const ENDPOINT_KIND_UNKNOWN = 'unknown';

export interface EndpointConnectionInfo {
  kind: string;
  label: string;
  addressText: string;
  canSwitch: boolean;
  /** 是否有公网直连可切换 */
  hasPublic: boolean;
  /** 是否有内网可切换 */
  hasLan: boolean;
  /** 是否有中继可切换（暂固定 false） */
  hasRelay: boolean;
  publicUrl: string;
  lanUrl: string;
  lanIpv6Url: string;
  publicIpv6Url: string;
  relayUrl: string;
  activeUrl: string;
}

export interface StoredEndpointUrls {
  publicUrl: string;
  publicDomainUrl: string;
  publicIpv4Url: string;
  publicIpv6Url: string;
  lanIpv4Url: string;
  lanIpv6Url: string;
  lanUrl: string;
  relayUrl: string;
}

export interface EndpointSwitchResult {
  ok: boolean;
  message: string;
  certificateError?: boolean;
  targetUrl?: string;
}

export function isFnRelayBaseUrl(baseUrl: string): boolean {
  return isFnRelayBaseUrlImpl(baseUrl);
}

function endpointKindLabel(kind: string): string {
  if (kind === LOGIN_ENDPOINT_PREF_LAN) {
    return '内网';
  }
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC) {
    return '公网';
  }
  if (kind === LOGIN_ENDPOINT_PREF_RELAY) {
    return '中继';
  }
  if (kind === ENDPOINT_KIND_SINGLE) {
    return '当前地址';
  }
  return '未知';
}

function compactAddressFromUrl(baseUrl: string, fallbackInput: string): string {
  const input = fallbackInput.trim();
  if (input.length > 0) {
    return input;
  }
  let u = baseUrl.trim();
  if (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  // 中继门户显示 fnos.net/{fnId}
  if (isFnRelayBaseUrlImpl(u)) {
    return u.replace(/^https?:\/\//i, '');
  }
  const origin = splitOrigin(u);
  if (origin.length === 0) {
    return baseUrl;
  }
  return origin.replace(/^https?:\/\//, '');
}

function sameEndpoint(a: string, b: string): boolean {
  if (a.length === 0 || b.length === 0) {
    return false;
  }
  const na = a.trim().replace(/\/$/, '');
  const nb = b.trim().replace(/\/$/, '');
  if (na === nb) {
    return true;
  }
  // 中继：比较完整路径（fnos.net/{fnId}），不能只用 origin
  if (isFnRelayBaseUrlImpl(na) || isFnRelayBaseUrlImpl(nb)) {
    return na.toLowerCase() === nb.toLowerCase();
  }
  return splitOrigin(na) === splitOrigin(nb);
}

function resolveKindByUrl(
  currentUrl: string,
  publicUrl: string,
  publicDomainUrl: string,
  publicIpUrl: string,
  publicIpv6Url: string,
  lanUrl: string,
  lanIpv6Url: string,
  relayUrl: string
): string {
  const current = currentUrl.trim();
  if (current.length === 0) {
    return ENDPOINT_KIND_UNKNOWN;
  }
  if (lanUrl.length > 0 && sameEndpoint(current, lanUrl)) {
    return LOGIN_ENDPOINT_PREF_LAN;
  }
  if (lanIpv6Url.length > 0 && sameEndpoint(current, lanIpv6Url)) {
    return LOGIN_ENDPOINT_PREF_LAN;
  }
  if (relayUrl.length > 0 && sameEndpoint(current, relayUrl)) {
    return LOGIN_ENDPOINT_PREF_RELAY;
  }
  if (publicDomainUrl.length > 0 && sameEndpoint(current, publicDomainUrl)) {
    return LOGIN_ENDPOINT_PREF_PUBLIC;
  }
  if (publicIpUrl.length > 0 && sameEndpoint(current, publicIpUrl)) {
    return LOGIN_ENDPOINT_PREF_PUBLIC;
  }
  if (publicIpv6Url.length > 0 && sameEndpoint(current, publicIpv6Url)) {
    return LOGIN_ENDPOINT_PREF_PUBLIC;
  }
  if (publicUrl.length > 0 && sameEndpoint(current, publicUrl)) {
    return LOGIN_ENDPOINT_PREF_PUBLIC;
  }
  if (isFnRelayBaseUrl(current)) {
    return LOGIN_ENDPOINT_PREF_RELAY;
  }
  return ENDPOINT_KIND_UNKNOWN;
}

function looksLikeIpv6Url(baseUrl: string): boolean {
  const parts = parseNormalizedBaseUrl(baseUrl);
  return parts !== null && parts.useBracket;
}

/**
 * 从会话字段或旧版 domain/lan 输入推导可切换地址。
 * 公网首选：域名优先于 IP。
 */
export function resolveStoredEndpointUrls(stored: StoredSession): StoredEndpointUrls {
  let publicDomainUrl = stored.endpointPublicDomainUrl.trim();
  let publicIpv4Url = stored.endpointPublicIpUrl.trim();
  let publicIpv6Url = stored.endpointPublicIpv6Url.trim();
  let publicUrl = stored.endpointPublicUrl.trim();
  let lanIpv4Url = stored.endpointLanUrl.trim();
  let lanIpv6Url = stored.endpointLanIpv6Url.trim();
  let relayUrl = stored.endpointRelayUrl.trim();

  if (publicDomainUrl.length === 0 && publicIpv4Url.length === 0 && publicUrl.length === 0 &&
    lanIpv4Url.length === 0 && lanIpv6Url.length === 0 && publicIpv6Url.length === 0 &&
    relayUrl.length === 0) {
    const fromDomain = normalizeServerUrl(stored.domainInput, stored.useHttps);
    const fromLan = normalizeServerUrl(stored.lanInput, stored.useHttps);
    if (fromDomain.length > 0) {
      if (isFnRelayBaseUrl(fromDomain)) {
        relayUrl = fromDomain;
      } else {
        const parts = parseNormalizedBaseUrl(fromDomain);
        const host = parts !== null ? parts.host : '';
        if (host.length > 0 && isIpLiteralHost(host)) {
          if (parts !== null && parts.useBracket) {
            publicIpv6Url = fromDomain;
          } else {
            publicIpv4Url = fromDomain;
          }
        } else {
          publicDomainUrl = fromDomain;
        }
      }
    }
    if (fromLan.length > 0 && looksLikeIpv6Url(fromLan)) {
      lanIpv6Url = fromLan;
    } else {
      lanIpv4Url = fromLan;
    }
  }

  if (publicIpv6Url.length === 0 && publicIpv4Url.length > 0 && looksLikeIpv6Url(publicIpv4Url)) {
    publicIpv6Url = publicIpv4Url;
    publicIpv4Url = '';
  }
  if (lanIpv6Url.length === 0 && lanIpv4Url.length > 0 && looksLikeIpv6Url(lanIpv4Url)) {
    lanIpv6Url = lanIpv4Url;
    lanIpv4Url = '';
  }

  if (publicUrl.length === 0) {
    publicUrl = preferPublicEndpointUrl(publicDomainUrl,
      publicIpv4Url.length > 0 ? publicIpv4Url : publicIpv6Url);
  }
  if (relayUrl.length > 0 && isFnRelayBaseUrl(relayUrl)) {
    relayUrl = normalizeFnRelayBaseUrl(relayUrl);
  }
  const lanUrl = lanIpv4Url.length > 0 ? lanIpv4Url : lanIpv6Url;
  return {
    publicUrl,
    publicDomainUrl,
    publicIpv4Url,
    publicIpv6Url,
    lanIpv4Url,
    lanIpv6Url,
    lanUrl,
    relayUrl: ''
  };
}

export function endpointPoolFromStored(stored: StoredSession): LoginEndpointPool {
  const urls = resolveStoredEndpointUrls(stored);
  return {
    lanIpv4Url: urls.lanIpv4Url,
    lanIpv6Url: urls.lanIpv6Url,
    publicDomainUrl: urls.publicDomainUrl,
    publicIpv4Url: urls.publicIpv4Url,
    publicIpv6Url: urls.publicIpv6Url
  };
}

function countDistinctEndpoints(urls: StoredEndpointUrls): number {
  const seen: string[] = [];
  const pushUnique = (u: string): void => {
    if (u.length === 0) {
      return;
    }
    const origin = splitOrigin(u);
    const key = (origin.length > 0 ? origin : u).toLowerCase();
    for (let i = 0; i < seen.length; i++) {
      if (seen[i] === key) {
        return;
      }
    }
    seen.push(key);
  };
  pushUnique(urls.publicDomainUrl);
  pushUnique(urls.publicIpv4Url);
  pushUnique(urls.publicIpv6Url);
  pushUnique(urls.lanIpv4Url);
  pushUnique(urls.lanIpv6Url);
  return seen.length;
}

export function resolveEndpointConnectionInfo(stored: StoredSession | null): EndpointConnectionInfo {
  if (stored === null) {
    return {
      kind: ENDPOINT_KIND_UNKNOWN,
      label: '未登录',
      addressText: '',
      canSwitch: false,
      hasPublic: false,
      hasLan: false,
      hasRelay: false,
      publicUrl: '',
      lanUrl: '',
      lanIpv6Url: '',
      publicIpv6Url: '',
      relayUrl: '',
      activeUrl: ''
    };
  }
  const urls = resolveStoredEndpointUrls(stored);
  const publicUrl = urls.publicUrl;
  const publicDomainUrl = urls.publicDomainUrl;
  const publicIpUrl = urls.publicIpv4Url;
  const lanUrl = urls.lanUrl;
  const activeUrl = stored.baseUrl.trim();
  const distinct = countDistinctEndpoints(urls);
  const canSwitch = distinct >= 2;
  let kind = resolveKindByUrl(
    activeUrl, publicUrl, publicDomainUrl, publicIpUrl, urls.publicIpv6Url,
    lanUrl, urls.lanIpv6Url, ''
  );
  if (kind === LOGIN_ENDPOINT_PREF_RELAY) {
    kind = ENDPOINT_KIND_UNKNOWN;
  }
  if (!canSwitch) {
    kind = ENDPOINT_KIND_SINGLE;
  } else if (kind === ENDPOINT_KIND_UNKNOWN) {
    if (lanUrl.length > 0 && sameEndpoint(activeUrl, lanUrl)) {
      kind = LOGIN_ENDPOINT_PREF_LAN;
    } else if (urls.lanIpv6Url.length > 0 && sameEndpoint(activeUrl, urls.lanIpv6Url)) {
      kind = LOGIN_ENDPOINT_PREF_LAN;
    } else if (publicUrl.length > 0) {
      kind = LOGIN_ENDPOINT_PREF_PUBLIC;
    } else {
      kind = LOGIN_ENDPOINT_PREF_LAN;
    }
  }
  let addressText = activeUrl;
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC) {
    const showPublic = publicDomainUrl.length > 0 ? publicDomainUrl : publicUrl;
    addressText = compactAddressFromUrl(showPublic, stored.domainInput);
  } else if (kind === LOGIN_ENDPOINT_PREF_LAN) {
    const showLan = sameEndpoint(activeUrl, urls.lanIpv6Url) ? urls.lanIpv6Url : lanUrl;
    addressText = compactAddressFromUrl(showLan, stored.lanInput);
  } else if (activeUrl.length > 0) {
    addressText = compactAddressFromUrl(
      activeUrl,
      stored.domainInput.length > 0 ? stored.domainInput : stored.lanInput
    );
  }
  const hasPublic = publicUrl.length > 0 || publicDomainUrl.length > 0 ||
    publicIpUrl.length > 0 || urls.publicIpv6Url.length > 0;
  const hasLan = lanUrl.length > 0 || urls.lanIpv6Url.length > 0;
  return {
    kind,
    label: endpointKindLabel(kind),
    addressText,
    canSwitch,
    hasPublic,
    hasLan,
    hasRelay: false,
    publicUrl: publicUrl.length > 0 ? publicUrl : preferPublicEndpointUrl(publicDomainUrl, publicIpUrl),
    lanUrl,
    lanIpv6Url: urls.lanIpv6Url,
    publicIpv6Url: urls.publicIpv6Url,
    relayUrl: '',
    activeUrl
  };
}

async function pickUrlForKind(stored: StoredSession, targetKind: string): Promise<string> {
  const pool = endpointPoolFromStored(stored);
  if (targetKind === LOGIN_ENDPOINT_PREF_LAN) {
    const selected = await selectAmongEndpointPool(pool, LOGIN_ENDPOINT_PREF_LAN);
    return selected.server;
  }
  if (targetKind === LOGIN_ENDPOINT_PREF_PUBLIC) {
    const selected = await selectAmongEndpointPool(pool, LOGIN_ENDPOINT_PREF_PUBLIC);
    return selected.server;
  }
  return '';
}

async function finishSwitchSession(
  ctx: common.UIAbilityContext,
  stored: StoredSession,
  newBaseUrl: string,
  token: string,
  signKeyB64: string,
  longToken?: string
): Promise<EndpointSwitchResult> {
  if (signKeyB64.length === 0) {
    return { ok: false, message: '切换成功但未拿到签名密钥' };
  }
  CertPolicy.addTrusted(fnWebViewBaseUrl(newBaseUrl));
  let longTok = longToken !== undefined && longToken.length > 0 ? longToken : '';
  if (longTok.length === 0) {
    const probeClient = new FnHttpClient(newBaseUrl, token, '', signKeyB64);
    try {
      longTok = await probeClient.fetchFnosLongTokenProbe(14000);
    } catch (_e) {
      longTok = '';
    }
  }
  stored.baseUrl = newBaseUrl;
  stored.token = token;
  stored.wsSignKeyB64 = signKeyB64;
  stored.openApiAuthxKey = token;
  stored.openApiAuthxSecret = signKeyB64;
  stored.fnosLongToken = longTok;
  stored.trustedHosts = CertPolicy.dumpAll();
  AppSession.apply(stored);
  await SessionPreferences.save(ctx, stored);
  hilog.info(DOMAIN, TAG, 'endpoint switched to %{public}s', newBaseUrl);
  return { ok: true, message: '已切换连接' };
}

export async function switchStoredLoginEndpointToUrl(
  ctx: common.UIAbilityContext,
  nextUrl: string,
  silentAlreadyCurrent: boolean = false
): Promise<EndpointSwitchResult> {
  const stored = AppSession.getStored();
  if (stored === null) {
    return { ok: false, message: '未登录' };
  }
  const target = nextUrl.trim();
  if (target.length === 0) {
    return { ok: false, message: '目标地址无效' };
  }
  if (sameEndpoint(stored.baseUrl, target)) {
    return {
      ok: true,
      message: silentAlreadyCurrent ? '' : '当前已是该连接'
    };
  }
  const defaults = await SessionPreferences.loadLoginFormDefaults(ctx);
  const pass = defaults.password;
  const user = stored.account.length > 0 ? stored.account : defaults.username;
  if (pass.length === 0 || user.length === 0) {
    return { ok: false, message: '缺少保存的登录凭据，请重新登录' };
  }
  const trusted = CertPolicy.isTrusted(target);
  const deviceId = await SessionPreferences.ensureWsDeviceId(ctx);
  const wsRes = await fnWsLogin(target, user, pass, trusted, deviceId);
  if (wsRes.requires2fa === true || wsRes.requires2faSetup === true) {
    return { ok: false, message: '切换需要双重验证，请返回登录页操作' };
  }
  if (wsRes.certificateError === true && !trusted) {
    return {
      ok: false,
      message: '目标地址证书未信任',
      certificateError: true,
      targetUrl: target
    };
  }
  if (wsRes.success !== true || wsRes.token === undefined || wsRes.token.length === 0) {
    const msg = wsRes.message !== undefined && wsRes.message.length > 0 ? wsRes.message : '切换连接失败';
    return { ok: false, message: msg };
  }
  const sk = wsRes.signKeyB64 !== undefined && wsRes.signKeyB64.length > 0 ? wsRes.signKeyB64 : '';
  const lt = wsRes.longToken !== undefined && wsRes.longToken.length > 0 ? wsRes.longToken : undefined;
  return finishSwitchSession(ctx, stored, target, wsRes.token, sk, lt);
}

export async function switchStoredLoginEndpoint(
  ctx: common.UIAbilityContext,
  targetKind: string
): Promise<EndpointSwitchResult> {
  const stored = AppSession.getStored();
  if (stored === null) {
    return { ok: false, message: '未登录' };
  }
  const info = resolveEndpointConnectionInfo(stored);
  if (!info.canSwitch) {
    return { ok: false, message: '未配置多地址，无法切换' };
  }
  const nextUrl = await pickUrlForKind(stored, targetKind);
  if (nextUrl.length === 0) {
    return { ok: false, message: '目标地址无效' };
  }
  return switchStoredLoginEndpointToUrl(ctx, nextUrl, false);
}
