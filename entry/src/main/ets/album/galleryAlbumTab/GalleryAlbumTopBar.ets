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
import { FN_UI_FADE_TOGGLE_CURVE, FN_UI_FADE_TOGGLE_DURATION } from '../../common/FnMotion';

const GALLERY_TOP_BAR_SHELL_RADIUS_VP: number = 26;
const GALLERY_TOP_BAR_SHELL_MARGIN_H_VP: number = 10;
const GALLERY_TOP_BAR_SHELL_MARGIN_TOP_VP: number = 8;
const GALLERY_TOP_BAR_CONTROL_RADIUS_VP: number = 18;
const GALLERY_TOP_BAR_ACTION_MIN_WIDTH_VP: number = 72;

@Component
export struct GalleryAlbumTopBar {
  @Prop inSearchMode: boolean = false;
  @Prop inCategoryMode: boolean = false;
  @Prop inSmartCategoryMode: boolean = false;
  @Prop inPersonMode: boolean = false;
  @Prop gallerySelectionMode: boolean = false;
  @Prop gallerySelectedCount: number = 0;
  @Prop searchQuery: string = '';
  @Prop topSafeInsetVp: number = 0;
  @Prop @Watch('onPageShowSignal') pageShowSignal: number = 0;

  onSearchQueryChange: (value: string) => void = (_: string) => {};
  onSearchSubmit: () => void = () => {};
  onExitSelection: () => void = () => {};
  onEnterSelection: () => void = () => {};
  onBackToGallery: () => void = () => {};
  @State private suppressSearchAutoFocus: boolean = true;
  private searchInputCtrl: TextInputController = new TextInputController();
  private suppressSearchFocusTimer: number = -1;

  private isMainGalleryMode(): boolean {
    return !this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode;
  }

