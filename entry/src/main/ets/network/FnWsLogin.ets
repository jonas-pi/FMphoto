/**
 * fnOS 主通道 WebSocket 登录（wss://host/websocket?type=main）
 * getRSAPub -> encrypted(user.login) -> user.authToken（HMAC 前缀 + JSON）
 * FN Connect 中继：握手带 Origin + Cookie（mode=relay），DNS 未就绪时短重试。
 * 自建反代 / Lucky 直连不带 mode=relay，避免被当成中继通道、握手停在 HTTP。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagError, fnDiagMaskUrl, fnDiagRecord, fnDiagRecordResolve, fnDiagSetState, fnDiagTiming } from '../common/FnDiagLog';
import { http } from '@kit.NetworkKit';
import webSocket from '@ohos.net.webSocket';
import { isFnRelayBaseUrl } from './FnConnectApi';
import { buildFnMainWebSocketUrl, isIpLiteralHost, parseNormalizedBaseUrl } from './ServerUrl';
import { resolvePublicDomainToIpBaseUrl } from './PublicDns';
import {
  fnWsAesCbcDecryptSecretToHmacKey,
  fnWsBuildEncryptedLogin,
  fnWsHmacKeyBytesToB64,
  fnWsHmacSha256SignConcatJson,
  fnWsMakeReqId,
  fnWsRandomAesKey32,
  fnWsRandomIv16,
  fnWsResetReqIdCounter,
  fnWsStringifyEncryptedFrame
} from './FnWsCrypto';

const DOMAIN = 0xFF00;
const TAG = 'FnWsLogin';

const WS_TIMEOUT_MS = 28000;
const WS_CONNECT_PROBE_TIMEOUT_MS = 5000;
/**
 * 主机名 WebSocket 迟迟没有 open 时的上限。
 * 整段 28s 超时表示协议已经连上，不能拿来换 IP；握手没建立则按连接失败，才能改走 IPv4。
 * 只用于已信任的主机名（IP 回退要求跳过证书校验）。文案不能含「超时」。
 */
const WS_OPEN_BUDGET_MS = 4500;
const DEFAULT_BACK_ID = '0000000000000000';
const WS_CONNECT_FAILED_CODE = '200';
const WS_CERT_ERROR_CODES: number[] = [2300060, 2300058, 2300059, 2300077];
/** 中继子域名 DNS 常滞后于隧道就绪；连接失败时短间隔再试，避免误报「找不到主机」 */
const RELAY_WS_CONNECT_ATTEMPTS = 3;
const RELAY_WS_RETRY_DELAY_MS = 1200;
/** 整段登录超时（28s）最多再试 1 次，避免中继抖动时卡太久 */
const RELAY_WS_TIMEOUT_RETRY_MAX = 1;

export interface FnWsLoginResult {
  success: boolean;
  token?: string;
  secretCipherB64?: string;
  /** 解密 secret 得到的 HMAC 密钥原始字节的 Base64，供后续 WS 帧签名与持久化 */
  signKeyB64?: string;
  /** 登录响应 longToken / long_token，与 sample/fnos_client.py 一致 */
  longToken?: string;
  backId?: string;
  uid?: number;
  admin?: boolean;
  message?: string;
  certificateError?: boolean;
  /** 密码正确但需第二步 TOTP / 紧急验证码（user.2fa.loginVerify） */
  requires2fa?: boolean;
  /** 系统强制 2FA 但账号尚未在网页端绑定 TOTP */
  requires2faSetup?: boolean;
  /** 2FA 挑战令牌，供 user.2fa.loginVerify 使用 */
  accessToken?: string;
}

interface WsJson {
  req?: string;
  reqid?: string;
  pub?: string;
  si?: string;
  token?: string;
  secret?: string;
  backId?: string;
  uid?: number;
  admin?: boolean;
  result?: string;
  errno?: number;
  msg?: string;
  longToken?: string;
  long_token?: string | number;
  accessToken?: string;
  isBindTwofaSecret?: boolean;
  isTrustedDevice?: boolean;
  isTwofaEnforced?: boolean;
}

interface PendingAfterAuth {
  token: string;
  signKeyB64: string;
  backId: string;
  secretCipherB64: string;
  longToken?: string;
  uid?: number;
  admin?: boolean;
}

interface WsFailureInfo {
  message: string;
  certificateError: boolean;
}

/** 与 Python json.dumps(..., separators=(',', ':')) 键序一致：req -> token -> si，不含 main */
function buildAuthTokenJson(tokenVal: string, siVal: string): string {
  return `{"req":"user.authToken","token":${JSON.stringify(tokenVal)},"si":${JSON.stringify(siVal)}}`;
}

/**
 * 紧凑 JSON，键序：reqid -> req -> user -> password -> deviceType -> deviceName -> stay -> si
 */
function buildLoginPlainJson(reqid: string, user: string, pass: string, siVal: string, deviceId: string): string {
  return `{"reqid":${JSON.stringify(reqid)},"req":"user.login","user":${JSON.stringify(user)},"password":${JSON.stringify(pass)},"deviceType":"Browser","deviceName":"FMphoto","stay":true,"did":${JSON.stringify(deviceId)},"si":${JSON.stringify(siVal)}}`;
}

/**
 * 紧凑 JSON：user.2fa.loginVerify（第二步 OTP）
 * stay 须为 0/1 整数，与官方 WebSocket 载荷一致。
 */
function build2faVerifyPlainJson(
  reqid: string,
  code: string,
  accessToken: string,
  trustDevice: boolean,
  stay: boolean,
  siVal: string,
  deviceId: string
): string {
  const stayNum = stay ? 1 : 0;
  return `{"reqid":${JSON.stringify(reqid)},"code":${JSON.stringify(code)},"isTrustedDevice":${trustDevice},"accessToken":${JSON.stringify(accessToken)},"stay":${stayNum},"deviceName":"FMphoto","deviceType":"Browser","did":${JSON.stringify(deviceId)},"req":"user.2fa.loginVerify","si":${JSON.stringify(siVal)}}`;
}

