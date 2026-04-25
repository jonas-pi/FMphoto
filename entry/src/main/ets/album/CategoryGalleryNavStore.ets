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
  static version: number = 0;
  static backgroundLoading: boolean = false;
  static sessionToken: number = 0;

  static open(
    baseUrl: string,
    title: string,
    items: GalleryListItem[],
    uiCtx: UIContext
  ): Promise<boolean> {
    if (items.length === 0) {
      hilog.warn(DOMAIN, TAG, 'open skipped: empty items');
      return Promise.resolve(false);
    }
    CategoryGalleryNavStore.sessionToken++;
    CategoryGalleryNavStore.baseUrl = baseUrl;
    CategoryGalleryNavStore.title = title;
    CategoryGalleryNavStore.items = items.slice();
    CategoryGalleryNavStore.backgroundLoading = false;
    CategoryGalleryNavStore.version++;
    return uiCtx.getRouter().pushUrl({ url: 'pages/CategoryGallery' }).then((): boolean => {
      return true;
    }).catch((e: Error): boolean => {
      hilog.error(DOMAIN, TAG, 'pushUrl CategoryGallery: %{public}s', String(e));
      CategoryGalleryNavStore.clear();
      return false;
    });
  }

  static currentToken(): number {
    return CategoryGalleryNavStore.sessionToken;
  }

  static setBackgroundLoading(token: number, value: boolean): void {
    if (token !== CategoryGalleryNavStore.sessionToken || CategoryGalleryNavStore.backgroundLoading === value) {
      return;
    }
    CategoryGalleryNavStore.backgroundLoading = value;
    CategoryGalleryNavStore.version++;
  }

  static appendItems(token: number, items: GalleryListItem[]): void {
    if (token !== CategoryGalleryNavStore.sessionToken || items.length === 0) {
      return;
    }
    CategoryGalleryNavStore.items = CategoryGalleryNavStore.items.concat(items);
    CategoryGalleryNavStore.version++;
  }

  static replaceItems(token: number, items: GalleryListItem[]): void {
    if (token !== CategoryGalleryNavStore.sessionToken || items.length === 0) {
      return;
    }
    CategoryGalleryNavStore.items = items.slice();
    CategoryGalleryNavStore.version++;
  }

  static clear(): void {
    CategoryGalleryNavStore.sessionToken++;
    CategoryGalleryNavStore.items = [];
    CategoryGalleryNavStore.baseUrl = '';
    CategoryGalleryNavStore.title = '';
    CategoryGalleryNavStore.backgroundLoading = false;
    CategoryGalleryNavStore.version++;
  }
}
