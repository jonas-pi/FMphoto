/**
 * 相册 Tab 内嵌子视图（AI 搜索 / 分类 / 人物等）时，由 Home.onBackPress 委托此处消费系统返回，
 * 避免直接退出应用。
 */
type GalleryAlbumBackHandler = () => boolean;

let galleryAlbumBackHandler: GalleryAlbumBackHandler | null = null;

/** 由 GalleryAlbumTab 在 aboutToAppear / aboutToDisappear 成对注册、清空 */
export function gallerySetAlbumBackHandler(h: GalleryAlbumBackHandler | null): void {
  galleryAlbumBackHandler = h;
}

/** Home 页在相册 Tab 选中时调用；若已消费返回 true */
export function galleryTryConsumeAlbumBack(): boolean {
  const h = galleryAlbumBackHandler;
  if (h === null) {
    return false;
  }
  return h();
}
