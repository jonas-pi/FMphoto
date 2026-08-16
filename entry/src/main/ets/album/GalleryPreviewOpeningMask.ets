import { FnFullLoadingMask } from '../common/FnUiCommon';

@Component
export struct GalleryPreviewOpeningMask {
  @Prop topOffsetVp: number = 0;

  build() {
    FnFullLoadingMask({ text: '加载中…', topOffsetVp: this.topOffsetVp })
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Block)
  }
}
