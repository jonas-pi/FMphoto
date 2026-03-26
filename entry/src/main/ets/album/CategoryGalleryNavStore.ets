/**
 * 分类相册页导航数据中转站。
 * 在打开 pages/CategoryGallery 前写入，页面内只读。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { GalleryListItem } from '../model/FnApiTypes';

const DOMAIN = 0xFF00;
const TAG = 'CategoryGalleryNav';

export class CategoryGalleryNavStore {
  static baseUrl: string = '';
  static title: string = '';
  static items: GalleryListItem[] = [];

  static open(
    baseUrl: string,
    title: string,
    items: GalleryListItem[],
    uiCtx: UIContext
  ): void {
    if (items.length === 0) {
      hilog.warn(DOMAIN, TAG, 'open skipped: empty items');
      return;
    }
    CategoryGalleryNavStore.baseUrl = baseUrl;
    CategoryGalleryNavStore.title = title;
    CategoryGalleryNavStore.items = items.slice();
    uiCtx.getRouter().pushUrl({ url: 'pages/CategoryGallery' }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'pushUrl CategoryGallery: %{public}s', String(e));
    });
  }

  static clear(): void {
    CategoryGalleryNavStore.items = [];
    CategoryGalleryNavStore.baseUrl = '';
    CategoryGalleryNavStore.title = '';
  }
}
