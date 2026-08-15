/**
 * 本机动态照片上传：检测 MOVING_PHOTO 后导出图+视频再分别上传。
 */
import { common } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { FnClientResult } from '../../model/FnApiTypes';
import { FnHttpClient } from '../../network/FnHttpClient';
import { LivePhotoPairFiles, unlinkLivePhotoPair } from './LivePhotoSandbox';
import { writeBufferToFile } from './MotionPhotoSplit';

class MovingPhotoReadyHandler implements photoAccessHelper.MediaAssetDataHandler<photoAccessHelper.MovingPhoto> {
  private resolveFn: (photo: photoAccessHelper.MovingPhoto | undefined) => void =
    (_: photoAccessHelper.MovingPhoto | undefined) => {};

  constructor(resolveFn: (photo: photoAccessHelper.MovingPhoto | undefined) => void) {
    this.resolveFn = resolveFn;
  }

  async onDataPrepared(movingPhoto: photoAccessHelper.MovingPhoto): Promise<void> {
    if (movingPhoto === undefined) {
      this.resolveFn(undefined);
      return;
    }
    this.resolveFn(movingPhoto);
  }
}

function fileNameFromUri(uri: string): string {
  const trimmed = uri.trim();
  const cut = trimmed.split('?')[0];
  const parts = cut.split('/');
  if (parts.length === 0) {
    return '';
  }
  try {
    return decodeURIComponent(parts[parts.length - 1]);
  } catch (_e) {
    return parts[parts.length - 1];
  }
}

function baseNameNoExt(name: string): string {
  const dot = name.lastIndexOf('.');
  const base = dot > 0 ? name.substring(0, dot) : name;
  const safe = base.replace(/[\\/:*?"<>|]/g, '_');
  return safe.length > 0 ? safe : `live_${Date.now()}`;
}

async function queryAssetByUri(
  context: Context,
  uri: string
): Promise<photoAccessHelper.PhotoAsset | undefined> {
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri);
    const fetchResult = await helper.getAssets({
      fetchColumns: [photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE, photoAccessHelper.PhotoKeys.DISPLAY_NAME],
      predicates: predicates
    });
    try {
      if (fetchResult.getCount() <= 0) {
        return undefined;
      }
      return await fetchResult.getFirstObject();
    } finally {
      fetchResult.close();
    }
  } catch (_e) {
    return undefined;
  }
}

function photoAssetSubtype(asset: photoAccessHelper.PhotoAsset): number {
  try {
    const raw = asset.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE);
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      return raw;
    }
    if (typeof raw === 'string') {
      const parsed = Number(raw);
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
  } catch (_e) {
  }
  return photoAccessHelper.PhotoSubtype.DEFAULT;
}

function requestMovingPhotoAsync(
  context: Context,
  asset: photoAccessHelper.PhotoAsset
): Promise<photoAccessHelper.MovingPhoto | undefined> {
  return new Promise<photoAccessHelper.MovingPhoto | undefined>((resolve) => {
    let settled = false;
    const finish = (photo: photoAccessHelper.MovingPhoto | undefined): void => {
      if (settled) {
        return;
      }
      settled = true;
      resolve(photo);
    };
    try {
      photoAccessHelper.MediaAssetManager.requestMovingPhoto(
        context,
        asset,
        { deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE },
        new MovingPhotoReadyHandler(finish)
      );
      setTimeout((): void => {
        finish(undefined);
      }, 15000);
    } catch (_e) {
      finish(undefined);
    }
  });
}

/**
 * 若 URI 指向系统动态照片，导出图+视频到缓存；否则返回 undefined。
 */
export async function exportLocalMovingPhotoPair(
  context: common.UIAbilityContext,
  uri: string
): Promise<LivePhotoPairFiles | undefined> {
  const asset = await queryAssetByUri(context, uri);
  if (asset === undefined) {
    return undefined;
  }
  if (photoAssetSubtype(asset) !== photoAccessHelper.PhotoSubtype.MOVING_PHOTO) {
    return undefined;
  }
  const movingPhoto = await requestMovingPhotoAsync(context, asset);
  if (movingPhoto === undefined) {
    return undefined;
  }
  const display = asset.displayName ?? fileNameFromUri(uri);
  const base = baseNameNoExt(display);
  const stamp = Date.now();
  const imagePath = `${context.cacheDir}/upload_${base}_${stamp}.jpg`;
  const videoPath = `${context.cacheDir}/upload_${base}_${stamp}.mp4`;
  try {
    await movingPhoto.requestContent(imagePath, videoPath);
    const pair = new LivePhotoPairFiles();
    pair.imagePath = imagePath;
    pair.videoPath = videoPath;
    pair.imageUri = fileUri.getUriFromPath(imagePath);
    pair.videoUri = fileUri.getUriFromPath(videoPath);
    return pair;
  } catch (_e) {
    try {
      const imageData = await movingPhoto.requestContent(photoAccessHelper.ResourceType.IMAGE_RESOURCE);
      const videoData = await movingPhoto.requestContent(photoAccessHelper.ResourceType.VIDEO_RESOURCE);
      const imgOk = await writeBufferToFile(imagePath, imageData);
      const vidOk = await writeBufferToFile(videoPath, videoData);
      if (!imgOk || !vidOk) {
        return undefined;
      }
      const pair = new LivePhotoPairFiles();
      pair.imagePath = imagePath;
      pair.videoPath = videoPath;
      pair.imageUri = fileUri.getUriFromPath(imagePath);
      pair.videoUri = fileUri.getUriFromPath(videoPath);
      return pair;
    } catch (_e2) {
      return undefined;
    }
  }
}

/**
 * 动态照片则先传封面再传伴生视频；普通 URI 走原上传。
 */
export async function uploadUriMaybeMovingPhoto(
  client: FnHttpClient,
  context: common.UIAbilityContext,
  uri: string,
  timeoutMs: number,
  albumDirHint?: string
): Promise<FnClientResult<Object>> {
  const pair = await exportLocalMovingPhotoPair(context, uri);
  if (pair === undefined) {
    return client.uploadPhotoByUri(uri, timeoutMs, albumDirHint);
  }
  try {
    const imgRes = await client.uploadPhotoByUri(pair.imageUri, timeoutMs, albumDirHint);
    if (!imgRes.success) {
      return imgRes;
    }
    const vidRes = await client.uploadPhotoByUri(pair.videoUri, timeoutMs, albumDirHint);
    if (!vidRes.success) {
      return vidRes;
    }
    return imgRes;
  } finally {
    await unlinkLivePhotoPair(pair);
  }
}
