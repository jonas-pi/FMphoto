import { hilog } from '@kit.PerformanceAnalysisKit';
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
  gallerySlideLastApplyMs: number;
  gallerySlidePendingEndFlat: number;
  galleryMainListDomId: string;
  gallerySlideAutoScrollTimer: number;
  gallerySlideAutoScrollVelocityVp: number;
  gallerySlideAutoScrollPointerX: number;
  gallerySlideAutoScrollPointerY: number;
  galleryLongPressIgnoreClickUntil: number;
  gallerySlideRefX: number;
  gallerySlideRefY: number;
  gallerySlideHasRef: boolean;
  searchResults: GalleryListItem[];
  scrollerRef: Scroller;
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

const GALLERY_SLIDE_SELECTION_APPLY_MIN_GAP_MS: number = 24;
const GALLERY_SLIDE_SELECTION_APPLY_FORCE_GAP_FLATS: number = 2;
const GALLERY_SLIDE_AUTO_SCROLL_TICK_MS: number = 16;
const GALLERY_SLIDE_AUTO_SCROLL_EDGE_VP: number = 108;
const GALLERY_SLIDE_AUTO_SCROLL_MIN_STEP_VP: number = 1.0;
const GALLERY_SLIDE_AUTO_SCROLL_MAX_STEP_VP: number = 20.0;
const GALLERY_SELECTION_DIAG_DOMAIN: number = 0xFF00;
const GALLERY_SELECTION_DIAG_TAG: string = 'GalleryDiag';

