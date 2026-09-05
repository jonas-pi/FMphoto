import { UIContext } from '@kit.ArkUI';
import { GalleryListItem } from '../../model/FnApiTypes';
import { playGalleryEnterSelectionHaptic } from '../../album/GallerySelectionHaptic';
import {
  gallerySlideAutoScrollStop,
  gallerySlideAutoScrollUpdate,
  GallerySlideAutoScrollSession
} from '../../album/GallerySlideAutoScroll';
import {
  pickIndexedFlatForSlidePointer,
  pickSlideEndFlatFromRowBand
} from '../../album/GallerySlidePick';
import { fnClampGridColumns } from '../../common/FnWindowBreakpoint';
import { galleryGridSlideLog } from '../../album/GalleryGridSlideTouch';
import {
  CgFingerCoordCompat,
  CgFingerWindowPoint,
  CgThumbHitRect,
  RowModel
} from './CategoryGalleryTypes';

export const CATEGORY_GALLERY_LIST_DOM_ID: string = 'category_gallery_main_list';

export interface CategoryGallerySelectionHost {
  getUIContext(): UIContext;
  flatItems: GalleryListItem[];
  groupOffsets: number[];
  columnsPerRow: number;
  selectionMode: boolean;
  selectedIds: string[];
  listScroller: Scroller;
  listDomId: string;
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

const cgSlideAutoScrollSession: GallerySlideAutoScrollSession = new GallerySlideAutoScrollSession();
/** GridSlide 命中诊断节流状态；仅记录索引变化或每 120ms 的持续跟手心跳。 */
let cgSlideTraceLastMs: number = 0;
let cgSlideTraceLastFlat: number = -99999;

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

function categoryGalleryVpToPx(host: CategoryGallerySelectionHost, value: number): number {
  try {
    return host.getUIContext().vp2px(value);
  } catch (_e) {
    return value;
  }
}

function categoryGalleryPxToVp(host: CategoryGallerySelectionHost, value: number): number {
  try {
    return host.getUIContext().px2vp(value);
  } catch (_e) {
    return value;
  }
}

export function categoryGalleryPanOffsetVpToPx(host: CategoryGallerySelectionHost, deltaVp: number): number {
  const probePx = 100;
  const probeVp = categoryGalleryPxToVp(host, probePx);
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

/**
 * 根据分组偏移计算 flat 所在宫格行的有效范围。
 * 分类页每个日期分组都会重新从第 1 列排布，不能直接用 flat / columnsPerRow。
 */
function categoryGalleryFlatRowRange(host: CategoryGallerySelectionHost, flatIdx: number): number[] {
  if (flatIdx < 0 || flatIdx >= host.flatItems.length) {
    return [-1, -1];
  }
  let groupStart = 0;
  let groupEnd = host.flatItems.length;
  for (let i = 0; i < host.groupOffsets.length; i++) {
    const offset = host.groupOffsets[i];
    if (offset <= flatIdx) {
      groupStart = offset;
      groupEnd = i + 1 < host.groupOffsets.length ? host.groupOffsets[i + 1] : host.flatItems.length;
      continue;
    }
    break;
  }
  const columns = fnClampGridColumns(host.columnsPerRow);
  const rowStart = groupStart + Math.floor((flatIdx - groupStart) / columns) * columns;
  return [rowStart, Math.min(groupEnd - 1, rowStart + columns - 1)];
}

/** 二次划选会刷新行节点；刷新前缓存锚点整行，避免只剩锚点一个矩形。 */
function categoryGalleryRecordAnchorRow(host: CategoryGallerySelectionHost, anchorFlat: number): void {
  const range = categoryGalleryFlatRowRange(host, anchorFlat);
  for (let fi = range[0]; fi >= 0 && fi <= range[1]; fi++) {
    categoryGalleryRecordThumbRect(host, fi);
  }
}

/**
 * DOM 正在重建时，用锚点矩形宽度和列位置推算同一行目标。
 * 二次手势本身限定为 Horizontal，这个兜底不跨日期标题，也不会误选相邻分组。
 */
function categoryGalleryEstimateFlatInAnchorRow(
  host: CategoryGallerySelectionHost,
  xPx: number,
  yPx: number
): number {
  const anchor = host.cgSlideAnchorFlat;
  const anchorRect = host.cgThumbHitBounds.get(`${anchor}`);
  if (anchorRect === undefined) {
    return -1;
  }
  const width = anchorRect.right - anchorRect.left;
  const height = anchorRect.bottom - anchorRect.top;
  if (width < 1 || height < 1 ||
    yPx < anchorRect.top - height * 0.35 || yPx > anchorRect.bottom + height * 0.35) {
    return -1;
  }
  const range = categoryGalleryFlatRowRange(host, anchor);
  if (range[0] < 0) {
    return -1;
  }
  const anchorCenterX = (anchorRect.left + anchorRect.right) * 0.5;
  const estimated = anchor + Math.round((xPx - anchorCenterX) / width);
  return Math.max(range[0], Math.min(range[1], estimated));
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
  const columnsPerRow = fnClampGridColumns(host.columnsPerRow);
  const fromCache = categoryGalleryPickFlatUnderPoint(host, xPx, yPx);
  if (fromCache >= rowStart && fromCache < rowStart + columnsPerRow && fromCache < n) {
    return fromCache;
  }
  for (let k = columnsPerRow - 1; k >= 0; k--) {
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
  if (next.length === 0 && host.cgSlideGestureActive && host.selectedIds.length > 0) {
    return;
  }
  host.cgSlideLastAppliedEndFlat = ef;
  host.selectedIds = next;
}

function categoryGalleryBeginSlideSelectGestureCore(
  host: CategoryGallerySelectionHost,
  anchorFlat: number,
  refX: number | null,
  refY: number | null
): void {
  cgSlideTraceLastMs = 0;
  cgSlideTraceLastFlat = -99999;
  galleryGridSlideLog('cg_begin', `anchor=${anchorFlat} sel=${host.selectionMode ? '1' : '0'} scroll=${host.cgScrollEnabled ? '1' : '0'}`);
  host.cgSlideGestureActive = true;
  host.cgScrollEnabled = false;
  host.cgSlideAnchorFlat = anchorFlat >= 0 ? anchorFlat : -1;
  host.cgSlideUnionBase = host.selectedIds.slice();
  host.cgSlideLastEndFlat = host.cgSlideAnchorFlat;
  host.cgSlideLastAppliedEndFlat = -99999;
  categoryGalleryRecordAnchorRow(host, anchorFlat);
  if (refX !== null && refY !== null) {
    host.cgSlideRefX = refX;
    host.cgSlideRefY = refY;
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

export function categoryGalleryBeginSlideSelectGesture(
  host: CategoryGallerySelectionHost,
  ev: GestureEvent,
  anchorFlat: number
): void {
  const win = categoryGalleryReadGestureFingerWindow(ev);
  if (win !== null) {
    categoryGalleryBeginSlideSelectGestureCore(
      host,
      anchorFlat,
      categoryGalleryVpToPx(host, win.x),
      categoryGalleryVpToPx(host, win.y)
    );
    return;
  }
  categoryGalleryBeginSlideSelectGestureCore(host, anchorFlat, null, null);
}

/** 触摸长按兜底：按窗口像素坐标起划选，不依赖 Sequence 仍活着 */
export function categoryGalleryBeginSlideSelectGestureAtWindowPx(
  host: CategoryGallerySelectionHost,
  anchorFlat: number,
  xPx: number,
  yPx: number
): void {
  categoryGalleryBeginSlideSelectGestureCore(host, anchorFlat, xPx, yPx);
}

export function categoryGalleryEndSlideSelectGesture(host: CategoryGallerySelectionHost): void {
  gallerySlideAutoScrollStop();
  if (!host.cgSlideGestureActive && host.cgScrollEnabled) {
    galleryGridSlideLog('cg_end_skip', `slide=${host.cgSlideGestureActive ? '1' : '0'} scroll=${host.cgScrollEnabled ? '1' : '0'}`);
    return;
  }
  galleryGridSlideLog('cg_end', `slide=${host.cgSlideGestureActive ? '1' : '0'} scroll=${host.cgScrollEnabled ? '1' : '0'}`);
  host.cgSlideGestureActive = false;
  host.cgSlideHasRef = false;
  host.cgSlideAnchorFlat = -1;
  host.cgSlideUnionBase = [];
  host.cgSlideLastEndFlat = -1;
  host.cgSlideLastAppliedEndFlat = -99999;
  host.cgScrollEnabled = true;
}

function categoryGalleryShiftHitBoundsY(host: CategoryGallerySelectionHost, dyPx: number): void {
  if (!Number.isFinite(dyPx) || Math.abs(dyPx) < 0.5) {
    return;
  }
  host.cgThumbHitBounds.forEach((rect: CgThumbHitRect): void => {
    rect.top += dyPx;
    rect.bottom += dyPx;
  });
}

function categoryGalleryBindSlideAutoScroll(host: CategoryGallerySelectionHost): GallerySlideAutoScrollSession {
  cgSlideAutoScrollSession.uiContext = host.getUIContext();
  cgSlideAutoScrollSession.scroller = host.listScroller;
  cgSlideAutoScrollSession.listDomId = host.listDomId;
  cgSlideAutoScrollSession.topInsetVp = 0;
  cgSlideAutoScrollSession.bottomInsetVp = 0;
  cgSlideAutoScrollSession.isActive = (): boolean => host.cgSlideGestureActive;
  cgSlideAutoScrollSession.shiftHitBoundsY = (dyPx: number): void => {
    categoryGalleryShiftHitBoundsY(host, dyPx);
  };
  cgSlideAutoScrollSession.followPointer = (xPx: number, yPx: number, cacheOnly: boolean): void => {
    categoryGalleryFollowSlidePointer(host, xPx, yPx, cacheOnly);
  };
  return cgSlideAutoScrollSession;
}

function categoryGalleryFollowSlidePointer(
  host: CategoryGallerySelectionHost,
  xPx: number,
  yPx: number,
  cacheOnly: boolean = false
): void {
  if (!host.cgSlideGestureActive) {
    galleryGridSlideLog('cg_follow_skip', 'reason=inactive');
    return;
  }
  const directHitFlat = cacheOnly
    ? categoryGalleryPickFlatUnderPoint(host, xPx, yPx)
    : categoryGalleryPickFlatForSlidePointer(host, xPx, yPx);
  let hitFlat = directHitFlat;
  let geometryHitFlat = -1;
  let usedRowFallback = false;
  if (hitFlat < 0 && !cacheOnly) {
    geometryHitFlat = categoryGalleryEstimateFlatInAnchorRow(host, xPx, yPx);
    hitFlat = geometryHitFlat;
  }
  if (hitFlat < 0) {
    usedRowFallback = true;
    hitFlat = pickSlideEndFlatFromRowBand(
      yPx,
      host.flatItems.length,
      host.cgSlideAnchorFlat,
      (fi: number): CgThumbHitRect | undefined => host.cgThumbHitBounds.get(`${fi}`)
    );
  }
  if (hitFlat >= 0) {
    host.cgSlideLastEndFlat = hitFlat;
  }
  categoryGalleryApplySlideRowRangeSelection(host, host.cgSlideLastEndFlat);
  const now = Date.now();
  if (host.cgSlideLastEndFlat !== cgSlideTraceLastFlat || now - cgSlideTraceLastMs >= 120) {
    cgSlideTraceLastMs = now;
    cgSlideTraceLastFlat = host.cgSlideLastEndFlat;
    galleryGridSlideLog(
      'cg_follow',
      `xy=${Math.round(xPx)},${Math.round(yPx)} direct=${directHitFlat} geom=${geometryHitFlat}` +
        ` end=${host.cgSlideLastEndFlat}` +
        ` anchor=${host.cgSlideAnchorFlat} fallback=${usedRowFallback ? '1' : '0'}` +
        ` cache=${cacheOnly ? '1' : '0'} rects=${host.cgThumbHitBounds.size} selected=${host.selectedIds.length}`
    );
  }
}

function categoryGalleryUpdateSlideAutoScroll(
  host: CategoryGallerySelectionHost,
  xPx: number,
  yPx: number
): void {
  gallerySlideAutoScrollUpdate(categoryGalleryBindSlideAutoScroll(host), xPx, yPx);
}

export function categoryGalleryResolveSlidePointerWindowPx(
  host: CategoryGallerySelectionHost,
  ev: GestureEvent
): CgFingerWindowPoint | null {
  const win = categoryGalleryReadGestureFingerWindow(ev);
  if (win !== null) {
    return { x: categoryGalleryVpToPx(host, win.x), y: categoryGalleryVpToPx(host, win.y) };
  }
  if (!host.cgSlideHasRef) {
    return null;
  }
  return {
    x: host.cgSlideRefX + categoryGalleryPanOffsetVpToPx(host, ev.offsetX),
    y: host.cgSlideRefY + categoryGalleryPanOffsetVpToPx(host, ev.offsetY)
  };
}

export function categoryGalleryOnSlidePanUpdate(host: CategoryGallerySelectionHost, ev: GestureEvent): void {
  if (!host.cgSlideGestureActive) {
    galleryGridSlideLog('cg_pan_skip', 'reason=inactive');
    return;
  }
  const pt = categoryGalleryResolveSlidePointerWindowPx(host, ev);
  if (pt === null) {
    galleryGridSlideLog('cg_pan_skip',
      `reason=no_pointer ref=${host.cgSlideHasRef ? '1' : '0'} dx=${Math.round(ev.offsetX)} dy=${Math.round(ev.offsetY)}`);
    return;
  }
  categoryGalleryUpdateSlideAutoScroll(host, pt.x, pt.y);
  categoryGalleryFollowSlidePointer(host, pt.x, pt.y);
}

export function categoryGalleryOnSlideTouchMoveWindow(
  host: CategoryGallerySelectionHost,
  xPx: number,
  yPx: number
): void {
  categoryGalleryUpdateSlideAutoScroll(host, xPx, yPx);
  categoryGalleryFollowSlidePointer(host, xPx, yPx);
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
