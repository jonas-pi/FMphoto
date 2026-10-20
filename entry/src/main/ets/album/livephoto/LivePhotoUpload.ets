/**
 * 本机动态照片：识别 MOVING_PHOTO，并导出封面和短视频供合成。
 */
import { common } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagRecord } from '../../common/FnDiagLog';
import { copyFileSync, fileHasEmbeddedLiveVideo } from '../GalleryLiveSyncIo';
import { isLiveExportCachePath, LivePhotoPairFiles } from './LivePhotoSandbox';
import { writeBufferToFile } from './MotionPhotoSplit';

/** 同步实况：优先直传内嵌原文件，否则用已打开的 MovingPhoto 做无损导出。 */
export class LiveMovingPhotoOpenResult {
  /** 可直接上传、无需再合成的媒体库 URI。 */
  directUploadUri: string = '';
  movingPhoto: photoAccessHelper.MovingPhoto | undefined = undefined;
  expectedAssetBytes: number = 0;
}

const LOG_DOMAIN: number = 0xFF00;
const LOG_TAG: string = 'LivePhotoUpload';
const MOVING_PHOTO_WAIT_MS: number = 60000;
const LIVE_EXPORT_CACHE_DIR: string = 'live_export_cache';

class MovingPhotoReadyHandler implements photoAccessHelper.MediaAssetDataHandler<photoAccessHelper.MovingPhoto> {
  /** 系统回调不绑定 this，必须用闭包接住结果。 */
  onDataPrepared: (movingPhoto: photoAccessHelper.MovingPhoto) => Promise<void>;

  constructor(resolveFn: (photo: photoAccessHelper.MovingPhoto | undefined) => void) {
    this.onDataPrepared = (movingPhoto: photoAccessHelper.MovingPhoto): Promise<void> => {
      resolveFn(movingPhoto);
      return Promise.resolve();
    };
  }
}

function logExportFail(reason: string): void {
  hilog.warn(LOG_DOMAIN, LOG_TAG, 'export fail %{public}s', reason);
  fnDiagRecord('W', LOG_TAG, `export fail ${reason}`);
}

function pathByteSize(path: string): number {
  try {
    const size = Number(fileIo.statSync(path).size);
    return Number.isFinite(size) && size > 0 ? Math.floor(size) : 0;
  } catch (_e) {
    return 0;
  }
}

async function createEmptyFile(path: string): Promise<void> {
  const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  await fileIo.close(file.fd);
}

