import { common } from '@kit.AbilityKit';
import {
  FnHdsPillButton,
  fnImmersiveBackgroundEffect,
  fnLiquidGlassGradient
} from '../../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../../common/FnImmersiveSettings';
import { gallerySlideshowLoadConfig } from './GallerySlideshowPreferences';
import {
  GALLERY_SLIDESHOW_INTERVAL_SEC_OPTIONS,
  GallerySlideshowConfig,
  GallerySlideshowScope,
  GallerySlideshowScopeKind,
  gallerySlideshowScopeLabel
} from './GallerySlideshowTypes';

@Component
export struct GallerySlideshowSettingsSheet {
  @Prop scope: GallerySlideshowScope = { kind: GallerySlideshowScopeKind.ALL_GALLERY };
  @Prop visible: boolean = false;
  @Prop preparing: boolean = false;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;

  onDismiss: () => void = (): void => {};
  onStart: (config: GallerySlideshowConfig) => void = (_: GallerySlideshowConfig): void => {};

  @State private intervalSec: number = 5;
  @State private includeVideo: boolean = true;
  @State private includeGif: boolean = true;
  @State private prefsLoaded: boolean = false;

  aboutToAppear(): void {
    void this.loadPrefs();
  }

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private async loadPrefs(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const config = await gallerySlideshowLoadConfig(ctx);
      this.intervalSec = config.intervalSec;
      this.includeVideo = config.includeVideo;
      this.includeGif = config.includeGif;
      this.prefsLoaded = true;
    } catch (_e) {
      this.prefsLoaded = true;
    }
  }

  private buildConfig(): GallerySlideshowConfig {
    return {
      intervalSec: this.intervalSec,
      includeVideo: this.includeVideo,
      includeGif: this.includeGif
    };
  }

  @Builder
  private panelChrome() {
    if (this.canUseHds()) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .hitTestBehavior(HitTestMode.None)
    } else {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.gallery_material_surface_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect())
        .linearGradient(fnLiquidGlassGradient())
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private intervalChip(sec: number) {
    FnHdsPillButton({
      text: `${sec} 秒`,
      widthValue: 76,
      heightValue: 36,
      fontSizeValue: 13,
      fontColorValue: $r('app.color.text_primary'),
      active: this.intervalSec === sec,
      action: (): void => {
        this.intervalSec = sec;
      }
    })
      .margin({ right: 8, bottom: 8 })
  }

  @Builder
  private toggleRow(label: string, isOn: boolean, onChange: (value: boolean) => void) {
    Row() {
      Text(label)
        .layoutWeight(1)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor($r('app.color.brand_primary'))
        .onChange((value: boolean): void => {
          onChange(value);
        })
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    if (!this.visible) {
      Blank()
        .width(0)
        .height(0)
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .onClick((): void => {
            if (!this.preparing) {
              this.onDismiss();
            }
          })

        Stack() {
          this.panelChrome()
          Column({ space: 14 }) {
            Text(gallerySlideshowScopeLabel(this.scope))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            Column({ space: 8 }) {
              Text('切换间隔')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')

              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(GALLERY_SLIDESHOW_INTERVAL_SEC_OPTIONS, (sec: number) => {
                  this.intervalChip(sec)
                }, (sec: number) => `slideshow_interval_${sec}`)
              }
              .width('100%')
            }

            Column({ space: 4 }) {
              this.toggleRow('包含视频', this.includeVideo, (value: boolean): void => {
                this.includeVideo = value;
              })
              this.toggleRow('包含动图', this.includeGif, (value: boolean): void => {
                this.includeGif = value;
              })
            }

            Row({ space: 10 }) {
              FnHdsPillButton({
                text: '取消',
                widthValue: '100%',
                heightValue: 44,
                fontSizeValue: 15,
                fontColorValue: $r('app.color.text_primary'),
                action: (): void => {
                  if (!this.preparing) {
                    this.onDismiss();
                  }
                }
              })
                .layoutWeight(1)

              FnHdsPillButton({
                text: this.preparing ? '准备中…' : '开始播放',
                widthValue: '100%',
                heightValue: 44,
                fontSizeValue: 15,
                fontColorValue: $r('app.color.text_primary'),
                prominent: true,
                action: (): void => {
                  if (!this.preparing && this.prefsLoaded) {
                    this.onStart(this.buildConfig());
                  }
                }
              })
                .layoutWeight(1)
                .opacity(this.preparing ? 0.6 : 1)
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 18, bottom: 18 })
        }
        .width('88%')
        .constraintSize({ maxWidth: 360 })
        .borderRadius(24)
        .borderWidth(this.canUseHds() ? 0 : 1)
        .borderColor($r('app.color.immersive_panel_border'))
        .clip(true)
      }
      .width('100%')
      .height('100%')
    }
  }
}
