/**
 * 相册列表页公共接线。新加相册不要新开页面、不要复制顶栏/多选/预览。
 *
 * 1. 列表数据：galleryListFromData（id / 缩略图 / 原图流 / 划选 ID）
 * 2. 打开相册网格：CategoryGalleryNavStore.open → CategoryGallery
 * 3. 顶栏 + 更多 + 多选入口：GalleryGridChrome
 * 4. 多选遮罩：GalleryAlbumSelectionOverlay
 * 5. 划选触摸：GalleryGridSlideTouch
 * 6. 预览（原图按钮、详情、上滑详情、下滑退出）：
 *    GalleryPreviewNavStore.openPreview → GalleryPreview
 *    打开时会再跑一遍 normalize，漏归一化也不会丢原图按钮
 * 7. 返回：galleryListTryConsumeOverlays → galleryListPopOrRouterBack
 */
import {
  GalleryListBackStep,
  galleryListPopOrRouterBack,
  galleryListTryConsumeOverlays
} from './GalleryListBack';

export { GalleryListBackStep, galleryListPopOrRouterBack, galleryListTryConsumeOverlays };
