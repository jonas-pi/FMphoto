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
  TextStyleMode,
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import { fnHdsBindMenuOptions } from '../../common/FnHdsOverlay';
import { FN_HDS_NAV_CHROME_HEIGHT_VP, fnHdsMiniTitleBarOptions } from '../../common/FnUiCommon';
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
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  scrollerList: Scroller[] = [];

  onCancelSelection: () => void = () => {};
  onBack: () => void = () => {};
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
        type: TextStyleMode.NORMAL,
        action: (): void => {
          this.onToggleMode();
        }
      };
      return [this.menuItem(doneContent)];
    }
    const moreContent: HdsNavigationIconOptions = {
      label: '更多',
      icon: $r('sys.symbol.dot_grid_2x2'),
      type: IconStyleMode.NORMAL,
      isEnabled: true,
      action: (): void => {
        this.onShowMoreMenu();
      }
    };
    return [this.menuItem(moreContent)];
  }

  private backIconOptions(): HdsNavigationBackButtonItemOptions {
    if (this.selectionMode) {
      const cancelIcon: HdsNavigationBackButtonItemOptions = {
        label: '取消',
        isEnabled: true,
        action: (): void => {
          this.onCancelSelection();
        }
      };
      return cancelIcon;
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

  @Builder
  private moreMenuBuilder() {
    Menu() {
      MenuItem({ content: '多选' })
        .onClick((): void => {
          this.onEnterMultiselectFromMore();
        })
      MenuItem({ content: '幻灯片' })
        .onClick((): void => {
          this.onOpenSlideshowFromMore();
        })
    }
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

      Row()
        .width(40)
        .height(40)
        .margin({ top: this.topSafeInsetVp + 8, right: $r('app.float.hds_title_bar_padding_horizontal') })
        .hitTestBehavior(HitTestMode.None)
        .bindMenu(this.moreMenuExpanded, this.moreMenuBuilder, fnHdsBindMenuOptions(
          Placement.BottomLeft,
          (): void => {
            this.onDismissMoreMenu();
          }
        ))
    }
    .width('100%')
    .height(this.topSafeInsetVp + FN_HDS_NAV_CHROME_HEIGHT_VP)
    .clip(true)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
