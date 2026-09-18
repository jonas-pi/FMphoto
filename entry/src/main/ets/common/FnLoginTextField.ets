/**
 * 登录页输入框：实色底。
 * 键盘弹出时整页会重布局，实时模糊会把点击响应拖到 600ms+；上架要求 ≤250ms。
 * TextInput.text 只在创建时生效，后续要用本地 @State + $$；父级改 seedText 时靠 @Watch 写进本地态。
 * InputType.Password 会拉起 TEE 安全键盘，从普通键盘切过去会再卡 600ms+，密码框用普通键盘 + 圆点遮罩。
 */
import { applyLoginPasswordEdit, loginPasswordMask } from './FnLoginPasswordMask';

const LOGIN_FIELD_HEIGHT_VP: number = 44;

@Component
export struct FnLoginTextField {
  @Prop @Watch('onSeedTextChanged') seedText: string = '';
  @Prop placeholder: Resource = $r('app.string.hint_fnid');
  @Prop inputType: InputType = InputType.Normal;
  @Prop fieldEnabled: boolean = true;
  @Prop maxLength: number = -1;
  @Prop maskAsPassword: boolean = false;
  onChange: (value: string) => void = (_: string) => {};
  @State private inputText: string = '';
  @State private displayText: string = '';
  @State private revealPassword: boolean = false;

  aboutToAppear(): void {
    this.inputText = this.seedText;
    this.syncDisplayFromSecret();
  }

  private onSeedTextChanged(): void {
    if (this.inputText !== this.seedText) {
      this.inputText = this.seedText;
      this.syncDisplayFromSecret();
    }
  }

  private syncDisplayFromSecret(): void {
    if (this.maskAsPassword && !this.revealPassword) {
      this.displayText = loginPasswordMask(this.inputText);
    } else {
      this.displayText = this.inputText;
    }
  }

  private commitSecret(next: string): void {
    this.inputText = next;
    this.syncDisplayFromSecret();
    this.onChange(next);
  }

  private onMaskedWillChange(info: EditableTextChangeValue): boolean {
    if (this.revealPassword) {
      return true;
    }
    const masked: string = loginPasswordMask(this.inputText);
    if (info.content === masked) {
      return true;
    }
    this.commitSecret(applyLoginPasswordEdit(this.inputText, info));
    return false;
  }

  private toggleRevealPassword(): void {
    this.revealPassword = !this.revealPassword;
    this.syncDisplayFromSecret();
  }

  build() {
    if (this.maskAsPassword) {
      Row() {
        TextInput({ text: $$this.displayText, placeholder: this.placeholder })
          .type(InputType.Normal)
          .maxLength(this.maxLength >= 0 ? this.maxLength : 512)
          .enableAutoFill(false)
          .enablePreviewText(false)
          .enableKeyboardOnFocus(true)
          .onWillChange((info: EditableTextChangeValue): boolean => {
            return this.onMaskedWillChange(info);
          })
          .onChange((value: string): void => {
            if (this.revealPassword) {
              this.commitSecret(value);
            }
          })
          .layoutWeight(1)
          .height(LOGIN_FIELD_HEIGHT_VP)
          .padding({ left: 14, right: 4 })
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.gallery_material_search_placeholder'))
          .caretColor($r('app.color.brand_primary'))
          .enabled(this.fieldEnabled)
          .backgroundColor(Color.Transparent)

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph(this.revealPassword ? $r('sys.symbol.eye') : $r('sys.symbol.eye_slash'))
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(36)
        .height(36)
        .margin({ right: 4 })
        .backgroundColor(Color.Transparent)
        .enabled(this.fieldEnabled)
        .onClick((): void => {
          this.toggleRevealPassword();
        })
      }
      .width('100%')
      .height(LOGIN_FIELD_HEIGHT_VP)
      .borderRadius($r('app.float.radius_medium'))
      .borderWidth(1)
      .borderColor($r('app.color.login_input_border'))
      .backgroundColor($r('app.color.login_input_fill'))
      .alignItems(VerticalAlign.Center)
    } else {
      TextInput({ text: $$this.inputText, placeholder: this.placeholder })
        .type(this.inputType)
        .maxLength(this.maxLength >= 0 ? this.maxLength : 512)
        .enableAutoFill(false)
        .enableKeyboardOnFocus(true)
        .onChange((value: string): void => {
          this.inputText = value;
          this.onChange(value);
        })
        .width('100%')
        .height(LOGIN_FIELD_HEIGHT_VP)
        .padding({ left: 14, right: 14 })
        .borderRadius($r('app.float.radius_medium'))
        .borderWidth(1)
        .borderColor($r('app.color.login_input_border'))
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.gallery_material_search_placeholder'))
        .caretColor($r('app.color.brand_primary'))
        .enabled(this.fieldEnabled)
        .backgroundColor($r('app.color.login_input_fill'))
    }
  }
}
