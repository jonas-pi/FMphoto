/**
 * 批量下载 NAS 图库媒体到本机相册。
 * 普通图/视频走系统相册保存确认；实况在 SaveButton 授权下写成动态照片。
 */
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri as fileUriUtil } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppSession } from '../auth/AppSession';
import { BackgroundKeepAliveController } from '../background/BackgroundKeepAliveController';
import { FnTransferDirection, fnTransferDirectionLabel } from '../common/FnTransferProgress';
import { FnTransferQueueStore } from '../common/FnTransferQueueStore';
import { GalleryListItem } from '../model/FnApiTypes';
import { copyGalleryUriContentToAlbumUri } from './GalleryAlbumSaveToAlbum';
import { isVideoItem, itemFileExt, nasUrl, pickOriginal, pickThumb, pickVideo } from './GalleryAlbumCommon';
import { isLivePhotoItem } from './livephoto/LivePhotoDetect';
import {
  appendStillAndVideoToPrepare,
  createMovingPhotoAsset,
  sanitizeMediaTitle,
  saveSandboxAssetWithPrivilege
} from './livephoto/LivePhotoSaveOps';
import { materializeLivePhotoPair, unlinkLivePhotoPair } from './livephoto/LivePhotoSandbox';

const BATCH_DOWNLOAD_CONCURRENCY = 4;
const BATCH_DOWNLOAD_MAX_ATTEMPTS = 2;

function itemHasOriginalPhoto(it: GalleryListItem): boolean {
  return !isVideoItem(it) && pickOriginal(it).trim().length > 0;
}

function suggestedSaveExt(it: GalleryListItem): string {
  if (isVideoItem(it)) {
    const ext = itemFileExt(it);
    if (ext === 'mp4' || ext === 'mov' || ext === 'm4v' || ext === 'mkv' || ext === 'avi' || ext === 'webm') {
      return ext;
    }
    return 'mp4';
  }
  const ext = itemFileExt(it);
  if (ext === 'gif') {
    return 'gif';
  }
  if (ext === 'png') {
    return 'png';
  }
  if (ext === 'webp') {
    return 'webp';
  }
  return 'jpg';
}

function suggestedBaseName(it: GalleryListItem, idx: number): string {
  const raw = it.filename ?? it.name ?? it.title ?? '';
  const id = it.id !== undefined && it.id !== null ? String(it.id).trim() : '';
  const fallback = id.length > 0 ? `nas_${id}` : `nas_${idx}_${Date.now()}`;
  return sanitizeMediaTitle(raw, fallback);
}

async function copyPreparedFilesToAlbum(
  preparedFileUris: string[],
  preparedConfigs: photoAccessHelper.PhotoCreationConfig[],
  hostContext: common.UIAbilityContext
): Promise<number> {
  try {
    const targetUris = await photoAccessHelper
      .getPhotoAccessHelper(hostContext)
      .showAssetsCreationDialog(preparedFileUris, preparedConfigs);
    if (targetUris.length === 0) {
      return 0;
    }
    let savedCount = 0;
    const limit = Math.min(targetUris.length, preparedFileUris.length);
    for (let i = 0; i < limit; i++) {
      const saved = await copyGalleryUriContentToAlbumUri(preparedFileUris[i], targetUris[i]);
      if (!saved) {
        return -1;
      }
      savedCount++;
    }
    return savedCount;
  } catch (_e) {
    return -1;
  }
}

/**
 * 按当前列表顺序收集已选中 id 对应的条目，去重顺序与列表一致。
 */
export function galleryItemsMatchingSelectedIds(
  list: GalleryListItem[],
  selectedIds: string[]
): GalleryListItem[] {
  if (selectedIds.length === 0 || list.length === 0) {
    return [];
  }
  const want = new Set<string>();
  for (let i = 0; i < selectedIds.length; i++) {
    const s = selectedIds[i].trim();
    if (s.length > 0) {
      want.add(s);
    }
  }
  const out: GalleryListItem[] = [];
  for (let i = 0; i < list.length; i++) {
    const it = list[i];
    const id = it.id !== undefined && it.id !== null ? String(it.id).trim() : '';
    if (id.length > 0 && want.has(id)) {
      out.push(it);
    }
  }
  return out;
}

function liveSaveSummary(movingCount: number, pairCount: number): string {
  const parts: string[] = [];
  if (movingCount > 0) {
    parts.push(`${movingCount} 张动态照片`);
  }
  if (pairCount > 0) {
    parts.push(`${pairCount} 组封面和视频`);
  }
  return parts.join('、');
}

let pendingMediaWriteAuthorized: boolean = false;

/** SaveButton 点击成功后、真正开始批量下载前标记特权写入。 */
export function markPendingMediaWriteAuthorized(): void {
  pendingMediaWriteAuthorized = true;
}

