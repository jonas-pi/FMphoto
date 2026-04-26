/**
 * 分类相册页导航数据中转站。
 * 在打开 pages/CategoryGallery 前写入，页面内只读。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { GalleryListItem } from '../model/FnApiTypes';

const DOMAIN = 0xFF00;
const TAG = 'CategoryGalleryNav';

export interface CategoryGalleryOpenMeta {
  expectedTotalCount?: number;
  categoryKey?: string;
  heroImageUri?: string;
  columnsPerRow?: number;
}

export class CategoryGalleryNavStore {
  static baseUrl: string = '';
  static title: string = '';
  static items: GalleryListItem[] = [];
  static useCreatedAtGrouping: boolean = false;
  static version: number = 0;
  static backgroundLoading: boolean = false;
  static sessionToken: number = 0;
  static expectedTotalCount: number = 0;
  static categoryKey: string = '';
  static heroImageUri: string = '';
  static columnsPerRow: number = 3;

  static open(
    baseUrl: string,
    title: string,
    items: GalleryListItem[],
    uiCtx: UIContext,
    useCreatedAtGrouping: boolean = false,
    meta?: CategoryGalleryOpenMeta
  ): Promise<boolean> {
    if (items.length === 0) {
      hilog.warn(DOMAIN, TAG, 'open skipped: empty items');
      return Promise.resolve(false);
    }
    CategoryGalleryNavStore.sessionToken++;
    CategoryGalleryNavStore.baseUrl = baseUrl;
    CategoryGalleryNavStore.title = title;
    CategoryGalleryNavStore.items = items.slice();
    CategoryGalleryNavStore.useCreatedAtGrouping = useCreatedAtGrouping;
    CategoryGalleryNavStore.backgroundLoading = false;
    CategoryGalleryNavStore.expectedTotalCount = Math.max(
      items.length,
      meta?.expectedTotalCount !== undefined ? Math.max(0, Math.floor(meta.expectedTotalCount)) : items.length
    );
    CategoryGalleryNavStore.categoryKey = meta?.categoryKey ?? '';
    CategoryGalleryNavStore.heroImageUri = meta?.heroImageUri ?? '';
    CategoryGalleryNavStore.columnsPerRow = meta?.columnsPerRow === 4 ? 4 : 3;
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
    CategoryGalleryNavStore.useCreatedAtGrouping = false;
    CategoryGalleryNavStore.backgroundLoading = false;
    CategoryGalleryNavStore.expectedTotalCount = 0;
    CategoryGalleryNavStore.categoryKey = '';
    CategoryGalleryNavStore.heroImageUri = '';
    CategoryGalleryNavStore.columnsPerRow = 3;
    CategoryGalleryNavStore.version++;
  }
}
