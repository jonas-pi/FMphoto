import { common } from '@kit.AbilityKit';
import {
  fnImmersiveBackgroundEffect,
  fnLiquidGlassGradient,
  FnPrimaryButton
} from '../../common/FnUiCommon';
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

  onDismiss: () => void = (): void => {};
  onStart: (config: GallerySlideshowConfig) => void = (_: GallerySlideshowConfig): void => {};

  @State private intervalSec: number = 5;
  @State private includeVideo: boolean = true;
  @State private includeGif: boolean = true;
  @State private prefsLoaded: boolean = false;

  aboutToAppear(): void {
    void this.loadPrefs();
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
  private intervalChip(sec: number) {
    Text(`${sec} 秒`)
      .fontSize(13)
      .fontWeight(this.intervalSec === sec ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.intervalSec === sec ? $r('app.color.brand_primary') : $r('app.color.text_primary'))
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.intervalSec === sec ? '#1A007AFF' : $r('app.color.gallery_material_surface_bg'))
      .borderRadius(16)
      .border({
        width: 1,
        color: this.intervalSec === sec ? $r('app.color.brand_primary') : $r('app.color.immersive_panel_border')
      })
      .margin({ right: 8, bottom: 8 })
      .onClick((): void => {
        this.intervalSec = sec;
      })
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
            Button('取消')
              .layoutWeight(1)
              .height(44)
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.gallery_material_surface_bg'))
              .enabled(!this.preparing)
              .onClick((): void => {
                this.onDismiss();
              })

            FnPrimaryButton({
              text: this.preparing ? '准备中…' : '开始播放',
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
        .width('88%')
        .constraintSize({ maxWidth: 360 })
        .padding({ left: 18, right: 18, top: 18, bottom: 18 })
        .backgroundColor($r('app.color.gallery_material_surface_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect())
        .linearGradient(fnLiquidGlassGradient())
        .borderRadius(24)
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })
        .shadow({ radius: 24, color: '#1A001A33', offsetX: 0, offsetY: 10 })
        .clip(true)
      }
      .width('100%')
      .height('100%')
    }
  }
}
