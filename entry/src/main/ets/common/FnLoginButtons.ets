/**
 * 登录主次按钮：胶囊实底，无 HdsTabs 果冻。
 */
const LOGIN_BTN_HEIGHT_VP: number = 44;
const LOGIN_BTN_FONT_SIZE_VP: number = 16;

@Component
export struct FnLoginPrimaryButton {
  @Prop text: ResourceStr = '';
  @Prop buttonEnabled: boolean = true;
  action: () => void = () => {};

  build() {
    Button(this.text, { type: ButtonType.Capsule, stateEffect: true })
      .width('100%')
      .height(LOGIN_BTN_HEIGHT_VP)
      .fontSize(LOGIN_BTN_FONT_SIZE_VP)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.button_primary_fg'))
      .backgroundColor($r('app.color.button_primary_bg'))
      .enabled(this.buttonEnabled)
      .opacity(this.buttonEnabled ? 1 : 0.45)
      .onClick((): void => {
        if (this.buttonEnabled) {
          this.action();
        }
      })
  }
}

@Component
export struct FnLoginSecondaryButton {
  @Prop text: ResourceStr = '';
  @Prop buttonEnabled: boolean = true;
  action: () => void = () => {};

  build() {
    Button(this.text, { type: ButtonType.Capsule, stateEffect: true })
      .width('100%')
      .height(LOGIN_BTN_HEIGHT_VP)
      .fontSize(LOGIN_BTN_FONT_SIZE_VP)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.button_secondary_fg'))
      .backgroundColor($r('app.color.button_secondary_bg'))
      .enabled(this.buttonEnabled)
      .opacity(this.buttonEnabled ? 1 : 0.45)
      .onClick((): void => {
        if (this.buttonEnabled) {
          this.action();
        }
      })
  }
}
