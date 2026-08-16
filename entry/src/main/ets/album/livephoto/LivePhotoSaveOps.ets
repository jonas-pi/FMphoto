/**
 * 实况落盘：优先写成系统动态照片（PhotoSubtype.MOVING_PHOTO）。
 * 无 WRITE_IMAGEVIDEO 时须在 SaveButton 点击授权窗口内调用。
 * 系统拒收时（常见于 iOS HEIC+MOV）再把封面和视频成对写入。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { copyGalleryUriContentToAlbumUri } from '../GalleryAlbumSaveToAlbum';
import { extFromFilePath } from './MotionPhotoSplit';
import { LivePhotoPairFiles } from './LivePhotoSandbox';

const LOG_DOMAIN: number = 0xFF00;
const LOG_TAG: string = 'LivePhotoSave';

/**
 * 媒体库 title 不含扩展名，且不能包含 . \\ / : * ? " ' ` < > | { } [ ]
 */
export function sanitizeMediaTitle(raw: string, fallback: string): string {
  let base = raw.trim();
  const dot = base.lastIndexOf('.');
  if (dot > 0) {
    base = base.substring(0, dot);
  }
  let out = '';
  for (let i = 0; i < base.length; i++) {
    const ch = base.charAt(i);
    const code = base.charCodeAt(i);
    const illegal = code < 32 ||
      ch === '.' || ch === '\\' || ch === '/' || ch === ':' || ch === '*' ||
      ch === '?' || ch === '"' || ch === "'" || ch === '`' || ch === '<' ||
      ch === '>' || ch === '|' || ch === '{' || ch === '}' || ch === '[' || ch === ']';
    if (illegal) {
      if (out.length === 0 || out.charAt(out.length - 1) !== '_') {
        out += '_';
      }
    } else {
      out += ch;
    }
  }
  while (out.length > 0 && out.charAt(0) === '_') {
    out = out.substring(1);
  }
  while (out.length > 0 && out.charAt(out.length - 1) === '_') {
    out = out.substring(0, out.length - 1);
  }
  if (out.length > 80) {
    out = out.substring(0, 80);
  }
  if (out.length === 0 || out === '_' || out === '..') {
    return fallback;
  }
  return out;
}

function imageExtForAsset(path: string): string {
  const ext = extFromFilePath(path);
  if (ext === 'jpg' || ext === 'jpeg' || ext === 'png' || ext === 'heic' || ext === 'heif') {
    return ext === 'jpeg' ? 'jpg' : ext;
  }
  return 'jpg';
}

function videoExtForAlbum(path: string): string {
  const ext = extFromFilePath(path);
  if (ext === 'mp4' || ext === 'mov' || ext === 'm4v') {
    return ext;
  }
  return 'mp4';
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

async function tryCreateMovingPhoto(
  context: common.UIAbilityContext,
  imageUri: string,
  videoUri: string,
  imageExt: string,
  title: string
): Promise<boolean> {
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const req: photoAccessHelper.MediaAssetChangeRequest =
      photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
        context,
        photoAccessHelper.PhotoType.IMAGE,
        imageExt,
        {
          title: title,
          subtype: photoAccessHelper.PhotoSubtype.MOVING_PHOTO
        }
      );
    req.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, imageUri);
    req.addResource(photoAccessHelper.ResourceType.VIDEO_RESOURCE, videoUri);
    await helper.applyChanges(req);
    return true;
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(LOG_DOMAIN, LOG_TAG, `create moving photo failed: ${err.code} ${err.message}`);
    return false;
  }
}

/**
 * 将成对静帧+短视频写成系统动态照片。须在 SaveButton 授权窗口内调用。
 */
export async function createMovingPhotoAsset(
  context: common.UIAbilityContext,
  pair: LivePhotoPairFiles,
  title: string
): Promise<boolean> {
  if (pair.imageUri.length === 0 || pair.videoUri.length === 0) {
    return false;
  }
  const safeTitle = sanitizeMediaTitle(title, `moving_photo_${Date.now()}`);
  const imageExt = imageExtForAsset(pair.imagePath);
  if (await tryCreateMovingPhoto(context, pair.imageUri, pair.videoUri, imageExt, safeTitle)) {
    return true;
  }
  const vidExt = videoExtForAlbum(pair.videoPath);
  if (vidExt === 'mp4') {
    return false;
  }
  const mp4Path = `${pair.videoPath}.mp4`;
  try {
    await fileIo.copyFile(pair.videoPath, mp4Path);
    const mp4Uri = fileUri.getUriFromPath(mp4Path);
    const ok = await tryCreateMovingPhoto(context, pair.imageUri, mp4Uri, imageExt, safeTitle);
    await unlinkQuiet(mp4Path);
    return ok;
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(LOG_DOMAIN, LOG_TAG, `moving photo mp4 retry failed: ${err.code} ${err.message}`);
    await unlinkQuiet(mp4Path);
    return false;
  }
}

