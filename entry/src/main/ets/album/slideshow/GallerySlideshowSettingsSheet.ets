import { common } from '@kit.AbilityKit';
import { FnHdsPillButton } from '../../common/FnUiCommon';
import { gallerySlideshowLoadConfig } from './GallerySlideshowPreferences';
import {
  GALLERY_SLIDESHOW_INTERVAL_SEC_OPTIONS,
  GallerySlideshowConfig
} from './GallerySlideshowTypes';

/**
 * 幻灯片设置：作为 bindSheet FIT_CONTENT 内容，高度跟选项/开关走，
 * 与下载选择、详情半模态同一套官方半模态，不要自绘全屏卡片。
 * 文档：ts-universal-attributes-sheet-transition
 */
@Component
export struct GallerySlideshowSettingsSheet {
  @Prop preparing: boolean = false;

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
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Text('切换间隔')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(GALLERY_SLIDESHOW_INTERVAL_SEC_OPTIONS, (sec: number) => {
            this.intervalChip(sec)
          }, (sec: number) => `slideshow_interval_${sec}`)
        }
        .width('100%')
      }

      if (this.prefsLoaded) {
        // Toggle.isOn 只在创建时生效，必须等偏好读回后再建开关，避免一直显示默认开
        Column({ space: 4 }) {
          this.toggleRow('包含视频', this.includeVideo, (value: boolean): void => {
            this.includeVideo = value;
          })
          this.toggleRow('包含动图', this.includeGif, (value: boolean): void => {
            this.includeGif = value;
          })
        }
      }

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
        .width('100%')
        .margin({ top: 4 })
        .opacity(this.preparing ? 0.6 : 1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 16 })
    .backgroundColor(Color.Transparent)
  }
}
