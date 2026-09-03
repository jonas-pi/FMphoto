/**
 * 智能分类 AI 搜索：magic-search 结果归一化为图库列表项。
 */
import { common } from '@kit.AbilityKit';
import { GalleryListItem, GalleryThumbnailBlock, MagicSearchItem, SmartCategoryItem } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { pickThumb } from './GalleryAlbumCommon';
import { smartCategoryCover, smartCategoryName } from './GalleryAlbumEntityData';
import { SmartCategoryCountStore } from './SmartCategoryCountStore';
import {
  SmartCategoryCoverPatch,
  smartCategoryApplyCoverPatches,
  smartCategoryCurrentAccount,
  smartCategoryCustomIdOf,
  smartCategoryIsCustom,
  smartCategoryLayoutFromDisplay,
  smartCategorySaveLayout
} from './SmartCategoryLayoutPreferences';

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
  keyword: string,
  timeoutMs: number = 20000
): Promise<SmartCategoryGalleryLoadResult> {
  const kw = keyword.trim();
  const empty: SmartCategoryGalleryLoadResult = { items: [], errorMessage: '' };
  if (kw.length === 0) {
    empty.errorMessage = '搜索关键词无效';
    return empty;
  }
  const res = await client.doMagicSearch(kw, timeoutMs);
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

/** 封面计数回调：按分类名回写，返回 false 则中止后续刷新。 */
export type SmartCategoryCountSink = (name: string, count: number) => boolean;

/** 用与内页相同的 magic-search 条数刷新封面计数。 */
export async function enrichSmartCategoryCountsFromSearch(
  client: FnHttpClient,
  items: SmartCategoryItem[],
  onCount: SmartCategoryCountSink,
  timeoutMs: number = 12000
): Promise<void> {
  const names: string[] = [];
  for (let i = 0; i < items.length; i++) {
    const name = smartCategoryName(items[i]);
    if (name.length > 0) {
      names.push(name);
    }
  }
  for (let i = 0; i < names.length; i++) {
    if (SmartCategoryCountStore.has(names[i])) {
      continue;
    }
    const mapped = await loadSmartCategoryGalleryItems(client, names[i], timeoutMs);
    if (mapped.errorMessage.length > 0) {
      continue;
    }
    if (!onCount(names[i], mapped.items.length)) {
      return;
    }
  }
}

export function smartCategoryCoverPatchFromItems(
  customId: string,
  items: GalleryListItem[]
): SmartCategoryCoverPatch | undefined {
  if (customId.length === 0 || items.length === 0) {
    return undefined;
  }
  const cover = pickThumb(items[0]).trim();
  if (cover.length === 0) {
    return undefined;
  }
  const patch: SmartCategoryCoverPatch = {
    customId: customId,
    cover: cover,
    count: items.length
  };
  return patch;
}

/** 为缺少封面的自定义分类拉首张缩略图；不改动已有封面，避免进页卡死。 */
export async function fetchMissingCustomSmartCategoryCovers(
  client: FnHttpClient,
  items: SmartCategoryItem[]
): Promise<SmartCategoryCoverPatch[]> {
  const patches: SmartCategoryCoverPatch[] = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (!smartCategoryIsCustom(item)) {
      continue;
    }
    if (smartCategoryCover(item).length > 0) {
      continue;
    }
    const id = smartCategoryCustomIdOf(item);
    const mapped = await loadSmartCategoryGalleryItems(client, smartCategoryName(item), 12000);
    if (mapped.errorMessage.length > 0) {
      continue;
    }
    const patch = smartCategoryCoverPatchFromItems(id, mapped.items);
    if (patch !== undefined) {
      patches.push(patch);
    }
  }
  return patches;
}

export async function fillAndPersistCustomSmartCategoryCovers(
  client: FnHttpClient,
  ctx: common.UIAbilityContext | undefined,
  sceneItems: SmartCategoryItem[],
  infoItems: SmartCategoryItem[],
  customItems: SmartCategoryItem[]
): Promise<SmartCategoryItem[]> {
  if (customItems.length === 0) {
    return customItems;
  }
  const patches = await fetchMissingCustomSmartCategoryCovers(client, customItems);
  const next = smartCategoryApplyCoverPatches(customItems, patches);
  if (ctx !== undefined && patches.length > 0) {
    const layout = smartCategoryLayoutFromDisplay(
      smartCategoryCurrentAccount(),
      sceneItems,
      infoItems,
      next
    );
    await smartCategorySaveLayout(ctx, layout);
  }
  return next;
}
