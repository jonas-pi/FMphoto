import { common } from '@kit.AbilityKit';
import { SymbolGlyphModifier, window } from '@kit.ArkUI';
import { DividerMode, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { retargetGalleryAfterEndpointSwitch } from '../album/GalleryEndpointRetarget';
import { GalleryAlbumTab } from '../album/GalleryAlbumTab';
import { galleryAlbumOpenFolderBrowse } from '../album/galleryAlbumTab/GalleryAlbumRootSurfaceController';
import {
  GalleryAlbumNavigation,
  GALLERY_ALBUM_NAV_DEPTH_KEY,
  GALLERY_ALBUM_ROUTE_CATEGORY,
  GALLERY_ALBUM_ROUTE_FOLDER,
  GALLERY_ALBUM_ROUTE_MAP,
  GALLERY_ALBUM_ROUTE_PERSON,
  GALLERY_ALBUM_ROUTE_RECYCLE,
  GALLERY_ALBUM_ROUTE_SMART
} from '../album/GalleryAlbumNavigation';
import { CategoryGalleryNavigationContent } from './CategoryGallery';
import { FolderBrowsePageNavigationContent } from './FolderBrowsePage';
import { MapPageNavigationContent } from './MapPage';
import { PersonPageNavigationContent } from './PersonPage';
import { RecycleBinPageNavigationContent } from './RecycleBinPage';
import { SmartCategoryPageNavigationContent } from './SmartCategoryPage';
import { MePanel } from './MePanel';
import { galleryTryConsumeAlbumBack } from '../album/GalleryAlbumHardwareBack';
import { AppSession, FN_MEDIA_BASE_URL } from '../auth/AppSession';
import { SessionPreferences } from '../auth/SessionPreferences';
import { proactiveRefreshLongTokenOnForeground } from '../auth/SessionReauth';
import {
  FN_ENDPOINT_SWITCH_VERSION
} from '../network/LoginEndpointAutoSwitch';
import { FnHdsOverlayCapsule } from '../common/FnHdsOverlayCapsule';
import { fnWebViewBaseUrl } from '../network/ServerUrl';
import {
  fnBottomDockBottomGap,
  fnHdsBottomDockActionTabStyle,
  fnHdsDockTabsFloatingStyle,
  fnImmersiveBackgroundEffect,
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
  FN_BOTTOM_DOCK_SIDE_PADDING_VP,
  FN_HDS_CAPSULE_JELLY_VP
} from '../common/FnUiCommon';
import { fnApplyImmersiveSystemBarColors } from '../common/FnSplashTheme';
import {
  FN_SYSTEM_BOTTOM_INSET_VP_KEY,
  FN_SYSTEM_TOP_INSET_VP_KEY,
  fnPublishSystemAvoidArea
} from '../common/FnSystemAvoidArea';
import {
  fnCanUseHdsImmersive,
  fnLoadImmersiveLightPreference,
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
  GALLERY_PREVIEW_HERO_ACTIVE_KEY,
  GALLERY_PREVIEW_SOURCE_HOME_ID
} from '../album/GallerySharedTransition';
import {
  GalleryViewGranularity,
  galleryViewGranularityLabel,
  nextGalleryViewGranularity
} from '../album/galleryAlbumTab/GalleryAlbumGranularity';
import { FN_SHARE_INBOX_VERSION_KEY } from '../album/share/GalleryShareInbox';
import { galleryShareTryConsume } from '../album/share/GalleryShareConsume';
import { FN_TRANSFER_QUEUE_VERSION } from '../common/FnTransferQueueStore';

const FN_SELECTION_DOCK_WIDTH_VP: number = 228;

@Entry
@Component
struct Home {
  @StorageProp(FN_MEDIA_BASE_URL) private galleryBaseUrl: string = '';
  @State private sessionOk: boolean = false;
  /** 非一级页（搜索/相册子页/全屏加载）时隐藏底栏；我的页始终显示。 */
  @State private hideHomeBottomDock: boolean = false;
  @StorageProp(GALLERY_ALBUM_NAV_DEPTH_KEY) private albumNavDepth: number = 0;
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
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(FN_SYSTEM_BOTTOM_INSET_VP_KEY) private systemBottomInsetVp: number = 0;
  @StorageProp(FN_ENDPOINT_SWITCH_VERSION) @Watch('onHomeEndpointSwitchVersionChanged') private endpointSwitchVersion: number = 0;
  @StorageProp(FN_SHARE_INBOX_VERSION_KEY) @Watch('onShareInboxVersionChanged') private shareInboxVersion: number = 0;
  @StorageProp(FN_TRANSFER_QUEUE_VERSION) @Watch('onTransferQueueVersionChanged') private transferQueueVersion: number = 0;
  @State private gallerySelectionDockActive: boolean = false;
  @State private gallerySelectionDockPrivilege: boolean = false;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  @StorageProp(GALLERY_PREVIEW_HERO_ACTIVE_KEY) private previewHeroActive: boolean = false;
  private gallerySelectionDockDownloadAction: () => void = () => {};
  private gallerySelectionDockDeleteAction: () => void = () => {};
  private gallerySelectionDockTimer: number = -1;
  private bottomTabsController: HdsTabsController | null = null;
  private albumNavPathStack: NavPathStack = new NavPathStack();

  onBackPress(): boolean {
    if (GalleryAlbumNavigation.handleBack()) {
      return true;
    }
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
    this.applySystemBarTheme(true);
    this.pageShowSignal++;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.tryConsumeShareInbox();
    void proactiveRefreshLongTokenOnForeground(ctx).then((changed: boolean): void => {
      if (changed) {
        this.albumReloadEpoch++;
      }
    });
  }

  private onShareInboxVersionChanged(): void {
    this.tryConsumeShareInbox();
  }

  private onTransferQueueVersionChanged(): void {
    this.tryConsumeShareInbox();
  }

  private tryConsumeShareInbox(): void {
    void galleryShareTryConsume(this.getUIContext(), (msg: string): void => {
      this.toast(msg);
    });
  }

  private onHomeEndpointSwitchVersionChanged(): void {
    const stored = AppSession.getStored();
    this.sessionOk = stored !== null;
    if (stored !== null) {
      retargetGalleryAfterEndpointSwitch(fnWebViewBaseUrl(stored.baseUrl), stored.token);
    }
  }

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBarTheme(false);
  }

  private applySystemBarTheme(relayout: boolean): void {
    try {
      const dark = this.colorMode === 1;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window): void => {
        if (relayout) {
          win.setWindowLayoutFullScreen(true).catch((_e: Error): void => {});
        }
        fnApplyImmersiveSystemBarColors(win, dark);
        fnPublishSystemAvoidArea(win, this.getUIContext());
      }).catch((_e: Error): void => {});
    } catch (_e) {
    }
  }

  private bottomDockBottomGap(): number {
    return fnBottomDockBottomGap(this.systemBottomInsetVp);
  }

  /** 中栏胶囊宽度：两侧预留圆钮 + 边距后剩余空间，供 barWidth 显式传入 */
  private centerDockWidthVp(): number {
    const total = this.rootContentWidthVp > 0 ? this.rootContentWidthVp : 360;
    return Math.max(
      168,
      total
        - FN_BOTTOM_DOCK_SIDE_PADDING_VP * 2
        - FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP * 2
        - FN_BOTTOM_DOCK_SIDE_GAP_VP * 2
    );
  }

  private dockBarSideMargin(barWidth: number): number {
    const total = this.rootContentWidthVp > 0 ? this.rootContentWidthVp : 360;
    return Math.max(0, (total - barWidth) / 2);
  }

  private dockReserveHeight(): number {
    if (!this.sessionOk || !this.shouldShowBottomDock()) {
      return 0;
    }
    return FN_BOTTOM_DOCK_CENTER_HEIGHT_VP + this.bottomDockBottomGap() + 16;
  }

  private shouldShowBottomDock(): boolean {
    if (this.bottomNavIndex === 2) {
      return true;
    }
    return this.albumNavDepth <= 0 && !this.hideHomeBottomDock;
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

  private openFolderBrowse(): void {
    galleryAlbumOpenFolderBrowse(this.getUIContext(), this.galleryBaseUrl, (msg: string): void => {
      this.toast(msg);
    });
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
    onDelete: () => void,
    privilegeDownload: boolean
  ): void {
    this.gallerySelectionDockDownloadAction = onDownload;
    this.gallerySelectionDockDeleteAction = onDelete;
    this.gallerySelectionDockPrivilege = privilegeDownload;
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
    GalleryAlbumNavigation.attach(this.albumNavPathStack);
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
            });
          }, 0);
        }
      }
    }
    setTimeout((): void => {
      this.tryConsumeShareInbox();
    }, 0);
  }

  aboutToDisappear(): void {
    GalleryAlbumNavigation.detach(this.albumNavPathStack);
    this.clearGallerySelectionDockTimer();
  }

  /** 相册子页统一由 NavDestination 承载，使用系统默认弹簧转场。 */
  @Builder
  private galleryAlbumDestination(name: string, _param: Object | undefined) {
    NavDestination() {
      if (name === GALLERY_ALBUM_ROUTE_CATEGORY) {
        CategoryGalleryNavigationContent()
      } else if (name === GALLERY_ALBUM_ROUTE_PERSON) {
        PersonPageNavigationContent()
      } else if (name === GALLERY_ALBUM_ROUTE_SMART) {
        SmartCategoryPageNavigationContent()
      } else if (name === GALLERY_ALBUM_ROUTE_MAP) {
        MapPageNavigationContent()
      } else if (name === GALLERY_ALBUM_ROUTE_RECYCLE) {
        RecycleBinPageNavigationContent()
      } else if (name === GALLERY_ALBUM_ROUTE_FOLDER) {
        FolderBrowsePageNavigationContent()
      }
    }
    .hideTitleBar(true)
    .onBackPressed((): boolean => {
      return GalleryAlbumNavigation.handleBack();
    })
  }

  @Builder
  private floatingDockHdsTabs() {
    HdsTabs({ controller: this.ensureBottomTabsController(), index: this.bottomNavIndex }) {
      TabContent() {
        Column()
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
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
          .hitTestBehavior(HitTestMode.None)
      }
      .tabBar(this.hdsBottomTabStyle(
        $r('sys.symbol.rectangle_on_rectangle'),
        $r('sys.symbol.rectangle_on_rectangle_fill'),
        '\u76f8\u518c'
      ))

      TabContent() {
        Column()
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
      }
      .tabBar(this.hdsBottomTabStyle(
        $r('sys.symbol.person'),
        $r('sys.symbol.person_fill'),
        '\u6211\u7684'
      ))
    }
    .width('100%')
    .height('100%')
    .barHeight(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barWidth(this.centerDockWidthVp())
    // @SuppressWarnings compatibility
    .barFloatingStyle(fnHdsDockTabsFloatingStyle(
      this.centerDockWidthVp(),
      this.bottomDockBottomGap(),
      this.dockBarSideMargin(this.centerDockWidthVp())
    ))
    .scrollable(false)
    .divider({ mode: DividerMode.NONE })
    .backgroundColor(Color.Transparent)
    .barBackgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.Transparent)
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
      this.floatingDockFallbackItem(1, $r('sys.symbol.rectangle_on_rectangle'), $r('sys.symbol.rectangle_on_rectangle_fill'), '\u76f8\u518c')
      this.floatingDockFallbackItem(2, $r('sys.symbol.person'), $r('sys.symbol.person_fill'), '\u6211\u7684')
    }
    .width(this.centerDockWidthVp())
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
          .hitTestBehavior(HitTestMode.None)
      }
      .tabBar(fnHdsBottomDockActionTabStyle(
        $r('sys.symbol.download'),
        '\u4e0b\u8f7d'
      ))

      TabContent() {
        Column()
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
      }
      .tabBar(fnHdsBottomDockActionTabStyle(
        $r('sys.symbol.trash'),
        '\u79fb\u5165\u56de\u6536\u7ad9',
        '#E11D48'
      ))
    }
    .width('100%')
    .height('100%')
    .barHeight(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barWidth(FN_SELECTION_DOCK_WIDTH_VP)
    // @SuppressWarnings compatibility
    .barFloatingStyle(fnHdsDockTabsFloatingStyle(
      FN_SELECTION_DOCK_WIDTH_VP,
      this.bottomDockBottomGap(),
      this.dockBarSideMargin(FN_SELECTION_DOCK_WIDTH_VP)
    ))
    .scrollable(false)
    .divider({ mode: DividerMode.NONE })
    .backgroundColor(Color.Transparent)
    .barBackgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.Transparent)
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
  private floatingDockGranularityOverlay() {
    Column() {
      Blank()
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)
      Row({ space: FN_BOTTOM_DOCK_SIDE_GAP_VP }) {
        FnHdsOverlayCapsule({
          barWidth: FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP,
          barHeight: FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP,
          useSymbol: true,
          symbol: $r('sys.symbol.folder'),
          fontSizeValue: 22,
          fontColorValue: $r('app.color.text_primary'),
          onBarClick: (): void => {
            this.openFolderBrowse();
          }
        })
        .margin({
          left: -FN_HDS_CAPSULE_JELLY_VP,
          right: -FN_HDS_CAPSULE_JELLY_VP
        })

        Blank()
          .width(this.centerDockWidthVp())
          .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
          .hitTestBehavior(HitTestMode.None)

        FnHdsOverlayCapsule({
          barWidth: FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP,
          barHeight: FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP,
          text: this.currentGalleryGranularityLabel(),
          fontSizeValue: 16,
          fontColorValue: $r('app.color.text_primary'),
          onBarClick: (): void => {
            this.toggleGalleryViewGranularity();
          }
        })
        .margin({
          left: -FN_HDS_CAPSULE_JELLY_VP,
          right: -FN_HDS_CAPSULE_JELLY_VP
        })
      }
      .width('100%')
      .padding({ left: FN_BOTTOM_DOCK_SIDE_PADDING_VP, right: FN_BOTTOM_DOCK_SIDE_PADDING_VP })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .clip(false)
      .margin({ bottom: this.bottomDockBottomGap() - FN_HDS_CAPSULE_JELLY_VP })
    }
    .width('100%')
    .height('100%')
    .clip(false)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private floatingDockFolderButtonFallback() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(22)
        .fontColor([$r('app.color.text_primary')])
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
      this.openFolderBrowse();
    })
  }

  @Builder
  private floatingDockSideButtonFallback() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.currentGalleryGranularityLabel())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
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
      this.toggleGalleryViewGranularity();
    })
  }

  @Builder
  private renderBottomDock() {
    if (this.canUseHds()) {
      Stack() {
        if (this.gallerySelectionDockActive) {
          this.floatingDockSelectionHdsTabs()
        } else {
          this.floatingDockHdsTabs()
        }
        if (this.shouldShowGalleryDockSideButtons()) {
          this.floatingDockGranularityOverlay()
        }
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    } else if (this.gallerySelectionDockActive) {
      Column() {
        Blank()
          .layoutWeight(1)
          .hitTestBehavior(HitTestMode.None)
        Row() {
          this.floatingDockSelectionFallbackTabs()
        }
        .width('100%')
        .padding({ left: FN_BOTTOM_DOCK_SIDE_PADDING_VP, right: FN_BOTTOM_DOCK_SIDE_PADDING_VP })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: this.bottomDockBottomGap() })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    } else {
      Column() {
        Blank()
          .layoutWeight(1)
          .hitTestBehavior(HitTestMode.None)
        Row({ space: FN_BOTTOM_DOCK_SIDE_GAP_VP }) {
          if (this.shouldShowGalleryDockSideButtons()) {
            this.floatingDockFolderButtonFallback()
          } else {
            Blank()
              .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
              .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
          }

          this.floatingDockFallbackTabs()

          if (this.shouldShowGalleryDockSideButtons()) {
            this.floatingDockSideButtonFallback()
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
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
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
            Navigation(this.albumNavPathStack) {
              GalleryAlbumTab({
                baseUrl: this.galleryBaseUrl,
                albumReloadEpoch: this.albumReloadEpoch,
                pageShowSignal: this.pageShowSignal,
                topSafeInsetVp: this.systemTopInsetVp,
                bottomSafeInsetVp: this.systemBottomInsetVp,
                floatingDockInsetBottomVp: this.dockReserveHeight(),
                homeSurface: this.currentHomeSurface(),
                viewGranularity: this.galleryViewGranularity,
                onViewGranularityChange: (mode: GalleryViewGranularity): void => {
                  this.galleryViewGranularity = mode;
                },
                onSearchModeVisibilityChange: (hiddenBottomNav: boolean): void => {
                  this.hideHomeBottomDock = hiddenBottomNav;
                },
                onSelectionDockStateChange: (active: boolean, onDownload: () => void, onDelete: () => void,
                  privilegeDownload: boolean): void => {
                  this.onGallerySelectionDockStateChange(active, onDownload, onDelete, privilegeDownload);
                }
              })
                .width('100%')
                .height('100%')
            }
            .width('100%')
            .height('100%')
            .mode(NavigationMode.Stack)
            // hideNavBar 会隐藏根内容并造成图库/相册白屏；这里只隐藏 Navigation 自带标题栏。
            .hideTitleBar(true)
            .navDestination(this.galleryAlbumDestination)
            .translate({ x: this.galleryShellTranslateX, y: 0 })
            .opacity(this.galleryShellOpacity)
            .enabled(this.bottomNavIndex !== 2)
            .hitTestBehavior(this.bottomNavIndex !== 2 ? HitTestMode.Default : HitTestMode.None)

            MePanel({
              topSafeInsetVp: this.systemTopInsetVp,
              pageShowSignal: this.pageShowSignal,
              onEndpointSwitched: (): void => {
                const stored = AppSession.getStored();
                this.sessionOk = stored !== null;
                if (stored !== null) {
                  retargetGalleryAfterEndpointSwitch(fnWebViewBaseUrl(stored.baseUrl), stored.token);
                }
              }
            })
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
          this.renderBottomDock()
        }
      }
    }
    .width('100%')
    .height('100%')
    .id(GALLERY_PREVIEW_SOURCE_HOME_ID)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    if (this.previewHeroActive) {
      // 源页保持不透明并固定在预览页后方；预览遮罩与共享图片同步淡入。
      // 不在共享图片到位后再次淡出整页，否则会短暂露出 Navigation 底色。
      PageTransitionEnter({ type: RouteType.None, duration: 0 })
      PageTransitionExit({ type: RouteType.None, duration: 0 })
    } else {
      PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
        .opacity(0)
        .translate({ x: 12, y: 0 });
      PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
        .opacity(0)
        .translate({ x: -8, y: 0 });
    }
  }
}
