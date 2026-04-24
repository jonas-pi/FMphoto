import { UIContext } from '@kit.ArkUI';
import { runBatchDownloadGalleryItems } from '../../album/GalleryBatchDownload';
import { AppSession } from '../../auth/AppSession';
import { RecycleBinListItem } from '../../model/FnApiTypes';
import { recycleBinGalleryListForSelection } from './RecycleBinSelectionController';
import { formatRecycleApiTime, RB_PAGE_LIMIT, RB_SAFETY_MAX_OFFSET } from './RecycleBinTypes';

export interface RecycleBinActionsHost {
  getUIContext(): UIContext;
  baseUrl: string;
  loading: boolean;
  restoring: boolean;
  rbBatchDownloading: boolean;
  error: string;
  items: RecycleBinListItem[];
  selectedIds: number[];
  toast(msg: string): void;
  exitSelection(): void;
}

export async function recycleBinLoadAll(host: RecycleBinActionsHost): Promise<void> {
  host.loading = true;
  host.error = '';
  const client = AppSession.getClient();
  if (client === null) {
    host.loading = false;
    host.error = '未登录';
    return;
  }
  const endStr = formatRecycleApiTime(new Date());
  const startStr = '2000:01:01 00:00:00';
  const merged: RecycleBinListItem[] = [];
  let offset = 0;
  try {
    for (;;) {
      const res = await client.getRecycleBinList(offset, RB_PAGE_LIMIT, startStr, endStr);
      if (!res.success || res.data === undefined) {
        host.error = res.message ?? '回收站列表加载失败';
        break;
      }
      const batch = res.data.list;
      if (!Array.isArray(batch)) {
        break;
      }
      for (let i = 0; i < batch.length; i++) {
        const el = batch[i];
        if (typeof el === 'object' && el !== null) {
          merged.push(el as RecycleBinListItem);
        }
      }
      if (batch.length < RB_PAGE_LIMIT) {
        break;
      }
      offset += RB_PAGE_LIMIT;
      if (offset > RB_SAFETY_MAX_OFFSET) {
        break;
      }
    }
    host.items = merged;
  } catch (e) {
    host.error = String(e) || '回收站列表加载失败';
  }
  host.loading = false;
}

export async function recycleBinAskBatchDownloadQuality(
  host: RecycleBinActionsHost
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

export async function recycleBinConfirmBatchDownload(host: RecycleBinActionsHost): Promise<void> {
  if (host.selectedIds.length === 0 || host.rbBatchDownloading) {
    return;
  }
  const items = recycleBinGalleryListForSelection(host.items, host.selectedIds);
  if (items.length === 0) {
    host.toast('没有可下载的项');
    return;
  }
  host.rbBatchDownloading = true;
  try {
    await runBatchDownloadGalleryItems(
      host.baseUrl,
      items,
      (msg: string): void => {
        host.toast(msg);
      },
      (): Promise<'original' | 'thumb' | 'cancel'> => recycleBinAskBatchDownloadQuality(host)
    );
  } finally {
    host.rbBatchDownloading = false;
  }
}

export async function recycleBinConfirmRestore(host: RecycleBinActionsHost): Promise<void> {
  if (host.selectedIds.length === 0) {
    host.toast('请先选择要还原的照片');
    return;
  }
  try {
    const dlg = await host.getUIContext().getPromptAction().showDialog({
      title: '还原到相册',
      message: `将还原已选的 ${host.selectedIds.length} 项，是否继续？`,
      buttons: [
        { text: '取消', color: '#99000000' },
        { text: '还原', color: '#0284C7' }
      ]
    });
    if (dlg.index !== 1) {
      return;
    }
  } catch (_e) {
    return;
  }
  await recycleBinRunRestore(host);
}

export async function recycleBinRunRestore(host: RecycleBinActionsHost): Promise<void> {
  if (host.restoring || host.selectedIds.length === 0) {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  host.restoring = true;
  const ids = host.selectedIds.slice();
  const res = await client.restoreRecycleBinPhotos(ids);
  host.restoring = false;
  if (!res.success) {
    host.toast(res.message ?? '还原失败');
    return;
  }
  host.toast('已提交还原');
  host.exitSelection();
  await recycleBinLoadAll(host);
}
