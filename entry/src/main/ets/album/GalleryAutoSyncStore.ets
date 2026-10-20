/**
 * 前台同步：本机账本快筛 → NAS 文件名+大小索引 → 未命中的才上传。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryListItem } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { buildNasDedupeIndex, localPhotoOfficialFingerprint } from './GalleryAutoSyncOfficialFingerprint';
import { compareLocalWithBackup, ContentCompareProgress, SyncUploadPiece } from './GalleryAutoSyncCompare';
import { GalleryAutoSyncLedger } from './GalleryAutoSyncLedger';
import { GalleryAutoSyncNasIndex } from './GalleryAutoSyncNasIndex';
import { FnTransferDirection } from '../common/FnTransferProgress';
import { FnTransferQueueStore } from '../common/FnTransferQueueStore';
import { LocalPhotoScanProgress, queryLocalPhotos, LocalPhotoEntry } from './GalleryAutoSyncService';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncStore';

class CompareQueueProgress implements ContentCompareProgress {
  private readonly taskId: string;

  constructor(taskId: string) {
    this.taskId = taskId;
  }

  onProgress(done: number, total: number, detail: string): void {
    FnTransferQueueStore.update(this.taskId, total > 0 ? done : 0, detail);
  }
}

class LocalScanQueueProgress implements LocalPhotoScanProgress {
  private readonly taskId: string;

  constructor(taskId: string) {
    this.taskId = taskId;
  }

  onLoaded(count: number): void {
    FnTransferQueueStore.update(this.taskId, count, `已读取 ${count} 项`);
  }
}

/** @deprecated 使用 localPhotoOfficialFingerprint */
export function localPhotoMediaFingerprint(entry: LocalPhotoEntry): string {
  return localPhotoOfficialFingerprint(entry);
}

/** @deprecated 使用 localPhotoOfficialFingerprint */
export function localPhotoLedgerKey(entry: LocalPhotoEntry): string {
  return localPhotoOfficialFingerprint(entry);
}

/** @deprecated 使用 buildNasDedupeIndex */
export function buildNasMediaFingerprints(nasTimeline: GalleryListItem[]): Set<string> {
  return buildNasDedupeIndex(nasTimeline).fingerprints;
}

export interface AutoSyncResult {
  unsynced: SyncUploadPiece[];
  detectedAt: number;
  skippedOnNas: number;
  skippedInLedger: number;
  compareFailed: number;
  unreadable: number;
}

export class GalleryAutoSyncStore {
  private static lastResult: AutoSyncResult | null = null;
  private static lastDetectTime: number = 0;
  private static readonly DETECT_INTERVAL_MS: number = 5 * 60 * 1000;
  private static detecting: boolean = false;
  /** 同一时刻只允许一次扫描；后来的调用等这一次，不再另开任务。 */
  private static inflight: Promise<AutoSyncResult> | null = null;

  static isDetecting(): boolean {
    return GalleryAutoSyncStore.detecting;
  }

  static getUnsyncedCount(): number {
    if (GalleryAutoSyncStore.lastResult === null) {
      return 0;
    }
    return GalleryAutoSyncStore.lastResult.unsynced.length;
  }

  static getUnsyncedPhotos(): SyncUploadPiece[] {
    if (GalleryAutoSyncStore.lastResult === null) {
      return [];
    }
    return GalleryAutoSyncStore.lastResult.unsynced;
  }

  static markPieceSynced(sourceUri: string, role: string): void {
    if (GalleryAutoSyncStore.lastResult === null || sourceUri.length === 0) {
      return;
    }
    GalleryAutoSyncStore.lastResult.unsynced =
      GalleryAutoSyncStore.lastResult.unsynced.filter(
        (e: SyncUploadPiece): boolean => !(e.sourceUri === sourceUri && e.role === role)
      );
  }

  static markSynced(uris: string[]): void {
    if (GalleryAutoSyncStore.lastResult === null || uris.length === 0) {
      return;
    }
    const uriSet = new Set<string>(uris);
    GalleryAutoSyncStore.lastResult.unsynced =
      GalleryAutoSyncStore.lastResult.unsynced.filter(
        (e: SyncUploadPiece): boolean => !uriSet.has(e.sourceUri)
      );
    hilog.info(
      DOMAIN,
      TAG,
      'markSynced removed=%{public}d remaining=%{public}d',
      uris.length,
      GalleryAutoSyncStore.lastResult.unsynced.length
    );
  }

