import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';

const PREF_NAME: string = 'fnos_client_prefs';
const K_IMMERSIVE_LIGHT_ENABLED: string = 'ui_immersive_light_enabled';

export const FN_IMMERSIVE_LIGHT_STORAGE_KEY: string = 'fnImmersiveLightEnabled';
export const FN_HDS_MIN_SDK_API_VERSION: number = 23;

async function tryOpenPrefs(ctx: common.UIAbilityContext): Promise<preferences.Preferences | null> {
  try {
    return await preferences.getPreferences(ctx, PREF_NAME);
  } catch (_e) {
    return null;
  }
}

function syncImmersiveLightStorage(enabled: boolean): void {
  try {
    if (AppStorage.has(FN_IMMERSIVE_LIGHT_STORAGE_KEY)) {
      AppStorage.set<boolean>(FN_IMMERSIVE_LIGHT_STORAGE_KEY, enabled);
      return;
    }
    AppStorage.setOrCreate<boolean>(FN_IMMERSIVE_LIGHT_STORAGE_KEY, enabled);
  } catch (_e) {
  }
}

export function fnCurrentSdkApiVersion(): number {
  try {
    return deviceInfo.sdkApiVersion;
  } catch (_e) {
    return 0;
  }
}

export function fnDeviceSupportsHdsImmersive(): boolean {
  return fnCurrentSdkApiVersion() >= FN_HDS_MIN_SDK_API_VERSION;
}

export function fnIsImmersiveLightPreferenceEnabled(): boolean {
  try {
    const stored = AppStorage.get<boolean>(FN_IMMERSIVE_LIGHT_STORAGE_KEY);
    return stored === undefined ? true : stored;
  } catch (_e) {
    return true;
  }
}

export function fnCanUseHdsImmersive(userEnabled?: boolean): boolean {
  const enabled = userEnabled === undefined ? fnIsImmersiveLightPreferenceEnabled() : userEnabled;
  return enabled && fnDeviceSupportsHdsImmersive();
}

export function fnSetImmersiveLightEnabled(enabled: boolean): void {
  syncImmersiveLightStorage(enabled);
}

export async function fnLoadImmersiveLightPreference(ctx: common.UIAbilityContext): Promise<boolean> {
  let enabled = true;
  try {
    const p = await tryOpenPrefs(ctx);
    if (p === null) {
      syncImmersiveLightStorage(enabled);
      return enabled;
    }
    enabled = (await p.get(K_IMMERSIVE_LIGHT_ENABLED, '1') as string) !== '0';
  } catch (_e) {
    enabled = true;
  }
  syncImmersiveLightStorage(enabled);
  return enabled;
}

export async function fnSaveImmersiveLightPreference(
  ctx: common.UIAbilityContext,
  enabled: boolean
): Promise<void> {
  syncImmersiveLightStorage(enabled);
  try {
    const p = await tryOpenPrefs(ctx);
    if (p === null) {
      return;
    }
    await p.put(K_IMMERSIVE_LIGHT_ENABLED, enabled ? '1' : '0');
    await p.flush();
  } catch (_e) {
  }
}
