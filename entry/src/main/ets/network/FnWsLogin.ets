/**
 * fnOS 主通道 WebSocket 登录（wss://host/websocket?type=main）
 * getRSAPub -> encrypted(user.login) -> user.authToken（HMAC 前缀 + JSON）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import webSocket from '@ohos.net.webSocket';
import { buildFnMainWebSocketUrl } from './ServerUrl';
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
const DEFAULT_BACK_ID = '0000000000000000';
const WS_CONNECT_FAILED_CODE = '200';
const WS_CERT_ERROR_CODES: number[] = [2300060, 2300058, 2300059, 2300077];

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
function buildLoginPlainJson(reqid: string, user: string, pass: string, siVal: string): string {
  return `{"reqid":${JSON.stringify(reqid)},"req":"user.login","user":${JSON.stringify(user)},"password":${JSON.stringify(pass)},"deviceType":"Browser","deviceName":"MyClient","stay":true,"si":${JSON.stringify(siVal)}}`;
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
    }
    return isLikelyCertificateError(describeWsError(e as Object | Error | string | undefined | null));
  } finally {
    try {
      req.destroy();
    } catch (_e) {
    }
  }
}

function buildWsConnectOptions(isTrustedHost: boolean): webSocket.WebSocketRequestOptions | undefined {
  if (!isTrustedHost) {
    return undefined;
  }
  return {
    skipServerCertVerification: true
  };
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
    const endpointHint = httpBaseNoSlash.startsWith('https://')
      ? '请检查服务器地址、5667 端口、证书以及设备到 NAS 的连通性'
      : '请检查服务器地址、5666 端口以及设备到 NAS 的连通性';
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
  isTrustedHost: boolean
): Promise<FnWsLoginResult> {
  fnWsResetReqIdCounter();
  const wsUrl = buildFnMainWebSocketUrl(httpBaseNoSlash);
  hilog.info(DOMAIN, TAG, 'WS connect %{public}s trusted=%{public}s', wsUrl, String(isTrustedHost));

  return new Promise<FnWsLoginResult>((resolve: (r: FnWsLoginResult) => void) => {
    let done = false;
    let failureInFlight = false;
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
      finish({ success: false, message: 'WebSocket 登录超时' });
    }, WS_TIMEOUT_MS);

    let backId = DEFAULT_BACK_ID;
    let pubPem = '';
    let si = '';
    let aesKey32: Uint8Array | null = null;
    let iv: Uint8Array | null = null;
    let step: 'waitPub' | 'waitLogin' | 'waitAuth' = 'waitPub';
    let pendingAfterAuth: PendingAfterAuth | null = null;

    const ws = webSocket.createWebSocket();
    const connectOptions = buildWsConnectOptions(isTrustedHost);

    const handleWsFailure = (err: Object | Error | string | undefined | null, fallbackMessage: string): void => {
      if (done || failureInFlight) {
        return;
      }
      failureInFlight = true;
      void (async (): Promise<void> => {
        try {
          const info = await resolveWsFailure(httpBaseNoSlash, err, isTrustedHost, fallbackMessage);
          hilog.error(DOMAIN, TAG, 'ws error %{public}s', info.message);
          finish({
            success: false,
            message: info.message,
            certificateError: info.certificateError
          });
        } catch (e) {
          const em = describeWsError(e);
          hilog.error(DOMAIN, TAG, 'ws error resolve %{public}s', em);
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
          void (async (): Promise<void> => {
            try {
              aesKey32 = await fnWsRandomAesKey32();
              iv = await fnWsRandomIv16();
              const reqid = fnWsMakeReqId(backId);
              const loginJson = buildLoginPlainJson(reqid, username, password, si);
              const enc = await fnWsBuildEncryptedLogin(loginJson, pubPem, aesKey32 as Uint8Array, iv as Uint8Array);
              ws.send(fnWsStringifyEncryptedFrame(enc));
              step = 'waitLogin';
            } catch (e) {
              finish({ success: false, message: `加密失败：${String(e)}` });
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
        if (data.result === 'succ' && data.token !== undefined && data.token.length > 0) {
          const token = data.token;
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
              finish({ success: false, message: `authToken 失败：${String(e)}` });
            }
          })();
        } else {
          const m =
            data.msg !== undefined && data.msg.length > 0
              ? data.msg
              : '登录失败（未返回 succ/token）';
          finish({ success: false, message: m });
        }
      }
    });

    ws.on('open', (err: Error) => {
      if (err !== undefined) {
        handleWsFailure(err, 'WebSocket 打开失败');
        return;
      }
      const reqid = fnWsMakeReqId(backId);
      const first = `{"reqid":${JSON.stringify(reqid)},"req":"util.crypto.getRSAPub"}`;
      ws.send(first);
    });

    const onConnect = (err: Error): void => {
      if (err !== undefined) {
        handleWsFailure(err, '无法连接 WebSocket');
      }
    };

    if (connectOptions !== undefined) {
      ws.connect(wsUrl, connectOptions, onConnect);
    } else {
      ws.connect(wsUrl, onConnect);
    }
  });
}