  private selectionText(): string {
    return `已选择 ${this.gallerySelectedCount} 项`;
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

  private blurSearchInput(): void {
    try {
      this.searchInputCtrl.stopEditing();
    } catch (_e) {
    }
  }

  private clearSuppressSearchFocusTimer(): void {
    if (this.suppressSearchFocusTimer >= 0) {
      clearTimeout(this.suppressSearchFocusTimer);
      this.suppressSearchFocusTimer = -1;
    }
  }

  private suppressSearchRestoreTemporarily(): void {
    this.blurSearchInput();
    this.suppressSearchAutoFocus = true;
    this.clearSuppressSearchFocusTimer();
    this.suppressSearchFocusTimer = setTimeout((): void => {
      this.suppressSearchFocusTimer = -1;
      this.suppressSearchAutoFocus = false;
    }, 180);
  }

  private onPageShowSignal(): void {
    this.suppressSearchRestoreTemporarily();
  }

  aboutToAppear(): void {
    this.suppressSearchRestoreTemporarily();
  }

  aboutToDisappear(): void {
    this.clearSuppressSearchFocusTimer();
  }

  build() {
    Row() {
      if (this.isMainGalleryMode()) {
        Row() {
          Row() {
            Stack({ alignContent: Alignment.Center }) {
              Text('图库')
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .textAlign(TextAlign.Center)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
              Button($r('app.string.gallery_batch_cancel'), { type: ButtonType.Capsule, stateEffect: true })
                .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .constraintSize({ minWidth: GALLERY_TOP_BAR_ACTION_MIN_WIDTH_VP })
                .backgroundColor($r('app.color.button_primary_bg'))
                .fontColor($r('app.color.button_primary_fg'))
                .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
                .shadow({ radius: 12, color: '#16001A33', offsetX: 0, offsetY: 4 })
                .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
                .onClick(this.onExitSelection)
            }
          }
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          .justifyContent(FlexAlign.Start)

          Row({ space: 8 }) {
            Stack({ alignContent: Alignment.Center }) {
              TextInput({ placeholder: 'AI 搜索照片...', text: this.searchQuery, controller: this.searchInputCtrl })
                .width('100%')
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .defaultFocus(false)
                .enableKeyboardOnFocus(false)
                .borderRadius(GALLERY_TOP_BAR_CONTROL_RADIUS_VP)
                .backgroundColor($r('app.color.gallery_material_search_bg'))
                .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .caretColor($r('app.color.brand_primary'))
                .placeholderColor($r('app.color.gallery_material_search_placeholder'))
                .padding({ left: 14, right: 14 })
                .enabled(!this.gallerySelectionMode && !this.suppressSearchAutoFocus)
                .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
                .onChange(this.onSearchQueryChange)
                .onSubmit(this.onSearchSubmit)
              Text(this.selectionText())
                .width('100%')
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .fontSize(GALLERY_TOP_BAR_SUBTITLE_FONT_VP)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
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
              .defaultFocus(false)
              .borderRadius(GALLERY_TOP_BAR_CONTROL_RADIUS_VP)
              .backgroundColor($r('app.color.gallery_material_surface_strong_bg'))
              .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
              .shadow({ radius: 10, color: '#12001A33', offsetX: 0, offsetY: 4 })
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
                .constraintSize({ minWidth: GALLERY_TOP_BAR_ACTION_MIN_WIDTH_VP })
                .backgroundColor($r('app.color.gallery_material_surface_bg'))
                .fontColor($r('app.color.button_secondary_fg'))
                .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
                .shadow({ radius: 12, color: '#12001A33', offsetX: 0, offsetY: 4 })
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
              .constraintSize({ minWidth: GALLERY_TOP_BAR_ACTION_MIN_WIDTH_VP })
              .backgroundColor($r('app.color.gallery_material_surface_bg'))
              .fontColor($r('app.color.button_secondary_fg'))
              .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
              .shadow({ radius: 12, color: '#12001A33', offsetX: 0, offsetY: 4 })
              .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
              .onClick(this.onBackToGallery)
            Button($r('app.string.gallery_batch_cancel'), { type: ButtonType.Capsule, stateEffect: true })
              .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .constraintSize({ minWidth: GALLERY_TOP_BAR_ACTION_MIN_WIDTH_VP })
              .backgroundColor($r('app.color.button_primary_bg'))
              .fontColor($r('app.color.button_primary_fg'))
              .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
              .shadow({ radius: 12, color: '#16001A33', offsetX: 0, offsetY: 4 })
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
              .constraintSize({ minWidth: GALLERY_TOP_BAR_ACTION_MIN_WIDTH_VP })
              .backgroundColor($r('app.color.gallery_material_surface_bg'))
              .fontColor($r('app.color.button_secondary_fg'))
              .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
              .shadow({ radius: 12, color: '#12001A33', offsetX: 0, offsetY: 4 })
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
            .constraintSize({ minWidth: GALLERY_TOP_BAR_ACTION_MIN_WIDTH_VP })
            .backgroundColor($r('app.color.gallery_material_surface_bg'))
            .fontColor($r('app.color.button_secondary_fg'))
            .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
            .shadow({ radius: 12, color: '#12001A33', offsetX: 0, offsetY: 4 })
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
    .backgroundColor($r('app.color.gallery_material_shell_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .borderRadius(GALLERY_TOP_BAR_SHELL_RADIUS_VP)
    .border({ width: 1, color: $r('app.color.gallery_material_shell_border') })
    .shadow({ radius: 18, color: '#14001A33', offsetX: 0, offsetY: 8 })
    .margin({
      left: GALLERY_TOP_BAR_SHELL_MARGIN_H_VP,
      right: GALLERY_TOP_BAR_SHELL_MARGIN_H_VP,
      top: GALLERY_TOP_BAR_SHELL_MARGIN_TOP_VP + this.topSafeInsetVp,
      bottom: 2
    })
    .clip(true)
    .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })
  }
}
