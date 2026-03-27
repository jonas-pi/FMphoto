/**
 * 图库多选进入时的触觉反馈。
 * 规范：短时振动（约 10～50ms）+ usage: touch，用于轻触确认类交互；强度由系统按场景映射。
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

/** 时间线下拉达到 Refresh 触发阈值时的轻提示（与进入多选同 usage，时长略短） */
export function playGalleryPullRefreshThresholdHaptic(): void {
  try {
    vibrator.startVibration(
      { type: 'time', duration: 30 },
      { id: 0, usage: 'touch' }
    );
  } catch (_e) {
    // 静默
  }
}
