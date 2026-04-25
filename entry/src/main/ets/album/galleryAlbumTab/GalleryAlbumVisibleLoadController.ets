import { GalleryFlowNode, GalleryWaterFlowDataSource } from '../GalleryFlowDataSource';
import {
  DATE_FEED_BATCH,
  GALLERY_LAST_KNOWN_DEGENERATE_NEW_SLOT_SPAN,
  GALLERY_LAST_KNOWN_MIN_PREV_SLOT_SPAN,
  GALLERY_LAST_KNOWN_SHRINK_IGNORE_RATIO,
  GALLERY_LIST_APPROX_DAY_NODE_VP,
  GALLERY_LIST_APPROX_MONTH_NODE_VP,
  GALLERY_LIST_APPROX_ROW_NODE_VP,
  GALLERY_LOAD_VISIBLE_BUFFER_AFTER_CAP,
  GALLERY_LOAD_VISIBLE_BUFFER_BASE_AGGRESSIVE,
  GALLERY_LOAD_VISIBLE_BUFFER_BASE_NON_AGGRESSIVE,
  GALLERY_LOAD_VISIBLE_BUFFER_SCAN_WIN_NODES,
  GALLERY_LOAD_VISIBLE_MULTI_DAY_CHAIN_MAX,
  GALLERY_LOAD_VISIBLE_SCROLLER_RANGE_PAD_NODES,
  GALLERY_LOAD_VISIBLE_SKELETON_SLOT_MULTIPLIER,
  GALLERY_REFINE_ANCHOR_RESYNC_NODE_DRIFT,
  GALLERY_REFINE_EST_ADV_MAX_DRIFT_NODES,
  GALLERY_REFINE_MIN_VISIBLE_NODE_SPAN,
  GALLERY_SCROLL_DEBUG_LOG,
  GALLERY_SCROLL_DELTA_CONSUME_MAX_IT,
  GALLERY_SCROLL_Y_ESTIMATE_MAX_NODES,
  PUMP_UI_GAP_MS
} from './GalleryAlbumTabConstants';
import {
  DayGlobalResolveResult,
  dayKey,
  GalleryScrollerMaybeVisibleRange,
  GalleryVisibleNodeRange,
  TimelineDayModel,
  TimelineYearMonthPair,
} from './GalleryAlbumTabTypes';
import { findFlowRoughVisibleRangeForYearMonth, findTimelineMonthRange } from './GalleryAlbumTimelineLogic';
import { GalleryAlbumDaySectionState } from './GalleryAlbumState';

export interface GalleryAlbumVisibleLoadHost {
  scrollerRef: Scroller;
  flowDataSource: GalleryWaterFlowDataSource;
  bootLoading: boolean;
  orderedDays: TimelineDayModel[];
  sections: GalleryAlbumDaySectionState[];
  visualPlaceholderMode: boolean;
  isDraggingOrFling: boolean;
  timelineSidebarDragging: boolean;
  pendingFlowRebuild: boolean;
  lastLoadVisibleAtMs: number;
  loadingMore: boolean;
  exhausted: boolean;
  listVisibleFirstNodeIdx: number;
  listVisibleLastNodeIdx: number;
  listScrollIndexAnchorHave: boolean;
  listScrollIndexAnchorYVp: number;
  listScrollIndexAnchorFirst: number;
  lastKnownGlobalPhotoSlotStart: number;
  lastKnownGlobalPhotoSlotEndExclusive: number;
  dayIndex: number;
  lastVisibleLoadDayIdx: number;
  dayOffsets: Map<string, number>;
  pumpEpoch: number;
  loadGen: number;
  loadVisibleRetryTimer: number;
  loadVisibleRetryGen: number;
  timelineSliderRatio: number;
  resolveDayByGlobalIndex(globalIndex: number): DayGlobalResolveResult | null;
  resolveYearMonthByTimelineRatio(ratio: number): TimelineYearMonthPair | null;
  isInScrollInteractiveLogWindow(): boolean;
  logScrollDebug(msg: string): void;
  rebuildFlow(): void;
  pumpLoad(singleBatch?: boolean): void;
  loadOneBatch(): Promise<number>;
}

function galleryAlbumVisibleCancelScheduledRetry(
  host: GalleryAlbumVisibleLoadHost,
  invalidateGen: boolean = true
): void {
  if (host.loadVisibleRetryTimer >= 0) {
    clearTimeout(host.loadVisibleRetryTimer);
    host.loadVisibleRetryTimer = -1;
  }
  if (invalidateGen) {
    host.loadVisibleRetryGen++;
  }
}

function galleryAlbumVisibleScheduleRetryAfterInflight(
  host: GalleryAlbumVisibleLoadHost,
  aggressive: boolean,
  delayMs: number = 48
): void {
  galleryAlbumVisibleCancelScheduledRetry(host, false);
  const retryGen = ++host.loadVisibleRetryGen;
  const epoch = host.pumpEpoch;
  const loadGen = host.loadGen;
  host.loadVisibleRetryTimer = setTimeout((): void => {
    host.loadVisibleRetryTimer = -1;
    if (retryGen !== host.loadVisibleRetryGen) {
      return;
    }
    if (epoch !== host.pumpEpoch || loadGen !== host.loadGen) {
      return;
    }
    if (host.exhausted || host.bootLoading) {
      return;
    }
    if (host.timelineSidebarDragging || host.isDraggingOrFling || host.visualPlaceholderMode) {
      return;
    }
    if (host.loadingMore) {
      galleryAlbumVisibleScheduleRetryAfterInflight(host, aggressive, delayMs);
      return;
    }
    host.lastLoadVisibleAtMs = 0;
    galleryAlbumVisibleLoadVisibleItemsThrottled(host, true, aggressive);
  }, delayMs);
}

