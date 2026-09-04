import { UIContext } from '@kit.ArkUI';
import { GalleryPreviewNavStore } from '../../album/GalleryPreviewNavStore';
import { playGalleryEnterSelectionHaptic } from '../../album/GallerySelectionHaptic';
import {
  gallerySlideAutoScrollStop,
  gallerySlideAutoScrollUpdate,
  GallerySlideAutoScrollSession
} from '../../album/GallerySlideAutoScroll';
import {
  GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE,
  GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE,
  pickIndexedFlatForSlidePointer,
  pickSlideEndFlatFromRowBand
} from '../../album/GallerySlidePick';
import { GalleryListItem, RecycleBinListItem } from '../../model/FnApiTypes';
import { fnClampGridColumns } from '../../common/FnWindowBreakpoint';
import { RbFingerCoordCompat, RbFingerWindowPoint, RbThumbHitRect } from './RecycleBinTypes';

export const RECYCLE_BIN_LIST_DOM_ID: string = 'recycle_bin_main_list';

export interface RecycleBinSelectionHost {
  getUIContext(): UIContext;
  baseUrl: string;
  items: RecycleBinListItem[];
  columnsPerRow: number;
  selectionMode: boolean;
  selectedIds: number[];
  listScroller: Scroller;
  listDomId: string;
  rbSlideGestureActive: boolean;
  rbScrollEnabled: boolean;
  rbLongPressIgnoreUntil: number;
  rbThumbHitBounds: Map<string, RbThumbHitRect>;
  rbSlideRefX: number;
  rbSlideRefY: number;
  rbSlideHasRef: boolean;
  rbSlideAnchorFlat: number;
  rbSlideUnionBase: number[];
  rbSlideLastEndFlat: number;
  rbSlideLastAppliedEndFlat: number;
  toast(msg: string): void;
}

const rbSlideAutoScrollSession: GallerySlideAutoScrollSession = new GallerySlideAutoScrollSession();

export function recycleBinDomId(flatIdx: number): string {
  return `rbcell_${flatIdx}`;
}

export function recycleBinNumericIdOf(it: RecycleBinListItem): number {
  const raw = it.id;
  if (raw === undefined || raw === null) {
    return -1;
  }
  const n = Math.floor(Number(raw));
  return Number.isFinite(n) && n > 0 ? n : -1;
}

export function recycleBinToGalleryItem(it: RecycleBinListItem): GalleryListItem | undefined {
  const nid = recycleBinNumericIdOf(it);
  const uuid = it.photoUUID !== undefined ? it.photoUUID.trim() : '';
  if (nid < 0 || uuid.length === 0) {
    return undefined;
  }
  const sid = `${nid}`;
  const thumb = `/p/api/v1/stream/p/t/${sid}/s/${uuid}`;
  return {
    id: sid,
    thumb: thumb,
    category: it.category,
    fileType: it.fileType,
    filename: it.fileName,
    name: it.fileName
  };
}

export function recycleBinThumbRelOf(it: RecycleBinListItem): string {
  const g = recycleBinToGalleryItem(it);
  const thumb = g !== undefined ? g.thumb : undefined;
  return thumb !== undefined && thumb.length > 0 ? thumb : '';
}

export function recycleBinGalleryListForSelection(items: RecycleBinListItem[], selectedIds: number[]): GalleryListItem[] {
  const out: GalleryListItem[] = [];
  const want = new Set<number>();
  for (let i = 0; i < selectedIds.length; i++) {
    want.add(selectedIds[i]);
  }
  for (let i = 0; i < items.length; i++) {
    const nid = recycleBinNumericIdOf(items[i]);
    if (nid >= 0 && want.has(nid)) {
      const g = recycleBinToGalleryItem(items[i]);
      if (g !== undefined) {
        out.push(g);
      }
    }
  }
  return out;
}

export function recycleBinGalleryListForPreview(items: RecycleBinListItem[]): GalleryListItem[] {
  const out: GalleryListItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const g = recycleBinToGalleryItem(items[i]);
    if (g !== undefined) {
      out.push(g);
    }
  }
  return out;
}

