/**
 * 预览页视频播控与底栏联动：放在 AppStorage，避免父页 @State 带动整页 Swiper 重绘。
 */
import { common } from '@kit.AbilityKit';
import { UIContext, window } from '@kit.ArkUI';

export const GALLERY_PREVIEW_VIDEO_ACTIVE_KEY: string = 'galleryPreviewVideoActive';
export const GALLERY_PREVIEW_VIDEO_PLAYING_KEY: string = 'galleryPreviewVideoPlaying';
export const GALLERY_PREVIEW_VIDEO_MUTED_KEY: string = 'galleryPreviewVideoMuted';
export const GALLERY_PREVIEW_VIDEO_DOCK_EXPANDED_KEY: string = 'galleryPreviewVideoDockExpanded';
export const GALLERY_PREVIEW_VIDEO_LANDSCAPE_KEY: string = 'galleryPreviewVideoLandscape';
export const GALLERY_PREVIEW_VIDEO_TOGGLE_PLAY_SEQ_KEY: string = 'galleryPreviewVideoTogglePlaySeq';
export const GALLERY_PREVIEW_VIDEO_TOGGLE_MUTE_SEQ_KEY: string = 'galleryPreviewVideoToggleMuteSeq';

export function setGalleryPreviewVideoActive(active: boolean): void {
  AppStorage.setOrCreate<boolean>(GALLERY_PREVIEW_VIDEO_ACTIVE_KEY, active);
}

export function setGalleryPreviewVideoPlaying(playing: boolean): void {
  AppStorage.setOrCreate<boolean>(GALLERY_PREVIEW_VIDEO_PLAYING_KEY, playing);
}

export function setGalleryPreviewVideoMuted(muted: boolean): void {
  AppStorage.setOrCreate<boolean>(GALLERY_PREVIEW_VIDEO_MUTED_KEY, muted);
}

export function setGalleryPreviewVideoDockExpanded(expanded: boolean): void {
  AppStorage.setOrCreate<boolean>(GALLERY_PREVIEW_VIDEO_DOCK_EXPANDED_KEY, expanded);
}

export function setGalleryPreviewVideoLandscape(landscape: boolean): void {
  AppStorage.setOrCreate<boolean>(GALLERY_PREVIEW_VIDEO_LANDSCAPE_KEY, landscape);
}

export function requestGalleryPreviewVideoTogglePlay(): void {
  const cur = AppStorage.get<number>(GALLERY_PREVIEW_VIDEO_TOGGLE_PLAY_SEQ_KEY);
  const next = (cur !== undefined ? cur : 0) + 1;
  AppStorage.setOrCreate<number>(GALLERY_PREVIEW_VIDEO_TOGGLE_PLAY_SEQ_KEY, next);
}

export function requestGalleryPreviewVideoToggleMute(): void {
  const cur = AppStorage.get<number>(GALLERY_PREVIEW_VIDEO_TOGGLE_MUTE_SEQ_KEY);
  const next = (cur !== undefined ? cur : 0) + 1;
  AppStorage.setOrCreate<number>(GALLERY_PREVIEW_VIDEO_TOGGLE_MUTE_SEQ_KEY, next);
}

export function resetGalleryPreviewVideoChrome(): void {
  setGalleryPreviewVideoActive(false);
  setGalleryPreviewVideoPlaying(false);
  setGalleryPreviewVideoMuted(false);
  setGalleryPreviewVideoDockExpanded(false);
}

export async function restoreGalleryPreviewPortrait(ui: UIContext): Promise<void> {
  const landscape = AppStorage.get<boolean>(GALLERY_PREVIEW_VIDEO_LANDSCAPE_KEY);
  if (landscape !== true) {
    return;
  }
  try {
    const ctx = ui.getHostContext() as common.UIAbilityContext;
    const win = await window.getLastWindow(ctx);
    await win.setPreferredOrientation(window.Orientation.PORTRAIT);
  } catch (_e) {
  }
  setGalleryPreviewVideoLandscape(false);
}
