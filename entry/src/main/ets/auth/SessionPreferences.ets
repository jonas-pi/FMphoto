import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { createFnWsDeviceId } from '../network/FnWsDeviceId';

const PREF_NAME = 'fnos_client_prefs';

const K_BASE_URL = 'base_url';
const K_TOKEN = 'token';
const K_ACCOUNT = 'account';
const K_DOMAIN_INPUT = 'domain_input';
const K_FN_ID_INPUT = 'fn_id_input';
const K_LAN_INPUT = 'lan_input';
const K_ENDPOINT_PUBLIC_URL = 'endpoint_public_url';
const K_ENDPOINT_PUBLIC_DOMAIN_URL = 'endpoint_public_domain_url';
const K_ENDPOINT_PUBLIC_IP_URL = 'endpoint_public_ip_url';
const K_ENDPOINT_LAN_URL = 'endpoint_lan_url';
const K_ENDPOINT_LAN_IPV6_URL = 'endpoint_lan_ipv6_url';
const K_ENDPOINT_PUBLIC_IPV6_URL = 'endpoint_public_ipv6_url';
const K_ENDPOINT_RELAY_URL = 'endpoint_relay_url';
const K_LOGIN_ENDPOINT_PREF = 'login_endpoint_pref';
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
  /** 登录表单 FN ID（可选） */
  fnIdInput: string;
  /** 登录表单公网域名（可选） */
  domainInput: string;
  /** 登录表单内网栏原文 */
  lanInput: string;
  /** 可切换的公网地址（域名优先后的首选） */
  endpointPublicUrl: string;
  /** 公网域名 baseUrl（若有） */
  endpointPublicDomainUrl: string;
  /** 公网 IP baseUrl（若有） */
  endpointPublicIpUrl: string;
  /** 可切换的内网 IPv4 baseUrl（规范化） */
  endpointLanUrl: string;
  /** 可切换的内网 IPv6 baseUrl（规范化） */
  endpointLanIpv6Url: string;
  /** 可切换的公网 IPv6 baseUrl（规范化） */
  endpointPublicIpv6Url: string;
  /** 可切换的中继 baseUrl（规范化，如 https://{fnId}.fnos.net 或 https://{fnId}.5ddd.com） */
  endpointRelayUrl: string;
  loginEndpointPreference: string;
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
  fnIdInput: string;
  domainInput: string;
  lanInput: string;
  loginEndpointPreference: string;
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