export function recycleBinPreviewIndexForFlatIndex(items: RecycleBinListItem[], flatIdx: number): number {
  let k = 0;
  for (let i = 0; i < flatIdx && i < items.length; i++) {
    if (recycleBinToGalleryItem(items[i]) !== undefined) {
      k++;
    }
  }
  return k;
}

export function recycleBinSelectedIdStrings(ids: number[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < ids.length; i++) {
    if (ids[i] >= 0) {
      out.push(`${ids[i]}`);
    }
  }
  return out;
}

export function recycleBinSlidePanDistance(active: boolean): number {
  return active ? GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE : GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE;
}

export function recycleBinExitSelection(host: RecycleBinSelectionHost): void {
  host.selectionMode = false;
  host.selectedIds = [];
  recycleBinEndSlideSelectGesture(host);
  host.rbLongPressIgnoreUntil = 0;
  host.rbThumbHitBounds.clear();
}

export function recycleBinToggleToolbarMode(host: RecycleBinSelectionHost): void {
  if (host.selectionMode) {
    recycleBinExitSelection(host);
  } else {
    host.selectionMode = true;
  }
}

export function recycleBinIsIdSelected(host: RecycleBinSelectionHost, nid: number): boolean {
  return host.selectedIds.indexOf(nid) >= 0;
}

export function recycleBinToggleIdSelected(host: RecycleBinSelectionHost, nid: number): void {
  const idx = host.selectedIds.indexOf(nid);
  if (idx >= 0) {
    const next: number[] = [];
    for (let i = 0; i < host.selectedIds.length; i++) {
      if (i !== idx) {
        next.push(host.selectedIds[i]);
      }
    }
    host.selectedIds = next;
  } else {
    const next: number[] = host.selectedIds.slice();
    next.push(nid);
    host.selectedIds = next;
  }
}

export function recycleBinReadGestureFingerWindow(ev: GestureEvent): RbFingerWindowPoint | null {
  const fl = ev.fingerList;
  if (fl === undefined || fl.length < 1) {
    return null;
  }
  const f0 = fl[0] as RbFingerCoordCompat;
  const x = f0.windowX ?? f0.globalX ?? f0.screenX ?? f0.displayX ?? f0.x;
  const y = f0.windowY ?? f0.globalY ?? f0.screenY ?? f0.displayY ?? f0.y;
  if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
    return null;
  }
  return { x, y };
}

function recycleBinVpToPx(host: RecycleBinSelectionHost, value: number): number {
  try {
    return host.getUIContext().vp2px(value);
  } catch (_e) {
    return value;
  }
}

function recycleBinPxToVp(host: RecycleBinSelectionHost, value: number): number {
  try {
    return host.getUIContext().px2vp(value);
  } catch (_e) {
    return value;
  }
}

export function recycleBinPanOffsetVpToPx(host: RecycleBinSelectionHost, deltaVp: number): number {
  const probePx = 100;
  const probeVp = recycleBinPxToVp(host, probePx);
  if (probeVp < 0.0001) {
    return deltaVp;
  }
  return deltaVp * (probePx / probeVp);
}

export function recycleBinRecordThumbRect(host: RecycleBinSelectionHost, flatIdx: number): void {
  if (flatIdx < 0 || flatIdx >= host.items.length) {
    return;
  }
  try {
    const info = host.getUIContext().getComponentUtils().getRectangleById(recycleBinDomId(flatIdx));
    const x = info.windowOffset.x as number;
    const y = info.windowOffset.y as number;
    const w = info.size.width as number;
    const h = info.size.height as number;
    if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
      host.rbThumbHitBounds.delete(`${flatIdx}`);
      return;
    }
    host.rbThumbHitBounds.set(`${flatIdx}`, { left: x, top: y, right: x + w, bottom: y + h });
  } catch (_e) {
  }
}

