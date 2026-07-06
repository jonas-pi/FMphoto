/**
 * 运行时识别当前 NAS 连接（公网域名 / 内网 IP），并支持在已登录状态下切换。
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
  LOGIN_ENDPOINT_PREF_PUBLIC
} from './LoginEndpointSelector';
import { splitOrigin } from './fnHttpClient/FnHttpClientCommon';
import { fnWebViewBaseUrl, normalizeServerUrl } from './ServerUrl';

const DOMAIN = 0xFF00;
const TAG = 'LoginEndpointSwitch';

export const ENDPOINT_KIND_SINGLE = 'single';
export const ENDPOINT_KIND_UNKNOWN = 'unknown';

export interface EndpointConnectionInfo {
  kind: string;
  label: string;
  addressText: string;
  canSwitch: boolean;
  publicUrl: string;
  lanUrl: string;
  activeUrl: string;
}

export interface EndpointSwitchResult {
  ok: boolean;
  message: string;
  certificateError?: boolean;
  targetUrl?: string;
}

function endpointKindLabel(kind: string): string {
  if (kind === LOGIN_ENDPOINT_PREF_LAN) {
    return '内网';
  }
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC) {
    return '公网';
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
  const origin = splitOrigin(baseUrl.trim());
  if (origin.length === 0) {
    return baseUrl;
  }
  return origin.replace(/^https?:\/\//, '');
}

function resolveKindByUrl(currentUrl: string, publicUrl: string, lanUrl: string): string {
  const current = currentUrl.trim();
  if (current.length === 0) {
    return ENDPOINT_KIND_UNKNOWN;
  }
  if (lanUrl.length > 0 && current === lanUrl) {
    return LOGIN_ENDPOINT_PREF_LAN;
  }
  if (publicUrl.length > 0 && current === publicUrl) {
    return LOGIN_ENDPOINT_PREF_PUBLIC;
  }
  const currentOrigin = splitOrigin(current);
  if (lanUrl.length > 0 && currentOrigin === splitOrigin(lanUrl)) {
    return LOGIN_ENDPOINT_PREF_LAN;
  }
  if (publicUrl.length > 0 && currentOrigin === splitOrigin(publicUrl)) {
    return LOGIN_ENDPOINT_PREF_PUBLIC;
  }
  return ENDPOINT_KIND_UNKNOWN;
}

export function resolveEndpointConnectionInfo(stored: StoredSession | null): EndpointConnectionInfo {
  if (stored === null) {
    return {
      kind: ENDPOINT_KIND_UNKNOWN,
      label: '未登录',
      addressText: '',
      canSwitch: false,
      publicUrl: '',
      lanUrl: '',
      activeUrl: ''
    };
  }
  const publicUrl = normalizeServerUrl(stored.domainInput, stored.useHttps);
  const lanUrl = normalizeServerUrl(stored.lanInput, stored.useHttps);
  const activeUrl = stored.baseUrl.trim();
  const hasDual = publicUrl.length > 0 && lanUrl.length > 0 && publicUrl !== lanUrl;
  let kind = resolveKindByUrl(activeUrl, publicUrl, lanUrl);
  if (!hasDual) {
    kind = ENDPOINT_KIND_SINGLE;
  } else if (kind === ENDPOINT_KIND_UNKNOWN) {
    kind = ENDPOINT_KIND_SINGLE;
  }
  let addressText = activeUrl;
  if (kind === LOGIN_ENDPOINT_PREF_PUBLIC) {
    addressText = compactAddressFromUrl(publicUrl, stored.domainInput);
  } else if (kind === LOGIN_ENDPOINT_PREF_LAN) {
    addressText = compactAddressFromUrl(lanUrl, stored.lanInput);
  } else if (activeUrl.length > 0) {
    addressText = compactAddressFromUrl(activeUrl, stored.domainInput.length > 0 ? stored.domainInput : stored.lanInput);
  }
  return {
    kind,
    label: endpointKindLabel(kind),
    addressText,
    canSwitch: hasDual,
    publicUrl,
    lanUrl,
    activeUrl
  };
}

function targetUrlForKind(info: EndpointConnectionInfo, targetKind: string): string {
  if (targetKind === LOGIN_ENDPOINT_PREF_LAN) {
    return info.lanUrl;
  }
  return info.publicUrl;
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
    return { ok: false, message: '未配置双地址，无法切换' };
  }
  const nextUrl = targetUrlForKind(info, targetKind);
  if (nextUrl.length === 0) {
    return { ok: false, message: '目标地址无效' };
  }
  if (info.activeUrl === nextUrl || splitOrigin(info.activeUrl) === splitOrigin(nextUrl)) {
    return { ok: true, message: '当前已是该连接' };
  }
  const defaults = await SessionPreferences.loadLoginFormDefaults(ctx);
  const pass = defaults.password;
  const user = stored.account.length > 0 ? stored.account : defaults.username;
  if (pass.length === 0 || user.length === 0) {
    return { ok: false, message: '缺少保存的登录凭据，请重新登录' };
  }
  const trusted = CertPolicy.isTrusted(nextUrl);
  const deviceId = await SessionPreferences.ensureWsDeviceId(ctx);
  const wsRes = await fnWsLogin(nextUrl, user, pass, trusted, deviceId);
  if (wsRes.requires2fa === true || wsRes.requires2faSetup === true) {
    return { ok: false, message: '切换需要双重验证，请返回登录页操作' };
  }
  if (wsRes.certificateError === true && !trusted) {
    return {
      ok: false,
      message: '目标地址证书未信任',
      certificateError: true,
      targetUrl: nextUrl
    };
  }
  if (wsRes.success !== true || wsRes.token === undefined || wsRes.token.length === 0) {
    const msg = wsRes.message !== undefined && wsRes.message.length > 0 ? wsRes.message : '切换连接失败';
    return { ok: false, message: msg };
  }
  const sk = wsRes.signKeyB64 !== undefined && wsRes.signKeyB64.length > 0 ? wsRes.signKeyB64 : '';
  const lt = wsRes.longToken !== undefined && wsRes.longToken.length > 0 ? wsRes.longToken : undefined;
  return finishSwitchSession(ctx, stored, nextUrl, wsRes.token, sk, lt);
}
