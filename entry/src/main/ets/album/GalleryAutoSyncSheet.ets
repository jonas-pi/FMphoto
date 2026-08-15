/**
 * 批量同步上传（后台传输队列，不阻塞 UI）。
 * 半官方策略：账本 + NAS 指纹快筛后，上传前再问服务端；仅明确 exists 才跳过。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { BackgroundKeepAliveController } from '../background/BackgroundKeepAliveController';
import { FnTransferDirection, fnTransferDirectionLabel } from '../common/FnTransferProgress';
import { FnTransferQueueStore } from '../common/FnTransferQueueStore';
import { FnHttpClient } from '../network/FnHttpClient';
import { LocalPhotoEntry } from './GalleryAutoSyncService';
import { GalleryAutoSyncLedger } from './GalleryAutoSyncLedger';
import { GalleryAutoSyncNasIndex } from './GalleryAutoSyncNasIndex';
import { mtimeSecFromMillis } from './GalleryAutoSyncOfficialFingerprint';
import { filterUnsyncedLocalPhotos, GalleryAutoSyncStore } from './GalleryAutoSyncStore';
import { GalleryTimelineRefreshStore } from './GalleryTimelineRefreshStore';
import { uploadUriMaybeMovingPhoto } from './livephoto/LivePhotoUpload';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncSheet';

export interface AutoSyncRunnerCallbacks {
  toast(msg: string): void;
  requestBootstrap(debounced: boolean): void;
}

/**
 * 上传前二次过滤：本地索引 + 服务端 check（仅 'exists' 跳过；unknown/missing 仍上传）。
 */
async function refilterBeforeUpload(
  ctx: common.UIAbilityContext,
  client: FnHttpClient,
  photos: LocalPhotoEntry[]
): Promise<LocalPhotoEntry[]> {
  const nasIndex = await GalleryAutoSyncNasIndex.getIndex(client, false);
  const ledger = await GalleryAutoSyncLedger.load(ctx);
  const clientFiltered = filterUnsyncedLocalPhotos(photos, nasIndex, ledger).unsynced;
  if (clientFiltered.length === 0) {
    return clientFiltered;
  }

  const toUpload: LocalPhotoEntry[] = [];
  const serverExists: LocalPhotoEntry[] = [];
  for (let i = 0; i < clientFiltered.length; i++) {
    const photo = clientFiltered[i];
    const mtimeSec = mtimeSecFromMillis(photo.dateModifiedMs);
    const check = await client.checkPhotoUploadExists(photo.fileName, photo.fileSize, mtimeSec);
    if (check === 'exists') {
      serverExists.push(photo);
      continue;
    }
    toUpload.push(photo);
  }
  if (serverExists.length > 0) {
    await GalleryAutoSyncLedger.markSynced(ctx, serverExists);
    GalleryAutoSyncStore.markSynced(serverExists.map((p: LocalPhotoEntry): string => p.uri));
    GalleryAutoSyncNasIndex.addLocalEntries(serverExists);
    hilog.info(DOMAIN, TAG, 'server dedupe skipped=%{public}d', serverExists.length);
  }
  return toUpload;
}

export function runAutoSyncInBackground(
  ctx: common.UIAbilityContext,
  photos: LocalPhotoEntry[],
  callbacks: AutoSyncRunnerCallbacks
): void {
  void (async (): Promise<void> => {
    const client = AppSession.getClient();
    if (client === null) {
      callbacks.toast('未登录');
      return;
    }
    if (photos.length === 0) {
      callbacks.toast('没有需要同步的照片');
      return;
    }
    if (FnTransferQueueStore.hasRunning()) {
      callbacks.toast('已有传输任务进行中');
      return;
    }

    const label = fnTransferDirectionLabel(FnTransferDirection.SYNC);
    const checkTaskId = FnTransferQueueStore.begin(FnTransferDirection.SYNC, '检查 NAS 已有照片', 0);
    const toUpload = await refilterBeforeUpload(ctx, client, photos);
    FnTransferQueueStore.finish(
      checkTaskId,
      true,
      toUpload.length === 0 ? '均已存在，无需同步' : `待同步 ${toUpload.length} 张`
    );
    if (toUpload.length === 0) {
      callbacks.toast('没有需要同步的照片');
      GalleryAutoSyncStore.markSynced(photos.map((p: LocalPhotoEntry): string => p.uri));
      return;
    }

    const taskId = FnTransferQueueStore.begin(FnTransferDirection.SYNC, label, toUpload.length);
    let ok = 0;
    let failMsg = '';
    const stored = AppSession.getStored();
    const albumDirHint =
      stored !== null && stored.albumParentGuid.trim().length > 0
        ? stored.albumParentGuid.trim()
        : undefined;

    try {
      await BackgroundKeepAliveController.withDataTransfer(ctx, 'auto-sync', async (): Promise<void> => {
        for (let i = 0; i < toUpload.length; i++) {
          const photo = toUpload[i];
          FnTransferQueueStore.update(taskId, i + 1, photo.fileName);
          try {
            const res = await uploadUriMaybeMovingPhoto(client, ctx, photo.uri, 150000, albumDirHint);
            if (res.success) {
              ok++;
              GalleryAutoSyncStore.markSynced([photo.uri]);
              await GalleryAutoSyncLedger.markSynced(ctx, [photo]);
              GalleryAutoSyncNasIndex.addLocalEntries([photo]);
            } else if (failMsg.length === 0) {
              failMsg = res.message ?? '同步失败';
            }
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'auto-sync upload failed: %{public}s', String(e));
            if (failMsg.length === 0) {
              failMsg = '同步失败，请稍后重试';
            }
          }
        }
      });
    } finally {
      const summary = ok > 0 ? `同步完成 ${ok}/${toUpload.length}` : (failMsg.length > 0 ? failMsg : '同步失败');
      FnTransferQueueStore.finish(taskId, ok > 0, summary);
    }

    if (ok > 0) {
      callbacks.toast(`同步完成 ${ok}/${toUpload.length}`);
      GalleryTimelineRefreshStore.bump();
      callbacks.requestBootstrap(false);
    } else {
      callbacks.toast(failMsg.length > 0 ? failMsg : '同步失败，请稍后重试');
    }
  })();
}

/** @deprecated 保留兼容；请使用 runAutoSyncInBackground */
export async function runAutoSync(
  ctx: common.UIAbilityContext,
  photos: LocalPhotoEntry[],
  callbacks: AutoSyncRunnerCallbacks
): Promise<void> {
  runAutoSyncInBackground(ctx, photos, callbacks);
}
