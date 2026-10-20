/**
 * 前台增量同步：账本快筛 → NAS 指纹（强匹配可入账本；size+mtime 弱匹配仅本轮跳过）。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryListItem } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import {
  buildNasDedupeIndex,
  emptyNasDedupeIndex,
  localPhotoOfficialFingerprint,
  mergeNasDedupeIndex,
  NasDedupeIndex,
  nasDedupeIndexHasEntry,
  nasDedupeIndexMatchKindForEntry,
  nasDedupeMatchIsStrong
} from './GalleryAutoSyncOfficialFingerprint';
import { GalleryAutoSyncLedger } from './GalleryAutoSyncLedger';
import { GalleryAutoSyncNasIndex } from './GalleryAutoSyncNasIndex';
import { FnTransferDirection } from '../common/FnTransferProgress';
import { FnTransferQueueStore } from '../common/FnTransferQueueStore';
import { LocalPhotoScanProgress, queryLocalPhotos, LocalPhotoEntry } from './GalleryAutoSyncService';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncStore';

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
  unsynced: LocalPhotoEntry[];
  detectedAt: number;
  skippedOnNas: number;
  skippedInLedger: number;
}

export function filterUnsyncedLocalPhotos(
  localPhotos: LocalPhotoEntry[],
  nasIndex: NasDedupeIndex,
  ledger: Set<string>
): AutoSyncResult {
  const unsynced: LocalPhotoEntry[] = [];
  let skippedOnNas = 0;
  let skippedInLedger = 0;
  for (let i = 0; i < localPhotos.length; i++) {
    const local = localPhotos[i];
    if (local.fileName.length === 0 || local.fileSize <= 0) {
      continue;
    }
    if (nasDedupeIndexHasEntry(nasIndex, local)) {
      skippedOnNas++;
      continue;
    }
    if (GalleryAutoSyncLedger.hasEntry(ledger, local)) {
      skippedInLedger++;
      continue;
    }
    unsynced.push(local);
  }
  unsynced.sort(
    (a: LocalPhotoEntry, b: LocalPhotoEntry): number => b.dateModifiedMs - a.dateModifiedMs
  );
  return {
    unsynced,
    detectedAt: Date.now(),
    skippedOnNas,
    skippedInLedger
  };
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

  static getUnsyncedPhotos(): LocalPhotoEntry[] {
    if (GalleryAutoSyncStore.lastResult === null) {
      return [];
    }
    return GalleryAutoSyncStore.lastResult.unsynced;
  }

  static markSynced(uris: string[]): void {
    if (GalleryAutoSyncStore.lastResult === null || uris.length === 0) {
      return;
    }
    const uriSet = new Set<string>(uris);
    GalleryAutoSyncStore.lastResult.unsynced =
      GalleryAutoSyncStore.lastResult.unsynced.filter(
        (e: LocalPhotoEntry): boolean => !uriSet.has(e.uri)
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
          skippedInLedger: 0
        };
        GalleryAutoSyncStore.lastDetectTime = now;
        scanOk = true;
        scanMessage = '本机相册没有可同步的项目';
        return GalleryAutoSyncStore.lastResult;
      }

      const ledger = await GalleryAutoSyncLedger.load(ctx);
      const ledgerFiltered = filterUnsyncedLocalPhotos(localPhotos, emptyNasDedupeIndex(), ledger);
      if (ledgerFiltered.unsynced.length === 0) {
        GalleryAutoSyncStore.lastResult = ledgerFiltered;
        GalleryAutoSyncStore.lastDetectTime = now;
        scanOk = true;
        scanMessage = '本机相册都已在 NAS';
        return GalleryAutoSyncStore.lastResult;
      }

      FnTransferQueueStore.update(taskId, localPhotos.length, '正在对比 NAS');
      const nasIndex = mergeNasDedupeIndex(
        await GalleryAutoSyncNasIndex.getIndex(client, false, ctx),
        partialTimeline
      );
      const nasFiltered = filterUnsyncedLocalPhotos(
        ledgerFiltered.unsynced,
        nasIndex,
        new Set<string>()
      );
      const unsyncedUris = new Set<string>(
        nasFiltered.unsynced.map((entry: LocalPhotoEntry): string => entry.uri)
      );
      const matchedOnNas = ledgerFiltered.unsynced.filter(
        (entry: LocalPhotoEntry): boolean => !unsyncedUris.has(entry.uri)
      );
      // 仅强匹配写入账本；size+mtime 弱匹配只本轮跳过，避免误永久跳过
      const strongMatches = matchedOnNas.filter(
        (entry: LocalPhotoEntry): boolean =>
          nasDedupeMatchIsStrong(nasDedupeIndexMatchKindForEntry(nasIndex, entry))
      );
      if (strongMatches.length > 0) {
        try {
          await GalleryAutoSyncLedger.markSynced(ctx, strongMatches);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'persist NAS matches failed: %{public}s', String(e));
        }
      }
      const filtered: AutoSyncResult = {
        unsynced: nasFiltered.unsynced,
        detectedAt: Date.now(),
        skippedOnNas: nasFiltered.skippedOnNas,
        skippedInLedger: ledgerFiltered.skippedInLedger
      };

      GalleryAutoSyncStore.lastResult = filtered;
      GalleryAutoSyncStore.lastDetectTime = now;
      scanOk = true;
      scanMessage = filtered.unsynced.length > 0
        ? `还有 ${filtered.unsynced.length} 项未同步`
        : '本机相册都已在 NAS';

      hilog.info(
        DOMAIN,
        TAG,
        'detectUnsynced official local=%{public}d nasFp=%{public}d sizeMtime=%{public}d nameSize=%{public}d unsynced=%{public}d skipNas=%{public}d skipLedger=%{public}d',
        localPhotos.length,
        nasIndex.fingerprints.size,
        nasIndex.sizeMtimeKeys.size,
        nasIndex.nameSizeKeys.size,
        filtered.unsynced.length,
        filtered.skippedOnNas,
        filtered.skippedInLedger
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
