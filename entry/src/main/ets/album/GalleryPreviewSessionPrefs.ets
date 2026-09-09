/**
 * 预览会话偏好：只活在当前应用进程里，不写 Preferences。
 * 单击只改当前项；长按按钮锁定后，后续照片/视频沿用。
 */
export class GalleryPreviewSessionPrefs {
  static speedLocked: boolean = false;
  static speedRate: number = 1.0;
  static qualityLocked: boolean = false;
  static qualityIndex: number = 0;
  static originalLocked: boolean = false;

  static lockSpeed(rate: number): void {
    GalleryPreviewSessionPrefs.speedLocked = true;
    GalleryPreviewSessionPrefs.speedRate = rate;
  }

  static unlockSpeed(): void {
    GalleryPreviewSessionPrefs.speedLocked = false;
  }

  static lockQuality(index: number): void {
    GalleryPreviewSessionPrefs.qualityLocked = true;
    GalleryPreviewSessionPrefs.qualityIndex = index;
  }

  static unlockQuality(): void {
    GalleryPreviewSessionPrefs.qualityLocked = false;
  }

  static toggleOriginalLock(): boolean {
    GalleryPreviewSessionPrefs.originalLocked = !GalleryPreviewSessionPrefs.originalLocked;
    return GalleryPreviewSessionPrefs.originalLocked;
  }
}
