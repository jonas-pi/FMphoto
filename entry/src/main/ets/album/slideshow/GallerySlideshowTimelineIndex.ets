import { GalleryTimelineData } from '../../model/FnApiTypes';
import {
  DayGlobalResolveResult,
  parseTimelineDayCells,
  sortDaysDesc,
  TimelineDayModel
} from '../galleryAlbumTab/GalleryAlbumTabTypes';

/** 时间轴上的全局序号索引：O(log n) 定位到「某日第几张」 */
export class GallerySlideshowTimelineIndex {
  days: TimelineDayModel[] = [];
  /** days[i] 在全局序列中的起始下标 */
  dayStarts: number[] = [];
  totalCount: number = 0;
}

/** 人物时间线常用 start_time 字符串，不能只认 year/month/day 数字字段 */
function parseFlexibleTimelineDays(raw: Object[]): TimelineDayModel[] {
  const numericRows: Array<Record<string, number | undefined>> = [];
  const extra: TimelineDayModel[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (typeof item !== 'object' || item === null) {
      continue;
    }
    const rec = item as Record<string, string | number | undefined>;
    const yy = rec['year'];
    const mm = rec['month'];
    const dd = rec['day'];
    if (typeof yy === 'number' && typeof mm === 'number' && typeof dd === 'number') {
      numericRows.push(item as Record<string, number | undefined>);
      continue;
    }
    const stRaw = rec['start_time'] ?? rec['startTime'];
    const st = stRaw !== undefined ? String(stRaw) : '';
    if (st.length < 10) {
      continue;
    }
    const space = st.indexOf(' ');
    const date = space > 0 ? st.substring(0, space) : st;
    const seg = date.split(':');
    if (seg.length < 3) {
      continue;
    }
    const y = Number(seg[0]);
    const m = Number(seg[1]);
    const d = Number(seg[2]);
    if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) {
      continue;
    }
    const cRaw = rec['itemCount'] ?? rec['item_count'] ?? rec['count'] ?? rec['total'] ?? rec['size'] ?? rec['num'];
    const c = cRaw !== undefined && Number.isFinite(Number(cRaw)) ? Math.max(0, Math.floor(Number(cRaw))) : 0;
    extra.push({ year: Math.floor(y), month: Math.floor(m), day: Math.floor(d), itemCount: c });
  }
  return sortDaysDesc(parseTimelineDayCells(numericRows).concat(extra));
}

export function buildGallerySlideshowTimelineIndex(timeline: GalleryTimelineData): GallerySlideshowTimelineIndex {
  const out = new GallerySlideshowTimelineIndex();
  const raw = timeline.list ?? [];
  const rows: Object[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (typeof item === 'object' && item !== null) {
      rows.push(item);
    }
  }
  out.days = parseFlexibleTimelineDays(rows).filter((day: TimelineDayModel): boolean => day.itemCount > 0);
  let acc = 0;
  for (let i = 0; i < out.days.length; i++) {
    out.dayStarts.push(acc);
    acc += out.days[i].itemCount;
  }
  out.totalCount = acc;
  return out;
}

export function locateSlideshowGlobalIndex(
  index: GallerySlideshowTimelineIndex,
  globalIdx: number
): DayGlobalResolveResult | null {
  if (globalIdx < 0 || globalIdx >= index.totalCount || index.days.length === 0) {
    return null;
  }
  let lo = 0;
  let hi = index.days.length - 1;
  while (lo <= hi) {
    const mid = Math.floor((lo + hi) / 2);
    const start = index.dayStarts[mid];
    const end = start + index.days[mid].itemCount;
    if (globalIdx < start) {
      hi = mid - 1;
    } else if (globalIdx >= end) {
      lo = mid + 1;
    } else {
      const out: DayGlobalResolveResult = { dayIdx: mid, dayOffset: globalIdx - start };
      return out;
    }
  }
  return null;
}
