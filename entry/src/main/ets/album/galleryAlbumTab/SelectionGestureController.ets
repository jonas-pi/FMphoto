import { UIContext } from '@kit.ArkUI';
import { GalleryListItem } from '../../model/FnApiTypes';
import { GalleryFlowNode, GalleryWaterFlowDataSource } from '../GalleryFlowDataSource';
import {
  GALLERY_SLIDE_DOM_BUDGET_PER_FRAME,
  GALLERY_SLIDE_FLOW_ROW_RADIUS,
  GALLERY_SLIDE_TAIL_FLOW_ROWS,
  pickIndexedFlatForSlidePointer
} from '../GallerySlidePick';
import { GalleryPreviewNavStore } from '../GalleryPreviewNavStore';
import { playGalleryEnterSelectionHaptic } from '../GallerySelectionHaptic';
import {
  GalleryFingerCoordCompat,
  GalleryFingerWindowPoint,
  GalleryThumbHitRect
} from './GalleryAlbumTabTypes';

export interface SelectionGestureControllerHost {
  getUIContext(): UIContext;
  baseUrl: string;
  inSearchMode: boolean;
  gallerySelectionMode: boolean;
  galleryTimelineRefreshing: boolean;
  gallerySlideGestureActive: boolean;
  galleryMainListScrollEnabled: boolean;
  gallerySlideAnchorFlat: number;
  gallerySlideUnionBase: string[];
  gallerySlideLastEndFlat: number;
  gallerySlideLastAppliedEndFlat: number;
  galleryLongPressIgnoreClickUntil: number;
  gallerySlideRefX: number;
  gallerySlideRefY: number;
  gallerySlideHasRef: boolean;
  searchResults: GalleryListItem[];
  flowDataSource: GalleryWaterFlowDataSource;
  galleryThumbHitBounds: Map<string, GalleryThumbHitRect>;
  searchThumbHitBounds: Map<string, GalleryThumbHitRect>;
  gallerySelectedIds: string[];
  itemIdOf(item: GalleryListItem): string;
  flatItems(): GalleryListItem[];
  galleryThumbDomId(photoId: string): string;
  recordGalleryThumbRectFromDom(photoId: string, domId: string): void;
  setGallerySelectedIdsState(ids: string[]): void;
  toast(msg: string): void;
  openPreview(flatIndex: number): void;
  resolveGalleryFlatIndexForOpenPreview(item: GalleryListItem, hintFlat: number): number;
}

