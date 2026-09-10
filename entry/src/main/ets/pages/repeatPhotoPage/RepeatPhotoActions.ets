import { UIContext } from '@kit.ArkUI';
import { AppSession } from '../../auth/AppSession';
import {
  FnClientResult,
  RepeatPhotoGroup,
  RepeatPhotoListData,
  RepeatPhotoMergeData,
  RepeatPhotoTaskProgress,
  GalleryListItem
} from '../../model/FnApiTypes';
import { galleryListItemIdOf } from '../../album/GalleryAlbumCommon';
import { GalleryPreviewNavStore } from '../../album/GalleryPreviewNavStore';
import { GALLERY_PREVIEW_SOURCE_REPEAT_ID } from '../../album/GallerySharedTransition';
import { REPEAT_PHOTO_PAGE_SIZE, RepeatPhotoStep } from './RepeatPhotoLogic';

export interface RepeatPhotoActionsHost {
  getUIContext(): UIContext;
  baseUrl: string;
  loading: boolean;
  starting: boolean;
  merging: boolean;
  error: string;
  step: RepeatPhotoStep;
  groups: RepeatPhotoGroup[];
  totalCount: number;
  strategy: string;
  progress: RepeatPhotoTaskProgress;
  toast(msg: string): void;
  startTaskPolling(): void;
  stopTaskPolling(): void;
}

export async function repeatPhotoBootstrap(host: RepeatPhotoActionsHost): Promise<void> {
  host.loading = true;
  host.error = '';
  const client = AppSession.getClient();
  if (client === null) {
    host.loading = false;
    host.step = 'error';
    host.error = '未登录';
    return;
  }
  try {
    const pair: [FnClientResult<RepeatPhotoListData>, FnClientResult<RepeatPhotoTaskProgress>] = await Promise.all([
      client.getRepeatPhotoList(0, 1),
      client.getTaskPanelList()
    ]);
    const listRes: FnClientResult<RepeatPhotoListData> = pair[0];
    const taskRes: FnClientResult<RepeatPhotoTaskProgress> = pair[1];
    if (taskRes.success && taskRes.data !== undefined && taskRes.data.running) {
      host.progress = taskRes.data;
      host.step = 'checking';
      host.loading = false;
      host.startTaskPolling();
      return;
    }
    const count = listRes.success && listRes.data !== undefined ? listRes.data.count : 0;
    if (count > 0) {
      await repeatPhotoLoadGroups(host);
      return;
    }
    host.groups = [];
    host.totalCount = 0;
    host.strategy = '';
    host.step = 'start';
    host.loading = false;
  } catch (e) {
    host.loading = false;
    host.step = 'error';
    host.error = String(e) || '加载初始数据失败';
  }
}

export async function repeatPhotoLoadGroups(host: RepeatPhotoActionsHost): Promise<void> {
  const client = AppSession.getClient();
  if (client === null) {
    host.loading = false;
    host.step = 'error';
    host.error = '未登录';
    return;
  }
  host.loading = true;
  host.error = '';
  const merged: RepeatPhotoGroup[] = [];
  let offset = 0;
  let strategy = '';
  let total = 0;
  try {
    for (;;) {
      const res: FnClientResult<RepeatPhotoListData> = await client.getRepeatPhotoList(offset, REPEAT_PHOTO_PAGE_SIZE);
      if (!res.success || res.data === undefined) {
        if (merged.length === 0) {
          host.step = 'error';
          host.error = res.message ?? '加载页面失败';
        }
        break;
      }
      if (strategy.length === 0 && res.data.strategy.length > 0) {
        strategy = res.data.strategy;
      }
      total = Math.max(total, res.data.count);
      const batch = res.data.list;
      for (let i = 0; i < batch.length; i++) {
        merged.push(batch[i]);
      }
      if (batch.length < REPEAT_PHOTO_PAGE_SIZE) {
        break;
      }
      offset += REPEAT_PHOTO_PAGE_SIZE;
      if (offset > 3000) {
        break;
      }
    }
    host.groups = merged.slice();
    host.totalCount = Math.max(total, merged.length);
    host.strategy = strategy;
    host.step = merged.length > 0 ? 'list' : 'empty';
  } catch (e) {
    if (merged.length === 0) {
      host.step = 'error';
      host.error = String(e) || '加载页面失败';
    }
  } finally {
    host.loading = false;
  }
}

