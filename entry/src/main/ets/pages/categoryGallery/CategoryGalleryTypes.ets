import { GalleryListItem } from '../../model/FnApiTypes';

export interface RowModel {
  startIdx: number;
  c0: GalleryListItem;
  c1: GalleryListItem | undefined;
  c2: GalleryListItem | undefined;
}

export interface DayGroup {
  label: string;
  sortKey: string;
  rows: RowModel[];
  count: number;
}

export interface CgThumbHitRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface CgFingerWindowPoint {
  x: number;
  y: number;
}

export interface CgFingerCoordCompat {
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

export interface CategoryGalleryViewData {
  groups: DayGroup[];
  flatItems: GalleryListItem[];
  groupOffsets: number[];
}

function parseDateKey(dateTime: string | undefined): string {
  if (dateTime === undefined || dateTime.length === 0) {
    return '1970-01-01';
  }
  const spaceIdx = dateTime.indexOf(' ');
  const datePart = spaceIdx > 0 ? dateTime.substring(0, spaceIdx) : dateTime;
  const segs = datePart.split(':');
  if (segs.length < 3) {
    return '1970-01-01';
  }
  const y = segs[0].padStart(4, '0');
  const m = segs[1].padStart(2, '0');
  const d = segs[2].padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function formatDayLabel(sortKey: string): string {
  const parts = sortKey.split('-');
  if (parts.length < 3) {
    return sortKey;
  }
  return `${parts[0]}年${parseInt(parts[1], 10)}月${parseInt(parts[2], 10)}日`;
}

export function buildCategoryGalleryViewData(
  items: GalleryListItem[],
  useCreatedAt: boolean = false
): CategoryGalleryViewData {
  const keyOrder: string[] = [];
  const mapItems: Map<string, GalleryListItem[]> = new Map();

  for (let i = 0; i < items.length; i++) {
    const dt = useCreatedAt ? (items[i].createdAt ?? items[i].dateTime) : items[i].dateTime;
    const key = parseDateKey(dt);
    if (!mapItems.has(key)) {
      mapItems.set(key, []);
      keyOrder.push(key);
    }
    (mapItems.get(key) as GalleryListItem[]).push(items[i]);
  }

  keyOrder.sort((a: string, b: string): number => {
    if (a > b) {
      return -1;
    }
    if (a < b) {
      return 1;
    }
    return 0;
  });

  const groups: DayGroup[] = [];
  const flatItems: GalleryListItem[] = [];
  const groupOffsets: number[] = [];
  let offset = 0;

  for (let ki = 0; ki < keyOrder.length; ki++) {
    const key = keyOrder[ki];
    const dayItems = mapItems.get(key) as GalleryListItem[];
    const rows: RowModel[] = [];
    for (let ri = 0; ri < dayItems.length; ri += 3) {
      rows.push({
        startIdx: ri,
        c0: dayItems[ri],
        c1: ri + 1 < dayItems.length ? dayItems[ri + 1] : undefined,
        c2: ri + 2 < dayItems.length ? dayItems[ri + 2] : undefined,
      });
    }
    groups.push({
      label: formatDayLabel(key),
      sortKey: key,
      rows: rows,
      count: dayItems.length
    });
    groupOffsets.push(offset);
    offset += dayItems.length;
    for (let i = 0; i < dayItems.length; i++) {
      flatItems.push(dayItems[i]);
    }
  }

  return { groups, flatItems, groupOffsets };
}
