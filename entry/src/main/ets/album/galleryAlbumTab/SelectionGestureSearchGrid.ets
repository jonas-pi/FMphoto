import { pickIndexedFlatForSlidePointer } from '../GallerySlidePick';
import { GalleryThumbHitRect } from './GalleryAlbumTabTypes';
import { SelectionGestureControllerHost } from './SelectionGestureHost';

export function pickSearchThumbFlatUnderPointForSlide(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): number {
  return pickIndexedFlatForSlidePointer(
    xPx,
    yPx,
    host.searchResults.length,
    host.gallerySlideLastEndFlat,
    host.gallerySlideAnchorFlat,
    (ax: number, ay: number): number => selectionPickSearchThumbFlatUnderPoint(host, ax, ay),
    (fi: number) => host.searchThumbHitBounds.get(`${fi}`),
    (fi: number, ax: number, ay: number): boolean => selectionHitSearchThumbDomPx(host, fi, ax, ay),
    (fi: number): void => {
      selectionRecordSearchThumbRect(host, fi);
    }
  );
}

function selectionRectContainsPx(rect: GalleryThumbHitRect, xPx: number, yPx: number): boolean {
  return xPx >= rect.left && xPx <= rect.right && yPx >= rect.top && yPx <= rect.bottom;
}

export function collectSearchIdsInFlatRange(host: SelectionGestureControllerHost, lo: number, hi: number): string[] {
  let a = lo;
  let b = hi;
  if (a > b) {
    const t = a;
    a = b;
    b = t;
  }
  const out: string[] = [];
  const n = host.searchResults.length;
  for (let fi = a; fi <= b && fi < n; fi++) {
    const id = host.itemIdOf(host.searchResults[fi]);
    if (id.length > 0) {
      out.push(id);
    }
  }
  return out;
}

export function selectionSearchThumbDomId(
  _host: SelectionGestureControllerHost,
  flatIdx: number
): string {
  return `sg_${flatIdx}`;
}

export function selectionRecordSearchThumbRect(
  host: SelectionGestureControllerHost,
  flatIdx: number
): void {
  if (flatIdx < 0 || flatIdx >= host.searchResults.length) {
    return;
  }
  try {
    const info = host.getUIContext().getComponentUtils().getRectangleById(selectionSearchThumbDomId(host, flatIdx));
    const x = info.windowOffset.x as number;
    const y = info.windowOffset.y as number;
    const w = info.size.width as number;
    const h = info.size.height as number;
    if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
      host.searchThumbHitBounds.delete(`${flatIdx}`);
      return;
    }
    const rect: GalleryThumbHitRect = {
      left: x,
      top: y,
      right: x + w,
      bottom: y + h
    };
    host.searchThumbHitBounds.set(`${flatIdx}`, rect);
  } catch (_e) {
  }
}

export function selectionHitSearchThumbDomPx(
  host: SelectionGestureControllerHost,
  flatIdx: number,
  xPx: number,
  yPx: number
): boolean {
  if (flatIdx < 0 || flatIdx >= host.searchResults.length) {
    return false;
  }
  try {
    const info = host.getUIContext().getComponentUtils().getRectangleById(selectionSearchThumbDomId(host, flatIdx));
    const left = info.windowOffset.x as number;
    const top = info.windowOffset.y as number;
    const w = info.size.width as number;
    const h = info.size.height as number;
    if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
      return false;
    }
    return xPx >= left && xPx <= left + w && yPx >= top && yPx <= top + h;
  } catch (_e) {
    return false;
  }
}

function selectionCachedSearchThumbHitValidPx(
  host: SelectionGestureControllerHost,
  flatIdx: number,
  xPx: number,
  yPx: number
): boolean {
  const cached = host.searchThumbHitBounds.get(`${flatIdx}`);
  return cached !== undefined && selectionRectContainsPx(cached, xPx, yPx);
}

export function selectionPickSearchThumbFlatUnderPoint(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): number {
  const n = host.searchResults.length;
  if (host.searchThumbHitBounds.size === 0 || n <= 0) {
    return -1;
  }
  for (let i = n - 1; i >= 0; i--) {
    if (selectionCachedSearchThumbHitValidPx(host, i, xPx, yPx)) {
      return i;
    }
  }
  return -1;
}

export function selectionPickSearchThumbFlatForRow(
  host: SelectionGestureControllerHost,
  rowStart: number,
  xPx: number,
  yPx: number
): number {
  const n = host.searchResults.length;
  const columnsPerRow = Math.max(1, Math.floor(host.searchGridColumns));
  const fromCache = selectionPickSearchThumbFlatUnderPoint(host, xPx, yPx);
  if (fromCache >= rowStart && fromCache < rowStart + columnsPerRow && fromCache < n) {
    return fromCache;
  }
  for (let k = columnsPerRow - 1; k >= 0; k--) {
    const fi = rowStart + k;
    if (fi >= n) {
      continue;
    }
    if (selectionCachedSearchThumbHitValidPx(host, fi, xPx, yPx)) {
      return fi;
    }
    if (selectionHitSearchThumbDomPx(host, fi, xPx, yPx)) {
      selectionRecordSearchThumbRect(host, fi);
      return fi;
    }
  }
  return -1;
}
