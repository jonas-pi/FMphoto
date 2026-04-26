import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { GalleryGetListData, GalleryListItem, GalleryTimelineData } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { CategoryGalleryNavStore } from './CategoryGalleryNavStore';
import { GALLERY_RECENT_DAY_MAX_ROUNDS } from './galleryAlbumTab/GalleryAlbumTabConstants';

const DOMAIN = 0xFF00;
const TAG = 'RecentAddedOpen';
const RECENT_ADDED_FETCH_PAGE_LIMIT = 32;
const RECENT_ADDED_INITIAL_OPEN_ITEMS = 96;
const RECENT_ADDED_BACKGROUND_APPEND_ITEMS = 96;
const RECENT_ADDED_BACKGROUND_APPEND_DELAY_MS = 48;

interface TimelineDayModel {
  year: number;
  month: number;
  day: number;
  itemCount: number;
}

class RecentAddedFetchCursor {
  dayIndex: number = 0;
  dayOffset: number = 0;
  loadedCount: number = 0;
}

class RecentAddedChunkResult {
  items: GalleryListItem[] = [];
  done: boolean = false;
  errorMessage: string = '';
}

class RecentAddedTimelineResult {
  days: TimelineDayModel[] = [];
  errorMessage: string = '';
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
    const year = Number(row['year']);
    const month = Number(row['month']);
    const day = Number(row['day']);
    const countRaw = row['itemCount'] ?? row['item_count'] ?? row['count'] ?? row['total'];
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

function appendUniqueItems(
  target: GalleryListItem[],
  seen: Set<string>,
  page: GalleryListItem[],
  fallbackPrefix: string,
  fallbackOffset: number,
  itemIdOf: (item: GalleryListItem) => string
): number {
  let added = 0;
  for (let i = 0; i < page.length; i++) {
    const item = page[i];
    const key = dedupKeyForItem(item, fallbackPrefix, fallbackOffset + i, itemIdOf);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    target.push(item);
    added++;
  }
  return added;
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, ms);
  });
}

function recentItemTimeOf(item: GalleryListItem | undefined): string {
  if (item === undefined) {
    return '';
  }
  return item.createdAt ?? item.dateTime ?? '';
}

function recentItemKeyOf(item: GalleryListItem | undefined, itemIdOf: (item: GalleryListItem) => string): string {
  if (item === undefined) {
    return '';
  }
  const id = itemIdOf(item);
  if (id.length > 0) {
    return id;
  }
  if (item.photoUUID !== undefined && String(item.photoUUID).trim().length > 0) {
    return String(item.photoUUID).trim();
  }
  if (item.path !== undefined && String(item.path).trim().length > 0) {
    return String(item.path).trim();
  }
  return '';
}

function logRecentPhotosPage(
  day: TimelineDayModel,
  requestOffset: number,
  list: GalleryListItem[],
  itemIdOf: (item: GalleryListItem) => string
): void {
  const firstItem = list.length > 0 ? list[0] : undefined;
  const lastItem = list.length > 0 ? list[list.length - 1] : undefined;
  hilog.warn(
    DOMAIN,
    TAG,
    'getRecentPhotos day=%{public}d-%{public}d-%{public}d offset=%{public}d listLen=%{public}d itemCount=%{public}d firstKey=%{public}s firstTime=%{public}s lastKey=%{public}s lastTime=%{public}s',
    day.year,
    day.month,
    day.day,
    requestOffset,
    list.length,
    day.itemCount,
    recentItemKeyOf(firstItem, itemIdOf),
    recentItemTimeOf(firstItem),
    recentItemKeyOf(lastItem, itemIdOf),
    recentItemTimeOf(lastItem)
  );
}

async function fetchRecentTimelineDays(
  client: FnHttpClient,
  shouldContinue?: () => boolean
): Promise<RecentAddedTimelineResult> {
  const out = new RecentAddedTimelineResult();
  if (shouldContinue !== undefined && !shouldContinue()) {
    return out;
  }
  const timeline = await client.getRecentTimeline();
  if (shouldContinue !== undefined && !shouldContinue()) {
    return out;
  }
  if (!timeline.success || timeline.data === undefined) {
    out.errorMessage = timeline.message ?? '最近添加时间轴加载失败';
    return out;
  }
  out.days = collectRecentTimelineDays(timeline.data);
  if (out.days.length === 0) {
    out.errorMessage = '最近添加暂无数据';
    return out;
  }
  return out;
}

