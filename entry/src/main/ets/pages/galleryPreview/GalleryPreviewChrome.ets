import {
  fnBottomDockBottomGap,
  fnImmersiveBackgroundEffect,
  fnImmersivePointLightSourceEffect,
  fnImmersiveTouchPressed,
  fnLiquidGlassGradient,
  FN_BOTTOM_DOCK_CENTER_HEIGHT_VP,
  FN_BOTTOM_DOCK_CENTER_RADIUS_VP,
  FN_BOTTOM_DOCK_INNER_PADDING_H_VP,
  FN_BOTTOM_DOCK_INNER_SPACE_VP,
  FN_BOTTOM_DOCK_ITEM_HEIGHT_VP,
  FN_BOTTOM_DOCK_ITEM_RADIUS_VP,
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

const PREVIEW_DOCK_ACTION_GAP_VP: number = 1;
const PREVIEW_DOCK_INNER_PADDING_H_VP: number = FN_BOTTOM_DOCK_INNER_PADDING_H_VP;

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
  @State private pressedKey: string = '';

  private syncPressed(key: string, event: TouchEvent): void {
    const pressed = fnImmersiveTouchPressed(event);
    if (pressed === undefined) {
      return;
    }
    if (pressed) {
      this.pressedKey = key;
    } else if (this.pressedKey === key) {
      this.pressedKey = '';
    }
  }

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

  @Builder
  private bottomAction(icon: Resource, label: string, loading: boolean, action: () => void, dimmed: boolean = false) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: 3 }) {
        if (loading) {
          LoadingProgress().width(22).height(22).color(this.fgColor)
        } else {
          SymbolGlyph(icon).fontSize(22).fontColor([dimmed ? this.dimmedColor() : this.fgColor])
        }
        Text(label).fontSize(10).fontColor(dimmed ? this.dimmedColor() : this.fgColor)
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
    .visualEffect(fnImmersivePointLightSourceEffect(false, this.pressedKey === `bottom-${label}`))
    .clip(true)
    .enabled(!dimmed && this.toolbarVisible)
    .onTouch((event: TouchEvent): void => {
      this.syncPressed(`bottom-${label}`, event);
    })
    .onClick((dimmed || !this.toolbarVisible) ? (): void => {} : action)
  }

  @Builder
  private bottomDownloadAction() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: 3 }) {
        if (this.downloading && this.downloadProgressKnown) {
          Stack({ alignContent: Alignment.Center }) {
            Progress({ value: this.normalizedDownloadProgress(), total: 100, type: ProgressType.Ring })
              .width(22)
              .height(22)
              .color(this.fgColor)
              .style({ strokeWidth: 2.4 })
            Text(`${Math.round(this.normalizedDownloadProgress())}`)
              .fontSize(8)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.fgColor)
          }
          .width(22)
          .height(22)
        } else if (this.downloading) {
          LoadingProgress().width(22).height(22).color(this.fgColor)
        } else {
          SymbolGlyph($r('sys.symbol.download')).fontSize(22).fontColor([this.fgColor])
        }
        Text(this.downloading ? (this.downloadProgressKnown ? `${Math.round(this.normalizedDownloadProgress())}%` : '\u4e0b\u8f7d\u4e2d') : '\u4e0b\u8f7d')
          .fontSize(10)
          .fontColor(this.fgColor)
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
    .visualEffect(fnImmersivePointLightSourceEffect(false, this.pressedKey === 'bottom-download'))
    .clip(true)
    .enabled(this.toolbarVisible && !this.downloading)
    .onTouch((event: TouchEvent): void => {
      this.syncPressed('bottom-download', event);
    })
    .onClick((!this.toolbarVisible || this.downloading) ? (): void => {} : this.onDownload)
  }

  @Builder
  private bottomFavoriteAction() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: 3 }) {
        if (this.favoriteToggling) {
          LoadingProgress().width(22).height(22).color(this.fgColor)
        } else {
          SymbolGlyph(this.starFilled ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
            .fontSize(22)
            .fontColor([this.starFilled ? this.favoriteStarTint : this.fgColor])
        }
        Text('\u6536\u85cf').fontSize(10).fontColor(this.fgColor)
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
    .visualEffect(fnImmersivePointLightSourceEffect(this.starFilled, this.pressedKey === 'bottom-favorite'))
    .clip(true)
    .enabled(this.toolbarVisible)
    .onTouch((event: TouchEvent): void => {
      this.syncPressed('bottom-favorite', event);
    })
    .onClick(!this.toolbarVisible ? (): void => {} : this.onFavorite)
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

        Row({ space: PREVIEW_DOCK_ACTION_GAP_VP }) {
          this.bottomAction($r('sys.symbol.share'), '\u5206\u4eab', this.sharing, this.onShare)
          this.bottomDownloadAction()
          this.bottomFavoriteAction()
          this.bottomAction($r('sys.symbol.trash'), '\u5220\u9664', this.deleting, this.onDelete)
        }
        .layoutWeight(1)
        .height(FN_BOTTOM_DOCK_CENTER_HEIGHT_VP)
        .padding({ left: PREVIEW_DOCK_INNER_PADDING_H_VP, right: PREVIEW_DOCK_INNER_PADDING_H_VP })
        .backgroundColor($r('app.color.immersive_tabbar_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect(true))
        .linearGradient(fnLiquidGlassGradient(true))
        .borderRadius(FN_BOTTOM_DOCK_CENTER_RADIUS_VP)
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })
        .shadow({ radius: 30, color: '#16002B55', offsetX: 0, offsetY: 10 })
        .clip(true)
        .onAreaChange((_old, area): void => {
          const h = area.height as number;
          if (h > 0) {
            this.onBottomBarHeightChange(h);
          }
        })

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
