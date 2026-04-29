import {
  AiPersonItem,
  GalleryGetListData,
  GalleryListItem,
  GalleryTimelineDayCell,
  MediaCategoryItem,
  SmartCategoryItem,
} from '../../model/FnApiTypes';
import { pickThumb } from '../GalleryAlbumCommon';
import { FnHttpClient } from '../../network/FnHttpClient';
import { loadAllRecentAddedItems } from '../RecentAddedOpenHelper';
import {
  GALLERY_RECENT_DAY_MAX_ROUNDS,
  GALLERY_RECENT_PAGE_LIMIT
} from './GalleryAlbumTabConstants';
import {
  fmtDayEnd,
  fmtDayStart,
  listFromData,
  sortDaysDesc,
  TimelineDayModel
} from './GalleryAlbumTabTypes';
import {
  collectMediaCategoryItems,
  collectPersonItems,
  collectSmartCategoryItems
} from './GalleryAlbumModeData';

export interface MediaCategoryLoadResult {
  items: MediaCategoryItem[];
  error: string;
}

export interface SmartCategoryLoadResult {
  sceneItems: SmartCategoryItem[];
  infoItems: SmartCategoryItem[];
  error: string;
}

export interface PersonLoadResult {
  items: AiPersonItem[];
  error: string;
}

export interface SpecialCollectionLoadResult {
  items: GalleryListItem[];
  error: string;
}

export interface GalleryAlbumModeLoadEnvelope<T> {
  data: T;
  error: string;
}

export interface GalleryAlbumModeLoader<T> {
  reset(): T;
  load(client: FnHttpClient): Promise<GalleryAlbumModeLoadEnvelope<T>>;
}

export interface GalleryMediaCategoryModeData {
  items: MediaCategoryItem[];
}

export interface GallerySmartCategoryModeData {
  sceneItems: SmartCategoryItem[];
  infoItems: SmartCategoryItem[];
}

export interface GalleryPersonModeData {
  items: AiPersonItem[];
}

class EmptyGalleryMediaCategoryModeData implements GalleryMediaCategoryModeData {
  items: MediaCategoryItem[] = [];
}

class EmptyGallerySmartCategoryModeData implements GallerySmartCategoryModeData {
  sceneItems: SmartCategoryItem[] = [];
  infoItems: SmartCategoryItem[] = [];
}

class EmptyGalleryPersonModeData implements GalleryPersonModeData {
  items: AiPersonItem[] = [];
}

function collectTimelineDays(rawList: GalleryTimelineDayCell[]): TimelineDayModel[] {
  const cellsIn: TimelineDayModel[] = [];
  for (let i = 0; i < rawList.length; i++) {
    const cell = rawList[i];
    if (
      cell.year === undefined ||
      cell.month === undefined ||
      cell.day === undefined
    ) {
      continue;
    }
    const yi = Number(cell.year);
    const mi = Number(cell.month);
    const di = Number(cell.day);
    if (!Number.isFinite(yi) || !Number.isFinite(mi) || !Number.isFinite(di)) {
      continue;
    }
    const itemCount = cell.itemCount !== undefined ? cell.itemCount : cell.item_count;
    const cnt = itemCount !== undefined && Number.isFinite(Number(itemCount))
      ? Math.max(0, Math.floor(Number(itemCount)))
      : 0;
    cellsIn.push({
      year: Math.floor(yi),
      month: Math.floor(mi),
      day: Math.floor(di),
      itemCount: cnt
    });
  }
  return sortDaysDesc(cellsIn).filter(
    (d: TimelineDayModel): boolean => d.itemCount > 0
  );
}

function dedupAndAppend(
  merged: GalleryListItem[],
  seen: Set<string>,
  list: GalleryListItem[],
  dayStart: string,
  itemIdOf: (item: GalleryListItem) => string
): void {
  for (let i = 0; i < list.length; i++) {
    const it = list[i];
    const key = itemIdOf(it);
    const thumb = pickThumb(it).trim();
    const dedupKey = key.length > 0 ? key : (thumb.length > 0 ? thumb : `${dayStart}_${i}`);
    if (!seen.has(dedupKey)) {
      seen.add(dedupKey);
      merged.push(it);
    }
  }
}

