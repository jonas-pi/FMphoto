/**
 * 本机账本快筛后，用 NAS 全库的原始文件名+大小核对普通照片。
 * 未命中的才交给上传流程；服务端 notice 会做最终内容去重。
 */
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagRecord } from '../common/FnDiagLog';
import { FnHttpClient } from '../network/FnHttpClient';
import { GalleryAutoSyncLedger, LedgerPut } from './GalleryAutoSyncLedger';
import { GalleryAutoSyncNasIndex } from './GalleryAutoSyncNasIndex';
import { LocalPhotoEntry } from './GalleryAutoSyncService';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncCompare';

export class SyncUploadPiece {
  sourceUri: string = '';
  fileName: string = '';
  sourceSize: number = 0;
  sourceMtimeMs: number = 0;
  role: string = 'file';
}

export class ContentCompareResult {
  pieces: SyncUploadPiece[] = [];
  skippedInLedger: number = 0;
  skippedOnNas: number = 0;
  compareFailed: number = 0;
  unreadable: number = 0;
}

export interface ContentCompareProgress {
  onProgress(done: number, total: number, detail: string): void;
}

function makePiece(entry: LocalPhotoEntry, role: string): SyncUploadPiece {
  const piece = new SyncUploadPiece();
  piece.sourceUri = entry.uri;
  piece.fileName = entry.fileName;
  piece.sourceSize = entry.fileSize;
  piece.sourceMtimeMs = entry.dateModifiedMs;
  piece.role = role;
  return piece;
}

export async function compareLocalWithBackup(
  ctx: common.UIAbilityContext,
  client: FnHttpClient,
  photos: LocalPhotoEntry[],
  progress: ContentCompareProgress | null
): Promise<ContentCompareResult> {
  const result = new ContentCompareResult();
  await GalleryAutoSyncLedger.load(ctx);
  const pending: LocalPhotoEntry[] = [];
  for (let i = 0; i < photos.length; i++) {
    const photo = photos[i];
    if (photo.uri.length === 0) {
      continue;
    }
    const moving = photo.photoSubtype === photoAccessHelper.PhotoSubtype.MOVING_PHOTO;
    if (!moving && (photo.fileName.length === 0 || photo.fileSize <= 0)) {
      continue;
    }
    const settled = moving
      ? GalleryAutoSyncLedger.isLiveSettled(photo.uri)
      : GalleryAutoSyncLedger.isSettled(photo.uri, photo.fileSize, photo.dateModifiedMs);
    if (settled) {
      result.skippedInLedger++;
      continue;
    }
    pending.push(photo);
  }
  if (pending.length === 0) {
    return result;
  }
  if (progress !== null) {
    progress.onProgress(photos.length, photos.length, '正在核对 NAS 文件名单');
  }
  let hasNormalPending: boolean = false;
  for (let i = 0; i < pending.length; i++) {
    if (pending[i].photoSubtype !== photoAccessHelper.PhotoSubtype.MOVING_PHOTO) {
      hasNormalPending = true;
      break;
    }
  }
  let nasByName: boolean = false;
  if (hasNormalPending) {
    let nasIndex = await GalleryAutoSyncNasIndex.getIndex(client, false, ctx);
    // 兼容旧版留下的有效期内空索引；强制重建一次。
    if (nasIndex.nameSizeKeys.size === 0) {
      nasIndex = await GalleryAutoSyncNasIndex.getIndex(client, true, ctx);
    }
    nasByName = nasIndex.nameSizeKeys.size > 0;
  }
  const puts: LedgerPut[] = [];
  let nameHits: number = 0;
  for (let i = 0; i < pending.length; i++) {
    const entry = pending[i];
    const moving = entry.photoSubtype === photoAccessHelper.PhotoSubtype.MOVING_PHOTO;
    const piece = makePiece(entry, moving ? 'live' : 'file');
    if (moving) {
      piece.sourceSize = 0;
      piece.sourceMtimeMs = 0;
    }
    if (nasByName && piece.role === 'file' &&
      GalleryAutoSyncNasIndex.hasNameSize(piece.fileName, piece.sourceSize)) {
      result.skippedOnNas++;
      nameHits++;
      const put = new LedgerPut();
      put.uri = piece.sourceUri;
      put.size = piece.sourceSize;
      put.mtimeMs = piece.sourceMtimeMs;
      put.role = piece.role;
      puts.push(put);
      continue;
    }
    result.pieces.push(piece);
  }
  if (puts.length > 0) {
    await GalleryAutoSyncLedger.rememberMany(ctx, puts);
  }
  let uploadSample: string = '';
  const sampleCount: number = Math.min(12, result.pieces.length);
  for (let i = 0; i < sampleCount; i++) {
    const piece = result.pieces[i];
    uploadSample += `${piece.role}:${piece.fileName}:${piece.sourceSize};`;
  }
  const summary =
    `local=${photos.length} pending=${pending.length} ledger=${result.skippedInLedger} ` +
    `nameHit=${nameHits} upload=${result.pieces.length} nasIndex=${nasByName} ` +
    `nameSize=${GalleryAutoSyncNasIndex.nameSizeCount()}`;
  hilog.info(DOMAIN, TAG, 'compare %{public}s', summary);
  fnDiagRecord('I', TAG, summary);
  if (uploadSample.length > 0) {
    hilog.info(DOMAIN, TAG, 'uploadSample %{public}s', uploadSample);
    fnDiagRecord('I', TAG, `uploadSample ${uploadSample}`);
  }
  return result;
}
