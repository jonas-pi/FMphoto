/**
 * 按人物 ID 拉取时间线并分页合并照片列表，再跳转 CategoryGallery。
 * 与 PersonPage / GalleryAlbumTab / 预览页中的“打开人物媒体”逻辑保持一致。
 */
import { UIContext } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import { GalleryGetListData, GalleryListItem } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { CategoryGalleryNavStore } from './CategoryGalleryNavStore';

const DATE_FEED_BATCH = 50;
const DAY_MAX_ROUNDS = 300;
const PERSON_ALBUM_INITIAL_OPEN_ITEMS = 120;
const PERSON_ALBUM_BACKGROUND_APPEND_ITEMS = 100;
const PERSON_ALBUM_BACKGROUND_APPEND_DELAY_MS = 48;

interface TimelineDayModel {
  year: number;
  month: number;
  day: number;
  itemCount: number;
}

class PersonAlbumFetchCursor {
  dayIndex: number = 0;
  dayOffset: number = 0;
  loadedCount: number = 0;
}

class PersonAlbumChunkResult {
  items: GalleryListItem[] = [];
  done: boolean = false;
}

/** 打开结果：ok 为 true 时表示已发起 CategoryGallery 路由 */
export interface PersonAlbumOpenResult {
  ok: boolean;
  /** ok 为 false 时的用户可见说明；成功时为空串 */
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

/**
 * 解析人物时间线接口返回的 list（与 GalleryAlbumTab.parsePersonTimeline 对齐）。
 */
function parsePersonTimelineRows(rawList: Array<Record<string, string | number | undefined>>): TimelineDayModel[] {
  const out: TimelineDayModel[] = [];
  for (let i = 0; i < rawList.length; i++) {
    const x = rawList[i];
    let y = 0;
    let m = 0;
    let d = 0;
    const yy = x['year'];
    const mm = x['month'];
    const dd = x['day'];
    if (typeof yy === 'number' && typeof mm === 'number' && typeof dd === 'number') {
      y = Math.floor(yy);
      m = Math.floor(mm);
      d = Math.floor(dd);
    } else {
      const stRaw = x['start_time'] ?? x['startTime'];
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
      y = Number(seg[0]);
      m = Number(seg[1]);
      d = Number(seg[2]);
    }
    if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) {
      continue;
    }
    const cRaw =
      x['itemCount'] ?? x['item_count'] ?? x['count'] ?? x['total'] ?? x['size'] ?? x['num'];
    const c = cRaw !== undefined && Number.isFinite(Number(cRaw)) ? Math.max(0, Math.floor(Number(cRaw))) : 0;
    out.push({ year: Math.floor(y), month: Math.floor(m), day: Math.floor(d), itemCount: c });
  }
  return sortDaysDesc(out);
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function fetchPersonAlbumChunk(
  client: FnHttpClient,
  personId: string,
  days: TimelineDayModel[],
  cursor: PersonAlbumFetchCursor,
  targetItems: number,
  detailItemCount: number,
  shouldContinue?: () => boolean
): Promise<PersonAlbumChunkResult> {
  const out: GalleryListItem[] = [];
  let rounds = 0;
  while (cursor.dayIndex < days.length && rounds < DAY_MAX_ROUNDS) {
    if (shouldContinue !== undefined && !shouldContinue()) {
      const cancelled = new PersonAlbumChunkResult();
      cancelled.items = out;
      cancelled.done = true;
      return cancelled;
    }
    if (targetItems > 0 && out.length >= targetItems) {
      break;
    }
    if (detailItemCount > 0 && cursor.loadedCount + out.length >= detailItemCount) {
      break;
    }
    const day = days[cursor.dayIndex];
    const st = fmtDayStart(day.year, day.month, day.day);
    const et = fmtDayEnd(day.year, day.month, day.day);
    const one = await client.getAiPersonPhotoList(personId, st, et, DATE_FEED_BATCH, cursor.dayOffset, 20000);
    if (shouldContinue !== undefined && !shouldContinue()) {
      const cancelled = new PersonAlbumChunkResult();
      cancelled.items = out;
      cancelled.done = true;
      return cancelled;
    }
    if (!one.success || one.data === undefined) {
      const failed = new PersonAlbumChunkResult();
      failed.items = out;
      failed.done = true;
      return failed;
    }
    const list = listFromData(one.data);
    if (list.length === 0) {
      cursor.dayIndex++;
      cursor.dayOffset = 0;
      rounds++;
      continue;
    }
    for (let i = 0; i < list.length; i++) {
      out.push(list[i]);
    }
    cursor.dayOffset += list.length;
    cursor.loadedCount += list.length;
    rounds++;
    if (list.length < DATE_FEED_BATCH || (day.itemCount > 0 && cursor.dayOffset >= day.itemCount)) {
      cursor.dayIndex++;
      cursor.dayOffset = 0;
    }
  }
  const done =
    cursor.dayIndex >= days.length ||
    (detailItemCount > 0 && cursor.loadedCount >= detailItemCount) ||
    rounds >= DAY_MAX_ROUNDS;
  const result = new PersonAlbumChunkResult();
  result.items = out;
  result.done = done;
  return result;
}

async function continuePersonAlbumBackgroundLoad(
  personId: string,
  days: TimelineDayModel[],
  cursor: PersonAlbumFetchCursor,
  detailItemCount: number,
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
    const chunk = await fetchPersonAlbumChunk(
      client,
      personId,
      days,
      cursor,
      PERSON_ALBUM_BACKGROUND_APPEND_ITEMS,
      detailItemCount
    );
    if (chunk.items.length > 0) {
      CategoryGalleryNavStore.appendItems(token, chunk.items);
    }
    if (chunk.done || chunk.items.length === 0) {
      CategoryGalleryNavStore.setBackgroundLoading(token, false);
      return;
    }
    await sleep(PERSON_ALBUM_BACKGROUND_APPEND_DELAY_MS);
  }
}