function isFinalLoginSuccess(data: WsJson): boolean {
  return data.result === 'succ'
    && data.token !== undefined
    && data.token.length > 0
    && data.secret !== undefined
    && data.secret.length > 0;
}

/** 已绑定 TOTP，当前设备未信任，需 OTP（中继与直连同一套挑战字段） */
function isTwofaChallenge(data: WsJson): boolean {
  const at = data.accessToken !== undefined ? data.accessToken : '';
  if (data.result !== 'succ' || at.length === 0) {
    return false;
  }
  if (data.token !== undefined && data.token.length > 0) {
    return false;
  }
  if (data.secret !== undefined && data.secret.length > 0) {
    return false;
  }
  // 未带 isTrustedDevice 时也视为未信任，避免中继漏掉 2FA 挑战
  return data.isBindTwofaSecret === true && data.isTrustedDevice !== true;
}

/** 管理员强制 2FA 但用户尚未绑定 */
function isTwofaSetupChallenge(data: WsJson): boolean {
  const at = data.accessToken !== undefined ? data.accessToken : '';
  return data.result === 'succ'
    && data.isTwofaEnforced === true
    && data.isBindTwofaSecret === false
    && at.length > 0
    && (data.token === undefined || data.token.length === 0)
    && (data.secret === undefined || data.secret.length === 0);
}

function messageToString(value: string | ArrayBuffer): string {
  if (typeof value === 'string') {
    return value;
  }
  const u8 = new Uint8Array(value);
  let out = '';
  for (let i = 0; i < u8.length; i++) {
    const b0 = u8[i];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      continue;
    }
    if ((b0 & 0xe0) === 0xc0 && i + 1 < u8.length) {
      const b1 = u8[++i];
      out += String.fromCharCode(((b0 & 0x1f) << 6) | (b1 & 0x3f));
      continue;
    }
    if ((b0 & 0xf0) === 0xe0 && i + 2 < u8.length) {
      const b1 = u8[++i];
      const b2 = u8[++i];
      out += String.fromCharCode(((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f));
      continue;
    }
    if ((b0 & 0xf8) === 0xf0 && i + 3 < u8.length) {
      const b1 = u8[++i];
      const b2 = u8[++i];
      const b3 = u8[++i];
      const codePoint = ((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f);
      const cp = codePoint - 0x10000;
      out += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
      continue;
    }
    out += '\uFFFD';
  }
  return out;
}

function parseJsonSafe(text: string): WsJson | null {
  try {
    return JSON.parse(text) as WsJson;
  } catch (_e) {
    return null;
  }
}

function pickWsErrorStringField(err: Object, key: string): string {
  const rec = err as Record<string, Object | undefined>;
  const raw = rec[key];
  if (typeof raw === 'string') {
    const text = raw.trim();
    if (text.length > 0) {
      return text;
    }
  }
  return '';
}

function pickWsErrorCodeField(err: Object, key: string): string {
  const rec = err as Record<string, Object | undefined>;
  const raw = rec[key];
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return `${raw}`;
  }
  if (typeof raw === 'string') {
    const text = raw.trim();
    if (text.length > 0) {
      return text;
    }
  }
  return '';
}

function describeWsError(err: Object | Error | string | undefined | null): string {
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
  const objectMsg = pickWsErrorStringField(err, 'message')
    || pickWsErrorStringField(err, 'msg')
    || pickWsErrorStringField(err, 'reason')
    || pickWsErrorStringField(err, 'errMsg')
    || pickWsErrorStringField(err, 'details')
    || pickWsErrorStringField(err, 'detail');
  if (objectMsg.length > 0) {
    const code = pickWsErrorCodeField(err, 'code')
      || pickWsErrorCodeField(err, 'errno')
      || pickWsErrorCodeField(err, 'errorCode')
      || pickWsErrorCodeField(err, 'statusCode');
    return code.length > 0 ? `${objectMsg} (code: ${code})` : objectMsg;
  }
  const codeOnly = pickWsErrorCodeField(err, 'code')
    || pickWsErrorCodeField(err, 'errno')
    || pickWsErrorCodeField(err, 'errorCode')
    || pickWsErrorCodeField(err, 'statusCode');
  if (codeOnly.length > 0) {
    return `错误码 ${codeOnly}`;
  }
  try {
    const text = JSON.stringify(err);
    if (text !== undefined) {
      const trimmed = text.trim();
      if (trimmed.length > 0 && trimmed !== '{}') {
        return trimmed;
      }
    }
  } catch (_e) {
  }
  const fallback = String(err).trim();
  return fallback !== '[object Object]' ? fallback : '';
}

function isLikelyCertificateError(message: string): boolean {
  const eml = message.toLowerCase();
  return eml.indexOf('cert') >= 0
    || eml.indexOf('ssl') >= 0
    || eml.indexOf('handshake') >= 0
    || eml.indexOf('x509') >= 0
    || eml.indexOf('trust') >= 0;
}

function getNetErrorCode(err: Object | Error | string | undefined | null): string {
  if (err === undefined || err === null || typeof err === 'string') {
    return '';
  }
  return pickWsErrorCodeField(err, 'code')
    || pickWsErrorCodeField(err, 'errno')
    || pickWsErrorCodeField(err, 'errorCode')
    || pickWsErrorCodeField(err, 'statusCode');
}

function isGenericWsConnectFailed(err: Object | Error | string | undefined | null, message: string): boolean {
  const code = getNetErrorCode(err);
  if (code === WS_CONNECT_FAILED_CODE) {
    return true;
  }
  const msg = message.trim();
  return msg === `错误码 ${WS_CONNECT_FAILED_CODE}`
    || msg.indexOf(`code: ${WS_CONNECT_FAILED_CODE}`) >= 0
    || msg.indexOf(`"code":${WS_CONNECT_FAILED_CODE}`) >= 0;
}

