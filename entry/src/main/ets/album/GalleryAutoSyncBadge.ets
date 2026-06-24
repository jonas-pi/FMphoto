/**
 * 自动同步提示徽章组件。
 * 显示未同步的本地照片数量，点击后触发同步流程。
 *
 * 放置位置：GalleryAlbumFloatingTopBarLayer 的工具栏区域。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { GalleryListItem } from '../model/FnApiTypes';
import { GalleryAutoSyncStore } from './GalleryAutoSyncStore';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncBadge';

/**
 * 在 bootstrap 完成后触发同步检测（非阻塞）。
 * @param ctx UIAbilityContext
 * @param timelineItems 当前已加载的时间线条目
 * @param onDetected 检测完成后的回调（未同步数量）
 */
export function triggerAutoSyncDetection(
  ctx: common.UIAbilityContext,
  timelineItems: GalleryListItem[],
  onDetected: (unsyncedCount: number) => void
): void {
  void (async (): Promise<void> => {
    try {
      const result = await GalleryAutoSyncStore.detectUnsynced(ctx, timelineItems);
      onDetected(result.unsynced.length);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'triggerAutoSyncDetection failed: %{public}s', String(e));
      onDetected(0);
    }
  })();
}

/**
 * 获取当前未同步照片数量（来自缓存，不触发新检测）。
 */
export function getAutoSyncBadgeCount(): number {
  return GalleryAutoSyncStore.getUnsyncedCount();
}

/**
 * 标记指定照片已同步（从未同步列表中移除）。
 */
export function markAutoSynced(uris: string[]): void {
  GalleryAutoSyncStore.markSynced(uris);
}

/**
 * 清除同步检测缓存（登出/切换服务器时调用）。
 */
export function invalidateAutoSync(): void {
  GalleryAutoSyncStore.invalidate();
}
