/**
 * 媒体分类顶栏：对齐官方 HdsNavigation.titleBar + systemMaterialEffect。
 * 多选 / 更多走 titleBar.menu / backIcon。
 *
 * 顶栏与宫格列表拆开（对齐预览页）。进多选立刻改取消 / 已选择 / 完成，
 * 但不会重建列表，长按划选的 Up 还能解锁滚动。
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
export struct CategoryGalleryChrome {
  @Prop selectionMode: boolean = false;
  @Prop selectedCount: number = 0;
  @Prop title: string = '';
  @Prop totalCount: number = 0;
  @Prop topSafeInsetVp: number = 0;
  /** 人物/智能分类相册：右侧显示「更多」而非直接露出「多选」 */
  @Prop personAlbumMode: boolean = false;
  @Prop moreMenuExpanded: boolean = false;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;

  /** 联动沉浸滚动光感的 Scroller 列表。 */
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

  private selectionText(): string {
    return `已选择 ${this.selectedCount} 项`;
  }

  private mainTitleText(): string {
    if (this.selectionMode) {
      return this.selectionText();
    }
    return this.title.length > 0 ? this.title : '媒体分类';
  }

  private subTitleText(): string {
    return `${this.totalCount} 项`;
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
    if (this.personAlbumMode) {
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
    const multiContent: HdsNavigationIconOptions = {
      label: $r('app.string.gallery_multiselect'),
      type: TextStyleMode.NORMAL,
      action: (): void => {
        this.onToggleMode();
      }
    };
    return [this.menuItem(multiContent)];
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
        subTitle: this.selectionMode ? '' : this.subTitleText()
      },
      menu: { value: this.buildMenuItems() },
      backIcon: this.backIconOptions()
    };
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    // 顶栏与列表拆开：不要 avoidLayoutSafeArea，由外层 padding 吃状态栏
    return fnHdsMiniTitleBarOptions(this.canUseHds(), this.titleBarContent(), false);
  }

  /** Navigation 内容槽必须有子节点；高度 0，真正列表在浮层下面，进多选改顶栏不会拆 List */
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
    // 高度只包顶栏，禁止 100% 铺满，否则 HdsNavigation 会把宫格命中区盖住，松手后点不动。
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
    // 作为全屏 Stack 子节点会被拉高；写死高度，空白区 Transparent 把点击还给宫格
    .height(this.topSafeInsetVp + FN_HDS_NAV_CHROME_HEIGHT_VP)
    .clip(true)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
