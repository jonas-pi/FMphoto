import { GalleryGetListData, GalleryListItem } from '../../model/FnApiTypes';

export interface GalleryThumbHitRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface GalleryVisibleNodeRange {
  first: number;
  last: number;
}

export interface GalleryScrollerVisibleRange {
  start: number;
  end: number;
}

export interface GalleryScrollerMaybeVisibleRange {
  getVisibleRange?: () => GalleryScrollerVisibleRange | null;
}

export interface GalleryFingerWindowPoint {
  x: number;
  y: number;
}

export interface GalleryFingerCoordCompat {
  windowX?: number;
  windowY?: number;
  globalX?: number;
  globalY?: number;
  screenX?: number;
  screenY?: number;
  displayX?: number;
  displayY?: number;
  x?: number;
  y?: number;
}

export interface TimelineDayModel {
  year: number;
  month: number;
  day: number;
  itemCount: number;
}

export interface TimelineYearMonth {
  year: number;
  month: number;
  index: number;
}

export interface TimelineYearMonthPair {
  year: number;
  month: number;
}

export interface YearMarker {
  year: number;
  y: number;
}

export interface DayGlobalResolveResult {
  dayIdx: number;
  dayOffset: number;
}

export function fmtDayStart(y: number, m: number, d: number): string {
  return `${y}:${m.toString().padStart(2, '0')}:${d.toString().padStart(2, '0')} 00:00:00`;
}

export function fmtDayEnd(y: number, m: number, d: number): string {
  return `${y}:${m.toString().padStart(2, '0')}:${d.toString().padStart(2, '0')} 23:59:59`;
}

export function ymKey(y: number, m: number): string {
  return `${y}-${m}`;
}

export function dayKey(y: number, m: number, d: number): string {
  return `${y}-${m}-${d}`;
}

export function parseTimelineDayCells(raw: Array<Record<string, number | undefined>>): TimelineDayModel[] {
  const out: TimelineDayModel[] = [];
  for (let i = 0; i < raw.length; i++) {
    const x = raw[i];
    const year = x['year'];
    const month = x['month'];
    const day = x['day'];
    if (year === undefined || month === undefined || day === undefined) {
      continue;
    }
    const yi = Number(year);
    const mi = Number(month);
    const di = Number(day);
    if (!Number.isFinite(yi) || !Number.isFinite(mi) || !Number.isFinite(di)) {
      continue;
    }
    const itemCount = x['itemCount'];
    const itemCountSnake = x['item_count'];
    const ic = itemCount !== undefined ? itemCount : itemCountSnake;
    const cnt = ic !== undefined && Number.isFinite(Number(ic)) ? Math.max(0, Math.floor(Number(ic))) : 0;
    out.push({ year: Math.floor(yi), month: Math.floor(mi), day: Math.floor(di), itemCount: cnt });
  }
  return out;
}

export function sortDaysDesc(cells: TimelineDayModel[]): TimelineDayModel[] {
  return cells.slice().sort((a: TimelineDayModel, b: TimelineDayModel): number => {
    if (a.year !== b.year) {
      return b.year - a.year;
    }
    if (a.month !== b.month) {
      return b.month - a.month;
    }
    return b.day - a.day;
  });
}

export function listFromData(data: GalleryGetListData | undefined): GalleryListItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  const raw = data.list ?? data.items ?? data.photos ?? data.records;
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw as GalleryListItem[];
}

