/**
 * 幻灯片下一张预拉：先中档图，原图锁定时再预拉原图像素。
 * 只写缓存，不碰页面 @State，切页时直接命中。
 */
import { GalleryListItem } from '../../model/FnApiTypes';
import {
  isGifItem,
  isVideoItem,
  loadFullPix,
  loadPreviewMidPix,
  nasUrl,
  pickOriginal,
  pickPreviewThumb
} from '../GalleryAlbumCommon';

function itemOriginalBytes(item: GalleryListItem): number | undefined {
  const raw = item.originalSize !== undefined ? item.originalSize : item.fileSize;
  if (raw === undefined || raw === null) {
    return undefined;
  }
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) {
    return undefined;
  }
  return Math.floor(n);
}

/**
 * 预拉下一张静帧。视频/动图只拉封面，避免和当前播控抢同一条原片缓存。
 */
export function prefetchSlideshowNextItem(
  item: GalleryListItem,
  baseUrl: string,
  prefetchOriginal: boolean,
  cacheDir: string
): void {
  const midUrl = nasUrl(baseUrl, pickPreviewThumb(item));
  if (midUrl.length > 0) {
    void loadPreviewMidPix(midUrl);
  }
  if (isVideoItem(item) || isGifItem(item)) {
    return;
  }
  if (!prefetchOriginal) {
    return;
  }
  const originalUrl = nasUrl(baseUrl, pickOriginal(item));
  if (originalUrl.length === 0) {
    return;
  }
  void loadFullPix(originalUrl, itemOriginalBytes(item), cacheDir);
}
