/**
 * 按人物 ID 拉取时间线并分页合并照片列表，再跳转 CategoryGallery。
 * 与 PersonPage / GalleryAlbumTab 中「打开人物媒体」逻辑一致，供多处复用（含预览详情人物行）。
 */
import { UIContext } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import { GalleryGetListData, GalleryListItem } from '../model/FnApiTypes';
import { CategoryGalleryNavStore } from './CategoryGalleryNavStore';

const DATE_FEED_BATCH = 50;
const DAY_MAX_ROUNDS = 300;

interface TimelineDayModel {
  year: number;
  month: number;
  day: number;
  itemCount: number;
}

/** 打开结果：ok 为 true 时已发起 CategoryGallery 路由 */
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

/**
 * 按人物 ID 打开其图库媒体列表页（CategoryGallery）。
 */
export async function openPersonAlbumById(
  baseUrl: string,
  personId: string,
  initialTitle: string,
  uiCtx: UIContext
): Promise<PersonAlbumOpenResult> {
  if (personId.length === 0) {
    return { ok: false, errorMessage: '人物 ID 无效' };
  }
  const client = AppSession.getClient();
  if (client === null) {
    return { ok: false, errorMessage: '未登录' };
  }
  let title = initialTitle.length > 0 ? initialTitle : '未命名人物';
  const detail = await client.getAiPersonDetail(personId);
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
  const merged: GalleryListItem[] = [];
  for (let di = 0; di < days.length; di++) {
    const day = days[di];
    const st = fmtDayStart(day.year, day.month, day.day);
    const et = fmtDayEnd(day.year, day.month, day.day);
    let off = 0;
    let rounds = 0;
    while (rounds < DAY_MAX_ROUNDS) {
      const one = await client.getAiPersonPhotoList(personId, st, et, DATE_FEED_BATCH, off, 20000);
      if (!one.success || one.data === undefined) {
        break;
      }
      const list = listFromData(one.data);
      if (list.length === 0) {
        break;
      }
      for (let li = 0; li < list.length; li++) {
        merged.push(list[li]);
      }
      off += list.length;
      rounds++;
      if (detailItemCount > 0 && merged.length >= detailItemCount) {
        break;
      }
      if (list.length < DATE_FEED_BATCH) {
        break;
      }
      if (day.itemCount > 0 && off >= day.itemCount) {
        break;
      }
    }
  }
  if (merged.length === 0) {
    return { ok: false, errorMessage: '该人物暂无可预览媒体' };
  }
  const opened = await CategoryGalleryNavStore.open(baseUrl, title, merged, uiCtx);
  if (!opened) {
    return { ok: false, errorMessage: '打开人物媒体失败' };
  }
  return { ok: true, errorMessage: '' };
}
