/**
 * 实况/动态照片标识：官方同心圆。
 * 宫格用静态小标；全屏预览用略大尺寸并做轻微呼吸，避免与静图混淆。
 */
@Component
export struct GalleryLivePhotoMark {
  @Prop sizeVp: number = 22;
  @Prop animated: boolean = false;
  @State private outerScale: number = 1;

  aboutToAppear(): void {
    if (this.animated) {
      this.outerScale = 1.16;
    }
  }

  private strokeWidth(): number {
    return Math.max(1.4, this.sizeVp * 1.4 / 22);
  }

  private ringSize(ratio: number): number {
    return this.sizeVp * ratio;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Circle()
        .width(this.sizeVp)
        .height(this.sizeVp)
        .fill('#66000000')

      Circle()
        .width(this.ringSize(14 / 22))
        .height(this.ringSize(14 / 22))
        .fill(Color.Transparent)
        .stroke(Color.White)
        .strokeWidth(this.strokeWidth())
        .scale({
          x: this.animated ? this.outerScale : 1,
          y: this.animated ? this.outerScale : 1
        })
        .animation(this.animated ? {
          duration: 1500,
          curve: Curve.EaseInOut,
          iterations: -1,
          playMode: PlayMode.Alternate
        } : { duration: 0 })

      Circle()
        .width(this.ringSize(6 / 22))
        .height(this.ringSize(6 / 22))
        .fill(Color.Transparent)
        .stroke(Color.White)
        .strokeWidth(this.strokeWidth())
    }
    .width(this.sizeVp)
    .height(this.sizeVp)
    .hitTestBehavior(HitTestMode.None)
  }
}
