/**
 * 前台同步：本机账本快筛 → NAS 文件名+大小索引 → 未命中的才上传。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagError, fnDiagRecord, fnDiagSetState } from '../common/FnDiagLog';
import { GalleryListItem } from '../model/FnApiTypes';
import { FnHttpClient } from '../network/FnHttpClient';
import { buildNasDedupeIndex, localPhotoOfficialFingerprint } from './GalleryAutoSyncOfficialFingerprint';
import { compareLocalWithBackup, ContentCompareProgress, SyncUploadPiece } from './GalleryAutoSyncCompare';
import { GalleryAutoSyncLedger } from './GalleryAutoSyncLedger';
import { GalleryAutoSyncNasIndex } from './GalleryAutoSyncNasIndex';
import { FnTransferDirection } from '../common/FnTransferProgress';
import { FnTransferQueueStore } from '../common/FnTransferQueueStore';
import { GalleryAutoSyncLocalSeen } from './GalleryAutoSyncLocalSeen';
import { LocalPhotoScanProgress, queryLocalPhotos, queryLocalPhotosInAlbums, LocalPhotoEntry } from './GalleryAutoSyncService';
import { getAlbumBackupSettingsCached, resolveBackupSourceScope } from '../sync/AlbumBackupSettings';
import { isLikelyVideoFileName } from '../sync/AlbumBackupUploadPolicy';
import { buildLocalAlbumRefIndex } from '../sync/AlbumBackupLocalSources';
import { albumBackupTargetDir } from '../sync/AlbumBackupTargetPath';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncStore';
/** 已见快照读失败时的扫描说明（要如实反映「没比对」，不能报成没有新增）。 */
const SEEN_READ_FAIL_MESSAGE = '已见记录读失败，本次未比对';
/** 备份源扫描失败：权限缺失或扫相册抛错。不能当作「本机没有可同步项目」。 */
const SOURCE_SCAN_FAIL_MESSAGE = '备份源扫描失败，请检查相册权限后重试';
/** 备份源里的相册在当前本机一个都找不到（配置与本机脱节）。 */
const SOURCE_ALBUMS_MISSING_MESSAGE = '备份源里的相册在本机找不到，请重新选择备份源';

class CompareQueueProgress implements ContentCompareProgress {
  private readonly taskId: string;

  constructor(taskId: string) {
    this.taskId = taskId;
  }

