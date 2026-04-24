import { UIContext } from '@kit.ArkUI';
import { GalleryListItem } from '../../model/FnApiTypes';
import { playGalleryEnterSelectionHaptic } from '../../album/GallerySelectionHaptic';
import {
  GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE,
  GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE,
  pickIndexedFlatForSlidePointer
} from '../../album/GallerySlidePick';
import {
  CgFingerCoordCompat,
  CgFingerWindowPoint,
  CgThumbHitRect,
  RowModel
} from './CategoryGalleryTypes';

export interface CategoryGallerySelectionHost {
  getUIContext(): UIContext;
  flatItems: GalleryListItem[];
  groupOffsets: number[];
  selectionMode: boolean;
  selectedIds: string[];
  cgSlideGestureActive: boolean;
  cgScrollEnabled: boolean;
  cgLongPressIgnoreUntil: number;
  cgThumbHitBounds: Map<string, CgThumbHitRect>;
  cgSlideRefX: number;
  cgSlideRefY: number;
  cgSlideHasRef: boolean;
  cgSlideAnchorFlat: number;
  cgSlideUnionBase: string[];
  cgSlideLastEndFlat: number;
  cgSlideLastAppliedEndFlat: number;
  toast(msg: string): void;
  openItemAtFlat(flatIdx: number): void;
}

export function categoryGalleryItemIdOf(it: GalleryListItem): string {
  if (it.id === undefined || it.id === null) {
    return '';
  }
  return String(it.id).trim();
}

export function categoryGalleryFlatPos(
  host: CategoryGallerySelectionHost,
  groupIdx: number,
  idxInGroup: number
): number {
  const base = groupIdx >= 0 && groupIdx < host.groupOffsets.length ? host.groupOffsets[groupIdx] : 0;
  return base + idxInGroup;
}

export function categoryGalleryDomId(flatIdx: number): string {
  return `cgcell_${flatIdx}`;
}

export function categoryGalleryRowGlobalStartFlat(
  host: CategoryGallerySelectionHost,
  groupIdx: number,
  row: RowModel
): number {
  return categoryGalleryFlatPos(host, groupIdx, row.startIdx);
}

export function categoryGallerySlidePanDistance(active: boolean): number {
  return active ? GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE : GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE;
}

export function categoryGalleryExitSelection(host: CategoryGallerySelectionHost): void {
  host.selectionMode = false;
  host.selectedIds = [];
  categoryGalleryEndSlideSelectGesture(host);
  host.cgLongPressIgnoreUntil = 0;
  host.cgThumbHitBounds.clear();
}

export function categoryGalleryToggleToolbarMode(host: CategoryGallerySelectionHost): void {
  if (host.selectionMode) {
    categoryGalleryExitSelection(host);
  } else {
    host.selectionMode = true;
  }
}

export function categoryGalleryIsIdSelected(host: CategoryGallerySelectionHost, id: string): boolean {
  return id.length > 0 && host.selectedIds.indexOf(id) >= 0;
}

export function categoryGalleryToggleId(host: CategoryGallerySelectionHost, id: string): void {
  if (id.length === 0) {
    return;
  }
  const idx = host.selectedIds.indexOf(id);
  if (idx >= 0) {
    const next: string[] = [];
    for (let i = 0; i < host.selectedIds.length; i++) {
      if (i !== idx) {
        next.push(host.selectedIds[i]);
      }
    }
    host.selectedIds = next;
  } else {
    const next: string[] = host.selectedIds.slice();
    next.push(id);
    host.selectedIds = next;
  }
}

export function categoryGalleryReadGestureFingerWindow(ev: GestureEvent): CgFingerWindowPoint | null {
  const fl = ev.fingerList;
  if (fl === undefined || fl.length < 1) {
    return null;
  }
  const f0 = fl[0] as CgFingerCoordCompat;
  const x = f0.windowX ?? f0.globalX ?? f0.screenX ?? f0.displayX ?? f0.x;
  const y = f0.windowY ?? f0.globalY ?? f0.screenY ?? f0.displayY ?? f0.y;
  if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
    return null;
  }
  return { x, y };
}

export function categoryGalleryPanOffsetVpToPx(deltaVp: number): number {
  const probePx = 100;
  const probeVp = px2vp(probePx);
  if (probeVp < 0.0001) {
    return deltaVp;
  }
  return deltaVp * (probePx / probeVp);
}