async function prefsDelete(p: preferences.Preferences, key: string): Promise<void> {
  try {
    await p.delete(key);
  } catch (_e) {
    try {
      await p.put(key, '');
    } catch (e) {
      throw new Error(`preferences delete ${key} failed: ${String(e)}`);
    }
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
      prefsGetString(p, K_FN_ID_INPUT, ''),
      prefsGetString(p, K_DOMAIN_INPUT, ''),
      prefsGetString(p, K_LAN_INPUT, ''),
      prefsGetString(p, K_ENDPOINT_PUBLIC_URL, ''),
      prefsGetString(p, K_ENDPOINT_PUBLIC_DOMAIN_URL, ''),
      prefsGetString(p, K_ENDPOINT_PUBLIC_IP_URL, ''),
      prefsGetString(p, K_ENDPOINT_LAN_URL, ''),
      prefsGetString(p, K_ENDPOINT_RELAY_URL, ''),
      prefsGetString(p, K_LOGIN_ENDPOINT_PREF, 'auto'),
      prefsGetString(p, K_USE_HTTPS, '1'),
      prefsGetString(p, K_ALBUM_PARENT, ''),
      prefsGetString(p, K_TRUSTED, '[]'),
      prefsGetString(p, K_FNOS_LONG_TOKEN, ''),
      prefsGetString(p, K_LOGIN_VIA_WS, '0'),
      prefsGetString(p, K_WS_SIGN_KEY_B64, ''),
      prefsGetString(p, K_OPENAPI_AUTHX_KEY, ''),
      prefsGetString(p, K_OPENAPI_AUTHX_SECRET, ''),
      prefsGetString(p, K_ENDPOINT_LAN_IPV6_URL, ''),
      prefsGetString(p, K_ENDPOINT_PUBLIC_IPV6_URL, '')
    ]);
    return {
      baseUrl: prefsValues[0],
      token: token,
      account: prefsValues[1],
      fnIdInput: prefsValues[2],
      domainInput: prefsValues[3],
      lanInput: prefsValues[4],
      endpointPublicUrl: prefsValues[5],
      endpointPublicDomainUrl: prefsValues[6],
      endpointPublicIpUrl: prefsValues[7],
      endpointLanUrl: prefsValues[8],
      endpointRelayUrl: prefsValues[9],
      loginEndpointPreference: prefsValues[10].length > 0 ? prefsValues[10] : 'auto',
      useHttps: prefsValues[11] === '1',
      albumParentGuid: prefsValues[12],
      trustedHosts: parseTrustedHostsSafe(prefsValues[13]),
      fnosLongToken: prefsValues[14],
      loginViaWebSocket: prefsValues[15] === '1',
      wsSignKeyB64: prefsValues[16],
      openApiAuthxKey: prefsValues[17],
      openApiAuthxSecret: prefsValues[18],
      endpointLanIpv6Url: prefsValues[19],
      endpointPublicIpv6Url: prefsValues[20]
    };
  }

  static async save(ctx: common.UIAbilityContext, s: StoredSession): Promise<void> {
    const p = await openPrefs(ctx);
    await prefsPutString(p, K_BASE_URL, s.baseUrl);
    await prefsPutString(p, K_TOKEN, s.token);
    await prefsPutString(p, K_ACCOUNT, s.account);
    await prefsPutString(p, K_FN_ID_INPUT, s.fnIdInput);
    await prefsPutString(p, K_DOMAIN_INPUT, s.domainInput);
    await prefsPutString(p, K_LAN_INPUT, s.lanInput);
    await prefsPutString(p, K_ENDPOINT_PUBLIC_URL, s.endpointPublicUrl);
    await prefsPutString(p, K_ENDPOINT_PUBLIC_DOMAIN_URL, s.endpointPublicDomainUrl);
    await prefsPutString(p, K_ENDPOINT_PUBLIC_IP_URL, s.endpointPublicIpUrl);
    await prefsPutString(p, K_ENDPOINT_LAN_URL, s.endpointLanUrl);
    await prefsPutString(p, K_ENDPOINT_LAN_IPV6_URL, s.endpointLanIpv6Url);
    await prefsPutString(p, K_ENDPOINT_PUBLIC_IPV6_URL, s.endpointPublicIpv6Url);
    await prefsPutString(p, K_ENDPOINT_RELAY_URL, s.endpointRelayUrl);
    await prefsPutString(p, K_LOGIN_ENDPOINT_PREF, s.loginEndpointPreference);
    await prefsPutString(p, K_USE_HTTPS, s.useHttps ? '1' : '0');
    await prefsPutString(p, K_ALBUM_PARENT, s.albumParentGuid);
    await prefsPutString(p, K_TRUSTED, JSON.stringify(s.trustedHosts));
    // 不落盘密码：清掉历史 last_password，切网/静默重登只用进程内口令
    await prefsDelete(p, K_LAST_PASSWORD);
    await prefsPutString(p, K_FNOS_LONG_TOKEN, s.fnosLongToken);
    await prefsPutString(p, K_LOGIN_VIA_WS, s.loginViaWebSocket ? '1' : '0');
    await prefsPutString(p, K_WS_SIGN_KEY_B64, s.wsSignKeyB64.length > 0 ? s.wsSignKeyB64 : '');
    await prefsPutString(p, K_OPENAPI_AUTHX_KEY, s.openApiAuthxKey.length > 0 ? s.openApiAuthxKey : '');
    await prefsPutString(p, K_OPENAPI_AUTHX_SECRET, s.openApiAuthxSecret.length > 0 ? s.openApiAuthxSecret : '');
    await prefsFlush(p);
  }

  /** 只写登录表单（不含密码、不含会话 token），退出登录后仍可回填。 */
  static async saveLoginFormDefaults(ctx: common.UIAbilityContext, d: LoginFormDefaults): Promise<void> {
    const p = await openPrefs(ctx);
    await prefsPutString(p, K_FN_ID_INPUT, d.fnIdInput);
    await prefsPutString(p, K_DOMAIN_INPUT, d.domainInput);
    await prefsPutString(p, K_LAN_INPUT, d.lanInput);
    await prefsPutString(p, K_LOGIN_ENDPOINT_PREF, d.loginEndpointPreference.length > 0 ? d.loginEndpointPreference : 'auto');
    await prefsPutString(p, K_ACCOUNT, d.username);
    await prefsPutString(p, K_USE_HTTPS, d.useHttps ? '1' : '0');
    await prefsDelete(p, K_LAST_PASSWORD);
    await prefsFlush(p);
  }

  static loginFormFromStored(s: StoredSession): LoginFormDefaults {
    return {
      fnIdInput: s.fnIdInput,
      domainInput: s.domainInput,
      lanInput: s.lanInput,
      loginEndpointPreference: s.loginEndpointPreference,
      username: s.account,
      password: '',
      useHttps: s.useHttps
    };
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
    let fnId = await prefsGetString(p, K_FN_ID_INPUT, '');
    let domain = await prefsGetString(p, K_DOMAIN_INPUT, '');
    // 旧版把 FN ID 写在 domain_input：迁移到独立 FN ID 栏
    if (fnId.length === 0 && domain.length > 0) {
      const migrated = domain.trim();
      // 纯 FN ID 形态（无点号等）才迁移，避免误伤真正域名
      if (/^[a-zA-Z][a-zA-Z0-9-]{4,31}$/.test(migrated) && !migrated.endsWith('-') &&
        migrated.indexOf('.') < 0) {
        fnId = migrated;
        domain = '';
      }
    }
    const leftoverPassword = await prefsGetString(p, K_LAST_PASSWORD, '');
    if (leftoverPassword.length > 0) {
      await prefsDelete(p, K_LAST_PASSWORD);
      await prefsFlush(p);
    }
    return {
      fnIdInput: fnId,
      domainInput: domain,
      lanInput: await prefsGetString(p, K_LAN_INPUT, ''),
      loginEndpointPreference: await prefsGetString(p, K_LOGIN_ENDPOINT_PREF, 'auto'),
      username: await prefsGetString(p, K_ACCOUNT, ''),
      password: '',
      useHttps: (await prefsGetString(p, K_USE_HTTPS, '1')) === '1'
    };
  }

  /** 只清会话凭据。FN ID / 域名 / 用户名 / 选路策略等登录表单一律保留。 */
  static async clearSession(ctx: common.UIAbilityContext): Promise<void> {
    const form = await SessionPreferences.loadLoginFormDefaults(ctx);
    const stored = await SessionPreferences.load(ctx);
    const keep = stored !== null ? SessionPreferences.loginFormFromStored(stored) : form;
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
    await SessionPreferences.saveLoginFormDefaults(ctx, keep);
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