  static async detectUnsynced(
    ctx: common.UIAbilityContext,
    client: FnHttpClient,
    force: boolean = false,
    partialTimeline: GalleryListItem[] = []
  ): Promise<AutoSyncResult> {
    if (GalleryAutoSyncStore.inflight !== null) {
      return GalleryAutoSyncStore.inflight;
    }
    const run = GalleryAutoSyncStore.detectUnsyncedBody(ctx, client, force, partialTimeline);
    GalleryAutoSyncStore.inflight = run;
    try {
      return await run;
    } finally {
      if (GalleryAutoSyncStore.inflight === run) {
        GalleryAutoSyncStore.inflight = null;
      }
    }
  }

  private static async detectUnsyncedBody(
    ctx: common.UIAbilityContext,
    client: FnHttpClient,
    force: boolean,
    partialTimeline: GalleryListItem[]
  ): Promise<AutoSyncResult> {
    const now = Date.now();
    if (
      !force &&
      GalleryAutoSyncStore.lastResult !== null &&
      now - GalleryAutoSyncStore.lastDetectTime < GalleryAutoSyncStore.DETECT_INTERVAL_MS
    ) {
      return GalleryAutoSyncStore.lastResult;
    }

    GalleryAutoSyncStore.detecting = true;
    const taskId = FnTransferQueueStore.begin(FnTransferDirection.SCAN, '扫描本机相册', 0);
    let scanOk = false;
    let scanMessage = '扫描失败';
    try {
      const localPhotos = await queryLocalPhotos(ctx, new LocalScanQueueProgress(taskId));
      if (localPhotos.length === 0) {
        GalleryAutoSyncStore.lastResult = {
          unsynced: [],
          detectedAt: now,
          skippedOnNas: 0,
          skippedInLedger: 0,
          compareFailed: 0,
          unreadable: 0
        };
        GalleryAutoSyncStore.lastDetectTime = now;
        scanOk = true;
        scanMessage = '本机相册没有可同步的项目';
        return GalleryAutoSyncStore.lastResult;
      }

      const progress = new CompareQueueProgress(taskId);
      const compared = await compareLocalWithBackup(ctx, client, localPhotos, progress);
      const filtered: AutoSyncResult = {
        unsynced: compared.pieces,
        detectedAt: Date.now(),
        skippedOnNas: compared.skippedOnNas,
        skippedInLedger: compared.skippedInLedger,
        compareFailed: compared.compareFailed,
        unreadable: compared.unreadable
      };
      GalleryAutoSyncStore.lastResult = filtered;
      GalleryAutoSyncStore.lastDetectTime = now;
      scanOk = true;
      if (filtered.unsynced.length > 0) {
        scanMessage = `还有 ${filtered.unsynced.length} 项未同步`;
      } else if (filtered.compareFailed + filtered.unreadable > 0) {
        scanMessage = '有照片没能完成对比';
      } else {
        scanMessage = '本机相册都已在 NAS';
      }
      hilog.info(
        DOMAIN,
        TAG,
        'detectUnsynced local=%{public}d unsynced=%{public}d skipNas=%{public}d skipLedger=%{public}d failed=%{public}d unreadable=%{public}d',
        localPhotos.length,
        filtered.unsynced.length,
        filtered.skippedOnNas,
        filtered.skippedInLedger,
        filtered.compareFailed,
        filtered.unreadable
      );
      return GalleryAutoSyncStore.lastResult;
    } catch (e) {
      scanMessage = '扫描失败';
      hilog.warn(DOMAIN, TAG, 'detectUnsynced failed: %{public}s', String(e));
      throw new Error(String(e));
    } finally {
      FnTransferQueueStore.finish(taskId, scanOk, scanMessage);
      GalleryAutoSyncStore.detecting = false;
    }
  }

  static invalidate(): void {
    GalleryAutoSyncStore.lastResult = null;
    GalleryAutoSyncStore.lastDetectTime = 0;
    GalleryAutoSyncStore.detecting = false;
    GalleryAutoSyncStore.inflight = null;
    GalleryAutoSyncNasIndex.invalidate();
    GalleryAutoSyncLedger.invalidate();
  }
}
