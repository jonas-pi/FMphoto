/**
 * 文件夹浏览顶栏：官方 HdsNavigation + 「更多」（多选 / 幻灯片）。
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
export struct FolderBrowseChrome {
  @Prop selectionMode: boolean = false;
  @Prop selectedCount: number = 0;
  @Prop title: string = '';
  @Prop totalCount: number = 0;
  @Prop topSafeInsetVp: number = 0;
  @Prop moreMenuExpanded: boolean = false;
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

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private mainTitleText(): string {
    if (this.selectionMode) {
      return `已选择 ${this.selectedCount} 项`;
    }
    return this.title.length > 0 ? this.title : '文件夹';
  }

  private menuItem(content: HdsNavigationIconOptions): HdsNavigationMenuItemOptions {
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
  }

  private buildMenuItems(): HdsNavigationMenuItemOptions[] {
    if (this.selectionMode) {
      const doneContent: HdsNavigationIconOptions = {
        label: '完成',
        icon: $r('sys.symbol.checkmark'),
        type: IconStyleMode.NORMAL,
        isEnabled: true,
        action: (): void => {
          this.onToggleMode();
        }
      };
      return [this.menuItem(doneContent)];
    }
    const upContent: HdsNavigationIconOptions = {
      label: '上一级',
      icon: $r('sys.symbol.arrow_up'),
      type: IconStyleMode.NORMAL,
      isEnabled: this.canGoUp,
      action: (): void => {
        this.onGoUp();
      }
    };
    const moreContent: HdsNavigationIconOptions = {
      label: '更多',
      icon: $r('sys.symbol.dot_grid_2x2'),
      type: IconStyleMode.NORMAL,
      isEnabled: true,
      action: (): void => {
        this.onShowMoreMenu();
      }
    };
    return [this.menuItem(upContent), this.menuItem(moreContent)];
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
    return {
      title: {
        mainTitle: this.mainTitleText(),
        subTitle: this.selectionMode ? '' : `${this.totalCount} 项`
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

      FnHdsMoreMenuAnchor({
        expanded: this.moreMenuExpanded,
        topSafeInsetVp: this.topSafeInsetVp,
        showMultiselect: true,
        showSlideshow: true,
        onDismiss: (): void => {
          this.onDismissMoreMenu();
        },
        onMultiselect: (): void => {
          this.onEnterMultiselectFromMore();
        },
        onSlideshow: (): void => {
          this.onOpenSlideshowFromMore();
        }
      })
    }
    .width('100%')
    .height(this.topSafeInsetVp + FN_HDS_NAV_CHROME_HEIGHT_VP)
    .clip(true)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
