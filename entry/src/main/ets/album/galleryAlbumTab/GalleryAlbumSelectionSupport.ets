import { SelectionGestureControllerHost } from './SelectionGestureController';
import { GalleryListItem } from '../../model/FnApiTypes';
import { GalleryPreviewNavStore } from '../GalleryPreviewNavStore';

export function galleryAlbumOpenPreview(host: SelectionGestureControllerHost, flatIndex: number): void {
  if (flatIndex < 0) {
    return;
  }
  GalleryPreviewNavStore.openPreview(host.getUIContext(), host.baseUrl, host.flatItems(), flatIndex);
}

export function galleryAlbumResolveGalleryFlatIndexForOpenPreview(
  host: SelectionGestureControllerHost,
  item: GalleryListItem,
  hintFlat: number
): number {
  const id = host.itemIdOf(item);
  const items = host.flatItems();
  if (id.length > 0) {
    for (let i = 0; i < items.length; i++) {
      if (host.itemIdOf(items[i]) === id) {
        return i;
      }
    }
  }
  if (items.length <= 0) {
    return hintFlat >= 0 ? hintFlat : 0;
  }
  if (hintFlat >= 0 && hintFlat < items.length) {
    return hintFlat;
  }
  return Math.max(0, Math.min(items.length - 1, hintFlat));
}

export function galleryAlbumExitSelection(host: SelectionGestureControllerHost): void {
  host.gallerySelectionMode = false;
  host.galleryTimelineRefreshing = false;
  galleryAlbumSetGallerySelectedIdsState(host, []);
  host.gallerySlideGestureActive = false;
  host.gallerySlideHasRef = false;
  host.gallerySlideAnchorFlat = -1;
  host.gallerySlideUnionBase = [];
  host.gallerySlideLastEndFlat = -1;
  host.gallerySlideLastAppliedEndFlat = -99999;
  host.gallerySlideLastApplyMs = 0;
  host.gallerySlidePendingEndFlat = -1;
  host.galleryThumbHitBounds.clear();
  host.searchThumbHitBounds.clear();
  host.galleryMainListScrollEnabled = true;
}

export function galleryAlbumSameGalleryIdBagUnordered(a: string[], b: string[]): boolean {
  if (a === b) {
    return true;
  }
  if (a.length !== b.length) {
    return false;
  }
  if (a.length === 0) {
    return true;
  }
  let sameOrder = true;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      sameOrder = false;
      break;
    }
  }
  if (sameOrder) {
    return true;
  }
  const counts = new Map<string, number>();
  for (let i = 0; i < a.length; i++) {
    const key = a[i];
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  for (let i = 0; i < b.length; i++) {
    const key = b[i];
    const next = (counts.get(key) ?? 0) - 1;
    if (next < 0) {
      return false;
    }
    counts.set(key, next);
  }
  let allZero = true;
  counts.forEach((value: number): void => {
    if (value !== 0) {
      allZero = false;
    }
  });
  return allZero;
}

export function galleryAlbumSetGallerySelectedIdsState(
  host: SelectionGestureControllerHost,
  next: string[]
): void {
  if (galleryAlbumSameGalleryIdBagUnordered(host.gallerySelectedIds, next)) {
    return;
  }
  host.gallerySelectedIds = next;
}

export function galleryAlbumGalleryThumbDomId(photoId: string): string {
  let normalized = '';
  for (let i = 0; i < photoId.length; i++) {
    const code = photoId.charCodeAt(i);
    if ((code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code === 95) {
      normalized += String.fromCharCode(code);
    } else {
      normalized += '_';
    }
  }
  return `gt_${normalized.length > 0 ? normalized : 'noid'}`;
}

export function galleryAlbumRecordGalleryThumbRectFromDom(
  host: SelectionGestureControllerHost,
  photoId: string,
  domId: string
): void {
  if (photoId.length === 0) {
    return;
  }
  try {
    const info = host.getUIContext().getComponentUtils().getRectangleById(domId);
    const x = info.windowOffset.x as number;
    const y = info.windowOffset.y as number;
    const w = info.size.width as number;
    const h = info.size.height as number;
    if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
      host.galleryThumbHitBounds.delete(photoId);
      return;
    }
    host.galleryThumbHitBounds.set(photoId, {
      left: x,
      top: y,
      right: x + w,
      bottom: y + h
    });
  } catch (_e) {
  }
}

export function galleryAlbumCollectGalleryIdsInFlatRange(
  host: SelectionGestureControllerHost,
  lo: number,
  hi: number
): string[] {
  let start = lo;
  let end = hi;
  if (start > end) {
    const temp = start;
    start = end;
    end = temp;
  }
  const out: string[] = [];
  const all = host.flatItems();
  if (all.length === 0) {
    return out;
  }
  const lo2 = Math.max(0, start);
  const hi2 = Math.min(end, all.length - 1);
  if (lo2 > hi2) {
    return out;
  }
  for (let fi = lo2; fi <= hi2; fi++) {
    const id = host.itemIdOf(all[fi]);
    if (id.length > 0) {
      out.push(id);
    }
  }
  return out;
}

export function galleryAlbumCollectSearchIdsInFlatRange(
  host: SelectionGestureControllerHost,
  lo: number,
  hi: number
): string[] {
  let start = lo;
  let end = hi;
  if (start > end) {
    const temp = start;
    start = end;
    end = temp;
  }
  const out: string[] = [];
  const total = host.searchResults.length;
  for (let fi = start; fi <= end && fi < total; fi++) {
    const id = host.itemIdOf(host.searchResults[fi]);
    if (id.length > 0) {
      out.push(id);
    }
  }
  return out;
}