export async function loadMediaCategories(
  client: FnHttpClient
): Promise<MediaCategoryLoadResult> {
  try {
    const res = await client.getMediaCategoryList();
    if (!res.success || res.data === undefined) {
      return { items: [], error: res.message ?? '媒体分类加载失败' };
    }
    const raw = res.data.list ?? res.data.items ?? [];
    const items = collectMediaCategoryItems(raw);
    return {
      items: items,
      error: items.length > 0 ? '' : '暂无媒体分类（接口返回为空或字段不匹配）'
    };
  } catch (e) {
    return { items: [], error: String(e) || '媒体分类加载异常' };
  }
}

class GalleryMediaCategoryModeLoaderImpl implements GalleryAlbumModeLoader<GalleryMediaCategoryModeData> {
  reset(): GalleryMediaCategoryModeData {
    return new EmptyGalleryMediaCategoryModeData();
  }

  async load(client: FnHttpClient): Promise<GalleryAlbumModeLoadEnvelope<GalleryMediaCategoryModeData>> {
    const result = await loadMediaCategories(client);
    return {
      data: { items: result.items },
      error: result.error
    };
  }
}

export const galleryMediaCategoryModeLoader: GalleryAlbumModeLoader<GalleryMediaCategoryModeData> =
  new GalleryMediaCategoryModeLoaderImpl();

export async function loadSmartCategories(
  client: FnHttpClient
): Promise<SmartCategoryLoadResult> {
  try {
    const pair = await Promise.all([
      client.getSmartRecCategories('scene', -1),
      client.getSmartRecCategories('information', -1)
    ]);
    const sceneRes = pair[0];
    const infoRes = pair[1];
    const sceneRaw =
      sceneRes.success && sceneRes.data !== undefined ? (sceneRes.data.list ?? sceneRes.data.items ?? []) : [];
    const infoRaw =
      infoRes.success && infoRes.data !== undefined ? (infoRes.data.list ?? infoRes.data.items ?? []) : [];
    const sceneItems = collectSmartCategoryItems(sceneRaw);
    const infoItems = collectSmartCategoryItems(infoRaw);
    return {
      sceneItems: sceneItems,
      infoItems: infoItems,
      error: sceneItems.length > 0 || infoItems.length > 0
        ? ''
        : '暂无智能分类（请先在系统设置中开启智能识别）'
    };
  } catch (e) {
    return { sceneItems: [], infoItems: [], error: String(e) || '智能分类加载异常' };
  }
}

class GallerySmartCategoryModeLoaderImpl implements GalleryAlbumModeLoader<GallerySmartCategoryModeData> {
  reset(): GallerySmartCategoryModeData {
    return new EmptyGallerySmartCategoryModeData();
  }

  async load(client: FnHttpClient): Promise<GalleryAlbumModeLoadEnvelope<GallerySmartCategoryModeData>> {
    const result = await loadSmartCategories(client);
    return {
      data: {
        sceneItems: result.sceneItems,
        infoItems: result.infoItems
      },
      error: result.error
    };
  }
}

export const gallerySmartCategoryModeLoader: GalleryAlbumModeLoader<GallerySmartCategoryModeData> =
  new GallerySmartCategoryModeLoaderImpl();

export async function loadPersons(
  client: FnHttpClient
): Promise<PersonLoadResult> {
  try {
    const res = await client.getAiPersonList(true, -1, 0);
    if (!res.success || res.data === undefined) {
      return { items: [], error: res.message ?? '人物列表加载失败' };
    }
    const raw = res.data.list ?? res.data.items ?? res.data.records ?? [];
    const items = collectPersonItems(raw);
    return {
      items: items,
      error: items.length > 0 ? '' : '暂无人物（请先在系统设置中开启智能识别）'
    };
  } catch (e) {
    return { items: [], error: String(e) || '人物列表加载异常' };
  }
}

class GalleryPersonModeLoaderImpl implements GalleryAlbumModeLoader<GalleryPersonModeData> {
  reset(): GalleryPersonModeData {
    return new EmptyGalleryPersonModeData();
  }

