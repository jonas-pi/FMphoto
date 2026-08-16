import { LengthMetrics } from '@kit.ArkUI';
import {
  BlurStrategy,
  DividerMode,
  HdsNavigation,
  HdsNavigationBackButtonItemOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
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
  fnHdsImmersiveTabsFloatingStyle,
  fnHdsNavChromeBackgroundStyle,
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
  FN_HDS_NAV_CHROME_HEIGHT_VP
} from '../../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../../common/FnImmersiveSettings';
import { FN_UI_FADE_TOGGLE_CURVE, FN_UI_FADE_TOGGLE_DURATION } from '../../common/FnMotion';
import { galleryPreviewToolbarAlpha } from './GalleryPreviewDetailsLogic';
import { GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY } from './GalleryPreviewToolbarStore';
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

@Component
export struct GalleryPreviewChrome {
  /** 自己订阅显隐，父页切换工具栏时不会整页重绘 Swiper */
  @StorageProp(GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY) private toolbarVisible: boolean = true;
  @StorageProp(GALLERY_PREVIEW_VIDEO_ACTIVE_KEY) private videoActive: boolean = false;
  @StorageProp(GALLERY_PREVIEW_VIDEO_DOCK_EXPANDED_KEY) private videoDockExpanded: boolean = false;
  @StorageProp(GALLERY_PREVIEW_VIDEO_PLAYING_KEY) private videoPlaying: boolean = false;
  @StorageProp(GALLERY_PREVIEW_VIDEO_MUTED_KEY) private videoMuted: boolean = false;
  @Prop dismissDragProgress: number = 0;
  @Prop titleText: string = '';
  @Prop toolbarBg: string = '#FF000000';
  @Prop buttonBg: string = '#33000000';
  @Prop fgColor: ResourceColor = Color.White;
  @Prop showOriginalAction: boolean = false;
  @Prop originalShowing: boolean = false;
  @Prop detailsShowing: boolean = false;
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

  onBack: () => void = () => {};
  onLoadOriginal: () => void = () => {};
  onOpenDetails: () => void = () => {};
  onShare: () => void = () => {};
  onDownload: () => void = () => {};
  onFavorite: () => void = () => {};
  onDelete: () => void = () => {};
  onBottomBarHeightChange: (height: number) => void = (_: number) => {};

  private dimmedColor(): ResourceColor {
    return this.darkMaterial ? '#80FFFFFF' : '#805B6675';
  }

  private chromeOpacity(): number {
    if (!this.toolbarVisible) {
      return 0;
    }
    return galleryPreviewToolbarAlpha(this.dismissDragProgress);
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

  private topMenuItem(content: HdsNavigationIconOptions): HdsNavigationMenuItemOptions {
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
  }

  private buildTopMenuItems(): HdsNavigationMenuItemOptions[] {
    const items: HdsNavigationMenuItemOptions[] = [];
    if (this.showOriginalAction) {
      const originalContent: HdsNavigationIconOptions = {
        label: '原图',
        icon: $r('sys.symbol.picture'),
        type: IconStyleMode.NORMAL,
        isEnabled: this.toolbarVisible,
        action: (): void => {
          this.onLoadOriginal();
        }
      };
      items.push(this.topMenuItem(originalContent));
    }
    const detailsContent: HdsNavigationIconOptions = {
      label: '详情',
      icon: $r('sys.symbol.info_circle'),
      type: IconStyleMode.NORMAL,
      isEnabled: this.toolbarVisible,
      action: (): void => {
        this.onOpenDetails();
      }
    };
    items.push(this.topMenuItem(detailsContent));
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
          iconColor: this.fgColor,
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
    .titleBar(this.canUseHds() ? {
      padding: { start: LengthMetrics.vp(8), end: LengthMetrics.vp(8) },
      avoidLayoutSafeArea: false,
      enableComponentSafeArea: false,
      style: {
        blurStrategy: BlurStrategy.ADAPTIVE,
        scrollEffectOpts: this.overlayScrollEffectOpts(),
        // 材质只作用在返回/菜单圆钮上；顶栏背板仍透明（blurRadius 0）
        systemMaterialEffect: fnHdsImmersiveSystemMaterialEffect(),
        originalStyle: this.topTitleBarOriginalStyle(),
        scrollEffectStyle: {
          backgroundStyle: fnHdsNavChromeBackgroundStyle()
        }
      },
      content: this.topTitleBarContent()
    } : {
      padding: { start: LengthMetrics.vp(8), end: LengthMetrics.vp(8) },
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
    })
  }

  private showVideoPlayingDock(): boolean {
    return this.videoActive && this.videoDockExpanded;
  }

  private dockWidth(): number {
    return this.showVideoPlayingDock() ? GALLERY_PREVIEW_VIDEO_PLAYING_DOCK_WIDTH_VP :
      GALLERY_PREVIEW_BOTTOM_DOCK_WIDTH_VP;
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
    if (!this.toolbarVisible) {
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
      }
      .tabBar(fnHdsBottomDockActionTabStyle(
        $r('sys.symbol.trash'),
        this.deleting ? '\u5220\u9664\u4e2d' : '\u5220\u9664',
        this.previewActionColor(this.deleting)
      ))
    }
    .width(this.dockWidth())
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barHeight(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barWidth(this.dockWidth())
    // @SuppressWarnings compatibility
    .barFloatingStyle(fnHdsImmersiveTabsFloatingStyle(
      FN_BOTTOM_DOCK_CENTER_HEIGHT_VP,
      this.dockWidth(),
      $r('app.color.gallery_material_surface_bg')
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
      this.onPreviewHdsAction(index);
    })
    .onAreaChange((_old, area): void => {
      const h = area.height as number;
      if (h > 0) {
        this.onBottomBarHeightChange(h);
      }
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
        .hitTestBehavior(this.toolbarVisible ? HitTestMode.Default : HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })

      Stack({ alignContent: Alignment.Bottom }) {
        Row() {
          if (this.canUseHds()) {
            this.previewBottomHdsTabs()
          } else {
            this.previewBottomFallbackTabs()
          }
        }
        .width('100%')
        .padding({ left: FN_BOTTOM_DOCK_SIDE_PADDING_VP, right: FN_BOTTOM_DOCK_SIDE_PADDING_VP })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: fnBottomDockBottomGap(this.bottomSafeInsetVp) })
        .hitTestBehavior(this.toolbarVisible ? HitTestMode.Default : HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .opacity(this.chromeOpacity())
    .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })
  }
}
