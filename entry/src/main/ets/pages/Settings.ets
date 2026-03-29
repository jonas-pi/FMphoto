/**
 * 设置：相册 parent_guid、FN ID 说明
 */
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import {
  GALLERY_TOP_BAR_BUTTON_FONT_VP,
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_ROW_HEIGHT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from '../common/GalleryTopBarLayout';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';

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
        Row() {
          Button($r('app.string.cancel'), { type: ButtonType.Capsule, stateEffect: true })
            .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
            .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
            .backgroundColor($r('app.color.button_secondary_bg'))
            .fontColor($r('app.color.button_secondary_fg'))
            .onClick((): void => {
              this.getUIContext().getRouter().back();
            })
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.Start)

        Text($r('app.string.settings'))
          .layoutWeight(2)
          .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.text_primary'))

        Row() {
          Button($r('app.string.save'), { type: ButtonType.Capsule, stateEffect: true })
            .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
            .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
            .backgroundColor($r('app.color.button_primary_bg'))
            .fontColor($r('app.color.button_primary_fg'))
            .onClick((): void => {
              const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
              AppSession.updateAlbumParentGuid(this.albumParentGuid.trim());
              void AppSession.persist(ctx).then(() => {
                this.getUIContext().getRouter().back();
              });
            })
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: GALLERY_TOP_BAR_PAD_LEFT_VP,
        right: GALLERY_TOP_BAR_PAD_RIGHT_VP,
        top: GALLERY_TOP_BAR_PAD_TOP_VP,
        bottom: GALLERY_TOP_BAR_PAD_BOTTOM_VP
      })

      Text($r('app.string.album_parent_label'))
        .fontSize(14)
        .width('100%')

      TextInput({ text: this.albumParentGuid, placeholder: 'fv_xxxx...' })
        .onChange((v: string) => {
          this.albumParentGuid = v;
        })
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius($r('app.float.radius_small'))
        .padding({ left: 12, right: 12 })

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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 12, y: 0 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: -8, y: 0 });
  }
}
