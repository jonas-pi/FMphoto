import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  GALLERY_SLIDESHOW_DEFAULT_INTERVAL_SEC,
  GallerySlideshowConfig,
  gallerySlideshowDefaultConfig
} from './GallerySlideshowTypes';

const PREF_NAME: string = 'fnos_client_prefs';
const K_SLIDESHOW_INTERVAL_SEC: string = 'gallery_slideshow_interval_sec';
const K_SLIDESHOW_INCLUDE_VIDEO: string = 'gallery_slideshow_include_video';
const K_SLIDESHOW_INCLUDE_GIF: string = 'gallery_slideshow_include_gif';

async function openPrefs(ctx: common.UIAbilityContext): Promise<preferences.Preferences | null> {
  try {
    return await preferences.getPreferences(ctx, PREF_NAME);
  } catch (_e) {
    return null;
  }
}

function clampIntervalSec(value: number): number {
  if (!Number.isFinite(value)) {
    return GALLERY_SLIDESHOW_DEFAULT_INTERVAL_SEC;
  }
  return Math.max(2, Math.min(120, Math.floor(value)));
}

export async function gallerySlideshowLoadConfig(ctx: common.UIAbilityContext): Promise<GallerySlideshowConfig> {
  const defaults = gallerySlideshowDefaultConfig();
  const p = await openPrefs(ctx);
  if (p === null) {
    return defaults;
  }
  try {
    const intervalRaw = await p.get(K_SLIDESHOW_INTERVAL_SEC, `${defaults.intervalSec}`) as string;
    const intervalSec = clampIntervalSec(Number(intervalRaw));
    const includeVideo = (await p.get(K_SLIDESHOW_INCLUDE_VIDEO, '1') as string) !== '0';
    const includeGif = (await p.get(K_SLIDESHOW_INCLUDE_GIF, '1') as string) !== '0';
    return { intervalSec, includeVideo, includeGif };
  } catch (_e) {
    return defaults;
  }
}

export async function gallerySlideshowSaveConfig(
  ctx: common.UIAbilityContext,
  config: GallerySlideshowConfig
): Promise<void> {
  const p = await openPrefs(ctx);
  if (p === null) {
    return;
  }
  try {
    await p.put(K_SLIDESHOW_INTERVAL_SEC, `${clampIntervalSec(config.intervalSec)}`);
    await p.put(K_SLIDESHOW_INCLUDE_VIDEO, config.includeVideo ? '1' : '0');
    await p.put(K_SLIDESHOW_INCLUDE_GIF, config.includeGif ? '1' : '0');
    await p.flush();
  } catch (_e) {
  }
}
