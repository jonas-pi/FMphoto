import { GalleryListItem, GalleryThumbnailBlock } from '../model/FnApiTypes';
import {
  galleryListItemIdOf,
  galleryListItemUuidOf,
  galleryPhotoStreamPath
} from './GalleryListItemNormalize';

/** 预览图缩放：最小值固定为 1.0（不允许缩小到比 fit 更小） */
export const GALLERY_PREVIEW_SCALE_MIN = 1.0;
export const GALLERY_PREVIEW_SCALE_MAX = 4;

export { galleryListItemIdOf };

/** 官方图片预览：双击在默认尺寸与固定倍率之间切换 */
export const GALLERY_PREVIEW_DOUBLE_TAP_SCALE = 2;
export const GALLERY_PREVIEW_ZOOM_EPS = 0.0005;
export const GALLERY_PREVIEW_SNAP_EPS = 0.001;
export const GALLERY_FLOATING_HERO_BACKDROP_HEIGHT_VP = 232;

export function itemFileExt(it: GalleryListItem): string {
  const name = it.filename ?? it.fileName ?? it.name ?? it.title ?? '';
  const dot = name.lastIndexOf('.');
  return dot >= 0 ? name.substring(dot + 1).toLowerCase() : (it.fileType ?? '').toLowerCase();
}

export function isVideoItem(it: GalleryListItem): boolean {
  if (it.category === 'video') {
    return true;
  }
  const ext = itemFileExt(it);
  return ext === 'mp4' || ext === 'mov' || ext === 'avi' || ext === 'mkv' || ext === 'webm' || ext === 'm4v';
}

export function isGifItem(it: GalleryListItem): boolean {
  return itemFileExt(it) === 'gif';
}

function pickFirstThumbUrl(urls: Array<string | undefined>): string {
  for (let i = 0; i < urls.length; i++) {
    const value = urls[i];
    if (value !== undefined && value.trim().length > 0) {
      return value.trim();
    }
  }
  return '';
}

type LooseThumbRecord = Record<string, Object | string | number | boolean | undefined | null>;

function readLooseThumbString(raw: LooseThumbRecord, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const value = raw[keys[i]];
    if (typeof value === 'string') {
      const text = value.trim();
      if (text.length > 0) {
        return text;
      }
    } else if (typeof value === 'number' || typeof value === 'boolean') {
      const text = String(value).trim();
      if (text.length > 0) {
        return text;
      }
    }
  }
  return '';
}

function asLooseThumbRecord(value: Object | string | number | boolean | undefined | null): LooseThumbRecord | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }
  return value as LooseThumbRecord;
}

function pickLooseThumbnailBlockUrl(value: Object | string | number | boolean | undefined | null): string {
  if (typeof value === 'string') {
    const text = value.trim();
    return text.length > 0 ? text : '';
  }
  const raw = asLooseThumbRecord(value);
  if (raw === null) {
    return '';
  }
  return readLooseThumbString(raw, [
    'mUrl',
    'sUrl',
    'xsUrl',
    'xxsUrl',
    'originalUrl',
    'videoUrl',
    'url',
    'src'
  ]);
}

function buildPhotoThumbStream(raw: LooseThumbRecord, mode: 'm' | 's' = 's'): string {
  const id = readLooseThumbString(raw, ['photoId', 'id']);
  const uuid = readLooseThumbString(raw, ['uuid', 'photoUUID', 'session']);
  if (id.length === 0 || uuid.length === 0 || id === 'null' || uuid === 'null') {
    return '';
  }
  return `/p/api/v1/stream/p/t/${id}/${mode}/${uuid}`;
}

function pickNestedPhotoThumb(it: GalleryListItem): string {
  const raw = it as LooseThumbRecord;
  const direct = readLooseThumbString(raw, [
    'mUrl',
    'sUrl',
    'xsUrl',
    'xxsUrl',
    'coverUrl',
    'posterUrl',
    'imageUrl',
    'imgUrl',
    'photoUrl'
  ]);
  if (direct.length > 0) {
    return direct;
  }
  const nestedKeys: string[] = ['poster', 'coverInfo', 'coverPhoto', 'photo', 'media', 'item'];
  for (let i = 0; i < nestedKeys.length; i++) {
    const nested = asLooseThumbRecord(raw[nestedKeys[i]]);
    if (nested === null) {
      continue;
    }
    const nestedDirect = readLooseThumbString(nested, [
      'cover',
      'thumb',
      'small_thumb',
      'thumb_url',
      'poster',
      'posterUrl',
      'imageUrl',
      'imgUrl',
      'photoUrl',
      'url',
      'src',
      'path'
    ]);
    if (nestedDirect.length > 0) {
      return nestedDirect;
    }
    const nestedBlock = pickLooseThumbnailBlockUrl(nested['thumbnail']);
    if (nestedBlock.length > 0) {
      return nestedBlock;
    }
    const nestedStream = buildPhotoThumbStream(nested);
    if (nestedStream.length > 0) {
      return nestedStream;
    }
  }
  return buildPhotoThumbStream(raw);
}

