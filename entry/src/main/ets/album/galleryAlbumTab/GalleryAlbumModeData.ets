import {
  AiPersonItem,
  GalleryListItem,
  MediaCategoryItem,
  SmartCategoryItem
} from '../../model/FnApiTypes';

export function parseCategoryMedia(item: MediaCategoryItem): GalleryListItem[] {
  const raw = item.list ?? item.items;
  if (!Array.isArray(raw)) {
    return [];
  }
  const out: GalleryListItem[] = [];
  for (let i = 0; i < raw.length; i++) {
    const it = raw[i];
    if (typeof it === 'object' && it !== null) {
      out.push(it as GalleryListItem);
    }
  }
  return out;
}

export function categoryTitle(item: MediaCategoryItem): string {
  const t = item.name ?? item.title ?? item.label;
  return t !== undefined && t.length > 0 ? t : '未命名分类';
}

export function categoryCount(item: MediaCategoryItem): number {
  const c = item.count ?? item.total;
  return c !== undefined && Number.isFinite(Number(c)) ? Math.max(0, Math.floor(Number(c))) : 0;
}

export function categoryCover(item: MediaCategoryItem): string {
  if (item.cover !== undefined && item.cover.length > 0) {
    return item.cover;
  }
  if (item.thumb !== undefined && item.thumb.length > 0) {
    return item.thumb;
  }
  if (typeof item.thumbnail === 'string' && item.thumbnail.length > 0) {
    return item.thumbnail;
  }
  if (typeof item.thumbnail === 'object' && item.thumbnail !== null) {
    const tb = item.thumbnail;
    const u = tb.mUrl ?? tb.sUrl ?? tb.xsUrl ?? tb.xxsUrl ?? tb.originalUrl;
    if (u !== undefined && u.length > 0) {
      return u;
    }
  }
  return '';
}

export function collectMediaCategoryItems(raw: Array<MediaCategoryItem | object | null | undefined>): MediaCategoryItem[] {
  const out: MediaCategoryItem[] = [];
  for (let i = 0; i < raw.length; i++) {
    const el = raw[i];
    if (typeof el === 'object' && el !== null) {
      out.push(el as MediaCategoryItem);
    }
  }
  return out;
}

export function smartCategoryName(item: SmartCategoryItem): string {
  const n = item.name;
  return n !== undefined && n.length > 0 ? n : '未命名分类';
}

export function smartCategoryCount(item: SmartCategoryItem): number {
  const directVals: Array<number | string | undefined> = [
    item.count,
    item.total,
    item.itemCount,
    item.item_count,
    item.photoCount,
    item.photo_count,
    item.num,
    item.size
  ];
  for (let i = 0; i < directVals.length; i++) {
    const v = directVals[i];
    if (typeof v === 'number' && Number.isFinite(v)) {
      return Math.max(0, Math.floor(v));
    }
    if (typeof v === 'string') {
      const n = Number(v);
      if (Number.isFinite(n)) {
        return Math.max(0, Math.floor(n));
      }
    }
  }
  return 0;
}

export function smartCategoryCover(item: SmartCategoryItem): string {
  const p = item.poster;
  if (p === undefined || p === null) {
    return '';
  }
  const id = p.photoId !== undefined ? String(p.photoId) : '';
  const uuid = p.uuid !== undefined ? p.uuid : '';
  if (id.length === 0 || uuid.length === 0) {
    return '';
  }
  return `/p/api/v1/stream/p/t/${id}/s/${uuid}`;
}

export function collectSmartCategoryItems(raw: Array<SmartCategoryItem | object | null | undefined>): SmartCategoryItem[] {
  const out: SmartCategoryItem[] = [];
  for (let i = 0; i < raw.length; i++) {
    const el = raw[i];
    if (typeof el === 'object' && el !== null) {
      out.push(el as SmartCategoryItem);
    }
  }
  return out;
}

export function personName(item: AiPersonItem): string {
  const n = item.name ?? item.nickName;
  return n !== undefined && n.length > 0 ? n : '未命名人物';
}

export function personFace(item: AiPersonItem): string {
  if (item.faceUrl !== undefined && item.faceUrl.length > 0) {
    return item.faceUrl;
  }
  const id = item.faceId ?? item.avatarId ?? item.posterId ?? item.coverId ?? item.id;
  if (id === undefined || id === null) {
    return '';
  }
  const idStr = String(id);
  return idStr.length > 0 ? `/p/api/v1/stream/face/${idStr}` : '';
}

export function personId(item: AiPersonItem): string {
  const id = item.id;
  if (id === undefined || id === null) {
    return '';
  }
  return String(id);
}

export function personStatText(item: AiPersonItem, overrides: Map<string, string>): string {
  const pid = personId(item);
  if (pid.length > 0) {
    const txt = overrides.get(pid);
    if (txt !== undefined && txt.length > 0) {
      return txt;
    }
  }
  const photoRaw = item.photoCount;
  const videoRaw = item.videoCount;
  const photo = photoRaw !== undefined && Number.isFinite(Number(photoRaw))
    ? Math.max(0, Math.floor(Number(photoRaw)))
    : -1;
  const video = videoRaw !== undefined && Number.isFinite(Number(videoRaw))
    ? Math.max(0, Math.floor(Number(videoRaw)))
    : -1;
  if (photo >= 0 || video >= 0) {
    const p = photo >= 0 ? photo : 0;
    const v = video >= 0 ? video : 0;
    return `${p} 张照片 · ${v} 个视频`;
  }
  const totalRaw = item.itemCount ?? item.count ?? item.total;
  const total = totalRaw !== undefined && Number.isFinite(Number(totalRaw))
    ? Math.max(0, Math.floor(Number(totalRaw)))
    : 0;
  return `共 ${total} 项`;
}

export function collectPersonItems(raw: Array<AiPersonItem | object | null | undefined>): AiPersonItem[] {
  const out: AiPersonItem[] = [];
  for (let i = 0; i < raw.length; i++) {
    const el = raw[i];
    if (typeof el === 'object' && el !== null) {
      out.push(el as AiPersonItem);
    }
  }
  return out;
}