export function galleryAlbumVisibleTryApplyScrollerVisibleRangeIfAvailable(
  host: GalleryAlbumVisibleLoadHost,
  total: number
): boolean {
  try {
    const sc = host.scrollerRef as GalleryScrollerMaybeVisibleRange;
    if (sc.getVisibleRange === undefined) {
      return false;
    }
    const range = sc.getVisibleRange();
    if (range === null || range === undefined) {
      return false;
    }
    const st = range.start;
    const en = range.end;
    if (typeof st !== 'number' || typeof en !== 'number' || !Number.isFinite(st) || !Number.isFinite(en)) {
      return false;
    }
    const first = Math.max(0, Math.min(total - 1, Math.floor(st)));
    const last = Math.max(first, Math.min(total - 1, Math.floor(en)));
    host.listVisibleFirstNodeIdx = first;
    host.listVisibleLastNodeIdx = last;
    host.logScrollDebug(`forceRefresh visible range by API: ${first} ~ ${last}`);
    return true;
  } catch (_e) {
    return false;
  }
}

export function galleryAlbumVisibleRefreshVisibleRangeIfAvailable(host: GalleryAlbumVisibleLoadHost): boolean {
  const total = host.flowDataSource.totalCount();
  if (total <= 0) {
    return false;
  }
  if (!galleryAlbumVisibleTryApplyScrollerVisibleRangeIfAvailable(host, total)) {
    return false;
  }
  galleryAlbumVisibleRefreshLastKnownGlobalSlotsFromListIndices(
    host,
    host.listVisibleFirstNodeIdx,
    host.listVisibleLastNodeIdx
  );
  galleryAlbumVisibleCaptureListScrollIndexAnchor(host);
  return true;
}

export function galleryAlbumVisibleNudgeListScrollForScrollIndexRefresh(host: GalleryAlbumVisibleLoadHost): void {
  host.logScrollDebug('forceRefresh: 1vp nudge for onScrollIndex');
  try {
    const off = host.scrollerRef.currentOffset();
    const yRaw = off.yOffset;
    const y = typeof yRaw === 'number' && Number.isFinite(yRaw) ? yRaw : 0;
    host.scrollerRef.scrollTo({ xOffset: 0, yOffset: y + 1 });
    setTimeout((): void => {
      try {
        host.scrollerRef.scrollTo({ xOffset: 0, yOffset: y });
      } catch (_e2) {
      }
    }, 16);
  } catch (_e) {
  }
}

export function galleryAlbumVisibleForceRefreshVisibleRange(host: GalleryAlbumVisibleLoadHost): boolean {
  if (galleryAlbumVisibleRefreshVisibleRangeIfAvailable(host)) {
    return true;
  }
  galleryAlbumVisibleNudgeListScrollForScrollIndexRefresh(host);
  return false;
}

export function galleryAlbumVisibleFlushPendingFlowRebuild(host: GalleryAlbumVisibleLoadHost): void {
  if (!host.pendingFlowRebuild) {
    return;
  }
  if (host.timelineSidebarDragging || host.isDraggingOrFling) {
    return;
  }
  host.pendingFlowRebuild = false;
  host.rebuildFlow();
  host.flowDataSource.notifyDataReload();
  galleryAlbumVisibleForceRefreshVisibleRange(host);
  setTimeout((): void => {
    if (host.visualPlaceholderMode || host.isDraggingOrFling) {
      return;
    }
    host.lastLoadVisibleAtMs = 0;
    galleryAlbumVisibleLoadVisibleItemsThrottled(host, true, false);
  }, 16);
}

export function galleryAlbumVisibleAlignPumpToTimelineSliderTarget(host: GalleryAlbumVisibleLoadHost): boolean {
  const ym = host.resolveYearMonthByTimelineRatio(host.timelineSliderRatio);
  if (ym === null || host.orderedDays.length === 0) {
    return false;
  }
  const range = findTimelineMonthRange(host.orderedDays, ym.year, ym.month);
  if (range === null) {
    return false;
  }
  const lo = range.startIndex;
  const hi = range.endIndex;
  host.dayIndex = lo;
  host.lastVisibleLoadDayIdx = lo;
  const d0 = host.orderedDays[lo];
  const k0 = dayKey(d0.year, d0.month, d0.day);
  host.dayOffsets.set(k0, 0);
  const gStart = galleryAlbumVisibleGlobalSlotIndexAtDayStart(host, lo);
  const dLast = host.orderedDays[hi];
  const gEndExclusive = galleryAlbumVisibleGlobalSlotIndexAtDayStart(host, hi) + Math.max(0, dLast.itemCount);
  host.lastKnownGlobalPhotoSlotStart = gStart;
  host.lastKnownGlobalPhotoSlotEndExclusive = Math.max(gStart + 1, gEndExclusive);
  return true;
}

export function galleryAlbumVisiblePrimeRoughVisibleRangeForTimelineTarget(
  host: GalleryAlbumVisibleLoadHost
): GalleryVisibleNodeRange | null {
  const ym = host.resolveYearMonthByTimelineRatio(host.timelineSliderRatio);
  if (ym === null) {
    return null;
  }
  const range = findFlowRoughVisibleRangeForYearMonth(host.flowDataSource, ym.year, ym.month);
  if (range === null) {
    return null;
  }
  host.listVisibleFirstNodeIdx = range.first;
  host.listVisibleLastNodeIdx = range.last;
  galleryAlbumVisibleRefreshLastKnownGlobalSlotsFromListIndices(host, range.first, range.last);
  galleryAlbumVisibleCaptureListScrollIndexAnchor(host);
  return range;
}

