import { LivePhotoSaveChoice } from '../../album/livephoto/LivePhotoSaveActionSheet';

export class GalleryPreviewSlideshowRuntime {
  slideshowEnabled: boolean = false;
  slideshowIntervalMs: number = 5000;
  slideshowLibraryTotal: number = 0;
  slideshowGlobalIndices: number[] = [];
  slideshowTimerId: number = -1;
  slideshowAdvancePending: boolean = false;
  slideshowPrefetchTimer: number = -1;
  lastLoggedSlideshowGlobal: number = -1;
  lastLoggedSlideshowKey: string = '';
}

export class GalleryPreviewOverlayRuntime {
  choiceSheetResolver: ((index: number) => void) | undefined = undefined;
  liveSaveResolver: ((choice: LivePhotoSaveChoice) => void) | undefined = undefined;
}

/**
 * Preview 非响应式运行态。@State 与 Swiper/DataSource 引用仍留在页面 shell。
 */
export class GalleryPreviewSession {
  slideshow: GalleryPreviewSlideshowRuntime = new GalleryPreviewSlideshowRuntime();
  overlay: GalleryPreviewOverlayRuntime = new GalleryPreviewOverlayRuntime();
  collectSyncGen: number = 0;
}