export function recycleBinHitThumbDomPx(
  host: RecycleBinSelectionHost,
  flatIdx: number,
  xPx: number,
  yPx: number
): boolean {
  if (flatIdx < 0 || flatIdx >= host.items.length) {
    return false;
  }
  try {
    const info = host.getUIContext().getComponentUtils().getRectangleById(recycleBinDomId(flatIdx));
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

export function recycleBinPickThumbFlatUnderPoint(
  host: RecycleBinSelectionHost,
  xPx: number,
  yPx: number
): number {
  const n = host.items.length;
  if (host.rbThumbHitBounds.size === 0 || n <= 0) {
    return -1;
  }
  for (let i = n - 1; i >= 0; i--) {
    const cached = host.rbThumbHitBounds.get(`${i}`);
    if (cached === undefined) {
      continue;
    }
    if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
      return i;
    }
  }
  return -1;
}

export function recycleBinPickThumbFlatForRow(
  host: RecycleBinSelectionHost,
  rowStart: number,
  xPx: number,
  yPx: number
): number {
  const n = host.items.length;
  const columnsPerRow = fnClampGridColumns(host.columnsPerRow);
  const fromCache = recycleBinPickThumbFlatUnderPoint(host, xPx, yPx);
  if (fromCache >= rowStart && fromCache < rowStart + columnsPerRow && fromCache < n) {
    return fromCache;
  }
  for (let k = columnsPerRow - 1; k >= 0; k--) {
    const fi = rowStart + k;
    if (fi >= n) {
      continue;
    }
    const cached = host.rbThumbHitBounds.get(`${fi}`);
    if (cached !== undefined) {
      if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
        return fi;
      }
      continue;
    }
    if (recycleBinHitThumbDomPx(host, fi, xPx, yPx)) {
      return fi;
    }
  }
  return -1;
}

export function recycleBinPickThumbFlatForSlidePointer(
  host: RecycleBinSelectionHost,
  xPx: number,
  yPx: number
): number {
  return pickIndexedFlatForSlidePointer(
    xPx,
    yPx,
    host.items.length,
    host.rbSlideLastEndFlat,
    host.rbSlideAnchorFlat,
    (ax: number, ay: number): number => recycleBinPickThumbFlatUnderPoint(host, ax, ay),
    (fi: number): RbThumbHitRect | undefined => host.rbThumbHitBounds.get(`${fi}`),
    (fi: number, ax: number, ay: number): boolean => recycleBinHitThumbDomPx(host, fi, ax, ay),
    (fi: number): void => {
      recycleBinRecordThumbRect(host, fi);
    }
  );
}

export function recycleBinCollectIdsInFlatRange(host: RecycleBinSelectionHost, lo: number, hi: number): number[] {
  let a = lo;
  let b = hi;
  if (a > b) {
    const t = a;
    a = b;
    b = t;
  }
  const out: number[] = [];
  const n = host.items.length;
  for (let fi = a; fi <= b && fi < n; fi++) {
    const nid = recycleBinNumericIdOf(host.items[fi]);
    if (nid >= 0) {
      out.push(nid);
    }
  }
  return out;
}

export function recycleBinApplySlideRowRangeSelection(host: RecycleBinSelectionHost, endFlat: number): void {
  if (host.rbSlideAnchorFlat < 0) {
    return;
  }
  const ef = endFlat >= 0 ? endFlat : host.rbSlideAnchorFlat;
  if (host.rbSlideGestureActive && ef === host.rbSlideLastAppliedEndFlat) {
    return;
  }
  let lo = host.rbSlideAnchorFlat;
  let hi = ef;
  if (lo > hi) {
    const t = lo;
    lo = hi;
    hi = t;
  }
  const rangeIds = recycleBinCollectIdsInFlatRange(host, lo, hi);
  const seen = new Set<number>();
  const next: number[] = [];
  for (let i = 0; i < host.rbSlideUnionBase.length; i++) {
    const v = host.rbSlideUnionBase[i];
    seen.add(v);
    next.push(v);
  }
  for (let i = 0; i < rangeIds.length; i++) {
    const id = rangeIds[i];
    if (!seen.has(id)) {
      seen.add(id);
      next.push(id);
    }
  }
  if (next.length === 0 && host.rbSlideGestureActive && host.selectedIds.length > 0) {
    return;
  }
  host.rbSlideLastAppliedEndFlat = ef;
  host.selectedIds = next;
}

