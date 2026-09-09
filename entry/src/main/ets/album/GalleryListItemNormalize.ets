/**
 * 各入口（主时间线 / 分类 / 用户相册 / 目录 / 最近添加）共用的媒体字段归一化。
 * 新页面拿到列表后走 galleryListFromData，预览原图、划选 ID、缩略图都会齐。
 */
import { GalleryGetListData, GalleryListItem } from '../model/FnApiTypes';

type LooseGalleryItem = Record<string, Object | string | number | boolean | undefined | null>;

function readLooseGalleryField(rec: LooseGalleryItem, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const raw = rec[keys[i]];
    if (raw === undefined || raw === null) {
      continue;
    }
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      const n = Math.floor(raw);
      if (n > 0) {
        return `${n}`;
      }
      continue;
    }
    const text = String(raw).trim();
    if (text.length > 0 && text !== 'null' && text !== 'undefined') {
      return text;
    }
  }
  return '';
}

function readLooseGalleryTime(rec: LooseGalleryItem, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const raw = rec[keys[i]];
    if (typeof raw !== 'string') {
      continue;
    }
    const text = raw.trim();
    if (text.length > 0 && text !== 'null' && text !== 'undefined') {
      return text;
    }
  }
  return '';
}

function fieldEmpty(rec: LooseGalleryItem, key: string): boolean {
  const raw = rec[key];
  if (raw === undefined || raw === null) {
    return true;
  }
  return String(raw).trim().length === 0;
}

function normalizeGalleryDateTime(raw: string): string {
  let text = raw.trim();
  if (text.length < 10) {
    return text;
  }
  const tIdx = text.indexOf('T');
  if (tIdx > 0) {
    text = `${text.substring(0, tIdx)} ${text.substring(tIdx + 1)}`;
  }
  const spaceIdx = text.indexOf(' ');
  const datePart = spaceIdx > 0 ? text.substring(0, spaceIdx) : text.substring(0, Math.min(10, text.length));
  const timePart = spaceIdx > 0 ? text.substring(spaceIdx + 1) : '';
  let normDate = '';
  for (let i = 0; i < datePart.length; i++) {
    const ch = datePart.charAt(i);
    normDate += ch === '-' ? ':' : ch;
  }
  if (timePart.length > 0) {
    return `${normDate} ${timePart}`;
  }
  return normDate;
}

export function galleryListItemIdOf(item: GalleryListItem): string {
  return readLooseGalleryField(item as LooseGalleryItem, ['id', 'photoId', 'photo_id']);
}

export function galleryListItemUuidOf(item: GalleryListItem): string {
  return readLooseGalleryField(item as LooseGalleryItem, ['photoUUID', 'uuid', 'photoUuid', 'photo_uuid', 'session']);
}

export function galleryPhotoStreamPath(id: string, uuid: string, mode: string): string {
  return `/p/api/v1/stream/p/t/${id}/${mode}/${uuid}`;
}

/**
 * 把各接口字段差补成主图库同款：id / photoUUID / thumb / originalUrl / dateTime。
 * 就地改 item，预览原图按钮与划选都读这些顶层字段。
 */
export function normalizeGalleryListItem(item: GalleryListItem): GalleryListItem {
  const rec = item as LooseGalleryItem;
  const id = galleryListItemIdOf(item);
  const uuid = galleryListItemUuidOf(item);
  if (id.length > 0) {
    rec['id'] = id;
  }
  if (uuid.length > 0) {
    rec['photoUUID'] = uuid;
  }
  if (id.length > 0 && uuid.length > 0) {
    if (fieldEmpty(rec, 'thumb')) {
      rec['thumb'] = galleryPhotoStreamPath(id, uuid, 'm');
    }
    if (fieldEmpty(rec, 'originalUrl')) {
      rec['originalUrl'] = galleryPhotoStreamPath(id, uuid, 'o');
    }
  }
  const dt = readLooseGalleryTime(rec, ['dateTime', 'photoDateTime', 'photo_date_time', 'createdAt', 'created_at']);
  if (dt.length > 0) {
    rec['dateTime'] = normalizeGalleryDateTime(dt);
  }
  return item;
}

export function normalizeGalleryListItems(items: GalleryListItem[]): GalleryListItem[] {
  for (let i = 0; i < items.length; i++) {
    normalizeGalleryListItem(items[i]);
  }
  return items;
}

export function galleryListFromData(data: GalleryGetListData | undefined): GalleryListItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  const raw = data.list ?? data.items ?? data.photos ?? data.records;
  if (!Array.isArray(raw)) {
    return [];
  }
  return normalizeGalleryListItems(raw as GalleryListItem[]);
}
