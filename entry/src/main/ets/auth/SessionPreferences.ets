/**
 * 会话与信任列表持久化（preferences）
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREF_NAME = 'fnos_client_prefs';

const K_BASE_URL = 'base_url';
const K_TOKEN = 'token';
const K_ACCOUNT = 'account';
const K_DOMAIN_INPUT = 'domain_input';
const K_USE_HTTPS = 'use_https';
const K_ALBUM_PARENT = 'album_parent_guid';
const K_TRUSTED = 'trusted_hosts_json';
/** 上次登录成功时保存的密码（与系统密码保险箱配合；本地 preferences 仅存一份便于冷启动回填） */
const K_LAST_PASSWORD = 'last_password';
const K_FNOS_LONG_TOKEN = 'fnos_long_token';
/** 通过 WebSocket 主通道登录；为 true 时 OpenAPI user/info 可能不可用，冷启动不强制校验 */
const K_LOGIN_VIA_WS = 'login_via_ws';
/** WS HMAC：解密 secret 得到的密钥原始字节，以 Base64 存储（与 Python hmac_key 一致） */
const K_WS_SIGN_KEY_B64 = 'ws_sign_key_b64';
/** 首次启动免责声明同意标记：1=已同意，0/空=未同意 */
const K_LEGAL_ACCEPTED = 'legal_notice_accepted';

export interface StoredSession {
  baseUrl: string;
  token: string;
  account: string;
  domainInput: string;
  useHttps: boolean;
  albumParentGuid: string;
  trustedHosts: string[];
  /** 与浏览器 Cookie「fnos-long-token」对应，可能由登录响应 Set-Cookie 下发 */
  fnosLongToken: string;
  /** 是否经 wss .../websocket?type=main 登录（与 HTTP OpenAPI 会话可能不互通） */
  loginViaWebSocket: boolean;
  /** secret 解密密钥 K 的 Base64：与 WS HMAC、H5 localStorage「fnos-Secret」相同（见 sample） */
  wsSignKeyB64: string;
}

/** 登录页回填：不依赖 token，退出登录后仍可读 */
export interface LoginFormDefaults {
  domainInput: string;
  username: string;
  password: string;
  useHttps: boolean;
}

async function openPrefs(ctx: common.UIAbilityContext) {
  return preferences.getPreferences(ctx, PREF_NAME);
}

export class SessionPreferences {
  /** 是否已同意启动免责声明 */
  static async isLegalNoticeAccepted(ctx: common.UIAbilityContext): Promise<boolean> {
    const p = await openPrefs(ctx);
    return (await p.get(K_LEGAL_ACCEPTED, '0') as string) === '1';
  }

  /** 持久化启动免责声明同意状态 */
  static async setLegalNoticeAccepted(ctx: common.UIAbilityContext, accepted: boolean): Promise<void> {
    const p = await openPrefs(ctx);
    await p.put(K_LEGAL_ACCEPTED, accepted ? '1' : '0');
    await p.flush();
  }

  static async load(ctx: common.UIAbilityContext): Promise<StoredSession | null> {
    const p = await openPrefs(ctx);
    const token = await p.get(K_TOKEN, '') as string;
    if (token.length === 0) {
      return null;
    }
    const baseUrl = await p.get(K_BASE_URL, '') as string;
    const account = await p.get(K_ACCOUNT, '') as string;
    const domainInput = await p.get(K_DOMAIN_INPUT, '') as string;
    const useHttps = (await p.get(K_USE_HTTPS, '1') as string) === '1';
    const albumParentGuid = await p.get(K_ALBUM_PARENT, '') as string;
    let trustedHosts: string[] = [];
    const tj = await p.get(K_TRUSTED, '[]') as string;
    try {
      trustedHosts = JSON.parse(tj) as string[];
    } catch (_e) {
      trustedHosts = [];
    }
    const fnosLongToken = await p.get(K_FNOS_LONG_TOKEN, '') as string;
    const loginViaWs = (await p.get(K_LOGIN_VIA_WS, '0') as string) === '1';
    const wsSignKeyB64 = await p.get(K_WS_SIGN_KEY_B64, '') as string;
    return {
      baseUrl: baseUrl,
      token: token,
      account: account,
      domainInput: domainInput,
      useHttps: useHttps,
      albumParentGuid: albumParentGuid,
      trustedHosts: trustedHosts,
      fnosLongToken: fnosLongToken,
      loginViaWebSocket: loginViaWs,
      wsSignKeyB64: wsSignKeyB64
    };
  }

