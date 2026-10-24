import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { runBatchDownloadGalleryItemsInBackground } from '../../album/GalleryBatchDownload';
import {
  LivePhotoSaveChoice,
  resolveLivePhotoWriteAuthorized
} from '../../album/livephoto/LivePhotoSaveActionSheet';
import { AppSession } from '../../auth/AppSession';
import { fnDiagRecord } from '../../common/FnDiagLog';
import { FnHttpClient } from '../../network/FnHttpClient';
import { RecycleBinListItem } from '../../model/FnApiTypes';
import { recycleBinGalleryListForSelection, recycleBinNumericIdOf } from './RecycleBinSelectionController';
import {
  formatRecycleApiTime,
  RB_DELETE_BATCH_SIZE,
  RB_DELETE_SETTLE_POLL_MS,
  RB_DELETE_SETTLE_TIMEOUT_MS,
  RB_PAGE_LIMIT,
  RB_SAFETY_MAX_OFFSET
} from './RecycleBinTypes';

export interface RecycleBinActionsHost {
  getUIContext(): UIContext;
  baseUrl: string;
  loading: boolean;
  restoring: boolean;
  rbBatchDownloading: boolean;
  rbBackgroundLoading: boolean;
  /** 列表是否完整拉完（中途失败或撞到分页安全上限时为 false） */
  rbListComplete: boolean;
  error: string;
  items: RecycleBinListItem[];
  selectedIds: number[];
  /** 正在永久删除：挡住还原与下载 */
  clearing: boolean;
  /** 用户请求停止：批与批之间生效，已提交给 NAS 的批次无法撤回 */
  clearingCancelRequested: boolean;
  /** 已尝试提交的 id 数 / 本次总 id 数，用于进度显示 */
  clearingSubmitted: number;
  clearingTotal: number;
  toast(msg: string): void;
  exitSelection(): void;
  askLivePhotoSave(): Promise<LivePhotoSaveChoice>;
  askChoice(title: string, buttons: string[]): Promise<number>;
}

export async function recycleBinLoadAll(host: RecycleBinActionsHost): Promise<void> {
  host.loading = true;
  host.rbBackgroundLoading = false;
  // 完整拉完之前为 false：中途失败或撞到分页安全上限时，列表只是部分内容。
  host.rbListComplete = false;
  host.error = '';
  host.items = [];
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
        if (merged.length === 0) {
          const msg: string = res.message !== undefined && res.message.length > 0 ? res.message : 'unknown';
          fnDiagRecord('E', 'RecycleBin', `list load failed ${msg}`);
          host.error = res.message ?? '回收站列表加载失败';
        }
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
      host.items = merged.slice();
      if (host.loading) {
        host.loading = false;
      }
      if (batch.length < RB_PAGE_LIMIT) {
        // 不足一页 = 全部拉完
        host.rbListComplete = true;
        break;
      }
      host.rbBackgroundLoading = true;
      offset += RB_PAGE_LIMIT;
      if (offset > RB_SAFETY_MAX_OFFSET) {
        // 撞到分页安全上限：后面的项目没拉到，列表不完整
        fnDiagRecord('W', 'RecycleBin', `list truncated at offset=${offset}`);
        break;
      }
    }
    host.items = merged.slice();
  } catch (e) {
    if (merged.length === 0) {
      fnDiagRecord('E', 'RecycleBin', `list load failed ${String(e)}`);
      host.error = String(e) || '回收站列表加载失败';
    }
  }
  host.rbBackgroundLoading = false;
  host.loading = false;
}

