import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { createFnWsDeviceId } from '../network/FnWsDeviceId';

const PREF_NAME = 'fnos_client_prefs';

const K_BASE_URL = 'base_url';
const K_TOKEN = 'token';
const K_ACCOUNT = 'account';
const K_DOMAIN_INPUT = 'domain_input';
const K_USE_HTTPS = 'use_https';
const K_ALBUM_PARENT = 'album_parent_guid';
const K_TRUSTED = 'trusted_hosts_json';
const K_LAST_PASSWORD = 'last_password';
const K_FNOS_LONG_TOKEN = 'fnos_long_token';
const K_LOGIN_VIA_WS = 'login_via_ws';
const K_WS_SIGN_KEY_B64 = 'ws_sign_key_b64';
const K_OPENAPI_AUTHX_KEY = 'openapi_authx_key';
const K_OPENAPI_AUTHX_SECRET = 'openapi_authx_secret';
const K_PRIVACY_ACCEPTED = 'privacy_policy_accepted';
/** 飞牛 WS 登录 did，用于 2FA 信任设备识别（退出登录不清理） */
const K_WS_DEVICE_ID = 'ws_device_id';

export interface StoredSession {
  baseUrl: string;
  token: string;
  account: string;
  domainInput: string;
  useHttps: boolean;
  albumParentGuid: string;
  trustedHosts: string[];
  fnosLongToken: string;
  loginViaWebSocket: boolean;
  wsSignKeyB64: string;
  openApiAuthxKey: string;
  openApiAuthxSecret: string;
}

export interface LoginFormDefaults {
  domainInput: string;
  username: string;
  password: string;
  useHttps: boolean;
}

async function openPrefs(ctx: common.UIAbilityContext): Promise<preferences.Preferences> {
  try {
    return await preferences.getPreferences(ctx, PREF_NAME);
  } catch (e) {
    throw new Error(`open preferences failed: ${String(e)}`);
  }
}

async function prefsGetString(p: preferences.Preferences, key: string, def: string): Promise<string> {
  try {
    return await p.get(key, def) as string;
  } catch (e) {
    throw new Error(`preferences get ${key} failed: ${String(e)}`);
  }
}

async function prefsPutString(p: preferences.Preferences, key: string, value: string): Promise<void> {
  try {
    await p.put(key, value);
  } catch (e) {
    throw new Error(`preferences put ${key} failed: ${String(e)}`);
  }
}

async function prefsFlush(p: preferences.Preferences): Promise<void> {
  try {
    await p.flush();
  } catch (e) {
    throw new Error(`preferences flush failed: ${String(e)}`);
  }
}

async function prefsClear(p: preferences.Preferences): Promise<void> {
  try {
    await p.clear();
  } catch (e) {
    throw new Error(`preferences clear failed: ${String(e)}`);
  }
}

function parseTrustedHostsSafe(raw: string): string[] {
  try {
    return JSON.parse(raw) as string[];
  } catch (_e) {
    return [];
  }
}

export class SessionPreferences {
  static async isPrivacyPolicyAccepted(ctx: common.UIAbilityContext): Promise<boolean> {
    const p = await openPrefs(ctx);
    return (await prefsGetString(p, K_PRIVACY_ACCEPTED, '0')) === '1';
  }

  static async setPrivacyPolicyAccepted(ctx: common.UIAbilityContext, accepted: boolean): Promise<void> {
    const p = await openPrefs(ctx);
    await prefsPutString(p, K_PRIVACY_ACCEPTED, accepted ? '1' : '0');
    await prefsFlush(p);
  }

  static async load(ctx: common.UIAbilityContext): Promise<StoredSession | null> {
    const p = await openPrefs(ctx);
    const token = await prefsGetString(p, K_TOKEN, '');
    if (token.length === 0) {
      return null;
    }
    const prefsValues = await Promise.all([
      prefsGetString(p, K_BASE_URL, ''),
      prefsGetString(p, K_ACCOUNT, ''),
      prefsGetString(p, K_DOMAIN_INPUT, ''),
      prefsGetString(p, K_USE_HTTPS, '1'),
      prefsGetString(p, K_ALBUM_PARENT, ''),
      prefsGetString(p, K_TRUSTED, '[]'),
      prefsGetString(p, K_FNOS_LONG_TOKEN, ''),
      prefsGetString(p, K_LOGIN_VIA_WS, '0'),
      prefsGetString(p, K_WS_SIGN_KEY_B64, ''),
      prefsGetString(p, K_OPENAPI_AUTHX_KEY, ''),
      prefsGetString(p, K_OPENAPI_AUTHX_SECRET, '')
    ]);
    return {
      baseUrl: prefsValues[0],
      token: token,
      account: prefsValues[1],
      domainInput: prefsValues[2],
      useHttps: prefsValues[3] === '1',
      albumParentGuid: prefsValues[4],
      trustedHosts: parseTrustedHostsSafe(prefsValues[5]),
      fnosLongToken: prefsValues[6],
      loginViaWebSocket: prefsValues[7] === '1',
      wsSignKeyB64: prefsValues[8],
      openApiAuthxKey: prefsValues[9],
      openApiAuthxSecret: prefsValues[10]
    };
  }

