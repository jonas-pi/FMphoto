/**
 * 需要「整页重拉时间轴 + 列表」时的全局信号（与 DeleteSyncStore 并列）。
 * - 预览页删除、上传成功后 bump；
 * - GalleryAlbumTab 在页面再次可见时消费版本号并触发刷新（带防抖，避免与手动连点刷新叠加风暴）。
 */
import { GalleryHomeTimelineCache } from './GalleryHomeTimelineCache';

export class GalleryTimelineRefreshStore {
  static version: number = 0;

  /** 递增版本，通知图库 Tab 在合适时机执行 bootstrap；同时丢弃主时间线内存快照，避免与网络状态不一致 */
  static bump(): void {
    GalleryTimelineRefreshStore.version++;
    GalleryHomeTimelineCache.invalidate();
  }
}