export function galleryAlbumVisibleCountPhotoSlotsBeforeNode(
  host: GalleryAlbumVisibleLoadHost,
  nodeIdx: number
): number {
  const totalNodes = host.flowDataSource.totalCount();
  const end = Math.max(0, Math.min(totalNodes, nodeIdx));
  let acc = 0;
  for (let i = 0; i < end; i++) {
    const n = host.flowDataSource.getData(i);
    if (n.kind === 'row') {
      acc += n.rowSlotItems.length;
    }
  }
  return acc;
}

export function galleryAlbumVisibleGlobalSlotIndexAtDayStart(
  host: GalleryAlbumVisibleLoadHost,
  dayIdx: number
): number {
  let acc = 0;
  const lim = Math.max(0, Math.min(dayIdx, host.orderedDays.length));
  for (let i = 0; i < lim; i++) {
    acc += Math.max(0, host.orderedDays[i].itemCount);
  }
  return acc;
}

export function galleryAlbumVisibleFindSectionForDayIndex(
  host: GalleryAlbumVisibleLoadHost,
  dayIdx: number
): GalleryAlbumDaySectionState | null {
  if (dayIdx < 0 || dayIdx >= host.orderedDays.length) {
    return null;
  }
  const day = host.orderedDays[dayIdx];
  for (let i = 0; i < host.sections.length; i++) {
    const section = host.sections[i];
    if (section.year === day.year && section.month === day.month && section.day === day.day) {
      return section;
    }
  }
  return null;
}

export function galleryAlbumVisibleFindEarliestMissingDayOffsetInRange(
  host: GalleryAlbumVisibleLoadHost,
  dayIdx: number,
  startOffsetInclusive: number,
  endOffsetExclusive: number
): number {
  if (dayIdx < 0 || dayIdx >= host.orderedDays.length) {
    return -1;
  }
  const total = Math.max(0, host.orderedDays[dayIdx].itemCount);
  if (total <= 0) {
    return -1;
  }
  const start = Math.max(0, Math.min(total - 1, startOffsetInclusive));
  const end = Math.max(start + 1, Math.min(total, endOffsetExclusive));
  const section = galleryAlbumVisibleFindSectionForDayIndex(host, dayIdx);
  if (section === null) {
    return start;
  }
  for (let off = start; off < end; off++) {
    if (section.slotByOffset.get(off) === undefined) {
      return off;
    }
  }
  return -1;
}

export function galleryAlbumVisibleAlignDayOffsetToLoadedGap(
  host: GalleryAlbumVisibleLoadHost,
  dayIdx: number,
  neededStartOffsetInclusive: number,
  neededEndOffsetExclusive: number
): number {
  if (dayIdx < 0 || dayIdx >= host.orderedDays.length) {
    return 0;
  }
  const day = host.orderedDays[dayIdx];
  const total = Math.max(0, day.itemCount);
  if (total <= 0) {
    return 0;
  }
  const start = Math.max(0, Math.min(total - 1, neededStartOffsetInclusive));
  const end = Math.max(start + 1, Math.min(total, neededEndOffsetExclusive));
  const key = dayKey(day.year, day.month, day.day);
  const current = Math.max(0, Math.min(total, host.dayOffsets.get(key) ?? 0));
  if (start > current) {
    host.dayOffsets.set(key, start);
    return start;
  }
  if (start < current) {
    const rewind = galleryAlbumVisibleFindEarliestMissingDayOffsetInRange(host, dayIdx, start, Math.min(current, end));
    if (rewind >= 0 && rewind < current) {
      host.dayOffsets.set(key, rewind);
      return rewind;
    }
  }
  return current;
}

export function galleryAlbumVisibleRefreshLastKnownGlobalSlotsFromListIndices(
  host: GalleryAlbumVisibleLoadHost,
  firstIdx: number,
  lastIdx: number
): void {
  const totalNodes = host.flowDataSource.totalCount();
  if (totalNodes <= 0) {
    return;
  }
  const first = Math.max(0, Math.min(totalNodes - 1, firstIdx));
  const last = Math.max(first, Math.min(totalNodes - 1, lastIdx));
  let visStart = galleryAlbumVisibleCountPhotoSlotsBeforeNode(host, first);
  let visEndExclusive = galleryAlbumVisibleCountPhotoSlotsBeforeNode(host, last + 1);
  if (visEndExclusive <= visStart) {
    let rowIdx = -1;
    for (let i = first; i <= last; i++) {
      const n = host.flowDataSource.getData(i);
      if (n.kind === 'row') {
        rowIdx = i;
        break;
      }
    }
    if (rowIdx < 0) {
      for (let i = first; i < totalNodes; i++) {
        const n = host.flowDataSource.getData(i);
        if (n.kind === 'row') {
          rowIdx = i;
          break;
        }
      }
    }
    if (rowIdx >= 0) {
      visStart = galleryAlbumVisibleCountPhotoSlotsBeforeNode(host, rowIdx);
      visEndExclusive = Math.max(visStart + 1, galleryAlbumVisibleCountPhotoSlotsBeforeNode(host, rowIdx + 1));
    }
  }
  if (visEndExclusive > visStart) {
    const newSpan = visEndExclusive - visStart;
    const prevStart = host.lastKnownGlobalPhotoSlotStart;
    const prevEnd = host.lastKnownGlobalPhotoSlotEndExclusive;
    const prevSpan = prevEnd - prevStart;
    if (prevSpan >= GALLERY_LAST_KNOWN_MIN_PREV_SLOT_SPAN &&
      newSpan < GALLERY_LAST_KNOWN_DEGENERATE_NEW_SLOT_SPAN &&
      newSpan * GALLERY_LAST_KNOWN_SHRINK_IGNORE_RATIO < prevSpan) {
      return;
    }
    host.lastKnownGlobalPhotoSlotStart = visStart;
    host.lastKnownGlobalPhotoSlotEndExclusive = visEndExclusive;
  }
}

