/**
 * 预览「搜索相似照片」：以图搜图后替换当前预览，打开分类网格页。
 */
import { CategoryGalleryNavStore } from '../../album/CategoryGalleryNavStore';
import { loadSimilarGalleryItems } from '../../album/SmartCategoryMagicSearch';
import { AppSession } from '../../auth/AppSession';
import { GalleryPreviewActionsHost } from './GalleryPreviewActions';

export async function galleryPreviewSearchSimilar(host: GalleryPreviewActionsHost): Promise<void> {
  if (host.similarSearching) {
    return;
  }
  const photoId = host.currentItemId().trim();
  if (photoId.length === 0) {
    host.toast('当前媒体无有效 ID');
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  host.similarSearching = true;
  let keepSearching = false;
  try {
    const mapped = await loadSimilarGalleryItems(client, photoId);
    if (mapped.errorMessage.length > 0) {
      host.toast(mapped.errorMessage);
      return;
    }
    host.detailsVisible = false;
    const opened = await CategoryGalleryNavStore.open(
      host.baseUrl,
      '相似照片',
      mapped.items,
      host.getUIContext(),
      false,
      {
        sourceKind: 'similar',
        expectedTotalCount: mapped.items.length
      },
      true
    );
    if (!opened) {
      host.toast('打开相似照片失败');
      return;
    }
    keepSearching = true;
    setTimeout((): void => {
      host.similarSearching = false;
    }, 280);
  } finally {
    if (!keepSearching) {
      host.similarSearching = false;
    }
  }
}
