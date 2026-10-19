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

/** 沉浸观感不再提供开关。系统版本够就一直开；旧的关闭记录不再生效。 */
export function fnCanUseHdsImmersive(_userEnabled?: boolean): boolean {
  return fnDeviceSupportsHdsImmersive();
}

export function fnSetImmersiveLightEnabled(enabled: boolean): void {
  syncImmersiveLightStorage(enabled);
}

export async function fnLoadImmersiveLightPreference(ctx: common.UIAbilityContext): Promise<boolean> {
  syncImmersiveLightStorage(true);
  try {
    const p = await tryOpenPrefs(ctx);
    if (p !== null) {
      await p.put(K_IMMERSIVE_LIGHT_ENABLED, '1');
      await p.flush();
    }
  } catch (_e) {
  }
  return true;
}
