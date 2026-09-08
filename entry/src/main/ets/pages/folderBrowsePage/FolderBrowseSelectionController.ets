import { UIContext } from '@kit.ArkUI';
import { playGalleryEnterSelectionHaptic } from '../../album/GallerySelectionHaptic';
import {
  isVideoItem,
  nasUrl,
  pickThumb,
  prefetchThumbPix
} from '../../album/GalleryAlbumCommon';
import {
  gallerySlideAutoScrollDirection,
  gallerySlideAutoScrollStop,
  gallerySlideAutoScrollUpdate,
  gallerySlideAutoScrollVelocityVpS,
  GallerySlideAutoScrollSession
} from '../../album/GallerySlideAutoScroll';
import {
  pickIndexedFlatForSlidePointer,
  pickSlideEndFlatFromRowBand
} from '../../album/GallerySlidePick';
import { fnClampGridColumns } from '../../common/FnWindowBreakpoint';
import { galleryGridSlideLog } from '../../album/GalleryGridSlideTouch';
import {
  FOLDER_BROWSE_KIND_FOLDER,
  FOLDER_BROWSE_KIND_MEDIA,
  FolderBrowseFingerCoordCompat,
  FolderBrowseFingerWindowPoint,
  FolderBrowseGridItem,
  FolderBrowseThumbHitRect
} from './FolderBrowseTypes';
import { folderBrowseSelectionIdOf } from './FolderBrowseLogic';

export interface FolderBrowseSelectionHost {
  getUIContext(): UIContext;
  baseUrl: string;
  gridItems: FolderBrowseGridItem[];
  columnsPerRow: number;
  selectionMode: boolean;
  selectedIds: string[];
  listScroller: Scroller;
  listDomId: string;
  fbSlideGestureActive: boolean;
  fbScrollEnabled: boolean;
  fbLongPressIgnoreUntil: number;
  fbThumbHitBounds: Map<string, FolderBrowseThumbHitRect>;
  fbSlideRefX: number;
  fbSlideRefY: number;
  fbSlideHasRef: boolean;
  fbSlideAnchorFlat: number;
  fbSlideUnionBase: string[];
  fbSlideLastEndFlat: number;
  fbSlideLastAppliedEndFlat: number;
  toast(msg: string): void;
  openMedia(index: number): void;
  enterFolder(path: string): void;
}

const fbSlideAutoScrollSession: GallerySlideAutoScrollSession = new GallerySlideAutoScrollSession();
let fbSlideTraceLastMs: number = 0;
let fbSlideTraceLastFlat: number = -99999;
let fbSlideLastPrefetchFlat: number = -1;
let fbSlideLastPrefetchDirection: number = 0;

export function folderBrowseDomId(flatIdx: number): string {
  return `fbcell_${flatIdx}`;
}

function folderBrowsePrefetchSlideDirection(host: FolderBrowseSelectionHost, anchorFlat: number): void {
  const direction = gallerySlideAutoScrollDirection();
  const columns = Math.max(1, host.columnsPerRow);
  if (direction === 0 || anchorFlat < 0 ||
    (direction === fbSlideLastPrefetchDirection &&
      Math.abs(anchorFlat - fbSlideLastPrefetchFlat) < columns)) {
    return;
  }
  fbSlideLastPrefetchFlat = anchorFlat;
  fbSlideLastPrefetchDirection = direction;
  const rows = Math.max(2, Math.min(6, Math.ceil(Math.abs(gallerySlideAutoScrollVelocityVpS()) / 200)));
  const count = columns * rows;
  for (let step = 1; step <= count; step++) {
    const index = anchorFlat + direction * step;
    if (index < 0 || index >= host.gridItems.length) {
      break;
    }
    const item = host.gridItems[index];
    if (item.kind === FOLDER_BROWSE_KIND_MEDIA && item.media !== undefined) {
      prefetchThumbPix(nasUrl(host.baseUrl, pickThumb(item.media)), isVideoItem(item.media));
    }
  }
}

