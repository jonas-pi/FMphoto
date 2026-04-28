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
