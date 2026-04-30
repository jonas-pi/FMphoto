import {
  GALLERY_TOP_BAR_BUTTON_FONT_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_SUBTITLE_FONT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from '../../common/GalleryTopBarLayout';
import { FN_UI_FADE_TOGGLE_CURVE, FN_UI_FADE_TOGGLE_DURATION } from '../../common/FnMotion';
import { BlurStrategy, DividerMode, HdsTabs } from '@kit.UIDesignKit';
import {
  fnHdsImmersiveTabsFloatingStyle,
  fnLiquidGlassGradient,
  FnFloatingTopCircleButton,
  FnFloatingTopPillButton
} from '../../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../../common/FnImmersiveSettings';

const GALLERY_TOP_BAR_FLOATING_MARGIN_TOP_VP: number = 8;
const GALLERY_TOP_BAR_FLOATING_BOTTOM_GAP_VP: number = 6;
const GALLERY_TOP_BAR_CONTROL_RADIUS_VP: number = 20;
const GALLERY_TOP_BAR_ACTION_MIN_WIDTH_VP: number = 62;
const GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP: number = 40;
const GALLERY_TOP_BAR_SEARCH_GAP_VP: number = 10;
const GALLERY_TOP_BAR_SEARCH_ICON_SIZE_VP: number = 15;
const GALLERY_TOP_BAR_SEARCH_TEXT_OFFSET_VP: number = 4;
const GALLERY_TOP_BAR_SEARCH_INPUT_FOCUS_KEY: string = 'gallery_album_top_bar_search_input';

export const GALLERY_TOP_BAR_FLOATING_TOTAL_HEIGHT_VP: number =
  GALLERY_TOP_BAR_FLOATING_MARGIN_TOP_VP + GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP + GALLERY_TOP_BAR_FLOATING_BOTTOM_GAP_VP;

@Component
export struct GalleryAlbumTopBar {
  @Prop homeSurface: string = 'photos';
  @Prop rootSurfaceTitle: string = '图库';
  @Prop @Watch('onSearchModeChanged') inSearchMode: boolean = false;
  @Prop inCategoryMode: boolean = false;
  @Prop inSmartCategoryMode: boolean = false;
  @Prop inPersonMode: boolean = false;
  @Prop gallerySelectionMode: boolean = false;
  @Prop gallerySelectedCount: number = 0;
  @Prop moreMenuExpanded: boolean = false;
  @Prop searchQuery: string = '';
  @Prop topSafeInsetVp: number = 0;
  @Prop @Watch('onPageShowSignal') pageShowSignal: number = 0;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;

  onSearchQueryChange: (value: string) => void = (_: string) => {};
  onSearchSubmit: () => void = () => {};
  onOpenSearch: () => void = () => {};
  onStartUpload: () => void = () => {};
  onExitSelection: () => void = () => {};
  onEnterSelection: () => void = () => {};
  onBackToGallery: () => void = () => {};
  onShowMoreMenu: () => void = () => {};

  @State private suppressSearchAutoFocus: boolean = true;
  @State private searchSubmitted: boolean = false;
  @State private searchFieldWidthVp: number = 0;
  private searchInputCtrl: TextInputController = new TextInputController();
  private suppressSearchFocusTimer: number = -1;
  private searchFocusKickTimer: number = -1;

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

  private clearSearchFocusKickTimer(): void {
    if (this.searchFocusKickTimer >= 0) {
      clearTimeout(this.searchFocusKickTimer);
      this.searchFocusKickTimer = -1;
    }
  }

  private searchHdsWidth(): Length {
    return this.searchFieldWidthVp > 1 ? this.searchFieldWidthVp : '100%';
  }

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private shouldAutoFocusSearchInput(): boolean {
    return this.inSearchMode && !this.suppressSearchAutoFocus && !this.searchSubmitted;
  }

  private onSearchTextChange(value: string): void {
    this.searchSubmitted = false;
    this.onSearchQueryChange(value);
  }

  private suppressSearchRestoreTemporarily(): void {
    this.blurSearchInput();
    this.searchSubmitted = false;
    this.suppressSearchAutoFocus = true;
    this.clearSuppressSearchFocusTimer();
    this.suppressSearchFocusTimer = setTimeout((): void => {
      this.suppressSearchFocusTimer = -1;
      this.suppressSearchAutoFocus = false;
    }, 180);
  }

  private onPageShowSignal(): void {
    if (this.inSearchMode) {
      if (this.searchSubmitted) {
        this.clearSearchFocusKickTimer();
        this.blurSearchInput();
        return;
      }
      this.activateSearchAutoFocus(96);
      return;
    }
    this.suppressSearchRestoreTemporarily();
  }

  private focusSearchInputOnce(): void {
    if (!this.shouldAutoFocusSearchInput()) {
      return;
    }
    this.suppressSearchAutoFocus = false;
    try {
      this.getUIContext().getFocusController().requestFocus(GALLERY_TOP_BAR_SEARCH_INPUT_FOCUS_KEY);
    } catch (_e) {
    }
    try {
      this.searchInputCtrl.caretPosition(this.searchQuery.length);
    } catch (_e) {
    }
  }

  private focusSearchInputSoon(delayMs: number = 48, retryCount: number = 0): void {
    this.clearSearchFocusKickTimer();
    this.searchFocusKickTimer = setTimeout((): void => {
      this.searchFocusKickTimer = -1;
      this.focusSearchInputOnce();
      if (this.shouldAutoFocusSearchInput() && retryCount < 2) {
        this.focusSearchInputSoon(96, retryCount + 1);
      }
    }, delayMs);
  }

  private activateSearchAutoFocus(delayMs: number = 48): void {
    this.searchSubmitted = false;
    this.clearSuppressSearchFocusTimer();
    this.suppressSearchAutoFocus = false;
    this.focusSearchInputSoon(delayMs);
  }

  private onSearchModeChanged(): void {
    if (this.inSearchMode) {
      this.activateSearchAutoFocus(80);
      return;
    }
    this.suppressSearchRestoreTemporarily();
  }

  private openSearchPanelWithAutoFocus(): void {
    this.onOpenSearch();
    this.activateSearchAutoFocus(48);
  }

  private leaveSearchMode(): void {
    this.suppressSearchRestoreTemporarily();
    this.onBackToGallery();
  }

  private submitSearchAndReleaseFocus(): void {
    this.searchSubmitted = true;
    this.clearSearchFocusKickTimer();
    this.blurSearchInput();
    this.onSearchSubmit();
  }

  aboutToAppear(): void {
    if (this.inSearchMode) {
      this.activateSearchAutoFocus(80);
      return;
    }
    this.suppressSearchRestoreTemporarily();
  }

  aboutToDisappear(): void {
    this.clearSuppressSearchFocusTimer();
    this.clearSearchFocusKickTimer();
  }

  @Builder
  private floatingPillButton(text: string, action: () => void) {
    FnFloatingTopPillButton({ text: text, action: action })
  }

  @Builder
  private floatingIconButton(symbol: Resource, action: () => void, active: boolean = false) {
    FnFloatingTopCircleButton({ symbol: symbol, active: active, action: action })
  }

  @Builder
  private searchFieldBlankTabBar() {
    Row()
      .width('100%')
      .height('100%')
  }

  @Builder
  private searchFieldHdsBackground() {
    if (this.canUseHds()) {
      HdsTabs({ index: 0 }) {
        TabContent() {
          Column()
            .width('100%')
            .height('100%')
        }
        .tabBar(this.searchFieldBlankTabBar)
      }
      .width(this.searchHdsWidth())
      .height(GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP)
      .barHeight(GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP)
      .barOverlap(true)
      .vertical(false)
      .barPosition(BarPosition.End)
      .barWidth(this.searchHdsWidth())
      // @SuppressWarnings compatibility
      .barFloatingStyle(fnHdsImmersiveTabsFloatingStyle(
        GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP,
        this.searchHdsWidth(),
        $r('app.color.gallery_material_surface_bg')
      ))
      .scrollable(false)
      .barMode(BarMode.Fixed)
      .divider({ mode: DividerMode.NONE })
      .barBackgroundColor(Color.Transparent)
      .barBackgroundStyle({ maskColor: Color.Transparent, maskHeight: GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP })
      .blurStrategy(BlurStrategy.ADAPTIVE)
      .borderRadius(GALLERY_TOP_BAR_CONTROL_RADIUS_VP)
      .clip(true)
      .hitTestBehavior(HitTestMode.None)
    } else {
      Row()
        .width('100%')
        .height(GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP)
        .backgroundColor($r('app.color.gallery_material_surface_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .linearGradient(fnLiquidGlassGradient())
        .borderRadius(GALLERY_TOP_BAR_CONTROL_RADIUS_VP)
        .borderWidth(1)
        .borderColor($r('app.color.immersive_panel_border'))
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
    }
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
        this.floatingPillButton('返回', (): void => this.leaveSearchMode())

        Stack({ alignContent: Alignment.Center }) {
          this.searchFieldHdsBackground()

          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(GALLERY_TOP_BAR_SEARCH_ICON_SIZE_VP)
              .fontColor([$r('app.color.gallery_material_search_placeholder')])

            TextInput({ placeholder: 'AI 搜索图库...', text: this.searchQuery, controller: this.searchInputCtrl })
              .layoutWeight(1)
              .id(GALLERY_TOP_BAR_SEARCH_INPUT_FOCUS_KEY)
              .height('100%')
              .defaultFocus(this.shouldAutoFocusSearchInput())
              .enableKeyboardOnFocus(true)
              .enabled(!this.suppressSearchAutoFocus)
              .backgroundColor(Color.Transparent)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .caretColor($r('app.color.brand_primary'))
              .placeholderColor($r('app.color.gallery_material_search_placeholder'))
              .padding({ left: GALLERY_TOP_BAR_SEARCH_TEXT_OFFSET_VP, right: 0 })
              .enterKeyType(EnterKeyType.Search)
              .onChange((value: string): void => {
                this.onSearchTextChange(value);
              })
              .onSubmit((): void => {
                this.submitSearchAndReleaseFocus();
              })
              .onAppear((): void => {
                if (this.shouldAutoFocusSearchInput()) {
                  this.focusSearchInputSoon(48);
                }
              })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 12, right: 12 })
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROOT_ICON_SIZE_VP)
        .margin({ left: GALLERY_TOP_BAR_SEARCH_GAP_VP })
        .borderRadius(GALLERY_TOP_BAR_CONTROL_RADIUS_VP)
        .clip(true)
        .onAreaChange((_old: Area, area: Area): void => {
          const width = area.width as number;
          if (width > 1 && Math.abs(width - this.searchFieldWidthVp) > 0.5) {
            this.searchFieldWidthVp = width;
          }
        })
      } else if (this.isRootSurfaceMode()) {
        Text(this.rootSurfaceTitle)
          .layoutWeight(1)
          .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 8 }) {
          if (this.isAlbumsHomeSurface()) {
            this.floatingIconButton($r('sys.symbol.plus'), this.onStartUpload)
          } else {
            this.floatingPillButton('多选', this.onEnterSelection)
          }
          this.floatingIconButton($r('sys.symbol.magnifyingglass'), (): void => this.openSearchPanelWithAutoFocus())
          this.floatingIconButton($r('sys.symbol.more'), this.onShowMoreMenu, this.moreMenuExpanded)
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

        this.floatingIconButton($r('sys.symbol.more'), this.onShowMoreMenu, this.moreMenuExpanded)
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