export function categoryGalleryRecordThumbRect(host: CategoryGallerySelectionHost, flatIdx: number): void {
  if (flatIdx < 0 || flatIdx >= host.flatItems.length) {
    return;
  }
  try {
    const info = host.getUIContext().getComponentUtils().getRectangleById(categoryGalleryDomId(flatIdx));
    const x = info.windowOffset.x as number;
    const y = info.windowOffset.y as number;
    const w = info.size.width as number;
    const h = info.size.height as number;
    if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
      host.cgThumbHitBounds.delete(`${flatIdx}`);
      return;
    }
    host.cgThumbHitBounds.set(`${flatIdx}`, { left: x, top: y, right: x + w, bottom: y + h });
  } catch (_e) {
  }
}

export function categoryGalleryHitThumbDomPx(
  host: CategoryGallerySelectionHost,
  flatIdx: number,
  xPx: number,
  yPx: number
): boolean {
  if (flatIdx < 0 || flatIdx >= host.flatItems.length) {
    return false;
  }
  try {
    const info = host.getUIContext().getComponentUtils().getRectangleById(categoryGalleryDomId(flatIdx));
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

export function categoryGalleryPickFlatUnderPoint(
  host: CategoryGallerySelectionHost,
  xPx: number,
  yPx: number
): number {
  const n = host.flatItems.length;
  if (host.cgThumbHitBounds.size === 0 || n <= 0) {
    return -1;
  }
  for (let i = n - 1; i >= 0; i--) {
    const cached = host.cgThumbHitBounds.get(`${i}`);
    if (cached === undefined) {
      continue;
    }
    if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
      return i;
    }
  }
  return -1;
}

export function categoryGalleryPickFlatForRow(
  host: CategoryGallerySelectionHost,
  rowStart: number,
  xPx: number,
  yPx: number
): number {
  const n = host.flatItems.length;
  const fromCache = categoryGalleryPickFlatUnderPoint(host, xPx, yPx);
  if (fromCache >= rowStart && fromCache < rowStart + 3 && fromCache < n) {
    return fromCache;
  }
  for (let k = 2; k >= 0; k--) {
    const fi = rowStart + k;
    if (fi >= n) {
      continue;
    }
    const cached = host.cgThumbHitBounds.get(`${fi}`);
    if (cached !== undefined) {
      if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
        return fi;
      }
      continue;
    }
    if (categoryGalleryHitThumbDomPx(host, fi, xPx, yPx)) {
      return fi;
    }
  }
  return -1;
}

export function categoryGalleryPickFlatForSlidePointer(
  host: CategoryGallerySelectionHost,
  xPx: number,
  yPx: number
): number {
  return pickIndexedFlatForSlidePointer(
    xPx,
    yPx,
    host.flatItems.length,
    host.cgSlideLastEndFlat,
    host.cgSlideAnchorFlat,
    (ax: number, ay: number): number => categoryGalleryPickFlatUnderPoint(host, ax, ay),
    (fi: number): CgThumbHitRect | undefined => host.cgThumbHitBounds.get(`${fi}`),
    (fi: number, ax: number, ay: number): boolean => categoryGalleryHitThumbDomPx(host, fi, ax, ay),
    (fi: number): void => {
      categoryGalleryRecordThumbRect(host, fi);
    }
  );
}

export function categoryGalleryCollectIdsInFlatRange(
  host: CategoryGallerySelectionHost,
  lo: number,
  hi: number
): string[] {
  let a = lo;
  let b = hi;
  if (a > b) {
    const t = a;
    a = b;
    b = t;
  }
  const out: string[] = [];
  const n = host.flatItems.length;
  for (let fi = a; fi <= b && fi < n; fi++) {
    const id = categoryGalleryItemIdOf(host.flatItems[fi]);
    if (id.length > 0) {
      out.push(id);
    }
  }
  return out;
}

export function categoryGalleryApplySlideRowRangeSelection(
  host: CategoryGallerySelectionHost,
  endFlat: number
): void {
  if (host.cgSlideAnchorFlat < 0) {
    return;
  }
  const ef = endFlat >= 0 ? endFlat : host.cgSlideAnchorFlat;
  if (host.cgSlideGestureActive && ef === host.cgSlideLastAppliedEndFlat) {
    return;
  }
  let lo = host.cgSlideAnchorFlat;
  let hi = ef;
  if (lo > hi) {
    const t = lo;
    lo = hi;
    hi = t;
  }
  const rangeIds = categoryGalleryCollectIdsInFlatRange(host, lo, hi);
  const seen = new Set<string>();
  const next: string[] = [];
  for (let i = 0; i < host.cgSlideUnionBase.length; i++) {
    seen.add(host.cgSlideUnionBase[i]);
    next.push(host.cgSlideUnionBase[i]);
  }
  for (let i = 0; i < rangeIds.length; i++) {
    const id = rangeIds[i];
    if (id.length > 0 && !seen.has(id)) {
      seen.add(id);
      next.push(id);
    }
  }
  host.cgSlideLastAppliedEndFlat = ef;
  host.selectedIds = next;
}