async function probeHttpsCertificateFailure(httpBaseNoSlash: string): Promise<boolean> {
  if (!httpBaseNoSlash.startsWith('https://')) {
    return false;
  }
  const req = http.createHttp();
  try {
    await req.request(httpBaseNoSlash, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: WS_CONNECT_PROBE_TIMEOUT_MS,
      readTimeout: WS_CONNECT_PROBE_TIMEOUT_MS,
      header: {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      }
    });
    return false;
  } catch (e) {
    const codeText = getNetErrorCode(e as Object | Error | string | undefined | null);
    if (codeText.length > 0) {
      const codeNum = parseInt(codeText, 10);
      if (!isNaN(codeNum) && WS_CERT_ERROR_CODES.indexOf(codeNum) >= 0) {
        return true;
      }
      fnDiagRecord('W', TAG, `cert probe not-cert code=${codeText}`);
    }
    return isLikelyCertificateError(describeWsError(e as Object | Error | string | undefined | null));
  } finally {
    try {
      req.destroy();
    } catch (_e) {
    }
  }
}

function delayMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

/** 协议+主机（不含路径），与官方 os-web 的 Origin 一致 */
function httpOriginOf(base: string): string {
  let u = base.trim();
  if (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  const pe = u.indexOf('://');
  if (pe < 0) {
    return u;
  }
  const after = u.substring(pe + 3);
  const slash = after.indexOf('/');
  if (slash < 0) {
    return u;
  }
  return u.substring(0, pe + 3 + slash);
}

/**
 * WSS 握手头：官方中继需要 Origin + Cookie(mode=relay)。
 * Lucky / 自建反代只带 Origin，勿带 mode=relay（否则握手可能停在普通 HTTP）。
 * hostOverride：拨号用 IP 字面量时，用原域名做 Host 头，反代才能选到对的站点。
 */
function buildWsConnectOptions(
  httpBase: string,
  isTrustedHost: boolean,
  hostOverride: string = ''
): webSocket.WebSocketRequestOptions {
  const origin = httpOriginOf(httpBase);
  const header: Record<string, string> = isFnRelayBaseUrl(httpBase)
    ? { 'Origin': origin, 'Cookie': 'mode=relay; language=zh-CN' }
    : { 'Origin': origin };
  if (hostOverride.length > 0) {
    header['Host'] = hostOverride;
  }
  const opt: webSocket.WebSocketRequestOptions = {
    header: header
  };
  if (isTrustedHost) {
    opt.skipServerCertVerification = true;
  }
  return opt;
}

/** 主机名地址：WS 无法指定地址族，需要靠 IP 字面量回退绕开不可用的 AAAA。 */
function isHostnameBaseUrl(baseUrl: string): boolean {
  const parts = parseNormalizedBaseUrl(baseUrl);
  if (parts === null || parts.host.length === 0) {
    return false;
  }
  return !isIpLiteralHost(parts.host);
}

/** 主机（含非默认端口），用于 IP 字面量拨号时补 Host 头。 */
function wsHostHeaderOf(baseUrl: string): string {
  const parts = parseNormalizedBaseUrl(baseUrl);
  if (parts === null || parts.host.length === 0) {
    return '';
  }
  const port = parts.port;
  if (port === null || port <= 0) {
    return parts.host;
  }
  const isDefault = (parts.scheme === 'https' && port === 443) || (parts.scheme === 'http' && port === 80);
  return isDefault ? parts.host : `${parts.host}:${port}`;
}

/**
 * 连接层失败（可换地址重试），只认明确的连接失败文案。
 *
 * 不把「超时」算进来：'WebSocket 登录超时' / '双重验证超时' 说明协议已经连上，
 * 这时再按 IP 拨一次等于把刚建立起来的会话重做一遍。
 * 握手在 WS_OPEN_BUDGET_MS 内没有 open，走的是「无法连接」，这里会认。
 */
function isConnectLevelFailure(message: string): boolean {
  const m = message.toLowerCase();
  if (m.indexOf('无法连接') >= 0 || m.indexOf('连接失败') >= 0) {
    return true;
  }
  if (m.indexOf('code: -1') >= 0 || m.indexOf('code:-1') >= 0 || m.indexOf('错误码 -1') >= 0) {
    return true;
  }
  return false;
}

/**
 * 主机名 WS 连不上时，改用解析出的 IP 字面量再试一次。
 *
 * ArkUI 的 webSocket 没有 addressFamily（HTTP 有），主机名连接会跟随系统解析顺序；
 * 家庭宽带 / 路由器下 AAAA 可能指向不可用地址，握手会直接失败（code -1），
 * 而同一域名的 HTTP 走 happy-eyeballs 反而正常。
 *
 * 前提是主机已被信任：连到 IP 时 TLS 的 SNI 是 IP，有效公网证书本来就对不上域名，
 * 不跳过校验就必然失败，所以这条回退只服务于已信任（自签等）站点；
 * 有效公网证书的站点走不到这里。
 */
async function wsIpLiteralFallback(baseUrl: string): Promise<string> {
  if (!isHostnameBaseUrl(baseUrl)) {
    return '';
  }
  // 记下此刻的解析结果条数：只有 AAAA、或 AAAA 指向不可达，是这类失败的典型成因
  const parts = parseNormalizedBaseUrl(baseUrl);
  if (parts !== null && parts.host.length > 0) {
    await fnDiagRecordResolve(parts.host);
  }
  try {
    const ipBase = await resolvePublicDomainToIpBaseUrl(baseUrl);
    if (ipBase.length === 0 || isHostnameBaseUrl(ipBase)) {
      fnDiagRecord('W', TAG, 'ws ip fallback resolve fail');
      return '';
    }
    return ipBase;
  } catch (e) {
    fnDiagRecord('W', TAG, `ws ip fallback resolve fail ${String(e)}`);
    return '';
  }
}

function isTerminalWsLoginResult(r: FnWsLoginResult): boolean {
  return r.success === true
    || r.requires2fa === true
    || r.requires2faSetup === true
    || r.certificateError === true;
}

/** 失败文案里可能带地址，落日志前把主机名换成掩码（端口等其余内容保留）。 */
export function maskWsFailureMessage(text: string | undefined, baseUrl: string): string {
  const t = (text !== undefined ? text : '').trim();
  if (t.length === 0) {
    return '';
  }
  const parts = parseNormalizedBaseUrl(baseUrl);
  if (parts === null || parts.host.length < 4) {
    return t.length > 80 ? t.substring(0, 80) : t;
  }
  return t.split(parts.host).join(fnDiagMaskUrl(parts.host));
}

/** 换一条登录地址再试：连接失败或证书问题；密码错 / 2FA 不换路 */
export function shouldTryNextLoginEndpoint(r: FnWsLoginResult): boolean {
  if (r.success === true || r.requires2fa === true || r.requires2faSetup === true) {
    return false;
  }
  if (r.certificateError === true) {
    return true;
  }
  return isRetryableRelayWsFailure(r);
}

/** 仅连接层失败才重试；密码错 / 2FA / 证书不可信不重试 */
function isRetryableRelayWsFailure(r: FnWsLoginResult): boolean {
  if (isTerminalWsLoginResult(r)) {
    return false;
  }
  const m = (r.message !== undefined ? r.message : '').toLowerCase();
  if (m.indexOf('websocket 登录超时') >= 0 || m.indexOf('双重验证超时') >= 0) {
    return true;
  }
  if (m.indexOf('无法连接') >= 0 || m.indexOf('连接失败') >= 0 || m.indexOf('打开失败') >= 0) {
    return true;
  }
  if (m.indexOf('找不到') >= 0 || m.indexOf('host') >= 0 || m.indexOf('dns') >= 0) {
    return true;
  }
  if (m.indexOf(`错误码 ${WS_CONNECT_FAILED_CODE}`) >= 0 || m.indexOf(`code: ${WS_CONNECT_FAILED_CODE}`) >= 0) {
    return true;
  }
  if (m.indexOf('eof') >= 0) {
    return true;
  }
  return false;
}

async function resolveWsFailure(
  httpBaseNoSlash: string,
  err: Object | Error | string | undefined | null,
  isTrustedHost: boolean,
  fallbackMessage: string
): Promise<WsFailureInfo> {
  const message = describeWsError(err);
  if (!isTrustedHost && isLikelyCertificateError(message)) {
    return {
      message: message.length > 0 ? message : 'WebSocket 无法校验服务器证书',
      certificateError: true
    };
  }

  if (!isTrustedHost && isGenericWsConnectFailed(err, message) && httpBaseNoSlash.startsWith('https://')) {
    const certFailed = await probeHttpsCertificateFailure(httpBaseNoSlash);
    if (certFailed) {
      return {
        message: 'WebSocket 无法校验服务器证书',
        certificateError: true
      };
    }
  }

  if (isGenericWsConnectFailed(err, message)) {
    let authority = httpBaseNoSlash;
    if (authority.startsWith('https://')) {
      authority = authority.substring('https://'.length);
    } else if (authority.startsWith('http://')) {
      authority = authority.substring('http://'.length);
    }
    const endpointHint = `请检查 ${authority} 是否可达、证书是否可信，以及设备到目标的网络连通性`;
    return {
      message: `WebSocket 连接失败（${endpointHint}）`,
      certificateError: false
    };
  }

  return {
    message: message.length > 0 ? message : fallbackMessage,
    certificateError: false
  };
}

/**
 * @param isTrustedHost 为 true 时允许自签等场景下由系统/应用网络安全策略放行（仍可能因设备策略失败）
 */
export async function fnWsLogin(
  httpBaseNoSlash: string,
  username: string,
  password: string,
  isTrustedHost: boolean,
  deviceId: string
): Promise<FnWsLoginResult> {
  if (deviceId.trim().length === 0) {
    fnDiagRecord('W', TAG, 'ws login param invalid:did');
    return { success: false, message: '缺少设备标识 did' };
  }
  const did = deviceId.trim();
  const isRelay = isFnRelayBaseUrl(httpBaseNoSlash);
  const maxAttempts = isRelay ? RELAY_WS_CONNECT_ATTEMPTS : 1;
  let last: FnWsLoginResult = { success: false, message: '无法连接 WebSocket' };
  let timeoutRetries = 0;
  let ipFallbackTried = false;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const onceT0 = Date.now();
    last = await fnWsLoginOnce(httpBaseNoSlash, username, password, isTrustedHost, did);
    fnDiagTiming(TAG, `wsOnce relay=${String(isRelay)} attempt=${attempt}`, Date.now() - onceT0);
    if (last.success === true) {
      fnDiagSetState('login', 'ok');
    }
    // 主机名 + 连接层失败：改用解析出的 IP 字面量再试一次（绕开不可用的 AAAA）
    if (!ipFallbackTried && isTrustedHost &&
      isConnectLevelFailure(last.message !== undefined ? last.message : '')) {
      const ipBase = await wsIpLiteralFallback(httpBaseNoSlash);
      if (ipBase.length > 0) {
        ipFallbackTried = true;
        const hostHeader = wsHostHeaderOf(httpBaseNoSlash);
        hilog.info(DOMAIN, TAG, 'WS retry via IP literal %{public}s', fnDiagMaskUrl(ipBase));
        fnDiagRecord('I', TAG, `WS retry via IP literal ${fnDiagMaskUrl(ipBase)}`);
        const ipT0 = Date.now();
        const ipResult = await fnWsLoginOnce(
          ipBase, username, password, isTrustedHost, did, httpBaseNoSlash, hostHeader);
        fnDiagTiming(TAG, 'wsOnce ipFallback', Date.now() - ipT0);
        if (ipResult.success === true || ipResult.requires2fa === true ||
          ipResult.requires2faSetup === true) {
          if (ipResult.success === true) {
            fnDiagSetState('login', 'ok');
          }
          return ipResult;
        }
        last = ipResult;
      }
    }
    if (!isRetryableRelayWsFailure(last) || attempt + 1 >= maxAttempts) {
      if (isRetryableRelayWsFailure(last) && attempt + 1 >= maxAttempts) {
        fnDiagRecord('W', TAG, `ws login final fail msg=${maskWsFailureMessage(last.message, httpBaseNoSlash)}`);
      }
      return last;
    }
    const msg = last.message !== undefined ? last.message : '';
    if (msg === 'WebSocket 登录超时') {
      timeoutRetries++;
      if (timeoutRetries > RELAY_WS_TIMEOUT_RETRY_MAX) {
        fnDiagRecord('W', TAG, `ws login final fail msg=${maskWsFailureMessage(last.message, httpBaseNoSlash)}`);
        fnDiagRecord('I', TAG, `wsRelayTimeoutRetryCap hit timeoutRetries=${timeoutRetries}`);
        return last;
      }
    }
    hilog.info(DOMAIN, TAG, 'relay WSS retry %{public}d/%{public}d: %{public}s',
      attempt + 1, maxAttempts - 1, msg);
    await delayMs(RELAY_WS_RETRY_DELAY_MS);
  }
  return last;
}

