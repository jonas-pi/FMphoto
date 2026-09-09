/**
 * 消费系统分享 inbox：已登录则走后台上传，未登录则提示。
 */
import { common } from '@kit.AbilityKit';
import { AppSession } from '../../auth/AppSession';
import { FnTransferQueueStore } from '../../common/FnTransferQueueStore';
import { galleryStartUriListUpload } from '../GalleryUriBackgroundUpload';
import { GalleryShareInbox } from './GalleryShareInbox';

export function galleryShareTryConsume(
  ctx: common.UIAbilityContext,
  toast: (msg: string) => void
): void {
  if (GalleryShareInbox.peekCount() === 0) {
    return;
  }
  if (AppSession.getClient() === null) {
    if (GalleryShareInbox.shouldShowLoginHint()) {
      toast('请先登录，登录后将上传分享的媒体');
    }
    return;
  }
  if (FnTransferQueueStore.hasRunning()) {
    return;
  }
  const uris = GalleryShareInbox.takeAll();
  if (uris.length === 0) {
    return;
  }
  toast(`正在上传 ${uris.length} 项分享的媒体`);
  const started = galleryStartUriListUpload(ctx, uris, 'share-upload', '上传', toast);
  if (!started) {
    GalleryShareInbox.enqueue(uris);
  }
}
