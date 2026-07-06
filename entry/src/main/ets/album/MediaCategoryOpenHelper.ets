/**
 * 媒体分类（照片/视频/RAW/动图/实况/截图/全景等）打开 CategoryGallery 的共用逻辑。
 * 首屏裁剪与 prefetchedRemainder 由 CategoryGalleryNavStore.open 统一处理。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { GalleryListItem, MediaCategoryItem } from '../model/FnApiTypes';
import { AppSession } from '../auth/AppSession';
import { CategoryGalleryNavStore } from './CategoryGalleryNavStore';
import {
  categoryCount,
  categoryCover,
  categoryLocalMediaCount,
  categoryTitle,
  parseCategoryMedia
} from './GalleryAlbumEntityData';
import { nasUrl } from './GalleryAlbumCommon';

const DOMAIN = 0xFF00;
const TAG = 'GalleryDiag';
const SEARCH_PAGE_HINT = 200;

export interface MediaCategoryOpenOptions {
  isActive?: () => boolean;
  onToast?: (msg: string) => void;
}

function openingTextForCategory(categoryKey: string, title: string): string {
  if (categoryKey === 'photo') {
    return '加载照片中…';
  }
  return `打开${title}中…`;
}

/**
 * 打开某一媒体分类图库页。
 * @returns 是否已成功发起路由（false 表示未打开或用户已离开）
 */
export async function openMediaCategoryGallery(
  baseUrl: string,
  cat: MediaCategoryItem,
  uiCtx: UIContext,
  options?: MediaCategoryOpenOptions
): Promise<boolean> {
  const isActive = options?.isActive ?? ((): boolean => true);
  const toast = options?.onToast ?? ((_msg: string): void => {});
  const title = categoryTitle(cat);
  const categoryKey = cat.key !== undefined ? cat.key.trim().toLowerCase() : '';
  const localMediaCount = categoryLocalMediaCount(cat);
  // 内嵌列表须全量交给 NavStore，由 open 统一首屏裁剪并写入 prefetchedRemainder
  const localFull = parseCategoryMedia(cat, -1);
  const heroRel = categoryCover(cat);
  const heroImageUri = heroRel.length > 0 ? nasUrl(baseUrl, heroRel) : '';
  const expectedTotalCount = Math.max(categoryCount(cat), localMediaCount, localFull.length);
  hilog.warn(
    DOMAIN,
    TAG,
    'openCategory title=%{public}s key=%{public}s localMediaCount=%{public}d localFull=%{public}d expectedTotal=%{public}d',
    title,
    categoryKey,
    localMediaCount,
    localFull.length,
    expectedTotalCount
  );

  if (localFull.length > 0) {
    if (!isActive()) {
      return false;
    }
    return CategoryGalleryNavStore.open(
      baseUrl,
      title,
      localFull,
      uiCtx,
      false,
      { expectedTotalCount, categoryKey, heroImageUri }
    );
  }

  const client = AppSession.getClient();
  if (client === null) {
    toast('未登录');
    return false;
  }
  const fetched = await client.searchResultsByCategory(cat);
  if (!isActive()) {
    return false;
  }
  if (!fetched.success || fetched.data === undefined || fetched.data.length === 0) {
    toast(fetched.message ?? '该分类暂无可预览媒体');
    return false;
  }
  const resolvedExpectedTotal = fetched.data.length >= SEARCH_PAGE_HINT
    ? Math.max(expectedTotalCount, fetched.data.length + 1)
    : Math.max(expectedTotalCount, fetched.data.length);
  return CategoryGalleryNavStore.open(
    baseUrl,
    title,
    fetched.data,
    uiCtx,
    false,
    { expectedTotalCount: resolvedExpectedTotal, categoryKey, heroImageUri }
  );
}

export { openingTextForCategory };
