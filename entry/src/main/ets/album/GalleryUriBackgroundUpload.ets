/**
 * 通用本地 URI 后台上传：图库选图与系统分享入站共用。
 */
import { common } from '@kit.AbilityKit';
import { AppSession } from '../auth/AppSession';
import { BackgroundKeepAliveController } from '../background/BackgroundKeepAliveController';
import { FnTransferDirection, fnTransferDirectionLabel } from '../common/FnTransferProgress';
import { FnTransferQueueStore } from '../common/FnTransferQueueStore';
import { fileNameFromPickerUri, localPhotoEntryFromPickerUri } from './GalleryAutoSyncPicker';
import { GalleryAutoSyncLedger } from './GalleryAutoSyncLedger';
import { GalleryAutoSyncNasIndex } from './GalleryAutoSyncNasIndex';
import { GalleryAutoSyncStore } from './GalleryAutoSyncStore';
import { GalleryTimelineRefreshStore } from './GalleryTimelineRefreshStore';
import { uploadUriMaybeMovingPhoto } from './livephoto/LivePhotoUpload';

export type GalleryUriUploadToast = (msg: string) => void;
export type GalleryUriUploadOnSuccess = () => void;

/**
 * 将本地媒体 URI 排队后台上传。
 * @returns 已启动为 true；未登录或列表为空为 false
 */
export function galleryStartUriListUpload(
  ctx: common.UIAbilityContext,
  uris: string[],
  keepAliveTag: string,
  doneVerb: string,
  toast: GalleryUriUploadToast,
  onSuccess?: GalleryUriUploadOnSuccess
): boolean {
  const client = AppSession.getClient();
  if (client === null) {
    toast('未登录');
    return false;
  }
  if (uris.length === 0) {
    return false;
  }
  const label = fnTransferDirectionLabel(FnTransferDirection.UPLOAD);
  void (async (): Promise<void> => {
    const taskId = FnTransferQueueStore.begin(FnTransferDirection.UPLOAD, label, uris.length);
    let ok = 0;
    let firstFailMsg = '';
    const stored = AppSession.getStored();
    const albumDirHint =
      stored !== null && stored.albumParentGuid.trim().length > 0 ? stored.albumParentGuid.trim() : undefined;
    try {
      await BackgroundKeepAliveController.withDataTransfer(ctx, keepAliveTag, async (): Promise<void> => {
        for (let i = 0; i < uris.length; i++) {
          const uri = uris[i];
          FnTransferQueueStore.update(taskId, i + 1, fileNameFromPickerUri(uri));
          const res = await uploadUriMaybeMovingPhoto(client, ctx, uri, 150000, albumDirHint);
          if (res.success) {
            ok++;
            const entry = localPhotoEntryFromPickerUri(uri);
            await GalleryAutoSyncLedger.markSynced(ctx, [entry]);
            GalleryAutoSyncStore.markSynced([uri]);
            GalleryAutoSyncNasIndex.addLocalEntries([entry]);
          } else if (firstFailMsg.length === 0) {
            const em = res.message ?? '';
            firstFailMsg = em.length > 0 ? em : `${doneVerb}失败`;
          }
        }
      });
    } finally {
      const summary = ok > 0 ? `${doneVerb}完成 ${ok}/${uris.length}` :
        (firstFailMsg.length > 0 ? firstFailMsg : `${doneVerb}失败`);
      FnTransferQueueStore.finish(taskId, ok > 0, summary);
    }
    if (ok > 0) {
      toast(`${doneVerb}完成 ${ok}/${uris.length}`);
      GalleryTimelineRefreshStore.bump();
      if (onSuccess !== undefined) {
        onSuccess();
      }
    } else {
      toast(firstFailMsg.length > 0 ? firstFailMsg : `${doneVerb}失败，请稍后重试`);
    }
  })();
  return true;
}
