/**
 * 预览页删除后的轻量同步仓：
 * - 预览页删除成功后写入 deletedIds + version；
 * - 背后页面（GalleryAlbumTab / CategoryGallery）在 onPageShow 里按 version 增量处理。
 *
 * 目标：只做增量删除，不触发整页重载，尽量保留用户当前滚动位置。
 */
export class GalleryDeleteSyncStore {
  static version: number = 0;
  static deletedIds: string[] = [];
  private static readonly MAX_IDS: number = 500;

  static markDeleted(photoId: string): void {
    const id = photoId.trim();
    if (id.length === 0) {
      return;
    }
    if (GalleryDeleteSyncStore.deletedIds.indexOf(id) < 0) {
      GalleryDeleteSyncStore.deletedIds.push(id);
      if (GalleryDeleteSyncStore.deletedIds.length > GalleryDeleteSyncStore.MAX_IDS) {
        GalleryDeleteSyncStore.deletedIds.shift();
      }
    }
    GalleryDeleteSyncStore.version++;
  }

  static snapshotIds(): string[] {
    return GalleryDeleteSyncStore.deletedIds.slice();
  }
}

