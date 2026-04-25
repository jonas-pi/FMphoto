import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppSession } from '../../auth/AppSession';
import { GalleryListItem } from '../../model/FnApiTypes';
import { galleryItemsMatchingSelectedIds, runBatchDownloadGalleryItems } from '../GalleryBatchDownload';
import { GalleryDeleteSyncStore } from '../GalleryDeleteSyncStore';
import { GalleryTimelineRefreshStore } from '../GalleryTimelineRefreshStore';
import { GalleryAlbumDaySectionState } from './GalleryAlbumState';

export interface GalleryAlbumBatchActionsHost {
  getUIContext(): UIContext;
  baseUrl: string;
  inSearchMode: boolean;
  gallerySelectedIds: string[];
  galleryBatchDeleting: boolean;
  galleryBatchDownloading: boolean;
  searchResults: GalleryListItem[];
  sections: GalleryAlbumDaySectionState[];
  handledDeleteSyncVersion: number;
  toast(msg: string): void;
  requestBootstrap(debounced: boolean): void;
  exitGallerySelection(): void;
  itemIdOf(item: GalleryListItem): string;
  flatItems(): GalleryListItem[];
  rebuildFlow(): void;
}

export async function galleryAlbumConfirmAndBatchDelete(host: GalleryAlbumBatchActionsHost): Promise<void> {
  if (host.gallerySelectedIds.length === 0 || host.galleryBatchDeleting) {
    return;
  }
  try {
    const dialog = await host.getUIContext().getPromptAction().showDialog({
      title: '批量移入回收站',
      message: '将所选照片/视频移入回收站？',
      buttons: [
        { text: '取消', color: '#99000000' },
        { text: '移入回收站', color: '#E5484D' }
      ]
    });
    if (dialog.index !== 1) {
      return;
    }
  } catch (_e) {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  host.galleryBatchDeleting = true;
  const ids = host.gallerySelectedIds.slice();
  let ok = 0;
  try {
    for (let i = 0; i < ids.length; i++) {
      const result = await client.addPhotoToRecycleBin(ids[i], 22000);
      if (result.success) {
        ok++;
        GalleryDeleteSyncStore.markDeleted(ids[i]);
      }
    }
  } finally {
    host.galleryBatchDeleting = false;
  }
  GalleryTimelineRefreshStore.bump();
  host.exitGallerySelection();
  host.toast(`已移入回收站 ${ok}/${ids.length}`);
  host.requestBootstrap(true);
}

export async function galleryAlbumAskBatchDownloadImageQuality(
  host: GalleryAlbumBatchActionsHost
): Promise<'original' | 'thumb' | 'cancel'> {
  try {
    const choice = await host.getUIContext().getPromptAction().showActionMenu({
      title: '批量下载图片',
      buttons: [
        { text: '原图（体积较大）', color: '#007AFF' },
        { text: '缩略图（更快）', color: '#007AFF' }
      ]
    });
    if (choice.index < 0) {
      return 'cancel';
    }
    return choice.index === 0 ? 'original' : 'thumb';
  } catch (_e) {
    return 'cancel';
  }
}

export async function galleryAlbumConfirmAndBatchDownload(host: GalleryAlbumBatchActionsHost): Promise<void> {
  if (host.gallerySelectedIds.length === 0 || host.galleryBatchDownloading) {
    return;
  }
  const list = host.inSearchMode ? host.searchResults : host.flatItems();
  const items = galleryItemsMatchingSelectedIds(list, host.gallerySelectedIds);
  if (items.length === 0) {
    host.toast('没有可下载的项');
    return;
  }
  host.galleryBatchDownloading = true;
  try {
    await runBatchDownloadGalleryItems(
      host.baseUrl,
      items,
      host.getUIContext().getHostContext() as common.UIAbilityContext,
      (msg: string): void => {
        host.toast(msg);
      },
      (): Promise<'original' | 'thumb' | 'cancel'> => galleryAlbumAskBatchDownloadImageQuality(host)
    );
  } finally {
    host.galleryBatchDownloading = false;
  }
}

export function galleryAlbumApplyDeleteSyncIfNeeded(host: GalleryAlbumBatchActionsHost): void {
  if (host.handledDeleteSyncVersion === GalleryDeleteSyncStore.version) {
    return;
  }
  const ids = GalleryDeleteSyncStore.snapshotIds();
  if (ids.length === 0) {
    host.handledDeleteSyncVersion = GalleryDeleteSyncStore.version;
    return;
  }
  if (host.sections.length === 0 && host.searchResults.length === 0) {
    return;
  }
  let changed = false;
  for (let si = host.sections.length - 1; si >= 0; si--) {
    const section = host.sections[si];
    const keys = Array.from(section.slotByOffset.keys());
    for (let j = 0; j < keys.length; j++) {
      const off = keys[j];
      const item = section.slotByOffset.get(off);
      if (item === undefined) {
        continue;
      }
      const id = host.itemIdOf(item);
      if (id.length > 0 && ids.indexOf(id) >= 0) {
        section.slotByOffset.delete(off);
        changed = true;
      }
    }
    if (section.slotByOffset.size === 0) {
      host.sections.splice(si, 1);
    }
  }
  if (host.searchResults.length > 0) {
    const kept: GalleryListItem[] = [];
    for (let i = 0; i < host.searchResults.length; i++) {
      const id = host.itemIdOf(host.searchResults[i]);
      if (id.length > 0 && ids.indexOf(id) >= 0) {
        changed = true;
        continue;
      }
      kept.push(host.searchResults[i]);
    }
    if (kept.length !== host.searchResults.length) {
      host.searchResults = kept;
    }
  }
  if (changed) {
    host.rebuildFlow();
  }
  host.handledDeleteSyncVersion = GalleryDeleteSyncStore.version;
}
