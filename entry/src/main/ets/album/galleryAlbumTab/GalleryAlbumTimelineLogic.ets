import { GalleryWaterFlowDataSource } from '../GalleryFlowDataSource';
import {
  GALLERY_TIMELINE_INDICATOR_PAD_VP,
  GALLERY_TIMELINE_INDICATOR_RESERVED_VP
} from './GalleryAlbumTabConstants';
import {
  GalleryVisibleNodeRange,
  TimelineDayModel,
  TimelineYearMonth,
  TimelineYearMonthPair,
  YearMarker,
  ymKey
} from './GalleryAlbumTabTypes';

export interface TimelineYearMonthSource {
  year: number;
  month: number;
}

export interface TimelineMonthRange {
  startIndex: number;
  endIndex: number;
}

export interface TimelineSliderSyncResult {
  ratio: number;
  highlightIndex: number;
  indicatorY: number;
}

export function collectTimelineYearMonths(
  orderedDays: TimelineDayModel[],
  sections: TimelineYearMonthSource[]
): TimelineYearMonth[] {
  const out: TimelineYearMonth[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < orderedDays.length; i++) {
    const day = orderedDays[i];
    const key = ymKey(day.year, day.month);
    if (!seen.has(key)) {
      seen.add(key);
      out.push({ year: day.year, month: day.month, index: i });
    }
  }
  if (out.length === 0) {
    for (let i = 0; i < sections.length; i++) {
      const sec = sections[i];
      const key = ymKey(sec.year, sec.month);
      if (!seen.has(key)) {
        seen.add(key);
        out.push({ year: sec.year, month: sec.month, index: i });
      }
    }
  }
  return out;
}

export function resolveTimelineYearMonthByRatio(
  ymList: TimelineYearMonth[],
  ratio: number
): TimelineYearMonthPair | null {
  if (ymList.length === 0) {
    return null;
  }
  const clamped = Math.max(0, Math.min(1, ratio));
  const idx = Math.round(clamped * (ymList.length - 1));
  const cursor = Math.max(0, Math.min(ymList.length - 1, idx));
  return { year: ymList[cursor].year, month: ymList[cursor].month };
}

export function findTimelineMonthRange(
  orderedDays: TimelineDayModel[],
  year: number,
  month: number
): TimelineMonthRange | null {
  let startIndex = orderedDays.length;
  let endIndex = -1;
  for (let i = 0; i < orderedDays.length; i++) {
    const day = orderedDays[i];
    if (day.year === year && day.month === month) {
      if (i < startIndex) {
        startIndex = i;
      }
      if (i > endIndex) {
        endIndex = i;
      }
    }
  }
  if (startIndex > endIndex || startIndex < 0 || endIndex < 0) {
    return null;
  }
  return { startIndex, endIndex };
}

export function hasFlowVisibleYearMonth(
  flowDataSource: GalleryWaterFlowDataSource,
  year: number,
  month: number
): boolean {
  const total = flowDataSource.totalCount();
  for (let i = 0; i < total; i++) {
    const node = flowDataSource.getData(i);
    if ((node.kind === 'month' || node.kind === 'day') && node.year === year && node.month === month) {
      return true;
    }
  }
  return false;
}

export function findFlowScrollIndexForYearMonth(
  flowDataSource: GalleryWaterFlowDataSource,
  year: number,
  month: number
): number {
  const total = flowDataSource.totalCount();
  for (let i = 0; i < total; i++) {
    const node = flowDataSource.getData(i);
    if ((node.kind === 'month' || node.kind === 'day') && node.year === year && node.month === month) {
      return i;
    }
  }
  return -1;
}

export function findFlowRoughVisibleRangeForYearMonth(
  flowDataSource: GalleryWaterFlowDataSource,
  year: number,
  month: number
): GalleryVisibleNodeRange | null {
  const total = flowDataSource.totalCount();
  if (total <= 0) {
    return null;
  }
  let first = -1;
  for (let i = 0; i < total; i++) {
    const node = flowDataSource.getData(i);
    if (node.year === year && node.month === month && node.kind === 'row') {
      first = i;
      break;
    }
  }
  if (first < 0) {
    for (let i = 0; i < total; i++) {
      const node = flowDataSource.getData(i);
      if (node.year === year && node.month === month && (node.kind === 'month' || node.kind === 'day')) {
        first = i;
        break;
      }
    }
  }
  if (first < 0) {
    return null;
  }
  const last = Math.min(total - 1, Math.max(first, first + 56));
  return { first, last };
}

