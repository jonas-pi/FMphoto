/**
 * 批量下载 NAS 图库媒体到本机相册。
 * 保留原有的批量选择与下载质量逻辑，只把最终保存出口改成系统相册保存确认。
 */
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri as fileUriUtil } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppSession } from '../auth/AppSession';
import { BackgroundKeepAliveController } from '../background/BackgroundKeepAliveController';
import { GalleryListItem } from '../model/FnApiTypes';
import { copyGalleryUriContentToAlbumUri } from './GalleryAlbumSaveToAlbum';
import { isVideoItem, itemFileExt, nasUrl, pickOriginal, pickThumb, pickVideo } from './GalleryAlbumCommon';

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
  const trimmed = raw.trim();
  if (trimmed.length > 0) {
    const dot = trimmed.lastIndexOf('.');
    const base = dot > 0 ? trimmed.substring(0, dot) : trimmed;
    const safe = base.replace(/[\\/:*?"<>|]/g, '_');
    if (safe.length > 0) {
      return safe.length > 80 ? safe.substring(0, 80) : safe;
    }
  }
  const id = it.id !== undefined && it.id !== null ? String(it.id).trim() : '';
  if (id.length > 0) {
    return `nas_${id}`;
  }
  return `nas_${idx}_${Date.now()}`;
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

/**
 * 批量下载：先拉到应用缓存，再弹系统相册保存确认。
 * 图片仍按原逻辑可选原图/缩略图，视频始终下载原文件。
 */
export async function runBatchDownloadGalleryItems(
  baseUrl: string,
  items: GalleryListItem[],
  hostContext: common.UIAbilityContext,
  toastMsg: (msg: string) => void,
  askBatchImageQuality: () => Promise<'original' | 'thumb' | 'cancel'>
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
  try {
  const preparedFileUris: string[] = [];
  const preparedConfigs: photoAccessHelper.PhotoCreationConfig[] = [];
  const tempPaths: string[] = [];
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    const isVideo = isVideoItem(it);
    let url = '';
    if (isVideo) {
      url = nasUrl(baseUrl, pickVideo(it));
    } else if (useOriginalForImages && pickOriginal(it).trim().length > 0) {
      url = nasUrl(baseUrl, pickOriginal(it));
    } else {
      url = nasUrl(baseUrl, pickThumb(it));
    }
    if (url.length === 0) {
      continue;
    }

    const ext = suggestedSaveExt(it);
    const tempPath = `${hostContext.cacheDir}/batch_download_${Date.now()}_${i}.${ext}`;
    if (isVideo) {
      const downloaded = await client.downloadGalleryAssetToFile(url, tempPath, 600000);
      if (!downloaded) {
        continue;
      }
      tempPaths.push(tempPath);
      preparedFileUris.push(fileUriUtil.getUriFromPath(tempPath));
      preparedConfigs.push({
        title: suggestedBaseName(it, i),
        fileNameExtension: ext,
        photoType: photoAccessHelper.PhotoType.VIDEO
      });
      continue;
    }

    const timeoutMs = useOriginalForImages ? 60000 : 15000;
    const buf = await client.fetchGalleryImageBuffer(url, timeoutMs);
    if (buf === undefined || buf.byteLength === 0) {
      continue;
    }

    try {
      const saveFile = await fileIo.open(
        tempPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      await fileIo.write(saveFile.fd, buf);
      await fileIo.close(saveFile.fd);

      tempPaths.push(tempPath);
      preparedFileUris.push(fileUriUtil.getUriFromPath(tempPath));
      preparedConfigs.push({
        title: suggestedBaseName(it, i),
        fileNameExtension: ext,
        photoType: photoAccessHelper.PhotoType.IMAGE
      });
    } catch (_e) {
    }
  }

  if (preparedFileUris.length === 0) {
    toastMsg('没有可下载的项目');
    return;
  }

  try {
    const savedCount = await copyPreparedFilesToAlbum(preparedFileUris, preparedConfigs, hostContext);
    if (savedCount < 0) {
      toastMsg('保存失败，请重试');
      return;
    }
    if (savedCount === 0) {
      toastMsg('已取消保存');
      return;
    }
    toastMsg(`已保存 ${savedCount}/${items.length} 项`);
  } catch (_e) {
    toastMsg('保存失败，请重试');
  } finally {
    for (let i = 0; i < tempPaths.length; i++) {
      try {
        await fileIo.unlink(tempPaths[i]);
      } catch (_e) {
      }
    }
  }
  } finally {
    BackgroundKeepAliveController.endDataTransfer('batch-download');
  }
}
