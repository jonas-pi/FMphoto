export const GALLERY_VIDEO_VOLUME_MAX_FALLBACK: number = 15;
/** 滑过屏高约 1/3 即走完全量程，避免按整屏换算发闷 */
export const GALLERY_VIDEO_ADJUST_TRAVEL_RATIO: number = 0.32;

export function galleryVideoClampAdjust(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export function galleryVideoNextBrightness(base: number, offsetY: number, viewH: number): number {
  const travel = Math.max(1, viewH * GALLERY_VIDEO_ADJUST_TRAVEL_RATIO);
  const delta = offsetY / travel;
  return galleryVideoClampAdjust(base - delta, 0, 1);
}

export function galleryVideoNextVolume(
  base: number,
  offsetY: number,
  viewH: number,
  volumeMax: number
): number {
  const travel = Math.max(1, viewH * GALLERY_VIDEO_ADJUST_TRAVEL_RATIO);
  const delta = offsetY / travel;
  return galleryVideoClampAdjust(base - delta * volumeMax, 0, volumeMax);
}
