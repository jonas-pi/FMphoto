/**
 * 图库轻触确认类触觉反馈。
 * 规范：短时振动（约 10～50ms）+ usage: touch；强度由系统按场景映射。
 * 无马达/模拟器/调用失败时静默。
 */
import vibrator from '@ohos.vibrator';

export function playGalleryEnterSelectionHaptic(): void {
  try {
    vibrator.startVibration(
      { type: 'time', duration: 35 },
      { id: 0, usage: 'touch' }
    );
  } catch (_e) {
    // 静默
  }
}

/** 时间线下拉达到 Refresh 触发阈值时的轻提示（与 refreshOffset = 状态栏 + 64vp 对齐） */
export function playGalleryPullRefreshThresholdHaptic(): void {
  try {
    vibrator.startVibration(
      { type: 'time', duration: 42 },
      { id: 0, usage: 'touch' }
    );
  } catch (_e) {
    // 静默
  }
}

/** 实况长按开始播放时的轻微确认 */
export function playGalleryLivePhotoHaptic(): void {
  try {
    vibrator.startVibration(
      { type: 'time', duration: 22 },
      { id: 0, usage: 'touch' }
    );
  } catch (_e) {
    // 静默
  }
}