  static async save(ctx: common.UIAbilityContext, s: StoredSession, loginPassword?: string): Promise<void> {
    const p = await openPrefs(ctx);
    await p.put(K_BASE_URL, s.baseUrl);
    await p.put(K_TOKEN, s.token);
    await p.put(K_ACCOUNT, s.account);
    await p.put(K_DOMAIN_INPUT, s.domainInput);
    await p.put(K_USE_HTTPS, s.useHttps ? '1' : '0');
    await p.put(K_ALBUM_PARENT, s.albumParentGuid);
    await p.put(K_TRUSTED, JSON.stringify(s.trustedHosts));
    // 仅在实际变更时写入密码，降低系统凭据服务对「重复提交同一密码」的感知
    if (loginPassword !== undefined) {
      const prevPw = await p.get(K_LAST_PASSWORD, '') as string;
      if (prevPw !== loginPassword) {
        await p.put(K_LAST_PASSWORD, loginPassword);
      }
    }
    await p.put(K_FNOS_LONG_TOKEN, s.fnosLongToken);
    await p.put(K_LOGIN_VIA_WS, s.loginViaWebSocket ? '1' : '0');
    await p.put(K_WS_SIGN_KEY_B64, s.wsSignKeyB64.length > 0 ? s.wsSignKeyB64 : '');
    await p.flush();
  }

  /** 退出登录后用于回填服务器、账号、密码、HTTPS 开关 */
  static async loadLoginFormDefaults(ctx: common.UIAbilityContext): Promise<LoginFormDefaults> {
    const p = await openPrefs(ctx);
    return {
      domainInput: await p.get(K_DOMAIN_INPUT, '') as string,
      username: await p.get(K_ACCOUNT, '') as string,
      password: await p.get(K_LAST_PASSWORD, '') as string,
      useHttps: (await p.get(K_USE_HTTPS, '1') as string) === '1'
    };
  }

  /** 仅清除会话（令牌与 baseUrl），保留上次填写的登录信息与信任列表 */
  static async clearSession(ctx: common.UIAbilityContext): Promise<void> {
    const p = await openPrefs(ctx);
    await p.put(K_TOKEN, '');
    await p.put(K_BASE_URL, '');
    await p.put(K_FNOS_LONG_TOKEN, '');
    await p.put(K_LOGIN_VIA_WS, '0');
    await p.put(K_WS_SIGN_KEY_B64, '');
    await p.flush();
  }

  /** 无有效 token 时仍恢复自签信任列表（与 clearSession 搭配使用） */
  static async loadTrustedHostsSnapshot(ctx: common.UIAbilityContext): Promise<string[]> {
    const p = await openPrefs(ctx);
    const tj = await p.get(K_TRUSTED, '[]') as string;
    try {
      return JSON.parse(tj) as string[];
    } catch (_e) {
      return [];
    }
  }

  /** 仅清除令牌（校验失败时） */
  static async clearToken(ctx: common.UIAbilityContext): Promise<void> {
    const p = await openPrefs(ctx);
    await p.put(K_TOKEN, '');
    await p.put(K_FNOS_LONG_TOKEN, '');
    await p.put(K_LOGIN_VIA_WS, '0');
    await p.put(K_WS_SIGN_KEY_B64, '');
    await p.flush();
  }

  static async clearAll(ctx: common.UIAbilityContext): Promise<void> {
    const p = await openPrefs(ctx);
    await p.clear();
    await p.flush();
  }
}
