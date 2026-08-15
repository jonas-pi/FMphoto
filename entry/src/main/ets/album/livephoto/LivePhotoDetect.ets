/**
 * 实况/动态照片识别：只信 NAS 显式标记或封面条目上的伴生 videoUrl，
 * 不复用普通视频 stream/v/{id} 兜底，避免静图被误判。
 */
import { isGifItem, isVideoItem, itemFileExt } from '../GalleryAlbumCommon';
import { GalleryListItem, GalleryThumbnailBlock } from '../../model/FnApiTypes';

type LooseLiveRecord = Record<string, Object | string | number | boolean | undefined | null>;

function asLooseRecord(value: Object | string | number | boolean | undefined | null): LooseLiveRecord | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }
  return value as LooseLiveRecord;
}

function readTrimmedString(value: Object | string | number | boolean | undefined | null): string {
  if (typeof value === 'string') {
    return value.trim();
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value).trim();
  }
  return '';
}

function readFlagNumber(value: Object | string | number | boolean | undefined | null): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'boolean') {
    return value ? 1 : 0;
  }
  if (typeof value === 'string') {
    const t = value.trim().toLowerCase();
    if (t === '1' || t === 'true' || t === 'yes') {
      return 1;
    }
    const n = Number(t);
    if (Number.isFinite(n)) {
      return n;
    }
  }
  return 0;
}

function readVideoUrlFromThumbBlock(block: GalleryThumbnailBlock | undefined): string {
  if (block === undefined) {
    return '';
  }
  const url = block.videoUrl;
  if (url !== undefined && url.trim().length > 0) {
    return url.trim();
  }
  return '';
}

/**
 * 从列表/详情宽松读取 isLive（兼容 is_live / live）。
 */
export function readLivePhotoFlag(it: GalleryListItem): number {
  if (it.isLive === 1) {
    return 1;
  }
  const raw = asLooseRecord(it as Object);
  if (raw === null) {
    return 0;
  }
  const keys: string[] = ['isLive', 'is_live', 'live', 'isLivePhoto'];
  for (let i = 0; i < keys.length; i++) {
    if (readFlagNumber(raw[keys[i]]) === 1) {
      return 1;
    }
  }
  const category = readTrimmedString(raw['category']).toLowerCase();
  if (category === 'live_photo' || category === 'livephoto' || category === 'moving_photo') {
    return 1;
  }
  const fileTypeSlug = readTrimmedString(raw['file_type']).toLowerCase();
  if (fileTypeSlug === 'live_photo' || fileTypeSlug === 'livephoto') {
    return 1;
  }
  return 0;
}

/**
 * 仅读取条目上显式下发的伴生视频地址，不做 stream/v/{id} 兜底。
 */
export function pickLiveVideo(it: GalleryListItem): string {
  const fromAdditional = readVideoUrlFromThumbBlock(it.additional?.thumbnail);
  if (fromAdditional.length > 0) {
    return fromAdditional;
  }
  if (typeof it.thumbnail === 'object') {
    const fromThumb = readVideoUrlFromThumbBlock(it.thumbnail as GalleryThumbnailBlock);
    if (fromThumb.length > 0) {
      return fromThumb;
    }
  }
  const raw = asLooseRecord(it as Object);
  if (raw !== null) {
    const top = readTrimmedString(raw['videoUrl']);
    if (top.length > 0) {
      return top;
    }
  }
  return '';
}

export function isLivePhotoItem(it: GalleryListItem): boolean {
  if (isVideoItem(it) || isGifItem(it)) {
    return false;
  }
  if (itemFileExt(it) === 'livp') {
    return true;
  }
  if (readLivePhotoFlag(it) === 1) {
    return true;
  }
  return pickLiveVideo(it).length > 0;
}
