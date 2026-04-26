import {
  GALLERY_TOP_BAR_BUTTON_FONT_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_SUBTITLE_FONT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from '../../common/GalleryTopBarLayout';
import { FN_UI_FADE_TOGGLE_CURVE, FN_UI_FADE_TOGGLE_DURATION } from '../../common/FnMotion';

const GALLERY_TOP_BAR_FLOATING_MARGIN_TOP_VP: number = 8;
const GALLERY_TOP_BAR_FLOATING_BOTTOM_GAP_VP: number = 6;
const GALLERY_TOP_BAR_CONTROL_RADIUS_VP: number = 22;
const GALLERY_TOP_BAR_ACTION_MIN_WIDTH_VP: number = 72;
const GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP: number = 44;

export const GALLERY_TOP_BAR_FLOATING_TOTAL_HEIGHT_VP: number =
  GALLERY_TOP_BAR_FLOATING_MARGIN_TOP_VP + GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP + GALLERY_TOP_BAR_FLOATING_BOTTOM_GAP_VP;

@Component
export struct GalleryAlbumTopBar {
  @Prop homeSurface: string = 'photos';
  @Prop rootSurfaceTitle: string = '照片';
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
  onOpenSearch: () => void = () => {};
  onStartUpload: () => void = () => {};
  onExitSelection: () => void = () => {};
  onEnterSelection: () => void = () => {};
  onBackToGallery: () => void = () => {};
  onShowMoreMenu: () => void = () => {};

  @State private suppressSearchAutoFocus: boolean = true;
  private searchInputCtrl: TextInputController = new TextInputController();
  private suppressSearchFocusTimer: number = -1;

  private isAlbumsHomeSurface(): boolean {
    return this.homeSurface === 'albums';
  }

  private isRootSurfaceMode(): boolean {
    if (this.inSearchMode || this.inSmartCategoryMode || this.inPersonMode) {
      return false;
    }
    if (this.isAlbumsHomeSurface()) {
      return this.inCategoryMode;
    }
    return !this.inCategoryMode;
  }

  private selectionText(): string {
    return `已选择 ${this.gallerySelectedCount} 项`;
  }

  private secondaryModeTitle(): string {
    if (this.inSmartCategoryMode) {
      return '智能分类';
    }
    if (this.inPersonMode) {
      return '人物';
    }
    if (this.inCategoryMode && !this.isAlbumsHomeSurface()) {
      return '媒体分类';
    }
    return this.rootSurfaceTitle;
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

  @Builder
  private floatingPillButton(text: string, action: () => void) {
    Button(text, { type: ButtonType.Capsule, stateEffect: true })
      .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
      .height(GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP)
      .constraintSize({ minWidth: GALLERY_TOP_BAR_ACTION_MIN_WIDTH_VP })
      .backgroundColor($r('app.color.gallery_material_surface_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .fontColor($r('app.color.button_secondary_fg'))
      .border({ width: 1, color: $r('app.color.immersive_panel_border') })
      .shadow({ radius: 14, color: '#14001A33', offsetX: 0, offsetY: 6 })
      .onClick(action)
  }

  @Builder
  private floatingIconButton(symbol: Resource, action: () => void) {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(symbol)
        .fontSize(18)
        .fontColor([$r('app.color.icon_primary')])
    }
    .width(GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP)
    .height(GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP)
    .borderRadius(GALLERY_TOP_BAR_CONTROL_RADIUS_VP)
    .backgroundColor($r('app.color.gallery_material_surface_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .border({ width: 1, color: $r('app.color.immersive_panel_border') })
    .shadow({ radius: 14, color: '#14001A33', offsetX: 0, offsetY: 6 })
    .padding(0)
    .clip(true)
    .onClick(action)
  }

  build() {
    Row() {
      if (this.gallerySelectionMode && !this.inSearchMode) {
        Text(this.selectionText())
          .layoutWeight(1)
          .fontSize(GALLERY_TOP_BAR_SUBTITLE_FONT_VP)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        this.floatingPillButton('取消', this.onExitSelection)
      } else if (this.inSearchMode) {
        this.floatingPillButton('返回', this.onBackToGallery)

        TextInput({ placeholder: 'AI 搜索照片...', text: this.searchQuery, controller: this.searchInputCtrl })
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP)
          .defaultFocus(false)
          .enableKeyboardOnFocus(false)
          .enabled(!this.suppressSearchAutoFocus)
          .borderRadius(GALLERY_TOP_BAR_CONTROL_RADIUS_VP)
          .backgroundColor($r('app.color.gallery_material_search_bg'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
          .border({ width: 1, color: $r('app.color.gallery_material_surface_border') })
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .caretColor($r('app.color.brand_primary'))
          .placeholderColor($r('app.color.gallery_material_search_placeholder'))
          .padding({ left: 14, right: 14 })
          .onChange(this.onSearchQueryChange)
          .onSubmit(this.onSearchSubmit)

        this.floatingIconButton($r('sys.symbol.magnifyingglass'), this.onSearchSubmit)
      } else if (this.isRootSurfaceMode()) {
        Text(this.rootSurfaceTitle)
          .layoutWeight(1)
          .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 10 }) {
          if (this.isAlbumsHomeSurface()) {
            this.floatingIconButton($r('sys.symbol.plus'), this.onStartUpload)
          } else {
            this.floatingPillButton('多选', this.onEnterSelection)
          }
          this.floatingIconButton($r('sys.symbol.magnifyingglass'), this.onOpenSearch)
          this.floatingIconButton($r('sys.symbol.more'), this.onShowMoreMenu)
        }
      } else {
        this.floatingPillButton('返回', this.onBackToGallery)

        Text(this.secondaryModeTitle())
          .layoutWeight(1)
          .fontSize(GALLERY_TOP_BAR_SUBTITLE_FONT_VP)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        this.floatingIconButton($r('sys.symbol.more'), this.onShowMoreMenu)
      }
    }
    .width('100%')
    .height(GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP)
    .alignItems(VerticalAlign.Center)
    .padding({ left: GALLERY_TOP_BAR_PAD_LEFT_VP, right: GALLERY_TOP_BAR_PAD_RIGHT_VP })
    .margin({
      top: this.topSafeInsetVp + GALLERY_TOP_BAR_FLOATING_MARGIN_TOP_VP,
      bottom: GALLERY_TOP_BAR_FLOATING_BOTTOM_GAP_VP
    })
    .animation({ duration: FN_UI_FADE_TOGGLE_DURATION, curve: FN_UI_FADE_TOGGLE_CURVE })
  }
}
