/**
 * 前台增量同步：按飞牛官方规则（original_name + size + mtime）对比 NAS 全库与本机账本。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryListItem } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import {
  buildNasOfficialFingerprints,
  localPhotoOfficialFingerprint,
  officialFingerprintSetHas
} from './GalleryAutoSyncOfficialFingerprint';
import { GalleryAutoSyncLedger } from './GalleryAutoSyncLedger';
import { GalleryAutoSyncNasIndex } from './GalleryAutoSyncNasIndex';
import { queryLocalPhotos, LocalPhotoEntry } from './GalleryAutoSyncService';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncStore';

/** @deprecated 使用 localPhotoOfficialFingerprint */
export function localPhotoMediaFingerprint(entry: LocalPhotoEntry): string {
  return localPhotoOfficialFingerprint(entry);
}

/** @deprecated 使用 localPhotoOfficialFingerprint */
export function localPhotoLedgerKey(entry: LocalPhotoEntry): string {
  return localPhotoOfficialFingerprint(entry);
}

/** @deprecated 使用 buildNasOfficialFingerprints */
export function buildNasMediaFingerprints(nasTimeline: GalleryListItem[]): Set<string> {
  return buildNasOfficialFingerprints(nasTimeline);
}

export interface AutoSyncResult {
  unsynced: LocalPhotoEntry[];
  detectedAt: number;
  skippedOnNas: number;
  skippedInLedger: number;
}

function mergeOfficialFingerprints(base: Set<string>, extra: GalleryListItem[]): Set<string> {
  const merged = new Set<string>(base);
  const extraFps = buildNasOfficialFingerprints(extra);
  extraFps.forEach((fp: string): void => {
    merged.add(fp);
  });
  return merged;
}

export function filterUnsyncedLocalPhotos(
  localPhotos: LocalPhotoEntry[],
  nasFingerprints: Set<string>,
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
    const officialFp = localPhotoOfficialFingerprint(local);
    if (officialFingerprintSetHas(nasFingerprints, officialFp)) {
      skippedOnNas++;
      continue;
    }
    if (ledger.has(officialFp)) {
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
    if (GalleryAutoSyncStore.detecting) {
      return GalleryAutoSyncStore.lastResult ?? {
        unsynced: [],
        detectedAt: 0,
        skippedOnNas: 0,
        skippedInLedger: 0
      };
    }

    const now = Date.now();
    if (
      !force &&
      GalleryAutoSyncStore.lastResult !== null &&
      now - GalleryAutoSyncStore.lastDetectTime < GalleryAutoSyncStore.DETECT_INTERVAL_MS
    ) {
      return GalleryAutoSyncStore.lastResult;
    }

    GalleryAutoSyncStore.detecting = true;
    try {
      const localPhotos = await queryLocalPhotos(ctx, 500);
      if (localPhotos.length === 0) {
        GalleryAutoSyncStore.lastResult = {
          unsynced: [],
          detectedAt: now,
          skippedOnNas: 0,
          skippedInLedger: 0
        };
        GalleryAutoSyncStore.lastDetectTime = now;
        return GalleryAutoSyncStore.lastResult;
      }

      const nasFingerprints = mergeOfficialFingerprints(
        await GalleryAutoSyncNasIndex.getFingerprints(client, force),
        partialTimeline
      );
      const ledger = await GalleryAutoSyncLedger.load(ctx);
      const filtered = filterUnsyncedLocalPhotos(localPhotos, nasFingerprints, ledger);

      GalleryAutoSyncStore.lastResult = filtered;
      GalleryAutoSyncStore.lastDetectTime = now;

      hilog.info(
        DOMAIN,
        TAG,
        'detectUnsynced official local=%{public}d nasFp=%{public}d unsynced=%{public}d skipNas=%{public}d skipLedger=%{public}d',
        localPhotos.length,
        nasFingerprints.size,
        filtered.unsynced.length,
        filtered.skippedOnNas,
        filtered.skippedInLedger
      );

      return GalleryAutoSyncStore.lastResult;
    } finally {
      GalleryAutoSyncStore.detecting = false;
    }
  }

  static invalidate(): void {
    GalleryAutoSyncStore.lastResult = null;
    GalleryAutoSyncStore.lastDetectTime = 0;
    GalleryAutoSyncStore.detecting = false;
    GalleryAutoSyncNasIndex.invalidate();
    GalleryAutoSyncLedger.invalidate();
  }
}
