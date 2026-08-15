/**
 * 实况资源未就绪时的静帧垫图 + 加载提示。
 * 仅在 MovingPhoto 尚未就绪时挂载，避免与点击切工具栏、长按播放抢手势。
 */
@Component
export struct GalleryLivePreviewLayer {
  @Prop stillUri: string = '';
  @Prop hintColor: string = '#666666';
  thumbPix: PixelMap | undefined = undefined;
  fullPix: PixelMap | undefined = undefined;
  showOriginal: boolean = false;
  spinnerColor: ResourceColor = Color.Black;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.thumbPix !== undefined) {
        Image(this.showOriginal && this.fullPix !== undefined ? this.fullPix : this.thumbPix)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .dynamicRangeMode(DynamicRangeMode.HIGH)
          .draggable(false)
      } else if (this.stillUri.length > 0) {
        Image(this.stillUri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .draggable(false)
      } else {
        Blank()
          .width('100%')
          .height('100%')
      }
      Column({ space: 8 }) {
        LoadingProgress().width(40).height(40).color(this.spinnerColor)
        Text('实况加载中…').fontSize(13).fontColor(this.hintColor)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
  }
}
