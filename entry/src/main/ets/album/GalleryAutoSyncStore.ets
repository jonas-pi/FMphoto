/**
 * 前台增量同步状态管理。
 * 对比本地相册与 NAS 时间线，发现未同步的本地照片后提示用户上传。
 *
 * 设计：
 * - 仅在 App 前台且 GalleryAlbumTab 可见时触发检测
 * - 使用文件名+大小+修改时间作为去重判据（NAS 已有同名同大小文件视为已同步）
 * - 检测结果缓存，避免每次页面切换都重新查询
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryListItem } from '../model/FnApiTypes';
import { queryLocalPhotos, LocalPhotoEntry } from './GalleryAutoSyncService';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncStore';

function nasTimelineItemName(item: GalleryListItem): string {
  return (item.filename ?? item.fileName ?? item.name ?? '').trim();
}

function nasTimelineItemSize(item: GalleryListItem): number {
  const raw = item.fileSize ?? 0;
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return raw;
  }
  if (typeof raw === 'string') {
    const parsed = Number(raw);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return 0;
}

/** 同步检测结果 */
export interface AutoSyncResult {
  /** 未同步的本地照片列表 */
  unsynced: LocalPhotoEntry[];
  /** 检测时间戳 */
  detectedAt: number;
}

export class GalleryAutoSyncStore {
  /** 上次检测结果 */
  private static lastResult: AutoSyncResult | null = null;
  /** 上次检测时间（毫秒） */
  private static lastDetectTime: number = 0;
  /** 检测间隔（毫秒）：5 分钟内不重复检测 */
  private static readonly DETECT_INTERVAL_MS: number = 5 * 60 * 1000;
  /** 是否正在检测中 */
  private static detecting: boolean = false;

  /**
   * 获取当前未同步照片数量。
   * 如果没有缓存结果或已过期，返回 0（不触发检测）。
   */
  static getUnsyncedCount(): number {
    if (GalleryAutoSyncStore.lastResult === null) {
      return 0;
    }
    return GalleryAutoSyncStore.lastResult.unsynced.length;
  }

  /**
   * 获取未同步照片列表。
   */
  static getUnsyncedPhotos(): LocalPhotoEntry[] {
    if (GalleryAutoSyncStore.lastResult === null) {
      return [];
    }
    return GalleryAutoSyncStore.lastResult.unsynced;
  }

  /**
   * 标记指定照片已同步（从结果中移除）。
   * @param uris 已同步的照片 URI 列表
   */
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

  /**
   * 触发增量同步检测。
   * 对比本地相册与 NAS 时间线中的媒体，找出未同步的本地照片。
   *
   * @param ctx UIAbilityContext
   * @param nasTimeline 当前 NAS 时间线中的媒体列表
   * @param force 强制检测（忽略间隔）
   * @returns 检测结果
   */
  static async detectUnsynced(
    ctx: common.UIAbilityContext,
    nasTimeline: GalleryListItem[],
    force: boolean = false
  ): Promise<AutoSyncResult> {
    // 防止重复检测
    if (GalleryAutoSyncStore.detecting) {
      return GalleryAutoSyncStore.lastResult ?? { unsynced: [], detectedAt: 0 };
    }

    // 检查间隔
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
      // 1. 查询本地相册
      const localPhotos = await queryLocalPhotos(ctx, 500);
      if (localPhotos.length === 0) {
        GalleryAutoSyncStore.lastResult = { unsynced: [], detectedAt: now };
        GalleryAutoSyncStore.lastDetectTime = now;
        return GalleryAutoSyncStore.lastResult;
      }

      // 2. 构建 NAS 已有文件的指纹集合（文件名+大小）
      const nasFingerprints = new Set<string>();
      for (const item of nasTimeline) {
        const name = nasTimelineItemName(item);
        const size = nasTimelineItemSize(item);
        if (name.length > 0) {
          nasFingerprints.add(`${name}:${size}`);
        }
      }

      // 3. 找出未同步的本地照片
      const unsynced: LocalPhotoEntry[] = [];
      for (const local of localPhotos) {
        if (local.fileName.length === 0) {
          continue;
        }
        const fp = `${local.fileName}:${local.fileSize}`;
        if (!nasFingerprints.has(fp)) {
          unsynced.push(local);
        }
      }

      // 4. 按修改时间倒序排列
      unsynced.sort(
        (a: LocalPhotoEntry, b: LocalPhotoEntry): number =>
          b.dateModifiedMs - a.dateModifiedMs
      );

      GalleryAutoSyncStore.lastResult = { unsynced: unsynced, detectedAt: now };
      GalleryAutoSyncStore.lastDetectTime = now;

      hilog.info(
        DOMAIN,
        TAG,
        'detectUnsynced local=%{public}d nas=%{public}d unsynced=%{public}d',
        localPhotos.length,
        nasTimeline.length,
        unsynced.length
      );

      return GalleryAutoSyncStore.lastResult;
    } finally {
      GalleryAutoSyncStore.detecting = false;
    }
  }

  /**
   * 清除缓存（例如用户登出或切换服务器时）。
   */
  static invalidate(): void {
    GalleryAutoSyncStore.lastResult = null;
    GalleryAutoSyncStore.lastDetectTime = 0;
    GalleryAutoSyncStore.detecting = false;
  }
}
