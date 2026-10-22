/**
 * 批量同步上传（进入任务队列，不阻塞界面）。
 * 扫描阶段已用本机账本和 NAS 文件名单过滤；服务端 notice 负责最终内容去重。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { BackgroundKeepAliveController } from '../background/BackgroundKeepAliveController';
import { FnTransferDirection, fnTransferDirectionLabel } from '../common/FnTransferProgress';
import { FnTransferQueueStore } from '../common/FnTransferQueueStore';
import { fnDiagRecord, fnDiagSetState } from '../common/FnDiagLog';
import { FnClientResult } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { uploadLocalMediaUri } from './GalleryLiveSyncPayload';
import { GalleryAutoSyncLedger, LedgerPut } from './GalleryAutoSyncLedger';
import { GalleryAutoSyncLocalSeen } from './GalleryAutoSyncLocalSeen';
import { LocalPhotoEntry } from './GalleryAutoSyncService';
import { SyncUploadPiece } from './GalleryAutoSyncCompare';
import { GalleryAutoSyncStore } from './GalleryAutoSyncStore';
import { GalleryTimelineRefreshStore } from './GalleryTimelineRefreshStore';
import { getAlbumBackupSettingsCached } from '../sync/AlbumBackupSettings';
import { evaluateAlbumBackupUploadGate } from '../sync/AlbumBackupUploadPolicy';
import { archivePhotosToNasAlbum, normalizeAlbumName } from './GalleryAutoSyncAlbums';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncSheet';
/** 同步上传默认并行满速，不跟「我的」里那个会改预取的满载开关走。 */
const SYNC_UPLOAD_CONCURRENCY: number = 4;

let syncUploadRunning: boolean = false;

export interface AutoSyncRunnerCallbacks {
  toast(msg: string): void;
  requestBootstrap(debounced: boolean): void;
  onSyncFinished(): void;
}

async function uploadPiece(
  ctx: common.UIAbilityContext,
  client: FnHttpClient,
  piece: SyncUploadPiece,
  timeoutMs: number,
  albumDirHint: string | undefined
): Promise<FnClientResult<Object>> {
  const nameHint = piece.fileName.length > 0 ? piece.fileName : undefined;
  return uploadLocalMediaUri(client, ctx, piece.sourceUri, timeoutMs, albumDirHint, nameHint);
}

