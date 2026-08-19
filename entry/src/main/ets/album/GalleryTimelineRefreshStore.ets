/**
 * 需要「整页重拉时间轴 + 列表」时的全局信号（与 DeleteSyncStore 并列）。
 * - 预览页删除、上传成功、下拉刷新后 bump；
 * - 同时丢掉缩略图三层缓存（磁盘 JPEG / 内存 PixelMap / HTTP buffer），避免 NAS 新数据脏读；
 * - GalleryAlbumTab 在页面再次可见时消费版本号并触发刷新。
 */
import { GalleryHomeTimelineCache } from './GalleryHomeTimelineCache';
import { clearThumbPixCache } from './GalleryAlbumCommon';
import { GalleryThumbDiskCache, GALLERY_THUMB_CACHE_EPOCH_KEY } from './GalleryThumbDiskCache';
import { FnHttpClientGalleryOps } from '../network/fnHttpClient/FnHttpClientGalleryOps';

export class GalleryTimelineRefreshStore {
  static version: number = 0;

  /** 递增版本，通知图库 Tab 在合适时机执行 bootstrap；同时丢弃时间线快照与缩略图缓存 */
  static bump(): void {
    GalleryTimelineRefreshStore.version++;
    GalleryHomeTimelineCache.invalidate();
    GalleryThumbDiskCache.invalidateAll();
    clearThumbPixCache();
    FnHttpClientGalleryOps.clearAssetBufferCache();
    const old = AppStorage.get<number>(GALLERY_THUMB_CACHE_EPOCH_KEY) ?? 0;
    AppStorage.setOrCreate<number>(GALLERY_THUMB_CACHE_EPOCH_KEY, old + 1);
  }
}
