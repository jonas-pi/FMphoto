/**
 * 图库顶栏：对齐官方 HdsNavigation.titleBar + systemMaterialEffect。
 * 搜索 / 更多 / 多选走 titleBar.menu / backIcon，由系统处理命中与沉浸光感。
 */
import { LengthMetrics } from '@kit.ArkUI';
import {
  BlurStrategy,
  HdsNavigation,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleMode,
  IconStyleMode,
  ScrollEffectType,
  TextStyleMode
} from '@kit.UIDesignKit';
import {
  fnHdsImmersiveSystemMaterialEffect,
  fnLiquidGlassGradient
} from '../../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../../common/FnImmersiveSettings';

/** 官方 MINI 标题栏内容区高度 */
export const GALLERY_TOP_BAR_MINI_HEIGHT_VP: number = 56;
/** 搜索模式下 bottomBuilder 高度 */
export const GALLERY_TOP_BAR_SEARCH_FIELD_HEIGHT_VP: number = 44;
/** 非搜索态顶栏占位（不含状态栏安全区） */
export const GALLERY_TOP_BAR_FLOATING_TOTAL_HEIGHT_VP: number = GALLERY_TOP_BAR_MINI_HEIGHT_VP;

const GALLERY_TOP_BAR_SEARCH_INPUT_FOCUS_KEY: string = 'gallery_album_top_bar_search_input';
const GALLERY_TOP_BAR_SEARCH_ICON_SIZE_VP: number = 15;
const GALLERY_TOP_BAR_SEARCH_TEXT_OFFSET_VP: number = 4;
const GALLERY_TOP_BAR_CONTROL_RADIUS_VP: number = 20;