export function galleryAlbumVisibleCaptureListScrollIndexAnchor(host: GalleryAlbumVisibleLoadHost): void {
  try {
    const off = host.scrollerRef.currentOffset();
    const yRaw = off.yOffset;
    const y = typeof yRaw === 'number' && Number.isFinite(yRaw) ? Math.max(0, yRaw) : 0;
    host.listScrollIndexAnchorYVp = y;
    host.listScrollIndexAnchorFirst = Math.max(0, host.listVisibleFirstNodeIdx);
    host.listScrollIndexAnchorHave = true;
  } catch (_e) {
    host.listScrollIndexAnchorHave = false;
  }
}

export function galleryAlbumVisibleApproxGalleryFlowListNodeHeightVp(node: GalleryFlowNode): number {
  if (node.kind === 'month') {
    return GALLERY_LIST_APPROX_MONTH_NODE_VP;
  }
  if (node.kind === 'day') {
    return GALLERY_LIST_APPROX_DAY_NODE_VP;
  }
  return GALLERY_LIST_APPROX_ROW_NODE_VP;
}

export function galleryAlbumVisibleEstimateFirstVisibleNodeIndexFromScrollY(
  host: GalleryAlbumVisibleLoadHost,
  yVp: number,
  total: number
): number {
  if (total <= 0 || !Number.isFinite(yVp) || yVp <= 0.5) {
    return 0;
  }
  const minByOffset = Math.ceil(yVp / 16) + 8000;
  const maxWalk = Math.min(total, GALLERY_SCROLL_Y_ESTIMATE_MAX_NODES, Math.max(16000, minByOffset));
  let cum = 0;
  for (let i = 0; i < maxWalk; i++) {
    const step = Math.max(1, galleryAlbumVisibleApproxGalleryFlowListNodeHeightVp(host.flowDataSource.getData(i)));
    if (cum + step > yVp) {
      return i;
    }
    cum += step;
  }
  if (cum <= yVp) {
    if (maxWalk < total) {
      const remain = yVp - cum;
      const guess = Math.max(1, GALLERY_LIST_APPROX_ROW_NODE_VP);
      const extra = Math.min(total - 1 - maxWalk, Math.max(0, Math.ceil(remain / guess)));
      return Math.min(total - 1, maxWalk + extra);
    }
    return total - 1;
  }
  return Math.max(0, maxWalk - 1);
}

export function galleryAlbumVisibleConsumeVerticalScrollDeltaAsNodeIndex(
  host: GalleryAlbumVisibleLoadHost,
  startIdx: number,
  deltaVp: number
): number {
  const total = host.flowDataSource.totalCount();
  if (total <= 0 || deltaVp <= 0.5) {
    return Math.max(0, Math.min(Math.max(0, total - 1), startIdx));
  }
  let i = Math.max(0, Math.min(total - 1, startIdx));
  let budget = deltaVp;
  let it = 0;
  while (i < total - 1 && budget > 0.5) {
    it++;
    if (it > GALLERY_SCROLL_DELTA_CONSUME_MAX_IT) {
      const guess = GALLERY_LIST_APPROX_ROW_NODE_VP;
      const extra = Math.min(total - 1 - i, Math.max(0, Math.ceil(budget / guess)));
      i += extra;
      break;
    }
    const h = galleryAlbumVisibleApproxGalleryFlowListNodeHeightVp(host.flowDataSource.getData(i));
    const step = Math.max(1, h);
    if (budget <= step) {
      break;
    }
    budget -= step;
    i++;
  }
  return Math.min(total - 1, i);
}

export function galleryAlbumVisibleConsumeVerticalScrollDeltaAsNodeIndexBackward(
  host: GalleryAlbumVisibleLoadHost,
  startIdx: number,
  deltaVp: number
): number {
  const total = host.flowDataSource.totalCount();
  if (total <= 0 || deltaVp <= 0.5) {
    return Math.max(0, Math.min(Math.max(0, total - 1), startIdx));
  }
  let i = Math.max(0, Math.min(total - 1, startIdx));
  let budget = deltaVp;
  let it = 0;
  while (i > 0 && budget > 0.5) {
    it++;
    if (it > GALLERY_SCROLL_DELTA_CONSUME_MAX_IT) {
      const guess = GALLERY_LIST_APPROX_ROW_NODE_VP;
      const extra = Math.min(i, Math.max(0, Math.ceil(budget / guess)));
      i -= extra;
      break;
    }
    const h = galleryAlbumVisibleApproxGalleryFlowListNodeHeightVp(host.flowDataSource.getData(i - 1));
    const step = Math.max(1, h);
    if (budget <= step) {
      break;
    }
    budget -= step;
    i--;
  }
  return Math.max(0, i);
}

