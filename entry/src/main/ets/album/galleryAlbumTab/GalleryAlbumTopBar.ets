import {
  GALLERY_TOP_BAR_BUTTON_FONT_VP,
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_ROW_HEIGHT_VP,
  GALLERY_TOP_BAR_SUBTITLE_FONT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from '../../common/GalleryTopBarLayout';

@Component
export struct GalleryAlbumTopBar {
  @Prop inSearchMode: boolean = false;
  @Prop inCategoryMode: boolean = false;
  @Prop inSmartCategoryMode: boolean = false;
  @Prop inPersonMode: boolean = false;
  @Prop gallerySelectionMode: boolean = false;
  @Prop gallerySelectedCount: number = 0;
  @Prop searchQuery: string = '';

  onSearchQueryChange: (value: string) => void = (_: string) => {};
  onSearchSubmit: () => void = () => {};
  onExitSelection: () => void = () => {};
  onEnterSelection: () => void = () => {};
  onBackToGallery: () => void = () => {};

  private isMainGalleryMode(): boolean {
    return !this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode;
  }

  private selectionText(): string {
    return `已选择 ${this.gallerySelectedCount} 张`;
  }

  private secondaryModeTitle(): string {
    if (this.inCategoryMode) {
      return '媒体分类';
    }
    if (this.inSmartCategoryMode) {
      return '智能分类';
    }
    return '人物';
  }

  build() {
    Row() {
      if (this.isMainGalleryMode()) {
        Row() {
          Row() {
            Stack({ alignContent: Alignment.Center }) {
              Text('图库')
                .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .lineHeight(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
              Button($r('app.string.gallery_batch_cancel'), { type: ButtonType.Capsule, stateEffect: true })
                .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .backgroundColor($r('app.color.button_primary_bg'))
                .fontColor($r('app.color.button_primary_fg'))
                .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
                .onClick(this.onExitSelection)
            }
          }
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          .justifyContent(FlexAlign.Start)

          Row({ space: 8 }) {
            Stack({ alignContent: Alignment.Center }) {
              TextInput({ placeholder: 'AI 搜索照片…', text: this.searchQuery })
                .width('100%')
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .borderRadius(18)
                .backgroundColor($r('app.color.card_background'))
                .fontSize(14)
                .placeholderColor($r('app.color.text_secondary'))
                .enabled(!this.gallerySelectionMode)
                .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
                .onChange(this.onSearchQueryChange)
                .onSubmit(this.onSearchSubmit)
              Text(this.selectionText())
                .width('100%')
                .fontSize(GALLERY_TOP_BAR_SUBTITLE_FONT_VP)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .textAlign(TextAlign.Center)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
            }
            .layoutWeight(1)
            .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)

            Stack({ alignContent: Alignment.Center }) {
              Button() {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(17)
                  .fontColor([$r('app.color.icon_primary')])
              }
              .width(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .borderRadius(18)
              .backgroundColor($r('app.color.card_background'))
              .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
              .onClick(this.onSearchSubmit)
              Column()
                .width(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
            }
            .width(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
            .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          }
          .layoutWeight(2)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          .margin({ left: 4, right: 4 })

          Row() {
            Stack({ alignContent: Alignment.Center }) {
              Button($r('app.string.gallery_multiselect'), { type: ButtonType.Capsule, stateEffect: true })
                .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .backgroundColor($r('app.color.button_secondary_bg'))
                .fontColor($r('app.color.button_secondary_fg'))
                .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
                .accessibilityText($r('app.string.gallery_multiselect'))
                .onClick(this.onEnterSelection)
            }
          }
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
      } else if (this.inSearchMode) {
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Button('返回图库', { type: ButtonType.Capsule, stateEffect: true })
              .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .backgroundColor($r('app.color.button_secondary_bg'))
              .fontColor($r('app.color.button_secondary_fg'))
              .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
              .onClick(this.onBackToGallery)
            Button($r('app.string.gallery_batch_cancel'), { type: ButtonType.Capsule, stateEffect: true })
              .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .backgroundColor($r('app.color.button_primary_bg'))
              .fontColor($r('app.color.button_primary_fg'))
              .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
              .onClick(this.onExitSelection)
          }
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.Start)

        Text(this.gallerySelectionMode ? this.selectionText() : 'AI 搜索结果')
          .layoutWeight(2)
          .fontSize(this.gallerySelectionMode ? GALLERY_TOP_BAR_SUBTITLE_FONT_VP : GALLERY_TOP_BAR_TITLE_FONT_VP)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.text_primary'))

        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Button($r('app.string.gallery_multiselect'), { type: ButtonType.Capsule, stateEffect: true })
              .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .backgroundColor($r('app.color.button_secondary_bg'))
              .fontColor($r('app.color.button_secondary_fg'))
              .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
              .accessibilityText($r('app.string.gallery_multiselect'))
              .onClick(this.onEnterSelection)
          }
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.End)
      } else {
        Row()
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)

        Text(this.secondaryModeTitle())
          .layoutWeight(2)
          .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.text_primary'))

        Row() {
          Button('返回图库', { type: ButtonType.Capsule, stateEffect: true })
            .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
            .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
            .backgroundColor($r('app.color.button_secondary_bg'))
            .fontColor($r('app.color.button_secondary_fg'))
            .onClick(this.onBackToGallery)
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.End)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: GALLERY_TOP_BAR_PAD_LEFT_VP,
      right: GALLERY_TOP_BAR_PAD_RIGHT_VP,
      top: GALLERY_TOP_BAR_PAD_TOP_VP,
      bottom: GALLERY_TOP_BAR_PAD_BOTTOM_VP
    })
  }
}

