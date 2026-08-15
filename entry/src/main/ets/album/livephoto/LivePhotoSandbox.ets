/**
 * 将 NAS 实况条目落到应用缓存，并构造官方 MovingPhoto 对象供预览/保存。
 */
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppSession } from '../../auth/AppSession';
import { itemFileExt, nasUrl, pickOriginal, pickThumb } from '../GalleryAlbumCommon';
import { GalleryListItem } from '../../model/FnApiTypes';
import { isLivePhotoItem, pickLiveVideo } from './LivePhotoDetect';
import { splitEmbeddedLivePhoto, writeBufferToFile } from './MotionPhotoSplit';

export class LivePhotoPairFiles {
  imagePath: string = '';
  videoPath: string = '';
  imageUri: string = '';
  videoUri: string = '';
}

function safeItemId(item: GalleryListItem): string {
  const sid = item.id !== undefined ? String(item.id) : `${Date.now()}`;
  return sid.replace(/[^a-zA-Z0-9_-]/g, '_');
}

function fileUriOf(path: string): string {
  return fileUri.getUriFromPath(path);
}

async function unlinkQuiet(path: string): Promise<void> {
  if (path.length === 0) {
    return;
  }
  try {
    await fileIo.unlink(path);
  } catch (_e) {
  }
}

export async function unlinkLivePhotoPair(pair: LivePhotoPairFiles | undefined): Promise<void> {
  if (pair === undefined) {
    return;
  }
  await unlinkQuiet(pair.imagePath);
  await unlinkQuiet(pair.videoPath);
}

async function downloadUrlToFile(url: string, path: string, timeoutMs: number): Promise<boolean> {
  const client = AppSession.getClient();
  if (client === null || url.length === 0) {
    return false;
  }
  return client.downloadGalleryAssetToFile(url, path, timeoutMs);
}

async function downloadUrlToBuffer(url: string, timeoutMs: number): Promise<ArrayBuffer | undefined> {
  const client = AppSession.getClient();
  if (client === null || url.length === 0) {
    return undefined;
  }
  return client.fetchGalleryImageBuffer(url, timeoutMs);
}

async function downloadStillWithFallback(
  primaryUrl: string,
  fallbackUrl: string,
  path: string,
  primaryTimeoutMs: number,
  fallbackTimeoutMs: number
): Promise<boolean> {
  if (primaryUrl.length > 0) {
    const ok = await downloadUrlToFile(primaryUrl, path, primaryTimeoutMs);
    if (ok) {
      return true;
    }
  }
  if (fallbackUrl.length > 0 && fallbackUrl !== primaryUrl) {
    return downloadUrlToFile(fallbackUrl, path, fallbackTimeoutMs);
  }
  return false;
}

function makePair(imagePath: string, videoPath: string): LivePhotoPairFiles {
  const pair = new LivePhotoPairFiles();
  pair.imagePath = imagePath;
  pair.videoPath = videoPath;
  pair.imageUri = fileUriOf(imagePath);
  pair.videoUri = fileUriOf(videoPath);
  return pair;
}

/**
 * 下载静帧 + 伴生视频（或从单文件拆分），写入 cacheDir。
 * 有独立 videoUrl 时静帧可用缩略图，不必等原图；无 videoUrl 时必须拉原图才能拆出视频。
 */
export async function materializeLivePhotoPair(
  context: common.UIAbilityContext,
  baseUrl: string,
  item: GalleryListItem,
  preferOriginal: boolean
): Promise<LivePhotoPairFiles | undefined> {
  if (!isLivePhotoItem(item)) {
    return undefined;
  }
  const id = safeItemId(item);
  const liveVideoUrl = nasUrl(baseUrl, pickLiveVideo(item));
  const origUrl = nasUrl(baseUrl, pickOriginal(item));
  const thumbUrl = nasUrl(baseUrl, pickThumb(item));
  const stillUrl = preferOriginal
    ? (origUrl.length > 0 ? origUrl : thumbUrl)
    : (thumbUrl.length > 0 ? thumbUrl : origUrl);
  const stillFallback = preferOriginal ? thumbUrl : origUrl;

  if (liveVideoUrl.length > 0) {
    const imageExt = itemFileExt(item);
    const stillExt = imageExt.length > 0 ? imageExt : 'jpg';
    const imagePath = `${context.cacheDir}/live_${id}_img.${stillExt}`;
    const videoPath = `${context.cacheDir}/live_${id}_vid.mp4`;
    const imgTask = downloadStillWithFallback(
      stillUrl,
      stillFallback,
      imagePath,
      preferOriginal ? 120000 : 20000,
      preferOriginal ? 20000 : 120000
    );
    const vidTask = downloadUrlToFile(liveVideoUrl, videoPath, 120000);
    const imgOk = await imgTask;
    const vidOk = await vidTask;
    if (!imgOk || !vidOk) {
      await unlinkQuiet(imagePath);
      await unlinkQuiet(videoPath);
      return undefined;
    }
    return makePair(imagePath, videoPath);
  }

  // 单文件 Motion Photo / livp：视频嵌在原图里，必须拉原图再拆
  const sourceUrl = origUrl.length > 0 ? origUrl : thumbUrl;
  if (sourceUrl.length === 0) {
    return undefined;
  }
  let buf = await downloadUrlToBuffer(sourceUrl, 120000);
  if ((buf === undefined || buf.byteLength === 0) && thumbUrl.length > 0 && thumbUrl !== sourceUrl) {
    buf = await downloadUrlToBuffer(thumbUrl, 30000);
  }
  if (buf === undefined || buf.byteLength === 0) {
    return undefined;
  }
  const split = splitEmbeddedLivePhoto(buf, itemFileExt(item));
  if (split === undefined) {
    return undefined;
  }
  const imagePath = `${context.cacheDir}/live_${id}_img.${split.imageExt}`;
  const videoPath = `${context.cacheDir}/live_${id}_vid.${split.videoExt}`;
  const imgOk = await writeBufferToFile(imagePath, split.imageBytes);
  const vidOk = await writeBufferToFile(videoPath, split.videoBytes);
  if (!imgOk || !vidOk) {
    await unlinkQuiet(imagePath);
    await unlinkQuiet(videoPath);
    return undefined;
  }
  return makePair(imagePath, videoPath);
}

export async function loadMovingPhotoFromPair(
  context: Context,
  pair: LivePhotoPairFiles
): Promise<photoAccessHelper.MovingPhoto | undefined> {
  if (pair.imageUri.length === 0 || pair.videoUri.length === 0) {
    return undefined;
  }
  try {
    return await photoAccessHelper.MediaAssetManager.loadMovingPhoto(context, pair.imageUri, pair.videoUri);
  } catch (_e) {
    return undefined;
  }
}
