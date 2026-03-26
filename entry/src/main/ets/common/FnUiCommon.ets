/**
 * 通用 UI 组件：
 * - FnTopBar: 统一子页面顶栏（返回 + 标题）
 * - FnPrimaryButton/FnSecondaryButton: 统一主次按钮样式
 * - FnFullLoadingMask: 统一全屏阻断式加载遮罩
 */

@Component
export struct FnTopBar {
  @Prop title: string = '';
  @Prop backText: string = '返回';
  @Prop backWidth: number = 56;
  @Prop rightText: string = '';

  build() {
    Row() {
      Button(this.backText)
        .height(34)
        .backgroundColor($r('app.color.button_secondary_bg'))
        .fontColor($r('app.color.button_secondary_fg'))
        .borderRadius($r('app.float.radius_medium'))
        .onClick((): void => {
          this.getUIContext().getRouter().back();
        })

      Text(this.title)
        .layoutWeight(1)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .fontColor($r('app.color.text_primary'))

      if (this.rightText.length > 0) {
        Text(this.rightText)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width(this.backWidth)
          .textAlign(TextAlign.End)
      } else {
        Blank().width(this.backWidth)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 8 })
  }
}

@Component
export struct FnPrimaryButton {
  @Prop text: ResourceStr = '';

  build() {
    Button(this.text)
      .height($r('app.float.button_height'))
      .fontColor($r('app.color.button_primary_fg'))
      .backgroundColor($r('app.color.button_primary_bg'))
      .borderRadius($r('app.float.radius_medium'))
  }
}

@Component
export struct FnSecondaryButton {
  @Prop text: ResourceStr = '';

  build() {
    Button(this.text)
      .height($r('app.float.button_height'))
      .backgroundColor($r('app.color.button_secondary_bg'))
      .fontColor($r('app.color.button_secondary_fg'))
      .borderRadius($r('app.float.radius_medium'))
  }
}

@Component
export struct FnFullLoadingMask {
  @Prop text: string = '加载中…';

  build() {
    Column({ space: 10 }) {
      LoadingProgress().width(48).height(48).color(Color.White)
      Text(this.text).fontSize(14).fontColor(Color.White)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.overlay_mask'))
    .hitTestBehavior(HitTestMode.Block)
  }
}

@Component
export struct FnInlineLoading {
  @Prop text: string = '加载中…';

  build() {
    Row({ space: 10 }) {
      LoadingProgress().width(28).height(28)
      Text(this.text).fontSize(14).fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct FnStateText {
  @Prop text: string = '';
  @Prop isError: boolean = false;

  build() {
    Text(this.text)
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 24, right: 24, top: 40 })
      .textAlign(TextAlign.Center)
      .fontSize(14)
      .fontColor(this.isError ? '#FFE0483E' : $r('app.color.text_secondary'))
  }
}