/**
 * 按人物 ID 打开其图库媒体列表页（CategoryGallery）。
 */
export async function openPersonAlbumById(
  baseUrl: string,
  personId: string,
  initialTitle: string,
  uiCtx: UIContext,
  shouldContinue?: () => boolean
): Promise<PersonAlbumOpenResult> {
  if (personId.length === 0) {
    return { ok: false, errorMessage: '人物 ID 无效' };
  }
  const client = AppSession.getClient();
  if (client === null) {
    return { ok: false, errorMessage: '未登录' };
  }
  let title = initialTitle.length > 0 ? initialTitle : '未命名人物';
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { ok: false, errorMessage: '' };
  }
  const detail = await client.getAiPersonDetail(personId);
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { ok: false, errorMessage: '' };
  }
  let detailItemCount = 0;
  if (detail.success && detail.data !== undefined) {
    if (detail.data.name !== undefined && detail.data.name.length > 0) {
      title = detail.data.name;
    }
    const cntRaw = detail.data.itemCount;
    if (cntRaw !== undefined && Number.isFinite(Number(cntRaw))) {
      detailItemCount = Math.max(0, Math.floor(Number(cntRaw)));
    }
  }
  const tl = await client.getAiPersonPhotoTimeline(personId);
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { ok: false, errorMessage: '' };
  }
  if (!tl.success || tl.data === undefined) {
    return { ok: false, errorMessage: tl.message ?? '人物时间线加载失败' };
  }
  const raw = tl.data.list ?? [];
  const rawIn: Array<Record<string, string | number | undefined>> = [];
  for (let i = 0; i < raw.length; i++) {
    const el = raw[i];
    if (typeof el === 'object' && el !== null) {
      rawIn.push(el as Record<string, string | number | undefined>);
    }
  }
  const days = parsePersonTimelineRows(rawIn);
  const cursor = new PersonAlbumFetchCursor();
  const initialChunk = await fetchPersonAlbumChunk(
    client,
    personId,
    days,
    cursor,
    PERSON_ALBUM_INITIAL_OPEN_ITEMS,
    detailItemCount,
    shouldContinue
  );
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { ok: false, errorMessage: '' };
  }
  if (initialChunk.items.length === 0) {
    return { ok: false, errorMessage: '该人物暂无可预览媒体' };
  }
  const opened = await CategoryGalleryNavStore.open(baseUrl, title, initialChunk.items, uiCtx, false, {
    sourceKind: 'person',
    personId: personId,
    expectedTotalCount: detailItemCount
  });
  if (!opened) {
    return { ok: false, errorMessage: '打开人物媒体失败' };
  }
  if (!initialChunk.done) {
    const token = CategoryGalleryNavStore.currentToken();
    void continuePersonAlbumBackgroundLoad(personId, days, cursor, detailItemCount, token);
  }
  return { ok: true, errorMessage: '' };
}
