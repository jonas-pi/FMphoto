import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { GalleryAlbumTab } from '../album/GalleryAlbumTab';
import { galleryTryConsumeAlbumBack } from '../album/GalleryAlbumHardwareBack';
import { AppSession } from '../auth/AppSession';
import { proactiveRefreshLongTokenOnForeground } from '../auth/SessionReauth';
import { SessionPreferences } from '../auth/SessionPreferences';
import { fnWebViewBaseUrl } from '../network/ServerUrl';
import { FnImmersiveBackdrop, FnPrimaryButton } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION,
  FN_TAB_ALBUM_ME_CURVE,
  FN_TAB_ALBUM_ME_IN_MS,
  FN_TAB_ALBUM_ME_OUT_MS,
  FN_TAB_SWITCH_CURVE,
  FN_TAB_SWITCH_IN_DURATION
} from '../common/FnMotion';
import {
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_ROW_HEIGHT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from '../common/GalleryTopBarLayout';

const HOME_FLOATING_DOCK_SIDE_BUTTON_SIZE_VP: number = 58;
const HOME_FLOATING_DOCK_SIDE_GAP_VP: number = 12;
const HOME_FLOATING_DOCK_CENTER_HEIGHT_VP: number = 58;
const HOME_FLOATING_DOCK_BOTTOM_GAP_VP: number = 16;
const HOME_FLOATING_DOCK_SIDE_PADDING_VP: number = 14;
const HOME_FLOATING_DOCK_NAV_ITEM_RADIUS_VP: number = 18;
const HOME_FLOATING_DOCK_NAV_ICON_SIZE_VP: number = 20;
const HOME_FLOATING_DOCK_NAV_LABEL_SIZE_VP: number = 12;
const HOME_FLOATING_DOCK_CENTER_RADIUS_VP: number = 29;

@Component
struct MePanel {
  @Prop topSafeInsetVp: number = 0;

  build() {
    Column() {
      Row() {
        Row()
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)

        Text('我的')
          .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(2)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row()
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: GALLERY_TOP_BAR_PAD_LEFT_VP,
        right: GALLERY_TOP_BAR_PAD_RIGHT_VP,
        top: GALLERY_TOP_BAR_PAD_TOP_VP + this.topSafeInsetVp,
        bottom: GALLERY_TOP_BAR_PAD_BOTTOM_VP
      })

      Column({ space: 18 }) {
        Column({ space: 10 }) {
          Text('FNOS 个人中心')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text('首页已经切换为纯原生图库壳体，这里保留账号与系统入口。')
            .fontSize(13)
            .lineHeight(20)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding(18)
        .backgroundColor($r('app.color.immersive_panel_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .borderRadius(24)
        .borderWidth(1)
        .borderColor($r('app.color.immersive_panel_border'))
        .shadow({ radius: 24, color: '#14001A33', offsetX: 0, offsetY: 10 })

        Column({ space: 12 }) {
          Text('当前状态')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('1. 首页 Web 已完全移除。')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text('2. 底部主导航统一为照片、相册、我的。')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text('3. 图库主页使用悬浮标题栏与悬浮底部导航。')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding(18)
        .backgroundColor($r('app.color.immersive_panel_strong_bg'))
        .borderRadius(24)
        .borderWidth(1)
        .borderColor($r('app.color.immersive_panel_border'))

        Button($r('app.string.logout'))
          .width('100%')
          .height($r('app.float.button_height'))
          .backgroundColor('#E11D48')
          .fontColor(Color.White)
          .borderRadius($r('app.float.radius_medium'))
          .shadow({ radius: 18, color: '#40E11D48', offsetX: 0, offsetY: 8 })
          .onClick((): void => {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
            void SessionPreferences.clearSession(ctx).then(() => {
              AppSession.clear();
              this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
              });
            });
          })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 24, right: 24, top: 8, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}

@Entry
@Component
struct Home {
  @State private galleryBaseUrl: string = '';
  @State private sessionOk: boolean = false;
  @State private albumSearchModeActive: boolean = false;
  @State private bottomNavIndex: number = 0;
  @State private albumReloadEpoch: number = 0;
  @State private pageShowSignal: number = 0;
  @State private contentTranslateX: number = 0;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @State private isDarkTheme: boolean = false;
  @State private systemTopInsetVp: number = 0;
  @State private systemBottomInsetVp: number = 0;

  onBackPress(): boolean {
    if (this.bottomNavIndex !== 2 && galleryTryConsumeAlbumBack()) {
      return true;
    }
    return false;
  }

  onPageShow(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBarTheme();
    this.pageShowSignal++;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void proactiveRefreshLongTokenOnForeground(ctx).then((changed: boolean): void => {
      if (changed) {
        this.albumReloadEpoch++;
      }
    });
  }

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBarTheme();
  }

  private applySystemBarTheme(): void {
    try {
      const dark = this.colorMode === 1;
      const content = dark ? '#FFFFFFFF' : '#FF000000';
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win): void => {
        win.setWindowLayoutFullScreen(true).catch((_e: Error): void => {});
        this.syncSystemAvoidArea(win);
        win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: content,
          navigationBarContentColor: content
        }).catch((_e: Error): void => {});
      }).catch((_e: Error): void => {});
    } catch (_e) {
    }
  }

  private pxToVp(value: number): number {
    try {
      return this.getUIContext().px2vp(value);
    } catch (_e) {
      return value;
    }
  }

  private syncSystemAvoidArea(win: window.Window): void {
    try {
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.systemTopInsetVp = Math.max(0, this.pxToVp(area.topRect.height));
      this.systemBottomInsetVp = Math.max(0, this.pxToVp(area.bottomRect.height));
    } catch (_e) {
      this.systemTopInsetVp = 0;
      this.systemBottomInsetVp = 0;
    }
  }

  private bottomDockBottomGap(): number {
    const liftedGap = HOME_FLOATING_DOCK_BOTTOM_GAP_VP + (HOME_FLOATING_DOCK_CENTER_HEIGHT_VP / 4);
    return Math.max(liftedGap, this.systemBottomInsetVp + liftedGap);
  }

  private dockReserveHeight(): number {
    if (!this.sessionOk || !this.shouldShowBottomDock()) {
      return 0;
    }
    return Math.max(HOME_FLOATING_DOCK_CENTER_HEIGHT_VP, HOME_FLOATING_DOCK_SIDE_BUTTON_SIZE_VP) +
      this.bottomDockBottomGap() + 16;
  }

  private shouldShowBottomDock(): boolean {
    return !this.albumSearchModeActive;
  }

  private isGalleryShellVisible(): boolean {
    return this.bottomNavIndex !== 2;
  }

  private currentHomeSurface(): string {
    return this.bottomNavIndex === 1 ? 'albums' : 'photos';
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_e) {
    }
  }

  private isDockNavItemSelected(index: number): boolean {
    return this.bottomNavIndex === index;
  }

  private shouldShowGalleryDockSideButtons(): boolean {
    return this.isGalleryShellVisible() && this.currentHomeSurface() === 'photos';
  }

  private switchTab(target: number): void {
    if (target === this.bottomNavIndex) {
      return;
    }
    const albumMeSwitch = target === 2 || this.bottomNavIndex === 2;
    if (!albumMeSwitch) {
      this.bottomNavIndex = target;
      return;
    }
    const towardMe = target === 2;
    const outPx = towardMe ? -22 : 22;
    this.getUIContext().animateTo(
      { duration: FN_TAB_ALBUM_ME_OUT_MS, curve: FN_TAB_ALBUM_ME_CURVE },
      (): void => {
        this.contentTranslateX = outPx;
      }
    );
    setTimeout((): void => {
      this.bottomNavIndex = target;
      this.getUIContext().animateTo(
        { duration: FN_TAB_ALBUM_ME_IN_MS, curve: FN_TAB_ALBUM_ME_CURVE },
        (): void => {
          this.contentTranslateX = 0;
        }
      );
    }, Math.floor(FN_TAB_ALBUM_ME_OUT_MS * 0.55));
  }

  aboutToAppear(): void {
    this.isDarkTheme = this.colorMode === 1;
    const session = AppSession.getStored();
    if (session !== null && session.token.length > 0 && session.baseUrl.length > 0) {
      let base = session.baseUrl;
      if (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      this.galleryBaseUrl = fnWebViewBaseUrl(base);
      this.sessionOk = true;
      if (session.fnosLongToken.length === 0) {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        const client = AppSession.getClient();
        if (client !== null) {
          void client.fetchFnosLongTokenProbe(12000).then((token: string): void => {
            if (token.length <= 0) {
              return;
            }
            const current = AppSession.getStored();
            if (current === null) {
              return;
            }
            current.fnosLongToken = token;
            AppSession.apply(current);
            void SessionPreferences.save(ctx, current);
            this.albumReloadEpoch++;
          });
        }
      }
    }
  }

  @Builder
  private floatingDockGridGlyph() {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        ForEach([0, 1], (idx: number) => {
          Column()
            .width(8)
            .height(8)
            .borderRadius(3)
            .backgroundColor(idx === 0 ? $r('app.color.brand_primary') : $r('app.color.text_primary'))
        }, (idx: number) => `dock_grid_top_${idx}`)
      }
      Row({ space: 4 }) {
        ForEach([0, 1], (idx: number) => {
          Column()
            .width(8)
            .height(8)
            .borderRadius(3)
            .backgroundColor(idx === 1 ? $r('app.color.brand_primary') : $r('app.color.text_primary'))
        }, (idx: number) => `dock_grid_bottom_${idx}`)
      }
    }
  }

  @Builder
  private floatingDockAlbumGlyph(active: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(16)
        .height(12)
        .borderRadius(4)
        .border({ width: 1.5, color: active ? $r('app.color.brand_primary') : $r('app.color.text_secondary') })
        .translate({ x: 3, y: -3 })
      Column()
        .width(16)
        .height(12)
        .borderRadius(4)
        .border({ width: 1.5, color: active ? $r('app.color.brand_primary') : $r('app.color.text_secondary') })
        .translate({ x: -3, y: 3 })
    }
    .width(24)
    .height(24)
  }

  @Builder
  private floatingDockNavItem(index: number, label: string) {
    Button() {
      Column({ space: 6 }) {
        if (index === 0) {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(HOME_FLOATING_DOCK_NAV_ICON_SIZE_VP)
            .fontColor([this.isDockNavItemSelected(index)
              ? $r('app.color.brand_primary')
              : $r('app.color.text_secondary')])
        } else if (index === 1) {
          this.floatingDockAlbumGlyph(this.isDockNavItemSelected(index))
        } else {
          SymbolGlyph($r('sys.symbol.person'))
            .fontSize(HOME_FLOATING_DOCK_NAV_ICON_SIZE_VP)
            .fontColor([this.isDockNavItemSelected(index)
              ? $r('app.color.brand_primary')
              : $r('app.color.text_secondary')])
        }

        Text(label)
          .fontSize(HOME_FLOATING_DOCK_NAV_LABEL_SIZE_VP)
          .fontWeight(this.isDockNavItemSelected(index) ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.isDockNavItemSelected(index)
            ? $r('app.color.brand_primary')
            : $r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .height(HOME_FLOATING_DOCK_CENTER_HEIGHT_VP - 10)
    .borderRadius(HOME_FLOATING_DOCK_NAV_ITEM_RADIUS_VP)
    .backgroundColor(this.isDockNavItemSelected(index) ? $r('app.color.gallery_material_surface_bg') : Color.Transparent)
    .border(this.isDockNavItemSelected(index)
      ? { width: 1, color: $r('app.color.immersive_panel_border') }
      : { width: 0, color: Color.Transparent })
    .scale({
      x: this.isDockNavItemSelected(index) ? 1 : 0.98,
      y: this.isDockNavItemSelected(index) ? 1 : 0.98
    })
    .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
    .onClick((): void => {
      this.switchTab(index);
    })
  }

  @Builder
  private floatingDockSideButton(isLayoutButton: boolean) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      if (isLayoutButton) {
        this.floatingDockGridGlyph()
      } else {
        Text('日')
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
    }
    .width(HOME_FLOATING_DOCK_SIDE_BUTTON_SIZE_VP)
    .height(HOME_FLOATING_DOCK_SIDE_BUTTON_SIZE_VP)
    .borderRadius(HOME_FLOATING_DOCK_SIDE_BUTTON_SIZE_VP / 2)
    .backgroundColor($r('app.color.gallery_material_surface_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .border({ width: 1, color: $r('app.color.immersive_panel_border') })
    .shadow({ radius: 18, color: '#14001A33', offsetX: 0, offsetY: 8 })
    .padding(0)
    .clip(true)
    .onClick((): void => {
      this.toast(isLayoutButton ? '显示模式切换入口预留中' : '视图粒度切换入口预留中');
    })
  }

  @Builder
  private floatingDockNavCapsule() {
    Row({ space: 8 }) {
      this.floatingDockNavItem(0, '鐓х墖')
      this.floatingDockNavItem(1, '鐩稿唽')
      this.floatingDockNavItem(2, '鎴戠殑')
    }
    .height(HOME_FLOATING_DOCK_CENTER_HEIGHT_VP)
    .padding({ left: 6, right: 6 })
    .backgroundColor($r('app.color.immersive_tabbar_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .borderRadius(HOME_FLOATING_DOCK_CENTER_RADIUS_VP)
    .border({ width: 1, color: $r('app.color.immersive_panel_border') })
    .shadow({ radius: 30, color: '#16002B55', offsetX: 0, offsetY: 10 })
  }

  @Builder
  private floatingBottomDock() {
    Row({ space: HOME_FLOATING_DOCK_SIDE_GAP_VP }) {
      if (this.shouldShowGalleryDockSideButtons()) {
        this.floatingDockSideButton(true)
      } else {
        Blank()
          .width(HOME_FLOATING_DOCK_SIDE_BUTTON_SIZE_VP)
          .height(HOME_FLOATING_DOCK_SIDE_BUTTON_SIZE_VP)
      }

      Row({ space: 8 }) {
        this.floatingDockNavItem(0, '照片')
        this.floatingDockNavItem(1, '相册')
        this.floatingDockNavItem(2, '我的')
      }
      .layoutWeight(1)
      .height(HOME_FLOATING_DOCK_CENTER_HEIGHT_VP)
      .padding({ left: 6, right: 6 })
      .backgroundColor($r('app.color.immersive_tabbar_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .borderRadius(HOME_FLOATING_DOCK_CENTER_RADIUS_VP)
      .border({ width: 1, color: $r('app.color.immersive_panel_border') })
      .shadow({ radius: 30, color: '#16002B55', offsetX: 0, offsetY: 10 })

      if (this.shouldShowGalleryDockSideButtons()) {
        this.floatingDockSideButton(false)
      } else {
        Blank()
          .width(HOME_FLOATING_DOCK_SIDE_BUTTON_SIZE_VP)
          .height(HOME_FLOATING_DOCK_SIDE_BUTTON_SIZE_VP)
      }
    }
    .width('100%')
    .padding({ left: HOME_FLOATING_DOCK_SIDE_PADDING_VP, right: HOME_FLOATING_DOCK_SIDE_PADDING_VP })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: this.bottomDockBottomGap() })
  }

  build() {
    Stack() {
      FnImmersiveBackdrop()

      if (!this.sessionOk) {
        Column() {
          Column({ space: 16 }) {
            Text($r('app.string.home_session_missing'))
              .fontSize(22)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            Text($r('app.string.home_session_hint'))
              .fontSize(14)
              .lineHeight(22)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            FnPrimaryButton({ text: $r('app.string.back_to_login') })
              .width('100%')
              .margin({ top: 8 })
              .onClick((): void => {
                this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
                });
              })
          }
          .padding(24)
          .backgroundColor($r('app.color.immersive_panel_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .borderRadius(28)
          .borderWidth(1)
          .borderColor($r('app.color.immersive_panel_border'))
          .shadow({ radius: 24, color: '#16002B55', offsetX: 0, offsetY: 10 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 20, right: 20 })
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Stack() {
            if (this.isGalleryShellVisible()) {
              GalleryAlbumTab({
                baseUrl: this.galleryBaseUrl,
                albumReloadEpoch: this.albumReloadEpoch,
                pageShowSignal: this.pageShowSignal,
                topSafeInsetVp: this.systemTopInsetVp,
                bottomSafeInsetVp: this.systemBottomInsetVp,
                floatingDockInsetBottomVp: this.dockReserveHeight(),
                homeSurface: this.currentHomeSurface(),
                onSearchModeVisibilityChange: (hiddenBottomNav: boolean): void => {
                  this.albumSearchModeActive = hiddenBottomNav;
                }
              })
                .width('100%')
                .height('100%')
            } else {
              MePanel({ topSafeInsetVp: this.systemTopInsetVp })
                .width('100%')
                .height('100%')
            }
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ bottom: this.isGalleryShellVisible() ? 0 : this.dockReserveHeight() })
          .translate({ x: this.contentTranslateX, y: 0 })
        }
        .width('100%')
        .height('100%')

        if (this.shouldShowBottomDock()) {
          Column() {
            Blank()
              .layoutWeight(1)
              .hitTestBehavior(HitTestMode.None)
            this.floatingBottomDock()
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
    }
    .width('100%')
    .height('100%')
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
