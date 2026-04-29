import { BlurStrategy, DividerMode, HdsTabs } from '@kit.UIDesignKit';
import {
  fnBottomDockBottomGap,
  fnHdsBottomDockActionTabStyle,
  fnHdsImmersiveSystemMaterialEffect,
  fnImmersiveBackgroundEffect,
  FN_BOTTOM_DOCK_CENTER_HEIGHT_VP,
  FN_BOTTOM_DOCK_CENTER_RADIUS_VP,
  FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP,
  FN_BOTTOM_DOCK_SIDE_GAP_VP,
  FN_BOTTOM_DOCK_SIDE_PADDING_VP,
  FN_FLOATING_TOP_BOTTOM_GAP_VP,
  FN_FLOATING_TOP_CONTROL_RADIUS_VP,
  FN_FLOATING_TOP_CONTROL_SIZE_VP,
  FN_FLOATING_TOP_MARGIN_VP,
  FnFloatingTopCircleButton,
  FnFloatingTopPillButton
} from '../../common/FnUiCommon';
import {
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_SUBTITLE_FONT_VP
} from '../../common/GalleryTopBarLayout';
import { FN_UI_FADE_TOGGLE_CURVE, FN_UI_FADE_TOGGLE_DURATION } from '../../common/FnMotion';

@Component
export struct GalleryPreviewChrome {
  @Prop toolbarVisible: boolean = true;
  @Prop titleText: string = '';
  @Prop toolbarBg: string = '#FF000000';
  @Prop buttonBg: string = '#33000000';
  @Prop fgColor: ResourceColor = Color.White;
  @Prop showOriginalAction: boolean = false;
  @Prop originalShowing: boolean = false;
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

  onBack: () => void = () => {};
  onLoadOriginal: () => void = () => {};
  onOpenDetails: () => void = () => {};
  onShare: () => void = () => {};
  onDownload: () => void = () => {};
  onFavorite: () => void = () => {};
  onDelete: () => void = () => {};
  onBottomBarHeightChange: (height: number) => void = (_: number) => {};

  private shellBackground(): string {
    return '#00000000';
  }

  private shellBorder(): string {
    return this.darkMaterial ? '#24FFFFFF' : '#14001A33';
  }

  private shadowColor(): string {
    return this.darkMaterial ? '#24000000' : '#14001A33';
  }

  private dimmedColor(): ResourceColor {
    return this.darkMaterial ? '#80FFFFFF' : '#805B6675';
  }

  private topMargin(): number {
    return FN_FLOATING_TOP_MARGIN_VP + this.topSafeInsetVp;
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
    .width('100%')
    .layoutWeight(1)
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
  private topCircleAction(icon: Resource, action: () => void, selected: boolean = false) {
    FnFloatingTopCircleButton({
      symbol: icon,
      active: selected,
      action: action
    })
  }

  build() {
    Column() {
      Row() {
        Row() {
          FnFloatingTopPillButton({
            text: '\u8fd4\u56de',
            action: this.onBack
          })
        }
        .layoutWeight(1)
        .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
        .justifyContent(FlexAlign.Start)

        Row() {
          if (this.titleText.length > 0) {
            Row() {
              Text(this.titleText)
                .fontSize(GALLERY_TOP_BAR_SUBTITLE_FONT_VP)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.fgColor)
                .textAlign(TextAlign.Center)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
            .constraintSize({ minWidth: 96, maxWidth: 180 })
            .padding({ left: 16, right: 16 })
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor(this.shellBackground())
            .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
            .backgroundEffect(fnImmersiveBackgroundEffect(true, this.shellBackground()))
            .borderRadius(FN_FLOATING_TOP_CONTROL_RADIUS_VP)
            .border({ width: 1, color: this.shellBorder() })
            .shadow({ radius: 12, color: this.shadowColor(), offsetX: 0, offsetY: 5 })
            .clip(true)
          }
        }
        .layoutWeight(2)
        .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        Row() {
          Row({ space: 8 }) {
            if (this.showOriginalAction) {
              this.topCircleAction($r('sys.symbol.picture'), this.onLoadOriginal, this.originalShowing)
            }
            this.topCircleAction($r('sys.symbol.more'), this.onOpenDetails)
          }
        }
        .layoutWeight(1)
        .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
      .alignItems(VerticalAlign.Center)
      .padding({
        left: GALLERY_TOP_BAR_PAD_LEFT_VP,
        right: GALLERY_TOP_BAR_PAD_RIGHT_VP
      })
      .margin({
        top: this.topMargin(),
        bottom: FN_FLOATING_TOP_BOTTOM_GAP_VP
      })
      .hitTestBehavior(this.toolbarVisible ? HitTestMode.Default : HitTestMode.None)
      .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })

      Blank()
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)

      Row({ space: FN_BOTTOM_DOCK_SIDE_GAP_VP }) {
        Blank()
          .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
          .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)

        this.previewBottomHdsTabs()

        Blank()
          .width(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
          .height(FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP)
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
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