async function fetchRecentAddedChunk(
  client: FnHttpClient,
  days: TimelineDayModel[],
  cursor: RecentAddedFetchCursor,
  targetItems: number,
  seen: Set<string>,
  itemIdOf: (item: GalleryListItem) => string,
  shouldContinue?: () => boolean
): Promise<RecentAddedChunkResult> {
  const out = new RecentAddedChunkResult();
  const startDayIndex = cursor.dayIndex;
  const startDayOffset = cursor.dayOffset;
  let rounds = 0;

  while (cursor.dayIndex < days.length && rounds < GALLERY_RECENT_DAY_MAX_ROUNDS) {
    if (shouldContinue !== undefined && !shouldContinue()) {
      out.done = true;
      return out;
    }
    if (targetItems > 0 && out.items.length >= targetItems) {
      break;
    }

    const day = days[cursor.dayIndex];
    const st = fmtDayStart(day.year, day.month, day.day);
    const et = fmtDayEnd(day.year, day.month, day.day);
    const requestOffset = cursor.dayOffset;

    const one = await client.getRecentPhotos(st, et, RECENT_ADDED_FETCH_PAGE_LIMIT, requestOffset, 'recent');

    if (shouldContinue !== undefined && !shouldContinue()) {
      out.done = true;
      return out;
    }
    if (!one.success || one.data === undefined) {
      hilog.warn(
        DOMAIN,
        TAG,
        'getRecentPhotos failed day=%{public}d-%{public}d-%{public}d offset=%{public}d msg=%{public}s',
        day.year,
        day.month,
        day.day,
        requestOffset,
        one.message ?? ''
      );
      out.done = true;
      out.errorMessage = one.message ?? '最近添加媒体加载失败';
      return out;
    }

    const list = listFromData(one.data);
    logRecentPhotosPage(day, requestOffset, list, itemIdOf);

    let reachedDayEnd = false;
    if (list.length > 0) {
      appendUniqueItems(out.items, seen, list, st, cursor.dayOffset, itemIdOf);
      cursor.dayOffset += list.length;
      cursor.loadedCount += list.length;
      reachedDayEnd = list.length < RECENT_ADDED_FETCH_PAGE_LIMIT;
    } else {
      reachedDayEnd = true;
    }

    if (!reachedDayEnd && day.itemCount > 0 && cursor.dayOffset >= day.itemCount) {
      reachedDayEnd = true;
    }

    rounds++;

    if (reachedDayEnd) {
      cursor.dayIndex++;
      cursor.dayOffset = 0;
    }
  }

  out.done =
    cursor.dayIndex >= days.length ||
    (cursor.dayIndex === startDayIndex && cursor.dayOffset === startDayOffset);

  return out;
}

async function continueRecentAddedBackgroundLoad(
  days: TimelineDayModel[],
  cursor: RecentAddedFetchCursor,
  seen: Set<string>,
  itemIdOf: (item: GalleryListItem) => string,
  token: number
): Promise<void> {
  const client = AppSession.getClient();
  if (client === null) {
    CategoryGalleryNavStore.setBackgroundLoading(token, false);
    return;
  }
  CategoryGalleryNavStore.setBackgroundLoading(token, true);
  for (;;) {
    if (token !== CategoryGalleryNavStore.currentToken()) {
      return;
    }
    const chunk = await fetchRecentAddedChunk(
      client,
      days,
      cursor,
      RECENT_ADDED_BACKGROUND_APPEND_ITEMS,
      seen,
      itemIdOf
    );
    if (token !== CategoryGalleryNavStore.currentToken()) {
      return;
    }
    if (chunk.items.length > 0) {
      CategoryGalleryNavStore.appendItems(token, chunk.items);
    }
    if (chunk.done || chunk.errorMessage.length > 0) {
      CategoryGalleryNavStore.setBackgroundLoading(token, false);
      return;
    }
    await sleep(RECENT_ADDED_BACKGROUND_APPEND_DELAY_MS);
  }
}

export async function loadAllRecentAddedItems(
  client: FnHttpClient,
  itemIdOf: (item: GalleryListItem) => string,
  shouldContinue?: () => boolean
): Promise<RecentAddedLoadResult> {
  const timelineResult = await fetchRecentTimelineDays(client, shouldContinue);
  if (timelineResult.errorMessage.length > 0 || timelineResult.days.length === 0) {
    return { items: [], errorMessage: timelineResult.errorMessage };
  }
  const cursor = new RecentAddedFetchCursor();
  const seen = new Set<string>();
  const merged: GalleryListItem[] = [];
  for (;;) {
    const chunk = await fetchRecentAddedChunk(
      client,
      timelineResult.days,
      cursor,
      0,
      seen,
      itemIdOf,
      shouldContinue
    );
    if (chunk.items.length > 0) {
      for (let i = 0; i < chunk.items.length; i++) {
        merged.push(chunk.items[i]);
      }
    }
    if (chunk.errorMessage.length > 0) {
      if (merged.length > 0) {
        return { items: merged, errorMessage: '' };
      }
      return { items: [], errorMessage: chunk.errorMessage };
    }
    if (chunk.done) {
      break;
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
  const timelineResult = await fetchRecentTimelineDays(client, shouldContinue);
  if (timelineResult.errorMessage.length > 0 || timelineResult.days.length === 0) {
    return { ok: false, errorMessage: timelineResult.errorMessage };
  }
  const cursor = new RecentAddedFetchCursor();
  const seen = new Set<string>();
  const initialChunk = await fetchRecentAddedChunk(
    client,
    timelineResult.days,
    cursor,
    RECENT_ADDED_INITIAL_OPEN_ITEMS,
    seen,
    itemIdOf,
    shouldContinue
  );
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { ok: false, errorMessage: '' };
  }
  if (initialChunk.items.length === 0) {
    return {
      ok: false,
      errorMessage: initialChunk.errorMessage.length > 0 ? initialChunk.errorMessage : '最近添加暂无可预览媒体'
    };
  }
  const opened = await CategoryGalleryNavStore.open(
    baseUrl,
    '最近添加',
    initialChunk.items,
    uiCtx,
    true,
    { columnsPerRow: 4 }
  );
  if (!opened) {
    return { ok: false, errorMessage: '打开最近添加失败' };
  }
  if (!initialChunk.done && initialChunk.errorMessage.length === 0) {
    const token = CategoryGalleryNavStore.currentToken();
    void continueRecentAddedBackgroundLoad(timelineResult.days, cursor, seen, itemIdOf, token);
  }
  return { ok: true, errorMessage: '' };
}
