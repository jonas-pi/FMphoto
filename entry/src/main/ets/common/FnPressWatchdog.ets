/**
 * 按压态看门狗。
 *
 * ArkUI 的按压反馈（收缩/背景光效）靠 TouchType.Up / TouchType.Cancel 复位。
 * 但组件按下后如果同时弹出菜单 / 半模态 / 弹窗，抬手事件会被新弹出的遮罩吃掉，
 * 组件就永远停在「按压态」：
 * 表现是第一次点击能看到「向内收缩一下」的反馈，之后每次点击都没有动画
 * ——因为按压态没有发生变化，动画自然不会重播。
 *
 * 这里在按下时起一个定时器：超时还没等到抬手/取消，就强制复位。
 * 这样无论抬手是否被遮罩吃掉，按压动画都能在下一次点击时重新播放。
 */
export class FnPressWatchdog {
  /** 超时时间。正常点按抬手在 100ms 内，留足余量即可。 */
  private static readonly timeoutMs: number = 800;

  private timer: number = -1;
  private onTimeout: () => void = (): void => {};

  bind(onTimeout: () => void): void {
    this.onTimeout = onTimeout;
  }

  /** 按下时调用：起一个看门狗。 */
  arm(): void {
    this.disarm();
    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.onTimeout();
    }, FnPressWatchdog.timeoutMs);
  }

  /** 收到抬手/取消，或组件消失时调用。 */
  disarm(): void {
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }
}
