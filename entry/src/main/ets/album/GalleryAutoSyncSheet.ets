/**
 * 批量同步上传（进入任务队列，不阻塞界面）。
 * 扫描阶段已经用整库 file_hash 去掉已存在的内容，这里只上传未命中的那一份字节。
 */
import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { BackgroundKeepAliveController } from '../background/BackgroundKeepAliveController';
import { FnTransferDirection, fnTransferDirectionLabel } from '../common/FnTransferProgress';
import { FnTransferQueueStore } from '../common/FnTransferQueueStore';
import { FnClientResult } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { deleteOwnedLivePayload } from './GalleryLiveSyncPayload';
import { GalleryAutoSyncLedger, LedgerPut } from './GalleryAutoSyncLedger';
import { SyncUploadPiece } from './GalleryAutoSyncCompare';
import { GalleryAutoSyncStore } from './GalleryAutoSyncStore';
import { GalleryTimelineRefreshStore } from './GalleryTimelineRefreshStore';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncSheet';
/** 同步上传默认并行满速，不跟「我的」里那个会改预取的满载开关走。 */
const SYNC_UPLOAD_CONCURRENCY: number = 4;

let syncUploadRunning: boolean = false;

export interface AutoSyncRunnerCallbacks {
  toast(msg: string): void;
  requestBootstrap(debounced: boolean): void;
}

async function uploadPiece(
  client: FnHttpClient,
  piece: SyncUploadPiece,
  timeoutMs: number,
  albumDirHint: string | undefined
): Promise<FnClientResult<Object>> {
  if (piece.role === 'live' && piece.payloadPath.length > 0) {
    const uri = fileUri.getUriFromPath(piece.payloadPath);
    const uploaded = await client.uploadPhotoByUri(uri, timeoutMs, albumDirHint);
    if (uploaded.success) {
      await deleteOwnedLivePayload(piece.payloadPath);
    }
    return uploaded;
  }
  return client.uploadPhotoByUri(piece.sourceUri, timeoutMs, albumDirHint);
}

export function runAutoSyncInBackground(
  ctx: common.UIAbilityContext,
  photos: SyncUploadPiece[],
  callbacks: AutoSyncRunnerCallbacks
): void {
  if (syncUploadRunning) {
    callbacks.toast('已有任务进行中');
    return;
  }
  syncUploadRunning = true;
  void (async (): Promise<void> => {
    try {
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
        callbacks.toast('已有任务进行中');
        return;
      }

      const label = fnTransferDirectionLabel(FnTransferDirection.SYNC);
      const taskId = FnTransferQueueStore.begin(FnTransferDirection.SYNC, label, photos.length);
      let ok = 0;
      let failMsg = '';
      const stored = AppSession.getStored();
      const albumDirHint =
        stored !== null && stored.albumParentGuid.trim().length > 0
          ? stored.albumParentGuid.trim()
          : undefined;

      try {
        await BackgroundKeepAliveController.withDataTransfer(ctx, 'auto-sync', async (): Promise<void> => {
          let uploadCursor = 0;
          let finished = 0;
          const uploadWorkers: Promise<void>[] = [];
          const uploadCount = Math.min(SYNC_UPLOAD_CONCURRENCY, photos.length);
          for (let w = 0; w < uploadCount; w++) {
            uploadWorkers.push((async (): Promise<void> => {
              while (true) {
                const index = uploadCursor;
                uploadCursor++;
                if (index >= photos.length) {
                  return;
                }
                const photo = photos[index];
                try {
                  const res = await uploadPiece(client, photo, 150000, albumDirHint);
                  if (res.success) {
                    ok++;
                    const put = new LedgerPut();
                    put.uri = photo.sourceUri;
                    put.size = photo.sourceSize;
                    put.mtimeMs = photo.sourceMtimeMs;
                    put.role = photo.role;
                    put.hash = photo.fingerprint;
                    await GalleryAutoSyncLedger.remember(ctx, put);
                    GalleryAutoSyncStore.markPieceSynced(photo.sourceUri, photo.role);
                  } else if (failMsg.length === 0) {
                    failMsg = res.message ?? '同步失败';
                  }
                } catch (e) {
                  hilog.warn(DOMAIN, TAG, 'auto-sync upload failed: %{public}s', String(e));
                  if (failMsg.length === 0) {
                    failMsg = '同步失败，请稍后重试';
                  }
                }
                finished++;
                FnTransferQueueStore.update(taskId, finished, photo.fileName);
              }
            })());
          }
          await Promise.all(uploadWorkers);
        });
      } finally {
        const summary = ok > 0 ? `同步完成 ${ok}/${photos.length}` : (failMsg.length > 0 ? failMsg : '同步失败');
        FnTransferQueueStore.finish(taskId, ok > 0, summary);
      }

      if (ok > 0) {
        callbacks.toast(`同步完成 ${ok}/${photos.length}`);
        GalleryTimelineRefreshStore.bump();
        callbacks.requestBootstrap(false);
      } else {
        callbacks.toast(failMsg.length > 0 ? failMsg : '同步失败，请稍后重试');
      }
    } finally {
      syncUploadRunning = false;
    }
  })();
}

/** @deprecated 保留兼容；请使用 runAutoSyncInBackground */
export async function runAutoSync(
  ctx: common.UIAbilityContext,
  photos: SyncUploadPiece[],
  callbacks: AutoSyncRunnerCallbacks
): Promise<void> {
  runAutoSyncInBackground(ctx, photos, callbacks);
}