interface SelectionGalleryFlowSlot {
  flowIndex: number;
  slotIndex: number;
  node: GalleryFlowNode;
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

function selectionSameIdsInOrder(a: string[], b: string[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
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

function selectionVpToPx(host: SelectionGestureControllerHost, value: number): number {
  try {
    return host.getUIContext().vp2px(value);
  } catch (_e) {
    return value;
  }
}

function selectionPxToVp(host: SelectionGestureControllerHost, value: number): number {
  try {
    return host.getUIContext().px2vp(value);
  } catch (_e) {
    return value;
  }
}

export function selectionPanOffsetVpToPx(
  host: SelectionGestureControllerHost,
  deltaVp: number
): number {
  const probePx = 100;
  const probeVp = selectionPxToVp(host, probePx);
  if (probeVp < 0.0001) {
    return deltaVp;
  }
  return deltaVp * (probePx / probeVp);
}

function selectionBeginGallerySlideSelectGestureCore(
  host: SelectionGestureControllerHost,
  item: GalleryListItem,
  anchorFlat: number,
  refX: number | null,
  refY: number | null
): void {
  host.gallerySlideGestureActive = true;
  host.galleryMainListScrollEnabled = false;
  host.gallerySlideAnchorFlat = anchorFlat >= 0 ? anchorFlat : -1;
  host.gallerySlideUnionBase = host.gallerySelectedIds.slice();
  host.gallerySlideLastEndFlat = host.gallerySlideAnchorFlat;
  host.gallerySlideLastAppliedEndFlat = -99999;
  host.gallerySlideLastApplyMs = 0;
  host.gallerySlidePendingEndFlat = host.gallerySlideAnchorFlat;
  const anchorId = host.itemIdOf(item);
  if (host.inSearchMode) {
    selectionRecordSearchThumbRect(host, anchorFlat);
  } else if (anchorId.length > 0) {
    host.recordGalleryThumbRectFromDom(anchorId, host.galleryThumbDomId(anchorId));
  }
  if (refX !== null && refY !== null) {
    host.gallerySlideRefX = refX;
    host.gallerySlideRefY = refY;
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

export function selectionBeginGallerySlideSelectGesture(
  host: SelectionGestureControllerHost,
  ev: GestureEvent,
  item: GalleryListItem,
  anchorFlat: number
): void {
  const win = selectionReadGestureFingerWindow(host, ev);
  if (win !== null) {
    selectionBeginGallerySlideSelectGestureCore(
      host,
      item,
      anchorFlat,
      selectionVpToPx(host, win.x),
      selectionVpToPx(host, win.y)
    );
    return;
  }
  selectionBeginGallerySlideSelectGestureCore(host, item, anchorFlat, null, null);
}

export function selectionBeginGallerySlideSelectGestureAtWindowPx(
  host: SelectionGestureControllerHost,
  item: GalleryListItem,
  anchorFlat: number,
  xPx: number,
  yPx: number
): void {
  selectionBeginGallerySlideSelectGestureCore(host, item, anchorFlat, xPx, yPx);
}

export function selectionEndGallerySlideSelectGesture(host: SelectionGestureControllerHost): void {
  selectionStopGallerySlideAutoScroll(host);
  const pendingEndFlat = host.gallerySlidePendingEndFlat;
  if (pendingEndFlat >= 0 && pendingEndFlat !== host.gallerySlideLastAppliedEndFlat) {
    selectionApplyGallerySlideRowRangeSelection(host, pendingEndFlat);
  }
  if (!host.gallerySlideGestureActive && host.galleryMainListScrollEnabled) {
    return;
  }
  host.gallerySlideGestureActive = false;
  host.gallerySlideHasRef = false;
  host.gallerySlideAnchorFlat = -1;
  host.gallerySlideUnionBase = [];
  host.gallerySlideLastEndFlat = -1;
  host.gallerySlideLastAppliedEndFlat = -99999;
  host.gallerySlideLastApplyMs = 0;
  host.gallerySlidePendingEndFlat = -1;
  host.galleryMainListScrollEnabled = true;
}

function selectionReadMainGalleryListRectPx(host: SelectionGestureControllerHost): GalleryThumbHitRect | null {
  if (host.galleryMainListDomId.length === 0) {
    return null;
  }
  try {
    const info = host.getUIContext().getComponentUtils().getRectangleById(host.galleryMainListDomId);
    const left = info.windowOffset.x as number;
    const top = info.windowOffset.y as number;
    const width = info.size.width as number;
    const height = info.size.height as number;
    if (!Number.isFinite(left) || !Number.isFinite(top) ||
      !Number.isFinite(width) || !Number.isFinite(height) || width < 1 || height < 1) {
      return null;
    }
    return {
      left: left,
      top: top,
      right: left + width,
      bottom: top + height
    };
  } catch (_e) {
    return null;
  }
}

function selectionComputeGallerySlideAutoScrollStepVp(
  host: SelectionGestureControllerHost,
  yPx: number
): number {
  if (host.inSearchMode || !host.gallerySlideGestureActive) {
    return 0;
  }
  const rect = selectionReadMainGalleryListRectPx(host);
  if (rect === null) {
    return 0;
  }
  const edgePx = Math.max(1, selectionVpToPx(host, GALLERY_SLIDE_AUTO_SCROLL_EDGE_VP));
  const startPx = rect.bottom - edgePx;
  if (yPx <= startPx) {
    return 0;
  }
  const ratio = Math.max(0, Math.min(1, (yPx - startPx) / edgePx));
  const eased = ratio * ratio;
  return GALLERY_SLIDE_AUTO_SCROLL_MIN_STEP_VP +
    (GALLERY_SLIDE_AUTO_SCROLL_MAX_STEP_VP - GALLERY_SLIDE_AUTO_SCROLL_MIN_STEP_VP) * eased;
}

function selectionScrollMainGalleryByVp(host: SelectionGestureControllerHost, deltaVp: number): void {
  if (Math.abs(deltaVp) < 0.01) {
    return;
  }
  try {
    const off = host.scrollerRef.currentOffset();
    const yRaw = off.yOffset;
    const y = typeof yRaw === 'number' && Number.isFinite(yRaw) ? Math.max(0, yRaw) : 0;
    host.scrollerRef.scrollTo({ xOffset: 0, yOffset: Math.max(0, y + deltaVp) });
  } catch (_e) {
  }
}

function selectionStopGallerySlideAutoScroll(host: SelectionGestureControllerHost): void {
  if (host.gallerySlideAutoScrollTimer >= 0) {
    clearInterval(host.gallerySlideAutoScrollTimer);
  }
  host.gallerySlideAutoScrollTimer = -1;
  host.gallerySlideAutoScrollVelocityVp = 0;
}

function selectionTickGallerySlideAutoScroll(host: SelectionGestureControllerHost): void {
  if (!host.gallerySlideGestureActive) {
    selectionStopGallerySlideAutoScroll(host);
    return;
  }
  const stepVp = selectionComputeGallerySlideAutoScrollStepVp(host, host.gallerySlideAutoScrollPointerY);
  if (stepVp <= 0) {
    selectionStopGallerySlideAutoScroll(host);
    return;
  }
  host.gallerySlideAutoScrollVelocityVp = stepVp;
  selectionScrollMainGalleryByVp(host, stepVp);
  selectionOnGallerySlideTouchMoveWindow(
    host,
    host.gallerySlideAutoScrollPointerX,
    host.gallerySlideAutoScrollPointerY
  );
}

function selectionUpdateGallerySlideAutoScroll(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): void {
  host.gallerySlideAutoScrollPointerX = xPx;
  host.gallerySlideAutoScrollPointerY = yPx;
  const stepVp = selectionComputeGallerySlideAutoScrollStepVp(host, yPx);
  host.gallerySlideAutoScrollVelocityVp = stepVp;
  if (stepVp <= 0) {
    selectionStopGallerySlideAutoScroll(host);
    return;
  }
  if (host.gallerySlideAutoScrollTimer >= 0) {
    return;
  }
  host.gallerySlideAutoScrollTimer = setInterval((): void => {
    selectionTickGallerySlideAutoScroll(host);
  }, GALLERY_SLIDE_AUTO_SCROLL_TICK_MS);
}

export function selectionResolveSlidePointerWindowPx(
  host: SelectionGestureControllerHost,
  ev: GestureEvent
): GalleryFingerWindowPoint | null {
  const win = selectionReadGestureFingerWindow(host, ev);
  if (win !== null) {
    return { x: selectionVpToPx(host, win.x), y: selectionVpToPx(host, win.y) };
  }
  if (host.gallerySlideHasRef) {
    return {
      x: host.gallerySlideRefX + selectionPanOffsetVpToPx(host, ev.offsetX),
      y: host.gallerySlideRefY + selectionPanOffsetVpToPx(host, ev.offsetY)
    };
  }
  return null;
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

function selectionCachedGalleryThumbHitValidPx(
  host: SelectionGestureControllerHost,
  photoId: string,
  xPx: number,
  yPx: number
): boolean {
  const cached = host.galleryThumbHitBounds.get(photoId);
  if (cached === undefined ||
    xPx < cached.left || xPx > cached.right || yPx < cached.top || yPx > cached.bottom) {
    return false;
  }
  if (!selectionHitGalleryThumbDomPx(host, photoId, xPx, yPx)) {
    host.galleryThumbHitBounds.delete(photoId);
    return false;
  }
  host.recordGalleryThumbRectFromDom(photoId, host.galleryThumbDomId(photoId));
  return true;
}

function selectionPickGalleryThumbFlatFromCacheOnly(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): number {
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
      if (selectionCachedGalleryThumbHitValidPx(host, id, xPx, yPx)) {
        return node.rowSlotFlatIndices[k];
      }
    }
  }
  return -1;
}

export function selectionPickGalleryThumbFlatUnderPoint(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): number {
  if (host.inSearchMode) {
    return selectionPickSearchThumbFlatUnderPoint(host, xPx, yPx);
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
      if (selectionCachedGalleryThumbHitValidPx(host, id, xPx, yPx)) {
        return node.rowSlotFlatIndices[k];
      }
    }
  }
  let domBudget = GALLERY_SLIDE_DOM_BUDGET_PER_FRAME;
  for (let i = 0; i < n && domBudget > 0; i++) {
    const node = host.flowDataSource.getData(i);
    if (node.kind !== 'row') {
      continue;
    }
    for (let k = node.rowSlotItems.length - 1; k >= 0 && domBudget > 0; k--) {
      const slot = node.rowSlotItems[k];
      if (slot === null || slot === undefined) {
        continue;
      }
      const id = host.itemIdOf(slot);
      if (id.length === 0) {
        continue;
      }
      domBudget--;
      if (selectionHitGalleryThumbDomPx(host, id, xPx, yPx)) {
        host.recordGalleryThumbRectFromDom(id, host.galleryThumbDomId(id));
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
  const fromCache = selectionPickGalleryThumbFlatFromCacheOnly(host, xPx, yPx);
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
      if (selectionCachedGalleryThumbHitValidPx(host, id, xPx, yPx)) {
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
    if (centerRi >= 0) {
      for (let delta = 0; delta <= GALLERY_SLIDE_FLOW_ROW_RADIUS; delta++) {
        const downRi = centerRi + delta;
        if (downRi < nFlow) {
          const hit = tryRowNode(host.flowDataSource.getData(downRi));
          if (hit >= 0) {
            return hit;
          }
        }
        const upRi = centerRi - delta;
        if (delta > 0 && upRi >= 0) {
          const hit = tryRowNode(host.flowDataSource.getData(upRi));
          if (hit >= 0) {
            return hit;
          }
        }
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
    if (selectionCachedGalleryThumbHitValidPx(host, id, xPx, yPx)) {
      return node.rowSlotFlatIndices[k];
    }
    if (selectionHitGalleryThumbDomPx(host, id, xPx, yPx)) {
      host.recordGalleryThumbRectFromDom(id, host.galleryThumbDomId(id));
      return node.rowSlotFlatIndices[k];
    }
  }
  return selectionPickGalleryThumbFlatFromCacheOnly(host, xPx, yPx);
}

function selectionFindGalleryFlowSlot(
  host: SelectionGestureControllerHost,
  flatIdx: number
): SelectionGalleryFlowSlot | null {
  if (flatIdx < 0) {
    return null;
  }
  const total = host.flowDataSource.totalCount();
  for (let i = 0; i < total; i++) {
    const node = host.flowDataSource.getData(i);
    if (node.kind !== 'row') {
      continue;
    }
    for (let k = 0; k < node.rowSlotFlatIndices.length; k++) {
      if (node.rowSlotFlatIndices[k] === flatIdx) {
        return {
          flowIndex: i,
          slotIndex: k,
          node: node
        };
      }
    }
  }
  return null;
}

function selectionGetGalleryFlowSlotRect(
  host: SelectionGestureControllerHost,
  slot: SelectionGalleryFlowSlot
): GalleryThumbHitRect | null {
  const item = slot.node.rowSlotItems[slot.slotIndex];
  if (item === null || item === undefined) {
    return null;
  }
  const id = host.itemIdOf(item);
  if (id.length === 0) {
    return null;
  }
  let rect = host.galleryThumbHitBounds.get(id);
  if (rect !== undefined) {
    return rect;
  }
  host.recordGalleryThumbRectFromDom(id, host.galleryThumbDomId(id));
  rect = host.galleryThumbHitBounds.get(id);
  return rect === undefined ? null : rect;
}

function selectionClampInt(value: number, min: number, max: number): number {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

function selectionPickLoadedFlatInRowNearSlot(node: GalleryFlowNode, slotIndex: number): number {
  const count = node.rowSlotFlatIndices.length;
  if (count <= 0) {
    return -1;
  }
  const start = selectionClampInt(slotIndex, 0, count - 1);
  for (let delta = 0; delta < count; delta++) {
    const right = start + delta;
    if (right < count && node.rowSlotItems[right] !== null && node.rowSlotItems[right] !== undefined &&
      node.rowSlotFlatIndices[right] >= 0) {
      return node.rowSlotFlatIndices[right];
    }
    const left = start - delta;
    if (left >= 0 && left !== right && node.rowSlotItems[left] !== null && node.rowSlotItems[left] !== undefined &&
      node.rowSlotFlatIndices[left] >= 0) {
      return node.rowSlotFlatIndices[left];
    }
  }
  return -1;
}

function selectionEstimateGalleryFlatFromPanOffset(
  host: SelectionGestureControllerHost,
  ev: GestureEvent
): number {
  if (host.inSearchMode || host.gallerySlideAnchorFlat < 0) {
    return -1;
  }
  if (!Number.isFinite(ev.offsetX) || !Number.isFinite(ev.offsetY)) {
    return -1;
  }
  const anchorSlot = selectionFindGalleryFlowSlot(host, host.gallerySlideAnchorFlat);
  if (anchorSlot === null) {
    return -1;
  }
  const anchorRect = selectionGetGalleryFlowSlotRect(host, anchorSlot);
  if (anchorRect === null) {
    return -1;
  }
  const itemWidth = Math.max(1, anchorRect.right - anchorRect.left);
  const itemHeight = Math.max(1, anchorRect.bottom - anchorRect.top);
  const dxPx = selectionPanOffsetVpToPx(host, ev.offsetX);
  const dyPx = selectionPanOffsetVpToPx(host, ev.offsetY);
  if (!Number.isFinite(dxPx) || !Number.isFinite(dyPx)) {
    return -1;
  }
  const colDelta = Math.round(dxPx / itemWidth);
  const rowDelta = Math.round(dyPx / itemHeight);
  if (colDelta === 0 && rowDelta === 0) {
    return host.gallerySlideAnchorFlat;
  }

  const rowFlowIndices: number[] = [];
  let anchorRowOrdinal = -1;
  const total = host.flowDataSource.totalCount();
  for (let i = 0; i < total; i++) {
    const node = host.flowDataSource.getData(i);
    if (node.kind !== 'row') {
      continue;
    }
    if (i === anchorSlot.flowIndex) {
      anchorRowOrdinal = rowFlowIndices.length;
    }
    rowFlowIndices.push(i);
  }
  if (anchorRowOrdinal < 0 || rowFlowIndices.length <= 0) {
    return -1;
  }
  const targetRowOrdinal = selectionClampInt(anchorRowOrdinal + rowDelta, 0, rowFlowIndices.length - 1);
  const targetNode = host.flowDataSource.getData(rowFlowIndices[targetRowOrdinal]);
  const targetSlot = selectionClampInt(
    anchorSlot.slotIndex + colDelta,
    0,
    Math.max(0, targetNode.rowSlotFlatIndices.length - 1)
  );
  return selectionPickLoadedFlatInRowNearSlot(targetNode, targetSlot);
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
  const key = `${flatIdx}`;
  const cached = host.searchThumbHitBounds.get(key);
  if (cached === undefined ||
    xPx < cached.left || xPx > cached.right || yPx < cached.top || yPx > cached.bottom) {
    return false;
  }
  if (!selectionHitSearchThumbDomPx(host, flatIdx, xPx, yPx)) {
    host.searchThumbHitBounds.delete(key);
    return false;
  }
  selectionRecordSearchThumbRect(host, flatIdx);
  return true;
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
  const fromCache = selectionPickSearchThumbFlatUnderPoint(host, xPx, yPx);
  if (fromCache >= rowStart && fromCache < rowStart + 3 && fromCache < n) {
    return fromCache;
  }
  for (let k = 2; k >= 0; k--) {
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
  const next: string[] = [];
  for (let i = 0; i < host.gallerySlideUnionBase.length; i++) {
    const id = host.gallerySlideUnionBase[i];
    if (id.length > 0 && !seen.has(id)) {
      seen.add(id);
      next.push(id);
    }
  }
  for (let i = 0; i < rangeIds.length; i++) {
    const id = rangeIds[i];
    if (id.length > 0 && !seen.has(id)) {
      seen.add(id);
      next.push(id);
    }
  }
  host.gallerySlideLastAppliedEndFlat = ef;
  host.gallerySlideLastApplyMs = Date.now();
  host.gallerySlidePendingEndFlat = ef;
  hilog.warn(
    GALLERY_SELECTION_DIAG_DOMAIN,
    GALLERY_SELECTION_DIAG_TAG,
    'selectionSlide apply mode=%{public}s anchor=%{public}d end=%{public}d lo=%{public}d hi=%{public}d ' +
      'rangeIds=%{public}d base=%{public}d next=%{public}d',
    host.inSearchMode ? 'search' : 'gallery',
    host.gallerySlideAnchorFlat,
    ef,
    lo,
    hi,
    rangeIds.length,
    host.gallerySelectedIds.length,
    next.length
  );
  if (!selectionSameIdsInOrder(next, host.gallerySelectedIds)) {
    host.setGallerySelectedIdsState(next);
  }
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
    selectionStopGallerySlideAutoScroll(host);
    return;
  }
  selectionUpdateGallerySlideAutoScroll(host, pt.x, pt.y);
  const hitFlat = host.inSearchMode ?
    pickSearchThumbFlatUnderPointForSlide(host, pt.x, pt.y) :
    selectionPickGalleryThumbFlatUnderPointForSlide(host, pt.x, pt.y);
  if (hitFlat >= 0) {
    host.gallerySlideLastEndFlat = hitFlat;
  }
  const targetEndFlat = host.gallerySlideLastEndFlat >= 0 ? host.gallerySlideLastEndFlat : host.gallerySlideAnchorFlat;
  if (targetEndFlat < 0) {
    return;
  }
  host.gallerySlidePendingEndFlat = targetEndFlat;
  const now = Date.now();
  const distanceFromApplied = host.gallerySlideLastAppliedEndFlat < 0
    ? Number.MAX_SAFE_INTEGER
    : Math.abs(targetEndFlat - host.gallerySlideLastAppliedEndFlat);
  if (distanceFromApplied >= GALLERY_SLIDE_SELECTION_APPLY_FORCE_GAP_FLATS ||
    now - host.gallerySlideLastApplyMs >= GALLERY_SLIDE_SELECTION_APPLY_MIN_GAP_MS) {
    selectionApplyGallerySlideRowRangeSelection(host, targetEndFlat);
  }
}

export function selectionOnGallerySlideTouchMoveWindow(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): void {
  if (!host.gallerySlideGestureActive) {
    return;
  }
  selectionUpdateGallerySlideAutoScroll(host, xPx, yPx);
  const hitFlat = host.inSearchMode
    ? pickSearchThumbFlatUnderPointForSlide(host, xPx, yPx)
    : selectionPickGalleryThumbFlatUnderPointForSlide(host, xPx, yPx);
  if (hitFlat >= 0) {
    host.gallerySlideLastEndFlat = hitFlat;
  }
  const targetEndFlat = host.gallerySlideLastEndFlat >= 0 ? host.gallerySlideLastEndFlat : host.gallerySlideAnchorFlat;
  if (targetEndFlat < 0) {
    return;
  }
  host.gallerySlidePendingEndFlat = targetEndFlat;
  const now = Date.now();
  const distanceFromApplied = host.gallerySlideLastAppliedEndFlat < 0
    ? Number.MAX_SAFE_INTEGER
    : Math.abs(targetEndFlat - host.gallerySlideLastAppliedEndFlat);
  if (distanceFromApplied >= GALLERY_SLIDE_SELECTION_APPLY_FORCE_GAP_FLATS ||
    now - host.gallerySlideLastApplyMs >= GALLERY_SLIDE_SELECTION_APPLY_MIN_GAP_MS) {
    selectionApplyGallerySlideRowRangeSelection(host, targetEndFlat);
  }
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
  GalleryPreviewNavStore.openPreview(host.getUIContext(), host.baseUrl, host.searchResults, flatIndex);
}
