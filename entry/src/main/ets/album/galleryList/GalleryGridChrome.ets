/**
 * 相册网格页统一顶栏：返回 / 标题 / 更多 / 多选。
 * CategoryGallery、文件夹、回收站都用这一份，不要再各写一套 HdsNavigation。
 */
import {
  HdsNavigation,
  HdsNavigationBackButtonItemOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  IconStyleMode,
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import { FnHdsMoreMenuAnchor } from '../../common/FnHdsMoreMenu';
import { FN_HDS_NAV_CHROME_HEIGHT_VP, fnHdsMiniTitleBarOptions, fnHdsRoundCancelIcon } from '../../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../../common/FnImmersiveSettings';

@Component
export struct GalleryGridChrome {
  @Prop selectionMode: boolean = false;
  @Prop selectedCount: number = 0;
  @Prop title: string = '';
  @Prop fallbackTitle: string = '';
  @Prop totalCount: number = 0;
  @Prop showCountSubtitle: boolean = true;
  @Prop topSafeInsetVp: number = 0;
  /** true：右侧「更多」（多选/幻灯片）；false：右侧直接「多选」（回收站） */
  @Prop useMoreMenu: boolean = true;
  @Prop moreMenuExpanded: boolean = false;
  @Prop showJumpToFolder: boolean = false;
  @Prop showSlideshow: boolean = true;
  @Prop showGoUp: boolean = false;
  @Prop canGoUp: boolean = false;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;

  scrollerList: Scroller[] = [];

  onCancelSelection: () => void = () => {};
  onBack: () => void = () => {};
  onGoUp: () => void = () => {};
  onToggleMode: () => void = () => {};
  onShowMoreMenu: () => void = () => {};
  onDismissMoreMenu: () => void = () => {};
  onEnterMultiselectFromMore: () => void = () => {};
  onOpenSlideshowFromMore: () => void = () => {};
  onJumpToFolder: () => void = () => {};

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private mainTitleText(): string {
    if (this.selectionMode) {
      return `已选择 ${this.selectedCount} 项`;
    }
    return this.title.length > 0 ? this.title : this.fallbackTitle;
  }

  private menuItem(content: HdsNavigationIconOptions): HdsNavigationMenuItemOptions {
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
  }

  private doneMenuContent(): HdsNavigationIconOptions {
    const content: HdsNavigationIconOptions = {
      label: '完成',
      icon: $r('sys.symbol.checkmark'),
      type: IconStyleMode.NORMAL,
      isEnabled: true,
      action: (): void => {
        this.onToggleMode();
      }
    };
    return content;
  }

  private moreMenuContent(): HdsNavigationIconOptions {
    const content: HdsNavigationIconOptions = {
      label: '更多',
      icon: $r('sys.symbol.dot_grid_2x2'),
      type: IconStyleMode.NORMAL,
      isEnabled: true,
      action: (): void => {
        this.onShowMoreMenu();
      }
    };
    return content;
  }

  private multiMenuContent(): HdsNavigationIconOptions {
    const content: HdsNavigationIconOptions = {
      label: $r('app.string.gallery_multiselect'),
      icon: $r('sys.symbol.checkmark_circle'),
      type: IconStyleMode.NORMAL,
      isEnabled: true,
      action: (): void => {
        this.onToggleMode();
      }
    };
    return content;
  }

  private goUpMenuContent(): HdsNavigationIconOptions {
    const content: HdsNavigationIconOptions = {
      label: '上一级',
      icon: $r('sys.symbol.arrow_up_to_line'),
      type: IconStyleMode.NORMAL,
      isEnabled: this.canGoUp,
      action: (): void => {
        this.onGoUp();
      }
    };
    return content;
  }

  private buildMenuItems(): HdsNavigationMenuItemOptions[] {
    if (this.selectionMode) {
      return [this.menuItem(this.doneMenuContent())];
    }
    const items: HdsNavigationMenuItemOptions[] = [];
    if (this.showGoUp) {
      items.push(this.menuItem(this.goUpMenuContent()));
    }
    if (this.useMoreMenu) {
      items.push(this.menuItem(this.moreMenuContent()));
      return items;
    }
    items.push(this.menuItem(this.multiMenuContent()));
    return items;
  }

  private backIconOptions(): HdsNavigationBackButtonItemOptions {
    if (this.selectionMode) {
      return fnHdsRoundCancelIcon((): void => {
        this.onCancelSelection();
      });
    }
    const backIcon: HdsNavigationBackButtonItemOptions = {
      label: '返回',
      isEnabled: true,
      action: (): void => {
        this.onBack();
      }
    };
    return backIcon;
  }

  private titleBarContent(): TitleBarContentOptions {
    if (this.selectionMode || !this.showCountSubtitle) {
      return {
        title: { mainTitle: this.mainTitleText() },
        menu: { value: this.buildMenuItems() },
        backIcon: this.backIconOptions()
      };
    }
    return {
      title: {
        mainTitle: this.mainTitleText(),
        subTitle: `${this.totalCount} 项`
      },
      menu: { value: this.buildMenuItems() },
      backIcon: this.backIconOptions()
    };
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    return fnHdsMiniTitleBarOptions(this.canUseHds(), this.titleBarContent(), false);
  }

  @Builder
  private titleBarNavigationBody() {
    Column()
      .width('100%')
      .height(0)
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        HdsNavigation() {
          this.titleBarNavigationBody()
        }
        .width('100%')
        .height(FN_HDS_NAV_CHROME_HEIGHT_VP)
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .hideBackButton(false)
        .bindToScrollable(this.scrollerList)
        .titleBar(this.titleBarOptions())
        .hitTestBehavior(HitTestMode.Default)
      }
      .width('100%')
      .padding({ top: this.topSafeInsetVp })
      .clip(true)
      .hitTestBehavior(HitTestMode.Default)

      if (this.useMoreMenu) {
        FnHdsMoreMenuAnchor({
          expanded: this.moreMenuExpanded,
          topSafeInsetVp: this.topSafeInsetVp,
          showMultiselect: true,
          showSlideshow: this.showSlideshow,
          showJumpToFolder: this.showJumpToFolder,
          onDismiss: (): void => {
            this.onDismissMoreMenu();
          },
          onMultiselect: (): void => {
            this.onEnterMultiselectFromMore();
          },
          onSlideshow: (): void => {
            this.onOpenSlideshowFromMore();
          },
          onJumpToFolder: (): void => {
            this.onJumpToFolder();
          }
        })
      }
    }
    .width('100%')
    .height(this.topSafeInsetVp + FN_HDS_NAV_CHROME_HEIGHT_VP)
    .clip(true)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