export function galleryAlbumVisibleRefineVisibleNodeIndicesAgainstScrollLag(
  host: GalleryAlbumVisibleLoadHost,
  claimedFirst: number,
  claimedLast: number
): GalleryVisibleNodeRange {
  const totalNodes = host.flowDataSource.totalCount();
  if (totalNodes <= 0) {
    return { first: 0, last: 0 };
  }
  const cf = Math.max(0, Math.min(totalNodes - 1, claimedFirst));
  const cl = Math.max(cf, Math.min(totalNodes - 1, claimedLast));

  let yNow = 0;
  try {
    const off = host.scrollerRef.currentOffset();
    const yRaw = off.yOffset;
    yNow = typeof yRaw === 'number' && Number.isFinite(yRaw) ? Math.max(0, yRaw) : 0;
  } catch (_e) {
    yNow = 0;
  }
  const estFromY = galleryAlbumVisibleEstimateFirstVisibleNodeIndexFromScrollY(host, yNow, totalNodes);

  if (host.listScrollIndexAnchorHave) {
    const angDr = Math.abs(host.listScrollIndexAnchorFirst - estFromY);
    if (angDr > GALLERY_REFINE_ANCHOR_RESYNC_NODE_DRIFT) {
      host.listScrollIndexAnchorYVp = yNow;
      host.listScrollIndexAnchorFirst = Math.max(0, Math.min(totalNodes - 1, estFromY));
    }
  }

  if (!host.listScrollIndexAnchorHave) {
    const drift = Math.abs(cf - estFromY);
    const driftTh = Math.max(3500, Math.min(12000, Math.floor(totalNodes / 4)));
    const first0 = drift > driftTh ? estFromY : Math.max(cf, estFromY);
    const span0 = Math.max(Math.max(0, cl - cf), GALLERY_REFINE_MIN_VISIBLE_NODE_SPAN);
    const last0 = Math.min(totalNodes - 1, Math.max(cl, first0 + span0));
    return { first: Math.min(totalNodes - 1, first0), last: Math.max(first0, last0) };
  }

  const deltaRaw = yNow - host.listScrollIndexAnchorYVp;
  if (Math.abs(deltaRaw) <= 8) {
    const span0 = Math.max(Math.max(0, cl - cf), GALLERY_REFINE_MIN_VISIBLE_NODE_SPAN);
    let first0: number;
    if (Math.abs(deltaRaw) <= 1.0) {
      const driftCe = Math.abs(cf - estFromY);
      first0 = driftCe > GALLERY_REFINE_EST_ADV_MAX_DRIFT_NODES ? estFromY : cf;
    } else if (deltaRaw < 0) {
      first0 = Math.min(cf, estFromY);
    } else {
      first0 = Math.max(cf, estFromY);
    }
    const last0 = Math.min(totalNodes - 1, Math.max(cl, first0 + span0));
    return { first: Math.min(totalNodes - 1, first0), last: Math.max(first0, last0) };
  }
  const span = Math.max(Math.max(0, cl - cf), GALLERY_REFINE_MIN_VISIBLE_NODE_SPAN);
  let first2: number;
  if (deltaRaw > 1) {
    const adv = galleryAlbumVisibleConsumeVerticalScrollDeltaAsNodeIndex(host, host.listScrollIndexAnchorFirst, deltaRaw);
    const advC = Math.min(totalNodes - 1, Math.max(0, adv));
    const estUse =
      Math.abs(estFromY - advC) > GALLERY_REFINE_EST_ADV_MAX_DRIFT_NODES ? advC : estFromY;
    first2 = Math.max(cf, advC, estUse);
  } else {
    const adv = galleryAlbumVisibleConsumeVerticalScrollDeltaAsNodeIndexBackward(
      host,
      host.listScrollIndexAnchorFirst,
      -deltaRaw
    );
    const advC = Math.min(totalNodes - 1, Math.max(0, adv));
    const estUse =
      Math.abs(estFromY - advC) > GALLERY_REFINE_EST_ADV_MAX_DRIFT_NODES ? advC : estFromY;
    first2 = Math.max(0, Math.min(cf, advC, estUse));
  }
  const last2 = Math.min(totalNodes - 1, Math.max(cl, first2 + span));
  return { first: first2, last: Math.max(first2, last2) };
}

export function galleryAlbumVisibleCountSkeletonPhotoSlotsInFlowNodeRange(
  host: GalleryAlbumVisibleLoadHost,
  first: number,
  last: number
): number {
  const total = host.flowDataSource.totalCount();
  if (total <= 0) {
    return 0;
  }
  const f = Math.max(0, Math.min(total - 1, first));
  const l = Math.max(f, Math.min(total - 1, last));
  let c = 0;
  for (let i = f; i <= l; i++) {
    const n = host.flowDataSource.getData(i);
    if (n.kind !== 'row') {
      continue;
    }
    for (let k = 0; k < n.rowSlotItems.length; k++) {
      const s = n.rowSlotItems[k];
      if (s === null || s === undefined) {
        c++;
      }
    }
  }
  return c;
}

export function galleryAlbumVisibleComputeLoadVisibleBufferAfterSlots(
  host: GalleryAlbumVisibleLoadHost,
  aggressive: boolean,
  scanFirst: number,
  scanLast: number
): number {
  const sk = galleryAlbumVisibleCountSkeletonPhotoSlotsInFlowNodeRange(host, scanFirst, scanLast);
  const base = aggressive ? GALLERY_LOAD_VISIBLE_BUFFER_BASE_AGGRESSIVE : GALLERY_LOAD_VISIBLE_BUFFER_BASE_NON_AGGRESSIVE;
  const extra = Math.min(GALLERY_LOAD_VISIBLE_BUFFER_AFTER_CAP, sk * GALLERY_LOAD_VISIBLE_SKELETON_SLOT_MULTIPLIER);
  return Math.max(base, extra);
}

