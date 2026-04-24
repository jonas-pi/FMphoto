import {
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_ROW_HEIGHT_VP,
  GALLERY_TOP_BAR_SUBTITLE_FONT_VP
} from '../../common/GalleryTopBarLayout';

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
  @Prop deleting: boolean = false;
  @Prop favoriteToggling: boolean = false;
  @Prop starFilled: boolean = false;
  @Prop favoriteStarTint: ResourceColor = '#FFD60A';

  onBack: () => void = () => {};
  onLoadOriginal: () => void = () => {};
  onOpenDetails: () => void = () => {};
  onShare: () => void = () => {};
  onDownload: () => void = () => {};
  onFavorite: () => void = () => {};
  onDelete: () => void = () => {};
  onBottomBarHeightChange: (height: number) => void = (_: number) => {};

  @Builder
  private bottomAction(icon: Resource, label: string, loading: boolean, action: () => void, dimmed: boolean = false) {
    Column({ space: 4 }) {
      if (loading) {
        LoadingProgress().width(26).height(26).color(this.fgColor)
      } else {
        SymbolGlyph(icon).fontSize(26).fontColor([dimmed ? '#888888' : this.fgColor])
      }
      Text(label).fontSize(11).fontColor(dimmed ? '#888888' : this.fgColor)
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14 })
    .alignItems(HorizontalAlign.Center)
    .onClick((dimmed || !this.toolbarVisible) ? (): void => {} : action)
  }

  @Builder
  private bottomFavoriteAction() {
    Column({ space: 4 }) {
      if (this.favoriteToggling) {
        LoadingProgress().width(26).height(26).color(this.fgColor)
      } else {
        SymbolGlyph(this.starFilled ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
          .fontSize(26)
          .fontColor([this.starFilled ? this.favoriteStarTint : this.fgColor])
      }
      Text('收藏').fontSize(11).fontColor(this.fgColor)
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14 })
    .alignItems(HorizontalAlign.Center)
    .onClick(!this.toolbarVisible ? (): void => {} : this.onFavorite)
  }

  @Builder
  private topCircleAction(icon: Resource, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(icon).fontSize(18).fontColor([this.fgColor])
    }
    .width(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
    .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
    .backgroundColor(this.buttonBg)
    .onClick(action)
  }

  build() {
    Column() {
      Row() {
        Row() {
          this.topCircleAction($r('sys.symbol.chevron_backward'), this.onBack)
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.Start)

        Text(this.titleText)
          .fontSize(GALLERY_TOP_BAR_SUBTITLE_FONT_VP)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.fgColor)
          .layoutWeight(2)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          if (this.showOriginalAction && !this.originalShowing) {
            this.topCircleAction($r('sys.symbol.picture'), this.onLoadOriginal)
          }
          this.topCircleAction($r('sys.symbol.more'), this.onOpenDetails)
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: GALLERY_TOP_BAR_PAD_LEFT_VP,
        right: GALLERY_TOP_BAR_PAD_RIGHT_VP,
        top: GALLERY_TOP_BAR_PAD_TOP_VP,
        bottom: GALLERY_TOP_BAR_PAD_BOTTOM_VP
      })
      .backgroundColor(this.toolbarBg)
      .hitTestBehavior(this.toolbarVisible ? HitTestMode.Default : HitTestMode.None)

      Blank().layoutWeight(1)

      Row() {
        this.bottomAction($r('sys.symbol.share'), '分享', this.sharing, this.onShare)
        this.bottomAction($r('sys.symbol.download'), '下载', this.downloading, this.onDownload)
        this.bottomFavoriteAction()
        this.bottomAction($r('sys.symbol.trash'), '删除', this.deleting, this.onDelete)
      }
      .width('100%')
      .backgroundColor(this.toolbarBg)
      .hitTestBehavior(this.toolbarVisible ? HitTestMode.Default : HitTestMode.None)
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