export function recycleBinBeginSlideSelectGesture(
  host: RecycleBinSelectionHost,
  ev: GestureEvent,
  anchorFlat: number
): void {
  host.rbSlideGestureActive = true;
  host.rbScrollEnabled = false;
  host.rbSlideAnchorFlat = anchorFlat >= 0 ? anchorFlat : -1;
  host.rbSlideUnionBase = host.selectedIds.slice();
  host.rbSlideLastEndFlat = host.rbSlideAnchorFlat;
  host.rbSlideLastAppliedEndFlat = -99999;
  recycleBinRecordThumbRect(host, anchorFlat);
  const win = recycleBinReadGestureFingerWindow(ev);
  if (win !== null) {
    host.rbSlideRefX = recycleBinVpToPx(host, win.x);
    host.rbSlideRefY = recycleBinVpToPx(host, win.y);
    host.rbSlideHasRef = true;
  } else {
    const cached = host.rbThumbHitBounds.get(`${anchorFlat}`);
    if (cached !== undefined) {
      host.rbSlideRefX = (cached.left + cached.right) * 0.5;
      host.rbSlideRefY = (cached.top + cached.bottom) * 0.5;
      host.rbSlideHasRef = true;
    } else {
      host.rbSlideHasRef = false;
    }
  }
  recycleBinApplySlideRowRangeSelection(host, host.rbSlideLastEndFlat);
}

export function recycleBinEndSlideSelectGesture(host: RecycleBinSelectionHost): void {
  gallerySlideAutoScrollStop();
  if (!host.rbSlideGestureActive && host.rbScrollEnabled) {
    return;
  }
  host.rbSlideGestureActive = false;
  host.rbSlideHasRef = false;
  host.rbSlideAnchorFlat = -1;
  host.rbSlideUnionBase = [];
  host.rbSlideLastEndFlat = -1;
  host.rbSlideLastAppliedEndFlat = -99999;
  host.rbScrollEnabled = true;
}

function recycleBinShiftHitBoundsY(host: RecycleBinSelectionHost, dyPx: number): void {
  if (!Number.isFinite(dyPx) || Math.abs(dyPx) < 0.5) {
    return;
  }
  host.rbThumbHitBounds.forEach((rect: RbThumbHitRect): void => {
    rect.top += dyPx;
    rect.bottom += dyPx;
  });
}

function recycleBinBindSlideAutoScroll(host: RecycleBinSelectionHost): GallerySlideAutoScrollSession {
  rbSlideAutoScrollSession.uiContext = host.getUIContext();
  rbSlideAutoScrollSession.scroller = host.listScroller;
  rbSlideAutoScrollSession.listDomId = host.listDomId;
  rbSlideAutoScrollSession.topInsetVp = 0;
  rbSlideAutoScrollSession.bottomInsetVp = 0;
  rbSlideAutoScrollSession.isActive = (): boolean => host.rbSlideGestureActive;
  rbSlideAutoScrollSession.shiftHitBoundsY = (dyPx: number): void => {
    recycleBinShiftHitBoundsY(host, dyPx);
  };
  rbSlideAutoScrollSession.followPointer = (xPx: number, yPx: number, cacheOnly: boolean): void => {
    recycleBinFollowSlidePointer(host, xPx, yPx, cacheOnly);
  };
  return rbSlideAutoScrollSession;
}

function recycleBinFollowSlidePointer(
  host: RecycleBinSelectionHost,
  xPx: number,
  yPx: number,
  cacheOnly: boolean = false
): void {
  if (!host.rbSlideGestureActive) {
    return;
  }
  let hitFlat = cacheOnly
    ? recycleBinPickThumbFlatUnderPoint(host, xPx, yPx)
    : recycleBinPickThumbFlatForSlidePointer(host, xPx, yPx);
  if (hitFlat < 0) {
    hitFlat = pickSlideEndFlatFromRowBand(
      yPx,
      host.items.length,
      host.rbSlideAnchorFlat,
      (fi: number): RbThumbHitRect | undefined => host.rbThumbHitBounds.get(`${fi}`)
    );
  }
  if (hitFlat >= 0) {
    host.rbSlideLastEndFlat = hitFlat;
  }
  recycleBinApplySlideRowRangeSelection(host, host.rbSlideLastEndFlat);
}