export function pickThumb(it: GalleryListItem): string {
  const th = it.additional?.thumbnail;
  const fromAdditional = th !== undefined ? pickFirstThumbUrl([th.mUrl, th.sUrl, th.xsUrl, th.xxsUrl]) : '';
  if (fromAdditional.length > 0) {
    return fromAdditional;
  }
  const topTh = it.thumbnail;
  if (topTh !== undefined && typeof topTh === 'object') {
    const tb = topTh as GalleryThumbnailBlock;
    const fromTopBlock = pickFirstThumbUrl([tb.mUrl, tb.sUrl, tb.xsUrl, tb.xxsUrl]);
    if (fromTopBlock.length > 0) {
      return fromTopBlock;
    }
  }
  for (const u of [it.thumb, it.small_thumb, it.thumb_url, it.cover, it.poster]) {
    if (u !== undefined && u.trim().length > 0) {
      return u.trim();
    }
  }
  if (typeof topTh === 'string' && topTh.trim().length > 0) {
    return topTh.trim();
  }
  const looseThumb = pickNestedPhotoThumb(it);
  if (looseThumb.length > 0) {
    return looseThumb;
  }
  for (const u of [it.url, it.src, it.path]) {
    if (u !== undefined && u.trim().length > 0) {
      return u.trim();
    }
  }
  return '';
}

/**
 * 预览中档地址：优先 mUrl，流路径 /s|/xs|/xxs 升到 /m，绝不走原图 /o。
 */
export function pickPreviewThumb(it: GalleryListItem): string {
  const th = it.additional?.thumbnail;
  const fromAdditional = th !== undefined ? pickFirstThumbUrl([th.mUrl, th.sUrl, th.xsUrl, th.xxsUrl]) : '';
  if (fromAdditional.length > 0) {
    return promoteStreamThumbToMedium(fromAdditional);
  }
  const topTh = it.thumbnail;
  if (topTh !== undefined && typeof topTh === 'object') {
    const tb = topTh as GalleryThumbnailBlock;
    const fromTopBlock = pickFirstThumbUrl([tb.mUrl, tb.sUrl, tb.xsUrl, tb.xxsUrl]);
    if (fromTopBlock.length > 0) {
      return promoteStreamThumbToMedium(fromTopBlock);
    }
  }
  for (const u of [it.thumb, it.small_thumb, it.thumb_url, it.cover, it.poster]) {
    if (u !== undefined && u.trim().length > 0) {
      return promoteStreamThumbToMedium(u.trim());
    }
  }
  if (typeof topTh === 'string' && topTh.trim().length > 0) {
    return promoteStreamThumbToMedium(topTh.trim());
  }
  const looseThumb = pickNestedPhotoThumb(it);
  if (looseThumb.length > 0) {
    return promoteStreamThumbToMedium(looseThumb);
  }
  for (const u of [it.url, it.src, it.path]) {
    if (u !== undefined && u.trim().length > 0) {
      return promoteStreamThumbToMedium(u.trim());
    }
  }
  return '';
}

function promoteStreamThumbToMedium(url: string): string {
  if (url.indexOf('/stream/p/t/') < 0) {
    return url;
  }
  return url.replace('/xxs/', '/m/').replace('/xs/', '/m/').replace('/s/', '/m/');
}