function assetNumber(asset: photoAccessHelper.PhotoAsset, key: string): number {
  try {
    const raw = asset.get(key);
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
  return 0;
}

function exportCacheKey(uri: string, assetSize: number, mtimeMs: number): string {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < uri.length; i++) {
    h ^= uri.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  const mt = Math.floor(mtimeMs);
  const sz = Math.floor(assetSize);
  return `${mt}_${sz}_${h.toString(16)}`;
}

function exportCacheRoot(ctx: common.UIAbilityContext): string {
  return `${ctx.filesDir}/${LIVE_EXPORT_CACHE_DIR}`;
}

function cachedPairPaths(ctx: common.UIAbilityContext, key: string): LivePhotoPairFiles {
  const dir = `${exportCacheRoot(ctx)}/${key}`;
  const pair = new LivePhotoPairFiles();
  pair.imagePath = `${dir}/cover.jpg`;
  pair.videoPath = `${dir}/clip.mp4`;
  pair.imageUri = fileUri.getUriFromPath(pair.imagePath);
  pair.videoUri = fileUri.getUriFromPath(pair.videoPath);
  pair.fromExportCache = true;
  return pair;
}

function tryLoadExportCache(
  ctx: common.UIAbilityContext,
  key: string,
  expectedAssetBytes: number
): LivePhotoPairFiles | undefined {
  const pair = cachedPairPaths(ctx, key);
  const img = pathByteSize(pair.imagePath);
  const vid = pathByteSize(pair.videoPath);
  if (img < 64 || vid < 64) {
    return undefined;
  }
  const sum = img + vid;
  if (expectedAssetBytes > 0 && sum < Math.floor(expectedAssetBytes * 0.85)) {
    fnDiagRecord('W', LOG_TAG, `export cache low quality sum=${sum} asset=${expectedAssetBytes}`);
    return undefined;
  }
  fnDiagRecord('I', LOG_TAG, `export cache hit img=${img} vid=${vid}`);
  return pair;
}

async function persistExportCache(
  ctx: common.UIAbilityContext,
  key: string,
  imagePath: string,
  videoPath: string
): Promise<LivePhotoPairFiles | undefined> {
  const pair = cachedPairPaths(ctx, key);
  try {
    fileIo.mkdirSync(exportCacheRoot(ctx));
  } catch (_e) {
  }
  try {
    fileIo.mkdirSync(`${exportCacheRoot(ctx)}/${key}`);
  } catch (_e) {
  }
  const imgOk = copyFileSync(imagePath, pair.imagePath);
  const vidOk = copyFileSync(videoPath, pair.videoPath);
  if (!imgOk || !vidOk) {
    return undefined;
  }
  return pair;
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
      fetchColumns: [
        photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE,
        photoAccessHelper.PhotoKeys.DISPLAY_NAME,
        photoAccessHelper.PhotoKeys.SIZE,
        photoAccessHelper.PhotoKeys.DATE_MODIFIED_MS
      ],
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

/** 相册 SIZE 与可读文件差距过大时，多为系统提供的压缩内嵌版，不能当原图直传。 */
const EMBEDDED_SIZE_MIN_RATIO: number = 0.92;

function embeddedUriIfReadable(uri: string, expectedAssetBytes: number): string {
  const trimmed = uri.trim();
  if (trimmed.length === 0) {
    return '';
  }
  try {
    if (!fileHasEmbeddedLiveVideo(trimmed)) {
      return '';
    }
    const actual = pathByteSize(trimmed);
    if (actual < 64) {
      return '';
    }
    if (expectedAssetBytes > 0 && actual < Math.floor(expectedAssetBytes * EMBEDDED_SIZE_MIN_RATIO)) {
      fnDiagRecord(
        'W',
        LOG_TAG,
        `embedded too small asset=${expectedAssetBytes} file=${actual} skip direct`
      );
      return '';
    }
    fnDiagRecord('I', LOG_TAG, `embedded ok asset=${expectedAssetBytes} file=${actual}`);
    return trimmed;
  } catch (_e) {
  }
  return '';
}

/**
 * 打开动态照片：优先返回系统内嵌原文件 URI（不经过 requestContent 重编码）。
 * 否则返回 HIGH_QUALITY MovingPhoto，供原样 requestContent 到缓存。
 */
export async function openLiveMovingPhotoForSync(
  context: common.UIAbilityContext,
  uri: string
): Promise<LiveMovingPhotoOpenResult | undefined> {
  const asset = await queryAssetByUri(context, uri);
  if (asset === undefined || photoAssetSubtype(asset) !== photoAccessHelper.PhotoSubtype.MOVING_PHOTO) {
    return undefined;
  }
  const assetSize = assetNumber(asset, photoAccessHelper.PhotoKeys.SIZE);
  const direct = embeddedUriIfReadable(uri, assetSize);
  if (direct.length > 0) {
    const out = new LiveMovingPhotoOpenResult();
    out.directUploadUri = direct;
    fnDiagRecord('I', LOG_TAG, 'sync use embedded source uri');
    return out;
  }
  const movingPhoto = await requestMovingPhotoAsync(context, asset);
  if (movingPhoto === undefined) {
    return undefined;
  }
  try {
    const fromMoving = embeddedUriIfReadable(movingPhoto.getUri(), assetSize);
    if (fromMoving.length > 0) {
      const out = new LiveMovingPhotoOpenResult();
      out.directUploadUri = fromMoving;
      fnDiagRecord('I', LOG_TAG, 'sync use movingPhoto.getUri embedded');
      return out;
    }
  } catch (_e) {
  }
  const out = new LiveMovingPhotoOpenResult();
  out.movingPhoto = movingPhoto;
  out.expectedAssetBytes = assetSize;
  return out;
}

async function requestMovingPhotoAsync(
  context: Context,
  asset: photoAccessHelper.PhotoAsset
): Promise<photoAccessHelper.MovingPhoto | undefined> {
  return await new Promise<photoAccessHelper.MovingPhoto | undefined>((resolve) => {
    let settled = false;
    let timer: number = -1;
    const finish = (photo: photoAccessHelper.MovingPhoto | undefined): void => {
      if (settled) {
        return;
      }
      settled = true;
      if (timer >= 0) {
        clearTimeout(timer);
      }
      resolve(photo);
    };
    timer = setTimeout((): void => {
      finish(undefined);
    }, MOVING_PHOTO_WAIT_MS);
    void photoAccessHelper.MediaAssetManager.requestMovingPhoto(
      context,
      asset,
      { deliveryMode: photoAccessHelper.DeliveryMode.HIGH_QUALITY_MODE },
      new MovingPhotoReadyHandler(finish)
    ).catch((): void => {
      finish(undefined);
    });
  });
}

/**
 * 若 URI 指向系统动态照片，导出图+视频到缓存；否则返回 undefined。
 */
export async function exportLocalMovingPhotoPair(
  context: common.UIAbilityContext,
  uri: string,
  movingPhotoReady: photoAccessHelper.MovingPhoto | undefined = undefined
): Promise<LivePhotoPairFiles | undefined> {
  const asset = await queryAssetByUri(context, uri);
  if (asset === undefined) {
    logExportFail('asset not found');
    return undefined;
  }
  if (photoAssetSubtype(asset) !== photoAccessHelper.PhotoSubtype.MOVING_PHOTO) {
    logExportFail('not MOVING_PHOTO');
    return undefined;
  }
  const assetSize = assetNumber(asset, photoAccessHelper.PhotoKeys.SIZE);
  let mtimeMs = assetNumber(asset, photoAccessHelper.PhotoKeys.DATE_MODIFIED_MS);
  if (mtimeMs <= 0) {
    mtimeMs = assetNumber(asset, photoAccessHelper.PhotoKeys.DATE_MODIFIED) * 1000;
  }
  const cacheKey = exportCacheKey(uri, assetSize, mtimeMs);
  const cached = tryLoadExportCache(context, cacheKey, assetSize);
  if (cached !== undefined) {
    return cached;
  }
  const movingPhoto = movingPhotoReady ?? await requestMovingPhotoAsync(context, asset);
  if (movingPhoto === undefined) {
    logExportFail('requestMovingPhoto timeout');
    return undefined;
  }
  const display = asset.displayName ?? fileNameFromUri(uri);
  const base = baseNameNoExt(display);
  const stamp = Date.now();
  const imagePath = `${context.cacheDir}/upload_${base}_${stamp}.jpg`;
  const videoPath = `${context.cacheDir}/upload_${base}_${stamp}.mp4`;
  const imageFileUri = fileUri.getUriFromPath(imagePath);
  const videoFileUri = fileUri.getUriFromPath(videoPath);
  try {
    await createEmptyFile(imagePath);
    await createEmptyFile(videoPath);
  } catch (_e) {
    logExportFail('create cache file failed');
    return undefined;
  }
  let wroteByUri = false;
  try {
    await movingPhoto.requestContent(imageFileUri, videoFileUri);
    wroteByUri = pathByteSize(imagePath) >= 64 && pathByteSize(videoPath) >= 64;
  } catch (_e) {
    wroteByUri = false;
  }
  if (!wroteByUri) {
    try {
      const imageData = await movingPhoto.requestContent(photoAccessHelper.ResourceType.IMAGE_RESOURCE);
      const videoData = await movingPhoto.requestContent(photoAccessHelper.ResourceType.VIDEO_RESOURCE);
      const imgOk = await writeBufferToFile(imagePath, imageData);
      const vidOk = await writeBufferToFile(videoPath, videoData);
      if (!imgOk || !vidOk) {
        logExportFail(
          `buffer write img=${imgOk}/${imageData.byteLength} vid=${vidOk}/${videoData.byteLength}`
        );
        return undefined;
      }
    } catch (_e2) {
      logExportFail('requestContent failed');
      return undefined;
    }
  }
  const imageBytes = pathByteSize(imagePath);
  const videoBytes = pathByteSize(videoPath);
  if (imageBytes < 64 || videoBytes < 64) {
    logExportFail(`short content img=${imageBytes} vid=${videoBytes}`);
    return undefined;
  }
  fnDiagRecord('I', LOG_TAG, `export ok img=${imageBytes} vid=${videoBytes}`);
  const stored = await persistExportCache(context, cacheKey, imagePath, videoPath);
  if (stored !== undefined) {
    await deleteQuietExportTemp(imagePath);
    await deleteQuietExportTemp(videoPath);
    return stored;
  }
  fnDiagRecord('W', LOG_TAG, 'export cache persist failed, use temp files');
  const pair = new LivePhotoPairFiles();
  pair.imagePath = imagePath;
  pair.videoPath = videoPath;
  pair.imageUri = imageFileUri;
  pair.videoUri = videoFileUri;
  return pair;
}

async function deleteQuietExportTemp(path: string): Promise<void> {
  if (path.length === 0 || isLiveExportCachePath(path)) {
    return;
  }
  try {
    await fileIo.unlink(path);
  } catch (_e) {
  }
}

/** 是实况则返回展示文件名，否则返回 undefined。 */
export async function localMovingPhotoDisplayName(
  context: common.UIAbilityContext,
  uri: string
): Promise<string | undefined> {
  const asset = await queryAssetByUri(context, uri);
  if (asset === undefined || photoAssetSubtype(asset) !== photoAccessHelper.PhotoSubtype.MOVING_PHOTO) {
    return undefined;
  }
  const displayRaw = asset.displayName;
  if (displayRaw !== undefined && displayRaw.length > 0) {
    return displayRaw;
  }
  const fromUri = fileNameFromUri(uri);
  return fromUri.length > 0 ? fromUri : 'live.jpg';
}