function recycleBinUpdateSlideAutoScroll(host: RecycleBinSelectionHost, xPx: number, yPx: number): void {
  gallerySlideAutoScrollUpdate(recycleBinBindSlideAutoScroll(host), xPx, yPx);
}

export function recycleBinResolveSlidePointerWindowPx(
  host: RecycleBinSelectionHost,
  ev: GestureEvent
): RbFingerWindowPoint | null {
  const win = recycleBinReadGestureFingerWindow(ev);
  if (win !== null) {
    return { x: recycleBinVpToPx(host, win.x), y: recycleBinVpToPx(host, win.y) };
  }
  if (!host.rbSlideHasRef) {
    return null;
  }
  return {
    x: host.rbSlideRefX + recycleBinPanOffsetVpToPx(host, ev.offsetX),
    y: host.rbSlideRefY + recycleBinPanOffsetVpToPx(host, ev.offsetY)
  };
}

export function recycleBinOnSlidePanUpdate(host: RecycleBinSelectionHost, ev: GestureEvent): void {
  if (!host.rbSlideGestureActive) {
    return;
  }
  const pt = recycleBinResolveSlidePointerWindowPx(host, ev);
  if (pt === null) {
    return;
  }
  recycleBinUpdateSlideAutoScroll(host, pt.x, pt.y);
  recycleBinFollowSlidePointer(host, pt.x, pt.y);
}

export function recycleBinOnSlideTouchMoveWindow(
  host: RecycleBinSelectionHost,
  xPx: number,
  yPx: number
): void {
  recycleBinUpdateSlideAutoScroll(host, xPx, yPx);
  recycleBinFollowSlidePointer(host, xPx, yPx);
}

export function recycleBinOnThumbLongPress(
  host: RecycleBinSelectionHost,
  it: RecycleBinListItem,
  flatIdx: number
): void {
  const nid = recycleBinNumericIdOf(it);
  if (nid < 0) {
    host.toast('该条目无有效 ID，无法多选');
    return;
  }
  if (host.rbSlideGestureActive) {
    return;
  }
  host.rbLongPressIgnoreUntil = Date.now() + 500;
  if (!host.selectionMode) {
    playGalleryEnterSelectionHaptic();
    host.selectionMode = true;
    host.selectedIds = [nid];
  } else {
    recycleBinToggleIdSelected(host, nid);
  }
}

export function recycleBinOnCellClick(
  host: RecycleBinSelectionHost,
  it: RecycleBinListItem,
  flatIdx: number
): void {
  if (Date.now() < host.rbLongPressIgnoreUntil) {
    return;
  }
  const nid = recycleBinNumericIdOf(it);
  if (host.selectionMode) {
    if (nid >= 0) {
      recycleBinToggleIdSelected(host, nid);
    }
    return;
  }
  const g = recycleBinToGalleryItem(it);
  if (g === undefined) {
    host.toast('无法预览该项');
    return;
  }
  const list = recycleBinGalleryListForPreview(host.items);
  const pIdx = recycleBinPreviewIndexForFlatIndex(host.items, flatIdx);
  GalleryPreviewNavStore.openPreview(host.getUIContext(), host.baseUrl, list, pIdx);
}

export function recycleBinRowCount(items: RecycleBinListItem[], columnsPerRow: number = 4): number {
  const n = items.length;
  const cols = fnClampGridColumns(columnsPerRow);
  return n <= 0 ? 0 : Math.floor((n + cols - 1) / cols);
}

export function recycleBinRowIndexArray(items: RecycleBinListItem[], columnsPerRow: number = 4): number[] {
  const count = recycleBinRowCount(items, columnsPerRow);
  const out: number[] = [];
  for (let i = 0; i < count; i++) {
    out.push(i);
  }
  return out;
}
