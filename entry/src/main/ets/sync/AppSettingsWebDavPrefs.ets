/**
 * WebDAV 连接配置：仅保存在本机 Preferences，不进入同步信封。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const PREF_NAME: string = 'fnos_client_prefs';
const K_URL: string = 'settings_webdav_url';
const K_USER: string = 'settings_webdav_user';
const K_PASSWORD: string = 'settings_webdav_password';
const K_PATH: string = 'settings_webdav_path';
const K_SKIP_CERT: string = 'settings_webdav_skip_cert';

export const APP_SETTINGS_WEBDAV_DEFAULT_PATH: string = '/fmphoto/settings.json';

export interface AppSettingsWebDavConfig {
  serverUrl: string;
  username: string;
  password: string;
  remotePath: string;
  skipCert: boolean;
}

function emptyConfig(): AppSettingsWebDavConfig {
  return {
    serverUrl: '',
    username: '',
    password: '',
    remotePath: APP_SETTINGS_WEBDAV_DEFAULT_PATH,
    skipCert: true
  };
}

async function openPrefs(ctx: common.UIAbilityContext): Promise<preferences.Preferences | null> {
  try {
    return await preferences.getPreferences(ctx, PREF_NAME);
  } catch (_e) {
    return null;
  }
}

async function prefsGet(p: preferences.Preferences, key: string, def: string): Promise<string> {
  try {
    return await p.get(key, def) as string;
  } catch (_e) {
    return def;
  }
}

export async function loadWebDavConfig(ctx: common.UIAbilityContext): Promise<AppSettingsWebDavConfig> {
  const p = await openPrefs(ctx);
  if (p === null) {
    return emptyConfig();
  }
  const path = (await prefsGet(p, K_PATH, APP_SETTINGS_WEBDAV_DEFAULT_PATH)).trim();
  return {
    serverUrl: (await prefsGet(p, K_URL, '')).trim(),
    username: await prefsGet(p, K_USER, ''),
    password: await prefsGet(p, K_PASSWORD, ''),
    remotePath: path.length > 0 ? path : APP_SETTINGS_WEBDAV_DEFAULT_PATH,
    skipCert: (await prefsGet(p, K_SKIP_CERT, '1')) !== '0'
  };
}

export async function saveWebDavConfig(
  ctx: common.UIAbilityContext,
  config: AppSettingsWebDavConfig
): Promise<boolean> {
  const p = await openPrefs(ctx);
  if (p === null) {
    return false;
  }
  try {
    const path = config.remotePath.trim().length > 0 ? config.remotePath.trim() : APP_SETTINGS_WEBDAV_DEFAULT_PATH;
    await p.put(K_URL, config.serverUrl.trim());
    await p.put(K_USER, config.username);
    await p.put(K_PASSWORD, config.password);
    await p.put(K_PATH, path);
    await p.put(K_SKIP_CERT, config.skipCert ? '1' : '0');
    await p.flush();
    return true;
  } catch (_e) {
    return false;
  }
}
