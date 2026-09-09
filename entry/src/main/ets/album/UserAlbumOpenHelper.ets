/**
 * 按用户相册 ID 拉取时间线并分页合并照片列表，再跳转 CategoryGallery。
 */
import { UIContext } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import { GalleryGetListData, GalleryListItem, GalleryTimelineData, UserAlbumItem } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { CategoryGalleryNavStore } from './CategoryGalleryNavStore';
import { userAlbumCount, userAlbumId, userAlbumIsBaby, userAlbumName } from './GalleryAlbumEntityData';
import { galleryListFromData } from './GalleryListItemNormalize';

const DATE_FEED_BATCH = 50;
const DAY_MAX_ROUNDS = 300;
const USER_ALBUM_INITIAL_OPEN_ITEMS = 120;
const USER_ALBUM_BACKGROUND_APPEND_ITEMS = 100;
const USER_ALBUM_BACKGROUND_APPEND_DELAY_MS = 48;
const USER_ALBUM_PHOTOS_MAX_ROUNDS = 80;

interface TimelineDayModel {
  year: number;
  month: number;
  day: number;
  itemCount: number;
}

class UserAlbumFetchCursor {
  dayIndex: number = 0;
  dayOffset: number = 0;
  loadedCount: number = 0;
  photosOffset: number = 0;
  useFlatPhotos: boolean = false;
}

class UserAlbumChunkResult {
  items: GalleryListItem[] = [];
  done: boolean = false;
}

export interface UserAlbumOpenResult {
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
  return galleryListFromData(data);
}

