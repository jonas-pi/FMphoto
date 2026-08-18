/**
 * 预览顶底栏显隐：放在 AppStorage，避免写在 GalleryPreview @State 上。
 * 父页 @State 一变会整页 build（含 Swiper/LazyForEach），把实况加载打回未完成。
 */
export const GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY: string = 'galleryPreviewToolbarVisible';
/** 详情半模态盖住预览时藏顶底栏；离场一开始就清，不必等 onDisappear */
export const GALLERY_PREVIEW_DETAILS_COVER_KEY: string = 'galleryPreviewDetailsCover';

export function setGalleryPreviewToolbarVisible(visible: boolean): void {
  AppStorage.setOrCreate<boolean>(GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY, visible);
}

export function setGalleryPreviewDetailsCover(cover: boolean): void {
  AppStorage.setOrCreate<boolean>(GALLERY_PREVIEW_DETAILS_COVER_KEY, cover);
}

export function toggleGalleryPreviewToolbarVisible(): void {
  const cur = AppStorage.get<boolean>(GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY);
  setGalleryPreviewToolbarVisible(cur !== true);
}
