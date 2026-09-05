/**
 * 登录页专用按钮：官方 Button + systemMaterial（API 26+）+ HdsEffect 按压阴影。
 * 主按钮品牌实底，次按钮与输入框同系实底，避免复用顶栏玻璃胶囊样式。
 */
import { hdsEffect } from '@kit.UIDesignKit';
import {
  fnArkUiSupportsSystemMaterial,
  fnHdsLoginSecondaryButtonSystemMaterial
} from './FnHdsOverlay';

const LOGIN_BTN_HEIGHT_VP: number = 44;
const LOGIN_BTN_FONT_SIZE_VP: number = 16;

@Component
export struct FnLoginPrimaryButton {
  @Prop text: ResourceStr = '';
  @Prop buttonEnabled: boolean = true;
  action: () => void = () => {};
  @State private pressShadowType: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;

  private onPressTouch(event: TouchEvent): void {
    if (!this.buttonEnabled) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.pressShadowType = hdsEffect.PressShadowType.BLEND_WHITE;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.pressShadowType = hdsEffect.PressShadowType.NONE;
    }
  }

  build() {
    Button(this.text, { type: ButtonType.Capsule, stateEffect: false })
      .width('100%')
      .height(LOGIN_BTN_HEIGHT_VP)
      .fontSize(LOGIN_BTN_FONT_SIZE_VP)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.button_primary_fg'))
      .enabled(this.buttonEnabled)
      .backgroundColor($r('app.color.button_primary_bg'))
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pressShadow(this.pressShadowType)
        .buildEffect())
      .onTouch((event: TouchEvent): void => {
        this.onPressTouch(event);
      })
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
  @State private pressShadowType: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;

  private onPressTouch(event: TouchEvent): void {
    if (!this.buttonEnabled) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.pressShadowType = hdsEffect.PressShadowType.BLEND_WHITE;
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.pressShadowType = hdsEffect.PressShadowType.NONE;
    }
  }

  build() {
    Button(this.text, { type: ButtonType.Capsule, stateEffect: false })
      .width('100%')
      .height(LOGIN_BTN_HEIGHT_VP)
      .fontSize(LOGIN_BTN_FONT_SIZE_VP)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.button_secondary_fg'))
      .enabled(this.buttonEnabled)
      .borderWidth(1)
      .borderColor($r('app.color.login_input_border'))
      .backgroundColor(fnArkUiSupportsSystemMaterial() ? Color.Transparent : $r('app.color.login_input_fill'))
      .systemMaterial(fnHdsLoginSecondaryButtonSystemMaterial())
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .pressShadow(this.pressShadowType)
        .buildEffect())
      .onTouch((event: TouchEvent): void => {
        this.onPressTouch(event);
      })
      .onClick((): void => {
        if (this.buttonEnabled) {
          this.action();
        }
      })
  }
}
