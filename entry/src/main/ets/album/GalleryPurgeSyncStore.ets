/**
 * 回收站「彻底删除」同步仓。
 *
 * 与 GalleryDeleteSyncStore 分开：那边记的是「移入回收站」的 id，
 * 这些 id 随后会正常出现在回收站列表里，不能拿来过滤回收站。
 * 这里只记永久删除的数字 id，供回收站页在预览返回后增量移除，
 * 避免整页重载、保留滚动位置。
 */
export const GALLERY_PURGE_SYNC_VERSION_KEY: string = 'galleryPurgeSyncVersion';

export class GalleryPurgeSyncStore {
  static version: number = 0;
  static purgedIds: number[] = [];
  private static readonly MAX_IDS: number = 500;

  static markPurged(numericId: number): void {
    const n = Math.floor(Number(numericId));
    if (!Number.isFinite(n) || n <= 0) {
      return;
    }
    if (GalleryPurgeSyncStore.purgedIds.indexOf(n) < 0) {
      GalleryPurgeSyncStore.purgedIds.push(n);
      if (GalleryPurgeSyncStore.purgedIds.length > GalleryPurgeSyncStore.MAX_IDS) {
        GalleryPurgeSyncStore.purgedIds.shift();
      }
    }
    GalleryPurgeSyncStore.version++;
    // 回收站页用 @StorageProp + @Watch 接；不论它是以路由页还是 Navigation 内容存活都能收到。
    try {
      if (AppStorage.has(GALLERY_PURGE_SYNC_VERSION_KEY)) {
        AppStorage.set<number>(GALLERY_PURGE_SYNC_VERSION_KEY, GalleryPurgeSyncStore.version);
      } else {
        AppStorage.setOrCreate<number>(GALLERY_PURGE_SYNC_VERSION_KEY, GalleryPurgeSyncStore.version);
      }
    } catch (_e) {
    }
  }
}
