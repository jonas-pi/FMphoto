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

/** AppStorage key：供相册 tab 通过 @StorageProp + @Watch 感知相册结构变化 */
export const GALLERY_ALBUMS_VERSION_KEY: string = 'galleryAlbumsVersion';

export class GalleryTimelineRefreshStore {
  static version: number = 0;
  /**
   * 相册结构版本：新建 / 删除 / 改名 / 归档照片进相册后递增。
   * 与 version 分开：改相册结构不需要丢弃缩略图缓存，只让「相册 tab」重拉一次列表。
   */
  static albumsVersion: number = 0;

  /** 递增版本，通知图库 Tab 在合适时机执行 bootstrap；同时丢弃时间线快照与缩略图缓存 */
  static bump(): void {
    GalleryTimelineRefreshStore.version++;
    GalleryHomeTimelineCache.invalidate();
    // 只丢时间线首屏：相册封面按 URL 复用，服务端换封面会得到新 URL，不必整页重下
    GalleryThumbDiskCache.invalidateFirstScreen();
    clearThumbPixCache();
    FnHttpClientGalleryOps.clearAssetBufferCache();
    const old = AppStorage.get<number>(GALLERY_THUMB_CACHE_EPOCH_KEY) ?? 0;
    AppStorage.setOrCreate<number>(GALLERY_THUMB_CACHE_EPOCH_KEY, old + 1);
  }

  /** 只通知相册列表刷新；不动缩略图缓存（封面靠 URL 差异自然更新）。 */
  static bumpAlbums(): void {
    GalleryTimelineRefreshStore.albumsVersion++;
    AppStorage.setOrCreate<number>(
      GALLERY_ALBUMS_VERSION_KEY,
      GalleryTimelineRefreshStore.albumsVersion
    );
  }
}
