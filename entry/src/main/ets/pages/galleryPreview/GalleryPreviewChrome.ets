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
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import {
  fnBottomDockBottomGap,
  fnHdsBottomDockActionTabStyle,
  fnHdsImmersiveSystemMaterialEffect,
  fnHdsImmersiveTabsFloatingStyle,
  fnHdsNavChromeBackgroundStyle,
  fnHdsNavChromeScrollEffectOpts,
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

const GALLERY_PREVIEW_BOTTOM_DOCK_WIDTH_VP: number = 268;

@Component
export struct GalleryPreviewChrome {
  /** 自己订阅显隐，父页切换工具栏时不会整页重绘 Swiper */
  @StorageProp(GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY) private toolbarVisible: boolean = true;
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

  private topTitleBarOriginalStyle(): HdsNavigationTitleBarStyle {
    return {
      backgroundStyle: fnHdsNavChromeBackgroundStyle(),
      contentStyle: {
        titleStyle: {
          mainTitleColor: this.fgColor,
          subTitleColor: this.fgColor
        },
        menuStyle: {
          backgroundColor: this.buttonBg,
          iconColor: this.fgColor,
          textColor: this.fgColor
        },
        backIconStyle: {
          backgroundColor: this.buttonBg,
          iconColor: this.fgColor
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
        scrollEffectOpts: fnHdsNavChromeScrollEffectOpts(),
        // @SuppressWarnings compatibility
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
        scrollEffectOpts: fnHdsNavChromeScrollEffectOpts(),
        originalStyle: this.topTitleBarOriginalStyle(),
        scrollEffectStyle: {
          backgroundStyle: fnHdsNavChromeBackgroundStyle()
        }
      },
      content: this.topTitleBarContent()
    })
  }

  private onPreviewHdsAction(index: number): void {
    if (!this.toolbarVisible) {
      return;
    }
    if (index === 0) {
      if (!this.sharing) {
        this.onShare();
      }
      return;
    }
    if (index === 1) {
      if (!this.downloading) {
        this.onDownload();
      }
      return;
    }
    if (index === 2) {
      if (!this.favoriteToggling) {
        this.onFavorite();
      }
      return;
    }
    if (!this.deleting) {
      this.onDelete();
    }
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
    .width(GALLERY_PREVIEW_BOTTOM_DOCK_WIDTH_VP)
    .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barHeight(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barWidth(GALLERY_PREVIEW_BOTTOM_DOCK_WIDTH_VP)
    // @SuppressWarnings compatibility
    .barFloatingStyle(fnHdsImmersiveTabsFloatingStyle(
      FN_BOTTOM_DOCK_CENTER_HEIGHT_VP,
      GALLERY_PREVIEW_BOTTOM_DOCK_WIDTH_VP,
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
    .width(GALLERY_PREVIEW_BOTTOM_DOCK_WIDTH_VP)
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
    Column() {
      Column() {
        this.previewTopBar()
      }
      .width('100%')
      .padding({ top: this.topSafeInsetVp })
      .hitTestBehavior(this.toolbarVisible ? HitTestMode.Default : HitTestMode.None)
      .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })

      Blank()
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)

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
      .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.toolbarVisible ? HitTestMode.Transparent : HitTestMode.None)
    .opacity(this.chromeOpacity())
    .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })
  }
}
