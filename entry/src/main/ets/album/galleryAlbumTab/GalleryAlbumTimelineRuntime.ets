import {
  buildTimelineScrubPillLabel,
  collectTimelineYearMarkers,
  collectTimelineYearMonths,
  findFlowRoughVisibleRangeForYearMonth,
  findTimelineMonthRange,
  findFlowScrollIndexForYearMonth,
  getTimelineHighlightDay,
  getTimelineHighlightMonth,
  getTimelineHighlightYear,
  hasFlowVisibleYearMonth,
  resolveTimelineSliderSyncResult,
  resolveTimelineYearMonthByRatio,
  timelineIndicatorYForRatio
} from './GalleryAlbumTimelineLogic';
import {
  DayGlobalResolveResult,
  TimelineDayModel,
  TimelineYearMonth,
  TimelineYearMonthPair,
  YearMarker
} from './GalleryAlbumTabTypes';
import { TimelineGestureControllerHost } from './TimelineGestureController';

export function galleryAlbumGetTimelineYearMonths(host: TimelineGestureControllerHost): TimelineYearMonth[] {
  return collectTimelineYearMonths(host.orderedDays, host.sections);
}

export function galleryAlbumResolveYearMonthByTimelineRatio(
  host: TimelineGestureControllerHost,
  ratio: number
): TimelineYearMonthPair | null {
  return resolveTimelineYearMonthByRatio(galleryAlbumGetTimelineYearMonths(host), ratio);
}

export function galleryAlbumFlowHasVisibleYearMonth(
  host: TimelineGestureControllerHost,
  year: number,
  month: number
): boolean {
  return hasFlowVisibleYearMonth(host.flowDataSource, year, month);
}

export function galleryAlbumTryScrollListToYearMonthIfVisible(
  host: TimelineGestureControllerHost,
  year: number,
  month: number
): boolean {
  let idx = findFlowScrollIndexForYearMonth(host.flowDataSource, year, month);
  if (idx < 0) {
    const range = findFlowRoughVisibleRangeForYearMonth(host.flowDataSource, year, month);
    if (range !== null) {
      idx = range.first;
    }
  }
  if (idx < 0) {
    return false;
  }
  try {
    host.timelineSeekAnchorNodeIdx = idx;
    host.scrollerRef.scrollToIndex(host.listIndexFromFlowNodeIndex(idx), false, ScrollAlign.START);
    return true;
  } catch (_e) {
    return false;
  }
}

export function galleryAlbumSyncListVisibleRoughToTimelineSliderTarget(host: TimelineGestureControllerHost): void {
  const ym = galleryAlbumResolveYearMonthByTimelineRatio(host, host.timelineSliderRatio);
  if (ym === null) {
    return;
  }
  const monthRange = findTimelineMonthRange(host.orderedDays, ym.year, ym.month);
  if (monthRange !== null) {
    host.dayIndex = monthRange.startIndex;
  }
  const range = findFlowRoughVisibleRangeForYearMonth(host.flowDataSource, ym.year, ym.month);
  if (range === null) {
    return;
  }
  host.listVisibleFirstNodeIdx = range.first;
  host.listVisibleLastNodeIdx = range.last;
  host.refreshLastKnownGlobalSlotsFromListIndices(range.first, range.last);
  host.captureListScrollIndexAnchor();
}

export function galleryAlbumScrollListByRatioEstimate(host: TimelineGestureControllerHost, ratio: number): void {
  const total = host.flowDataSource.totalCount();
  if (total <= 0) {
    return;
  }
  const clamped = Math.max(0, Math.min(1, ratio));
  host.timelineSeekAnchorNodeIdx = Math.max(0, Math.min(total - 1, Math.floor(clamped * Math.max(0, total - 1))));
  if (clamped >= 0.995) {
    try {
      host.timelineSeekAnchorNodeIdx = total - 1;
      host.scrollerRef.scrollToIndex(host.listIndexFromFlowNodeIndex(total - 1), false, ScrollAlign.END);
    } catch (_e) {
    }
    return;
  }
  const estimatedTotalVp = total * 120;
  const y = Math.max(0, clamped * estimatedTotalVp);
  try {
    host.scrollerRef.scrollTo({ xOffset: 0, yOffset: y });
  } catch (_e) {
  }
}

export function galleryAlbumSeekTimelineListToDisplayRatio(
  host: TimelineGestureControllerHost,
  ratio: number
): void {
  const clamped = Math.max(0, Math.min(1, ratio));
  if (clamped >= 0.995) {
    galleryAlbumScrollListByRatioEstimate(host, clamped);
    return;
  }
  const ym = galleryAlbumResolveYearMonthByTimelineRatio(host, ratio);
  if (ym === null) {
    return;
  }
  if (galleryAlbumTryScrollListToYearMonthIfVisible(host, ym.year, ym.month)) {
    return;
  }
  galleryAlbumScrollListByRatioEstimate(host, ratio);
}

export function galleryAlbumStartTimelineSeekWatchdog(
  host: TimelineGestureControllerHost,
  targetYear: number,
  targetMonth: number
): void {
  host.timelineSeekGen++;
  const gen = host.timelineSeekGen;
  const started = Date.now();
  const tick = (): void => {
    if (gen !== host.timelineSeekGen) {
      return;
    }
    if (Date.now() - started > 60_000) {
      return;
    }
    if (galleryAlbumTryScrollListToYearMonthIfVisible(host, targetYear, targetMonth)) {
      return;
    }
    if (!host.loadingMore && !host.exhausted) {
      host.pumpLoad();
    }
    if (host.exhausted) {
      return;
    }
    setTimeout(tick, 120);
  };
  setTimeout(tick, 120);
}

