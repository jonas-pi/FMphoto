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
  /** 拍摄时间（毫秒）。「按拍摄日期」分目录只用它，0 表示没有拍摄时间。 */
  sourceTakenMs: number = 0;
  role: string = 'file';
  /** 来源本地相册名；开启「同步创建相册」时按它在 NAS 建同名相册 */
  albumName: string = '';
  /** 来源目录路径（如 /DCIM/Camera）；「按设备文件夹」目录模式用它拼目标目录 */
  sourceAlbumPath: string = '';
}

export class ContentCompareResult {
  pieces: SyncUploadPiece[] = [];
  skippedInLedger: number = 0;
  skippedOnNas: number = 0;
  compareFailed: number = 0;
  unreadable: number = 0;
  /**
   * 本轮是否真的用上了 NAS 的「文件名+大小」名单。
   * false 表示名单没拿到（NAS 不可达/索引不可用），此时不能把「没命中」当成「NAS 上没有」，
   * 首次扫描据此拒绝写基线、也不把整库当成待上传。
   */
  nasIndexUsable: boolean = false;
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
  piece.sourceTakenMs = entry.dateTakenMs;
  piece.role = role;
  piece.albumName = entry.sourceAlbumName;
  piece.sourceAlbumPath = entry.sourceAlbumPath;
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
      // 文件名或大小异常的条目被静默丢弃，照片不会被同步。
      const reason: string = photo.fileName.length === 0 ? 'noName' : 'noSize';
      fnDiagRecord('W', TAG, `skip invalid entry reason=${reason}`);
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
  const reportCheck = (done: number, total: number, detail: string): void => {
    if (progress !== null && total > 0) {
      progress.onProgress(done, total, detail);
    }
  };
  let hasNormalPending: boolean = false;
  for (let i = 0; i < pending.length; i++) {
    if (pending[i].photoSubtype !== photoAccessHelper.PhotoSubtype.MOVING_PHOTO) {
      hasNormalPending = true;
      break;
    }
  }
  let nasByName: boolean = false;
  let nasDayTotal: number = 0;
  const onNasDayProgress = (doneDays: number, totalDays: number): void => {
    nasDayTotal = totalDays;
    const grandTotal: number = totalDays > 0 ? totalDays + pending.length : pending.length;
    const detail: string =
      totalDays > 0 ? `正在拉取 NAS 文件名单 ${doneDays}/${totalDays} 天` : '正在拉取 NAS 文件名单';
    reportCheck(doneDays, grandTotal, detail);
  };
  reportCheck(0, pending.length, '正在核对 NAS 文件名单');
  let nasIndex = await GalleryAutoSyncNasIndex.getIndex(client, false, ctx, onNasDayProgress);
  // 兼容旧版留下的有效期内空索引；强制重建一次。
  if (!GalleryAutoSyncNasIndex.nasIndexUsable()) {
    nasIndex = await GalleryAutoSyncNasIndex.getIndex(client, true, ctx, onNasDayProgress);
  }
  nasByName = GalleryAutoSyncNasIndex.nasIndexUsable();
  result.nasIndexUsable = nasByName;
  const compareGrandTotal: number = nasDayTotal > 0 ? nasDayTotal + pending.length : pending.length;
  const compareDayBase: number = nasDayTotal > 0 ? nasDayTotal : 0;
  const progressStride: number = pending.length > 200 ? 25 : pending.length > 80 ? 10 : 1;
  const puts: LedgerPut[] = [];
  let nameHits: number = 0;
  let liveNameHits: number = 0;
  for (let i = 0; i < pending.length; i++) {
    const entry = pending[i];
    const moving = entry.photoSubtype === photoAccessHelper.PhotoSubtype.MOVING_PHOTO;
    const piece = makePiece(entry, moving ? 'live' : 'file');
    let skipOnNas = false;
    if (nasByName) {
      if (piece.role === 'file' &&
        GalleryAutoSyncNasIndex.hasNameSize(piece.fileName, piece.sourceSize)) {
        skipOnNas = true;
        nameHits++;
      } else if (piece.role === 'live' &&
        GalleryAutoSyncNasIndex.liveLikelyOnNas(piece.fileName, entry.fileSize)) {
        skipOnNas = true;
        liveNameHits++;
      }
    }
    if (skipOnNas) {
      result.skippedOnNas++;
      const put = new LedgerPut();
      put.uri = piece.sourceUri;
      put.size = moving ? 0 : piece.sourceSize;
      put.mtimeMs = moving ? 0 : piece.sourceMtimeMs;
      put.role = piece.role;
      puts.push(put);
    } else {
      if (moving) {
        piece.sourceSize = 0;
        piece.sourceMtimeMs = 0;
      }
      result.pieces.push(piece);
    }
    const atEnd: boolean = i === pending.length - 1;
    if (atEnd || (i + 1) % progressStride === 0) {
      const detail: string = hasNormalPending
        ? `正在核对 NAS 文件名单 ${i + 1}/${pending.length}`
        : `正在核对待同步项 ${i + 1}/${pending.length}`;
      reportCheck(compareDayBase + i + 1, compareGrandTotal, detail);
    }
  }
  if (puts.length > 0) {
    await GalleryAutoSyncLedger.rememberMany(ctx, puts);
  }
  // 抽样只保留角色与大小，不落文件名（文件名属于私人内容）。
  let uploadSample: string = '';
  const sampleCount: number = Math.min(6, result.pieces.length);
  for (let i = 0; i < sampleCount; i++) {
    const piece = result.pieces[i];
    uploadSample += `${piece.role}:${piece.sourceSize};`;
  }
  const summary =
    `local=${photos.length} pending=${pending.length} ledger=${result.skippedInLedger} ` +
    `nameHit=${nameHits} liveNameHit=${liveNameHits} upload=${result.pieces.length} nasIndex=${nasByName} ` +
    `nameSize=${GalleryAutoSyncNasIndex.nameSizeCount()}`;
  hilog.info(DOMAIN, TAG, 'compare %{public}s', summary);
  fnDiagRecord('I', TAG, summary);
  if (uploadSample.length > 0) {
    hilog.info(DOMAIN, TAG, 'uploadSample %{public}s', uploadSample);
    fnDiagRecord('I', TAG, `upload sample n=${result.pieces.length} ${uploadSample}`);
  }
  return result;
}