export function galleryAlbumVisibleLoadVisibleItemsThrottled(
  host: GalleryAlbumVisibleLoadHost,
  forceImmediate: boolean = false,
  aggressive: boolean = false,
  allowWhileInteracting: boolean = false
): void {
  galleryAlbumVisibleCancelScheduledRetry(host);
  const now = Date.now();
  const throttleWindowMs = allowWhileInteracting ? 96 : 300;
  if (!forceImmediate && now - host.lastLoadVisibleAtMs < throttleWindowMs) {
    if (host.isInScrollInteractiveLogWindow()) {
      host.logScrollDebug('loadVisible throttled');
    }
    return;
  }
  host.lastLoadVisibleAtMs = now;
  if (host.bootLoading || host.orderedDays.length === 0 || host.visualPlaceholderMode
    || (!allowWhileInteracting && host.isDraggingOrFling)) {
    if (GALLERY_SCROLL_DEBUG_LOG) {
      host.logScrollDebug(
        `loadVisible skip: boot=${host.bootLoading ? 1 : 0}, days=${host.orderedDays.length}, `
        + `placeholder=${host.visualPlaceholderMode ? 1 : 0}, dragFling=${host.isDraggingOrFling ? 1 : 0}, `
        + `allowInteractive=${allowWhileInteracting ? 1 : 0}`
      );
    }
    return;
  }
  const totalNodes = host.flowDataSource.totalCount();
  if (totalNodes <= 0) {
    return;
  }
  let loadVisibleUsedScrollerRange = false;
  if (galleryAlbumVisibleTryApplyScrollerVisibleRangeIfAvailable(host, totalNodes)) {
    loadVisibleUsedScrollerRange = true;
    galleryAlbumVisibleRefreshLastKnownGlobalSlotsFromListIndices(
      host,
      host.listVisibleFirstNodeIdx,
      host.listVisibleLastNodeIdx
    );
    galleryAlbumVisibleCaptureListScrollIndexAnchor(host);
  }
  if (allowWhileInteracting && !loadVisibleUsedScrollerRange) {
    if (host.isInScrollInteractiveLogWindow()) {
      host.logScrollDebug('loadVisible interactive skip: scroller visible range unavailable');
    }
    return;
  }
  let refFirst = Math.max(0, Math.min(totalNodes - 1, host.listVisibleFirstNodeIdx));
  let refLast = Math.max(refFirst, Math.min(totalNodes - 1, host.listVisibleLastNodeIdx));
  let visStart = 0;
  let visEndExclusive = 0;
  let aggressiveRoughVisibleRange: GalleryVisibleNodeRange | null = null;
  let usedAggressiveTimelineAnchor = false;
  if (aggressive && !loadVisibleUsedScrollerRange) {
    aggressiveRoughVisibleRange = galleryAlbumVisiblePrimeRoughVisibleRangeForTimelineTarget(host);
  }
  if (aggressiveRoughVisibleRange !== null) {
    refFirst = aggressiveRoughVisibleRange.first;
    refLast = aggressiveRoughVisibleRange.last;
    visStart = galleryAlbumVisibleCountPhotoSlotsBeforeNode(host, refFirst);
    visEndExclusive = galleryAlbumVisibleCountPhotoSlotsBeforeNode(host, refLast + 1);
    if (visEndExclusive <= visStart &&
      host.lastKnownGlobalPhotoSlotEndExclusive > host.lastKnownGlobalPhotoSlotStart) {
      visStart = host.lastKnownGlobalPhotoSlotStart;
      visEndExclusive = host.lastKnownGlobalPhotoSlotEndExclusive;
    }
  } else if (aggressive && galleryAlbumVisibleAlignPumpToTimelineSliderTarget(host)) {
    visStart = host.lastKnownGlobalPhotoSlotStart;
    visEndExclusive = host.lastKnownGlobalPhotoSlotEndExclusive;
    usedAggressiveTimelineAnchor = visEndExclusive > visStart;
  }
  if (!usedAggressiveTimelineAnchor) {
    let refinedFirst: number;
    let refinedLast: number;
    if (loadVisibleUsedScrollerRange) {
      refinedFirst = Math.max(0, Math.min(totalNodes - 1, host.listVisibleFirstNodeIdx));
      refinedLast = Math.max(refinedFirst, Math.min(totalNodes - 1, host.listVisibleLastNodeIdx));
    } else {
      const refined = galleryAlbumVisibleRefineVisibleNodeIndicesAgainstScrollLag(
        host,
        host.listVisibleFirstNodeIdx,
        host.listVisibleLastNodeIdx
      );
      refinedFirst = refined.first;
      refinedLast = refined.last;
    }
    const firstNode = Math.max(0, Math.min(totalNodes - 1, refinedFirst));
    const lastNode = Math.max(firstNode, Math.min(totalNodes - 1, refinedLast));
    refFirst = firstNode;
    refLast = lastNode;
    visStart = galleryAlbumVisibleCountPhotoSlotsBeforeNode(host, firstNode);
    visEndExclusive = galleryAlbumVisibleCountPhotoSlotsBeforeNode(host, lastNode + 1);
    if (visEndExclusive <= visStart) {
      if (host.lastKnownGlobalPhotoSlotEndExclusive > host.lastKnownGlobalPhotoSlotStart) {
        visStart = host.lastKnownGlobalPhotoSlotStart;
        visEndExclusive = host.lastKnownGlobalPhotoSlotEndExclusive;
      }
    }
    if (visEndExclusive <= visStart) {
      galleryAlbumVisibleRefreshLastKnownGlobalSlotsFromListIndices(host, refinedFirst, refinedLast);
      if (host.lastKnownGlobalPhotoSlotEndExclusive > host.lastKnownGlobalPhotoSlotStart) {
        visStart = host.lastKnownGlobalPhotoSlotStart;
        visEndExclusive = host.lastKnownGlobalPhotoSlotEndExclusive;
      }
    }
    if (visEndExclusive <= visStart) {
      if (aggressive && !host.exhausted) {
        if (host.loadingMore) {
          galleryAlbumVisibleScheduleRetryAfterInflight(host, true);
          return;
        }
        if (!galleryAlbumVisibleAlignPumpToTimelineSliderTarget(host)) {
          return;
        }
        const epoch = host.pumpEpoch;
        host.pumpLoad(true);
        setTimeout((): void => {
          if (epoch !== host.pumpEpoch || host.isDraggingOrFling || host.visualPlaceholderMode) {
            return;
          }
          host.pumpLoad(true);
        }, 40);
      }
      return;
    }
  }
  let bufferScanFirst = refFirst;
  let bufferScanLast = refLast;
  if (!usedAggressiveTimelineAnchor) {
    if (loadVisibleUsedScrollerRange) {
      bufferScanFirst = Math.max(0, refFirst - GALLERY_LOAD_VISIBLE_SCROLLER_RANGE_PAD_NODES);
      bufferScanLast = Math.min(totalNodes - 1, refLast + GALLERY_LOAD_VISIBLE_SCROLLER_RANGE_PAD_NODES);
      bufferScanLast = Math.max(bufferScanFirst, bufferScanLast);
    } else {
      let yVis = 0;
      try {
        const off2 = host.scrollerRef.currentOffset();
        const yRaw2 = off2.yOffset;
        yVis = typeof yRaw2 === 'number' && Number.isFinite(yRaw2) ? Math.max(0, yRaw2) : 0;
      } catch (_e2) {
        yVis = 0;
      }
      const estNode = galleryAlbumVisibleEstimateFirstVisibleNodeIndexFromScrollY(host, yVis, totalNodes);
      if (estNode < refFirst) {
        const visLo = galleryAlbumVisibleCountPhotoSlotsBeforeNode(host, estNode);
        if (visLo < visStart) {
          visStart = visLo;
        }
      }
      bufferScanFirst = Math.max(0, Math.min(refFirst, estNode));
      const winNodes = Math.max(GALLERY_LOAD_VISIBLE_BUFFER_SCAN_WIN_NODES, refLast - refFirst + 1);
      const estLastHint = Math.min(totalNodes - 1, Math.max(refLast, estNode + winNodes - 1));
      bufferScanLast = Math.min(totalNodes - 1, Math.max(refLast, estLastHint));
      bufferScanLast = Math.max(bufferScanFirst, bufferScanLast);
    }
  }
  const bufferSlots = galleryAlbumVisibleComputeLoadVisibleBufferAfterSlots(
    host,
    aggressive,
    bufferScanFirst,
    bufferScanLast
  );
  const start = aggressive ? Math.max(0, visStart) : Math.max(0, visStart - bufferSlots);
  const end = Math.max(start, visEndExclusive - 1 + bufferSlots);
  const startHit = host.resolveDayByGlobalIndex(start);
  if (startHit === null) {
    if (host.isInScrollInteractiveLogWindow()) {
      host.logScrollDebug(
        `loadVisible miss: start=${start}, end=${end}, listFirst=${host.listVisibleFirstNodeIdx}, `
        + `listLast=${host.listVisibleLastNodeIdx}, timelineAnchor=${usedAggressiveTimelineAnchor ? 1 : 0}`
      );
    }
    return;
  }
  const endHit = host.resolveDayByGlobalIndex(end);
  if (endHit === null) {
    return;
  }
  if (host.loadingMore) {
    if (host.isInScrollInteractiveLogWindow()) {
      host.logScrollDebug(
        `loadVisible defer while inflight: start=${start}, end=${end}, day=${startHit.dayIdx}, aggressive=${aggressive ? 1 : 0}`
      );
    }
    galleryAlbumVisibleScheduleRetryAfterInflight(host, aggressive);
    return;
  }
  if (startHit.dayIdx !== host.lastVisibleLoadDayIdx || startHit.dayIdx !== host.dayIndex) {
    const nextIdx = startHit.dayIdx;
    host.dayIndex = nextIdx;
    host.lastVisibleLoadDayIdx = nextIdx;
    if (host.isInScrollInteractiveLogWindow()) {
      host.logScrollDebug(`loadVisible jump dayIndex -> ${nextIdx} (target=${startHit.dayIdx}, start=${start}, end=${end})`);
    }
  }
  if (host.dayIndex >= 0 && host.dayIndex < host.orderedDays.length) {
    const d = host.orderedDays[host.dayIndex];
    const k = dayKey(d.year, d.month, d.day);
    const dayGlobalStart = galleryAlbumVisibleGlobalSlotIndexAtDayStart(host, host.dayIndex);
    const overlapEndExclusive = Math.max(
      startHit.dayOffset + 1,
      Math.min(Math.max(0, d.itemCount), Math.max(0, Math.min(end + 1, dayGlobalStart + Math.max(0, d.itemCount)) - dayGlobalStart))
    );
    const curOff = host.dayOffsets.get(k) ?? 0;
    const alignedStart = galleryAlbumVisibleAlignDayOffsetToLoadedGap(
      host,
      host.dayIndex,
      Math.max(0, startHit.dayOffset),
      overlapEndExclusive
    );
    if (curOff !== alignedStart && host.isInScrollInteractiveLogWindow()) {
      const action = alignedStart < curOff ? 'rewind' : 'align';
      host.logScrollDebug(
        `loadVisible ${action} day offset -> ${alignedStart} `
        + `(dayOffset=${startHit.dayOffset}, overlapEnd=${overlapEndExclusive})`
      );
    }
  }
  const loD = startHit.dayIdx;
  const hiD = endHit.dayIdx;
  const spanDays = hiD - loD;

  if (!host.exhausted) {
    if (host.isInScrollInteractiveLogWindow()) {
      host.logScrollDebug(
        `loadVisible trigger visible-band pump: `
        + `dayIndex=${host.dayIndex}, start=${start}, end=${end}, spanDays=${spanDays}`
      );
    }
    const epochBand = host.pumpEpoch;
    void galleryAlbumVisiblePumpVisibleDayBandAllChunks(host, loD, hiD, start, end, epochBand);
  }
}

