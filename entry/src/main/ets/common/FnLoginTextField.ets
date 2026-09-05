/**
 * 登录页输入框：透明底 + 可见描边 + systemMaterial(THIN)。
 * 官方 FAQ：不透明 materialColor / 不透明底会盖住材质；systemMaterial 须放在边框之后。
 * $$ 绑定本地文本，避免父页每敲一字重建 TextInput 导致输入法延迟。
 */
import { fnArkUiSupportsSystemMaterial, fnHdsLoginInputSystemMaterial } from './FnHdsOverlay';

const LOGIN_FIELD_HEIGHT_VP: number = 44;

@Component
export struct FnLoginTextField {
  @Prop @Watch('onSeedTextChanged') seedText: string = '';
  @Prop placeholder: Resource = $r('app.string.hint_fnid');
  @Prop inputType: InputType = InputType.Normal;
  @Prop fieldEnabled: boolean = true;
  @Prop maxLength: number = -1;
  onChange: (value: string) => void = (_: string) => {};
  @State private inputText: string = '';

  aboutToAppear(): void {
    this.inputText = this.seedText;
  }

  private onSeedTextChanged(): void {
    if (this.inputText !== this.seedText) {
      this.inputText = this.seedText;
    }
  }

  build() {
    TextInput({ text: $$this.inputText, placeholder: this.placeholder })
      .type(this.inputType)
      .maxLength(this.maxLength >= 0 ? this.maxLength : undefined)
      .enableAutoFill(false)
      .enableKeyboardOnFocus(true)
      .onChange((value: string): void => {
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
      .backgroundColor(fnArkUiSupportsSystemMaterial() ? Color.Transparent : $r('app.color.login_input_fill'))
      .systemMaterial(fnHdsLoginInputSystemMaterial())
  }
}
