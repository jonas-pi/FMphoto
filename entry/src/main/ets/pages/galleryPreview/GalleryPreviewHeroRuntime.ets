import { getGalleryPreviewDismissProgress } from '../../album/GalleryPreviewVerticalGesture';

export interface GalleryPreviewPlaceholderRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export function galleryPreviewPlaceholderFromPx(
  px2vp: (px: number) => number,
  xPx: number,
  yPx: number,
  wPx: number,
  hPx: number
): GalleryPreviewPlaceholderRect {
  return {
    x: px2vp(xPx),
    y: px2vp(yPx),
    w: px2vp(wPx),
    h: px2vp(hPx)
  };
}

export function galleryPreviewShouldPlayHeroScrim(
  slideshowEnabled: boolean,
  heroScrimEntered: boolean
): boolean {
  return !slideshowEnabled && !heroScrimEntered;
}

export function galleryPreviewScrimDisplayOpacity(baseOpacity: number): number {
  return baseOpacity * (1 - getGalleryPreviewDismissProgress());
}
