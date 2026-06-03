import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { GalleryListItem } from '../../model/FnApiTypes';
import { CategoryGalleryNavStore } from '../../album/CategoryGalleryNavStore';
import { GalleryDeleteSyncStore } from '../../album/GalleryDeleteSyncStore';
import { GalleryTimelineRefreshStore } from '../../album/GalleryTimelineRefreshStore';
import {
  galleryItemsMatchingSelectedIds,
  runBatchDownloadGalleryItems
} from '../../album/GalleryBatchDownload';
import { AppSession } from '../../auth/AppSession';
import {
  buildCategoryGalleryInputOrderViewData,
  buildCategoryGalleryViewData,
  DayGroup
} from './CategoryGalleryTypes';
import { categoryGalleryItemIdOf } from './CategoryGallerySelectionController';

export interface CategoryGalleryBatchActionsHost {
  getUIContext(): UIContext;
  baseUrl: string;
  title: string;
  groups: DayGroup[];
  flatItems: GalleryListItem[];
  groupOffsets: number[];
  handledDeleteSyncVersion: number;
  selectedIds: string[];
  cgBatchDeleting: boolean;
  cgBatchDownloading: boolean;
  toast(msg: string): void;
  exitSelection(): void;
}

export async function categoryGalleryAskBatchDownloadQuality(
  host: CategoryGalleryBatchActionsHost
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

export async function categoryGalleryConfirmBatchDownload(host: CategoryGalleryBatchActionsHost): Promise<void> {
  if (host.selectedIds.length === 0 || host.cgBatchDownloading) {
    return;
  }
  const items = galleryItemsMatchingSelectedIds(host.flatItems, host.selectedIds);
  if (items.length === 0) {
    host.toast('没有可下载的项');
    return;
  }
  host.cgBatchDownloading = true;
  try {
    await runBatchDownloadGalleryItems(
      host.baseUrl,
      items,
      host.getUIContext().getHostContext() as common.UIAbilityContext,
      (msg: string): void => {
        host.toast(msg);
      },
      (): Promise<'original' | 'thumb' | 'cancel'> => categoryGalleryAskBatchDownloadQuality(host)
    );
  } finally {
    host.cgBatchDownloading = false;
  }
}

export async function categoryGalleryConfirmBatchDelete(host: CategoryGalleryBatchActionsHost): Promise<void> {
  if (host.selectedIds.length === 0 || host.cgBatchDeleting) {
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
  host.cgBatchDeleting = true;
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
    host.cgBatchDeleting = false;
  }
  GalleryTimelineRefreshStore.bump();
  host.toast(`已移入回收站 ${ok}/${ids.length}`);
  host.exitSelection();
  categoryGalleryApplyDeleteSyncIfNeeded(host);
}

export function categoryGalleryRebuildByFlatItems(host: CategoryGalleryBatchActionsHost): void {
  const useCreatedAt = CategoryGalleryNavStore.useCreatedAtGrouping;
  const viewData = CategoryGalleryNavStore.sourceKind === 'smart-category'
    ? buildCategoryGalleryInputOrderViewData(host.flatItems, CategoryGalleryNavStore.columnsPerRow)
    : buildCategoryGalleryViewData(host.flatItems, useCreatedAt, CategoryGalleryNavStore.columnsPerRow);
  host.groups = viewData.groups;
  host.groupOffsets = viewData.groupOffsets;
}

export function categoryGalleryApplyDeleteSyncIfNeeded(host: CategoryGalleryBatchActionsHost): void {
  if (host.handledDeleteSyncVersion === GalleryDeleteSyncStore.version) {
    return;
  }
  const ids = GalleryDeleteSyncStore.snapshotIds();
  if (ids.length === 0) {
    host.handledDeleteSyncVersion = GalleryDeleteSyncStore.version;
    return;
  }
  if (host.flatItems.length === 0 && CategoryGalleryNavStore.items.length > 0) {
    host.flatItems = CategoryGalleryNavStore.items.slice();
  }
  if (host.flatItems.length === 0) {
    host.handledDeleteSyncVersion = GalleryDeleteSyncStore.version;
    return;
  }
  const kept: GalleryListItem[] = [];
  let changed = false;
  for (let i = 0; i < host.flatItems.length; i++) {
    const id = categoryGalleryItemIdOf(host.flatItems[i]);
    if (id.length > 0 && ids.indexOf(id) >= 0) {
      changed = true;
      continue;
    }
    kept.push(host.flatItems[i]);
  }
  if (changed) {
    host.flatItems = kept;
    categoryGalleryRebuildByFlatItems(host);
    CategoryGalleryNavStore.items = kept.slice();
  }
  host.handledDeleteSyncVersion = GalleryDeleteSyncStore.version;
}
