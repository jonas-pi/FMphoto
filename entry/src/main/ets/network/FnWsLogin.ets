/**
 * fnOS 主通道 WebSocket 登录（wss://host/websocket?type=main）
 * getRSAPub → encrypted(user.login) → user.authToken（HMAC 帧与前端/Python 一致）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
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
const DEFAULT_BACK_ID = '0000000000000000';

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

/** 与 Python json.dumps(..., separators=(',', ':')) 键序：req → token → si，不含 main */
function buildAuthTokenJson(tokenVal: string, siVal: string): string {
  return `{"req":"user.authToken","token":${JSON.stringify(tokenVal)},"si":${JSON.stringify(siVal)}}`;
}

/**
 * 紧凑 JSON，键序：reqid → req → user → password → deviceType → deviceName → stay → si
 */
function buildLoginPlainJson(reqid: string, user: string, pass: string, siVal: string): string {
  return `{"reqid":${JSON.stringify(reqid)},"req":"user.login","user":${JSON.stringify(user)},"password":${JSON.stringify(pass)},"deviceType":"Browser","deviceName":"MyClient","stay":true,"si":${JSON.stringify(siVal)}}`;
}

function messageToString(value: string | ArrayBuffer): string {
  if (typeof value === 'string') {
    return value;
  }
  const u8 = new Uint8Array(value);
  const dec = new util.TextDecoder('utf-8');
  return dec.decode(u8);
}

function parseJsonSafe(text: string): WsJson | null {
  try {
    return JSON.parse(text) as WsJson;
  } catch (_e) {
    return null;
  }
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

    ws.on('error', (err: Error) => {
      const em = err !== undefined && err.message !== undefined ? err.message : String(err);
      hilog.error(DOMAIN, TAG, 'ws error %{public}s', em);
      const eml = em.toLowerCase();
      const certHint =
        eml.indexOf('cert') >= 0 || eml.indexOf('ssl') >= 0 || eml.indexOf('handshake') >= 0;
      finish({
        success: false,
        message: em.length > 0 ? em : 'WebSocket 错误',
        certificateError: certHint && !isTrustedHost
      });
    });

    ws.on('message', (err: Error, value: string | ArrayBuffer) => {
      if (err !== undefined) {
        hilog.warn(DOMAIN, TAG, 'message err %{public}s', String(err));
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
        finish({ success: false, message: String(err) });
        return;
      }
      const reqid = fnWsMakeReqId(backId);
      const first = `{"reqid":${JSON.stringify(reqid)},"req":"util.crypto.getRSAPub"}`;
      ws.send(first);
    });

    ws.connect(wsUrl, (err: Error) => {
      if (err !== undefined) {
        const em = err.message !== undefined ? err.message : String(err);
        const eml = em.toLowerCase();
        const certHint = eml.indexOf('cert') >= 0 || eml.indexOf('ssl') >= 0;
        finish({
          success: false,
          message: em.length > 0 ? em : '无法连接 WebSocket',
          certificateError: certHint && !isTrustedHost
        });
      }
    });
  });
}
