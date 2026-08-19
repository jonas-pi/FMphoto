/**
 * 图库轻触确认类触觉反馈。
 * 官方 js-apis-vibrator：触控短振优先 VibratePreset；VibrateAttribute 不要写死 id:0，
 * Native 会按 deviceId 查属性，找不到就打 GetPropertyInt32 deviceId 错误。
 */
import { vibrator } from '@kit.SensorServiceKit';

const TOUCH_PRESET_EFFECT: string = 'haptic.effect.soft';

function playTouchHaptic(durationMs: number): void {
  try {
    const attr: vibrator.VibrateAttribute = { usage: 'touch' };
    if (vibrator.isSupportEffectSync(TOUCH_PRESET_EFFECT)) {
      void vibrator.startVibration(
        { type: 'preset', effectId: TOUCH_PRESET_EFFECT, count: 1 },
        attr
      ).catch((): void => {});
      return;
    }
    void vibrator.startVibration(
      { type: 'time', duration: durationMs },
      attr
    ).catch((): void => {});
  } catch (_e) {
    // 无马达 / 模拟器 / 调用失败时静默
  }
}

export function playGalleryEnterSelectionHaptic(): void {
  playTouchHaptic(35);
}

/** 时间线下拉达到 Refresh 触发阈值时的轻提示（与 refreshOffset = 状态栏 + 64vp 对齐） */
export function playGalleryPullRefreshThresholdHaptic(): void {
  playTouchHaptic(42);
}

/** 实况长按开始播放时的轻微确认 */
export function playGalleryLivePhotoHaptic(): void {
  playTouchHaptic(22);
}