export function galleryAlbumSyncTimelineSliderFromFirstIndex(
  host: TimelineGestureControllerHost,
  firstIdx: number
): void {
  const sync = resolveTimelineSliderSyncResult(
    host.flowDataSource,
    galleryAlbumGetTimelineYearMonths(host),
    firstIdx,
    host.timelineScrubTrackHeightVp,
    host.timelineSliderRatio,
    host.timelineSidebarHighlightIndex
  );
  if (sync === null) {
    return;
  }
  host.timelineSliderRatio = sync.ratio;
  host.timelineSidebarHighlightIndex = sync.highlightIndex;
  host.timelineIndicatorY = sync.indicatorY;
}

export function galleryAlbumGetCurrentHighlightYear(host: TimelineGestureControllerHost): number {
  return getTimelineHighlightYear(
    galleryAlbumGetTimelineYearMonths(host),
    host.timelineSidebarHighlightIndex,
    new Date().getFullYear()
  );
}

export function galleryAlbumGetCurrentHighlightMonth(host: TimelineGestureControllerHost): number {
  return getTimelineHighlightMonth(
    galleryAlbumGetTimelineYearMonths(host),
    host.timelineSidebarHighlightIndex,
    new Date().getMonth() + 1
  );
}

export function galleryAlbumGetCurrentHighlightDay(host: TimelineGestureControllerHost): number {
  return getTimelineHighlightDay(host.flowDataSource, host.listVisibleFirstNodeIdx, new Date().getDate());
}

export function galleryAlbumGetTimelineScrubPillLabel(host: TimelineGestureControllerHost): string {
  if (host.timelineSidebarDragging) {
    return `${galleryAlbumGetCurrentHighlightYear(host)}年${galleryAlbumGetCurrentHighlightMonth(host)}月`;
  }
  return buildTimelineScrubPillLabel(
    galleryAlbumGetCurrentHighlightYear(host),
    galleryAlbumGetCurrentHighlightMonth(host),
    galleryAlbumGetCurrentHighlightDay(host)
  );
}

export function galleryAlbumGetYearMarkersForTrack(host: TimelineGestureControllerHost): YearMarker[] {
  return collectTimelineYearMarkers(galleryAlbumGetTimelineYearMonths(host), host.timelineScrubTrackHeightVp);
}

export function galleryAlbumCalculateGlobalIndex(
  host: TimelineGestureControllerHost,
  day: TimelineDayModel,
  offsetInDay: number
): number {
  if (host.dayGlobalSlotStarts.length === host.orderedDays.length && host.orderedDays.length > 0) {
    for (let i = 0; i < host.orderedDays.length; i++) {
      const current = host.orderedDays[i];
      if (current.year === day.year && current.month === day.month && current.day === day.day) {
        return Math.max(0, host.dayGlobalSlotStarts[i]) + Math.max(0, offsetInDay);
      }
    }
  }
  let acc = 0;
  for (let i = 0; i < host.orderedDays.length; i++) {
    const current = host.orderedDays[i];
    if (current.year === day.year && current.month === day.month && current.day === day.day) {
      return acc + Math.max(0, offsetInDay);
    }
    acc += Math.max(0, current.itemCount);
  }
  return acc + Math.max(0, offsetInDay);
}

export function galleryAlbumResolveDayByGlobalIndex(
  host: TimelineGestureControllerHost,
  globalIndex: number
): DayGlobalResolveResult | null {
  if (host.orderedDays.length === 0) {
    return null;
  }
  const g = Math.max(0, globalIndex);
  if (host.dayGlobalSlotStarts.length === host.orderedDays.length && host.dayGlobalSlotStarts.length > 0) {
    let lo = 0;
    let hi = host.dayGlobalSlotStarts.length - 1;
    while (lo <= hi) {
      const mid = lo + Math.floor((hi - lo) / 2);
      const start = Math.max(0, host.dayGlobalSlotStarts[mid]);
      const nextStart = mid + 1 < host.dayGlobalSlotStarts.length
        ? Math.max(start, host.dayGlobalSlotStarts[mid + 1])
        : Number.MAX_SAFE_INTEGER;
      if (g < start) {
        hi = mid - 1;
        continue;
      }
      if (g >= nextStart) {
        lo = mid + 1;
        continue;
      }
      return { dayIdx: mid, dayOffset: Math.max(0, g - start) };
    }
  }
  let acc = 0;
  for (let i = 0; i < host.orderedDays.length; i++) {
    const count = Math.max(0, host.orderedDays[i].itemCount);
    if (g < acc + count) {
      return { dayIdx: i, dayOffset: g - acc };
    }
    acc += count;
  }
  const last = host.orderedDays.length - 1;
  return {
    dayIdx: last,
    dayOffset: Math.max(0, host.orderedDays[last].itemCount - 1)
  };
}

export function galleryAlbumTimelineIndicatorYForRatio(trackHeight: number, ratio: number): number {
  return timelineIndicatorYForRatio(trackHeight, ratio);
}
