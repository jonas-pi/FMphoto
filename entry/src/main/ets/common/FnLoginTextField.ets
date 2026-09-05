/**
 * 登录页输入框：透明底 + 组件模糊。
 * 回填用单向 text + 换代 key，避免 $$ 双向绑定把异步 seed 吃掉。
 */
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
  @State private bindGen: number = 0;

  aboutToAppear(): void {
    this.inputText = this.seedText;
  }

  private onSeedTextChanged(): void {
    if (this.inputText === this.seedText) {
      return;
    }
    this.inputText = this.seedText;
    this.bindGen = this.bindGen + 1;
  }

  private fieldGlassEffect(): BackgroundEffectOptions {
    return {
      radius: 24,
      saturation: 1.2,
      brightness: 1.05,
      color: $r('app.color.login_input_fill'),
      adaptiveColor: AdaptiveColor.DEFAULT
    };
  }

  build() {
    TextInput({ text: this.inputText, placeholder: this.placeholder })
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
      .backgroundColor(Color.Transparent)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .backgroundEffect(this.fieldGlassEffect())
      .key(`login-field-${this.bindGen}`)
  }
}