async function fnWsLoginOnce(
  httpBaseNoSlash: string,
  username: string,
  password: string,
  isTrustedHost: boolean,
  did: string,
  originBaseNoSlash: string = '',
  hostOverride: string = ''
): Promise<FnWsLoginResult> {
  fnWsResetReqIdCounter();
  // 拨号地址可以是 IP 字面量；Origin / 中继判定仍用原始域名
  const originBase = originBaseNoSlash.length > 0 ? originBaseNoSlash : httpBaseNoSlash;
  const wsUrl = buildFnMainWebSocketUrl(httpBaseNoSlash);
  const relay = isFnRelayBaseUrl(originBase);
  hilog.info(DOMAIN, TAG, 'WS connect %{public}s trusted=%{public}s relay=%{public}s',
    fnDiagMaskUrl(wsUrl), String(isTrustedHost), String(relay));
  fnDiagRecord('I', TAG, `WS connect ${fnDiagMaskUrl(wsUrl)} trusted=${String(isTrustedHost)} relay=${String(relay)}`);

  // 握手分段计时：连接 / 取 RSA 公钥 / user.login / user.authToken。
  // 28s 硬超时是整段共用的，拆开才知道慢在「连不上」还是「连上了拿不到 token」。
  // 注：wsStage user.login 的起点是公钥到达，中间的本地 RSA 加密也计在里面，
  // 它比纯网络往返长；以后要拿这个数拆 28s 时得算上。
  const wsStart = Date.now();
  return new Promise<FnWsLoginResult>((resolve: (r: FnWsLoginResult) => void) => {
    let done = false;
    let failureInFlight = false;
    let openAt = 0;
    let pubAt = 0;
    let loginAt = 0;
    const finish = (r: FnWsLoginResult): void => {
      if (done) {
        return;
      }
      done = true;
      clearTimeout(timer);
      if (openTimer >= 0) {
        clearTimeout(openTimer);
        openTimer = -1;
      }
      try {
        ws.close();
      } catch (_e) {
      }
      resolve(r);
    };

    const timer = setTimeout((): void => {
      // step 说明卡在哪一段：waitPub=等公钥，waitLogin=等登录响应，waitAuth=等 authToken。
      // step=waitPub 有两种情况：还没连上（conn=0）和连上了在等公钥（conn=1），用 conn 区分。
      fnDiagRecord('W', TAG, `ws login timeout step=${step} conn=${openAt > 0 ? '1' : '0'}`);
      finish({
        success: false,
        message: relay
          ? 'WebSocket 登录超时'
          : '公网 WebSocket 登录超时，可改自动选路或使用中继'
      });
    }, WS_TIMEOUT_MS);
    // 仅已信任的主机名：open 不来就按连接失败结束，外层才会改拨 IPv4。已在 IP 上回退时不再缩短。
    let openTimer: number = -1;

    let backId = DEFAULT_BACK_ID;
    let pubPem = '';
    let si = '';
    let aesKey32: Uint8Array | null = null;
    let iv: Uint8Array | null = null;
    let step: 'waitPub' | 'waitLogin' | 'waitAuth' = 'waitPub';
    let pendingAfterAuth: PendingAfterAuth | null = null;

    const ws = webSocket.createWebSocket();
    const connectOptions = buildWsConnectOptions(originBase, isTrustedHost, hostOverride);

    const handleWsFailure = (err: Object | Error | string | undefined | null, fallbackMessage: string): void => {
      if (done || failureInFlight) {
        return;
      }
      failureInFlight = true;
      void (async (): Promise<void> => {
        try {
          const info = await resolveWsFailure(httpBaseNoSlash, err, isTrustedHost, fallbackMessage);
          hilog.error(DOMAIN, TAG, 'ws error %{public}s', info.message);
          fnDiagRecord('E', TAG, `ws error ${maskWsFailureMessage(info.message, httpBaseNoSlash)}`);
          fnDiagSetState('lastWsFail', info.certificateError ? 'cert' : 'connect');
          finish({
            success: false,
            message: info.message,
            certificateError: info.certificateError
          });
        } catch (e) {
          const em = describeWsError(e);
          hilog.error(DOMAIN, TAG, 'ws error resolve %{public}s', em);
          fnDiagRecord('E', TAG, `ws error resolve ${maskWsFailureMessage(em, httpBaseNoSlash)}`);
          fnDiagSetState('lastWsFail', 'resolve-fail');
          finish({
            success: false,
            message: em.length > 0 ? em : fallbackMessage
          });
        }
      })();
    };

    ws.on('error', (err: Error) => {
      handleWsFailure(err, 'WebSocket 错误');
    });

    ws.on('message', (err: Error, value: string | ArrayBuffer) => {
      if (err !== undefined) {
        hilog.warn(DOMAIN, TAG, 'message err %{public}s', describeWsError(err));
        return;
      }
      const text = messageToString(value);
      const data = parseJsonSafe(text);
      if (data === null) {
        if (step === 'waitAuth' && pendingAfterAuth !== null) {
          finish({ success: false, message: 'authToken 响应不是有效 JSON' });
        }
        return;
      }
      if (data.errno !== undefined && data.errno !== 0) {
        const m = data.msg !== undefined && data.msg.length > 0 ? data.msg : `错误码 ${data.errno}`;
        finish({ success: false, message: m });
        return;
      }

      if (step === 'waitPub') {
        if (data.pub !== undefined && data.pub.length > 0 && data.si !== undefined) {
          pubPem = data.pub;
          si = data.si;
          pubAt = Date.now();
          if (openAt > 0) {
            fnDiagTiming(TAG, 'wsStage getRSAPub', pubAt - openAt);
          }
          void (async (): Promise<void> => {
            try {
              aesKey32 = await fnWsRandomAesKey32();
              iv = await fnWsRandomIv16();
              const reqid = fnWsMakeReqId(backId);
              const loginJson = buildLoginPlainJson(reqid, username, password, si, did);
              const enc = await fnWsBuildEncryptedLogin(loginJson, pubPem, aesKey32 as Uint8Array, iv as Uint8Array);
              ws.send(fnWsStringifyEncryptedFrame(enc));
              step = 'waitLogin';
            } catch (e) {
              fnDiagError(TAG, 'ws encrypt fail', e);
              finish({ success: false, message: `加密失败：${describeWsError(e)}` });
            }
          })();
        }
        return;
      }

      if (step === 'waitAuth') {
        if (pendingAfterAuth === null) {
          return;
        }
        const p = pendingAfterAuth;
        pendingAfterAuth = null;
        if (loginAt > 0) {
          fnDiagTiming(TAG, 'wsStage user.authToken', Date.now() - loginAt);
        }
        hilog.info(DOMAIN, TAG, 'user.authToken 响应已收');
        finish({
          success: true,
          token: p.token,
          secretCipherB64: p.secretCipherB64,
          signKeyB64: p.signKeyB64,
          longToken: p.longToken,
          backId: p.backId,
          uid: p.uid,
          admin: p.admin
        });
        return;
      }

      if (step === 'waitLogin') {
        if (isTwofaSetupChallenge(data)) {
          finish({
            success: false,
            requires2faSetup: true,
            message: '该账号需在飞牛网页端先绑定双重验证'
          });
          return;
        }
        if (isTwofaChallenge(data)) {
          const at = data.accessToken !== undefined ? data.accessToken : '';
          finish({
            success: false,
            requires2fa: true,
            accessToken: at,
            message: '请输入身份验证器中的 6 位动态验证码'
          });
          return;
        }
        if (isFinalLoginSuccess(data)) {
          const token = data.token as string;
          loginAt = Date.now();
          if (pubAt > 0) {
            fnDiagTiming(TAG, 'wsStage user.login', loginAt - pubAt);
          }
          const secretB64 = data.secret !== undefined ? data.secret : '';
          const bid = data.backId !== undefined && data.backId.length > 0 ? data.backId : backId;
          let siForAuth = si;
          if (data.si !== undefined && data.si.length > 0) {
            siForAuth = data.si;
          }
          const uidVal = data.uid;
          const adminVal = data.admin;
          let longTokFromLogin = '';
          if (data.longToken !== undefined && data.longToken.length > 0) {
            longTokFromLogin = data.longToken;
          } else if (data.long_token !== undefined) {
            const raw = `${data.long_token}`;
            if (raw.length > 0 && raw !== 'undefined') {
              longTokFromLogin = raw;
            }
          }
          void (async (): Promise<void> => {
            try {
              if (secretB64.length === 0 || iv === null || aesKey32 === null) {
                finish({ success: false, message: '登录未返回 secret，无法完成 authToken' });
                return;
              }
              const hmacKey = await fnWsAesCbcDecryptSecretToHmacKey(secretB64, aesKey32, iv as Uint8Array);
              const payload = buildAuthTokenJson(token, siForAuth);
              const frame = await fnWsHmacSha256SignConcatJson(hmacKey, payload);
              const signKeyB64 = fnWsHmacKeyBytesToB64(hmacKey);
              pendingAfterAuth = {
                token: token,
                signKeyB64: signKeyB64,
                backId: bid,
                secretCipherB64: secretB64,
                longToken: longTokFromLogin.length > 0 ? longTokFromLogin : undefined,
                uid: uidVal,
                admin: adminVal
              };
              step = 'waitAuth';
              ws.send(frame);
              hilog.info(DOMAIN, TAG, '已发送 user.authToken（HMAC 前缀+JSON）');
            } catch (e) {
              fnDiagError(TAG, 'ws authToken fail', e);
              finish({ success: false, message: `authToken 失败：${describeWsError(e)}` });
            }
          })();
        } else {
          const m =
            data.msg !== undefined && data.msg.length > 0
              ? data.msg
              : '登录失败（未返回 succ/token）';
          fnDiagRecord('W', TAG, 'ws login no succ/token');
          finish({ success: false, message: m });
        }
      }
    });

    ws.on('open', (err: Error) => {
      if (openTimer >= 0) {
        clearTimeout(openTimer);
        openTimer = -1;
      }
      if (err !== undefined) {
        handleWsFailure(err, 'WebSocket 打开失败');
        return;
      }
      openAt = Date.now();
      fnDiagTiming(TAG, 'wsStage connect', openAt - wsStart);
      const reqid = fnWsMakeReqId(backId);
      const first = `{"reqid":${JSON.stringify(reqid)},"req":"util.crypto.getRSAPub"}`;
      ws.send(first);
    });

    const onConnect = (err: Error): void => {
      if (err !== undefined) {
        handleWsFailure(err, '无法连接 WebSocket');
      }
    };

    // AAAA 黑洞时 open 往往一直不来，原先要等满 28s。这里提前按连接失败结束，外层改拨 IPv4。
    // 文案固定为「无法连接」，不能写成超时，否则不会换地址。
    // 中继不走这条：提前掐断会误把 fnos.net 换成解析出的 IP，中继通道就断了。
    if (isTrustedHost && !relay && hostOverride.length === 0 && isHostnameBaseUrl(httpBaseNoSlash)) {
      openTimer = setTimeout((): void => {
        fnDiagRecord('W', TAG, 'ws open budget exceeded');
        finish({ success: false, message: '无法连接 WebSocket' });
      }, WS_OPEN_BUDGET_MS);
    }
    ws.connect(wsUrl, connectOptions, onConnect);
  });
}