export async function repeatPhotoStartCheck(host: RepeatPhotoActionsHost, checkSimilarity: boolean): Promise<void> {
  if (host.starting || host.step === 'checking') {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  host.starting = true;
  const res: FnClientResult<Object> = await client.startRepeatPhotoCheck(checkSimilarity);
  host.starting = false;
  if (!res.success) {
    host.toast(res.message ?? (checkSimilarity ? '检查相似照片失败' : '检查重复照片失败'));
    return;
  }
  const next = new RepeatPhotoTaskProgress();
  next.running = true;
  next.name = checkSimilarity ? 'check-similar' : 'check-repeat';
  host.progress = next;
  host.strategy = checkSimilarity ? 'similar' : 'repeat';
  host.step = 'checking';
  host.startTaskPolling();
  void repeatPhotoPollTask(host);
}

export async function repeatPhotoPollTask(host: RepeatPhotoActionsHost): Promise<void> {
  const client = AppSession.getClient();
  if (client === null) {
    return;
  }
  const res: FnClientResult<RepeatPhotoTaskProgress> = await client.getTaskPanelList();
  if (!res.success || res.data === undefined) {
    return;
  }
  host.progress = res.data;
  if (res.data.running) {
    return;
  }
  if (host.step === 'checking' && res.data.taskId.length === 0 && res.data.name.length === 0) {
    return;
  }
  host.stopTaskPolling();
  if (res.data.error.length > 0) {
    host.step = 'error';
    host.error = res.data.error;
    return;
  }
  await repeatPhotoLoadGroups(host);
}

export async function repeatPhotoConfirmMergeGroup(host: RepeatPhotoActionsHost, group: RepeatPhotoGroup): Promise<void> {
  try {
    const dlg = await host.getUIContext().getPromptAction().showDialog({
      title: '合并此组',
      message: '确定要合并此组？将保留一项并继承其余项的数据，其余项将被移到回收站。',
      buttons: [
        { text: '取消', color: '#99000000' },
        { text: '合并', color: '#E5484D' }
      ]
    });
    if (dlg.index !== 1) {
      return;
    }
  } catch (_e) {
    return;
  }
  await repeatPhotoMerge(host, group.id);
}

export async function repeatPhotoConfirmMergeAll(host: RepeatPhotoActionsHost): Promise<void> {
  if (host.groups.length === 0) {
    return;
  }
  try {
    const dlg = await host.getUIContext().getPromptAction().showDialog({
      title: '合并所有',
      message: '确定要合并所有？将分别保留每组中的一项，其余项移到回收站。',
      buttons: [
        { text: '取消', color: '#99000000' },
        { text: '合并所有', color: '#E5484D' }
      ]
    });
    if (dlg.index !== 1) {
      return;
    }
  } catch (_e) {
    return;
  }
  await repeatPhotoMerge(host, '');
}

export async function repeatPhotoMerge(host: RepeatPhotoActionsHost, groupId: string): Promise<void> {
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  if (host.merging) {
    return;
  }
  host.merging = true;
  const res: FnClientResult<RepeatPhotoMergeData> = await client.mergeRepeatPhotos(groupId);
  host.merging = false;
  if (!res.success) {
    host.toast(res.message ?? '合并失败');
    return;
  }
  const recycled = res.data !== undefined ? res.data.recycledCount : 0;
  host.toast(recycled > 0 ? `已成功将 ${recycled} 项内容移到回收站` : '合并成功');
  await repeatPhotoLoadGroups(host);
}

export function repeatPhotoHasPendingResults(host: RepeatPhotoActionsHost): boolean {
  return host.step === 'list' && host.groups.length > 0 && !host.merging;
}

/**
 * 退出结果页：NAS 没有「整次丢弃、不做任何更改」接口。
 * exclude 只接受 PhotoId / Group，type=All 会返回 invalid type；
 * 官方 Web 也是直接离开，结果仍留在 /repeat-photo/list，下次进入可继续处理。
 * 返回 false 表示用户取消，应留在结果页。
 */
export async function repeatPhotoExitWithoutAction(host: RepeatPhotoActionsHost): Promise<boolean> {
  if (!repeatPhotoHasPendingResults(host)) {
    return true;
  }
  try {
    const dlg = await host.getUIContext().getPromptAction().showDialog({
      title: '退出',
      message: '本次检查结果会保留，下次进入可继续处理。',
      buttons: [
        { text: '取消', color: '#99000000' },
        { text: '退出', color: '#E5484D' }
      ]
    });
    return dlg.index === 1;
  } catch (_e) {
    return false;
  }
}

export async function repeatPhotoKeepGroup(host: RepeatPhotoActionsHost, group: RepeatPhotoGroup): Promise<void> {
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  const res: FnClientResult<Object> = await client.excludeRepeatPhotoGroup(group.id);
  if (!res.success) {
    host.toast(res.message ?? '保留失败');
    return;
  }
  const next: RepeatPhotoGroup[] = [];
  for (let i = 0; i < host.groups.length; i++) {
    if (host.groups[i].id !== group.id) {
      next.push(host.groups[i]);
    }
  }
  host.groups = next;
  host.totalCount = Math.max(0, host.totalCount - 1);
  if (next.length === 0) {
    host.step = 'empty';
  }
}

export function repeatPhotoOpenPreview(host: RepeatPhotoActionsHost, group: RepeatPhotoGroup, index: number): void {
  if (group.photos.length === 0) {
    host.toast('找不到该照片');
    return;
  }
  const list: GalleryListItem[] = group.photos.slice();
  const start = Math.max(0, Math.min(index, list.length - 1));
  GalleryPreviewNavStore.openPreview(
    host.getUIContext(),
    host.baseUrl,
    list,
    start,
    GALLERY_PREVIEW_SOURCE_REPEAT_ID
  );
}

export function repeatPhotoThumbId(item: GalleryListItem, fallback: string): string {
  const id = galleryListItemIdOf(item);
  return id.length > 0 ? id : fallback;
}
