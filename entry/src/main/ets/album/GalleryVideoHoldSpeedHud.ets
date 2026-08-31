/**
 * 按住画面 2 倍速标识：对齐视频画面顶（含 letterbox），不跟窗口/状态栏对齐。
 */
/** 相对画面顶再往下收一截，避免贴边 */
const HOLD_SPEED_TOP_EXTRA_VP: number = 20;

@Component
export struct GalleryVideoHoldSpeedHud {
  @Prop visible: boolean = false;
  /** 画面相对播放器容器的顶黑边，单位 vp */
  @Prop videoLetterboxTopVp: number = 0;

  private topOffsetVp(): number {
    const letterbox = this.videoLetterboxTopVp > 0 ? this.videoLetterboxTopVp : 0;
    return letterbox + HOLD_SPEED_TOP_EXTRA_VP;
  }

  build() {
    Column() {
      if (this.visible) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.chevron_forward'))
            .fontSize(16)
            .fontColor([Color.White])
            .fontWeight(FontWeight.Bold)
          SymbolGlyph($r('sys.symbol.chevron_forward'))
            .fontSize(16)
            .fontColor([Color.White])
            .fontWeight(FontWeight.Bold)
            .margin({ left: -10 })
          Text('2.0X')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
        }
        .padding({ left: 18, right: 18, top: 10, bottom: 10 })
        .borderRadius(22)
        .backgroundColor('#4D000000')
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: this.topOffsetVp() })
    .hitTestBehavior(HitTestMode.None)
  }
}
