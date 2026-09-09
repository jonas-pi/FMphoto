/**
 * 消费系统分享 inbox：先确认，再后台上传；未登录则提示。
 */
import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { AppSession } from '../../auth/AppSession';
import { FnTransferQueueStore } from '../../common/FnTransferQueueStore';
import { galleryStartUriListUpload } from '../GalleryUriBackgroundUpload';
import { GalleryShareInbox } from './GalleryShareInbox';

export async function galleryShareTryConsume(
  ui: UIContext,
  toast: (msg: string) => void
): Promise<void> {
  if (GalleryShareInbox.peekCount() === 0 || GalleryShareInbox.isConfirming()) {
    return;
  }
  if (AppSession.getClient() === null) {
    if (GalleryShareInbox.shouldShowLoginHint()) {
      toast('请先登录，登录后可确认并上传分享的媒体');
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
  GalleryShareInbox.beginConfirm();
  let confirmed = false;
  try {
    confirmed = await confirmShareUpload(ui, uris.length);
  } finally {
    GalleryShareInbox.endConfirm();
  }
  if (!confirmed) {
    if (GalleryShareInbox.peekCount() > 0) {
      void galleryShareTryConsume(ui, toast);
    }
    return;
  }
  const ctx = ui.getHostContext() as common.UIAbilityContext;
  toast(`正在上传 ${uris.length} 项分享的媒体`);
  const started = galleryStartUriListUpload(ctx, uris, 'share-upload', '上传', toast);
  if (!started) {
    GalleryShareInbox.enqueue(uris);
  }
  if (GalleryShareInbox.peekCount() > 0) {
    void galleryShareTryConsume(ui, toast);
  }
}

async function confirmShareUpload(ui: UIContext, count: number): Promise<boolean> {
  try {
    const dlg = await ui.getPromptAction().showDialog({
      title: '上传到飞马相册',
      message: count === 1 ? '将这 1 项媒体上传到相册？' : `将这 ${count} 项媒体上传到相册？`,
      buttons: [
        { text: '取消', color: '#99000000' },
        { text: '上传', color: '#FF2563EB' }
      ]
    });
    return dlg.index === 1;
  } catch (_e) {
    return false;
  }
}
