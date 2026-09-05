/**
 * 设置：相册 parent_guid
 */
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  HdsNavigation,
  HdsNavigationBackButtonItemOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleMode,
  TextStyleMode,
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import { AppSession } from '../auth/AppSession';
import { fnRestoreAppSystemBars } from '../common/FnSplashTheme';
import { FN_SYSTEM_TOP_INSET_VP_KEY, fnPublishSystemAvoidArea } from '../common/FnSystemAvoidArea';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import {
  fnHdsMiniTitleBarOptions,
  FN_HDS_NAV_CHROME_HEIGHT_VP
} from '../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../common/FnImmersiveSettings';

@Entry
@Component
struct Settings {
  @State private albumParentGuid: string = '';
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;

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
      window.getLastWindow(ctx).then((win: window.Window): void => {
        fnRestoreAppSystemBars(win);
        fnPublishSystemAvoidArea(win, this.getUIContext());
        win.setWindowSystemBarProperties({
          statusBarColor: bg, navigationBarColor: bg,
          statusBarContentColor: content, navigationBarContentColor: content
        }).catch((_e: Error): void => {});
      }).catch((_e: Error): void => {});
    } catch (_e) {}
  }

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private persistAndBack(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppSession.updateAlbumParentGuid(this.albumParentGuid.trim());
    void AppSession.persist(ctx).then(() => {
      this.getUIContext().getRouter().back();
    });
  }

  private titleBarContent(): TitleBarContentOptions {
    const saveContent: HdsNavigationIconOptions = {
      label: $r('app.string.save'),
      type: TextStyleMode.NORMAL,
      action: (): void => {
        this.persistAndBack();
      }
    };
    const saveItem: HdsNavigationMenuItemOptions = { content: saveContent };
    const backIcon: HdsNavigationBackButtonItemOptions = {
      label: $r('app.string.cancel'),
      isEnabled: true,
      action: (): void => {
        this.getUIContext().getRouter().back();
      }
    };
    return {
      title: { mainTitle: $r('app.string.settings') },
      menu: { value: [saveItem] },
      backIcon: backIcon
    };
  }

  @Builder
  private navigationContent() {
    Column()
      .width('100%')
      .height(0)
  }

  build() {
    Column() {
      Column() {
        HdsNavigation() {
          this.navigationContent()
        }
        .width('100%')
        .height(FN_HDS_NAV_CHROME_HEIGHT_VP)
        // 顶栏壳固定单栏，避免宽屏 Auto 触发空右栏
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .hideBackButton(false)
        .titleBar(fnHdsMiniTitleBarOptions(this.canUseHds(), this.titleBarContent(), false))
      }
      .width('100%')
      .padding({ top: this.systemTopInsetVp })

      Column({ space: 16 }) {
        Text($r('app.string.album_parent_label'))
          .fontSize(14)
          .width('100%')

        TextInput({ text: this.albumParentGuid, placeholder: 'fv_xxxx...' })
          .enableKeyboardOnFocus(false)
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
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
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