export function folderBrowseExitSelection(host: FolderBrowseSelectionHost): void {
  host.selectionMode = false;
  host.selectedIds = [];
  folderBrowseEndSlideSelectGesture(host);
  host.fbLongPressIgnoreUntil = 0;
  host.fbThumbHitBounds.clear();
}

export function folderBrowseToggleToolbarMode(host: FolderBrowseSelectionHost): void {
  if (host.selectionMode) {
    folderBrowseExitSelection(host);
  } else {
    host.selectionMode = true;
  }
}

export function folderBrowseToggleIdSelected(host: FolderBrowseSelectionHost, id: string): void {
  if (id.length === 0) {
    return;
  }
  const next: string[] = [];
  let found = false;
  for (let i = 0; i < host.selectedIds.length; i++) {
    if (host.selectedIds[i] === id) {
      found = true;
    } else {
      next.push(host.selectedIds[i]);
    }
  }
  if (!found) {
    next.push(id);
  }
  host.selectedIds = next;
}

export function folderBrowseReadGestureFingerWindow(ev: GestureEvent): FolderBrowseFingerWindowPoint | null {
  const fl = ev.fingerList;
  if (fl === undefined || fl.length < 1) {
    return null;
  }
  const f0 = fl[0] as FolderBrowseFingerCoordCompat;
  const x = f0.windowX ?? f0.globalX ?? f0.screenX ?? f0.displayX ?? f0.x;
  const y = f0.windowY ?? f0.globalY ?? f0.screenY ?? f0.displayY ?? f0.y;
  if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
    return null;
  }
  return { x, y };
}

function folderBrowseVpToPx(host: FolderBrowseSelectionHost, value: number): number {
  try {
    return host.getUIContext().vp2px(value);
  } catch (_e) {
    return value;
  }
}

function folderBrowsePxToVp(host: FolderBrowseSelectionHost, value: number): number {
  try {
    return host.getUIContext().px2vp(value);
  } catch (_e) {
    return value;
  }
}

export function folderBrowsePanOffsetVpToPx(host: FolderBrowseSelectionHost, deltaVp: number): number {
  const probePx = 100;
  const probeVp = folderBrowsePxToVp(host, probePx);
  if (probeVp < 0.0001) {
    return deltaVp;
  }
  return deltaVp * (probePx / probeVp);
}

export function folderBrowseRecordThumbRect(host: FolderBrowseSelectionHost, flatIdx: number): void {
  if (flatIdx < 0 || flatIdx >= host.gridItems.length) {
    return;
  }
  try {
    const info = host.getUIContext().getComponentUtils().getRectangleById(folderBrowseDomId(flatIdx));
    const x = info.windowOffset.x as number;
    const y = info.windowOffset.y as number;
    const w = info.size.width as number;
    const h = info.size.height as number;
    if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
      host.fbThumbHitBounds.delete(`${flatIdx}`);
      return;
    }
    host.fbThumbHitBounds.set(`${flatIdx}`, { left: x, top: y, right: x + w, bottom: y + h });
  } catch (_e) {
  }
}

function folderBrowseFlatRowRange(host: FolderBrowseSelectionHost, flatIdx: number): number[] {
  if (flatIdx < 0 || flatIdx >= host.gridItems.length) {
    return [-1, -1];
  }
  const columns = fnClampGridColumns(host.columnsPerRow);
  const rowStart = Math.floor(flatIdx / columns) * columns;
  return [rowStart, Math.min(host.gridItems.length - 1, rowStart + columns - 1)];
}

function folderBrowseRecordAnchorRow(host: FolderBrowseSelectionHost, anchorFlat: number): void {
  const range = folderBrowseFlatRowRange(host, anchorFlat);
  for (let fi = range[0]; fi >= 0 && fi <= range[1]; fi++) {
    folderBrowseRecordThumbRect(host, fi);
  }
}

