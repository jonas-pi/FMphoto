/**
 * 分类相册页导航数据中转站。
 * 仅在打开 pages/CategoryGallery 前写入；各页面实例绑定自己的 sessionToken，原路 back 即可。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, UIContext } from '@kit.ArkUI';
import { GalleryListItem } from '../model/FnApiTypes';
import { CATEGORY_GALLERY_PHOTO_INITIAL_RENDER_CAP } from './GalleryAlbumEntityData';

const DOMAIN = 0xFF00;
const TAG = 'GalleryDiag';
export const CATEGORY_GALLERY_INITIAL_RENDER_CAP = 240;

export interface CategoryGalleryOpenMeta {
  expectedTotalCount?: number;
  categoryKey?: string;
  heroImageUri?: string;
  columnsPerRow?: number;
  sourceKind?: string;
  /** 人物相册来源时的人物 ID */
  personId?: string;
  /** 智能分类来源时的 AI 搜索关键词 */
  smartCategoryKeyword?: string;
}

interface CategoryGallerySessionBackup {
  baseUrl: string;
  title: string;
  items: GalleryListItem[];
  useCreatedAtGrouping: boolean;
  backgroundLoading: boolean;
  sessionToken: number;
  expectedTotalCount: number;
  categoryKey: string;
  heroImageUri: string;
  columnsPerRow: number;
  sourceKind: string;
  personId: string;
  smartCategoryKeyword: string;
  version: number;
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
  static sourceKind: string = '';
  static personId: string = '';
  static smartCategoryKeyword: string = '';

  private static captureSession(): CategoryGallerySessionBackup {
    return {
      baseUrl: CategoryGalleryNavStore.baseUrl,
      title: CategoryGalleryNavStore.title,
      items: CategoryGalleryNavStore.items.slice(),
      useCreatedAtGrouping: CategoryGalleryNavStore.useCreatedAtGrouping,
      backgroundLoading: CategoryGalleryNavStore.backgroundLoading,
      sessionToken: CategoryGalleryNavStore.sessionToken,
      expectedTotalCount: CategoryGalleryNavStore.expectedTotalCount,
      categoryKey: CategoryGalleryNavStore.categoryKey,
      heroImageUri: CategoryGalleryNavStore.heroImageUri,
      columnsPerRow: CategoryGalleryNavStore.columnsPerRow,
      sourceKind: CategoryGalleryNavStore.sourceKind,
      personId: CategoryGalleryNavStore.personId,
      smartCategoryKeyword: CategoryGalleryNavStore.smartCategoryKeyword,
      version: CategoryGalleryNavStore.version
    };
  }

  private static restoreSession(backup: CategoryGallerySessionBackup): void {
    CategoryGalleryNavStore.baseUrl = backup.baseUrl;
    CategoryGalleryNavStore.title = backup.title;
    CategoryGalleryNavStore.items = backup.items.slice();
    CategoryGalleryNavStore.useCreatedAtGrouping = backup.useCreatedAtGrouping;
    CategoryGalleryNavStore.backgroundLoading = backup.backgroundLoading;
    CategoryGalleryNavStore.sessionToken = backup.sessionToken;
    CategoryGalleryNavStore.expectedTotalCount = backup.expectedTotalCount;
    CategoryGalleryNavStore.categoryKey = backup.categoryKey;
    CategoryGalleryNavStore.heroImageUri = backup.heroImageUri;
    CategoryGalleryNavStore.columnsPerRow = backup.columnsPerRow;
    CategoryGalleryNavStore.sourceKind = backup.sourceKind;
    CategoryGalleryNavStore.personId = backup.personId;
    CategoryGalleryNavStore.smartCategoryKeyword = backup.smartCategoryKeyword;
    CategoryGalleryNavStore.version = backup.version;
  }

  static open(
    baseUrl: string,
    title: string,
    items: GalleryListItem[],
    uiCtx: UIContext,
    useCreatedAtGrouping: boolean = false,
    meta?: CategoryGalleryOpenMeta
  ): Promise<boolean> {
    const allowEmptyPage = meta?.sourceKind === 'collect';
    if (items.length === 0 && !allowEmptyPage) {
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
    const backup = CategoryGalleryNavStore.captureSession();
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
    CategoryGalleryNavStore.sourceKind = meta?.sourceKind ?? '';
    CategoryGalleryNavStore.personId = meta?.personId?.trim() ?? '';
    CategoryGalleryNavStore.smartCategoryKeyword = meta?.smartCategoryKeyword?.trim() ?? '';
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
    return uiCtx.getRouter().pushUrl(
      { url: 'pages/CategoryGallery' },
      router.RouterMode.Standard
    ).then((): boolean => {
      return true;
    }).catch((e: Error): boolean => {
      hilog.error(DOMAIN, TAG, 'pushUrl CategoryGallery: %{public}s', String(e));
      CategoryGalleryNavStore.restoreSession(backup);
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

  static removeItemById(idText: string): boolean {
    const id = idText.trim();
    if (id.length === 0 || CategoryGalleryNavStore.items.length === 0) {
      return false;
    }
    const kept: GalleryListItem[] = [];
    let hit = false;
    for (let i = 0; i < CategoryGalleryNavStore.items.length; i++) {
      const it = CategoryGalleryNavStore.items[i];
      const nid = it.id !== undefined && it.id !== null ? String(it.id).trim() : '';
      if (nid === id) {
        hit = true;
        continue;
      }
      kept.push(it);
    }
    if (!hit) {
      return false;
    }
    CategoryGalleryNavStore.items = kept;
    const nextExpected = Math.max(0, CategoryGalleryNavStore.expectedTotalCount - 1);
    CategoryGalleryNavStore.expectedTotalCount = Math.max(kept.length, nextExpected);
    if (kept.length === 0) {
      CategoryGalleryNavStore.expectedTotalCount = 0;
      CategoryGalleryNavStore.backgroundLoading = false;
    }
    CategoryGalleryNavStore.heroImageUri = '';
    hilog.warn(
      DOMAIN,
      TAG,
      'removeItemById id=%{public}s total=%{public}d expectedTotal=%{public}d source=%{public}s',
      id,
      CategoryGalleryNavStore.items.length,
      CategoryGalleryNavStore.expectedTotalCount,
      CategoryGalleryNavStore.sourceKind
    );
    CategoryGalleryNavStore.version++;
    return true;
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
    CategoryGalleryNavStore.sourceKind = '';
    CategoryGalleryNavStore.personId = '';
    CategoryGalleryNavStore.smartCategoryKeyword = '';
    CategoryGalleryNavStore.version++;
  }
}
