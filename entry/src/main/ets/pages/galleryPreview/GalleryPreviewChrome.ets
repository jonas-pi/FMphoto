import {
  FN_FLOATING_TOP_BOTTOM_GAP_VP,
  FN_FLOATING_TOP_CONTROL_RADIUS_VP,
  FN_FLOATING_TOP_CONTROL_SIZE_VP,
  FN_FLOATING_TOP_MARGIN_VP,
  FnFloatingTopPillButton
} from '../../common/FnUiCommon';
import {
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_SUBTITLE_FONT_VP
} from '../../common/GalleryTopBarLayout';
import { FN_UI_FADE_TOGGLE_CURVE, FN_UI_FADE_TOGGLE_DURATION } from '../../common/FnMotion';

const PREVIEW_CHROME_BOTTOM_RADIUS_VP: number = 28;
const PREVIEW_CHROME_MARGIN_H_VP: number = 10;
const PREVIEW_CHROME_BOTTOM_MARGIN_VP: number = 8;
const PREVIEW_CHROME_BOTTOM_ACTION_HEIGHT_VP: number = 60;
const PREVIEW_CHROME_BOTTOM_ACTION_RADIUS_VP: number = 18;
const PREVIEW_CHROME_BOTTOM_GAP_VP: number = 6;

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
    return this.darkMaterial ? '#A61A1A1E' : '#D9FFFFFF';
  }

  private bottomShellBackground(): string {
    return this.darkMaterial ? '#B31A1A1E' : '#E6FFFFFF';
  }

  private surfaceBackground(): string {
    return this.darkMaterial ? '#2BFFFFFF' : '#F2FFFFFF';
  }

  private shellBorder(): string {
    return this.darkMaterial ? '#24FFFFFF' : '#14001A33';
  }

  private surfaceBorder(): string {
    return this.darkMaterial ? '#1FFFFFFF' : '#14001A33';
  }

  private shadowColor(): string {
    return this.darkMaterial ? '#24000000' : '#14001A33';
  }

  private dimmedColor(): ResourceColor {
    return this.darkMaterial ? '#80FFFFFF' : '#805B6675';
  }

  private selectedSurfaceBackground(): ResourceColor {
    return $r('app.color.brand_primary');
  }

  private topMargin(): number {
    return FN_FLOATING_TOP_MARGIN_VP + this.topSafeInsetVp;
  }

  private bottomPad(): number {
    return 8 + this.bottomSafeInsetVp;
  }

  private normalizedDownloadProgress(): number {
    return Math.max(0, Math.min(100, this.downloadProgressPct));
  }

  @Builder
  private bottomAction(icon: Resource, label: string, loading: boolean, action: () => void, dimmed: boolean = false) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: 4 }) {
        if (loading) {
          LoadingProgress().width(24).height(24).color(this.fgColor)
        } else {
          SymbolGlyph(icon).fontSize(24).fontColor([dimmed ? this.dimmedColor() : this.fgColor])
        }
        Text(label).fontSize(11).fontColor(dimmed ? this.dimmedColor() : this.fgColor)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .height(PREVIEW_CHROME_BOTTOM_ACTION_HEIGHT_VP)
    .borderRadius(PREVIEW_CHROME_BOTTOM_ACTION_RADIUS_VP)
    .backgroundColor(Color.Transparent)
    .enabled(!dimmed && this.toolbarVisible)
    .onClick((dimmed || !this.toolbarVisible) ? (): void => {} : action)
  }

  @Builder
  private bottomDownloadAction() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: 4 }) {
        if (this.downloading && this.downloadProgressKnown) {
          Stack({ alignContent: Alignment.Center }) {
            Progress({ value: this.normalizedDownloadProgress(), total: 100, type: ProgressType.Ring })
              .width(24)
              .height(24)
              .color(this.fgColor)
              .style({ strokeWidth: 2.4 })
            Text(`${Math.round(this.normalizedDownloadProgress())}`)
              .fontSize(8)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.fgColor)
          }
          .width(24)
          .height(24)
        } else if (this.downloading) {
          LoadingProgress().width(24).height(24).color(this.fgColor)
        } else {
          SymbolGlyph($r('sys.symbol.download')).fontSize(24).fontColor([this.fgColor])
        }
        Text(this.downloading ? (this.downloadProgressKnown ? `${Math.round(this.normalizedDownloadProgress())}%` : '\u4e0b\u8f7d\u4e2d') : '\u4e0b\u8f7d')
          .fontSize(11)
          .fontColor(this.fgColor)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .height(PREVIEW_CHROME_BOTTOM_ACTION_HEIGHT_VP)
    .borderRadius(PREVIEW_CHROME_BOTTOM_ACTION_RADIUS_VP)
    .backgroundColor(Color.Transparent)
    .enabled(this.toolbarVisible && !this.downloading)
    .onClick((!this.toolbarVisible || this.downloading) ? (): void => {} : this.onDownload)
  }

  @Builder
  private bottomFavoriteAction() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Column({ space: 4 }) {
        if (this.favoriteToggling) {
          LoadingProgress().width(24).height(24).color(this.fgColor)
        } else {
          SymbolGlyph(this.starFilled ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
            .fontSize(24)
            .fontColor([this.starFilled ? this.favoriteStarTint : this.fgColor])
        }
        Text('\u6536\u85cf').fontSize(11).fontColor(this.fgColor)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .height(PREVIEW_CHROME_BOTTOM_ACTION_HEIGHT_VP)
    .borderRadius(PREVIEW_CHROME_BOTTOM_ACTION_RADIUS_VP)
    .backgroundColor(Color.Transparent)
    .enabled(this.toolbarVisible)
    .onClick(!this.toolbarVisible ? (): void => {} : this.onFavorite)
  }

  @Builder
  private topCircleAction(icon: Resource, action: () => void, selected: boolean = false) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(icon).fontSize(18).fontColor([selected ? Color.White : this.fgColor])
    }
    .width(FN_FLOATING_TOP_CONTROL_SIZE_VP)
    .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
    .borderRadius(FN_FLOATING_TOP_CONTROL_RADIUS_VP)
    .backgroundColor(selected ? this.selectedSurfaceBackground() : this.surfaceBackground())
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .border({ width: 1, color: this.surfaceBorder() })
    .shadow({ radius: 10, color: this.shadowColor(), offsetX: 0, offsetY: 4 })
    .onClick(action)
  }

  build() {
    Column() {
      Row() {
        Row() {
          FnFloatingTopPillButton({
            text: '返回',
            action: this.onBack
          })
        }
        .layoutWeight(1)
        .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
        .justifyContent(FlexAlign.Start)

        Row() {
          Text(this.titleText)
            .fontSize(GALLERY_TOP_BAR_SUBTITLE_FONT_VP)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.fgColor)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(2)
        .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        Row({ space: 8 }) {
          if (this.showOriginalAction) {
            this.topCircleAction($r('sys.symbol.picture'), this.onLoadOriginal, this.originalShowing)
          }
          this.topCircleAction($r('sys.symbol.more'), this.onOpenDetails)
        }
        .layoutWeight(1)
        .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
      .alignItems(VerticalAlign.Center)
      .padding({ left: GALLERY_TOP_BAR_PAD_LEFT_VP, right: GALLERY_TOP_BAR_PAD_RIGHT_VP })
      .margin({
        top: this.topMargin(),
        bottom: FN_FLOATING_TOP_BOTTOM_GAP_VP
      })
      .hitTestBehavior(this.toolbarVisible ? HitTestMode.Default : HitTestMode.None)
      .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })

      Blank()
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)

      Row({ space: PREVIEW_CHROME_BOTTOM_GAP_VP }) {
        this.bottomAction($r('sys.symbol.share'), '\u5206\u4eab', this.sharing, this.onShare)
        this.bottomDownloadAction()
        this.bottomFavoriteAction()
        this.bottomAction($r('sys.symbol.trash'), '\u5220\u9664', this.deleting, this.onDelete)
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: this.bottomPad() })
      .backgroundColor(this.bottomShellBackground())
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .borderRadius(PREVIEW_CHROME_BOTTOM_RADIUS_VP)
      .border({ width: 1, color: this.shellBorder() })
      .shadow({ radius: 18, color: this.shadowColor(), offsetX: 0, offsetY: 8 })
      .margin({
        left: PREVIEW_CHROME_MARGIN_H_VP,
        right: PREVIEW_CHROME_MARGIN_H_VP,
        bottom: PREVIEW_CHROME_BOTTOM_MARGIN_VP
      })
      .clip(true)
      .hitTestBehavior(this.toolbarVisible ? HitTestMode.Default : HitTestMode.None)
      .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })
      .onAreaChange((_old, area): void => {
        const h = area.height as number;
        if (h > 0) {
          this.onBottomBarHeightChange(h);
        }
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
