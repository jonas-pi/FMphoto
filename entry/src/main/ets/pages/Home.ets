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
  fnHdsBottomDockActionTabStyle,
  fnHdsImmersiveSystemMaterialEffect,
  fnHdsImmersiveTabsFloatingStyle,
  fnImmersiveBackgroundEffect,
  fnLiquidGlassGradient,
  FnHdsPillButton,
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
  fnCanUseHdsImmersive,
  fnCurrentSdkApiVersion,
  fnDeviceSupportsHdsImmersive,
  fnLoadImmersiveLightPreference,
  fnSaveImmersiveLightPreference,
  FN_HDS_MIN_SDK_API_VERSION,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../common/FnImmersiveSettings';
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

const FN_SELECTION_DOCK_WIDTH_VP: number = 228;
const ME_IMMERSIVE_SWITCH_ROW_HEIGHT_VP: number = 72;
const ME_IMMERSIVE_SWITCH_ROW_RADIUS_VP: number = 22;
const ME_ACTION_GAP_VP: number = 18;

@Component
struct MePanel {
  @Prop topSafeInsetVp: number = 0;
  @StorageLink(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  @State private sdkApiVersion: number = 0;
  @State private immersiveSwitchWidthVp: number = 0;
  private lastImmersiveToggleAt: number = 0;

  private immersiveSupportText(): string {
    if (this.sdkApiVersion <= 0) {
      return `HDS 需要 API${FN_HDS_MIN_SDK_API_VERSION}+`;
    }
    if (fnDeviceSupportsHdsImmersive()) {
      return `当前 API${this.sdkApiVersion}，可实时切换 HDS`;
    }
    return `当前 API${this.sdkApiVersion}，HDS 需要 API${FN_HDS_MIN_SDK_API_VERSION}+`;
  }

  private toggleImmersiveLight(enabled: boolean): void {
    this.immersiveLightEnabled = enabled;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void fnSaveImmersiveLightPreference(ctx, enabled);
  }

  private shouldUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private immersiveSwitchMaterialWidth(): Length {
    return this.immersiveSwitchWidthVp > 1 ? this.immersiveSwitchWidthVp : '100%';
  }

  private triggerImmersiveLightToggle(): void {
    const now = Date.now();
    if (now - this.lastImmersiveToggleAt < 120) {
      return;
    }
    this.lastImmersiveToggleAt = now;
    this.toggleImmersiveLight(!this.immersiveLightEnabled);
  }

  aboutToAppear(): void {
    this.sdkApiVersion = fnCurrentSdkApiVersion();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void fnLoadImmersiveLightPreference(ctx).then((enabled: boolean): void => {
      this.immersiveLightEnabled = enabled;
    });
  }

  @Builder
  private immersiveSwitchTabBarContent() {
    Row()
      .width('100%')
      .height('100%')
  }

  @Builder
  private immersiveSwitchContent() {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text('\u6c89\u6d78\u5149\u611f')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.immersiveSupportText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.immersiveLightEnabled })
        .selectedColor($r('app.color.brand_primary'))
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 16, top: 0, bottom: 0 })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private immersiveSwitchRow() {
    Stack() {
      if (this.shouldUseHds()) {
        HdsTabs({ index: 0 }) {
          TabContent() {
            Column()
              .width('100%')
              .height('100%')
          }
          .tabBar(this.immersiveSwitchTabBarContent)
        }
        .width('100%')
        .height(ME_IMMERSIVE_SWITCH_ROW_HEIGHT_VP)
        .barHeight(ME_IMMERSIVE_SWITCH_ROW_HEIGHT_VP)
        .barOverlap(true)
        .vertical(false)
        .barPosition(BarPosition.End)
        .barWidth(this.immersiveSwitchMaterialWidth())
        // @SuppressWarnings compatibility
        .barFloatingStyle(fnHdsImmersiveTabsFloatingStyle(
          ME_IMMERSIVE_SWITCH_ROW_HEIGHT_VP,
          this.immersiveSwitchMaterialWidth(),
          $r('app.color.gallery_material_surface_bg')
        ))
        .scrollable(false)
        .divider({ mode: DividerMode.NONE })
        .barBackgroundColor(Color.Transparent)
        .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: ME_IMMERSIVE_SWITCH_ROW_HEIGHT_VP })
        .blurStrategy(BlurStrategy.ADAPTIVE)
        .borderRadius(ME_IMMERSIVE_SWITCH_ROW_RADIUS_VP)
        .clip(true)
        .onContentWillChange((_currentIndex: number, _comingIndex: number): boolean => {
          return false;
        })
        .onTabBarClick((_index: number): void => {
          this.triggerImmersiveLightToggle();
        })
      } else {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.card_background'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .linearGradient(fnLiquidGlassGradient())
          .borderRadius(ME_IMMERSIVE_SWITCH_ROW_RADIUS_VP)
          .borderWidth(1)
          .borderColor($r('app.color.immersive_panel_border'))
          .clip(true)
      }

      this.immersiveSwitchContent()
    }
    .width('100%')
    .height(ME_IMMERSIVE_SWITCH_ROW_HEIGHT_VP)
    .onAreaChange((_old: Area, area: Area): void => {
      const width = area.width as number;
      if (width > 1 && Math.abs(width - this.immersiveSwitchWidthVp) > 0.5) {
        this.immersiveSwitchWidthVp = width;
      }
    })
    .onClick((): void => {
      this.triggerImmersiveLightToggle();
    })
  }

  @Builder
  private feedbackBoard() {
    Column({ space: 8 }) {
      Text('帮助 FMphoto 变得更好')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text('请多多在应用市场反馈你需要的功能以及发现的 BUG。如果觉得好用，也欢迎给个好评，助我破鼎。')
        .fontSize(13)
        .lineHeight(20)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
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
  }

  build() {
    Column() {
      Row() {
        Row()
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)

        Text('\u6211\u7684')
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
          Text('FNOS \u4e2a\u4eba\u4e2d\u5fc3')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text('\u9996\u9875\u5df2\u7ecf\u5207\u6362\u4e3a\u7eaf\u539f\u751f\u56fe\u5e93\u58f3\u4f53\uff0c\u8fd9\u91cc\u4fdd\u7559\u8d26\u53f7\u4e0e\u7cfb\u7edf\u5165\u53e3\u3002')
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
          Text('\u5f53\u524d\u72b6\u6001')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('1. \u9996\u9875 Web \u5df2\u5b8c\u5168\u79fb\u9664\u3002')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text('2. \u5e95\u90e8\u4e3b\u5bfc\u822a\u7edf\u4e00\u4e3a\u7167\u7247\u3001\u76f8\u518c\u3001\u6211\u7684\u3002')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text('3. \u56fe\u5e93\u4e3b\u9875\u4f7f\u7528\u60ac\u6d6e\u6807\u9898\u680f\u4e0e\u60ac\u6d6e\u5e95\u90e8\u5bfc\u822a\u3002')
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

        this.feedbackBoard()

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        this.immersiveSwitchRow()

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        FnHdsPillButton({
          text: $r('app.string.logout'),
          widthValue: '100%',
          heightValue: 40,
          fontSizeValue: 16,
          fontColorValue: '#E11D48',
          action: (): void => {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
            void SessionPreferences.clearSession(ctx).then(() => {
              AppSession.clear();
              this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
              });
            });
          }
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
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  private gallerySelectionDockDownloadAction: () => void = () => {};
  private gallerySelectionDockDeleteAction: () => void = () => {};
  private gallerySelectionDockTimer: number = -1;
  private bottomTabsController: HdsTabsController | null = null;

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

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private ensureBottomTabsController(): HdsTabsController {
    if (this.bottomTabsController === null) {
      this.bottomTabsController = new HdsTabsController();
    }
    return this.bottomTabsController;
  }

  private syncBottomTabsController(index: number): void {
    if (this.bottomTabsController === null) {
      return;
    }
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
    this.gallerySelectionDockActive = active;
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
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void fnLoadImmersiveLightPreference(ctx);
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
        const client = AppSession.getClient();
        if (client !== null) {
          setTimeout((): void => {
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
          }, 0);
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
  private floatingDockHdsTabs() {
    HdsTabs({ controller: this.ensureBottomTabsController(), index: this.bottomNavIndex }) {
      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(this.hdsBottomTabStyle(
        $r('sys.symbol.picture'),
        $r('sys.symbol.picture_fill'),
        '\u56fe\u5e93'
      ))

      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(this.hdsBottomTabStyle(
        $r('sys.symbol.rectangle_stack'),
        $r('sys.symbol.square_stack_3d_fill'),
        '\u76f8\u518c'
      ))

      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(this.hdsBottomTabStyle(
        $r('sys.symbol.person'),
        $r('sys.symbol.person_fill'),
        '\u6211\u7684'
      ))
    }
    .width('100%')
    .layoutWeight(1)
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barHeight(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    // @SuppressWarnings compatibility
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
    .barBackgroundColor(Color.Transparent)
    .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: FN_BOTTOM_DOCK_CENTER_HEIGHT_VP })
    .blurStrategy(BlurStrategy.ADAPTIVE)
    .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
    .clip(true)
    .onChange((index: number): void => {
      this.switchTab(index, true);
    })
  }

  @Builder
  private floatingDockFallbackItem(index: number, icon: Resource, selectedIcon: Resource, label: string) {
    Column({ space: 2 }) {
      SymbolGlyph(this.isDockNavItemSelected(index) ? selectedIcon : icon)
        .fontSize(FN_BOTTOM_DOCK_ICON_SIZE_VP + 5)
        .fontColor([this.isDockNavItemSelected(index) ? $r('app.color.brand_primary') : $r('app.color.text_primary')])

      Text(label)
        .fontSize(FN_BOTTOM_DOCK_LABEL_SIZE_VP)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDockNavItemSelected(index) ? $r('app.color.brand_primary') : $r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(FN_BOTTOM_DOCK_ITEM_HEIGHT_VP)
    .borderRadius(FN_BOTTOM_DOCK_ITEM_RADIUS_VP)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      this.switchTab(index);
    })
  }

  @Builder
  private floatingDockFallbackTabs() {
    Row({ space: FN_BOTTOM_DOCK_INNER_SPACE_VP }) {
      this.floatingDockFallbackItem(0, $r('sys.symbol.picture'), $r('sys.symbol.picture_fill'), '\u56fe\u5e93')
      this.floatingDockFallbackItem(1, $r('sys.symbol.rectangle_stack'), $r('sys.symbol.square_stack_3d_fill'), '\u76f8\u518c')
      this.floatingDockFallbackItem(2, $r('sys.symbol.person'), $r('sys.symbol.person_fill'), '\u6211\u7684')
    }
    .width('100%')
    .layoutWeight(1)
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .padding({ left: FN_BOTTOM_DOCK_INNER_PADDING_H_VP, right: FN_BOTTOM_DOCK_INNER_PADDING_H_VP })
    .backgroundColor(this.dockMaterialBackgroundColor())
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(fnLiquidGlassGradient())
    .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
    .borderWidth(1)
    .borderColor(this.dockMaterialBorderColor())
    .shadow({ radius: 20, color: this.dockMaterialShadowColor(), offsetX: 0, offsetY: 8 })
    .clip(true)
  }

  @Builder
  private floatingDockSelectionHdsTabs() {
    HdsTabs({ index: 0 }) {
      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(fnHdsBottomDockActionTabStyle(
        $r('sys.symbol.download'),
        '\u4e0b\u8f7d'
      ))

      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(fnHdsBottomDockActionTabStyle(
        $r('sys.symbol.trash'),
        '\u79fb\u5165\u56de\u6536\u7ad9',
        '#E11D48'
      ))
    }
    .width(FN_SELECTION_DOCK_WIDTH_VP)
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barHeight(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barWidth(FN_SELECTION_DOCK_WIDTH_VP)
    // @SuppressWarnings compatibility
    .barFloatingStyle(fnHdsImmersiveTabsFloatingStyle(
      FN_BOTTOM_DOCK_CENTER_HEIGHT_VP,
      FN_SELECTION_DOCK_WIDTH_VP,
      this.dockMaterialBackgroundColor()
    ))
    .scrollable(false)
    .divider({ mode: DividerMode.NONE })
    .barBackgroundColor(Color.Transparent)
    .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: FN_BOTTOM_DOCK_CENTER_HEIGHT_VP })
    .blurStrategy(BlurStrategy.ADAPTIVE)
    .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
    .clip(true)
    .onContentWillChange((_currentIndex: number, _comingIndex: number): boolean => {
      return false;
    })
    .onTabBarClick((index: number): void => {
      if (index === 0) {
        this.gallerySelectionDockDownloadAction();
        return;
      }
      this.gallerySelectionDockDeleteAction();
    })
  }

  @Builder
  private floatingDockSelectionFallbackAction(index: number, icon: Resource, label: string, color: ResourceColor) {
    Column({ space: 2 }) {
      SymbolGlyph(icon)
        .fontSize(FN_BOTTOM_DOCK_ICON_SIZE_VP + 5)
        .fontColor([color])

      Text(label)
        .fontSize(FN_BOTTOM_DOCK_LABEL_SIZE_VP)
        .fontWeight(FontWeight.Medium)
        .fontColor(color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(FN_BOTTOM_DOCK_ITEM_HEIGHT_VP)
    .borderRadius(FN_BOTTOM_DOCK_ITEM_RADIUS_VP)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      if (index === 0) {
        this.gallerySelectionDockDownloadAction();
        return;
      }
      this.gallerySelectionDockDeleteAction();
    })
  }

  @Builder
  private floatingDockSelectionFallbackTabs() {
    Row({ space: FN_BOTTOM_DOCK_INNER_SPACE_VP }) {
      this.floatingDockSelectionFallbackAction(0, $r('sys.symbol.download'), '\u4e0b\u8f7d', $r('app.color.brand_primary'))
      this.floatingDockSelectionFallbackAction(1, $r('sys.symbol.trash'), '\u79fb\u5165\u56de\u6536\u7ad9', '#E11D48')
    }
    .width(FN_SELECTION_DOCK_WIDTH_VP)
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .padding({ left: FN_BOTTOM_DOCK_INNER_PADDING_H_VP, right: FN_BOTTOM_DOCK_INNER_PADDING_H_VP })
    .backgroundColor(this.dockMaterialBackgroundColor())
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(fnLiquidGlassGradient())
    .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
    .borderWidth(1)
    .borderColor(this.dockMaterialBorderColor())
    .shadow({ radius: 20, color: this.dockMaterialShadowColor(), offsetX: 0, offsetY: 8 })
    .clip(true)
  }

  @Builder
  private floatingDockLayoutSideButtonTabBar() {
    this.floatingDockGridGlyph()
  }

  @Builder
  private floatingDockViewSideButtonTabBar() {
    Text(this.currentGalleryGranularityLabel())
      .fontSize(16)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .textAlign(TextAlign.Center)
      .width('100%')
      .height('100%')
  }

  @Builder
  private floatingDockSideButtonBase(isLayoutButton: boolean) {
    HdsTabs({ index: 0 }) {
      TabContent() {
        Column()
          .width('100%')
          .height('100%')
      }
      .tabBar(isLayoutButton ? this.floatingDockLayoutSideButtonTabBar : this.floatingDockViewSideButtonTabBar)
    }
    .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
    .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
    .barHeight(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barWidth(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
    // @SuppressWarnings compatibility
    .barFloatingStyle(fnHdsImmersiveTabsFloatingStyle(
      FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP,
      FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP,
      $r('app.color.gallery_material_surface_bg')
    ))
    .scrollable(false)
    .divider({ mode: DividerMode.NONE })
    .barBackgroundColor(Color.Transparent)
    .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP })
    .blurStrategy(BlurStrategy.ADAPTIVE)
    .borderRadius(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP / 2)
    .clip(true)
    .onContentWillChange((_currentIndex: number, _comingIndex: number): boolean => {
      return false;
    })
    .onTabBarClick((_index: number): void => {
      if (isLayoutButton) {
        this.toast('\u663e\u793a\u6a21\u5f0f\u5207\u6362\u5165\u53e3\u9884\u7559\u4e2d');
        return;
      }
      this.toggleGalleryViewGranularity();
    })
  }

  @Builder
  private floatingDockSideButton(isLayoutButton: boolean) {
    if (this.canUseHds()) {
      this.floatingDockSideButtonBase(isLayoutButton)
    } else {
      Stack({ alignContent: Alignment.Center }) {
        if (isLayoutButton) {
          this.floatingDockGridGlyph()
        } else {
          Text(this.currentGalleryGranularityLabel())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
        }
      }
      .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
      .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
      .backgroundColor($r('app.color.gallery_material_surface_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .linearGradient(fnLiquidGlassGradient())
      .borderRadius(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP / 2)
      .borderWidth(1)
      .borderColor(this.dockMaterialBorderColor())
      .shadow({ radius: 18, color: this.dockMaterialShadowColor(), offsetX: 0, offsetY: 8 })
      .clip(true)
      .onClick((): void => {
        if (isLayoutButton) {
          this.toast('\u663e\u793a\u6a21\u5f0f\u5207\u6362\u5165\u53e3\u9884\u7559\u4e2d');
          return;
        }
        this.toggleGalleryViewGranularity();
      })
    }
  }

  @Builder
  private floatingDockSideButtonSpacer() {
    Blank()
      .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
      .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
  }

  @Builder
  private renderBottomDock() {
    if (this.gallerySelectionDockActive) {
      Row() {
        if (this.canUseHds()) {
          this.floatingDockSelectionHdsTabs()
        } else {
          this.floatingDockSelectionFallbackTabs()
        }
      }
      .width('100%')
      .padding({ left: FN_BOTTOM_DOCK_SIDE_PADDING_VP, right: FN_BOTTOM_DOCK_SIDE_PADDING_VP })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: this.bottomDockBottomGap() })
    } else {
      Row({ space: FN_BOTTOM_DOCK_SIDE_GAP_VP }) {
        this.floatingDockSideButtonSpacer()

        if (this.canUseHds()) {
          this.floatingDockHdsTabs()
        } else {
          this.floatingDockFallbackTabs()
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

            FnPrimaryButton({
              text: $r('app.string.back_to_login'),
              action: (): void => {
                this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
                });
              }
            })
              .width('100%')
              .margin({ top: 8 })
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
