export enum GalleryViewGranularity {
  DAY = 0,
  MONTH = 1,
  YEAR = 2
}

export function nextGalleryViewGranularity(mode: GalleryViewGranularity): GalleryViewGranularity {
  if (mode === GalleryViewGranularity.MONTH) {
    return GalleryViewGranularity.YEAR;
  }
  if (mode === GalleryViewGranularity.YEAR) {
    return GalleryViewGranularity.DAY;
  }
  return GalleryViewGranularity.MONTH;
}

/** 双指捏合（scale < 1）：日 → 月 → 年，列数变多。 */
export function pinchInGalleryViewGranularity(mode: GalleryViewGranularity): GalleryViewGranularity | null {
  if (mode === GalleryViewGranularity.DAY) {
    return GalleryViewGranularity.MONTH;
  }
  if (mode === GalleryViewGranularity.MONTH) {
    return GalleryViewGranularity.YEAR;
  }
  return null;
}

/** 双指张开（scale > 1）：年 → 月 → 日，列数变少。 */
export function pinchOutGalleryViewGranularity(mode: GalleryViewGranularity): GalleryViewGranularity | null {
  if (mode === GalleryViewGranularity.YEAR) {
    return GalleryViewGranularity.MONTH;
  }
  if (mode === GalleryViewGranularity.MONTH) {
    return GalleryViewGranularity.DAY;
  }
  return null;
}

const GALLERY_PINCH_IN_SCALE: number = 0.86;
const GALLERY_PINCH_OUT_SCALE: number = 1.16;

/** 一次捏合只切一级，与系统图库一致。 */
export function galleryViewGranularityAfterPinch(
  mode: GalleryViewGranularity,
  scale: number
): GalleryViewGranularity | null {
  if (scale <= GALLERY_PINCH_IN_SCALE) {
    return pinchInGalleryViewGranularity(mode);
  }
  if (scale >= GALLERY_PINCH_OUT_SCALE) {
    return pinchOutGalleryViewGranularity(mode);
  }
  return null;
}

export function galleryViewGranularityLabel(mode: GalleryViewGranularity): string {
  if (mode === GalleryViewGranularity.MONTH) {
    return '\u6708';
  }
  if (mode === GalleryViewGranularity.YEAR) {
    return '\u5e74';
  }
  return '\u65e5';
}

export function galleryViewGranularityColumns(mode: GalleryViewGranularity): number {
  if (mode === GalleryViewGranularity.MONTH) {
    return 8;
  }
  if (mode === GalleryViewGranularity.YEAR) {
    return 12;
  }
  return 3;
}

export function galleryViewGranularityTitle(
  year: number,
  month: number,
  day: number,
  mode: GalleryViewGranularity
): string {
  if (mode === GalleryViewGranularity.MONTH) {
    return `${year}\u5e74${month}\u6708`;
  }
  if (mode === GalleryViewGranularity.YEAR) {
    return `${year}\u5e74`;
  }
  return `${year}\u5e74${month}\u6708${day}\u65e5`;
}