export function timelineIndicatorYForRatio(thRaw: number, ratio: number): number {
  const th = Math.max(thRaw, GALLERY_TIMELINE_INDICATOR_RESERVED_VP + 40);
  const span = Math.max(th - GALLERY_TIMELINE_INDICATOR_RESERVED_VP, 40);
  return GALLERY_TIMELINE_INDICATOR_PAD_VP + ratio * span;
}

export function resolveTimelineSliderSyncResult(
  flowDataSource: GalleryWaterFlowDataSource,
  ymList: TimelineYearMonth[],
  firstIdx: number,
  trackHeight: number,
  currentRatio: number,
  currentHighlightIndex: number
): TimelineSliderSyncResult | null {
  const total = flowDataSource.totalCount();
  if (ymList.length === 0 || total <= 0 || firstIdx < 0) {
    return null;
  }
  const clamped = Math.min(firstIdx, total - 1);
  let year = -1;
  let month = -1;
  for (let i = clamped; i >= 0; i--) {
    const node = flowDataSource.getData(i);
    if ((node.kind === 'month' || node.kind === 'day') && node.year > 0 && node.month > 0) {
      year = node.year;
      month = node.month;
      break;
    }
  }
  if (year < 0) {
    return null;
  }
  let highlightIndex = -1;
  for (let i = 0; i < ymList.length; i++) {
    if (ymList[i].year === year && ymList[i].month === month) {
      highlightIndex = i;
      break;
    }
  }
  if (highlightIndex < 0) {
    return null;
  }
  const ratio = ymList.length > 1 ? highlightIndex / (ymList.length - 1) : 0;
  if (Math.abs(ratio - currentRatio) < 0.01 && highlightIndex === currentHighlightIndex) {
    return null;
  }
  const height = Math.max(80, trackHeight);
  return {
    ratio,
    highlightIndex,
    indicatorY: timelineIndicatorYForRatio(height, ratio)
  };
}

function clampHighlightIndex(ymList: TimelineYearMonth[], highlightIndex: number): number {
  return Math.max(0, Math.min(ymList.length - 1, highlightIndex));
}

export function getTimelineHighlightYear(
  ymList: TimelineYearMonth[],
  highlightIndex: number,
  fallbackYear: number
): number {
  if (ymList.length === 0) {
    return fallbackYear;
  }
  return ymList[clampHighlightIndex(ymList, highlightIndex)].year;
}

export function getTimelineHighlightMonth(
  ymList: TimelineYearMonth[],
  highlightIndex: number,
  fallbackMonth: number
): number {
  if (ymList.length === 0) {
    return fallbackMonth;
  }
  return ymList[clampHighlightIndex(ymList, highlightIndex)].month;
}

export function getTimelineHighlightDay(
  flowDataSource: GalleryWaterFlowDataSource,
  firstVisibleNodeIdx: number,
  fallbackDay: number
): number {
  const total = flowDataSource.totalCount();
  if (total <= 0) {
    return fallbackDay;
  }
  const anchor = Math.max(0, Math.min(firstVisibleNodeIdx, total - 1));
  for (let i = anchor; i >= 0; i--) {
    const node = flowDataSource.getData(i);
    if (node.year > 0 && node.month > 0 && node.day > 0 && (node.kind === 'day' || node.kind === 'row')) {
      return node.day;
    }
  }
  return fallbackDay;
}

export function buildTimelineScrubPillLabel(year: number, month: number, day: number): string {
  return `${year}年${month}月${day}日`;
}

export function collectTimelineYearMarkers(
  ymList: TimelineYearMonth[],
  trackHeight: number
): YearMarker[] {
  if (ymList.length === 0 || trackHeight <= 0) {
    return [];
  }
  const out: YearMarker[] = [];
  const seen = new Set<number>();
  let lastY = -999;
  for (let i = 0; i < ymList.length; i++) {
    const year = ymList[i].year;
    if (seen.has(year)) {
      continue;
    }
    seen.add(year);
    const ratio = ymList.length > 1 ? i / (ymList.length - 1) : 0;
    const y = timelineIndicatorYForRatio(trackHeight, ratio);
    if (y - lastY >= 22) {
      out.push({ year, y });
      lastY = y;
    }
  }
  return out;
}
