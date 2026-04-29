import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier, window } from '@kit.ArkUI';
import { BlurStrategy, DividerMode, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { GalleryAlbumTab } from '../album/GalleryAlbumTab';
import { galleryTryConsumeAlbumBack } from '../album/GalleryAlbumHardwareBack';
import { AppSession } from '../auth/AppSession';
import { proactiveRefreshLongTokenOnForeground } from '../auth/SessionReauth';
import { SessionPreferences } from '../auth/SessionPreferences';
import { fnWebViewBaseUrl } from '../network/ServerUrl';
import {
  fnBottomDockBottomGap,
  fnHdsImmersiveSystemMaterialEffect,
  fnImmersiveBackgroundEffect,
  fnImmersivePointLightSourceEffect,
  fnImmersiveTouchPressed,
  fnLiquidGlassGradient,
  FnImmersiveBackdrop,
  FnPrimaryButton,
  FN_BOTTOM_DOCK_CENTER_HEIGHT_VP,
  FN_BOTTOM_DOCK_CENTER_RADIUS_VP,
  FN_BOTTOM_DOCK_ICON_SIZE_VP,
  FN_BOTTOM_DOCK_INNER_PADDING_H_VP,
  FN_BOTTOM_DOCK_INNER_SPACE_VP,
  FN_BOTTOM_DOCK_ITEM_HEIGHT_VP,
  FN_BOTTOM_DOCK_ITEM_RADIUS_VP,
  FN_BOTTOM_DOCK_LABEL_SIZE_VP,
  FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP,
  FN_BOTTOM_DOCK_SIDE_GAP_VP,
  FN_BOTTOM_DOCK_SIDE_PADDING_VP
} from '../common/FnUiCommon';
import {
  FN_GLOBAL_TAB_SWITCH_CURVE,
  FN_GLOBAL_TAB_SWITCH_DURATION,
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import {
  GalleryViewGranularity,
  galleryViewGranularityLabel,
  nextGalleryViewGranularity
} from '../album/galleryAlbumTab/GalleryAlbumGranularity';
import {
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_ROW_HEIGHT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from '../common/GalleryTopBarLayout';

@Component
struct MePanel {
  @Prop topSafeInsetVp: number = 0;
  @State private logoutPressed: boolean = false;

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

      Column({ space: 0 }) {
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
        .backgroundEffect(fnImmersiveBackgroundEffect())
        .linearGradient(fnLiquidGlassGradient())
        .borderRadius(24)
        .borderWidth(1)
        .borderColor($r('app.color.immersive_panel_border'))
        .shadow({ radius: 24, color: '#14001A33', offsetX: 0, offsetY: 10 })
        .clip(true)
        .visibility(Visibility.None)

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
        .visibility(Visibility.None)

        Button($r('app.string.logout'), { stateEffect: false })
          .width('100%')
          .height($r('app.float.button_height'))
          .backgroundColor('#E11D48')
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .backgroundEffect(fnImmersiveBackgroundEffect(true, '#33E11D48'))
          .linearGradient(fnLiquidGlassGradient(true, this.logoutPressed))
          .fontColor(Color.White)
          .borderRadius($r('app.float.radius_medium'))
          .border({ width: 1, color: $r('app.color.immersive_panel_border') })
          .visualEffect(fnImmersivePointLightSourceEffect(true, this.logoutPressed))
          .shadow({ radius: 18, color: '#40E11D48', offsetX: 0, offsetY: 8 })
          .clip(true)
          .onTouch((event: TouchEvent): void => {
            const pressed = fnImmersiveTouchPressed(event);
            if (pressed !== undefined) {
              this.logoutPressed = pressed;
            }
          })
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
      .justifyContent(FlexAlign.Start)
      .padding({ left: 24, right: 24, top: 8, bottom: 24 })
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
  @State private gallerySurfaceIndex: number = 0;
  @State private galleryViewGranularity: GalleryViewGranularity = GalleryViewGranularity.DAY;
  @State private albumReloadEpoch: number = 0;
  @State private pageShowSignal: number = 0;
  @State private rootContentWidthVp: number = 360;
  @State private galleryShellTranslateX: number = 0;
  @State private mePanelTranslateX: number = 360;
  @State private galleryShellOpacity: number = 1;
  @State private mePanelOpacity: number = 0;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @State private isDarkTheme: boolean = false;
  @State private systemTopInsetVp: number = 0;
  @State private systemBottomInsetVp: number = 0;
  @State private gallerySelectionDockActive: boolean = false;
  @State private immersivePressedKey: string = '';
  private gallerySelectionDockDownloadAction: () => void = () => {};
  private gallerySelectionDockDeleteAction: () => void = () => {};
  private gallerySelectionDockTimer: number = -1;
  private bottomTabsController: HdsTabsController = new HdsTabsController();

  onBackPress(): boolean {
    if (this.bottomNavIndex !== 2 && galleryTryConsumeAlbumBack()) {
      return true;
    }
    if (this.bottomNavIndex !== 0) {
      this.switchTab(0);
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
    return fnBottomDockBottomGap(this.systemBottomInsetVp);
  }

  private syncImmersivePressed(key: string, event: TouchEvent): void {
    const pressed = fnImmersiveTouchPressed(event);
    if (pressed === undefined) {
      return;
    }
    if (pressed) {
      this.immersivePressedKey = key;
    } else if (this.immersivePressedKey === key) {
      this.immersivePressedKey = '';
    }
  }

  private isImmersivePressed(key: string): boolean {
    return this.immersivePressedKey === key;
  }

  private dockReserveHeight(): number {
    if (!this.sessionOk || !this.shouldShowBottomDock()) {
      return 0;
    }
    return Math.max(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP, FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP) +
      this.bottomDockBottomGap() + 16;
  }

  private shouldShowBottomDock(): boolean {
    return !this.albumSearchModeActive;
  }

  private isGalleryShellVisible(): boolean {
    return this.bottomNavIndex !== 2;
  }

  private currentHomeSurface(): string {
    return this.gallerySurfaceIndex === 1 ? 'albums' : 'photos';
  }

  private rootTabSlideWidthVp(): number {
    return this.rootContentWidthVp > 0 ? this.rootContentWidthVp : 360;
  }

  private syncRootTabTransforms(): void {
    const width = this.rootTabSlideWidthVp();
    if (this.bottomNavIndex === 2) {
      this.galleryShellTranslateX = -width;
      this.mePanelTranslateX = 0;
      this.mePanelOpacity = 1;
      return;
    }
    this.galleryShellTranslateX = 0;
    this.mePanelTranslateX = width;
    this.galleryShellOpacity = 1;
    this.mePanelOpacity = 1;
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

  private dockMaterialBackgroundColor(): ResourceColor {
    return $r('app.color.gallery_material_surface_bg');
  }

  private dockMaterialBorderColor(): ResourceColor {
    return this.isDarkTheme ? '#32FFFFFF' : '#46FFFFFF';
  }

  private dockMaterialShadowColor(): ResourceColor {
    return this.isDarkTheme ? '#52000000' : '#22001A33';
  }

  private syncBottomTabsController(index: number): void {
    try {
      this.bottomTabsController.changeIndex(index);
    } catch (_e) {
    }
  }

  private hdsBottomTabSymbol(icon: Resource, selectedIcon: Resource): TabBarSymbol {
    return {
      normal: new SymbolGlyphModifier(icon)
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
        .fontSize(FN_BOTTOM_DOCK_ICON_SIZE_VP + 5)
        .fontColor([
          $r('sys.color.ohos_id_color_bottom_tab_icon_off'),
          $r('sys.color.ohos_id_color_bottom_tab_icon_auxcolor_off02')
        ]),
      selected: new SymbolGlyphModifier(selectedIcon)
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
        .fontSize(FN_BOTTOM_DOCK_ICON_SIZE_VP + 5)
        .fontColor([
          $r('sys.color.ohos_id_color_activated'),
          $r('sys.color.ohos_id_color_primary_contrary')
        ])
    };
  }

  private hdsBottomTabStyle(icon: Resource, selectedIcon: Resource, label: string): BottomTabBarStyle {
    return new BottomTabBarStyle(this.hdsBottomTabSymbol(icon, selectedIcon), label)
      .labelStyle({
        font: { size: FN_BOTTOM_DOCK_LABEL_SIZE_VP, weight: FontWeight.Medium },
        selectedColor: $r('sys.color.ohos_id_color_bottom_tab_text_on'),
        unselectedColor: $r('sys.color.ohos_id_color_bottom_tab_text_off')
      })
      .iconStyle({
        selectedColor: $r('sys.color.ohos_id_color_activated'),
        unselectedColor: $r('sys.color.ohos_id_color_bottom_tab_icon_off')
      })
      .padding({ left: 0, right: 0, top: 3, bottom: 2 })
      .layoutMode(LayoutMode.VERTICAL)
      .verticalAlign(VerticalAlign.Center)
      .symmetricExtensible(true);
  }

  private shouldShowGalleryDockSideButtons(): boolean {
    return !this.gallerySelectionDockActive && this.isGalleryShellVisible() && this.currentHomeSurface() === 'photos';
  }

  private currentGalleryGranularityLabel(): string {
    return galleryViewGranularityLabel(this.galleryViewGranularity);
  }

  private toggleGalleryViewGranularity(): void {
    this.galleryViewGranularity = nextGalleryViewGranularity(this.galleryViewGranularity);
  }

  private clearGallerySelectionDockTimer(): void {
    if (this.gallerySelectionDockTimer >= 0) {
      clearTimeout(this.gallerySelectionDockTimer);
      this.gallerySelectionDockTimer = -1;
    }
  }

  private onGallerySelectionDockStateChange(
    active: boolean,
    onDownload: () => void,
    onDelete: () => void
  ): void {
    this.gallerySelectionDockDownloadAction = onDownload;
    this.gallerySelectionDockDeleteAction = onDelete;
    this.clearGallerySelectionDockTimer();
    if (!active) {
      this.gallerySelectionDockActive = false;
      return;
    }
    this.gallerySelectionDockTimer = setTimeout((): void => {
      this.gallerySelectionDockTimer = -1;
      this.gallerySelectionDockActive = true;
    }, 180);
  }

  private animateShellToMe(): void {
    const width = this.rootTabSlideWidthVp();
    this.bottomNavIndex = 2;
    this.galleryShellOpacity = 1;
    this.mePanelOpacity = 1;
    this.getUIContext().animateTo(
      { duration: FN_GLOBAL_TAB_SWITCH_DURATION, curve: FN_GLOBAL_TAB_SWITCH_CURVE },
      (): void => {
        this.galleryShellTranslateX = -width;
        this.mePanelTranslateX = 0;
        this.mePanelOpacity = 1;
      }
    );
  }

  private animateShellFromMe(target: number): void {
    const width = this.rootTabSlideWidthVp();
    this.bottomNavIndex = target;
    this.galleryShellTranslateX = -width;
    this.mePanelTranslateX = 0;
    this.galleryShellOpacity = 1;
    this.mePanelOpacity = 1;
    this.getUIContext().animateTo(
      { duration: FN_GLOBAL_TAB_SWITCH_DURATION, curve: FN_GLOBAL_TAB_SWITCH_CURVE },
      (): void => {
        this.galleryShellTranslateX = 0;
        this.mePanelTranslateX = width;
        this.galleryShellOpacity = 1;
        this.mePanelOpacity = 1;
      }
    );
  }

  private switchTab(target: number, fromHdsTabs: boolean = false): void {
    if (target === this.bottomNavIndex) {
      return;
    }
    if (target === 0 || target === 1) {
      this.gallerySurfaceIndex = target;
    }
    const rootSwitch = target === 2 || this.bottomNavIndex === 2;
    if (!rootSwitch) {
      this.bottomNavIndex = target;
      if (!fromHdsTabs) {
        this.syncBottomTabsController(target);
      }
      return;
    }
    if (target === 2) {
      if (this.bottomNavIndex === 0 && this.gallerySurfaceIndex === 0) {
        this.gallerySurfaceIndex = 1;
      }
      this.animateShellToMe();
      if (!fromHdsTabs) {
        this.syncBottomTabsController(target);
      }
      return;
    }
    if (this.bottomNavIndex === 2 && target === 0 && this.gallerySurfaceIndex !== 0) {
      this.gallerySurfaceIndex = 0;
    }
    this.animateShellFromMe(target);
    if (!fromHdsTabs) {
      this.syncBottomTabsController(target);
    }
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
      this.gallerySurfaceIndex = this.bottomNavIndex === 1 ? 1 : 0;
      this.syncRootTabTransforms();
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

  aboutToDisappear(): void {
    this.clearGallerySelectionDockTimer();
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
        .width(15)
        .height(11)
        .borderRadius(4)
        .border({ width: 1.5, color: active ? $r('app.color.brand_primary') : $r('app.color.text_secondary') })
        .translate({ x: 3, y: -3 })
      Column()
        .width(15)
        .height(11)
        .borderRadius(4)
        .border({ width: 1.5, color: active ? $r('app.color.brand_primary') : $r('app.color.text_secondary') })
        .translate({ x: -3, y: 3 })
    }
    .width(22)
    .height(22)
  }

  @Builder
  private floatingDockNavItem(index: number, label: string) {
    Button({ stateEffect: false }) {
      Column({ space: 5 }) {
        if (index === 0) {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(FN_BOTTOM_DOCK_ICON_SIZE_VP)
            .fontColor([this.isDockNavItemSelected(index)
              ? $r('app.color.brand_primary')
              : $r('app.color.text_secondary')])
        } else if (index === 1) {
          this.floatingDockAlbumGlyph(this.isDockNavItemSelected(index))
        } else {
          SymbolGlyph($r('sys.symbol.person'))
            .fontSize(FN_BOTTOM_DOCK_ICON_SIZE_VP)
            .fontColor([this.isDockNavItemSelected(index)
              ? $r('app.color.brand_primary')
              : $r('app.color.text_secondary')])
        }

        Text(label)
          .fontSize(FN_BOTTOM_DOCK_LABEL_SIZE_VP)
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
    .height(FN_BOTTOM_DOCK_ITEM_HEIGHT_VP)
    .borderRadius(FN_BOTTOM_DOCK_ITEM_RADIUS_VP)
    .backgroundColor(this.isDockNavItemSelected(index) ? $r('app.color.gallery_material_surface_bg') : Color.Transparent)
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .backgroundEffect(fnImmersiveBackgroundEffect(this.isDockNavItemSelected(index)))
    .linearGradient(fnLiquidGlassGradient(
      this.isDockNavItemSelected(index),
      this.isImmersivePressed(`dock-nav-${index}`)
    ))
    .border(this.isDockNavItemSelected(index)
      ? { width: 1, color: $r('app.color.immersive_panel_border') }
      : { width: 0, color: Color.Transparent })
    .visualEffect(fnImmersivePointLightSourceEffect(
      this.isDockNavItemSelected(index),
      this.isImmersivePressed(`dock-nav-${index}`)
    ))
    .clip(true)
    .scale({
      x: this.isDockNavItemSelected(index) ? 1 : 0.98,
      y: this.isDockNavItemSelected(index) ? 1 : 0.98
    })
    .onTouch((event: TouchEvent): void => {
      this.syncImmersivePressed(`dock-nav-${index}`, event);
    })
    .onClick((): void => {
      this.switchTab(index);
    })
  }

  @Builder
  private floatingDockHdsTabs() {
    HdsTabs({ controller: this.bottomTabsController, index: this.bottomNavIndex }) {
      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(this.hdsBottomTabStyle(
        $r('sys.symbol.picture'),
        $r('sys.symbol.picture_fill'),
        '图库'
      ))

      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(this.hdsBottomTabStyle(
        $r('sys.symbol.rectangle_stack'),
        $r('sys.symbol.square_stack_3d_fill'),
        '相册'
      ))

      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(this.hdsBottomTabStyle(
        $r('sys.symbol.person'),
        $r('sys.symbol.person_fill'),
        '我的'
      ))
    }
    .width('100%')
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barHeight(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barFloatingStyle({
      barBottomMargin: 0,
      gradientMask: {
        maskColor: Color.Transparent,
        maskHeight: FN_BOTTOM_DOCK_CENTER_HEIGHT_VP
      },
      lightColor: $r('app.color.gallery_material_surface_bg'),
      systemMaterialEffect: fnHdsImmersiveSystemMaterialEffect()
    })
    .scrollable(false)
    .divider({ mode: DividerMode.NONE })
    .barBackgroundColor($r('app.color.gallery_material_surface_bg'))
    .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: FN_BOTTOM_DOCK_CENTER_HEIGHT_VP })
    .blurStrategy(BlurStrategy.ADAPTIVE)
    .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
    .clip(true)
    .onChange((index: number): void => {
      this.switchTab(index, true);
    })
  }

  @Builder
  private floatingDockHdsTabsCapsule() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
        .backgroundColor(this.dockMaterialBackgroundColor())
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect(true))
        .linearGradient(fnLiquidGlassGradient(true))
        .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
        .border({ width: 1, color: this.dockMaterialBorderColor() })
        .clip(true)

      this.floatingDockHdsTabs()
    }
    .layoutWeight(1)
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
    .shadow({ radius: 30, color: this.dockMaterialShadowColor(), offsetX: 0, offsetY: 10 })
    .clip(true)
  }

  @Builder
  private floatingDockSelectionActionItem(
    icon: Resource,
    label: string,
    destructive: boolean,
    action: () => void
  ) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: 5 }) {
        SymbolGlyph(icon)
          .fontSize(FN_BOTTOM_DOCK_ICON_SIZE_VP)
          .fontColor([destructive ? '#E11D48' : $r('app.color.brand_primary')])

        Text(label)
          .fontSize(FN_BOTTOM_DOCK_LABEL_SIZE_VP)
          .fontWeight(FontWeight.Medium)
          .fontColor(destructive ? '#E11D48' : $r('app.color.brand_primary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .height(FN_BOTTOM_DOCK_ITEM_HEIGHT_VP)
    .borderRadius(FN_BOTTOM_DOCK_ITEM_RADIUS_VP)
    .backgroundColor(Color.Transparent)
    .visualEffect(fnImmersivePointLightSourceEffect(false, this.isImmersivePressed(`dock-action-${label}`)))
    .clip(true)
    .onTouch((event: TouchEvent): void => {
      this.syncImmersivePressed(`dock-action-${label}`, event);
    })
    .onClick(action)
  }

  @Builder
  private floatingDockSideButton(isLayoutButton: boolean) {
    Button({ type: ButtonType.Circle, stateEffect: false }) {
      if (isLayoutButton) {
        this.floatingDockGridGlyph()
      } else {
        Text(this.currentGalleryGranularityLabel())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
    }
    .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
    .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
    .borderRadius(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP / 2)
    .backgroundColor(this.dockMaterialBackgroundColor())
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .backgroundEffect(fnImmersiveBackgroundEffect())
    .linearGradient(fnLiquidGlassGradient(false, this.isImmersivePressed(isLayoutButton ? 'dock-side-layout' : 'dock-side-view')))
    .border({ width: 1, color: this.dockMaterialBorderColor() })
    .visualEffect(fnImmersivePointLightSourceEffect(false, this.isImmersivePressed(isLayoutButton ? 'dock-side-layout' : 'dock-side-view')))
    .shadow({ radius: 24, color: this.dockMaterialShadowColor(), offsetX: 0, offsetY: 9 })
    .padding(0)
    .clip(true)
    .onTouch((event: TouchEvent): void => {
      this.syncImmersivePressed(isLayoutButton ? 'dock-side-layout' : 'dock-side-view', event);
    })
    .onClick((): void => {
      if (isLayoutButton) {
        this.toast('\u663e\u793a\u6a21\u5f0f\u5207\u6362\u5165\u53e3\u9884\u7559\u4e2d');
        return;
      }
      this.toggleGalleryViewGranularity();
    })
  }

  @Builder
  private floatingDockNavCapsule() {
    Row({ space: 8 }) {
      this.floatingDockNavItem(0, '\u56fe\u5e93')
      this.floatingDockNavItem(1, '鐩稿唽')
      this.floatingDockNavItem(2, '鎴戠殑')
    }
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .padding({ left: 6, right: 6 })
    .backgroundColor($r('app.color.immersive_tabbar_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .backgroundEffect(fnImmersiveBackgroundEffect(true))
    .linearGradient(fnLiquidGlassGradient(true))
    .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
    .border({ width: 1, color: $r('app.color.immersive_panel_border') })
    .shadow({ radius: 30, color: '#16002B55', offsetX: 0, offsetY: 10 })
    .clip(true)
  }

  @Builder
  private floatingBottomDock() {
    Row({ space: FN_BOTTOM_DOCK_SIDE_GAP_VP }) {
      if (this.shouldShowGalleryDockSideButtons()) {
        this.floatingDockSideButton(true)
      } else {
        Blank()
          .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
          .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
      }

      Row({ space: FN_BOTTOM_DOCK_INNER_SPACE_VP }) {
        this.floatingDockNavItem(0, '\u56fe\u5e93')
        this.floatingDockNavItem(1, '相册')
        this.floatingDockNavItem(2, '我的')
      }
      .layoutWeight(1)
      .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
      .padding({ left: FN_BOTTOM_DOCK_INNER_PADDING_H_VP, right: FN_BOTTOM_DOCK_INNER_PADDING_H_VP })
      .backgroundColor($r('app.color.immersive_tabbar_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .backgroundEffect(fnImmersiveBackgroundEffect(true))
      .linearGradient(fnLiquidGlassGradient(true))
      .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
      .border({ width: 1, color: $r('app.color.immersive_panel_border') })
      .shadow({ radius: 30, color: '#16002B55', offsetX: 0, offsetY: 10 })
      .clip(true)

      if (this.shouldShowGalleryDockSideButtons()) {
        this.floatingDockSideButton(false)
      } else {
        Blank()
          .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
          .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
      }
    }
    .width('100%')
    .padding({ left: FN_BOTTOM_DOCK_SIDE_PADDING_VP, right: FN_BOTTOM_DOCK_SIDE_PADDING_VP })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: this.bottomDockBottomGap() })
  }

  @Builder
  private renderBottomDock() {
    Row({ space: FN_BOTTOM_DOCK_SIDE_GAP_VP }) {
      if (this.shouldShowGalleryDockSideButtons()) {
        this.floatingDockSideButton(true)
      } else {
        Blank()
          .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
          .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
      }

      if (this.gallerySelectionDockActive) {
        Row({ space: FN_BOTTOM_DOCK_INNER_SPACE_VP }) {
          this.floatingDockSelectionActionItem(
            $r('sys.symbol.download'),
            '下载',
            false,
            this.gallerySelectionDockDownloadAction
          )
          this.floatingDockSelectionActionItem(
            $r('sys.symbol.trash'),
            '移入回收站',
            true,
            this.gallerySelectionDockDeleteAction
          )
        }
        .layoutWeight(1)
        .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
        .padding({ left: FN_BOTTOM_DOCK_INNER_PADDING_H_VP, right: FN_BOTTOM_DOCK_INNER_PADDING_H_VP })
        .backgroundColor(this.dockMaterialBackgroundColor())
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect(true))
        .linearGradient(fnLiquidGlassGradient(true))
        .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
        .border({ width: 1, color: this.dockMaterialBorderColor() })
        .shadow({ radius: 30, color: this.dockMaterialShadowColor(), offsetX: 0, offsetY: 10 })
        .clip(true)
      } else {
        this.floatingDockHdsTabsCapsule()
      }

      if (this.shouldShowGalleryDockSideButtons()) {
        this.floatingDockSideButton(false)
      } else {
        Blank()
          .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
          .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
      }
    }
    .width('100%')
    .padding({ left: FN_BOTTOM_DOCK_SIDE_PADDING_VP, right: FN_BOTTOM_DOCK_SIDE_PADDING_VP })
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
          .backgroundEffect(fnImmersiveBackgroundEffect())
          .linearGradient(fnLiquidGlassGradient())
          .borderRadius(28)
          .borderWidth(1)
          .borderColor($r('app.color.immersive_panel_border'))
          .shadow({ radius: 24, color: '#16002B55', offsetX: 0, offsetY: 10 })
          .clip(true)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 20, right: 20 })
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Stack() {
            GalleryAlbumTab({
              baseUrl: this.galleryBaseUrl,
              albumReloadEpoch: this.albumReloadEpoch,
              pageShowSignal: this.pageShowSignal,
              topSafeInsetVp: this.systemTopInsetVp,
              bottomSafeInsetVp: this.systemBottomInsetVp,
              floatingDockInsetBottomVp: this.dockReserveHeight(),
              homeSurface: this.currentHomeSurface(),
              viewGranularity: this.galleryViewGranularity,
              onSearchModeVisibilityChange: (hiddenBottomNav: boolean): void => {
                this.albumSearchModeActive = hiddenBottomNav;
              },
              onSelectionDockStateChange: (active: boolean, onDownload: () => void, onDelete: () => void): void => {
                this.onGallerySelectionDockStateChange(active, onDownload, onDelete);
              }
            })
              .width('100%')
              .height('100%')
              .translate({ x: this.galleryShellTranslateX, y: 0 })
              .opacity(this.galleryShellOpacity)
              .enabled(this.bottomNavIndex !== 2)
              .hitTestBehavior(this.bottomNavIndex !== 2 ? HitTestMode.Default : HitTestMode.None)

            MePanel({ topSafeInsetVp: this.systemTopInsetVp })
              .width('100%')
              .height('100%')
              .padding({ bottom: this.dockReserveHeight() })
              .translate({ x: this.mePanelTranslateX, y: 0 })
              .opacity(this.mePanelOpacity)
              .enabled(this.bottomNavIndex === 2)
              .hitTestBehavior(this.bottomNavIndex === 2 ? HitTestMode.Default : HitTestMode.None)
          }
          .width('100%')
          .layoutWeight(1)
          .onAreaChange((_old, area): void => {
            const width = area.width as number;
            if (width > 0 && Math.abs(width - this.rootContentWidthVp) > 0.5) {
              this.rootContentWidthVp = width;
              this.syncRootTabTransforms();
            }
          })
        }
        .width('100%')
        .height('100%')

        if (this.shouldShowBottomDock()) {
          Column() {
            Blank()
              .layoutWeight(1)
              .hitTestBehavior(HitTestMode.None)
            this.renderBottomDock()
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
