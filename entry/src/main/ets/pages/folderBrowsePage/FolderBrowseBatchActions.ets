import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppSession } from '../../auth/AppSession';
import { FnClientResult, GalleryListItem, PhotoFolderListData, PhotoFolderListItem } from '../../model/FnApiTypes';
import { galleryItemsMatchingSelectedIds, runBatchDownloadGalleryItemsInBackground } from '../../album/GalleryBatchDownload';
import {
  LivePhotoSaveChoice,
  resolveLivePhotoWriteAuthorized
} from '../../album/livephoto/LivePhotoSaveActionSheet';
import { GalleryDeleteSyncStore } from '../../album/GalleryDeleteSyncStore';
import { GalleryTimelineRefreshStore } from '../../album/GalleryTimelineRefreshStore';
import {
  folderBrowseDirPathFromSelectionId,
  folderBrowseFoldersFromList,
  folderBrowseIsDirSelectionId,
  folderBrowseMergeMediaUnique,
  folderBrowseSelectionHasFolder
} from './FolderBrowseLogic';
import { FOLDER_BROWSE_PAGE_SIZE } from './FolderBrowseTypes';

const FOLDER_COLLECT_MAX_ITEMS: number = 4000;
const FOLDER_COLLECT_MAX_FOLDERS: number = 200;
const FOLDER_COLLECT_MAX_DEPTH: number = 16;

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

async function folderBrowseCollectMediaUnderFolder(
  folderPath: string,
  acc: GalleryListItem[]
): Promise<GalleryListItem[]> {
  const client = AppSession.getClient();
  if (client === null || folderPath.trim().length === 0) {
    return acc;
  }
  const queue: string[] = [folderPath.trim()];
  const depths: number[] = [0];
  const seen = new Set<string>();
  let walked = 0;
  let cursor = 0;
  let out = acc;
  while (cursor < queue.length && walked < FOLDER_COLLECT_MAX_FOLDERS && out.length < FOLDER_COLLECT_MAX_ITEMS) {
    const path = queue[cursor];
    const depth = depths[cursor];
    cursor++;
    if (seen.has(path)) {
      continue;
    }
    seen.add(path);
    walked++;
    let offset = 0;
    let hasMore = true;
    while (hasMore && out.length < FOLDER_COLLECT_MAX_ITEMS) {
    const fileRes: FnClientResult<GalleryListItem[]> = await client.getFolderViewFileList(
        path,
        FOLDER_BROWSE_PAGE_SIZE,
        offset,
        false,
        2,
        20000
      );
      if (!fileRes.success || fileRes.data === undefined) {
        break;
      }
      const page = fileRes.data;
      out = folderBrowseMergeMediaUnique(out, page);
      offset += page.length;
      hasMore = page.length >= FOLDER_BROWSE_PAGE_SIZE;
    }
    if (depth >= FOLDER_COLLECT_MAX_DEPTH || walked >= FOLDER_COLLECT_MAX_FOLDERS) {
      continue;
    }
    const folderRes: FnClientResult<PhotoFolderListData> = await client.getFolderViewFolderList(path, false, 2, 20000);
    if (!folderRes.success || folderRes.data === undefined) {
      continue;
    }
    const raw: PhotoFolderListItem[] = folderRes.data.list ?? folderRes.data.items ?? [];
    const children = folderBrowseFoldersFromList(raw);
    for (let i = 0; i < children.length; i++) {
      const childPath = children[i].path;
      if (childPath.length > 0 && !seen.has(childPath)) {
        queue.push(childPath);
        depths.push(depth + 1);
      }
    }
  }
  return out;
}

async function folderBrowseResolveDownloadItems(host: FolderBrowseBatchActionsHost): Promise<GalleryListItem[]> {
  const mediaIds: string[] = [];
  const folderPaths: string[] = [];
  for (let i = 0; i < host.selectedIds.length; i++) {
    const id = host.selectedIds[i];
    if (folderBrowseIsDirSelectionId(id)) {
      const path = folderBrowseDirPathFromSelectionId(id);
      if (path.length > 0) {
        folderPaths.push(path);
      }
    } else if (id.length > 0) {
      mediaIds.push(id);
    }
  }
  let items = galleryItemsMatchingSelectedIds(host.mediaItems, mediaIds);
  for (let i = 0; i < folderPaths.length; i++) {
    items = await folderBrowseCollectMediaUnderFolder(folderPaths[i], items);
  }
  return items;
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
  host.batchDownloading = true;
  try {
    const items = await folderBrowseResolveDownloadItems(host);
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
  if (folderBrowseSelectionHasFolder(host.selectedIds)) {
    host.toast('所选包含文件夹，无法移入回收站');
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
