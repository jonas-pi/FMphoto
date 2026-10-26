/**

 * 自动同步检测：对比本地相册与 NAS 全库（需 READ_IMAGEVIDEO ACL Profile）。

 */

import { common } from '@kit.AbilityKit';

import { hilog } from '@kit.PerformanceAnalysisKit';

import { AppSession } from '../auth/AppSession';

import { fnCheckReadImageVideoGranted } from '../common/FnMediaPermission';
import { fnDiagRecord } from '../common/FnDiagLog';

import { GalleryListItem } from '../model/FnApiTypes';

import { GalleryAutoSyncNasIndex } from './GalleryAutoSyncNasIndex';
import { GalleryAutoSyncStore } from './GalleryAutoSyncStore';



const DOMAIN = 0xFF00;

const TAG = 'AutoSyncBadge';



export interface AutoSyncDetectNotice {
  unsyncedCount: number;
  state: 'denied' | 'offline' | 'failed' | 'ready';
}

export function triggerAutoSyncDetection(
  ctx: common.UIAbilityContext,
  timelineItems: GalleryListItem[],
  onDetected: (notice: AutoSyncDetectNotice) => void
): void {
  void (async (): Promise<void> => {
    try {
      const client = AppSession.getClient();
      if (client === null) {
        onDetected({ unsyncedCount: 0, state: 'offline' });
        return;
      }
      // 图库首屏不是用户点的功能。未授权就跳过，不能在这里弹「图片和视频」权限。
      const granted = await fnCheckReadImageVideoGranted(ctx);
      if (!granted) {
        hilog.info(DOMAIN, TAG, 'auto sync skipped: read permission not granted');
        fnDiagRecord('I', TAG, 'read permission not granted, sync skipped without prompt');
        onDetected({ unsyncedCount: 0, state: 'denied' });
        return;
      }
      const result = await GalleryAutoSyncStore.detectUnsynced(ctx, client, false, timelineItems);
      hilog.info(DOMAIN, TAG, 'auto sync unsynced=%{public}d', result.unsynced.length);
      onDetected({ unsyncedCount: result.unsynced.length, state: 'ready' });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'triggerAutoSyncDetection failed: %{public}s', String(e));
      onDetected({ unsyncedCount: 0, state: 'failed' });
    }
  })();
}



export function getAutoSyncBadgeCount(): number {

  return GalleryAutoSyncStore.getUnsyncedCount();

}



export function markAutoSynced(uris: string[]): void {

  GalleryAutoSyncStore.markSynced(uris);

}



export function invalidateAutoSync(ctx: common.UIAbilityContext | null = null): void {
  GalleryAutoSyncStore.invalidate();
  if (ctx !== null) {
    void GalleryAutoSyncNasIndex.discardDisk(ctx);
  }
}


