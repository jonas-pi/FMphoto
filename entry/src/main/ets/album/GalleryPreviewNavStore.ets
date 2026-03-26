/**
 * 进入独立预览页前写入会话数据（路由 params 不宜携带大列表）。
 * 退出预览页后应 clear，释放引用。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { GalleryListItem } from '../model/FnApiTypes';

const DOMAIN = 0xFF00;
const TAG = 'GalleryNav';

export class GalleryPreviewNavStore {
  static baseUrl: string = '';
  static items: GalleryListItem[] = [];
  static startIndex: number = 0;

  static openPreview(
    baseUrl: string,
    items: GalleryListItem[],
    startIndex: number,
    uiCtx: UIContext
  ): void {
    GalleryPreviewNavStore.baseUrl = baseUrl;
    GalleryPreviewNavStore.items = items.slice();
    const n = GalleryPreviewNavStore.items.length;
    GalleryPreviewNavStore.startIndex = n <= 0 ? 0 : Math.max(0, Math.min(startIndex, n - 1));
    if (n === 0) {
      hilog.warn(DOMAIN, TAG, 'openPreview skipped: empty list');
      return;
    }
    uiCtx.getRouter().pushUrl({
      url: 'pages/GalleryPreview',
      params: { idx: `${GalleryPreviewNavStore.startIndex}` }
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'pushUrl GalleryPreview: %{public}s', String(e));
    });
  }

  static clear(): void {
    GalleryPreviewNavStore.items = [];
    GalleryPreviewNavStore.baseUrl = '';
    GalleryPreviewNavStore.startIndex = 0;
  }
}
