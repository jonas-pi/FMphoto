/**
 * 智能分类 AI 搜索：magic-search 结果归一化为图库列表项。
 */
import { GalleryListItem, GalleryThumbnailBlock, MagicSearchItem } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';

export interface SmartCategoryGalleryLoadResult {
  items: GalleryListItem[];
  errorMessage: string;
}

type SmartMagicRecord = Record<string, Object | string | number | boolean | undefined | null>;

function smartReadFirstString(raw: SmartMagicRecord, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const value = raw[keys[i]];
    if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
      const text = String(value).trim();
      if (text.length > 0 && text !== 'null') {
        return text;
      }
    }
  }
  return '';
}

/** 将 magic-search 单条结果补全缩略图与流地址字段 */
export function normalizeSmartMagicItem(item: MagicSearchItem): GalleryListItem {
  const out = item as GalleryListItem;
  const raw = item as SmartMagicRecord;
  const id = smartReadFirstString(raw, ['photoId', 'id']);
  const uuid = smartReadFirstString(raw, ['uuid', 'photoUUID', 'session']);
  if (id.length === 0 || uuid.length === 0) {
    return out;
  }

  const thumbM = `/p/api/v1/stream/p/t/${id}/m/${uuid}`;
  const thumbS = `/p/api/v1/stream/p/t/${id}/s/${uuid}`;
  const original = `/p/api/v1/stream/p/t/${id}/o/${uuid}`;
  const thumbBlock: GalleryThumbnailBlock = {
    mUrl: thumbM,
    sUrl: thumbS,
    xsUrl: thumbS,
    xxsUrl: thumbS,
    originalUrl: original
  };

  out.id = id;
  out.photoUUID = uuid;
  out.thumb = thumbM;
  out.small_thumb = thumbS;
  out.thumbnail = thumbBlock;
  if (out.originalUrl === undefined || out.originalUrl.trim().length === 0) {
    out.originalUrl = original;
  }
  if (out.additional === undefined) {
    out.additional = { thumbnail: thumbBlock };
  } else {
    out.additional.thumbnail = thumbBlock;
  }
  return out;
}

/** 按关键词拉取智能分类媒体列表（AI 语义搜索） */
export async function loadSmartCategoryGalleryItems(
  client: FnHttpClient,
  keyword: string
): Promise<SmartCategoryGalleryLoadResult> {
  const kw = keyword.trim();
  const empty: SmartCategoryGalleryLoadResult = { items: [], errorMessage: '' };
  if (kw.length === 0) {
    empty.errorMessage = '搜索关键词无效';
    return empty;
  }
  const res = await client.doMagicSearch(kw);
  if (!res.success || res.data === undefined) {
    return { items: [], errorMessage: res.message ?? '加载失败' };
  }
  const rawList = res.data.list ?? [];
  const mapped: GalleryListItem[] = [];
  for (let i = 0; i < rawList.length; i++) {
    mapped.push(normalizeSmartMagicItem(rawList[i]));
  }
  return { items: mapped, errorMessage: '' };
}
