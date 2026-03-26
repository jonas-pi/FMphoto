/**
 * 设置：相册 parent_guid、FN ID 说明
 */
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';

@Entry
@Component
struct Settings {
  @State private albumParentGuid: string = '';
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;

  aboutToAppear(): void {
    const s = AppSession.getStored();
    this.albumParentGuid = s !== null ? s.albumParentGuid : '';
  }

  onPageShow(): void {
    this.applySystemBarTheme();
  }

  onColorModeChanged(): void {
    this.applySystemBarTheme();
  }

  private applySystemBarTheme(): void {
    try {
      const dark = this.colorMode === 1;
      const bg = dark ? '#FF1C1C1E' : '#FFF5F5F5';
      const content = dark ? '#FFFFFFFF' : '#FF000000';
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win): void => {
        win.setWindowSystemBarProperties({
          statusBarColor: bg, navigationBarColor: bg,
          statusBarContentColor: content, navigationBarContentColor: content
        }).catch((_e: Error): void => {});
      }).catch((_e: Error): void => {});
    } catch (_e) {}
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .onClick((): void => {
            this.getUIContext().getRouter().back();
          })
        Blank()
        Text($r('app.string.settings'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
        Blank()
        Button($r('app.string.save'))
          .onClick((): void => {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
            AppSession.updateAlbumParentGuid(this.albumParentGuid.trim());
            void AppSession.persist(ctx).then(() => {
              this.getUIContext().getRouter().back();
            });
          })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8 })

      Text($r('app.string.album_parent_label'))
        .fontSize(14)
        .width('100%')

      TextInput({ text: this.albumParentGuid, placeholder: 'fv_xxxx...' })
        .onChange((v: string) => {
          this.albumParentGuid = v;
        })
        .width('100%')

      Text($r('app.string.album_parent_hint'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Text($r('app.string.fnid_deferred'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 24 })
    }
    .padding(16)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.page_background'))
  }
}
