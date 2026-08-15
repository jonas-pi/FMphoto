/**
 * 切网后只改媒体根地址与会话快照，不丢时间线、不重进主页。
 */
import { GalleryHomeTimelineCache } from './GalleryHomeTimelineCache';
import { GalleryPreviewNavStore } from './GalleryPreviewNavStore';
import { CategoryGalleryNavStore } from './CategoryGalleryNavStore';

export function retargetGalleryAfterEndpointSwitch(webBaseUrl: string, token: string): void {
  const web = webBaseUrl.trim();
  if (web.length === 0) {
    return;
  }
  GalleryHomeTimelineCache.retarget(web, token);
  GalleryPreviewNavStore.baseUrl = web;
  CategoryGalleryNavStore.baseUrl = web;
}
