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

export function buildGallerySlideshowTimelineIndex(timeline: GalleryTimelineData): GallerySlideshowTimelineIndex {
  const out = new GallerySlideshowTimelineIndex();
  const raw = timeline.list ?? [];
  const rows: Array<Record<string, number | undefined>> = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (typeof item === 'object' && item !== null) {
      rows.push(item as Record<string, number | undefined>);
    }
  }
  out.days = sortDaysDesc(parseTimelineDayCells(rows)).filter((day: TimelineDayModel): boolean => day.itemCount > 0);
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
