/**
 * 永久删除进度遮罩：显示已提交进度，并提供「停止」。
 *
 * 「停止」只在批与批之间生效：已经交给 NAS 的批次撤回不了
 * （服务端任务标了 cancellable，但取消接口地址没抓到，客户端不主动取消）。
 */
@Component
export struct RecycleBinClearingMask {
  /** 已尝试提交的 id 数 */
  @Prop submitted: number = 0;
  /** 本次总的 id 数 */
  @Prop total: number = 0;
  /** 已全部提交，等 NAS 把 id 真正删掉 */
  @Prop waiting: boolean = false;
  onStop: () => void = () => {};

  private progressText(): string {
    if (this.waiting) {
      return '等待 NAS 处理…';
    }
    return `正在永久删除… ${this.submitted}/${this.total}`;
  }

  build() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(Color.White)
      Text(this.progressText())
        .fontSize(14)
        .fontColor(Color.White)
      // 「停止」只在批与批之间有意义：批次全提交后，NAS 侧的任务撤不回来。
      if (!this.waiting) {
        Text('停止')
          .fontSize(14)
          .fontColor(Color.White)
          .padding({ left: 20, right: 20, top: 10, bottom: 10 })
          .onClick((): void => {
            this.onStop();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.overlay_mask'))
    .hitTestBehavior(HitTestMode.Block)
  }
}
