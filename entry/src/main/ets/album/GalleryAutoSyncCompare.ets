/**
 * 先用本机内容指纹查询备份标识，再用 NAS 全库文件名+大小补齐普通上传来源。
 * POST /p/api/v1/backup/identifier/file_hash，一次最多 1000 条。
 * 接口失败不当成缺失，避免把已经在相册里的照片再传一遍。
 */
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagRecord } from '../common/FnDiagLog';
import { FnHttpClient } from '../network/FnHttpClient';
import { contentFingerprintOf } from './GalleryContentHash';
import { deleteOwnedLivePayload, prepareLiveSyncPayload } from './GalleryLiveSyncPayload';
import { GalleryAutoSyncLedger, LedgerPut } from './GalleryAutoSyncLedger';
import { GalleryAutoSyncNasIndex } from './GalleryAutoSyncNasIndex';
import { LocalPhotoEntry } from './GalleryAutoSyncService';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncCompare';
const HASH_CONCURRENCY: number = 4;
const FILE_HASH_BATCH: number = 1000;

export class SyncUploadPiece {
  sourceUri: string = '';
  fileName: string = '';
  sourceSize: number = 0;
  sourceMtimeMs: number = 0;
  fingerprint: string = '';
  role: string = 'file';
  /** 实况拼接文件。空串表示直接上传 sourceUri。 */
  payloadPath: string = '';
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

function makePiece(entry: LocalPhotoEntry, role: string, fingerprint: string, fileName: string): SyncUploadPiece {
  const piece = new SyncUploadPiece();
  piece.sourceUri = entry.uri;
  piece.fileName = fileName;
  piece.sourceSize = entry.fileSize;
  piece.sourceMtimeMs = entry.dateModifiedMs;
  piece.fingerprint = fingerprint.toLowerCase();
  piece.role = role;
  return piece;
}

class HashOutcome {
  pieces: SyncUploadPiece[] = [];
  settled: boolean = false;
  failed: boolean = false;
}

async function hashOne(ctx: common.UIAbilityContext, entry: LocalPhotoEntry): Promise<HashOutcome> {
  const outcome = new HashOutcome();
  if (entry.photoSubtype === photoAccessHelper.PhotoSubtype.MOVING_PHOTO) {
    const payload = await prepareLiveSyncPayload(ctx, entry.uri, entry.fileName);
    if (payload === null) {
      outcome.failed = true;
      return outcome;
    }
    if (GalleryAutoSyncLedger.liveFingerprint(entry.uri) === payload.fingerprint) {
      await deleteOwnedLivePayload(payload.ownedPath);
      outcome.settled = true;
      return outcome;
    }
    const piece = makePiece(entry, 'live', payload.fingerprint, entry.fileName);
    piece.sourceSize = 0;
    piece.sourceMtimeMs = 0;
    piece.payloadPath = payload.ownedPath;
    outcome.pieces.push(piece);
    return outcome;
  }
  const fingerprint = await contentFingerprintOf(entry.uri);
  if (fingerprint.length === 0) {
    outcome.failed = true;
    return outcome;
  }
  if (GalleryAutoSyncLedger.confirmedHash(entry.uri, entry.fileSize, entry.dateModifiedMs, 'file') ===
    fingerprint.toLowerCase()) {
    outcome.settled = true;
    return outcome;
  }
  outcome.pieces.push(makePiece(entry, 'file', fingerprint, entry.fileName));
  return outcome;
}

class HashBatch {
  pieces: SyncUploadPiece[] = [];
  settled: number = 0;
  failed: number = 0;
}

async function hashPending(
  ctx: common.UIAbilityContext,
  entries: LocalPhotoEntry[],
  progress: ContentCompareProgress | null
): Promise<HashBatch> {
  const batch = new HashBatch();
  let cursor = 0;
  let done = 0;
  const workers: Promise<void>[] = [];
  const count = Math.min(HASH_CONCURRENCY, entries.length);
  for (let w = 0; w < count; w++) {
    workers.push((async (): Promise<void> => {
      while (true) {
        const index = cursor;
        cursor++;
        if (index >= entries.length) {
          return;
        }
        const made = await hashOne(ctx, entries[index]);
        if (made.settled) {
          batch.settled++;
        } else if (made.failed) {
          batch.failed++;
        }
        for (let i = 0; i < made.pieces.length; i++) {
          batch.pieces.push(made.pieces[i]);
        }
        done++;
        if (progress !== null && (done % 20 === 0 || done === entries.length)) {
          progress.onProgress(done, entries.length, `正在计算指纹 ${done}/${entries.length}`);
        }
      }
    })());
  }
  await Promise.all(workers);
  return batch;
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
    if (!moving && GalleryAutoSyncLedger.isSettled(photo.uri, photo.fileSize, photo.dateModifiedMs)) {
      result.skippedInLedger++;
      continue;
    }
    pending.push(photo);
  }
  if (pending.length === 0) {
    return result;
  }
  const hashed = await hashPending(ctx, pending, progress);
  result.skippedInLedger += hashed.settled;
  result.unreadable = hashed.failed;
  const fresh = hashed.pieces;
  if (progress !== null) {
    progress.onProgress(photos.length, photos.length, '正在对比 NAS');
  }
  const unique: string[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < fresh.length; i++) {
    const hash = fresh[i].fingerprint;
    if (!seen.has(hash)) {
      seen.add(hash);
      unique.push(hash);
    }
  }
  const failed = new Set<string>();
  const hits = new Set<string>();
  for (let offset = 0; offset < unique.length; offset += FILE_HASH_BATCH) {
    const batch: string[] = [];
    const end = Math.min(offset + FILE_HASH_BATCH, unique.length);
    for (let i = offset; i < end; i++) {
      batch.push(unique[i]);
    }
    const queried = await client.queryBackupFileHashes(batch);
    if (!queried.ok) {
      for (let i = 0; i < batch.length; i++) {
        failed.add(batch[i]);
      }
      hilog.warn(DOMAIN, TAG, 'file_hash batch failed size=%{public}d', batch.length);
      continue;
    }
    for (let i = 0; i < queried.hits.length; i++) {
      hits.add(queried.hits[i].trim().toLowerCase());
    }
  }
  // file_hash 接口不是相册整库索引：实测 Web upload/notice 已入库且二次 notice
  // 返回 repeat=true 的同字节文件，仍不会出现在这里。这时拉 NAS 全库名单，
  // 用服务端返回的原始文件名+大小识别已经存在的普通照片。
  // 不能只读落盘缓存：内容指纹流程本身不会创建那份缓存，全新安装时它通常不存在。
  let needsNasNameSize: boolean = false;
  for (let i = 0; i < fresh.length; i++) {
    const piece = fresh[i];
    if (piece.role === 'file' && piece.sourceSize > 0 &&
      !failed.has(piece.fingerprint) && !hits.has(piece.fingerprint)) {
      needsNasNameSize = true;
      break;
    }
  }
  let nasByName: boolean = false;
  if (needsNasNameSize) {
    if (progress !== null) {
      progress.onProgress(photos.length, photos.length, '正在核对 NAS 文件名单');
    }
    let nasIndex = await GalleryAutoSyncNasIndex.getIndex(client, false, ctx);
    // 兼容旧版留下的有效期内空索引；强制重建一次，避免一直复用无 nameSize 的缓存。
    if (nasIndex.nameSizeKeys.size === 0) {
      nasIndex = await GalleryAutoSyncNasIndex.getIndex(client, true, ctx);
    }
    nasByName = nasIndex.nameSizeKeys.size > 0;
  }
  const puts: LedgerPut[] = [];
  let hashHits: number = 0;
  let nameHits: number = 0;
  for (let i = 0; i < fresh.length; i++) {
    const piece = fresh[i];
    if (failed.has(piece.fingerprint)) {
      await deleteOwnedLivePayload(piece.payloadPath);
      result.compareFailed++;
      continue;
    }
    if (hits.has(piece.fingerprint)) {
      await deleteOwnedLivePayload(piece.payloadPath);
      result.skippedOnNas++;
      hashHits++;
      const put = new LedgerPut();
      put.uri = piece.sourceUri;
      put.size = piece.sourceSize;
      put.mtimeMs = piece.sourceMtimeMs;
      put.role = piece.role;
      put.hash = piece.fingerprint;
      puts.push(put);
      continue;
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
      put.hash = piece.fingerprint;
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
    `local=${photos.length} pending=${fresh.length} ledger=${result.skippedInLedger} ` +
    `hashHit=${hashHits} nameHit=${nameHits} upload=${result.pieces.length} ` +
    `failed=${result.compareFailed} unreadable=${result.unreadable} nasIndex=${nasByName} ` +
    `nameSize=${GalleryAutoSyncNasIndex.nameSizeCount()}`;
  hilog.info(DOMAIN, TAG, 'compare %{public}s', summary);
  fnDiagRecord('I', TAG, summary);
  if (uploadSample.length > 0) {
    hilog.info(DOMAIN, TAG, 'uploadSample %{public}s', uploadSample);
    fnDiagRecord('I', TAG, `uploadSample ${uploadSample}`);
  }
  return result;
}
