import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppSession } from '../../auth/AppSession';
import { GalleryListItem } from '../../model/FnApiTypes';
import { galleryItemsMatchingSelectedIds, runBatchDownloadGalleryItemsInBackground } from '../../album/GalleryBatchDownload';
import {
  LivePhotoSaveChoice,
  resolveLivePhotoWriteAuthorized
} from '../../album/livephoto/LivePhotoSaveActionSheet';
import { GalleryDeleteSyncStore } from '../../album/GalleryDeleteSyncStore';
import { GalleryTimelineRefreshStore } from '../../album/GalleryTimelineRefreshStore';

export interface FolderBrowseBatchActionsHost {
  getUIContext(): UIContext;
  baseUrl: string;
  mediaItems: GalleryListItem[];
  selectedIds: string[];
  batchDeleting: boolean;
  batchDownloading: boolean;
  toast(msg: string): void;
  exitSelection(): void;
  removeMediaByIds(ids: string[]): void;
  askLivePhotoSave(): Promise<LivePhotoSaveChoice>;
  askChoice(title: string, buttons: string[]): Promise<number>;
}

export async function folderBrowseAskBatchDownloadQuality(
  host: FolderBrowseBatchActionsHost
): Promise<'original' | 'thumb' | 'cancel'> {
  const choiceIdx = await host.askChoice('批量下载图片', [
    '原图（体积较大）',
    '缩略图（更快）'
  ]);
  if (choiceIdx < 0) {
    return 'cancel';
  }
  return choiceIdx === 0 ? 'original' : 'thumb';
}

export async function folderBrowseConfirmBatchDownload(host: FolderBrowseBatchActionsHost): Promise<void> {
  if (host.selectedIds.length === 0 || host.batchDownloading) {
    return;
  }
  const items = galleryItemsMatchingSelectedIds(host.mediaItems, host.selectedIds);
  if (items.length === 0) {
    host.toast('没有可下载的项');
    return;
  }
  const authorized = await resolveLivePhotoWriteAuthorized(items, (): Promise<LivePhotoSaveChoice> => {
    return host.askLivePhotoSave();
  });
  if (authorized === undefined) {
    return;
  }
  host.batchDownloading = true;
  try {
    runBatchDownloadGalleryItemsInBackground(
      host.baseUrl,
      items,
      host.getUIContext().getHostContext() as common.UIAbilityContext,
      (msg: string): void => {
        host.toast(msg);
      },
      (): Promise<'original' | 'thumb' | 'cancel'> => folderBrowseAskBatchDownloadQuality(host),
      authorized
    );
    host.exitSelection();
  } finally {
    host.batchDownloading = false;
  }
}

export async function folderBrowseConfirmBatchDelete(host: FolderBrowseBatchActionsHost): Promise<void> {
  if (host.selectedIds.length === 0 || host.batchDeleting) {
    return;
  }
  try {
    const dlg = await host.getUIContext().getPromptAction().showDialog({
      title: '批量移入回收站',
      message: '将所选照片/视频移入回收站？',
      buttons: [
        { text: '取消', color: '#99000000' },
        { text: '移入回收站', color: '#E5484D' }
      ]
    });
    if (dlg.index !== 1) {
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
  host.batchDeleting = true;
  const ids = host.selectedIds.slice();
  let ok = 0;
  try {
    for (let i = 0; i < ids.length; i++) {
      const res = await client.addPhotoToRecycleBin(ids[i], 22000);
      if (res.success) {
        ok++;
        GalleryDeleteSyncStore.markDeleted(ids[i]);
      }
    }
  } finally {
    host.batchDeleting = false;
  }
  GalleryTimelineRefreshStore.bump();
  host.toast(`已移入回收站 ${ok}/${ids.length}`);
  host.removeMediaByIds(ids);
  host.exitSelection();
}