function consumePendingMediaWriteAuthorized(): boolean {
  const v: boolean = pendingMediaWriteAuthorized;
  pendingMediaWriteAuthorized = false;
  return v;
}

/**
 * 批量下载：先拉到应用缓存，再写入相册。
 * mediaWriteAuthorized 为 true 时，实况写成系统动态照片。
 */
export function runBatchDownloadGalleryItemsInBackground(
  baseUrl: string,
  items: GalleryListItem[],
  hostContext: common.UIAbilityContext,
  toastMsg: (msg: string) => void,
  askBatchImageQuality: () => Promise<'original' | 'thumb' | 'cancel'>,
  mediaWriteAuthorized: boolean = false
): void {
  void (async (): Promise<void> => {
    await runBatchDownloadGalleryItems(
      baseUrl,
      items,
      hostContext,
      toastMsg,
      askBatchImageQuality,
      mediaWriteAuthorized
    );
  })();
}

export async function runBatchDownloadGalleryItems(
  baseUrl: string,
  items: GalleryListItem[],
  hostContext: common.UIAbilityContext,
  toastMsg: (msg: string) => void,
  askBatchImageQuality: () => Promise<'original' | 'thumb' | 'cancel'>,
  mediaWriteAuthorized: boolean = false
): Promise<void> {
  if (items.length === 0) {
    toastMsg('没有可下载的项目');
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    toastMsg('未登录');
    return;
  }
  const writeAuthorized = mediaWriteAuthorized || consumePendingMediaWriteAuthorized();

  let useOriginalForImages = false;
  let anyOriginal = false;
  for (let i = 0; i < items.length; i++) {
    if (itemHasOriginalPhoto(items[i])) {
      anyOriginal = true;
      break;
    }
  }
  if (anyOriginal) {
    const q = await askBatchImageQuality();
    if (q === 'cancel') {
      return;
    }
    useOriginalForImages = q === 'original';
  }

  BackgroundKeepAliveController.beginDataTransfer(hostContext, 'batch-download');
  const label = fnTransferDirectionLabel(FnTransferDirection.DOWNLOAD);
  const taskId = FnTransferQueueStore.begin(FnTransferDirection.DOWNLOAD, label, items.length);
  const preparedFileUris: string[] = [];
  const preparedConfigs: photoAccessHelper.PhotoCreationConfig[] = [];
  const tempPaths: string[] = [];
  let livePairCount = 0;
  let liveMovingCount = 0;
  let privilegeSavedCount = 0;
  let failedCount = 0;
  try {
  let nextIndex = 0;
  let startedCount = 0;
  const downloadWorker = async (): Promise<void> => {
  for (;;) {
    const i = nextIndex;
    nextIndex++;
    if (i >= items.length) {
      return;
    }
    const it = items[i];
    startedCount++;
    FnTransferQueueStore.update(taskId, startedCount, suggestedBaseName(it, i));
    const isVideo = isVideoItem(it);
    if (!isVideo && isLivePhotoItem(it)) {
      const pair = await materializeLivePhotoPair(hostContext, baseUrl, it, useOriginalForImages);
      if (pair !== undefined) {
        const liveTitle = suggestedBaseName(it, i);
        if (writeAuthorized && await createMovingPhotoAsset(hostContext, pair, liveTitle)) {
          liveMovingCount++;
          await unlinkLivePhotoPair(pair);
          continue;
        }
        if (writeAuthorized) {
          const imgOk = await saveSandboxAssetWithPrivilege(
            hostContext,
            pair.imageUri,
            liveTitle,
            suggestedSaveExt(it),
            photoAccessHelper.PhotoType.IMAGE
          );
          const vidOk = await saveSandboxAssetWithPrivilege(
            hostContext,
            pair.videoUri,
            `${liveTitle}_live`,
            'mp4',
            photoAccessHelper.PhotoType.VIDEO
          );
          if (imgOk && vidOk) {
            livePairCount++;
            await unlinkLivePhotoPair(pair);
            continue;
          }
        }
        appendStillAndVideoToPrepare(pair, liveTitle, preparedFileUris, preparedConfigs);
        tempPaths.push(pair.imagePath);
        tempPaths.push(pair.videoPath);
        livePairCount++;
        continue;
      }
    }
    let url = '';
    if (isVideo) {
      url = nasUrl(baseUrl, pickVideo(it));
    } else if (useOriginalForImages && pickOriginal(it).trim().length > 0) {
      url = nasUrl(baseUrl, pickOriginal(it));
    } else {
      url = nasUrl(baseUrl, pickThumb(it));
    }
    if (url.length === 0) {
      failedCount++;
      continue;
    }

    const ext = suggestedSaveExt(it);
    const tempPath = `${hostContext.cacheDir}/batch_download_${Date.now()}_${i}.${ext}`;
    const itemTitle = suggestedBaseName(it, i);
    if (isVideo) {
      let downloaded = false;
      for (let attempt = 0; attempt < BATCH_DOWNLOAD_MAX_ATTEMPTS && !downloaded; attempt++) {
        downloaded = await client.downloadGalleryAssetToFile(url, tempPath, 600000);
      }
      if (!downloaded) {
        failedCount++;
        continue;
      }
      const videoUri = fileUriUtil.getUriFromPath(tempPath);
      if (writeAuthorized &&
        await saveSandboxAssetWithPrivilege(hostContext, videoUri, itemTitle, ext, photoAccessHelper.PhotoType.VIDEO)) {
        privilegeSavedCount++;
        try {
          await fileIo.unlink(tempPath);
        } catch (_e) {
        }
        continue;
      }
      tempPaths.push(tempPath);
      preparedFileUris.push(videoUri);
      preparedConfigs.push({
        title: itemTitle,
        fileNameExtension: ext,
        photoType: photoAccessHelper.PhotoType.VIDEO
      });
      continue;
    }

    /*
     * 图片也使用流式文件下载。fetchGalleryImageBuffer 的单文件上限为 20MB，
     * 大尺寸原图会返回空并被跳过；流式写入同时避免并发下载占用大量 JS 堆。
     */
    let downloaded = false;
    for (let attempt = 0; attempt < BATCH_DOWNLOAD_MAX_ATTEMPTS && !downloaded; attempt++) {
      downloaded = await client.downloadGalleryAssetToFile(url, tempPath, 600000);
    }
    if (!downloaded) {
      failedCount++;
      continue;
    }

    const imageUri = fileUriUtil.getUriFromPath(tempPath);
    if (writeAuthorized &&
      await saveSandboxAssetWithPrivilege(hostContext, imageUri, itemTitle, ext, photoAccessHelper.PhotoType.IMAGE)) {
      privilegeSavedCount++;
      try {
        await fileIo.unlink(tempPath);
      } catch (_e) {
      }
      continue;
    }
    tempPaths.push(tempPath);
    preparedFileUris.push(imageUri);
    preparedConfigs.push({
      title: itemTitle,
      fileNameExtension: ext,
      photoType: photoAccessHelper.PhotoType.IMAGE
    });
  }
  };
  const workerCount = Math.min(BATCH_DOWNLOAD_CONCURRENCY, items.length);
  const workers: Promise<void>[] = [];
  for (let i = 0; i < workerCount; i++) {
    workers.push(downloadWorker());
  }
  await Promise.all(workers);

  const directCount = liveMovingCount + privilegeSavedCount;
  if (preparedFileUris.length === 0) {
    if (directCount > 0) {
      const liveText = liveSaveSummary(liveMovingCount, livePairCount);
      const liveHint = liveText.length > 0 ? `（含 ${liveText}）` : '';
      const failHint = failedCount > 0 ? `，${failedCount} 项下载失败` : '';
      FnTransferQueueStore.finish(taskId, failedCount === 0,
        `已保存 ${directCount}/${items.length} 项${failHint}`);
      toastMsg(`已保存 ${directCount}/${items.length} 项${liveHint}${failHint}`);
      return;
    }
    FnTransferQueueStore.finish(taskId, false, `${failedCount} 项下载失败`);
    toastMsg(failedCount > 0 ? `${failedCount} 项下载失败，请重试` : '没有可下载的项目');
    return;
  }

  try {
    const savedCount = await copyPreparedFilesToAlbum(preparedFileUris, preparedConfigs, hostContext);
    if (savedCount < 0) {
      FnTransferQueueStore.finish(taskId, false, '保存失败');
      toastMsg('保存失败，请重试');
      return;
    }
    if (savedCount === 0 && directCount === 0) {
      FnTransferQueueStore.finish(taskId, true, '已取消保存');
      toastMsg('已取消保存');
      return;
    }
    const totalSaved = directCount + Math.max(0, savedCount);
    const liveText = liveSaveSummary(liveMovingCount, livePairCount);
    const liveHint = liveText.length > 0 ? `（含 ${liveText}）` : '';
    const failHint = failedCount > 0 ? `，${failedCount} 项下载失败` : '';
    FnTransferQueueStore.finish(taskId, failedCount === 0,
      `已保存 ${totalSaved}/${items.length} 项${failHint}`);
    toastMsg(`已保存 ${totalSaved}/${items.length} 项${liveHint}${failHint}`);
  } catch (_e) {
    toastMsg('保存失败，请重试');
  }
  } finally {
    for (let i = 0; i < tempPaths.length; i++) {
      try {
        await fileIo.unlink(tempPaths[i]);
      } catch (_e) {
      }
    }
    BackgroundKeepAliveController.endDataTransfer('batch-download');
  }
}
