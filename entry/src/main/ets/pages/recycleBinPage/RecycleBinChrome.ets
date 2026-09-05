/**
 * 回收站顶栏：对齐官方 HdsNavigation.titleBar + systemMaterialEffect。
 * 多选走 titleBar.menu / backIcon。
 * 顶栏与列表拆开，进多选立刻改顶栏，不拆宫格 List。
 */
import {
  HdsNavigation,
  HdsNavigationBackButtonItemOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  TextStyleMode,
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import { FN_HDS_NAV_CHROME_HEIGHT_VP, fnHdsMiniTitleBarOptions } from '../../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../../common/FnImmersiveSettings';

@Component
export struct RecycleBinChrome {
  @Prop selectionMode: boolean = false;
  @Prop selectedCount: number = 0;
  @Prop topSafeInsetVp: number = 0;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;

  /** 联动沉浸滚动光感的 Scroller 列表。 */
  scrollerList: Scroller[] = [];

  onCancelSelection: () => void = () => {};
  onBack: () => void = () => {};
  onToggleMode: () => void = () => {};

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private mainTitleText(): string {
    if (this.selectionMode) {
      return `已选择 ${this.selectedCount} 项`;
    }
    return '回收站';
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
      title: { mainTitle: this.mainTitleText() },
      menu: { value: this.buildMenuItems() },
      backIcon: this.backIconOptions()
    };
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    return fnHdsMiniTitleBarOptions(this.canUseHds(), this.titleBarContent(), false);
  }

  /** Navigation 内容槽必须有子节点；高度 0，真正列表在浮层下面 */
  @Builder
  private titleBarNavigationBody() {
    Column()
      .width('100%')
      .height(0)
  }

  build() {
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
    .height(this.topSafeInsetVp + FN_HDS_NAV_CHROME_HEIGHT_VP)
    .padding({ top: this.topSafeInsetVp })
    .clip(true)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