export function categoryGalleryBeginSlideSelectGesture(
  host: CategoryGallerySelectionHost,
  ev: GestureEvent,
  anchorFlat: number
): void {
  host.cgSlideGestureActive = true;
  host.cgScrollEnabled = false;
  host.cgSlideAnchorFlat = anchorFlat >= 0 ? anchorFlat : -1;
  host.cgSlideUnionBase = host.selectedIds.slice();
  host.cgSlideLastEndFlat = host.cgSlideAnchorFlat;
  host.cgSlideLastAppliedEndFlat = -99999;
  categoryGalleryRecordThumbRect(host, anchorFlat);
  const win = categoryGalleryReadGestureFingerWindow(ev);
  if (win !== null) {
    host.cgSlideRefX = vp2px(win.x);
    host.cgSlideRefY = vp2px(win.y);
    host.cgSlideHasRef = true;
  } else {
    const cached = host.cgThumbHitBounds.get(`${anchorFlat}`);
    if (cached !== undefined) {
      host.cgSlideRefX = (cached.left + cached.right) * 0.5;
      host.cgSlideRefY = (cached.top + cached.bottom) * 0.5;
      host.cgSlideHasRef = true;
    } else {
      host.cgSlideHasRef = false;
    }
  }
  categoryGalleryApplySlideRowRangeSelection(host, host.cgSlideLastEndFlat);
}

export function categoryGalleryEndSlideSelectGesture(host: CategoryGallerySelectionHost): void {
  if (!host.cgSlideGestureActive && host.cgScrollEnabled) {
    return;
  }
  host.cgSlideGestureActive = false;
  host.cgSlideHasRef = false;
  host.cgSlideAnchorFlat = -1;
  host.cgSlideUnionBase = [];
  host.cgSlideLastEndFlat = -1;
  host.cgSlideLastAppliedEndFlat = -99999;
  host.cgScrollEnabled = true;
}

export function categoryGalleryResolveSlidePointerWindowPx(
  host: CategoryGallerySelectionHost,
  ev: GestureEvent
): CgFingerWindowPoint | null {
  const win = categoryGalleryReadGestureFingerWindow(ev);
  if (win !== null) {
    return { x: vp2px(win.x), y: vp2px(win.y) };
  }
  if (!host.cgSlideHasRef) {
    return null;
  }
  return {
    x: host.cgSlideRefX + categoryGalleryPanOffsetVpToPx(ev.offsetX),
    y: host.cgSlideRefY + categoryGalleryPanOffsetVpToPx(ev.offsetY)
  };
}

export function categoryGalleryOnSlidePanUpdate(host: CategoryGallerySelectionHost, ev: GestureEvent): void {
  if (!host.cgSlideGestureActive) {
    return;
  }
  const pt = categoryGalleryResolveSlidePointerWindowPx(host, ev);
  if (pt === null) {
    return;
  }
  const hitFlat = categoryGalleryPickFlatForSlidePointer(host, pt.x, pt.y);
  if (hitFlat >= 0) {
    host.cgSlideLastEndFlat = hitFlat;
  }
  categoryGalleryApplySlideRowRangeSelection(host, host.cgSlideLastEndFlat);
}

export function categoryGalleryOnThumbLongPress(
  host: CategoryGallerySelectionHost,
  item: GalleryListItem,
  flatIdx: number
): void {
  const id = categoryGalleryItemIdOf(item);
  if (id.length === 0) {
    host.toast('该媒体无 ID，无法多选');
    return;
  }
  if (host.cgSlideGestureActive) {
    return;
  }
  host.cgLongPressIgnoreUntil = Date.now() + 500;
  if (!host.selectionMode) {
    playGalleryEnterSelectionHaptic();
    host.selectionMode = true;
    host.selectedIds = [id];
  } else {
    categoryGalleryToggleId(host, id);
  }
}

export function categoryGalleryOnCellClick(
  host: CategoryGallerySelectionHost,
  item: GalleryListItem,
  flatIdx: number
): void {
  if (Date.now() < host.cgLongPressIgnoreUntil) {
    return;
  }
  const id = categoryGalleryItemIdOf(item);
  if (host.selectionMode) {
    if (id.length > 0) {
      categoryGalleryToggleId(host, id);
    }
    return;
  }
  host.openItemAtFlat(flatIdx);
}