export async function galleryAlbumVisiblePumpVisibleDayBandAllChunks(
  host: GalleryAlbumVisibleLoadHost,
  loD: number,
  hiD: number,
  startG: number,
  endG: number,
  epoch: number
): Promise<void> {
  let curLo = Math.max(0, loD);
  const hiCap = Math.max(curLo, Math.min(hiD, host.orderedDays.length - 1));
  while (curLo <= hiCap) {
    if (epoch !== host.pumpEpoch || host.exhausted || host.bootLoading) {
      return;
    }
    if (host.visualPlaceholderMode || host.isDraggingOrFling) {
      return;
    }
    const hiChunk = Math.min(hiCap, curLo + GALLERY_LOAD_VISIBLE_MULTI_DAY_CHAIN_MAX - 1);
    await galleryAlbumVisiblePumpVisibleDayBandSequential(host, curLo, hiChunk, startG, endG, epoch);
    curLo = hiChunk + 1;
  }
}

export async function galleryAlbumVisiblePumpVisibleDayBandSequential(
  host: GalleryAlbumVisibleLoadHost,
  loDayIdx: number,
  hiDayIdx: number,
  startG: number,
  endG: number,
  epoch: number
): Promise<void> {
  if (host.visualPlaceholderMode || host.isDraggingOrFling) {
    return;
  }
  const lo = Math.max(0, loDayIdx);
  const hi = Math.max(lo, Math.min(hiDayIdx, host.orderedDays.length - 1));
  for (let d = lo; d <= hi; d++) {
    if (epoch !== host.pumpEpoch || host.exhausted || host.bootLoading) {
      return;
    }
    if (host.visualPlaceholderMode || host.isDraggingOrFling) {
      return;
    }
    let waitGuard = 0;
    while (host.loadingMore && waitGuard < 120) {
      await new Promise<void>((resolve) => setTimeout(resolve, 30));
      waitGuard++;
      if (epoch !== host.pumpEpoch) {
        return;
      }
    }
    if (host.loadingMore) {
      galleryAlbumVisibleScheduleRetryAfterInflight(host, true);
      return;
    }

    const day = host.orderedDays[d];
    const g0 = galleryAlbumVisibleGlobalSlotIndexAtDayStart(host, d);
    const g1 = g0 + Math.max(0, day.itemCount);
    if (endG < g0 || startG >= g1) {
      continue;
    }
    const overlapStart = Math.max(startG, g0);
    const localNeed = Math.min(Math.max(0, overlapStart - g0), Math.max(0, day.itemCount - 1));
    const overlapEndExclusive = Math.max(
      localNeed + 1,
      Math.min(Math.max(0, day.itemCount), Math.max(0, Math.min(endG + 1, g1) - g0))
    );
    const maxRoundsForRange = Math.max(1, Math.ceil(Math.max(1, overlapEndExclusive - localNeed) / DATE_FEED_BATCH) + 2);
    let rounds = 0;
    while (rounds < maxRoundsForRange) {
      const nextGap = galleryAlbumVisibleFindEarliestMissingDayOffsetInRange(host, d, localNeed, overlapEndExclusive);
      if (nextGap < 0) {
        break;
      }
      galleryAlbumVisibleAlignDayOffsetToLoadedGap(host, d, nextGap, overlapEndExclusive);
      const key = dayKey(day.year, day.month, day.day);
      const prevOffset = host.dayOffsets.get(key) ?? 0;

      host.dayIndex = d;
      host.lastVisibleLoadDayIdx = d;

      const gen = host.loadGen;
      host.loadingMore = true;
      let added = 0;
      try {
        added = await host.loadOneBatch();
      } finally {
        host.loadingMore = false;
      }

      if (epoch !== host.pumpEpoch || gen !== host.loadGen) {
        return;
      }
      if (added === -1) {
        return;
      }
      if (added === -2) {
        galleryAlbumVisibleScheduleRetryAfterInflight(host, true, 3000);
        return;
      }
      if (added === -3) {
        galleryAlbumVisibleScheduleRetryAfterInflight(host, true, 500);
        return;
      }

      rounds++;
      const nextGapAfter = galleryAlbumVisibleFindEarliestMissingDayOffsetInRange(host, d, localNeed, overlapEndExclusive);
      if (nextGapAfter < 0) {
        break;
      }
      const nextOffset = host.dayOffsets.get(key) ?? prevOffset;
      if (added <= 0 || nextOffset <= prevOffset) {
        galleryAlbumVisibleScheduleRetryAfterInflight(host, true, added > 0 ? PUMP_UI_GAP_MS : 48);
        return;
      }
      await new Promise<void>((resolve) => setTimeout(resolve, added > 0 ? PUMP_UI_GAP_MS : 2));
    }

    if (galleryAlbumVisibleFindEarliestMissingDayOffsetInRange(host, d, localNeed, overlapEndExclusive) >= 0) {
      galleryAlbumVisibleScheduleRetryAfterInflight(host, true, PUMP_UI_GAP_MS);
      return;
    }
  }
}

export function galleryAlbumVisibleLoadVisibleItems(host: GalleryAlbumVisibleLoadHost): void {
  galleryAlbumVisibleLoadVisibleItemsThrottled(host);
}

export function galleryAlbumVisibleLoadVisibleItemsImmediate(host: GalleryAlbumVisibleLoadHost): void {
  host.lastLoadVisibleAtMs = 0;
  galleryAlbumVisibleLoadVisibleItemsThrottled(host, true, true);
}
