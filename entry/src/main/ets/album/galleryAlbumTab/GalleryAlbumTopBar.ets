/**
 * 图库顶栏：对齐官方 HdsNavigation.titleBar + systemMaterialEffect。
 * 搜索 / 更多 / 多选走 titleBar.menu / backIcon，由系统处理命中与沉浸光感。
 */
import {
  HdsNavigation,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  IconStyleMode,
  TextStyleMode
} from '@kit.UIDesignKit';
import { fnHdsBindMenuOptions } from '../../common/FnHdsOverlay';
import {
  fnHdsMiniTitleBarOptions,
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
const GALLERY_TOP_BAR_SEARCH_INSET_VP: number = 12;
const GALLERY_TOP_BAR_SEARCH_GAP_BOTTOM_VP: number = 4;
const GALLERY_TOP_BAR_CONTROL_RADIUS_VP: number = 20;

/** 内容区顶部 inset：含搜索态 bottomBuilder */
export function galleryAlbumTopBarChromeHeightVp(inSearchMode: boolean): number {
  if (inSearchMode) {
    return GALLERY_TOP_BAR_MINI_HEIGHT_VP + GALLERY_TOP_BAR_SEARCH_FIELD_HEIGHT_VP;
  }
  return GALLERY_TOP_BAR_MINI_HEIGHT_VP;
}

/** pageContent 默认占位：未传入真实内容时渲染空视图，避免 HdsNavigation 内容区为 undefined。 */
@Builder
function galleryAlbumTopBarEmptyPageContent() {
}

/**
 * 搜索输入独立成子组件：文本只存在本组件 @State，并用官方 $$ 双向绑定。
 * 文档：TextInput.text「建议通过 onChange 将状态与文本绑定 / API10+ 支持 $$」，
 * 避免父页每敲一字刷新时重建 TextInput，导致输入法收起再弹出。
 */
@Component
struct GalleryAlbumSearchField {
  @Prop seedQuery: string = '';
  inputCtrl: TextInputController = new TextInputController();
  onTextChange: (value: string) => void = (_: string) => {};
  onSubmit: () => void = () => {};
  @State private inputText: string = '';

  aboutToAppear(): void {
    this.inputText = this.seedQuery;
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(GALLERY_TOP_BAR_SEARCH_ICON_SIZE_VP)
          .fontColor([$r('app.color.gallery_material_search_placeholder')])
          .flexShrink(0)

        TextInput({
          placeholder: 'AI 搜索图库...',
          text: $$this.inputText,
          controller: this.inputCtrl
        })
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .id(GALLERY_TOP_BAR_SEARCH_INPUT_FOCUS_KEY)
          .height('100%')
          .defaultFocus(false)
          .enableKeyboardOnFocus(true)
          .backgroundColor(Color.Transparent)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .caretColor($r('app.color.brand_primary'))
          .placeholderColor($r('app.color.gallery_material_search_placeholder'))
          .padding({ left: GALLERY_TOP_BAR_SEARCH_TEXT_OFFSET_VP, right: 0 })
          .enterKeyType(EnterKeyType.Search)
          .onChange((value: string): void => {
            this.onTextChange(value);
          })
          .onSubmit((): void => {
            this.onSubmit();
          })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: GALLERY_TOP_BAR_SEARCH_INSET_VP, right: GALLERY_TOP_BAR_SEARCH_INSET_VP })
      .backgroundColor($r('app.color.gallery_material_surface_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .linearGradient(fnLiquidGlassGradient())
      .borderRadius(GALLERY_TOP_BAR_CONTROL_RADIUS_VP)
      .borderWidth(1)
      .borderColor($r('app.color.immersive_panel_border'))
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(GALLERY_TOP_BAR_SEARCH_FIELD_HEIGHT_VP)
    .padding({
      left: GALLERY_TOP_BAR_SEARCH_INSET_VP,
      right: GALLERY_TOP_BAR_SEARCH_INSET_VP,
      bottom: GALLERY_TOP_BAR_SEARCH_GAP_BOTTOM_VP
    })
  }
}

/** 「更多」菜单锚点：独立组件，展开时不要刷新搜索顶栏，避免输入框重建把键盘再次拉起。 */
@Component
export struct GalleryAlbumMoreMenuLayer {
  @Prop expanded: boolean = false;
  @Prop topSafeInsetVp: number = 0;
  @Prop showMoreMultiselect: boolean = false;
  @Prop showMoreUpload: boolean = false;
  onDismiss: () => void = () => {};
  onEnterMultiselect: () => void = () => {};
  onOpenSlideshow: () => void = () => {};
  onStartUpload: () => void = () => {};

  @Builder
  private moreMenuBuilder() {
    Menu() {
      if (this.showMoreMultiselect) {
        MenuItem({ content: '多选' })
          .onClick((): void => {
            this.onEnterMultiselect();
          })
      }
      if (this.showMoreUpload) {
        // 与相册页“+”按钮复用同一手动 Picker 上传流程；
        // NAS 去重规则明确前，不从更多菜单触发自动扫描与同步。
        MenuItem({ content: '上传' })
          .onClick((): void => {
            this.onStartUpload();
          })
      }
      MenuItem({ content: '幻灯片' })
        .onClick((): void => {
          this.onOpenSlideshow();
        })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Row()
        .width(40)
        .height(40)
        .margin({ top: this.topSafeInsetVp + 8, right: $r('app.float.hds_title_bar_padding_horizontal') })
        .hitTestBehavior(HitTestMode.None)
        .expandSafeArea([SafeAreaType.KEYBOARD], [SafeAreaEdge.BOTTOM])
        .bindMenu(this.expanded, this.moreMenuBuilder, fnHdsBindMenuOptions(
          Placement.BottomLeft,
          (): void => {
            this.onDismiss();
          }
        ))
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
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
  /** 外部写入的搜索词（智能分类点选等）；输入过程不要回写成会刷新本组件的 @Prop。 */
  @Prop seedQuery: string = '';
  /** 系统状态栏高度：内容区顶部留白仍用此值；按钮避让靠 titleBar.avoidLayoutSafeArea。 */
  @Prop topSafeInsetVp: number = 0;
  @Prop @Watch('onPageShowSignal') pageShowSignal: number = 0;
  @Prop searchFilterActive: boolean = false;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;

  /** 真实可滚动内容：图库/相册/分类等页面 Stack，由调用方通过尾随闭包传入。 */
  @BuilderParam pageContent: () => void = galleryAlbumTopBarEmptyPageContent;
  /** 当前可见列表的 Scroller；只绑这一条，闲置 Scroller 停在顶端会把模糊打回初始态。 */
  @Prop scrollerList: Scroller[] = [];

  onSearchQueryChange: (value: string) => void = (_: string) => {};
  onSearchSubmit: () => void = () => {};
  onOpenSearch: () => void = () => {};
  onStartUpload: () => void = () => {};
  onExitSelection: () => void = () => {};
  onEnterSelection: () => void = () => {};
  onBackToGallery: () => void = () => {};
  onShowMoreMenu: () => void = () => {};
  onOpenSearchFilter: () => void = () => {};

  /** 不进 @State：只挡自动抢焦，避免为了收键盘刷新输入框。 */
  private suppressSearchAutoFocus: boolean = true;
  private searchSubmitted: boolean = false;
  private searchDraft: string = '';
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

  /**
   * 官方：弹出菜单前用 stopEditing + clearFocus 收起软键盘，避免「弹窗被键盘顶起」。
   * 文档：arkts-manage-keyboard。只收键盘，不改装饰器状态，避免 TextInput 被重建后又自动获焦。
   */
  private releaseSearchImeForOverlay(): void {
    this.clearSearchFocusKickTimer();
    this.searchSubmitted = true;
    this.blurSearchInput();
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (_e) {
    }
  }

  private onSearchFilterAction(): void {
    if (this.inSearchMode) {
      this.releaseSearchImeForOverlay();
    }
    this.onOpenSearchFilter();
  }

  private onMoreMenuAction(): void {
    if (this.inSearchMode) {
      this.releaseSearchImeForOverlay();
    }
    this.onShowMoreMenu();
  }

  private onSearchTextChange(value: string): void {
    this.searchDraft = value;
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
      this.searchInputCtrl.caretPosition(this.searchDraft.length);
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
      this.searchDraft = this.seedQuery;
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
    this.searchDraft = this.seedQuery;
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
    GalleryAlbumSearchField({
      seedQuery: this.seedQuery,
      inputCtrl: this.searchInputCtrl,
      onTextChange: (value: string): void => {
        this.onSearchTextChange(value);
      },
      onSubmit: (): void => {
        this.submitSearchAndReleaseFocus();
      }
    })
  }

  /** 根态 / 子模式 / 多选：官方 titleBar.menu */
  private defaultTitleBarOptions(): HdsNavigationTitleBarOptions {
    return fnHdsMiniTitleBarOptions(this.canUseHds(), {
      title: { mainTitle: this.mainTitleText() },
      menu: { value: this.buildDefaultMenuItems() },
      backIcon: {
        label: '返回',
        isEnabled: this.shouldShowBack(),
        action: (): void => {
          this.leaveSearchOrBack();
        }
      }
    }, true);
  }

  /** 搜索态：bottomBuilder 放输入框，menu 放更多/完成 */
  private searchTitleBarOptions(): HdsNavigationTitleBarOptions {
    return fnHdsMiniTitleBarOptions(this.canUseHds(), {
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
    }, true);
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
    const filterContent: HdsNavigationIconOptions = {
      label: this.searchFilterActive ? '已筛选' : '筛选',
      icon: $r('sys.symbol.slider_horizontal_2'),
      type: IconStyleMode.NORMAL,
      isEnabled: true,
      action: (): void => {
        this.onSearchFilterAction();
      }
    };
    const moreContent: HdsNavigationIconOptions = {
      label: '更多',
      icon: $r('sys.symbol.dot_grid_2x2'),
      type: IconStyleMode.NORMAL,
      isEnabled: true,
      action: (): void => {
        this.onMoreMenuAction();
      }
    };
    return [this.menuItem(filterContent), this.menuItem(moreContent)];
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
        icon: $r('sys.symbol.dot_grid_2x2'),
        type: IconStyleMode.NORMAL,
        isEnabled: true,
        action: (): void => {
          this.onMoreMenuAction();
        }
      };
      items.push(this.menuItem(moreContent));
    }
    return items;
  }

  build() {
    HdsNavigation() {
      this.pageContent()
    }
    .width('100%')
    .height('100%')
    // 用作整页壳时必须 Stack：默认 Auto 在宽屏(≥600vp)会 Split，内容只占左栏
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(!this.shouldShowBack())
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .bindToScrollable(this.scrollerList)
    .titleBar(this.inSearchMode ? this.searchTitleBarOptions() : this.defaultTitleBarOptions())
  }
}
