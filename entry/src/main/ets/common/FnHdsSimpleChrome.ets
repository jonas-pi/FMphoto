/**
 * 相册子页迷你顶栏：官方 HdsNavigation 返回按钮 + systemMaterialEffect。
 * 与回收站 / 分类相册 / 设置同一套返回，不再使用 FnTopBar 胶囊「返回」。
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
import { FN_HDS_NAV_CHROME_HEIGHT_VP, fnHdsMiniTitleBarOptions } from './FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from './FnImmersiveSettings';

@Component
export struct FnHdsSimpleChrome {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop rightText: string = '';
  /** 官方圆形菜单图标；rightAsIcon 为 true 时与返回按钮同款圆形背板 */
  @Prop rightIcon: Resource = $r('sys.symbol.pencil_line');
  @Prop rightAsIcon: boolean = false;
  @Prop topSafeInsetVp: number = 0;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  scrollerList: Scroller[] = [];
  onBack: () => void = () => {};
  onRightClick: () => void = () => {};

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private menuItem(content: HdsNavigationIconOptions): HdsNavigationMenuItemOptions {
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
  }

  private buildMenuItems(): HdsNavigationMenuItemOptions[] {
    const label = this.rightText.trim();
    if (label.length === 0) {
      return [];
    }
    if (this.rightAsIcon) {
      const iconContent: HdsNavigationIconOptions = {
        label: label,
        icon: this.rightIcon,
        type: IconStyleMode.NORMAL,
        isEnabled: true,
        action: (): void => {
          this.onRightClick();
        }
      };
      return [this.menuItem(iconContent)];
    }
    const content: HdsNavigationIconOptions = {
      label: label,
      type: TextStyleMode.NORMAL,
      action: (): void => {
        this.onRightClick();
      }
    };
    return [this.menuItem(content)];
  }

  private backIconOptions(): HdsNavigationBackButtonItemOptions {
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
    if (this.subtitle.length > 0) {
      return {
        title: { mainTitle: this.title, subTitle: this.subtitle },
        menu: { value: this.buildMenuItems() },
        backIcon: this.backIconOptions()
      };
    }
    return {
      title: { mainTitle: this.title },
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
