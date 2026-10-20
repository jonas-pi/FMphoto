/**
 * 鸿蒙实况同步成飞牛能识别的一个文件。
 * URI 尾部已有短视频时，直接用这份原文件。
 * 没有时，封面和短视频是两条资源，接成带 MicroVideoOffset 的一个 JPEG 再上传。
 * 不单独上传封面。
 */
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { assembleLiveFile, fileHasEmbeddedLiveVideo } from './GalleryLiveSyncIo';
import { FnClientResult } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { exportLocalMovingPhotoPair, localMovingPhotoDisplayName } from './livephoto/LivePhotoUpload';

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

/** 查文件尾是否已有短视频。放到 TaskPool，避免读最多 32MB 时卡住界面。 */
@Concurrent
function liveHasEmbeddedConcurrent(pathOrUri: string): boolean {
  return fileHasEmbeddedLiveVideo(pathOrUri);
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
  let embedded = false;
  try {
    embedded = await taskpool.execute(liveHasEmbeddedConcurrent, sourceUri) as boolean;
  } catch (_e) {
    embedded = false;
  }
  if (embedded) {
    const ready = new LiveSyncPayload();
    ready.uploadUri = sourceUri;
    return ready;
  }
  const pair = await exportLocalMovingPhotoPair(ctx, sourceUri);
  if (pair === undefined) {
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
    let wrote = false;
    try {
      wrote = await taskpool.execute(assembleLiveConcurrent, pair.imagePath, pair.videoPath, outPath) as boolean;
    } catch (_e) {
      wrote = false;
    }
    if (!wrote) {
      await deleteQuiet(outPath);
      return null;
    }
    const ready = new LiveSyncPayload();
    ready.uploadUri = fileUri.getUriFromPath(outPath);
    ready.ownedPath = outPath;
    return ready;
  } finally {
    await deleteQuiet(pair.imagePath);
    await deleteQuiet(pair.videoPath);
  }
}

export async function deleteOwnedLivePayload(path: string): Promise<void> {
  await deleteQuiet(path);
}

/**
 * 手动上传：实况合成一份带短视频的文件再传。合成失败不改传封面。
 * 普通文件直接上传。
 */
export async function uploadLocalMediaUri(
  client: FnHttpClient,
  context: common.UIAbilityContext,
  uri: string,
  timeoutMs: number,
  albumDirHint?: string
): Promise<FnClientResult<Object>> {
  const movingName = await localMovingPhotoDisplayName(context, uri);
  if (movingName === undefined) {
    return client.uploadPhotoByUri(uri, timeoutMs, albumDirHint);
  }
  const payload = await prepareLiveSyncPayload(context, uri, movingName, true);
  if (payload === null) {
    return { success: false, message: '实况照片导出失败' };
  }
  try {
    return await client.uploadPhotoByUri(payload.uploadUri, timeoutMs, albumDirHint);
  } finally {
    await deleteOwnedLivePayload(payload.ownedPath);
  }
}