  async load(client: FnHttpClient): Promise<GalleryAlbumModeLoadEnvelope<GalleryPersonModeData>> {
    const result = await loadPersons(client);
    return {
      data: { items: result.items },
      error: result.error
    };
  }
}

export const galleryPersonModeLoader: GalleryAlbumModeLoader<GalleryPersonModeData> =
  new GalleryPersonModeLoaderImpl();

export async function loadRecentAddedItems(
  client: FnHttpClient,
  itemIdOf: (item: GalleryListItem) => string,
  shouldContinue?: () => boolean
): Promise<SpecialCollectionLoadResult> {
  const result = await loadAllRecentAddedItems(client, itemIdOf, shouldContinue);
  return { items: result.items, error: result.errorMessage };
}

export async function loadCollectGalleryItems(
  client: FnHttpClient,
  itemIdOf: (item: GalleryListItem) => string,
  shouldContinue?: () => boolean
): Promise<SpecialCollectionLoadResult> {
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { items: [], error: '' };
  }
  const tl = await client.getCollectGalleryTimeline();
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { items: [], error: '' };
  }
  if (!tl.success || tl.data === undefined) {
    return { items: [], error: tl.message ?? '收藏时间轴加载失败' };
  }
  const days = collectTimelineDays(tl.data.list ?? []);
  if (days.length === 0) {
    return { items: [], error: '暂无收藏' };
  }

  const merged: GalleryListItem[] = [];
  const seen = new Set<string>();
  for (let di = 0; di < days.length; di++) {
    if (shouldContinue !== undefined && !shouldContinue()) {
      return { items: [], error: '' };
    }
    const day = days[di];
    const st = fmtDayStart(day.year, day.month, day.day);
    const et = fmtDayEnd(day.year, day.month, day.day);
    let off = 0;
    let rounds = 0;
    for (;;) {
      if (shouldContinue !== undefined && !shouldContinue()) {
        return { items: [], error: '' };
      }
      const one = await client.getCollectGalleryList(st, et, GALLERY_RECENT_PAGE_LIMIT, off);
      if (shouldContinue !== undefined && !shouldContinue()) {
        return { items: [], error: '' };
      }
      if (!one.success || one.data === undefined) {
        break;
      }
      const list = listFromData(one.data);
      if (list.length <= 0) {
        break;
      }
      dedupAndAppend(merged, seen, list, st, itemIdOf);
      off += list.length;
      rounds++;
      if (list.length < GALLERY_RECENT_PAGE_LIMIT) {
        break;
      }
      if (day.itemCount > 0 && off >= day.itemCount) {
        break;
      }
      if (rounds >= GALLERY_RECENT_DAY_MAX_ROUNDS) {
        break;
      }
    }
  }

  return {
    items: merged,
    error: merged.length > 0 ? '' : '收藏暂无可预览媒体'
  };
}

export async function loadFirstCollectGalleryItem(
  client: FnHttpClient,
  shouldContinue?: () => boolean
): Promise<SpecialCollectionLoadResult> {
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { items: [], error: '' };
  }
  const tl = await client.getCollectGalleryTimeline();
  if (shouldContinue !== undefined && !shouldContinue()) {
    return { items: [], error: '' };
  }
  if (!tl.success || tl.data === undefined) {
    return { items: [], error: tl.message ?? '收藏时间轴加载失败' };
  }
  const days = collectTimelineDays(tl.data.list ?? []);
  if (days.length === 0) {
    return { items: [], error: '暂无收藏' };
  }
  for (let i = 0; i < days.length; i++) {
    if (shouldContinue !== undefined && !shouldContinue()) {
      return { items: [], error: '' };
    }
    const day = days[i];
    const st = fmtDayStart(day.year, day.month, day.day);
    const et = fmtDayEnd(day.year, day.month, day.day);
    const one = await client.getCollectGalleryList(st, et, 1, 0);
    if (shouldContinue !== undefined && !shouldContinue()) {
      return { items: [], error: '' };
    }
    if (!one.success || one.data === undefined) {
      continue;
    }
    const list = listFromData(one.data);
    if (list.length > 0) {
      return { items: [list[0]], error: '' };
    }
  }
  return { items: [], error: '收藏暂无可预览媒体' };
}