export async function recycleBinAskBatchDownloadQuality(
  host: RecycleBinActionsHost
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

export async function recycleBinConfirmBatchDownload(host: RecycleBinActionsHost): Promise<void> {
  if (host.selectedIds.length === 0 || host.rbBatchDownloading || host.clearing) {
    return;
  }
  const items = recycleBinGalleryListForSelection(host.items, host.selectedIds);
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
  host.rbBatchDownloading = true;
  try {
    runBatchDownloadGalleryItemsInBackground(
      host.baseUrl,
      items,
      host.getUIContext().getHostContext() as common.UIAbilityContext,
      (msg: string): void => {
        host.toast(msg);
      },
      (): Promise<'original' | 'thumb' | 'cancel'> => recycleBinAskBatchDownloadQuality(host),
      authorized
    );
    host.exitSelection();
  } finally {
    host.rbBatchDownloading = false;
  }
}

export async function recycleBinConfirmRestore(host: RecycleBinActionsHost): Promise<void> {
  if (host.clearing) {
    return;
  }
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
  if (host.restoring || host.selectedIds.length === 0 || host.clearing) {
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
    const msg: string = res.message !== undefined && res.message.length > 0 ? res.message : 'unknown';
    fnDiagRecord('E', 'RecycleBin', `restore failed ${msg}`);
    host.toast(res.message ?? '还原失败');
    return;
  }
  host.toast('已提交还原');
  host.exitSelection();
  await recycleBinLoadAll(host);
}

/** 可用于彻底删除的数字 id：delete 接口只认正整数 id。 */
export function recycleBinClearableIds(items: RecycleBinListItem[]): number[] {
  const out: number[] = [];
  for (let i = 0; i < items.length; i++) {
    const nid = recycleBinNumericIdOf(items[i]);
    if (nid > 0) {
      out.push(nid);
    }
  }
  return out;
}

function rbDelayMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

/**
 * 等待 NAS 真正把这批 id 删掉。
 *
 * delete 返回 200 只表示任务已受理（taskInfo.done 受理瞬间为 false），
 * 所以这里把列表整份翻完，确认这批 id 一个都不在了才算删完。
 * 返回 false 表示还没确认删完（没等到 / 请求失败 / 列表翻不完）。
 */
async function recycleBinAwaitDeleted(
  client: FnHttpClient,
  ids: number[]
): Promise<boolean> {
  const wanted: Set<number> = new Set<number>();
  for (let i = 0; i < ids.length; i++) {
    wanted.add(ids[i]);
  }
  const startStr = '2000:01:01 00:00:00';
  const deadline = Date.now() + RB_DELETE_SETTLE_TIMEOUT_MS;
  for (;;) {
    // 每轮重新取当前时间：删除期间可能又有项目进入回收站。
    const endStr = formatRecycleApiTime(new Date());
    let offset = 0;
    let remaining = false;
    let incomplete = false;
    for (;;) {
      const res = await client.getRecycleBinList(offset, RB_PAGE_LIMIT, startStr, endStr);
      if (!res.success || res.data === undefined || !Array.isArray(res.data.list)) {
        return false;
      }
      const batch = res.data.list;
      for (let i = 0; i < batch.length; i++) {
        const nid = recycleBinNumericIdOf(batch[i]);
        if (nid > 0 && wanted.has(nid)) {
          remaining = true;
        }
      }
      if (batch.length < RB_PAGE_LIMIT) {
        // 不足一页 = 整份列表已翻完
        break;
      }
      offset += RB_PAGE_LIMIT;
      if (offset > RB_SAFETY_MAX_OFFSET) {
        // 翻不完，判定不完整
        incomplete = true;
        break;
      }
    }
    if (!incomplete && !remaining) {
      return true;
    }
    if (Date.now() >= deadline) {
      return false;
    }
    await rbDelayMs(RB_DELETE_SETTLE_POLL_MS);
  }
}

/**
 * 清空回收站：确认 → 分批 POST recycle-bin/delete。
 *
 * NAS 没有「清空全部」开关，清空就是把回收站里的数字 id 全部放进 ids 数组。
 */
export async function recycleBinConfirmClearAll(host: RecycleBinActionsHost): Promise<void> {
  if (host.clearing) {
    return;
  }
  // 列表还在翻页时不能报数量：items.length 只是已加载到的那部分。
  if (host.rbBackgroundLoading) {
    host.toast('回收站还在加载，请稍候');
    return;
  }
  // 列表没拉完（中途失败或撞到分页上限）时，清空只能删掉一部分，不能说「全部」。
  if (!host.rbListComplete) {
    host.toast('回收站列表未加载完整，请刷新后再试');
    return;
  }
  if (host.items.length === 0) {
    return;
  }
  const ids = recycleBinClearableIds(host.items);
  const skipped = host.items.length - ids.length;
  let message = '将永久删除回收站中的全部项目，无法恢复。';
  if (skipped > 0) {
    message = `${message}\n其中 ${skipped} 项没有可用的数字 ID，无法通过此接口删除。`;
  }
  try {
    const dlg = await host.getUIContext().getPromptAction().showDialog({
      title: '清空回收站',
      message: message,
      buttons: [
        { text: '取消', color: '#99000000' },
        { text: '清空', color: '#E5484D' }
      ]
    });
    if (dlg.index !== 1) {
      return;
    }
  } catch (_e) {
    return;
  }
  await recycleBinRunClearAll(host);
}

export async function recycleBinRunClearAll(host: RecycleBinActionsHost): Promise<void> {
  if (host.clearing) {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  const ids = recycleBinClearableIds(host.items);
  if (ids.length === 0) {
    host.toast('没有可删除的项目');
    return;
  }
  // 先退出多选：清空与还原/下载不能并发。
  host.exitSelection();
  host.clearing = true;
  host.clearingCancelRequested = false;
  host.clearingTotal = ids.length;
  host.clearingSubmitted = 0;
  let failedIds = 0;
  let failedBatches = 0;
  let canceled = false;
  /** 是否已确认 NAS 把这批 id 真的删掉了 */
  let settled = false;
  try {
    for (let start = 0; start < ids.length; start += RB_DELETE_BATCH_SIZE) {
      if (host.clearingCancelRequested) {
        canceled = true;
        break;
      }
      const end = Math.min(start + RB_DELETE_BATCH_SIZE, ids.length);
      const batch = ids.slice(start, end);
      const res = await client.deleteRecycleBinPhotos(batch);
      host.clearingSubmitted = end;
      if (!res.success) {
        // taskInfo.retryable = false：失败的这一批不自动重发。
        failedBatches++;
        failedIds += batch.length;
        const msg: string = res.message !== undefined && res.message.length > 0 ? res.message : 'unknown';
        fnDiagRecord('E', 'RecycleBin', `delete batch failed ${msg}`);
      }
    }
    // 受理 ≠ 删完，等 NAS 真正把 id 删掉再刷新列表。
    if (!canceled && failedBatches === 0) {
      settled = await recycleBinAwaitDeleted(client, ids);
    }
  } catch (e) {
    fnDiagRecord('E', 'RecycleBin', `clear failed ${String(e)}`);
  } finally {
    host.clearing = false;
  }
  await recycleBinLoadAll(host);
  if (canceled) {
    host.toast(`已停止提交，已尝试 ${host.clearingSubmitted} 项`);
  } else if (failedBatches > 0) {
    host.toast(`已提交 ${host.clearingSubmitted - failedIds} 项，${failedIds} 项提交失败`);
  } else if (settled) {
    host.toast(`已永久删除 ${ids.length} 项`);
  } else {
    // 没确认删完就不能说已删除：服务端任务还在跑。
    host.toast('已提交删除请求，NAS 仍在处理');
  }
}
