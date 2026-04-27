/**
 * 分类相册页导航数据中转站。
 * 在打开 pages/CategoryGallery 前写入，页面内只读。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { GalleryListItem } from '../model/FnApiTypes';
import { CATEGORY_GALLERY_PHOTO_INITIAL_RENDER_CAP } from './galleryAlbumTab/GalleryAlbumModeData';

const DOMAIN = 0xFF00;
const TAG = 'GalleryDiag';
export const CATEGORY_GALLERY_INITIAL_RENDER_CAP = 240;

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
    const categoryKey = meta?.categoryKey ?? '';
    const initialRenderCap = categoryKey === 'photo'
      ? CATEGORY_GALLERY_PHOTO_INITIAL_RENDER_CAP
      : CATEGORY_GALLERY_INITIAL_RENDER_CAP;
    const shouldCapInitialItems = categoryKey.length > 0 && items.length > initialRenderCap;
    const initialItems = shouldCapInitialItems
      ? items.slice(0, initialRenderCap)
      : items.slice();
    CategoryGalleryNavStore.sessionToken++;
    CategoryGalleryNavStore.baseUrl = baseUrl;
    CategoryGalleryNavStore.title = title;
    CategoryGalleryNavStore.items = initialItems;
    CategoryGalleryNavStore.useCreatedAtGrouping = useCreatedAtGrouping;
    CategoryGalleryNavStore.backgroundLoading = false;
    CategoryGalleryNavStore.expectedTotalCount = Math.max(
      items.length,
      CategoryGalleryNavStore.items.length,
      meta?.expectedTotalCount !== undefined ? Math.max(0, Math.floor(meta.expectedTotalCount)) : items.length
    );
    CategoryGalleryNavStore.categoryKey = categoryKey;
    CategoryGalleryNavStore.heroImageUri = meta?.heroImageUri ?? '';
    CategoryGalleryNavStore.columnsPerRow = meta?.columnsPerRow === 4 ? 4 : 3;
    hilog.warn(
      DOMAIN,
      TAG,
      'open title=%{public}s items=%{public}d initialItems=%{public}d expectedTotal=%{public}d categoryKey=%{public}s useCreatedAt=%{public}s columns=%{public}d',
      title,
      items.length,
      CategoryGalleryNavStore.items.length,
      CategoryGalleryNavStore.expectedTotalCount,
      CategoryGalleryNavStore.categoryKey,
      useCreatedAtGrouping ? 'true' : 'false',
      CategoryGalleryNavStore.columnsPerRow
    );
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
    hilog.warn(
      DOMAIN,
      TAG,
      'appendItems token=%{public}d append=%{public}d total=%{public}d expectedTotal=%{public}d',
      token,
      items.length,
      CategoryGalleryNavStore.items.length,
      CategoryGalleryNavStore.expectedTotalCount
    );
    CategoryGalleryNavStore.version++;
  }

  static replaceItems(token: number, items: GalleryListItem[]): void {
    if (token !== CategoryGalleryNavStore.sessionToken || items.length === 0) {
      return;
    }
    CategoryGalleryNavStore.items = items.slice();
    hilog.warn(
      DOMAIN,
      TAG,
      'replaceItems token=%{public}d total=%{public}d expectedTotal=%{public}d',
      token,
      CategoryGalleryNavStore.items.length,
      CategoryGalleryNavStore.expectedTotalCount
    );
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