function folderBrowseEstimateFlatInAnchorRow(
  host: FolderBrowseSelectionHost,
  xPx: number,
  yPx: number
): number {
  const anchor = host.fbSlideAnchorFlat;
  const anchorRect = host.fbThumbHitBounds.get(`${anchor}`);
  if (anchorRect === undefined) {
    return -1;
  }
  const width = anchorRect.right - anchorRect.left;
  const height = anchorRect.bottom - anchorRect.top;
  if (width < 1 || height < 1 ||
    yPx < anchorRect.top - height * 0.35 || yPx > anchorRect.bottom + height * 0.35) {
    return -1;
  }
  const range = folderBrowseFlatRowRange(host, anchor);
  if (range[0] < 0) {
    return -1;
  }
  const anchorCenterX = (anchorRect.left + anchorRect.right) * 0.5;
  const estimated = anchor + Math.round((xPx - anchorCenterX) / width);
  return Math.max(range[0], Math.min(range[1], estimated));
}

export function folderBrowseHitThumbDomPx(
  host: FolderBrowseSelectionHost,
  flatIdx: number,
  xPx: number,
  yPx: number
): boolean {
  if (flatIdx < 0 || flatIdx >= host.gridItems.length) {
    return false;
  }
  try {
    const info = host.getUIContext().getComponentUtils().getRectangleById(folderBrowseDomId(flatIdx));
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

export function folderBrowsePickThumbFlatUnderPoint(
  host: FolderBrowseSelectionHost,
  xPx: number,
  yPx: number
): number {
  const n = host.gridItems.length;
  if (host.fbThumbHitBounds.size === 0 || n <= 0) {
    return -1;
  }
  for (let i = n - 1; i >= 0; i--) {
    const cached = host.fbThumbHitBounds.get(`${i}`);
    if (cached === undefined) {
      continue;
    }
    if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
      return i;
    }
  }
  return -1;
}

export function folderBrowsePickThumbFlatForRow(
  host: FolderBrowseSelectionHost,
  rowStart: number,
  xPx: number,
  yPx: number
): number {
  const n = host.gridItems.length;
  const columnsPerRow = fnClampGridColumns(host.columnsPerRow);
  const fromCache = folderBrowsePickThumbFlatUnderPoint(host, xPx, yPx);
  if (fromCache >= rowStart && fromCache < rowStart + columnsPerRow && fromCache < n) {
    return fromCache;
  }
  for (let k = columnsPerRow - 1; k >= 0; k--) {
    const fi = rowStart + k;
    if (fi >= n) {
      continue;
    }
    const cached = host.fbThumbHitBounds.get(`${fi}`);
    if (cached !== undefined) {
      if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
        return fi;
      }
      continue;
    }
    if (folderBrowseHitThumbDomPx(host, fi, xPx, yPx)) {
      return fi;
    }
  }
  return -1;
}

export function folderBrowsePickThumbFlatForSlidePointer(
  host: FolderBrowseSelectionHost,
  xPx: number,
  yPx: number
): number {
  return pickIndexedFlatForSlidePointer(
    xPx,
    yPx,
    host.gridItems.length,
    host.fbSlideLastEndFlat,
    host.fbSlideAnchorFlat,
    (ax: number, ay: number): number => folderBrowsePickThumbFlatUnderPoint(host, ax, ay),
    (fi: number): FolderBrowseThumbHitRect | undefined => host.fbThumbHitBounds.get(`${fi}`),
    (fi: number, ax: number, ay: number): boolean => folderBrowseHitThumbDomPx(host, fi, ax, ay),
    (fi: number): void => {
      folderBrowseRecordThumbRect(host, fi);
    }
  );
}

export function folderBrowseCollectIdsInFlatRange(
  host: FolderBrowseSelectionHost,
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
  const n = host.gridItems.length;
  for (let fi = a; fi <= b && fi < n; fi++) {
    const id = folderBrowseSelectionIdOf(host.gridItems[fi]);
    if (id.length > 0) {
      out.push(id);
    }
  }
  return out;
}

