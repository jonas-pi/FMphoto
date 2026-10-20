/**
 * 鸿蒙实况同步成飞牛能识别的一个文件。
 * URI 尾部已有短视频时，直接用这份原文件。
 * 没有时，封面和短视频是两条资源，接成带 MicroVideoOffset 的一个 JPEG 再上传。
 * 不单独上传封面。
 */
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { fnDiagRecord } from '../common/FnDiagLog';
import { assembleLiveFile } from './GalleryLiveSyncIo';
import { FnClientResult } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { isLiveExportCachePath } from './livephoto/LivePhotoSandbox';
import {
  exportLocalMovingPhotoPair,
  localMovingPhotoDisplayName,
  openLiveMovingPhotoForSync
} from './livephoto/LivePhotoUpload';

const LIVE_SYNC_TAG: string = 'LiveSyncPayload';

let liveFileSeq: number = 1;

export class LiveSyncPayload {
  /** 要上传的文件。原文件已含短视频时就是资源 URI。 */
  uploadUri: string = '';
  /** 拼接出来的临时文件，上传结束或确认已存在后删除。空串表示不拥有文件。 */
  ownedPath: string = '';
}

async function deleteQuiet(path: string): Promise<void> {
  if (path.length === 0) {
    return;
  }
  try {
    await fileIo.unlink(path);
  } catch (_e) {
  }
  const slash = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  if (slash <= 0) {
    return;
  }
  const parent = path.substring(0, slash);
  const parentSlash = Math.max(parent.lastIndexOf('/'), parent.lastIndexOf('\\'));
  const parentName = parentSlash >= 0 ? parent.substring(parentSlash + 1) : parent;
  if (!parentName.startsWith('liveup')) {
    return;
  }
  try {
    fileIo.rmdirSync(parent);
  } catch (_e) {
  }
}

function pathByteSize(path: string): number {
  try {
    const size = Number(fileIo.statSync(path).size);
    return Number.isFinite(size) && size > 0 ? Math.floor(size) : 0;
  } catch (_e) {
    return 0;
  }
}

function safeFileName(name: string): string {
  const cleaned = name.replace(/[\\/:*?"<>|]/g, '_').trim();
  if (cleaned.length === 0) {
    return `live_${Date.now()}.jpg`;
  }
  const lower = cleaned.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return cleaned;
  }
  return `${cleaned}.jpg`;
}

/** 把封面和短视频接成一个文件。整段拷贝留在后台线程。 */
@Concurrent
function assembleLiveConcurrent(imagePath: string, videoPath: string, outPath: string): boolean {
  return assembleLiveFile(imagePath, videoPath, outPath);
}

/**
 * 准备这一条实况实际上传的那一份字节。
 * 尾部没有短视频时返回 null，调用方不得改传封面。
 */
export async function prepareLiveSyncPayload(
  ctx: common.UIAbilityContext,
  sourceUri: string,
  fileName: string,
  keepDisplayName: boolean = false
): Promise<LiveSyncPayload | null> {
  const opened = await openLiveMovingPhotoForSync(ctx, sourceUri);
  if (opened !== undefined && opened.directUploadUri.length > 0) {
    const ready = new LiveSyncPayload();
    ready.uploadUri = opened.directUploadUri;
    fnDiagRecord('I', LIVE_SYNC_TAG, 'upload original embedded live');
    return ready;
  }
  const pair = await exportLocalMovingPhotoPair(
    ctx,
    sourceUri,
    opened !== undefined ? opened.movingPhoto : undefined
  );
  if (pair === undefined) {
    fnDiagRecord('W', LIVE_SYNC_TAG, 'prepare null: export pair failed');
    return null;
  }
  let outPath = '';
  if (keepDisplayName) {
    const dir = `${ctx.cacheDir}/liveup${liveFileSeq}`;
    liveFileSeq++;
    try {
      fileIo.mkdirSync(dir);
    } catch (_e) {
    }
    outPath = `${dir}/${safeFileName(fileName)}`;
  } else {
    outPath = `${ctx.cacheDir}/sync${liveFileSeq}_${safeFileName(fileName)}`;
    liveFileSeq++;
  }
  try {
    let wrote = assembleLiveFile(pair.imagePath, pair.videoPath, outPath);
    if (!wrote) {
      try {
        wrote = await taskpool.execute(assembleLiveConcurrent, pair.imagePath, pair.videoPath, outPath) as boolean;
      } catch (_e) {
        wrote = false;
      }
    }
    if (!wrote) {
      let imageBytes = 0;
      let videoBytes = 0;
      try {
        imageBytes = Number(fileIo.statSync(pair.imagePath).size);
        videoBytes = Number(fileIo.statSync(pair.videoPath).size);
      } catch (_e) {
      }
      fnDiagRecord('W', LIVE_SYNC_TAG, `prepare null: assemble failed img=${imageBytes} vid=${videoBytes}`);
      await deleteQuiet(outPath);
      return null;
    }
    const uploadBytes = pathByteSize(outPath);
    const expect = opened !== undefined ? opened.expectedAssetBytes : 0;
    if (expect > 0 && uploadBytes < Math.floor(expect * 0.92)) {
      fnDiagRecord(
        'W',
        LIVE_SYNC_TAG,
        `assemble too small bytes=${uploadBytes} asset=${expect}, reject upload`
      );
      await deleteQuiet(outPath);
      return null;
    }
    const ready = new LiveSyncPayload();
    ready.uploadUri = fileUri.getUriFromPath(outPath);
    ready.ownedPath = outPath;
    fnDiagRecord('I', LIVE_SYNC_TAG, `assemble ok bytes=${uploadBytes} asset=${expect}`);
    return ready;
  } finally {
    if (!isLiveExportCachePath(pair.imagePath)) {
      await deleteQuiet(pair.imagePath);
    }
    if (!isLiveExportCachePath(pair.videoPath)) {
      await deleteQuiet(pair.videoPath);
    }
  }
}

export async function deleteOwnedLivePayload(path: string): Promise<void> {
  await deleteQuiet(path);
}

/**
 * 本机媒体上传（手动选图、分享入站、自动同步共用）。
 * 实况走导出+合成+体积校验；普通图直传 URI。
 * @param fileNameHint 同步队列里的展示名，合成输出文件名优先用它。
 */
export async function uploadLocalMediaUri(
  client: FnHttpClient,
  context: common.UIAbilityContext,
  uri: string,
  timeoutMs: number,
  albumDirHint?: string,
  fileNameHint?: string
): Promise<FnClientResult<Object>> {
  const movingName = await localMovingPhotoDisplayName(context, uri);
  if (movingName === undefined) {
    return client.uploadPhotoByUri(uri, timeoutMs, albumDirHint);
  }
  const outName =
    fileNameHint !== undefined && fileNameHint.trim().length > 0 ? fileNameHint.trim() : movingName;
  const payload = await prepareLiveSyncPayload(context, uri, outName, true);
  if (payload === null) {
    return { success: false, message: '实况照片导出失败' };
  }
  try {
    return await client.uploadPhotoByUri(payload.uploadUri, timeoutMs, albumDirHint);
  } finally {
    await deleteOwnedLivePayload(payload.ownedPath);
  }
}