/**
 * 2FA 第二步：提交 TOTP / 紧急验证码（user.2fa.loginVerify）。
 * 须在 fnWsLogin 返回 requires2fa 后尽快调用；accessToken 有时效。
 * 中继上会新开 WSS（带 Origin/Cookie）；连接失败时短重试，验证码错误不重试。
 */
export async function fnWs2faVerify(
  httpBaseNoSlash: string,
  accessToken: string,
  otpCode: string,
  trustDevice: boolean,
  isTrustedHost: boolean,
  deviceId: string
): Promise<FnWsLoginResult> {
  const code = otpCode.trim();
  if (!/^\d{6}$/.test(code)) {
    fnDiagRecord('W', TAG, 'ws login param invalid:2fa_code');
    return { success: false, message: '验证码须为 6 位数字' };
  }
  if (accessToken.length === 0) {
    fnDiagRecord('W', TAG, 'ws login param invalid:2fa_token');
    return { success: false, message: '缺少 2FA 挑战令牌，请重新登录' };
  }
  if (deviceId.trim().length === 0) {
    fnDiagRecord('W', TAG, 'ws login param invalid:did');
    return { success: false, message: '缺少设备标识 did，请重新登录' };
  }
  const did = deviceId.trim();
  const maxAttempts = isFnRelayBaseUrl(httpBaseNoSlash) ? RELAY_WS_CONNECT_ATTEMPTS : 1;
  let last: FnWsLoginResult = { success: false, message: '无法连接 WebSocket' };
  let timeoutRetries = 0;
  let ipFallbackTried = false;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const onceT0 = Date.now();
    last = await fnWs2faVerifyOnce(
      httpBaseNoSlash, accessToken, code, trustDevice, isTrustedHost, did
    );
    fnDiagTiming(TAG, `ws2faOnce attempt=${attempt}`, Date.now() - onceT0);
    if (last.success === true) {
      fnDiagSetState('login', 'ok');
    }
    // 主机名 + 连接层失败：改用解析出的 IP 字面量再试一次（绕开不可用的 AAAA）
    if (!ipFallbackTried && isTrustedHost &&
      isConnectLevelFailure(last.message !== undefined ? last.message : '')) {
      const ipBase = await wsIpLiteralFallback(httpBaseNoSlash);
      if (ipBase.length > 0) {
        ipFallbackTried = true;
        const hostHeader = wsHostHeaderOf(httpBaseNoSlash);
        hilog.info(DOMAIN, TAG, 'WS 2FA retry via IP literal %{public}s', fnDiagMaskUrl(ipBase));
        fnDiagRecord('I', TAG, `WS 2FA retry via IP literal ${fnDiagMaskUrl(ipBase)}`);
        const ipResult = await fnWs2faVerifyOnce(
          ipBase, accessToken, code, trustDevice, isTrustedHost, did, httpBaseNoSlash, hostHeader);
        if (ipResult.success === true) {
          fnDiagSetState('login', 'ok');
          return ipResult;
        }
        last = ipResult;
      }
    }
    if (!isRetryableRelayWsFailure(last) || attempt + 1 >= maxAttempts) {
      return last;
    }
    const msg = last.message !== undefined ? last.message : '';
    if (msg === '双重验证超时') {
      timeoutRetries++;
      if (timeoutRetries > RELAY_WS_TIMEOUT_RETRY_MAX) {
        fnDiagRecord('W', TAG, `ws 2fa final fail msg=${maskWsFailureMessage(last.message, httpBaseNoSlash)}`);
        fnDiagRecord('I', TAG, `ws2faRelayTimeoutRetryCap hit timeoutRetries=${timeoutRetries}`);
        return last;
      }
    }
    hilog.info(DOMAIN, TAG, 'relay WSS 2FA retry %{public}d/%{public}d: %{public}s',
      attempt + 1, maxAttempts - 1, msg);
    await delayMs(RELAY_WS_RETRY_DELAY_MS);
  }
  return last;
}

