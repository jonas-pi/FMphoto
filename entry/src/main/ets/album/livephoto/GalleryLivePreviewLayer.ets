/**
 * 实况静帧垫图。始终留在树上，就绪后只 Hidden，避免卸节点造成闪烁。
 * 优先用 MovingPhoto 同源静帧，不用 HDR 缩略图，减少揭开时色差。
 */
@Component
export struct GalleryLivePreviewLayer {
  @Prop stillUri: string = '';
  @Prop hintColor: string = '#666666';
  /** 资源下载中才转圈；控件已挂载、等首帧时只留静帧 */
  @Prop showLoading: boolean = true;
  thumbPix: PixelMap | undefined = undefined;
  fullPix: PixelMap | undefined = undefined;
  showOriginal: boolean = false;
  spinnerColor: ResourceColor = Color.Black;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.stillUri.length > 0) {
        Image(this.stillUri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .autoResize(false)
          .syncLoad(true)
          .draggable(false)
      } else if (this.thumbPix !== undefined) {
        Image(this.showOriginal && this.fullPix !== undefined ? this.fullPix : this.thumbPix)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .autoResize(false)
          .draggable(false)
      } else {
        Blank()
          .width('100%')
          .height('100%')
      }
      if (this.showLoading) {
        Column({ space: 8 }) {
          LoadingProgress().width(40).height(40).color(this.spinnerColor)
          Text('实况加载中…').fontSize(13).fontColor(this.hintColor)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
  }
}
