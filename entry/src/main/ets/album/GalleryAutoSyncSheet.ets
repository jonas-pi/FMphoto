/**
 * 自动同步底部弹窗组件。
 * 显示未同步的本地照片缩略图网格，用户点击「同步」按钮后批量上传到 NAS。
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { BackgroundKeepAliveController } from '../background/BackgroundKeepAliveController';
import { LocalPhotoEntry } from './GalleryAutoSyncService';
import { GalleryAutoSyncStore } from './GalleryAutoSyncStore';
import { GalleryTimelineRefreshStore } from './GalleryTimelineRefreshStore';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncSheet';

export interface AutoSyncSheetHost {
  /** 是否显示弹窗 */
  syncSheetVisible: boolean;
  /** 是否正在同步 */
  syncing: boolean;
  /** 同步进度文本 */
  syncProgressText: string;
  /** 未同步照片列表 */
  unsyncedPhotos: LocalPhotoEntry[];
  /** toast 回调 */
  toast(msg: string): void;
  /** 刷新时间线 */
  requestBootstrap(debounced: boolean): void;
}

/**
 * 执行批量同步上传。
 * @param host 宿主状态
 * @param ctx UIAbilityContext
 */
export async function runAutoSync(
  host: AutoSyncSheetHost,
  ctx: common.UIAbilityContext
): Promise<void> {
  if (host.syncing) {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  const photos = host.unsyncedPhotos;
  if (photos.length === 0) {
    host.toast('没有需要同步的照片');
    return;
  }

  host.syncing = true;
  host.syncProgressText = `同步中 0/${photos.length}…`;
  let ok = 0;
  let failMsg = '';
  const stored = AppSession.getStored();
  const albumDirHint =
    stored !== null && stored.albumParentGuid.trim().length > 0
      ? stored.albumParentGuid.trim()
      : undefined;

  try {
    await BackgroundKeepAliveController.withDataTransfer(ctx, 'auto-sync', async (): Promise<void> => {
      for (let i = 0; i < photos.length; i++) {
        host.syncProgressText = `同步中 ${i + 1}/${photos.length}…`;
        try {
          const res = await client.uploadPhotoByUri(photos[i].uri, 150000, albumDirHint);
          if (res.success) {
            ok++;
            GalleryAutoSyncStore.markSynced([photos[i].uri]);
          } else if (failMsg.length === 0) {
            failMsg = res.message ?? '同步失败';
          }
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'auto-sync upload failed: %{public}s', String(e));
          if (failMsg.length === 0) {
            failMsg = '同步失败，请稍后重试';
          }
        }
      }
    });
  } finally {
    host.syncing = false;
    host.syncProgressText = '';
  }

  if (ok > 0) {
    host.toast(`同步完成 ${ok}/${photos.length}`);
    GalleryTimelineRefreshStore.bump();
    host.requestBootstrap(false);
  } else {
    host.toast(failMsg.length > 0 ? failMsg : '同步失败，请稍后重试');
  }
}