export function folderBrowseApplySlideRowRangeSelection(
  host: FolderBrowseSelectionHost,
  endFlat: number
): void {
  if (host.fbSlideAnchorFlat < 0) {
    return;
  }
  const ef = endFlat >= 0 ? endFlat : host.fbSlideAnchorFlat;
  if (host.fbSlideGestureActive && ef === host.fbSlideLastAppliedEndFlat) {
    return;
  }
  let lo = host.fbSlideAnchorFlat;
  let hi = ef;
  if (lo > hi) {
    const t = lo;
    lo = hi;
    hi = t;
  }
  const rangeIds = folderBrowseCollectIdsInFlatRange(host, lo, hi);
  const seen = new Set<string>();
  const next: string[] = [];
  for (let i = 0; i < host.fbSlideUnionBase.length; i++) {
    const v = host.fbSlideUnionBase[i];
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
  if (next.length === 0 && host.fbSlideGestureActive && host.selectedIds.length > 0) {
    return;
  }
  host.fbSlideLastAppliedEndFlat = ef;
  host.selectedIds = next;
}

function folderBrowseBeginSlideSelectGestureCore(
  host: FolderBrowseSelectionHost,
  anchorFlat: number,
  refX: number | null,
  refY: number | null
): void {
  fbSlideTraceLastMs = 0;
  fbSlideTraceLastFlat = -99999;
  galleryGridSlideLog('fb_begin',
    `anchor=${anchorFlat} sel=${host.selectionMode ? '1' : '0'} scroll=${host.fbScrollEnabled ? '1' : '0'}`);
  host.fbSlideGestureActive = true;
  host.fbScrollEnabled = false;
  host.fbSlideAnchorFlat = anchorFlat >= 0 ? anchorFlat : -1;
  host.fbSlideUnionBase = host.selectedIds.slice();
  host.fbSlideLastEndFlat = host.fbSlideAnchorFlat;
  host.fbSlideLastAppliedEndFlat = -99999;
  folderBrowseRecordAnchorRow(host, anchorFlat);
  if (refX !== null && refY !== null) {
    host.fbSlideRefX = refX;
    host.fbSlideRefY = refY;
    host.fbSlideHasRef = true;
  } else {
    const cached = host.fbThumbHitBounds.get(`${anchorFlat}`);
    if (cached !== undefined) {
      host.fbSlideRefX = (cached.left + cached.right) * 0.5;
      host.fbSlideRefY = (cached.top + cached.bottom) * 0.5;
      host.fbSlideHasRef = true;
    } else {
      host.fbSlideHasRef = false;
    }
  }
  folderBrowseApplySlideRowRangeSelection(host, host.fbSlideLastEndFlat);
}

export function folderBrowseBeginSlideSelectGesture(
  host: FolderBrowseSelectionHost,
  ev: GestureEvent,
  anchorFlat: number
): void {
  const win = folderBrowseReadGestureFingerWindow(ev);
  if (win !== null) {
    folderBrowseBeginSlideSelectGestureCore(
      host,
      anchorFlat,
      folderBrowseVpToPx(host, win.x),
      folderBrowseVpToPx(host, win.y)
    );
    return;
  }
  folderBrowseBeginSlideSelectGestureCore(host, anchorFlat, null, null);
}

export function folderBrowseBeginSlideSelectGestureAtWindowPx(
  host: FolderBrowseSelectionHost,
  anchorFlat: number,
  xPx: number,
  yPx: number
): void {
  folderBrowseBeginSlideSelectGestureCore(host, anchorFlat, xPx, yPx);
}

export function folderBrowseEndSlideSelectGesture(host: FolderBrowseSelectionHost): void {
  gallerySlideAutoScrollStop();
  if (!host.fbSlideGestureActive && host.fbScrollEnabled) {
    galleryGridSlideLog('fb_end_skip',
      `slide=${host.fbSlideGestureActive ? '1' : '0'} scroll=${host.fbScrollEnabled ? '1' : '0'}`);
    return;
  }
  galleryGridSlideLog('fb_end',
    `slide=${host.fbSlideGestureActive ? '1' : '0'} scroll=${host.fbScrollEnabled ? '1' : '0'}`);
  host.fbSlideGestureActive = false;
  host.fbSlideHasRef = false;
  host.fbSlideAnchorFlat = -1;
  host.fbSlideUnionBase = [];
  host.fbSlideLastEndFlat = -1;
  host.fbSlideLastAppliedEndFlat = -99999;
  host.fbScrollEnabled = true;
}

function folderBrowseShiftHitBoundsY(host: FolderBrowseSelectionHost, dyPx: number): void {
  if (!Number.isFinite(dyPx) || Math.abs(dyPx) < 0.5) {
    return;
  }
  host.fbThumbHitBounds.forEach((rect: FolderBrowseThumbHitRect): void => {
    rect.top += dyPx;
    rect.bottom += dyPx;
  });
}

function folderBrowseBindSlideAutoScroll(host: FolderBrowseSelectionHost): GallerySlideAutoScrollSession {
  fbSlideAutoScrollSession.uiContext = host.getUIContext();
  fbSlideAutoScrollSession.scroller = host.listScroller;
  fbSlideAutoScrollSession.listDomId = host.listDomId;
  fbSlideAutoScrollSession.topInsetVp = 0;
  fbSlideAutoScrollSession.bottomInsetVp = 0;
  fbSlideAutoScrollSession.isActive = (): boolean => host.fbSlideGestureActive;
  fbSlideAutoScrollSession.shiftHitBoundsY = (dyPx: number): void => {
    folderBrowseShiftHitBoundsY(host, dyPx);
  };
  fbSlideAutoScrollSession.followPointer = (xPx: number, yPx: number, cacheOnly: boolean): void => {
    folderBrowseFollowSlidePointer(host, xPx, yPx, cacheOnly);
  };
  return fbSlideAutoScrollSession;
}

function folderBrowseFollowSlidePointer(
  host: FolderBrowseSelectionHost,
  xPx: number,
  yPx: number,
  cacheOnly: boolean = false
): void {
  if (!host.fbSlideGestureActive) {
    galleryGridSlideLog('fb_follow_skip', 'reason=inactive');
    return;
  }
  const directHitFlat = cacheOnly
    ? folderBrowsePickThumbFlatUnderPoint(host, xPx, yPx)
    : folderBrowsePickThumbFlatForSlidePointer(host, xPx, yPx);
  let hitFlat = directHitFlat;
  let geometryHitFlat = -1;
  let usedRowFallback = false;
  if (hitFlat < 0 && !cacheOnly) {
    geometryHitFlat = folderBrowseEstimateFlatInAnchorRow(host, xPx, yPx);
    hitFlat = geometryHitFlat;
  }
  if (hitFlat < 0) {
    usedRowFallback = true;
    hitFlat = pickSlideEndFlatFromRowBand(
      yPx,
      host.gridItems.length,
      host.fbSlideAnchorFlat,
      (fi: number): FolderBrowseThumbHitRect | undefined => host.fbThumbHitBounds.get(`${fi}`)
    );
  }
  if (hitFlat >= 0) {
    host.fbSlideLastEndFlat = hitFlat;
  }
  folderBrowsePrefetchSlideDirection(host, host.fbSlideLastEndFlat);
  folderBrowseApplySlideRowRangeSelection(host, host.fbSlideLastEndFlat);
  const now = Date.now();
  if (host.fbSlideLastEndFlat !== fbSlideTraceLastFlat || now - fbSlideTraceLastMs >= 120) {
    fbSlideTraceLastMs = now;
    fbSlideTraceLastFlat = host.fbSlideLastEndFlat;
    galleryGridSlideLog(
      'fb_follow',
      `xy=${Math.round(xPx)},${Math.round(yPx)} direct=${directHitFlat} geom=${geometryHitFlat}` +
        ` end=${host.fbSlideLastEndFlat}` +
        ` anchor=${host.fbSlideAnchorFlat} fallback=${usedRowFallback ? '1' : '0'}` +
        ` cache=${cacheOnly ? '1' : '0'} rects=${host.fbThumbHitBounds.size} selected=${host.selectedIds.length}`
    );
  }
}

function folderBrowseUpdateSlideAutoScroll(host: FolderBrowseSelectionHost, xPx: number, yPx: number): void {
  gallerySlideAutoScrollUpdate(folderBrowseBindSlideAutoScroll(host), xPx, yPx);
}

export function folderBrowseOnSlidePanUpdate(host: FolderBrowseSelectionHost, ev: GestureEvent): void {
  if (!host.fbSlideGestureActive) {
    galleryGridSlideLog('fb_pan_skip', 'reason=inactive');
    return;
  }
  const win = folderBrowseReadGestureFingerWindow(ev);
  if (win !== null) {
    const xPx = folderBrowseVpToPx(host, win.x);
    const yPx = folderBrowseVpToPx(host, win.y);
    folderBrowseUpdateSlideAutoScroll(host, xPx, yPx);
    folderBrowseFollowSlidePointer(host, xPx, yPx);
    return;
  }
  if (!host.fbSlideHasRef) {
    galleryGridSlideLog('fb_pan_skip',
      `reason=no_pointer ref=${host.fbSlideHasRef ? '1' : '0'} dx=${Math.round(ev.offsetX)} dy=${Math.round(ev.offsetY)}`);
    return;
  }
  const xPx = host.fbSlideRefX + folderBrowsePanOffsetVpToPx(host, ev.offsetX);
  const yPx = host.fbSlideRefY + folderBrowsePanOffsetVpToPx(host, ev.offsetY);
  folderBrowseUpdateSlideAutoScroll(host, xPx, yPx);
  folderBrowseFollowSlidePointer(host, xPx, yPx);
}

export function folderBrowseOnSlideTouchMoveWindow(
  host: FolderBrowseSelectionHost,
  xPx: number,
  yPx: number
): void {
  folderBrowseUpdateSlideAutoScroll(host, xPx, yPx);
  folderBrowseFollowSlidePointer(host, xPx, yPx);
}

export function folderBrowseOnThumbLongPress(
  host: FolderBrowseSelectionHost,
  item: FolderBrowseGridItem,
  _flatIdx: number
): void {
  const id = folderBrowseSelectionIdOf(item);
  if (id.length === 0) {
    host.toast('该项无法多选');
    return;
  }
  if (host.fbSlideGestureActive) {
    return;
  }
  host.fbLongPressIgnoreUntil = Date.now() + 500;
  if (!host.selectionMode) {
    playGalleryEnterSelectionHaptic();
    host.selectionMode = true;
    host.selectedIds = [id];
  } else {
    folderBrowseToggleIdSelected(host, id);
  }
}

export function folderBrowseOnCellClick(
  host: FolderBrowseSelectionHost,
  item: FolderBrowseGridItem,
  _flatIdx: number
): void {
  if (Date.now() < host.fbLongPressIgnoreUntil) {
    return;
  }
  const id = folderBrowseSelectionIdOf(item);
  if (host.selectionMode) {
    folderBrowseToggleIdSelected(host, id);
    return;
  }
  if (item.kind === FOLDER_BROWSE_KIND_FOLDER) {
    host.enterFolder(item.folderPath);
    return;
  }
  if (item.kind === FOLDER_BROWSE_KIND_MEDIA) {
    host.openMedia(item.mediaIndex);
  }
}