/**
 * SaveButton 授权窗口内保存普通图/视频。
 */
export async function saveSandboxAssetWithPrivilege(
  context: common.UIAbilityContext,
  fileUriStr: string,
  title: string,
  ext: string,
  photoType: photoAccessHelper.PhotoType
): Promise<boolean> {
  if (fileUriStr.length === 0) {
    return false;
  }
  const safeTitle = sanitizeMediaTitle(title, `nas_${Date.now()}`);
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const req: photoAccessHelper.MediaAssetChangeRequest =
      photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
        context,
        photoType,
        ext,
        { title: safeTitle }
      );
    const resourceType = photoType === photoAccessHelper.PhotoType.VIDEO ?
      photoAccessHelper.ResourceType.VIDEO_RESOURCE :
      photoAccessHelper.ResourceType.IMAGE_RESOURCE;
    req.addResource(resourceType, fileUriStr);
    await helper.applyChanges(req);
    return true;
  } catch (e) {
    const err = e as BusinessError;
    hilog.error(LOG_DOMAIN, LOG_TAG, `privilege save failed: ${err.code} ${err.message}`);
    return false;
  }
}

export function appendStillAndVideoToPrepare(
  pair: LivePhotoPairFiles,
  title: string,
  preparedFileUris: string[],
  preparedConfigs: photoAccessHelper.PhotoCreationConfig[]
): void {
  const safeTitle = sanitizeMediaTitle(title, `live_${Date.now()}`);
  preparedFileUris.push(pair.imageUri);
  preparedConfigs.push({
    title: safeTitle,
    fileNameExtension: imageExtForAsset(pair.imagePath),
    photoType: photoAccessHelper.PhotoType.IMAGE
  });
  preparedFileUris.push(pair.videoUri);
  preparedConfigs.push({
    title: `${safeTitle}_live`,
    fileNameExtension: videoExtForAlbum(pair.videoPath),
    photoType: photoAccessHelper.PhotoType.VIDEO
  });
}

export async function saveStillAndVideoToAlbum(
  context: common.UIAbilityContext,
  pair: LivePhotoPairFiles,
  title: string
): Promise<number> {
  const preparedFileUris: string[] = [];
  const preparedConfigs: photoAccessHelper.PhotoCreationConfig[] = [];
  appendStillAndVideoToPrepare(pair, title, preparedFileUris, preparedConfigs);
  try {
    const targetUris = await photoAccessHelper
      .getPhotoAccessHelper(context)
      .showAssetsCreationDialog(preparedFileUris, preparedConfigs);
    if (targetUris.length === 0) {
      return 0;
    }
    const limit = Math.min(targetUris.length, preparedFileUris.length);
    for (let i = 0; i < limit; i++) {
      const saved = await copyGalleryUriContentToAlbumUri(preparedFileUris[i], targetUris[i]);
      if (!saved) {
        return -1;
      }
    }
    return limit;
  } catch (_e) {
    return -1;
  }
}

export type LivePhotoSaveKind = 'moving' | 'pair' | 'cancel' | 'fail';

/**
 * 优先写成动态照片；失败则封面+视频成对保存。
 * mediaWriteAuthorized 为 true 时走 SaveButton 特权写入。
 */
export async function saveLivePhotoToAlbum(
  context: common.UIAbilityContext,
  pair: LivePhotoPairFiles,
  title: string,
  mediaWriteAuthorized: boolean
): Promise<LivePhotoSaveKind> {
  const safeTitle = sanitizeMediaTitle(title, `live_${Date.now()}`);
  if (mediaWriteAuthorized) {
    if (await createMovingPhotoAsset(context, pair, safeTitle)) {
      return 'moving';
    }
    const imgOk = await saveSandboxAssetWithPrivilege(
      context,
      pair.imageUri,
      safeTitle,
      imageExtForAsset(pair.imagePath),
      photoAccessHelper.PhotoType.IMAGE
    );
    const vidOk = await saveSandboxAssetWithPrivilege(
      context,
      pair.videoUri,
      `${safeTitle}_live`,
      videoExtForAlbum(pair.videoPath),
      photoAccessHelper.PhotoType.VIDEO
    );
    if (imgOk && vidOk) {
      return 'pair';
    }
    return 'fail';
  }
  const savedCount = await saveStillAndVideoToAlbum(context, pair, safeTitle);
  if (savedCount < 0) {
    return 'fail';
  }
  if (savedCount === 0) {
    return 'cancel';
  }
  return 'pair';
}
