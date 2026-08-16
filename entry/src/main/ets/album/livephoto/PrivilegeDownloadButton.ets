/**
 * 官方保存安全控件，文案为「下载」。
 * 点击成功后 1 分钟内可写入 PhotoSubtype.MOVING_PHOTO。
 * 不要放进带模糊/遮挡的父组件，否则授权会失败。
 */
@Component
export struct PrivilegeDownloadButton {
  @Prop allowAuthorize: boolean = true;
  onAuthorized: () => void = () => {};

  private readonly saveOptions: SaveButtonOptions = {
    icon: SaveIconStyle.FULL_FILLED,
    text: SaveDescription.DOWNLOAD,
    buttonType: ButtonType.Capsule
  };

  build() {
    SaveButton(this.saveOptions)
      .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => {
        if (result === SaveButtonOnClickResult.SUCCESS && this.allowAuthorize) {
          this.onAuthorized();
        }
      })
  }
}