function parseAlbumTimelineRows(rawList: Array<Record<string, string | number | undefined>>): TimelineDayModel[] {
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

async function fetchUserAlbumChunk(
  client: FnHttpClient,
  albumId: string,
  isBaby: boolean,
  days: TimelineDayModel[],
  cursor: UserAlbumFetchCursor,
  targetItems: number,
  detailItemCount: number,
  shouldContinue?: () => boolean
): Promise<UserAlbumChunkResult> {
  const out: GalleryListItem[] = [];
  let rounds = 0;
  if (cursor.useFlatPhotos) {
    while (rounds < USER_ALBUM_PHOTOS_MAX_ROUNDS) {
      if (shouldContinue !== undefined && !shouldContinue()) {
        const cancelled = new UserAlbumChunkResult();
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
      const one = await client.getUserAlbumPhotos(albumId, cursor.photosOffset, DATE_FEED_BATCH, 20000);
      if (shouldContinue !== undefined && !shouldContinue()) {
        const cancelled = new UserAlbumChunkResult();
        cancelled.items = out;
        cancelled.done = true;
        return cancelled;
      }
      if (!one.success || one.data === undefined) {
        const failed = new UserAlbumChunkResult();
        failed.items = out;
        failed.done = true;
        return failed;
      }
      const list = listFromData(one.data);
      if (list.length === 0) {
        const done = new UserAlbumChunkResult();
        done.items = out;
        done.done = true;
        return done;
      }
      for (let i = 0; i < list.length; i++) {
        out.push(list[i]);
      }
      cursor.photosOffset += list.length;
      cursor.loadedCount += list.length;
      rounds++;
      if (list.length < DATE_FEED_BATCH) {
        const done = new UserAlbumChunkResult();
        done.items = out;
        done.done = true;
        return done;
      }
    }
    const result = new UserAlbumChunkResult();
    result.items = out;
    result.done = rounds >= USER_ALBUM_PHOTOS_MAX_ROUNDS ||
      (detailItemCount > 0 && cursor.loadedCount >= detailItemCount);
    return result;
  }

  while (cursor.dayIndex < days.length && rounds < DAY_MAX_ROUNDS) {
    if (shouldContinue !== undefined && !shouldContinue()) {
      const cancelled = new UserAlbumChunkResult();
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
    const one = await client.getUserAlbumPhotoList(
      albumId,
      isBaby,
      st,
      et,
      DATE_FEED_BATCH,
      cursor.dayOffset,
      20000
    );
    if (shouldContinue !== undefined && !shouldContinue()) {
      const cancelled = new UserAlbumChunkResult();
      cancelled.items = out;
      cancelled.done = true;
      return cancelled;
    }
    if (!one.success || one.data === undefined) {
      const failed = new UserAlbumChunkResult();
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
  const result = new UserAlbumChunkResult();
  result.items = out;
  result.done = done;
  return result;
}

async function continueUserAlbumBackgroundLoad(
  albumId: string,
  isBaby: boolean,
  days: TimelineDayModel[],
  cursor: UserAlbumFetchCursor,
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
    const chunk = await fetchUserAlbumChunk(
      client,
      albumId,
      isBaby,
      days,
      cursor,
      USER_ALBUM_BACKGROUND_APPEND_ITEMS,
      detailItemCount
    );
    if (chunk.items.length > 0) {
      CategoryGalleryNavStore.appendItems(token, chunk.items);
    }
    if (chunk.done || chunk.items.length === 0) {
      CategoryGalleryNavStore.setBackgroundLoading(token, false);
      return;
    }
    await sleep(USER_ALBUM_BACKGROUND_APPEND_DELAY_MS);
  }
}

function timelineRowsFromData(data: GalleryTimelineData | undefined): TimelineDayModel[] {
  if (data === undefined || data === null) {
    return [];
  }
  const raw = data.list ?? [];
  const rawIn: Array<Record<string, string | number | undefined>> = [];
  for (let i = 0; i < raw.length; i++) {
    const el = raw[i];
    if (typeof el === 'object' && el !== null) {
      rawIn.push(el as Record<string, string | number | undefined>);
    }
  }
  return parseAlbumTimelineRows(rawIn);
}

/**
 * 按用户相册 ID 打开其媒体列表页（CategoryGallery）。空相册仍打开，展示空态。
 */
export async function openUserAlbumById(
  baseUrl: string,
  album: UserAlbumItem,
  uiCtx: UIContext,
  shouldContinue?: () => boolean
): Promise<UserAlbumOpenResult> {
  const albumId = userAlbumId(album);
  if (albumId.length === 0) {
    return { ok: false, errorMessage: '相册 ID 无效' };
  }
  const client = AppSession.getClient();
  if (client === null) {
    return { ok: false, errorMessage: '未登录' };
  }
  const title = userAlbumName(album);
  const isBaby = userAlbumIsBaby(album);
  const detailItemCount = userAlbumCount(album);
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { ok: false, errorMessage: '' };
  }
  const tl = await client.getUserAlbumTimeline(albumId, isBaby);
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { ok: false, errorMessage: '' };
  }
  const cursor = new UserAlbumFetchCursor();
  let days: TimelineDayModel[] = [];
  if (tl.success && tl.data !== undefined) {
    days = timelineRowsFromData(tl.data);
  }
  if (days.length === 0) {
    cursor.useFlatPhotos = true;
  }
  const initialChunk = await fetchUserAlbumChunk(
    client,
    albumId,
    isBaby,
    days,
    cursor,
    USER_ALBUM_INITIAL_OPEN_ITEMS,
    detailItemCount,
    shouldContinue
  );
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { ok: false, errorMessage: '' };
  }
  const opened = await CategoryGalleryNavStore.open(baseUrl, title, initialChunk.items, uiCtx, false, {
    sourceKind: 'user-album',
    expectedTotalCount: detailItemCount
  });
  if (!opened) {
    return { ok: false, errorMessage: '打开相册失败' };
  }
  if (!initialChunk.done) {
    const token = CategoryGalleryNavStore.currentToken();
    void continueUserAlbumBackgroundLoad(albumId, isBaby, days, cursor, detailItemCount, token);
  }
  return { ok: true, errorMessage: '' };
}
