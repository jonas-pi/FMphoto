import { UIContext } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import { GalleryGetListData, GalleryListItem, GalleryTimelineData } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { CategoryGalleryNavStore } from './CategoryGalleryNavStore';
import { GALLERY_RECENT_DAY_MAX_ROUNDS } from './galleryAlbumTab/GalleryAlbumTabConstants';

const RECENT_ADDED_FETCH_PAGE_LIMIT = 32;

interface TimelineDayModel {
  year: number;
  month: number;
  day: number;
  itemCount: number;
}

export interface RecentAddedLoadResult {
  items: GalleryListItem[];
  errorMessage: string;
}

export interface RecentAddedOpenResult {
  ok: boolean;
  errorMessage: string;
}

function fmtDayStart(y: number, m: number, d: number): string {
  return `${y}:${m.toString().padStart(2, '0')}:${d.toString().padStart(2, '0')} 00:00:00`;
}

function fmtDayEnd(y: number, m: number, d: number): string {
  return `${y}:${m.toString().padStart(2, '0')}:${d.toString().padStart(2, '0')} 23:59:59`;
}

function sortDaysDesc(cells: TimelineDayModel[]): TimelineDayModel[] {
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

function listFromData(data: GalleryGetListData | undefined): GalleryListItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  const raw = data.list ?? data.items ?? data.photos ?? data.records;
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw as GalleryListItem[];
}

function parseRecentTimelineRows(rawList: Array<Record<string, string | number | undefined>>): TimelineDayModel[] {
  const out: TimelineDayModel[] = [];
  for (let i = 0; i < rawList.length; i++) {
    const row = rawList[i];
    const yearRaw = row['year'];
    const monthRaw = row['month'];
    const dayRaw = row['day'];
    const countRaw = row['itemCount'] ?? row['item_count'] ?? row['count'] ?? row['total'];
    const year = Number(yearRaw);
    const month = Number(monthRaw);
    const day = Number(dayRaw);
    if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
      continue;
    }
    const count = Number.isFinite(Number(countRaw)) ? Math.max(0, Math.floor(Number(countRaw))) : 0;
    out.push({
      year: Math.floor(year),
      month: Math.floor(month),
      day: Math.floor(day),
      itemCount: count
    });
  }
  return sortDaysDesc(out).filter((day: TimelineDayModel): boolean => day.itemCount > 0);
}

function dedupKeyForItem(
  item: GalleryListItem,
  fallbackPrefix: string,
  fallbackIndex: number,
  itemIdOf: (item: GalleryListItem) => string
): string {
  const norm = (value: string | number | undefined | null): string => {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value).trim();
  };
  const photoUUID = norm(item.photoUUID);
  if (photoUUID.length > 0) {
    return `uuid:${photoUUID}`;
  }
  const id = itemIdOf(item);
  if (id.length > 0) {
    return `id:${id}`;
  }
  const guid = norm(item.guid);
  if (guid.length > 0) {
    return `guid:${guid}`;
  }
  const path = norm(item.path);
  if (path.length > 0) {
    return `path:${path}`;
  }
  const originalUrl = norm(item.originalUrl);
  if (originalUrl.length > 0) {
    return `origin:${originalUrl}`;
  }
  return `${fallbackPrefix}_${fallbackIndex}`;
}

function collectRecentTimelineDays(timeline: GalleryTimelineData): TimelineDayModel[] {
  const raw = timeline.list ?? [];
  const rows: Array<Record<string, string | number | undefined>> = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (typeof item === 'object' && item !== null) {
      rows.push(item as Record<string, string | number | undefined>);
    }
  }
  return parseRecentTimelineRows(rows);
}

async function fetchRecentDayItems(
  client: FnHttpClient,
  day: TimelineDayModel,
  seen: Set<string>,
  itemIdOf: (item: GalleryListItem) => string,
  shouldContinue?: () => boolean
): Promise<RecentAddedLoadResult> {
  const st = fmtDayStart(day.year, day.month, day.day);
  const et = fmtDayEnd(day.year, day.month, day.day);
  const merged: GalleryListItem[] = [];
  let off = 0;
  let rounds = 0;
  for (;;) {
    if (shouldContinue !== undefined && !shouldContinue()) {
      return { items: merged, errorMessage: '' };
    }
    const one = await client.getRecentPhotos(st, et, RECENT_ADDED_FETCH_PAGE_LIMIT, off, 'recent');
    if (shouldContinue !== undefined && !shouldContinue()) {
      return { items: merged, errorMessage: '' };
    }
    if (!one.success || one.data === undefined) {
      return {
        items: [],
        errorMessage: one.message ?? '最近添加媒体加载失败'
      };
    }
    const list = listFromData(one.data);
    if (list.length <= 0) {
      break;
    }
    let pageAdded = 0;
    for (let i = 0; i < list.length; i++) {
      const item = list[i];
      const key = dedupKeyForItem(item, st, off + i, itemIdOf);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      merged.push(item);
      pageAdded++;
    }
    off += list.length;
    rounds++;
    if (pageAdded <= 0) {
      break;
    }
    if (rounds >= GALLERY_RECENT_DAY_MAX_ROUNDS) {
      break;
    }
  }
  return { items: merged, errorMessage: '' };
}

export async function loadAllRecentAddedItems(
  client: FnHttpClient,
  itemIdOf: (item: GalleryListItem) => string,
  shouldContinue?: () => boolean
): Promise<RecentAddedLoadResult> {
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { items: [], errorMessage: '' };
  }
  const timeline = await client.getRecentTimeline();
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { items: [], errorMessage: '' };
  }
  if (!timeline.success || timeline.data === undefined) {
    return {
      items: [],
      errorMessage: timeline.message ?? '最近添加时间轴加载失败'
    };
  }
  const days = collectRecentTimelineDays(timeline.data);
  if (days.length === 0) {
    return {
      items: [],
      errorMessage: '最近添加暂时无数据'
    };
  }

  const merged: GalleryListItem[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < days.length; i++) {
    if (shouldContinue !== undefined && !shouldContinue()) {
      return { items: [], errorMessage: '' };
    }
    const oneDay = await fetchRecentDayItems(client, days[i], seen, itemIdOf, shouldContinue);
    if (oneDay.errorMessage.length > 0) {
      return oneDay;
    }
    if (oneDay.items.length > 0) {
      for (let j = 0; j < oneDay.items.length; j++) {
        merged.push(oneDay.items[j]);
      }
    }
  }

  return {
    items: merged,
    errorMessage: merged.length > 0 ? '' : '最近添加暂无可预览媒体'
  };
}

export async function openRecentAddedGallery(
  baseUrl: string,
  uiCtx: UIContext,
  itemIdOf: (item: GalleryListItem) => string,
  shouldContinue?: () => boolean
): Promise<RecentAddedOpenResult> {
  const client = AppSession.getClient();
  if (client === null) {
    return { ok: false, errorMessage: '未登录' };
  }
  const result = await loadAllRecentAddedItems(client, itemIdOf, shouldContinue);
  if (result.items.length === 0) {
    return { ok: false, errorMessage: result.errorMessage };
  }
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { ok: false, errorMessage: '' };
  }
  const opened = await CategoryGalleryNavStore.open(baseUrl, '最近添加', result.items, uiCtx);
  if (!opened) {
    return { ok: false, errorMessage: '打开最近添加失败' };
  }
  return { ok: true, errorMessage: '' };
}