  onProgress(done: number, total: number, detail: string): void {
    FnTransferQueueStore.update(this.taskId, done, detail, total);
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
  /** 用户点过「检查同步」且这次结果还没同步完。后台扫描不把它打开。 */
  private static launchArmed: boolean = false;

  static isDetecting(): boolean {
    return GalleryAutoSyncStore.detecting;
  }

  static hasChecked(): boolean {
    return GalleryAutoSyncStore.lastResult !== null;
  }

  static isLaunchArmed(): boolean {
    return GalleryAutoSyncStore.launchArmed;
  }

  static armLaunch(): void {
    GalleryAutoSyncStore.launchArmed = true;
  }

  static disarmLaunch(): void {
    GalleryAutoSyncStore.launchArmed = false;
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
    // 本次自动同步的结果类别（只记类别，不记文件名）。
    let syncState: string = 'failed: exception';
    try {
      const backupPrefs = getAlbumBackupSettingsCached();
      // 备份源 = 扫描范围：只扫用户勾选的相册，其余目录的文件根本不会被枚举，
      // 因此不参与「新媒体」判定、也不会被上传。
      // 主键读不出来时用影子副本还原上一次的选择——绝不能把「读失败」当成「备份所有文件夹」，
      // 否则用户明确排除过的目录会被一并上传。
      const scope = resolveBackupSourceScope(backupPrefs);
      if (scope.degraded) {
        fnDiagRecord('W', 'AlbumBackup', scope.guessed
          ? 'source folders unreadable and no shadow copy, fallback to all folders'
          : 'source folders unreadable, using shadow copy n=' + String(scope.keys.length));
      }
      let localPhotos: LocalPhotoEntry[];
      if (scope.scoped) {
        const scanResult = await queryLocalPhotosInAlbums(ctx, scope.keys, new LocalScanQueueProgress(taskId));
        localPhotos = scanResult.entries;
        if (scanResult.failed || !scanResult.granted) {
          // 权限缺失 / 扫相册抛错：这是失败，不是「本机没有可同步项目」
          syncState = 'failed: source scan';
          scanMessage = SOURCE_SCAN_FAIL_MESSAGE;
          throw new Error(SOURCE_SCAN_FAIL_MESSAGE);
        }
        if (scanResult.albumsScanned === 0) {
          // 选中的备份源一个都没对上当前本机相册：配置和本机脱节，同样不能当成功
          syncState = 'failed: source albums missing';
          scanMessage = SOURCE_ALBUMS_MISSING_MESSAGE;
          throw new Error(SOURCE_ALBUMS_MISSING_MESSAGE);
        }
        fnDiagRecord('I', 'AlbumBackup', 'source scope photos=' + String(localPhotos.length) +
          ' albums=' + String(scanResult.albumsScanned) + ' selected=' + String(scope.keys.length));
      } else {
        localPhotos = await queryLocalPhotos(ctx, new LocalScanQueueProgress(taskId));
      }
      // 统一补齐：全库扫描没有相册信息；按备份源扫描时用户相册/系统相册没有 lpath。
      // 两条路径都补成「优先用 SOURCE 相册的设备内路径」，否则 mode 3 会落到备份根目录。
      const needName = backupPrefs.syncCreateAlbum;
      const needPath = backupPrefs.folderManageMode === 3;
      if (needName || needPath) {
        let missing = false;
        for (let i = 0; i < localPhotos.length; i++) {
          if ((needName && localPhotos[i].sourceAlbumName.length === 0) ||
            (needPath && localPhotos[i].sourceAlbumPath.length === 0)) {
            missing = true;
            break;
          }
        }
        if (missing) {
          const albumRefIndex = await buildLocalAlbumRefIndex(ctx);
          for (let i = 0; i < localPhotos.length; i++) {
            const ref = albumRefIndex.get(localPhotos[i].uri);
            if (ref === undefined) {
              continue;
            }
            if (needName && localPhotos[i].sourceAlbumName.length === 0 && ref.name.length > 0) {
              localPhotos[i].sourceAlbumName = ref.name;
            }
            if (needPath && localPhotos[i].sourceAlbumPath.length === 0 && ref.lpath.length > 0) {
              localPhotos[i].sourceAlbumPath = ref.lpath;
            }
          }
        }
      }
      if (backupPrefs.photosOnly) {
        localPhotos = localPhotos.filter((p: LocalPhotoEntry): boolean => !isLikelyVideoFileName(p.fileName));
      }
      if (backupPrefs.folderManageMode === 2 || backupPrefs.folderManageMode === 3) {
        // 「按拍摄日期 / 按设备文件夹」会按照片算不同目录，打一条样本方便核对落位
        const sample: LocalPhotoEntry | undefined = localPhotos.length > 0 ? localPhotos[0] : undefined;
        if (sample !== undefined) {
          const sampleDir = albumBackupTargetDir(backupPrefs.deviceBackupPath, backupPrefs.folderManageMode,
            sample.sourceAlbumPath, sample.dateTakenMs);
          fnDiagRecord('I', 'AlbumBackup', 'target dir mode=' + String(backupPrefs.folderManageMode) +
            ' dir=' + sampleDir + ' src=' + sample.sourceAlbumPath);
        }
      }
      const seenDiff = await GalleryAutoSyncLocalSeen.diff(ctx, localPhotos);
      if (seenDiff.readFailed) {
        // 已见快照读不了：这一轮没有比对，不能当成「空成功」返回——
        // 否则角标/检查同步会显示「没有待同步」，且 5 分钟内非强制扫描直接复用这份空结果。
        // 不刷新 lastDetectTime、不复用 lastResult，直接按扫描失败抛给调用方。
        syncState = 'failed: seen snapshot';
        scanMessage = SEEN_READ_FAIL_MESSAGE;
        throw new Error(SEEN_READ_FAIL_MESSAGE);
      }
      if (seenDiff.freshBaseline) {
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
        syncState = 'ok';
        scanMessage = seenDiff.baselineCount > 0
          ? `已记录本机现有 ${seenDiff.baselineCount} 项，之后新增的才会和 NAS 对比`
          : '本机相册没有可同步的项目';
        return GalleryAutoSyncStore.lastResult;
      }
      const addedPhotos = seenDiff.added;
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
        syncState = 'ok';
        scanMessage = '本机相册没有可同步的项目';
        return GalleryAutoSyncStore.lastResult;
      }
      if (addedPhotos.length === 0) {
        if (GalleryAutoSyncStore.lastResult === null) {
          GalleryAutoSyncStore.lastResult = {
            unsynced: [],
            detectedAt: now,
            skippedOnNas: 0,
            skippedInLedger: 0,
            compareFailed: 0,
            unreadable: 0
          };
        }
        GalleryAutoSyncStore.lastDetectTime = now;
        scanOk = true;
        syncState = 'ok';
        scanMessage = '没有新增照片';
        return GalleryAutoSyncStore.lastResult;
      }

      FnTransferQueueStore.update(taskId, 0, `本机新增 ${addedPhotos.length} 项，正在和 NAS 对比`, addedPhotos.length);
      const progress = new CompareQueueProgress(taskId);
      const compared = await compareLocalWithBackup(ctx, client, addedPhotos, progress);
      const confirmed: LocalPhotoEntry[] = [];
      const pendingUris = new Set<string>();
      for (let i = 0; i < compared.pieces.length; i++) {
        pendingUris.add(compared.pieces[i].sourceUri);
      }
      for (let i = 0; i < addedPhotos.length; i++) {
        if (!pendingUris.has(addedPhotos[i].uri)) {
          confirmed.push(addedPhotos[i]);
        }
      }
      await GalleryAutoSyncLocalSeen.remember(ctx, confirmed);
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
      syncState = (filtered.compareFailed + filtered.unreadable) > 0 ? 'failed: compare' : 'ok';
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
        'detectUnsynced local=%{public}d added=%{public}d unsynced=%{public}d skipNas=%{public}d skipLedger=%{public}d failed=%{public}d unreadable=%{public}d',
        localPhotos.length,
        addedPhotos.length,
        filtered.unsynced.length,
        filtered.skippedOnNas,
        filtered.skippedInLedger,
        filtered.compareFailed,
        filtered.unreadable
      );
      return GalleryAutoSyncStore.lastResult;
    } catch (e) {
      // 已见快照读失败有自己的说明，别被通用的「扫描失败」盖掉
      if (scanMessage !== SEEN_READ_FAIL_MESSAGE) {
        scanMessage = '扫描失败';
      }
      hilog.warn(DOMAIN, TAG, 'detectUnsynced failed: %{public}s', String(e));
      fnDiagError(TAG, 'detect unsynced failed', e);
      throw new Error(String(e));
    } finally {
      FnTransferQueueStore.finish(taskId, scanOk, scanMessage);
      GalleryAutoSyncStore.detecting = false;
      fnDiagSetState('autoSyncLast', syncState);
    }
  }

  static invalidate(): void {
    GalleryAutoSyncStore.launchArmed = false;
    GalleryAutoSyncStore.lastResult = null;
    GalleryAutoSyncStore.lastDetectTime = 0;
    GalleryAutoSyncStore.detecting = false;
    GalleryAutoSyncStore.inflight = null;
    GalleryAutoSyncNasIndex.invalidate();
    GalleryAutoSyncLedger.invalidate();
  }
}
