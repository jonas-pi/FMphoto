import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryGetListData, GalleryListItem, GalleryTimelineData } from '../../model/FnApiTypes';
import { FnHttpClient } from '../../network/FnHttpClient';
import { isGifItem, isVideoItem } from '../GalleryAlbumCommon';
import { DATE_FEED_BATCH, DAY_MAX_ROUNDS } from '../galleryAlbumTab/GalleryAlbumTabConstants';
import {
  fmtDayEnd,
  fmtDayStart,
  parseTimelineDayCells,
  sortDaysDesc,
  TimelineDayModel
} from '../galleryAlbumTab/GalleryAlbumTabTypes';
import {
  GallerySlideshowConfig,
  GallerySlideshowPlaylistEntry,
  GallerySlideshowScope,
  GallerySlideshowScopeKind
} from './GallerySlideshowTypes';

const DOMAIN = 0xFF00;
const TAG = 'GallerySlideshow';

export class GallerySlideshowFetchResult {
  items: GalleryListItem[] = [];
  errorMessage: string = '';
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

function collectTimelineDays(timeline: GalleryTimelineData): TimelineDayModel[] {
  const raw = timeline.list ?? [];
  const rows: Array<Record<string, number | undefined>> = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    if (typeof item === 'object' && item !== null) {
      rows.push(item as Record<string, number | undefined>);
    }
  }
  return sortDaysDesc(parseTimelineDayCells(rows)).filter((day: TimelineDayModel): boolean => day.itemCount > 0);
}

function dedupKeyForItem(item: GalleryListItem, fallbackPrefix: string, fallbackIndex: number): string {
  const norm = (value: string | number | undefined | null): string => {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value).trim();
  };
  const photoUUID = norm(item.photoUUID);
  if (photoUUID.length > 0) {
    return `uuid:${photoUUID}`;
  }
  const id = norm(item.id);
  if (id.length > 0) {
    return `id:${id}`;
  }
  const guid = norm(item.guid);
  if (guid.length > 0) {
    return `guid:${guid}`;
  }
  const path = norm(item.path);
  if (path.length > 0) {
    return `path:${path}`;
  }
  return `${fallbackPrefix}_${fallbackIndex}`;
}

function appendUniqueItems(
  target: GalleryListItem[],
  seen: Set<string>,
  page: GalleryListItem[],
  fallbackPrefix: string,
  fallbackOffset: number
): void {
  for (let i = 0; i < page.length; i++) {
    const item = page[i];
    const key = dedupKeyForItem(item, fallbackPrefix, fallbackOffset + i);
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    target.push(item);
  }
}

/** Fisher-Yates 洗牌 */
export function shuffleGallerySlideshowItems(items: GalleryListItem[]): GalleryListItem[] {
  const out = items.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

export function shuffleGallerySlideshowEntries(
  entries: GallerySlideshowPlaylistEntry[]
): GallerySlideshowPlaylistEntry[] {
  const out = entries.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

/**
 * 按配置过滤：RAW / 静态图始终保留；视频、动图可单独开关。
 */
export function filterGallerySlideshowItems(
  items: GalleryListItem[],
  config: GallerySlideshowConfig
): GalleryListItem[] {
  const out: GalleryListItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (!config.includeVideo && isVideoItem(item)) {
      continue;
    }
    if (!config.includeGif && isGifItem(item)) {
      continue;
    }
    out.push(item);
  }
  return out;
}

async function fetchDayPages(
  client: FnHttpClient,
  day: TimelineDayModel,
  seen: Set<string>,
  target: GalleryListItem[],
  personId: string,
  shouldContinue?: () => boolean
): Promise<string> {
  const st = fmtDayStart(day.year, day.month, day.day);
  const et = fmtDayEnd(day.year, day.month, day.day);
  let dayOffset = 0;
  let rounds = 0;
  while (rounds < DAY_MAX_ROUNDS) {
    if (shouldContinue !== undefined && !shouldContinue()) {
      return '';
    }
    const res = personId.length > 0
      ? await client.getAiPersonPhotoList(personId, st, et, DATE_FEED_BATCH, dayOffset)
      : await client.getGalleryList(st, et, DATE_FEED_BATCH, dayOffset);
    if (!res.success || res.data === undefined) {
      return res.message ?? '媒体加载失败';
    }
    const list = listFromData(res.data as GalleryGetListData);
    if (list.length === 0) {
      break;
    }
    appendUniqueItems(target, seen, list, st, dayOffset);
    dayOffset += list.length;
    rounds++;
    if (list.length < DATE_FEED_BATCH) {
      break;
    }
  }
  return '';
}

async function fetchByTimeline(
  client: FnHttpClient,
  timeline: GalleryTimelineData,
  personId: string,
  shouldContinue?: () => boolean
): Promise<GallerySlideshowFetchResult> {
  const out = new GallerySlideshowFetchResult();
  const days = collectTimelineDays(timeline);
  if (days.length === 0) {
    out.errorMessage = '暂无可播放媒体';
    return out;
  }
  const seen = new Set<string>();
  for (let di = 0; di < days.length; di++) {
    if (shouldContinue !== undefined && !shouldContinue()) {
      return out;
    }
    const err = await fetchDayPages(client, days[di], seen, out.items, personId, shouldContinue);
    if (err.length > 0) {
      out.errorMessage = err;
      return out;
    }
  }
  return out;
}

/**
 * 按作用域拉取全量媒体（时间轴 + 分日分页），尽量覆盖全部条目后再随机。
 */
export async function gallerySlideshowFetchItems(
  client: FnHttpClient,
  scope: GallerySlideshowScope,
  shouldContinue?: () => boolean
): Promise<GallerySlideshowFetchResult> {
  const out = new GallerySlideshowFetchResult();
  if (shouldContinue !== undefined && !shouldContinue()) {
    return out;
  }

  if (scope.kind === GallerySlideshowScopeKind.PERSON_ALBUM) {
    const personId = scope.personId !== undefined ? scope.personId.trim() : '';
    if (personId.length === 0) {
      out.errorMessage = '人物相册参数无效';
      return out;
    }
    const timeline = await client.getAiPersonPhotoTimeline(personId);
    if (!timeline.success || timeline.data === undefined) {
      out.errorMessage = timeline.message ?? '人物时间轴加载失败';
      return out;
    }
    const fetched = await fetchByTimeline(client, timeline.data, personId, shouldContinue);
    hilog.info(DOMAIN, TAG, 'person slideshow fetched=%{public}d', fetched.items.length);
    if (fetched.items.length === 0 && fetched.errorMessage.length === 0) {
      fetched.errorMessage = '该人物暂无可播放媒体';
    }
    return fetched;
  }

  const timeline = await client.getGalleryTimeline();
  if (!timeline.success || timeline.data === undefined) {
    out.errorMessage = timeline.message ?? '时间轴加载失败';
    return out;
  }
  const fetched = await fetchByTimeline(client, timeline.data, '', shouldContinue);
  hilog.info(DOMAIN, TAG, 'gallery slideshow fetched=%{public}d', fetched.items.length);
  if (fetched.items.length === 0 && fetched.errorMessage.length === 0) {
    fetched.errorMessage = '暂无可播放媒体';
  }
  return fetched;
}