function pickSearchThumbFlatUnderPointForSlide(
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

function collectGalleryIdsInFlatRange(host: SelectionGestureControllerHost, lo: number, hi: number): string[] {
  let a = lo;
  let b = hi;
  if (a > b) {
    const t = a;
    a = b;
    b = t;
  }
  const out: string[] = [];
  const all = host.flatItems();
  if (all.length === 0) {
    return out;
  }
  const lo2 = Math.max(0, a);
  const hi2 = Math.min(b, all.length - 1);
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

function collectSearchIdsInFlatRange(host: SelectionGestureControllerHost, lo: number, hi: number): string[] {
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

export function selectionReadGestureFingerWindow(
  _host: SelectionGestureControllerHost,
  ev: GestureEvent
): GalleryFingerWindowPoint | null {
  const fl = ev.fingerList;
  if (fl === undefined || fl.length < 1) {
    return null;
  }
  const f0 = fl[0] as GalleryFingerCoordCompat;
  const x = f0.windowX ?? f0.globalX ?? f0.screenX ?? f0.displayX ?? f0.x;
  const y = f0.windowY ?? f0.globalY ?? f0.screenY ?? f0.displayY ?? f0.y;
  if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
    return null;
  }
  return { x: x, y: y };
}

export function selectionPanOffsetVpToPx(
  _host: SelectionGestureControllerHost,
  deltaVp: number
): number {
  const probePx = 100;
  const probeVp = px2vp(probePx);
  if (probeVp < 0.0001) {
    return deltaVp;
  }
  return deltaVp * (probePx / probeVp);
}

export function selectionBeginGallerySlideSelectGesture(
  host: SelectionGestureControllerHost,
  ev: GestureEvent,
  item: GalleryListItem,
  anchorFlat: number
): void {
  host.gallerySlideGestureActive = true;
  host.galleryMainListScrollEnabled = false;
  host.gallerySlideAnchorFlat = anchorFlat >= 0 ? anchorFlat : -1;
  host.gallerySlideUnionBase = host.gallerySelectedIds.slice();
  host.gallerySlideLastEndFlat = host.gallerySlideAnchorFlat;
  host.gallerySlideLastAppliedEndFlat = -99999;
  const anchorId = host.itemIdOf(item);
  if (host.inSearchMode) {
    selectionRecordSearchThumbRect(host, anchorFlat);
  } else if (anchorId.length > 0) {
    host.recordGalleryThumbRectFromDom(anchorId, host.galleryThumbDomId(anchorId));
  }
  const win = selectionReadGestureFingerWindow(host, ev);
  if (win !== null) {
    host.gallerySlideRefX = vp2px(win.x);
    host.gallerySlideRefY = vp2px(win.y);
    host.gallerySlideHasRef = true;
  } else if (host.inSearchMode) {
    const rs = host.searchThumbHitBounds.get(`${anchorFlat}`);
    if (rs !== undefined) {
      host.gallerySlideRefX = (rs.left + rs.right) * 0.5;
      host.gallerySlideRefY = (rs.top + rs.bottom) * 0.5;
      host.gallerySlideHasRef = true;
    } else {
      host.gallerySlideHasRef = false;
    }
  } else if (anchorId.length > 0) {
    const r = host.galleryThumbHitBounds.get(anchorId);
    if (r !== undefined) {
      host.gallerySlideRefX = (r.left + r.right) * 0.5;
      host.gallerySlideRefY = (r.top + r.bottom) * 0.5;
      host.gallerySlideHasRef = true;
    } else {
      host.gallerySlideHasRef = false;
    }
  } else {
    host.gallerySlideHasRef = false;
  }
  selectionApplyGallerySlideRowRangeSelection(host, host.gallerySlideLastEndFlat);
}

export function selectionEndGallerySlideSelectGesture(host: SelectionGestureControllerHost): void {
  if (!host.gallerySlideGestureActive && host.galleryMainListScrollEnabled) {
    return;
  }
  host.gallerySlideGestureActive = false;
  host.gallerySlideHasRef = false;
  host.gallerySlideAnchorFlat = -1;
  host.gallerySlideUnionBase = [];
  host.gallerySlideLastEndFlat = -1;
  host.gallerySlideLastAppliedEndFlat = -99999;
  host.galleryMainListScrollEnabled = true;
}

export function selectionResolveSlidePointerWindowPx(
  host: SelectionGestureControllerHost,
  ev: GestureEvent
): GalleryFingerWindowPoint | null {
  const win = selectionReadGestureFingerWindow(host, ev);
  if (win !== null) {
    return { x: vp2px(win.x), y: vp2px(win.y) };
  }
  if (!host.gallerySlideHasRef) {
    return null;
  }
  return {
    x: host.gallerySlideRefX + selectionPanOffsetVpToPx(host, ev.offsetX),
    y: host.gallerySlideRefY + selectionPanOffsetVpToPx(host, ev.offsetY)
  };
}

export function selectionHitGalleryThumbDomPx(
  host: SelectionGestureControllerHost,
  photoId: string,
  xPx: number,
  yPx: number
): boolean {
  if (photoId.length === 0) {
    return false;
  }
  try {
    const domId = host.galleryThumbDomId(photoId);
    const info = host.getUIContext().getComponentUtils().getRectangleById(domId);
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

export function selectionPickGalleryThumbFlatUnderPoint(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): number {
  if (host.inSearchMode) {
    return selectionPickSearchThumbFlatUnderPoint(host, xPx, yPx);
  }
  if (host.galleryThumbHitBounds.size === 0) {
    return -1;
  }
  const n = host.flowDataSource.totalCount();
  for (let i = n - 1; i >= 0; i--) {
    const node = host.flowDataSource.getData(i);
    if (node.kind !== 'row') {
      continue;
    }
    for (let k = node.rowSlotItems.length - 1; k >= 0; k--) {
      const slot = node.rowSlotItems[k];
      if (slot === null || slot === undefined) {
        continue;
      }
      const id = host.itemIdOf(slot);
      if (id.length === 0) {
        continue;
      }
      const cached = host.galleryThumbHitBounds.get(id);
      if (cached === undefined) {
        continue;
      }
      if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
        return node.rowSlotFlatIndices[k];
      }
    }
  }
  return -1;
}

export function selectionPickGalleryThumbFlatUnderPointForSlide(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): number {
  const fromCache = selectionPickGalleryThumbFlatUnderPoint(host, xPx, yPx);
  if (fromCache >= 0) {
    return fromCache;
  }
  const seed = host.gallerySlideLastEndFlat >= 0 ? host.gallerySlideLastEndFlat : host.gallerySlideAnchorFlat;
  const nFlow = host.flowDataSource.totalCount();
  let domBudget = GALLERY_SLIDE_DOM_BUDGET_PER_FRAME;

  const tryRowNode = (node: GalleryFlowNode): number => {
    if (node.kind !== 'row') {
      return -1;
    }
    for (let k = node.rowSlotItems.length - 1; k >= 0; k--) {
      const slot = node.rowSlotItems[k];
      if (slot === null || slot === undefined) {
        continue;
      }
      const id = host.itemIdOf(slot);
      if (id.length === 0) {
        continue;
      }
      const flat = node.rowSlotFlatIndices[k];
      const cached = host.galleryThumbHitBounds.get(id);
      if (cached !== undefined &&
        xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
        return flat;
      }
      if (domBudget <= 0) {
        continue;
      }
      domBudget--;
      if (selectionHitGalleryThumbDomPx(host, id, xPx, yPx)) {
        host.recordGalleryThumbRectFromDom(id, host.galleryThumbDomId(id));
        return flat;
      }
    }
    return -1;
  };

  if (seed >= 0) {
    let centerRi = -1;
    for (let i = 0; i < nFlow; i++) {
      const node = host.flowDataSource.getData(i);
      if (node.kind !== 'row') {
        continue;
      }
      for (let k = 0; k < node.rowSlotItems.length; k++) {
        if (node.rowSlotFlatIndices[k] === seed) {
          centerRi = i;
          break;
        }
      }
      if (centerRi >= 0) {
        break;
      }
    }
    const loR = centerRi >= 0 ? Math.max(0, centerRi - GALLERY_SLIDE_FLOW_ROW_RADIUS) : 0;
    const hiR = centerRi >= 0 ? Math.min(nFlow - 1, centerRi + GALLERY_SLIDE_FLOW_ROW_RADIUS) : nFlow - 1;
    for (let ri = hiR; ri >= loR; ri--) {
      const hit = tryRowNode(host.flowDataSource.getData(ri));
      if (hit >= 0) {
        return hit;
      }
    }
  }

  domBudget = GALLERY_SLIDE_DOM_BUDGET_PER_FRAME;
  let tailRows = 0;
  for (let ri = nFlow - 1; ri >= 0 && tailRows < GALLERY_SLIDE_TAIL_FLOW_ROWS; ri--) {
    const node = host.flowDataSource.getData(ri);
    if (node.kind !== 'row') {
      continue;
    }
    tailRows++;
    const hit = tryRowNode(node);
    if (hit >= 0) {
      return hit;
    }
  }
  return -1;
}

export function selectionPickGalleryThumbFlatForRowOrCache(
  host: SelectionGestureControllerHost,
  node: GalleryFlowNode,
  xPx: number,
  yPx: number
): number {
  const fromCache = selectionPickGalleryThumbFlatUnderPoint(host, xPx, yPx);
  if (fromCache >= 0) {
    return fromCache;
  }
  if (node.kind !== 'row') {
    return -1;
  }
  for (let k = node.rowSlotItems.length - 1; k >= 0; k--) {
    const slot = node.rowSlotItems[k];
    if (slot === null || slot === undefined) {
      continue;
    }
    const id = host.itemIdOf(slot);
    if (id.length === 0) {
      continue;
    }
    const cached = host.galleryThumbHitBounds.get(id);
    if (cached !== undefined) {
      if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
        return node.rowSlotFlatIndices[k];
      }
      continue;
    }
    if (selectionHitGalleryThumbDomPx(host, id, xPx, yPx)) {
      return node.rowSlotFlatIndices[k];
    }
  }
  return -1;
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
    const cached = host.searchThumbHitBounds.get(`${i}`);
    if (cached === undefined) {
      continue;
    }
    if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
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
  const fromCache = selectionPickSearchThumbFlatUnderPoint(host, xPx, yPx);
  if (fromCache >= rowStart && fromCache < rowStart + 3 && fromCache < n) {
    return fromCache;
  }
  for (let k = 2; k >= 0; k--) {
    const fi = rowStart + k;
    if (fi >= n) {
      continue;
    }
    const cached = host.searchThumbHitBounds.get(`${fi}`);
    if (cached !== undefined) {
      if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
        return fi;
      }
      continue;
    }
    if (selectionHitSearchThumbDomPx(host, fi, xPx, yPx)) {
      return fi;
    }
  }
  return -1;
}

export function selectionApplyGallerySlideRowRangeSelection(
  host: SelectionGestureControllerHost,
  endFlat: number
): void {
  if (host.gallerySlideAnchorFlat < 0) {
    return;
  }
  const ef = endFlat >= 0 ? endFlat : host.gallerySlideAnchorFlat;
  if (host.gallerySlideGestureActive && ef === host.gallerySlideLastAppliedEndFlat) {
    return;
  }
  let lo = host.gallerySlideAnchorFlat;
  let hi = ef;
  if (lo > hi) {
    const t = lo;
    lo = hi;
    hi = t;
  }
  const rangeIds = host.inSearchMode
    ? collectSearchIdsInFlatRange(host, lo, hi)
    : collectGalleryIdsInFlatRange(host, lo, hi);
  const seen = new Set<string>();
  const base = host.gallerySlideUnionBase;
  for (let i = 0; i < base.length; i++) {
    seen.add(base[i]);
  }
  const next: string[] = base.slice();
  for (let i = 0; i < rangeIds.length; i++) {
    const id = rangeIds[i];
    if (id.length > 0 && !seen.has(id)) {
      seen.add(id);
      next.push(id);
    }
  }
  host.gallerySlideLastAppliedEndFlat = ef;
  host.setGallerySelectedIdsState(next);
}

export function selectionOnGallerySlidePanUpdate(
  host: SelectionGestureControllerHost,
  ev: GestureEvent
): void {
  if (!host.gallerySlideGestureActive) {
    return;
  }
  const pt = selectionResolveSlidePointerWindowPx(host, ev);
  if (pt === null) {
    return;
  }
  const hitFlat = host.inSearchMode ?
    pickSearchThumbFlatUnderPointForSlide(host, pt.x, pt.y) :
    selectionPickGalleryThumbFlatUnderPointForSlide(host, pt.x, pt.y);
  if (hitFlat >= 0) {
    host.gallerySlideLastEndFlat = hitFlat;
  }
  selectionApplyGallerySlideRowRangeSelection(host, host.gallerySlideLastEndFlat);
}

export function selectionIsGalleryIdSelected(
  host: SelectionGestureControllerHost,
  id: string
): boolean {
  return id.length > 0 && host.gallerySelectedIds.indexOf(id) >= 0;
}

export function selectionToggleGallerySelectedId(
  host: SelectionGestureControllerHost,
  id: string
): void {
  if (id.length === 0) {
    return;
  }
  const idx = host.gallerySelectedIds.indexOf(id);
  if (idx >= 0) {
    const next: string[] = [];
    for (let i = 0; i < host.gallerySelectedIds.length; i++) {
      if (i !== idx) {
        next.push(host.gallerySelectedIds[i]);
      }
    }
    host.setGallerySelectedIdsState(next);
  } else {
    const next: string[] = host.gallerySelectedIds.slice();
    next.push(id);
    host.setGallerySelectedIdsState(next);
  }
}

export function selectionOnGalleryThumbLongPress(
  host: SelectionGestureControllerHost,
  item: GalleryListItem
): void {
  const id = host.itemIdOf(item);
  if (id.length === 0) {
    host.toast('该媒体无 ID，无法多选');
    return;
  }
  if (host.gallerySlideGestureActive) {
    return;
  }
  host.galleryLongPressIgnoreClickUntil = Date.now() + 500;
  if (!host.gallerySelectionMode) {
    playGalleryEnterSelectionHaptic();
    host.gallerySelectionMode = true;
    host.galleryTimelineRefreshing = false;
    host.setGallerySelectedIdsState([id]);
  } else {
    selectionToggleGallerySelectedId(host, id);
  }
}

export function selectionOnGalleryThumbTap(
  host: SelectionGestureControllerHost,
  item: GalleryListItem,
  flatIndex: number
): void {
  if (Date.now() < host.galleryLongPressIgnoreClickUntil) {
    return;
  }
  if (host.gallerySelectionMode) {
    const id = host.itemIdOf(item);
    if (id.length > 0) {
      selectionToggleGallerySelectedId(host, id);
    }
    return;
  }
  const idx = host.resolveGalleryFlatIndexForOpenPreview(item, flatIndex);
  host.openPreview(idx);
}

export function selectionOnSearchThumbTap(
  host: SelectionGestureControllerHost,
  item: GalleryListItem,
  flatIndex: number
): void {
  if (Date.now() < host.galleryLongPressIgnoreClickUntil) {
    return;
  }
  if (host.gallerySelectionMode) {
    const id = host.itemIdOf(item);
    if (id.length > 0) {
      selectionToggleGallerySelectedId(host, id);
    }
    return;
  }
  if (flatIndex < 0 || flatIndex >= host.searchResults.length) {
    return;
  }
  GalleryPreviewNavStore.openPreview(host.baseUrl, host.searchResults, flatIndex);
}