/** 内容区顶部 inset：含搜索态 bottomBuilder */
export function galleryAlbumTopBarChromeHeightVp(inSearchMode: boolean): number {
  if (inSearchMode) {
    return GALLERY_TOP_BAR_MINI_HEIGHT_VP + GALLERY_TOP_BAR_SEARCH_FIELD_HEIGHT_VP;
  }
  return GALLERY_TOP_BAR_MINI_HEIGHT_VP;
}

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

  private mainTitleText(): string {
    if (this.gallerySelectionMode) {
      return this.selectionText();
    }
    if (this.inSearchMode) {
      return '搜索';
    }
    if (this.isRootSurfaceMode()) {
      return this.rootSurfaceTitle;
    }
    return this.secondaryModeTitle();
  }

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private shouldShowBack(): boolean {
    if (this.gallerySelectionMode && !this.inSearchMode) {
      return false;
    }
    if (this.inSearchMode) {
      return true;
    }
    return !this.isRootSurfaceMode();
  }

  private chromeHeightVp(): number {
    return galleryAlbumTopBarChromeHeightVp(this.inSearchMode);
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

  private leaveSearchOrBack(): void {
    if (this.gallerySelectionMode && this.inSearchMode) {
      this.onExitSelection();
      return;
    }
    if (this.inSearchMode) {
      this.suppressSearchRestoreTemporarily();
      this.onBackToGallery();
      return;
    }
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
  private searchBottomBuilder() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(GALLERY_TOP_BAR_SEARCH_ICON_SIZE_VP)
        .fontColor([$r('app.color.gallery_material_search_placeholder')])

      TextInput({
        placeholder: 'AI 搜索图库...',
        text: this.searchQuery,
        controller: this.searchInputCtrl
      })
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
    .height(GALLERY_TOP_BAR_SEARCH_FIELD_HEIGHT_VP)
    .padding({ left: 12, right: 12 })
    .margin({ left: 12, right: 12, bottom: 4 })
    .backgroundColor($r('app.color.gallery_material_surface_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(fnLiquidGlassGradient())
    .borderRadius(GALLERY_TOP_BAR_CONTROL_RADIUS_VP)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
    .alignItems(VerticalAlign.Center)
  }

  /** 根态 / 子模式 / 多选：官方 titleBar.menu */
  @Builder
  private navigationDefault() {
    HdsNavigation() {
      // 仅作顶栏浮层：内容区留空，高度收束到 chrome，避免挡住下方图库
      Column()
        .width('100%')
        .height(0)
    }
    .width('100%')
    .height(this.chromeHeightVp())
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(!this.shouldShowBack())
    .titleBar(this.canUseHds() ? {
      padding: { start: LengthMetrics.vp(8), end: LengthMetrics.vp(8) },
      avoidLayoutSafeArea: false,
      enableComponentSafeArea: false,
      style: {
        blurStrategy: BlurStrategy.ADAPTIVE,
        scrollEffectOpts: {
          enableScrollEffect: false,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        // @SuppressWarnings compatibility
        systemMaterialEffect: fnHdsImmersiveSystemMaterialEffect(),
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('app.color.text_primary'),
              subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              backgroundColor: $r('app.color.gallery_material_surface_bg'),
              iconColor: $r('app.color.icon_primary'),
              textColor: $r('app.color.button_secondary_fg')
            },
            backIconStyle: {
              backgroundColor: $r('app.color.gallery_material_surface_bg'),
              iconColor: $r('app.color.icon_primary')
            }
          }
        }
      },
      content: {
        title: { mainTitle: this.mainTitleText() },
        menu: { value: this.buildDefaultMenuItems() },
        backIcon: {
          label: '返回',
          isEnabled: this.shouldShowBack(),
          action: (): void => {
            this.leaveSearchOrBack();
          }
        }
      }
    } : {
      padding: { start: LengthMetrics.vp(8), end: LengthMetrics.vp(8) },
      avoidLayoutSafeArea: false,
      enableComponentSafeArea: false,
      style: {
        blurStrategy: BlurStrategy.ADAPTIVE,
        scrollEffectOpts: {
          enableScrollEffect: false,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('app.color.text_primary'),
              subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              backgroundColor: $r('app.color.gallery_material_surface_bg'),
              iconColor: $r('app.color.icon_primary'),
              textColor: $r('app.color.button_secondary_fg')
            },
            backIconStyle: {
              backgroundColor: $r('app.color.gallery_material_surface_bg'),
              iconColor: $r('app.color.icon_primary')
            }
          }
        }
      },
      content: {
        title: { mainTitle: this.mainTitleText() },
        menu: { value: this.buildDefaultMenuItems() },
        backIcon: {
          label: '返回',
          isEnabled: this.shouldShowBack(),
          action: (): void => {
            this.leaveSearchOrBack();
          }
        }
      }
    })
  }

  /** 搜索态：bottomBuilder 放输入框，menu 放更多/完成 */
  @Builder
  private navigationSearch() {
    HdsNavigation() {
      Column()
        .width('100%')
        .height(0)
    }
    .width('100%')
    .height(this.chromeHeightVp())
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(false)
    .titleBar(this.canUseHds() ? {
      padding: { start: LengthMetrics.vp(8), end: LengthMetrics.vp(8) },
      avoidLayoutSafeArea: false,
      enableComponentSafeArea: false,
      style: {
        blurStrategy: BlurStrategy.ADAPTIVE,
        scrollEffectOpts: {
          enableScrollEffect: false,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        // @SuppressWarnings compatibility
        systemMaterialEffect: fnHdsImmersiveSystemMaterialEffect(),
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('app.color.text_primary'),
              subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              backgroundColor: $r('app.color.gallery_material_surface_bg'),
              iconColor: $r('app.color.icon_primary'),
              textColor: $r('app.color.button_secondary_fg')
            },
            backIconStyle: {
              backgroundColor: $r('app.color.gallery_material_surface_bg'),
              iconColor: $r('app.color.icon_primary')
            }
          }
        }
      },
      content: {
        title: { mainTitle: this.mainTitleText() },
        menu: { value: this.buildSearchMenuItems() },
        backIcon: {
          label: '返回',
          isEnabled: true,
          action: (): void => {
            this.leaveSearchOrBack();
          }
        },
        bottomBuilder: {
          builder: (): void => {
            this.searchBottomBuilder();
          },
          height: GALLERY_TOP_BAR_SEARCH_FIELD_HEIGHT_VP
        }
      }
    } : {
      padding: { start: LengthMetrics.vp(8), end: LengthMetrics.vp(8) },
      avoidLayoutSafeArea: false,
      enableComponentSafeArea: false,
      style: {
        blurStrategy: BlurStrategy.ADAPTIVE,
        scrollEffectOpts: {
          enableScrollEffect: false,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('app.color.text_primary'),
              subTitleColor: $r('app.color.text_secondary')
            },
            menuStyle: {
              backgroundColor: $r('app.color.gallery_material_surface_bg'),
              iconColor: $r('app.color.icon_primary'),
              textColor: $r('app.color.button_secondary_fg')
            },
            backIconStyle: {
              backgroundColor: $r('app.color.gallery_material_surface_bg'),
              iconColor: $r('app.color.icon_primary')
            }
          }
        }
      },
      content: {
        title: { mainTitle: this.mainTitleText() },
        menu: { value: this.buildSearchMenuItems() },
        backIcon: {
          label: '返回',
          isEnabled: true,
          action: (): void => {
            this.leaveSearchOrBack();
          }
        },
        bottomBuilder: {
          builder: (): void => {
            this.searchBottomBuilder();
          },
          height: GALLERY_TOP_BAR_SEARCH_FIELD_HEIGHT_VP
        }
      }
    })
  }

  private menuItem(content: HdsNavigationIconOptions): HdsNavigationMenuItemOptions {
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
  }

  private buildSearchMenuItems(): HdsNavigationMenuItemOptions[] {
    if (this.gallerySelectionMode) {
      const doneContent: HdsNavigationIconOptions = {
        label: '完成',
        type: TextStyleMode.NORMAL,
        action: (): void => {
          this.onExitSelection();
        }
      };
      return [this.menuItem(doneContent)];
    }
    const moreContent: HdsNavigationIconOptions = {
      label: '更多',
      icon: $r('sys.symbol.more'),
      type: IconStyleMode.NORMAL,
      isEnabled: true,
      action: (): void => {
        this.onShowMoreMenu();
      }
    };
    return [this.menuItem(moreContent)];
  }

  private buildDefaultMenuItems(): HdsNavigationMenuItemOptions[] {
    if (this.gallerySelectionMode) {
      const cancelContent: HdsNavigationIconOptions = {
        label: '取消',
        type: TextStyleMode.NORMAL,
        action: (): void => {
          this.onExitSelection();
        }
      };
      return [this.menuItem(cancelContent)];
    }
    if (!this.isRootSurfaceMode()) {
      const empty: HdsNavigationMenuItemOptions[] = [];
      return empty;
    }
    const items: HdsNavigationMenuItemOptions[] = [];
    if (this.isAlbumsHomeSurface()) {
      const uploadContent: HdsNavigationIconOptions = {
        label: '上传',
        icon: $r('sys.symbol.plus'),
        type: IconStyleMode.NORMAL,
        isEnabled: true,
        action: (): void => {
          this.onStartUpload();
        }
      };
      items.push(this.menuItem(uploadContent));
    } else {
      const multiContent: HdsNavigationIconOptions = {
        label: '多选',
        type: TextStyleMode.NORMAL,
        action: (): void => {
          this.onEnterSelection();
        }
      };
      items.push(this.menuItem(multiContent));
    }
    const searchContent: HdsNavigationIconOptions = {
      label: '搜索',
      icon: $r('sys.symbol.magnifyingglass'),
      type: IconStyleMode.NORMAL,
      isEnabled: true,
      action: (): void => {
        this.onOpenSearch();
        this.activateSearchAutoFocus(48);
      }
    };
    items.push(this.menuItem(searchContent));
    if (!this.isAlbumsHomeSurface()) {
      const moreContent: HdsNavigationIconOptions = {
        label: '更多',
        icon: $r('sys.symbol.more'),
        type: IconStyleMode.NORMAL,
        isEnabled: true,
        action: (): void => {
          this.onShowMoreMenu();
        }
      };
      items.push(this.menuItem(moreContent));
    }
    return items;
  }

  build() {
    Column() {
      if (this.inSearchMode) {
        this.navigationSearch()
      } else {
        this.navigationDefault()
      }
    }
    .width('100%')
    .padding({ top: this.topSafeInsetVp })
  }
}
