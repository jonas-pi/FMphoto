/**
 * 视频竖滑调节 HUD：亮度 / 音量条。
 * 交互对齐《基于AVPlayer播放长视频实践》《基于AVPlayer基础播控实践》。
 */
@Component
export struct GalleryVideoGestureHud {
  @Prop visible: boolean = false;
  @Prop isBrightness: boolean = true;
  @Prop brightnessValue: number = 0.5;
  @Prop volumeValue: number = 0;
  @Prop volumeMax: number = 15;

  private sliderValue(): number {
    if (this.isBrightness) {
      return this.brightnessValue;
    }
    if (this.volumeMax <= 0) {
      return 0;
    }
    return this.volumeValue / this.volumeMax;
  }

  build() {
    Column() {
      if (this.visible) {
        Stack() {
          Slider({
            value: this.sliderValue(),
            min: 0,
            max: 1,
            step: 0.01,
            style: SliderStyle.NONE,
            direction: Axis.Vertical,
            reverse: true
          })
            .height(160)
            .selectedColor(Color.White)
            .trackColor('#66000000')
            .trackThickness(40)
            .enabled(false)

          SymbolGlyph(this.isBrightness ? $r('sys.symbol.sun_max_fill') : $r('sys.symbol.speaker_wave_2_fill'))
            .fontSize(20)
            .fontColor([Color.White])
            .margin({ top: 120 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(this.isBrightness ? HorizontalAlign.Start : HorizontalAlign.End)
    .padding({ left: 28, right: 28 })
    .hitTestBehavior(HitTestMode.None)
  }
}
