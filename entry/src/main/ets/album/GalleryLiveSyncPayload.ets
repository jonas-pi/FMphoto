/**
 * 鸿蒙实况同步成飞牛能识别的一个文件。
 * URI 尾部已有短视频时，直接用这份原文件。
 * 没有时，封面和短视频是两条资源，接成带 MicroVideoOffset 的一个 JPEG 再上传。
 * 不单独上传封面。
 */
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { contentFingerprintOf } from './GalleryContentHash';
import { assembleLiveFile, fileHasEmbeddedLiveVideo } from './GalleryLiveSyncIo';
import { exportLocalMovingPhotoPair } from './livephoto/LivePhotoUpload';

let liveFileSeq: number = 1;

export class LiveSyncPayload {
  /** 要上传的文件。原文件已含短视频时就是资源 URI。 */
  uploadUri: string = '';
  /** 拼接出来的临时文件，上传结束或确认已存在后删除。空串表示不拥有文件。 */
  ownedPath: string = '';
  fingerprint: string = '';
}

async function deleteQuiet(path: string): Promise<void> {
  if (path.length === 0) {
    return;
  }
  try {
    await fileIo.unlink(path);
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
  fileName: string
): Promise<LiveSyncPayload | null> {
  let embedded = false;
  try {
    embedded = await taskpool.execute(liveHasEmbeddedConcurrent, sourceUri) as boolean;
  } catch (_e) {
    embedded = false;
  }
  if (embedded) {
    const fingerprint = await contentFingerprintOf(sourceUri);
    if (fingerprint.length === 0) {
      return null;
    }
    const ready = new LiveSyncPayload();
    ready.uploadUri = sourceUri;
    ready.fingerprint = fingerprint.toLowerCase();
    return ready;
  }
  const pair = await exportLocalMovingPhotoPair(ctx, sourceUri);
  if (pair === undefined) {
    return null;
  }
  const outPath = `${ctx.cacheDir}/sync${liveFileSeq}_${safeFileName(fileName)}`;
  liveFileSeq++;
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
    const fingerprint = await contentFingerprintOf(outPath);
    if (fingerprint.length === 0) {
      await deleteQuiet(outPath);
      return null;
    }
    const ready = new LiveSyncPayload();
    ready.uploadUri = fileUri.getUriFromPath(outPath);
    ready.ownedPath = outPath;
    ready.fingerprint = fingerprint.toLowerCase();
    return ready;
  } finally {
    await deleteQuiet(pair.imagePath);
    await deleteQuiet(pair.videoPath);
  }
}

export async function deleteOwnedLivePayload(path: string): Promise<void> {
  await deleteQuiet(path);
}
