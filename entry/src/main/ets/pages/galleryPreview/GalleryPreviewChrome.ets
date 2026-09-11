import { SymbolGlyphModifier } from '@kit.ArkUI';
import { fnHdsBindMenuOptions } from '../../common/FnHdsOverlay';
import {
  BlurStrategy,
  DividerMode,
  HdsNavigation,
  HdsNavigationBackButtonItemOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleBarStyle,
  HdsNavigationTitleMode,
  HdsTabs,
  IconStyleMode,
  ScrollEffectOptions,
  ScrollEffectType,
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import {
  fnBottomDockBottomGap,
  fnHdsBottomDockActionTabStyle,
  fnHdsChromeButtonBackgroundColor,
  fnHdsChromeButtonFallbackBackgroundColor,
  fnHdsImmersiveSystemMaterialEffect,
  fnHdsDockTabsFloatingStyle,
  fnHdsNavChromeBackgroundStyle,
  fnHdsNavTitleBarPadding,
  fnLiquidGlassGradient,
  FN_BOTTOM_DOCK_CENTER_HEIGHT_VP,
  FN_BOTTOM_DOCK_CENTER_RADIUS_VP,
  FN_BOTTOM_DOCK_ICON_SIZE_VP,
  FN_BOTTOM_DOCK_INNER_PADDING_H_VP,
  FN_BOTTOM_DOCK_INNER_SPACE_VP,
  FN_BOTTOM_DOCK_ITEM_HEIGHT_VP,
  FN_BOTTOM_DOCK_ITEM_RADIUS_VP,
  FN_BOTTOM_DOCK_LABEL_SIZE_VP,
  FN_BOTTOM_DOCK_SIDE_PADDING_VP,
  FN_FLOATING_TOP_CONTROL_SIZE_VP,
  FN_HDS_NAV_CHROME_HEIGHT_VP
} from '../../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../../common/FnImmersiveSettings';
import { FN_UI_FADE_TOGGLE_CURVE, FN_UI_FADE_TOGGLE_DURATION } from '../../common/FnMotion';
import { galleryPreviewToolbarAlpha } from './GalleryPreviewDetailsLogic';
import { GALLERY_PREVIEW_DETAILS_COVER_KEY, GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY } from './GalleryPreviewToolbarStore';
import { playGalleryLongPressMenuHaptic } from '../../album/GallerySelectionHaptic';
import {
  addGalleryPreviewDetailsFitListener,
  addGalleryPreviewDismissListener,
  GalleryPreviewOpacityUpdater,
  getGalleryPreviewDetailsSheetHeight,
  getGalleryPreviewDismissProgress,
  removeGalleryPreviewDetailsFitListener,
  removeGalleryPreviewDismissListener
} from '../../album/GalleryPreviewVerticalGesture';
import {
  GALLERY_PREVIEW_VIDEO_ACTIVE_KEY,
  GALLERY_PREVIEW_VIDEO_DOCK_EXPANDED_KEY,
  GALLERY_PREVIEW_VIDEO_MUTED_KEY,
  GALLERY_PREVIEW_VIDEO_PLAYING_KEY,
  requestGalleryPreviewVideoToggleMute,
  requestGalleryPreviewVideoTogglePlay
} from './GalleryPreviewVideoStore';

const GALLERY_PREVIEW_BOTTOM_DOCK_WIDTH_VP: number = 268;
const GALLERY_PREVIEW_VIDEO_PLAYING_DOCK_WIDTH_VP: number = 372;
const GALLERY_PREVIEW_TOP_MENU_SLOT_VP: number = 64;

@Component
export struct GalleryPreviewChrome {
  /** 自己订阅显隐，父页切换工具栏时不会整页重绘 Swiper */
  @StorageProp(GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY) @Watch('onChromeFadeInputsChanged')
  private toolbarVisible: boolean = true;
  @StorageProp(GALLERY_PREVIEW_DETAILS_COVER_KEY) @Watch('onChromeFadeInputsChanged')
  private detailsCover: boolean = false;
  @StorageProp(GALLERY_PREVIEW_VIDEO_ACTIVE_KEY) private videoActive: boolean = false;
  @StorageProp(GALLERY_PREVIEW_VIDEO_DOCK_EXPANDED_KEY) private videoDockExpanded: boolean = false;
  @StorageProp(GALLERY_PREVIEW_VIDEO_PLAYING_KEY) private videoPlaying: boolean = false;
  @StorageProp(GALLERY_PREVIEW_VIDEO_MUTED_KEY) private videoMuted: boolean = false;
  @Prop titleText: string = '';
  @Prop toolbarBg: string = '#FF000000';
  @Prop buttonBg: string = '#33000000';
  @Prop fgColor: ResourceColor = Color.White;
  @Prop showOriginalAction: boolean = false;
  @Prop showSearchSimilarAction: boolean = false;
  @Prop moreMenuExpanded: boolean = false;
  @Prop originalShowing: boolean = false;
  @Prop originalLocked: boolean = false;
  @Prop sharing: boolean = false;
  @Prop downloading: boolean = false;
  @Prop downloadProgressPct: number = 0;
  @Prop downloadProgressKnown: boolean = false;
  @Prop deleting: boolean = false;
  @Prop favoriteToggling: boolean = false;
  @Prop starFilled: boolean = false;
  @Prop favoriteStarTint: ResourceColor = '#FFD60A';
  @Prop darkMaterial: boolean = false;
  @Prop topSafeInsetVp: number = 0;
  @Prop bottomSafeInsetVp: number = 0;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  /** 详情高度是模块变量，不进响应式树；跨过阈值时才写 @State，用来卸掉仍会吃点击的 HdsTabs。 */
  @State private detailsSheetOpen: boolean = false;

  onBack: () => void = () => {};
  onLoadOriginal: () => void = () => {};
  onLockOriginal: () => void = () => {};
  onOpenDetails: () => void = () => {};
  onToggleMoreMenu: () => void = () => {};
  onDismissMoreMenu: () => void = () => {};
  onSearchSimilar: () => void = () => {};
  onShare: () => void = () => {};
  onDownload: () => void = () => {};
  onFavorite: () => void = () => {};
  onDelete: () => void = () => {};
  onBottomBarHeightChange: (height: number) => void = (_: number) => {};
  private chromeOpacityUpdater: GalleryPreviewOpacityUpdater = new GalleryPreviewOpacityUpdater();
  private skipOriginalClick: boolean = false;
  private lastOriginalToggleAt: number = 0;
  private readonly onDismissProgress = (_progress: number): void => {
    this.syncChromeOpacity();
  };
  private readonly onDetailsProgress = (): void => {
    this.syncChromeOpacity();
    this.syncDetailsSheetOpen();
  };

  aboutToAppear(): void {
    addGalleryPreviewDismissListener(this.onDismissProgress);
    addGalleryPreviewDetailsFitListener(this.onDetailsProgress);
    this.syncDetailsSheetOpen();
    this.syncChromeOpacity();
    this.notifyBottomDockHeight();
  }

  aboutToDisappear(): void {
    removeGalleryPreviewDismissListener(this.onDismissProgress);
    removeGalleryPreviewDetailsFitListener(this.onDetailsProgress);
  }

  onChromeFadeInputsChanged(): void {
    this.syncChromeOpacity();
  }

  private dimmedColor(): ResourceColor {
    return this.darkMaterial ? '#80FFFFFF' : '#805B6675';
  }

  private syncDetailsSheetOpen(): void {
    const open: boolean = getGalleryPreviewDetailsSheetHeight() >= 4;
    if (open !== this.detailsSheetOpen) {
      this.detailsSheetOpen = open;
    }
  }

  private chromeInteractive(): boolean {
    return this.toolbarVisible && !this.detailsCover && !this.detailsSheetOpen;
  }

  private chromeOpacity(): number {
    if (!this.toolbarVisible || this.detailsCover) {
      return 0;
    }
    const detailsAlpha = 1 - Math.max(0, Math.min(1, getGalleryPreviewDetailsSheetHeight() / 72));
    return galleryPreviewToolbarAlpha(getGalleryPreviewDismissProgress()) * detailsAlpha;
  }

  private syncChromeOpacity(): void {
    this.chromeOpacityUpdater.apply(this.chromeOpacity());
  }

  private normalizedDownloadProgress(): number {
    return Math.max(0, Math.min(100, this.downloadProgressPct));
  }

  private previewDownloadLabel(): ResourceStr {
    if (!this.downloading) {
      return '\u4e0b\u8f7d';
    }
    if (this.downloadProgressKnown) {
      return `${Math.round(this.normalizedDownloadProgress())}%`;
    }
    return '\u4e0b\u8f7d\u4e2d';
  }

  private previewActionColor(busy: boolean = false, color?: ResourceColor): ResourceColor {
    return busy ? this.dimmedColor() : (color ?? this.fgColor);
  }

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private previewTitleBarOptions(): HdsNavigationTitleBarOptions {
    const material = this.canUseHds() ? fnHdsImmersiveSystemMaterialEffect() : undefined;
    if (material !== undefined) {
      return {
        padding: fnHdsNavTitleBarPadding(),
        avoidLayoutSafeArea: false,
        enableComponentSafeArea: false,
        style: {
          blurStrategy: BlurStrategy.ADAPTIVE,
          scrollEffectOpts: this.overlayScrollEffectOpts(),
          systemMaterialEffect: material,
          originalStyle: this.topTitleBarOriginalStyle(),
          scrollEffectStyle: {
            backgroundStyle: fnHdsNavChromeBackgroundStyle()
          }
        },
        content: this.topTitleBarContent()
      };
    }
    return {
      padding: fnHdsNavTitleBarPadding(),
      avoidLayoutSafeArea: false,
      enableComponentSafeArea: false,
      style: {
        blurStrategy: BlurStrategy.ADAPTIVE,
        scrollEffectOpts: this.overlayScrollEffectOpts(),
        originalStyle: this.topTitleBarOriginalStyle(),
        scrollEffectStyle: {
          backgroundStyle: fnHdsNavChromeBackgroundStyle()
        }
      },
      content: this.topTitleBarContent()
    };
  }

  private topMenuItem(content: HdsNavigationIconOptions): HdsNavigationMenuItemOptions {
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
  }

  private originalActivated(): boolean {
    return this.originalLocked || this.originalShowing;
  }

  /** 单项图标走 SymbolGlyphModifier，避免 menuStyle.iconColor 整组盖色，也避免叠第二层。 */
  private originalMenuGlyph(): SymbolGlyphModifier {
    if (this.originalActivated()) {
      return new SymbolGlyphModifier($r('sys.symbol.picture_fill'))
        .fontSize(24)
        .fontColor([$r('app.color.brand_primary')]);
    }
    return new SymbolGlyphModifier($r('sys.symbol.picture'))
      .fontSize(24)
      .fontColor([this.fgColor]);
  }

  private originalHitRight(): number {
    // 更多在最右，原图在它左侧一格。
    return GALLERY_PREVIEW_TOP_MENU_SLOT_VP;
  }

  private originalHitTop(): number {
    return (FN_HDS_NAV_CHROME_HEIGHT_VP - FN_FLOATING_TOP_CONTROL_SIZE_VP) / 2;
  }

  @Builder
  private previewMoreMenuBuilder() {
    Menu() {
      if (this.showSearchSimilarAction) {
        MenuItem({ content: '搜索相似照片' })
          .onClick((): void => {
            this.onSearchSimilar();
          })
      }
      MenuItem({ content: '查看详情' })
        .onClick((): void => {
          this.onOpenDetails();
        })
    }
  }

  private onOriginalMenuClick(): void {
    if (this.skipOriginalClick) {
      this.skipOriginalClick = false;
      return;
    }
    const now = Date.now();
    if (now - this.lastOriginalToggleAt < 200) {
      return;
    }
    this.lastOriginalToggleAt = now;
    this.onLoadOriginal();
  }

  private buildTopMenuItems(): HdsNavigationMenuItemOptions[] {
    const items: HdsNavigationMenuItemOptions[] = [];
    if (this.showOriginalAction) {
      const originalContent: HdsNavigationIconOptions = {
        label: '原图',
        icon: this.originalMenuGlyph(),
        type: IconStyleMode.NORMAL,
        isEnabled: this.toolbarVisible,
        action: (): void => {
          this.onOriginalMenuClick();
        }
      };
      items.push(this.topMenuItem(originalContent));
    }
    const moreContent: HdsNavigationIconOptions = {
      label: '更多',
      icon: new SymbolGlyphModifier($r('sys.symbol.dot_grid_2x2'))
        .fontSize(24)
        .fontColor([this.fgColor]),
      type: IconStyleMode.NORMAL,
      isEnabled: this.toolbarVisible,
      action: (): void => {
        this.onToggleMoreMenu();
      }
    };
    items.push(this.topMenuItem(moreContent));
    return items;
  }

  private topBackIconOptions(): HdsNavigationBackButtonItemOptions {
    const backIcon: HdsNavigationBackButtonItemOptions = {
      label: '返回',
      isEnabled: this.toolbarVisible,
      action: (): void => {
        this.onBack();
      }
    };
    return backIcon;
  }

  private overlayButtonBg(): ResourceColor {
    // 官方：图标背板透明，由 titleBar.systemMaterialEffect 出圆形模糊材质；
    // 无沉浸光感时退回浅灰玻璃底，避免按钮融进照片。
    return this.canUseHds() ? fnHdsChromeButtonBackgroundColor() : fnHdsChromeButtonFallbackBackgroundColor();
  }

  /**
   * 全屏预览顶栏：不要列表页的沉浸渐变模糊。
   * 官方大图预览是透明底 + 圆形图标背板；IMMERSIVE_GRADIENT_BLUR 会在照片上方画出一层渐变阴影。
   */
  private overlayScrollEffectOpts(): ScrollEffectOptions {
    return {
      enableScrollEffect: false,
      scrollEffectType: ScrollEffectType.COMMON_BLUR
    };
  }

  private topTitleBarOriginalStyle(): HdsNavigationTitleBarStyle {
    const chipBg: ResourceColor = this.overlayButtonBg();
    return {
      backgroundStyle: fnHdsNavChromeBackgroundStyle(),
      contentStyle: {
        titleStyle: {
          mainTitleColor: this.fgColor,
          subTitleColor: this.fgColor,
          // 关掉标题投影：透明顶栏时默认灰投影会看成一条阴影
          mainTitleShadowColor: Color.Transparent,
          subTitleShadowColor: Color.Transparent
        },
        // 官方悬浮按钮：menu / back 各自一块圆形背板，不是整条顶栏
        menuStyle: {
          backgroundColor: chipBg,
          textColor: this.fgColor
        },
        backIconStyle: {
          backgroundColor: chipBg,
          iconColor: this.fgColor
        },
        dividerStyle: {
          dividerColor: Color.Transparent
        }
      }
    };
  }

  private topTitleBarContent(): TitleBarContentOptions {
    return {
      title: { mainTitle: this.titleText },
      menu: { value: this.buildTopMenuItems() },
      backIcon: this.topBackIconOptions()
    };
  }

  @Builder
  private topNavigationContent() {
    Column()
      .width('100%')
      .height(0)
  }

  @Builder
  private previewTopBar() {
    HdsNavigation() {
      this.topNavigationContent()
    }
    .width('100%')
    .height(FN_HDS_NAV_CHROME_HEIGHT_VP)
    // 顶栏壳固定单栏，避免宽屏 Auto 触发空右栏
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .titleBar(this.previewTitleBarOptions())
  }

  private showVideoPlayingDock(): boolean {
    return this.videoActive && this.videoDockExpanded;
  }

  private dockWidth(): number {
    return this.showVideoPlayingDock() ? GALLERY_PREVIEW_VIDEO_PLAYING_DOCK_WIDTH_VP :
      GALLERY_PREVIEW_BOTTOM_DOCK_WIDTH_VP;
  }

  private notifyBottomDockHeight(): void {
    this.onBottomBarHeightChange(
      FN_BOTTOM_DOCK_CENTER_HEIGHT_VP + fnBottomDockBottomGap(this.bottomSafeInsetVp)
    );
  }

  private onDockShare(): void {
    if (!this.sharing) {
      this.onShare();
    }
  }

  private onDockDownload(): void {
    if (!this.downloading) {
      this.onDownload();
    }
  }

  private onDockFavorite(): void {
    if (!this.favoriteToggling) {
      this.onFavorite();
    }
  }

  private onDockDelete(): void {
    if (!this.deleting) {
      this.onDelete();
    }
  }

  private onPreviewHdsAction(index: number): void {
    if (!this.chromeInteractive()) {
      return;
    }
    if (this.showVideoPlayingDock()) {
      if (index === 0) {
        this.onDockShare();
        return;
      }
      if (index === 1) {
        this.onDockDownload();
        return;
      }
      if (index === 2) {
        requestGalleryPreviewVideoTogglePlay();
        return;
      }
      if (index === 3) {
        requestGalleryPreviewVideoToggleMute();
        return;
      }
      if (index === 4) {
        this.onDockFavorite();
        return;
      }
      this.onDockDelete();
      return;
    }
    if (index === 0) {
      this.onDockShare();
      return;
    }
    if (index === 1) {
      this.onDockDownload();
      return;
    }
    if (index === 2) {
      this.onDockFavorite();
      return;
    }
    this.onDockDelete();
  }

  @Builder
  private previewBottomHdsTabs() {
    HdsTabs({ index: 0 }) {
      TabContent() {
        Column()
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
      }
      .tabBar(fnHdsBottomDockActionTabStyle(
        $r('sys.symbol.share'),
        this.sharing ? '\u5206\u4eab\u4e2d' : '\u5206\u4eab',
        this.previewActionColor(this.sharing)
      ))

      TabContent() {
        Column()
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
      }
      .tabBar(fnHdsBottomDockActionTabStyle(
        $r('sys.symbol.download'),
        this.previewDownloadLabel(),
        this.previewActionColor(this.downloading)
      ))

      if (this.showVideoPlayingDock()) {
        TabContent() {
          Column()
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.None)
        }
        .tabBar(fnHdsBottomDockActionTabStyle(
          this.videoPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
          this.videoPlaying ? '\u6682\u505c' : '\u64ad\u653e',
          this.fgColor
        ))

        TabContent() {
          Column()
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.None)
        }
        .tabBar(fnHdsBottomDockActionTabStyle(
          this.videoMuted ? $r('sys.symbol.speaker_slash_fill') : $r('sys.symbol.speaker_wave_2_fill'),
          this.videoMuted ? '\u6062\u590d' : '\u9759\u97f3',
          this.fgColor
        ))
      }

      TabContent() {
        Column()
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
      }
      .tabBar(fnHdsBottomDockActionTabStyle(
        this.starFilled ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'),
        '\u6536\u85cf',
        this.previewActionColor(this.favoriteToggling, this.starFilled ? this.favoriteStarTint : this.fgColor)
      ))

      TabContent() {
        Column()
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
      }
      .tabBar(fnHdsBottomDockActionTabStyle(
        $r('sys.symbol.trash'),
        this.deleting ? '\u5220\u9664\u4e2d' : '\u5220\u9664',
        this.previewActionColor(this.deleting)
      ))
    }
    .width('100%')
    .height('100%')
    .barHeight(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barWidth(this.dockWidth())
    // @SuppressWarnings compatibility
    .barFloatingStyle(fnHdsDockTabsFloatingStyle(
      this.dockWidth(),
      fnBottomDockBottomGap(this.bottomSafeInsetVp)
    ))
    .scrollable(false)
    .divider({ mode: DividerMode.NONE })
    .backgroundColor(Color.Transparent)
    .barBackgroundColor(Color.Transparent)
    .hitTestBehavior(this.chromeInteractive() ? HitTestMode.Transparent : HitTestMode.None)
    .onContentWillChange((_currentIndex: number, _comingIndex: number): boolean => {
      return false;
    })
    .onTabBarClick((index: number): void => {
      this.onPreviewHdsAction(index);
    })
  }

  @Builder
  private previewBottomFallbackAction(index: number, icon: Resource, label: ResourceStr, color: ResourceColor) {
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
      this.onPreviewHdsAction(index);
    })
  }

  @Builder
  private previewBottomFallbackTabs() {
    Row({ space: FN_BOTTOM_DOCK_INNER_SPACE_VP }) {
      this.previewBottomFallbackAction(
        0,
        $r('sys.symbol.share'),
        this.sharing ? '\u5206\u4eab\u4e2d' : '\u5206\u4eab',
        this.previewActionColor(this.sharing)
      )
      this.previewBottomFallbackAction(
        1,
        $r('sys.symbol.download'),
        this.previewDownloadLabel(),
        this.previewActionColor(this.downloading)
      )
      if (this.showVideoPlayingDock()) {
        this.previewBottomFallbackAction(
          2,
          this.videoPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'),
          this.videoPlaying ? '\u6682\u505c' : '\u64ad\u653e',
          this.fgColor
        )
        this.previewBottomFallbackAction(
          3,
          this.videoMuted ? $r('sys.symbol.speaker_slash_fill') : $r('sys.symbol.speaker_wave_2_fill'),
          this.videoMuted ? '\u6062\u590d' : '\u9759\u97f3',
          this.fgColor
        )
        this.previewBottomFallbackAction(
          4,
          this.starFilled ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'),
          '\u6536\u85cf',
          this.previewActionColor(this.favoriteToggling, this.starFilled ? this.favoriteStarTint : this.fgColor)
        )
        this.previewBottomFallbackAction(
          5,
          $r('sys.symbol.trash'),
          this.deleting ? '\u5220\u9664\u4e2d' : '\u5220\u9664',
          this.previewActionColor(this.deleting)
        )
      } else {
        this.previewBottomFallbackAction(
          2,
          this.starFilled ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'),
          '\u6536\u85cf',
          this.previewActionColor(this.favoriteToggling, this.starFilled ? this.favoriteStarTint : this.fgColor)
        )
        this.previewBottomFallbackAction(
          3,
          $r('sys.symbol.trash'),
          this.deleting ? '\u5220\u9664\u4e2d' : '\u5220\u9664',
          this.previewActionColor(this.deleting)
        )
      }
    }
    .width(this.dockWidth())
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .padding({ left: FN_BOTTOM_DOCK_INNER_PADDING_H_VP, right: FN_BOTTOM_DOCK_INNER_PADDING_H_VP })
    .backgroundColor($r('app.color.gallery_material_surface_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(fnLiquidGlassGradient())
    .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
    .shadow({ radius: 18, color: '#28000000', offsetX: 0, offsetY: 8 })
    .clip(true)
    .onAreaChange((_old, area): void => {
      const h = area.height as number;
      if (h > 0) {
        this.onBottomBarHeightChange(h);
      }
    })
  }

  build() {
    Stack() {
      Stack({ alignContent: Alignment.Top }) {
        Column() {
          this.previewTopBar()
        }
        .width('100%')
        .padding({ top: this.topSafeInsetVp })
        .hitTestBehavior(this.chromeInteractive() ? HitTestMode.Default : HitTestMode.None)

        if (this.showOriginalAction) {
          Stack({ alignContent: Alignment.TopEnd }) {
            Row()
              .width(FN_FLOATING_TOP_CONTROL_SIZE_VP)
              .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
              .margin({
                top: this.topSafeInsetVp + this.originalHitTop(),
                right: this.originalHitRight()
              })
              .hitTestBehavior(this.chromeInteractive() ? HitTestMode.Default : HitTestMode.None)
              .onClick((): void => {
                this.onOriginalMenuClick();
              })
              .gesture(
                LongPressGesture({ repeat: false })
                  .onAction((): void => {
                    this.skipOriginalClick = true;
                    playGalleryLongPressMenuHaptic();
                    this.onLockOriginal();
                  })
              )
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
        }

        Stack({ alignContent: Alignment.TopEnd }) {
            Row()
              .width(FN_FLOATING_TOP_CONTROL_SIZE_VP)
              .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
              .margin({
                top: this.topSafeInsetVp + this.originalHitTop(),
                right: $r('app.float.hds_title_bar_padding_horizontal')
              })
              .hitTestBehavior(HitTestMode.None)
              .bindMenu(this.moreMenuExpanded, this.previewMoreMenuBuilder, fnHdsBindMenuOptions(
                Placement.BottomLeft,
                (): void => {
                  this.onDismissMoreMenu();
                }
              ))
          }
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })

      Stack({ alignContent: Alignment.Bottom }) {
        // HdsTabs 浮层栏在 HitTestMode.None / 透明时仍会吃点击，详情展开时直接不挂载。
        if (this.chromeInteractive()) {
          if (this.canUseHds()) {
            this.previewBottomHdsTabs()
          } else {
            Row() {
              this.previewBottomFallbackTabs()
            }
            .width('100%')
            .padding({ left: FN_BOTTOM_DOCK_SIDE_PADDING_VP, right: FN_BOTTOM_DOCK_SIDE_PADDING_VP })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: fnBottomDockBottomGap(this.bottomSafeInsetVp) })
            .hitTestBehavior(HitTestMode.Default)
          }
        }
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(this.chromeInteractive() ? HitTestMode.Transparent : HitTestMode.None)
      .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .attributeModifier(this.chromeOpacityUpdater)
  }
}
