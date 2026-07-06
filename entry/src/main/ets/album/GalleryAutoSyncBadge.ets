/**

 * 自动同步检测：对比本地相册与 NAS 全库（需 READ_IMAGEVIDEO ACL Profile）。

 */

import { common } from '@kit.AbilityKit';

import { hilog } from '@kit.PerformanceAnalysisKit';

import { AppSession } from '../auth/AppSession';

import { fnEnsureReadImageVideoGranted } from '../common/FnMediaPermission';

import { GalleryListItem } from '../model/FnApiTypes';

import { GalleryAutoSyncStore } from './GalleryAutoSyncStore';



const DOMAIN = 0xFF00;

const TAG = 'AutoSyncBadge';



export function triggerAutoSyncDetection(

  ctx: common.UIAbilityContext,

  timelineItems: GalleryListItem[],

  onDetected: (unsyncedCount: number) => void

): void {

  void (async (): Promise<void> => {

    try {

      const granted = await fnEnsureReadImageVideoGranted(ctx);

      if (!granted) {

        onDetected(0);

        return;

      }

      const client = AppSession.getClient();

      if (client === null) {

        onDetected(0);

        return;

      }

      const result = await GalleryAutoSyncStore.detectUnsynced(ctx, client, false, timelineItems);

      onDetected(result.unsynced.length);

    } catch (e) {

      hilog.warn(DOMAIN, TAG, 'triggerAutoSyncDetection failed: %{public}s', String(e));

      onDetected(0);

    }

  })();

}



export function getAutoSyncBadgeCount(): number {

  return GalleryAutoSyncStore.getUnsyncedCount();

}



export function markAutoSynced(uris: string[]): void {

  GalleryAutoSyncStore.markSynced(uris);

}



export function invalidateAutoSync(): void {

  GalleryAutoSyncStore.invalidate();

}