  static async save(ctx: common.UIAbilityContext, s: StoredSession, loginPassword?: string): Promise<void> {
    const p = await openPrefs(ctx);
    await prefsPutString(p, K_BASE_URL, s.baseUrl);
    await prefsPutString(p, K_TOKEN, s.token);
    await prefsPutString(p, K_ACCOUNT, s.account);
    await prefsPutString(p, K_DOMAIN_INPUT, s.domainInput);
    await prefsPutString(p, K_USE_HTTPS, s.useHttps ? '1' : '0');
    await prefsPutString(p, K_ALBUM_PARENT, s.albumParentGuid);
    await prefsPutString(p, K_TRUSTED, JSON.stringify(s.trustedHosts));
    if (loginPassword !== undefined) {
      const prevPw = await prefsGetString(p, K_LAST_PASSWORD, '');
      if (prevPw !== loginPassword) {
        await prefsPutString(p, K_LAST_PASSWORD, loginPassword);
      }
    }
    await prefsPutString(p, K_FNOS_LONG_TOKEN, s.fnosLongToken);
    await prefsPutString(p, K_LOGIN_VIA_WS, s.loginViaWebSocket ? '1' : '0');
    await prefsPutString(p, K_WS_SIGN_KEY_B64, s.wsSignKeyB64.length > 0 ? s.wsSignKeyB64 : '');
    await prefsPutString(p, K_OPENAPI_AUTHX_KEY, s.openApiAuthxKey.length > 0 ? s.openApiAuthxKey : '');
    await prefsPutString(p, K_OPENAPI_AUTHX_SECRET, s.openApiAuthxSecret.length > 0 ? s.openApiAuthxSecret : '');
    await prefsFlush(p);
  }

  /** 读取或生成本机稳定的 WS did（信任设备须每次登录携带同一值） */
  static async ensureWsDeviceId(ctx: common.UIAbilityContext): Promise<string> {
    const p = await openPrefs(ctx);
    let did = (await prefsGetString(p, K_WS_DEVICE_ID, '')).trim();
    if (did.length === 0) {
      did = createFnWsDeviceId();
      await prefsPutString(p, K_WS_DEVICE_ID, did);
      await prefsFlush(p);
    }
    return did;
  }

  static async loadLoginFormDefaults(ctx: common.UIAbilityContext): Promise<LoginFormDefaults> {
    const p = await openPrefs(ctx);
    return {
      domainInput: await prefsGetString(p, K_DOMAIN_INPUT, ''),
      username: await prefsGetString(p, K_ACCOUNT, ''),
      password: await prefsGetString(p, K_LAST_PASSWORD, ''),
      useHttps: (await prefsGetString(p, K_USE_HTTPS, '1')) === '1'
    };
  }

  static async clearSession(ctx: common.UIAbilityContext): Promise<void> {
    const p = await openPrefs(ctx);
    await prefsPutString(p, K_TOKEN, '');
    await prefsPutString(p, K_BASE_URL, '');
    await prefsPutString(p, K_ALBUM_PARENT, '');
    await prefsPutString(p, K_FNOS_LONG_TOKEN, '');
    await prefsPutString(p, K_LOGIN_VIA_WS, '0');
    await prefsPutString(p, K_WS_SIGN_KEY_B64, '');
    await prefsPutString(p, K_OPENAPI_AUTHX_KEY, '');
    await prefsPutString(p, K_OPENAPI_AUTHX_SECRET, '');
    await prefsFlush(p);
  }

  static async loadTrustedHostsSnapshot(ctx: common.UIAbilityContext): Promise<string[]> {
    const p = await openPrefs(ctx);
    return parseTrustedHostsSafe(await prefsGetString(p, K_TRUSTED, '[]'));
  }

  static async clearToken(ctx: common.UIAbilityContext): Promise<void> {
    const p = await openPrefs(ctx);
    await prefsPutString(p, K_TOKEN, '');
    await prefsPutString(p, K_FNOS_LONG_TOKEN, '');
    await prefsPutString(p, K_LOGIN_VIA_WS, '0');
    await prefsPutString(p, K_WS_SIGN_KEY_B64, '');
    await prefsPutString(p, K_OPENAPI_AUTHX_KEY, '');
    await prefsPutString(p, K_OPENAPI_AUTHX_SECRET, '');
    await prefsFlush(p);
  }

  static async clearAll(ctx: common.UIAbilityContext): Promise<void> {
    const p = await openPrefs(ctx);
    await prefsClear(p);
    await prefsFlush(p);
  }
}
