/**
 * 图库公共：URL 解析、缩略图/原图加载与 LRU、网格缩略图组件。
 * 供 GalleryAlbumTab 与独立预览页共用，避免重复缓存与解码逻辑。
 */
import {
  galleryListItemIdOf,
  GALLERY_FLOATING_HERO_BACKDROP_HEIGHT_VP,
  GALLERY_PREVIEW_DOUBLE_TAP_SCALE,
  GALLERY_PREVIEW_SCALE_MAX,
  GALLERY_PREVIEW_SCALE_MIN,
  GALLERY_PREVIEW_SNAP_EPS,
  GALLERY_PREVIEW_ZOOM_EPS,
  isGifItem,
  isVideoItem,
  itemFileExt,
  nasUrl,
  pickOriginal,
  pickPreviewThumb,
  pickThumb,
  pickThumbForGridDensity,
  pickVideo,
  thumbDensityCacheRank,
  thumbIdentityOfItem
} from './GalleryItemUrls';
import {
  GalleryThumbLoadTelemetry,
  THUMB_CACHE_MAX,
  clearThumbPixCache,
  currentThumbCacheMax,
  enqueueThumbPaintCommit,
  getPreviewMidPixCached,
  getThumbIdentityCacheRank,
  getThumbLoadTelemetry,
  getThumbPixCached,
  getThumbPixCachedByIdentity,
  isGalleryListScrollFrozen,
  loadFullPix,
  loadPreviewMidPix,
  loadThumbPix,
  prefetchThumbPix,
  recommendedThumbCacheKeep,
  registerGalleryThumbFreezeResume,
  setGalleryListScrollFrozen,
  setGallerySeekDecodeHold,
  setThumbHighThroughputLevel,
  setThumbHighThroughputMode,
  thumbCacheKey,
  trimThumbPixCache,
  trimThumbPixCacheForList
} from './GalleryThumbCache';
import {
  GalleryFloatingHeroBackdrop,
  GalleryNetworkBackdropImage,
  GalleryNetworkThumb,
  GalleryStaticThumbPlaceholder,
  GalleryThumbSkeleton
} from './GalleryThumbWidgets';

export { galleryListItemIdOf };

export {
  GALLERY_FLOATING_HERO_BACKDROP_HEIGHT_VP,
  GALLERY_PREVIEW_DOUBLE_TAP_SCALE,
  GALLERY_PREVIEW_SCALE_MAX,
  GALLERY_PREVIEW_SCALE_MIN,
  GALLERY_PREVIEW_SNAP_EPS,
  GALLERY_PREVIEW_ZOOM_EPS,
  isGifItem,
  isVideoItem,
  itemFileExt,
  nasUrl,
  pickOriginal,
  pickPreviewThumb,
  pickThumb,
  pickThumbForGridDensity,
  pickVideo,
  thumbDensityCacheRank,
  thumbIdentityOfItem
};

export {
  GalleryThumbLoadTelemetry,
  THUMB_CACHE_MAX,
  clearThumbPixCache,
  currentThumbCacheMax,
  enqueueThumbPaintCommit,
  getPreviewMidPixCached,
  getThumbIdentityCacheRank,
  getThumbLoadTelemetry,
  getThumbPixCached,
  getThumbPixCachedByIdentity,
  isGalleryListScrollFrozen,
  loadFullPix,
  loadPreviewMidPix,
  loadThumbPix,
  prefetchThumbPix,
  recommendedThumbCacheKeep,
  registerGalleryThumbFreezeResume,
  setGalleryListScrollFrozen,
  setGallerySeekDecodeHold,
  setThumbHighThroughputLevel,
  setThumbHighThroughputMode,
  thumbCacheKey,
  trimThumbPixCache,
  trimThumbPixCacheForList
};

export {
  GalleryFloatingHeroBackdrop,
  GalleryNetworkBackdropImage,
  GalleryNetworkThumb,
  GalleryStaticThumbPlaceholder,
  GalleryThumbSkeleton
};