export function runAutoSyncInBackground(
  ctx: common.UIAbilityContext,
  photos: SyncUploadPiece[],
  callbacks: AutoSyncRunnerCallbacks
): void {
  if (syncUploadRunning) {
    fnDiagRecord('W', TAG, 'sync skipped: task running');
    fnDiagSetState('autoSync', 'disabled');
    callbacks.toast('已有任务进行中');
    return;
  }
  syncUploadRunning = true;
  void (async (): Promise<void> => {
    try {
      const client = AppSession.getClient();
      if (client === null) {
        fnDiagSetState('autoSync', 'disabled');
        callbacks.toast('未登录');
        return;
      }
      if (photos.length === 0) {
        fnDiagSetState('autoSync', 'disabled');
        callbacks.toast('没有需要同步的照片');
        return;
      }
      const gate = await evaluateAlbumBackupUploadGate();
      if (!gate.allowed) {
        // 只记门控类别，不记门控文案。
        const reason: string = gate.reason.indexOf('电量') >= 0
          ? 'battery'
          : (gate.reason.indexOf('流量') >= 0 ? 'cellular' : 'other');
        fnDiagRecord('W', TAG, `upload gate blocked ${reason}`);
        fnDiagSetState('autoSync', 'disabled');
        callbacks.toast(gate.reason.length > 0 ? gate.reason : '当前无法备份');
        return;
      }
      if (FnTransferQueueStore.hasRunningDirection(FnTransferDirection.SYNC)) {
        fnDiagRecord('W', TAG, 'sync skipped: queue busy');
        fnDiagSetState('autoSync', 'disabled');
        callbacks.toast('已有任务进行中');
        return;
      }
      fnDiagSetState('autoSync', 'enabled');

      const label = fnTransferDirectionLabel(FnTransferDirection.SYNC);
      const taskId = FnTransferQueueStore.begin(FnTransferDirection.SYNC, label, photos.length);
      let ok = 0;
      let failMsg = '';
      let albumNotArchived = 0;
      let summary = '';
      const stored = AppSession.getStored();
      const backupPrefs = getAlbumBackupSettingsCached();
      // 按本机来源相册名建 NAS 同名相册：仅在开关打开时做，失败不影响照片本身入库
      const archiveToAlbums = backupPrefs.syncCreateAlbum;
      const albumPending: Map<string, string[]> = new Map<string, string[]>();
      let albumDirHint: string | undefined = undefined;
      if (backupPrefs.deviceBackupPath.trim().length > 0) {
        albumDirHint = backupPrefs.deviceBackupPath.trim();
      } else if (stored !== null && stored.albumParentGuid.trim().length > 0) {
        albumDirHint = stored.albumParentGuid.trim();
      }

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
                  const res = await uploadPiece(ctx, client, photo, 150000, albumDirHint);
                  if (res.success) {
                    ok++;
                    hilog.info(DOMAIN, TAG, 'synced role=%{public}s', photo.role);
                    if (archiveToAlbums && photo.albumName.length > 0) {
                      const albumKey = normalizeAlbumName(photo.albumName);
                      const uploadedId = res.uploadedPhotoId ?? '';
                      if (albumKey.length > 0 && uploadedId.length > 0) {
                        const bucket = albumPending.get(albumKey);
                        if (bucket === undefined) {
                          albumPending.set(albumKey, [uploadedId]);
                        } else {
                          bucket.push(uploadedId);
                        }
                      } else if (albumKey.length > 0) {
                        // 上传成功但拿不到 photoId（例如「已存在」的重复入库响应里没有 id）：
                        // 这张照片没法归档，计数进摘要，避免「同步完成」却悄悄漏归档
                        albumNotArchived++;
                        hilog.info(DOMAIN, TAG, 'archive skipped no-photoId role=%{public}s', photo.role);
                      }
                    }
                    const put = new LedgerPut();
                    put.uri = photo.sourceUri;
                    put.size = photo.sourceSize;
                    put.mtimeMs = photo.sourceMtimeMs;
                    put.role = photo.role;
                    await GalleryAutoSyncLedger.remember(ctx, put);
                    const seen: LocalPhotoEntry = {
                      uri: photo.sourceUri,
                      fileName: photo.fileName,
                      fileSize: photo.sourceSize,
                      dateModifiedMs: photo.sourceMtimeMs,
                      mimeType: '',
                      photoSubtype: 0,
                      sourceAlbumName: photo.albumName
                    };
                    const seenBatch: LocalPhotoEntry[] = [seen];
                    await GalleryAutoSyncLocalSeen.remember(ctx, seenBatch);
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

          // 上传结束后按本地相册名分组归档；这一步失败不回滚已上传的照片
          const albumNames: string[] = [];
          albumPending.forEach((_ids: string[], name: string) => {
            albumNames.push(name);
          });
          for (let i = 0; i < albumNames.length; i++) {
            const ids = albumPending.get(albumNames[i]);
            if (ids === undefined || ids.length === 0) {
              continue;
            }
            const albumOk = await archivePhotosToNasAlbum(client, albumNames[i], ids);
            if (!albumOk) {
              albumNotArchived += ids.length;
              fnDiagRecord('W', TAG, `archive to album failed count=${ids.length}`);
            }
          }
          // 归档之后再通知相册列表：此时 NAS 上已经有新相册/新计数，
          // 提前发会让相册页拉到创建前的结果，并把 lastAlbumsVersion 记成当前版本。
          if (albumNames.length > 0) {
            GalleryTimelineRefreshStore.bumpAlbums();
          }
        });
      } finally {
        summary = ok > 0 ? `同步完成 ${ok}/${photos.length}` : (failMsg.length > 0 ? failMsg : '同步失败');
        if (albumNotArchived > 0) {
          summary = `${summary}，${albumNotArchived} 张未归档到相册`;
        }
        FnTransferQueueStore.finish(taskId, ok > 0, summary);
      }

      if (ok > 0) {
        callbacks.toast(summary);
        GalleryTimelineRefreshStore.bump();
        callbacks.onSyncFinished();
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
