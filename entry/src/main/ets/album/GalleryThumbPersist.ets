/**
 * 缩略图磁盘缓存调度：从时间线条目 / 相册封面 URI 生成 cacheKey 并触发落盘。
 * NAS 增删/封面更新后由 GalleryTimelineRefreshStore.bump 丢掉旧缓存，再调用本文件重新落盘。
 */
import { GalleryListItem } from '../model/FnApiTypes';
import { isVideoItem, nasUrl, pickThumbForGridDensity } from './GalleryAlbumCommon';
import {
  GalleryThumbDiskCache,
  GALLERY_THUMB_CACHE_EPOCH_KEY,
  THUMB_DISK_ALBUM_COVER,
  THUMB_DISK_FIRST_SCREEN
} from './GalleryThumbDiskCache';
import {
  GalleryViewGranularity,
  galleryViewGranularityColumns
} from './galleryAlbumTab/GalleryAlbumGranularity';

function densityOf(mode: GalleryViewGranularity): 'day' | 'month' | 'year' {
  if (mode === GalleryViewGranularity.MONTH) {
    return 'month';
  }
  if (mode === GalleryViewGranularity.YEAR) {
    return 'year';
  }
  return 'day';
}

/** 与 GalleryAlbumMainModeView.currentListCachedCount 对齐 */
function listCachedCountOf(mode: GalleryViewGranularity): number {
  if (mode === GalleryViewGranularity.YEAR) {
    return 14;
  }
  if (mode === GalleryViewGranularity.MONTH) {
    return 8;
  }
  return 3;
}

function diskCacheKey(fullUrl: string, autoCropBlack: boolean): string {
  return `${autoCropBlack ? '1' : '0'}|${fullUrl}`;
}

export function ensureGalleryThumbCacheEpochStorage(): void {
  AppStorage.setOrCreate<number>(GALLERY_THUMB_CACHE_EPOCH_KEY, 0);
}

/**
 * 固化时间线首屏部分缩略图（可视约一屏 + 少量 List cachedCount 预加载带）。
 * 网格组件会自行 decode；这里只锁定集合并把 JPEG 写入磁盘。
 */
export function scheduleGalleryFirstScreenThumbPersist(
  baseUrl: string,
  items: GalleryListItem[],
  mode: GalleryViewGranularity
): void {
  const columns = galleryViewGranularityColumns(mode);
  const maxCount = GalleryThumbDiskCache.recommendedFirstScreenCount(columns, listCachedCountOf(mode));
  const density = densityOf(mode);
  const keys: string[] = [];
  for (let i = 0; i < items.length && keys.length < maxCount; i++) {
    const rel = pickThumbForGridDensity(items[i], density);
    if (rel.length <= 0) {
      continue;
    }
    const url = nasUrl(baseUrl, rel);
    if (url.length <= 0) {
      continue;
    }
    keys.push(diskCacheKey(url, isVideoItem(items[i])));
  }
  GalleryThumbDiskCache.lockFirstScreen(keys);
  for (let i = 0; i < keys.length; i++) {
    GalleryThumbDiskCache.ensurePersisted(keys[i], THUMB_DISK_FIRST_SCREEN);
  }
}

/** 相册页全部封面：媒体分类卡、人物/智能预览格、最近/收藏快捷入口。 */
export function scheduleGalleryAlbumCoverPersist(coverUrls: string[]): void {
  const keys: string[] = [];
  for (let i = 0; i < coverUrls.length; i++) {
    const url = coverUrls[i];
    if (url.length <= 0) {
      continue;
    }
    keys.push(diskCacheKey(url, false));
  }
  GalleryThumbDiskCache.replaceAlbumCovers(keys);
  for (let i = 0; i < keys.length; i++) {
    GalleryThumbDiskCache.ensurePersisted(keys[i], THUMB_DISK_ALBUM_COVER);
  }
}
