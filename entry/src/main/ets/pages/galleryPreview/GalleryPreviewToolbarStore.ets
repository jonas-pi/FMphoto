/**
 * 预览顶底栏显隐：放在 AppStorage，避免写在 GalleryPreview @State 上。
 * 父页 @State 一变会整页 build（含 Swiper/LazyForEach），把实况加载打回未完成。
 */
export const GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY: string = 'galleryPreviewToolbarVisible';

export function setGalleryPreviewToolbarVisible(visible: boolean): void {
  AppStorage.setOrCreate<boolean>(GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY, visible);
}

export function toggleGalleryPreviewToolbarVisible(): void {
  const cur = AppStorage.get<boolean>(GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY);
  setGalleryPreviewToolbarVisible(cur !== true);
}