export function pickThumbForGridDensity(it: GalleryListItem, density: 'day' | 'month' | 'year'): string {
  const topLevelPriorities = density === 'day'
    ? [it.thumb, it.small_thumb, it.thumb_url, it.cover, it.poster]
    : [it.small_thumb, it.thumb, it.thumb_url, it.cover, it.poster];
  const th = it.additional?.thumbnail;
  const fromAdditional = th !== undefined
    ? density === 'year'
      ? pickFirstThumbUrl([th.xsUrl, th.xxsUrl, th.sUrl, th.mUrl])
      : density === 'month'
        ? pickFirstThumbUrl([th.sUrl, th.xsUrl, th.xxsUrl, th.mUrl])
        : pickFirstThumbUrl([th.mUrl, th.sUrl, th.xsUrl, th.xxsUrl])
    : '';
  if (fromAdditional.length > 0) {
    return fromAdditional;
  }
  const topTh = it.thumbnail;
  if (topTh !== undefined && typeof topTh === 'object') {
    const tb = topTh as GalleryThumbnailBlock;
    const fromTopBlock = density === 'year'
      ? pickFirstThumbUrl([tb.xsUrl, tb.xxsUrl, tb.sUrl, tb.mUrl])
      : density === 'month'
        ? pickFirstThumbUrl([tb.sUrl, tb.xsUrl, tb.xxsUrl, tb.mUrl])
        : pickFirstThumbUrl([tb.mUrl, tb.sUrl, tb.xsUrl, tb.xxsUrl]);
    if (fromTopBlock.length > 0) {
      return fromTopBlock;
    }
  }
  for (let i = 0; i < topLevelPriorities.length; i++) {
    const u = topLevelPriorities[i];
    if (u !== undefined && u.trim().length > 0) {
      return u.trim();
    }
  }
  if (typeof topTh === 'string' && topTh.trim().length > 0) {
    return topTh.trim();
  }
  const looseThumb = pickNestedPhotoThumb(it);
  if (looseThumb.length > 0) {
    return looseThumb;
  }
  for (const u of [it.url, it.src, it.path]) {
    if (u !== undefined && u.trim().length > 0) {
      return u.trim();
    }
  }
  return '';
}

export function thumbDensityCacheRank(density: 'day' | 'month' | 'year'): number {
  if (density === 'day') {
    return 3;
  }
  if (density === 'month') {
    return 2;
  }
  return 1;
}

export function pickOriginal(it: GalleryListItem): string {
  if (it.originalUrl !== undefined && it.originalUrl.trim().length > 0) {
    return it.originalUrl.trim();
  }
  const th = it.additional?.thumbnail;
  if (th?.originalUrl !== undefined && th.originalUrl.trim().length > 0) {
    return th.originalUrl.trim();
  }
  if (typeof it.thumbnail === 'object') {
    const orig = (it.thumbnail as GalleryThumbnailBlock).originalUrl;
    if (orig !== undefined && orig.trim().length > 0) {
      return orig.trim();
    }
  }
  const id = galleryListItemIdOf(it);
  const uuid = galleryListItemUuidOf(it);
  if (id.length > 0 && uuid.length > 0) {
    return galleryPhotoStreamPath(id, uuid, 'o');
  }
  return '';
}

export function thumbIdentityOfItem(it: GalleryListItem): string {
  const id = it.id !== undefined ? String(it.id).trim() : '';
  if (id.length > 0) {
    return `id:${id}`;
  }
  const photoUUID = it.photoUUID !== undefined ? String(it.photoUUID).trim() : '';
  if (photoUUID.length > 0) {
    return `uuid:${photoUUID}`;
  }
  const guid = it.guid !== undefined ? String(it.guid).trim() : '';
  if (guid.length > 0) {
    return `guid:${guid}`;
  }
  const orig = pickOriginal(it);
  if (orig.length > 0) {
    return `orig:${orig}`;
  }
  const thumb = pickThumb(it);
  if (thumb.length > 0) {
    return `thumb:${thumb}`;
  }
  return '';
}

export function pickVideo(it: GalleryListItem): string {
  const th = it.additional?.thumbnail;
  if (th?.videoUrl !== undefined && th.videoUrl.trim().length > 0) {
    return th.videoUrl.trim();
  }
  if (typeof it.thumbnail === 'object') {
    const vUrl = (it.thumbnail as GalleryThumbnailBlock).videoUrl;
    if (vUrl !== undefined && vUrl.trim().length > 0) {
      return vUrl.trim();
    }
  }
  // 兼容部分返回：视频条目未给 videoUrl，仅给 id
  if (it.id !== undefined) {
    const sid = String(it.id).trim();
    if (sid.length > 0) {
      return `/p/api/v1/stream/v/${sid}`;
    }
  }
  for (const u of [it.url, it.src, it.path]) {
    if (u !== undefined && u.trim().length > 0) {
      return u.trim();
    }
  }
  return '';
}

export function nasUrl(base: string, ref: string): string {
  const t = ref.trim();
  if (t.length === 0) {
    return '';
  }
  if (t.startsWith('http://') || t.startsWith('https://') || t.startsWith('data:')) {
    return t;
  }
  let b = base.trim();
  while (b.length > 1 && b.endsWith('/')) {
    b = b.substring(0, b.length - 1);
  }
  return t.startsWith('/') ? `${b}${t}` : `${b}/${t}`;
}