async function fnWs2faVerifyOnce(
  httpBaseNoSlash: string,
  accessToken: string,
  code: string,
  trustDevice: boolean,
  isTrustedHost: boolean,
  did: string,
  originBaseNoSlash: string = '',
  hostOverride: string = ''
): Promise<FnWsLoginResult> {
  fnWsResetReqIdCounter();
  // 拨号地址可以是 IP 字面量；Origin 仍用原始域名
  const originBase = originBaseNoSlash.length > 0 ? originBaseNoSlash : httpBaseNoSlash;
  const wsUrl = buildFnMainWebSocketUrl(httpBaseNoSlash);
  hilog.info(DOMAIN, TAG, 'WS 2FA verify %{public}s', fnDiagMaskUrl(wsUrl));

  // 与 fnWsLoginOnce 同口径的握手分段计时
  const wsStart = Date.now();
  return new Promise<FnWsLoginResult>((resolve: (r: FnWsLoginResult) => void) => {
    let done = false;
    let failureInFlight = false;
    let openAt = 0;
    let pubAt = 0;
    let loginAt = 0;
    const finish = (r: FnWsLoginResult): void => {
      if (done) {
        return;
      }
      done = true;
      clearTimeout(timer);
      try {
        ws.close();
      } catch (_e) {
      }
      resolve(r);
    };

    const timer = setTimeout((): void => {
      fnDiagRecord('W', TAG, `ws 2fa timeout step=${step} conn=${openAt > 0 ? '1' : '0'}`);
      finish({ success: false, message: '双重验证超时' });
    }, WS_TIMEOUT_MS);

    let backId = DEFAULT_BACK_ID;
    let pubPem = '';
    let si = '';
    let aesKey32: Uint8Array | null = null;
    let iv: Uint8Array | null = null;
    let step: 'waitPub' | 'waitLogin' | 'waitAuth' = 'waitPub';
    let pendingAfterAuth: PendingAfterAuth | null = null;

    const ws = webSocket.createWebSocket();
    const connectOptions = buildWsConnectOptions(originBase, isTrustedHost, hostOverride);

    const handleWsFailure = (err: Object | Error | string | undefined | null, fallbackMessage: string): void => {
      if (done || failureInFlight) {
        return;
      }
      failureInFlight = true;
      void (async (): Promise<void> => {
        try {
          const info = await resolveWsFailure(httpBaseNoSlash, err, isTrustedHost, fallbackMessage);
          fnDiagRecord('E', TAG, `ws error ${maskWsFailureMessage(info.message, httpBaseNoSlash)}`);
          fnDiagSetState('lastWsFail', info.certificateError ? 'cert' : 'connect');
          finish({
            success: false,
            message: info.message,
            certificateError: info.certificateError
          });
        } catch (e) {
          const em = describeWsError(e);
          fnDiagError(TAG, 'ws 2fa error resolve', e);
          fnDiagSetState('lastWsFail', 'resolve-fail');
          finish({ success: false, message: em.length > 0 ? em : fallbackMessage });
        }
      })();
    };

    ws.on('error', (err: Error) => {
      handleWsFailure(err, 'WebSocket 错误');
    });

    ws.on('message', (err: Error, value: string | ArrayBuffer) => {
      if (err !== undefined) {
        fnDiagRecord('W', TAG, 'ws 2fa msg carry err');
        return;
      }
      const text = messageToString(value);
      const data = parseJsonSafe(text);
      if (data === null) {
        fnDiagRecord('W', TAG, `ws msg parse fail step=${step}`);
        if (step === 'waitAuth' && pendingAfterAuth !== null) {
          finish({ success: false, message: 'authToken 响应不是有效 JSON' });
        }
        return;
      }
      if (data.errno !== undefined && data.errno !== 0) {
        fnDiagRecord('W', TAG, `ws biz errno=${data.errno} step=${step}`);
        const m = data.msg !== undefined && data.msg.length > 0 ? data.msg : `错误码 ${data.errno}`;
        finish({ success: false, message: m });
        return;
      }

      if (step === 'waitPub') {
        if (data.pub !== undefined && data.pub.length > 0 && data.si !== undefined) {
          pubPem = data.pub;
          si = data.si;
          pubAt = Date.now();
          if (openAt > 0) {
            fnDiagTiming(TAG, 'wsStage getRSAPub', pubAt - openAt);
          }
          void (async (): Promise<void> => {
            try {
              aesKey32 = await fnWsRandomAesKey32();
              iv = await fnWsRandomIv16();
              const reqid = fnWsMakeReqId(backId);
              const verifyJson = build2faVerifyPlainJson(
                reqid, code, accessToken, trustDevice, true, si, did
              );
              const enc = await fnWsBuildEncryptedLogin(verifyJson, pubPem, aesKey32 as Uint8Array, iv as Uint8Array);
              ws.send(fnWsStringifyEncryptedFrame(enc));
              step = 'waitLogin';
            } catch (e) {
              fnDiagError(TAG, 'ws encrypt fail', e);
              finish({ success: false, message: `加密失败：${describeWsError(e)}` });
            }
          })();
        }
        return;
      }

      if (step === 'waitAuth') {
        if (pendingAfterAuth === null) {
          return;
        }
        const p = pendingAfterAuth;
        pendingAfterAuth = null;
        if (loginAt > 0) {
          fnDiagTiming(TAG, 'wsStage user.authToken', Date.now() - loginAt);
        }
        finish({
          success: true,
          token: p.token,
          secretCipherB64: p.secretCipherB64,
          signKeyB64: p.signKeyB64,
          longToken: p.longToken,
          backId: p.backId,
          uid: p.uid,
          admin: p.admin
        });
        return;
      }

      if (step === 'waitLogin') {
        if (isFinalLoginSuccess(data)) {
          const token = data.token as string;
          loginAt = Date.now();
          if (pubAt > 0) {
            fnDiagTiming(TAG, 'wsStage user.login', loginAt - pubAt);
          }
          const secretB64 = data.secret !== undefined ? data.secret : '';
          const bid = data.backId !== undefined && data.backId.length > 0 ? data.backId : backId;
          let siForAuth = si;
          if (data.si !== undefined && data.si.length > 0) {
            siForAuth = data.si;
          }
          const uidVal = data.uid;
          const adminVal = data.admin;
          let longTokFromLogin = '';
          if (data.longToken !== undefined && data.longToken.length > 0) {
            longTokFromLogin = data.longToken;
          } else if (data.long_token !== undefined) {
            const raw = `${data.long_token}`;
            if (raw.length > 0 && raw !== 'undefined') {
              longTokFromLogin = raw;
            }
          }
          void (async (): Promise<void> => {
            try {
              if (secretB64.length === 0 || iv === null || aesKey32 === null) {
                finish({ success: false, message: '验证成功但未返回 secret' });
                return;
              }
              const hmacKey = await fnWsAesCbcDecryptSecretToHmacKey(secretB64, aesKey32, iv as Uint8Array);
              const payload = buildAuthTokenJson(token, siForAuth);
              const frame = await fnWsHmacSha256SignConcatJson(hmacKey, payload);
              const signKeyB64 = fnWsHmacKeyBytesToB64(hmacKey);
              pendingAfterAuth = {
                token: token,
                signKeyB64: signKeyB64,
                backId: bid,
                secretCipherB64: secretB64,
                longToken: longTokFromLogin.length > 0 ? longTokFromLogin : undefined,
                uid: uidVal,
                admin: adminVal
              };
              step = 'waitAuth';
              ws.send(frame);
            } catch (e) {
              fnDiagError(TAG, 'ws authToken fail', e);
              finish({ success: false, message: `authToken 失败：${describeWsError(e)}` });
            }
          })();
        } else {
          const m =
            data.msg !== undefined && data.msg.length > 0
              ? data.msg
              : '验证码错误或已过期';
          fnDiagRecord('W', TAG, 'ws login no succ/token');
          finish({ success: false, message: m });
        }
      }
    });

    ws.on('open', (err: Error) => {
      if (err !== undefined) {
        handleWsFailure(err, 'WebSocket 打开失败');
        return;
      }
      openAt = Date.now();
      fnDiagTiming(TAG, 'wsStage connect', openAt - wsStart);
      const reqid = fnWsMakeReqId(backId);
      ws.send(`{"reqid":${JSON.stringify(reqid)},"req":"util.crypto.getRSAPub"}`);
    });

    const onConnect = (err: Error): void => {
      if (err !== undefined) {
        handleWsFailure(err, '无法连接 WebSocket');
      }
    };

    ws.connect(wsUrl, connectOptions, onConnect);
  });
}
