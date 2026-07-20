/**
 * 回收站顶栏：对齐官方 HdsNavigation.titleBar + systemMaterialEffect。
 * 多选走 titleBar.menu / backIcon，由系统处理命中与沉浸光感。
 */
import { LengthMetrics } from '@kit.ArkUI';
import {
  BlurStrategy,
  HdsNavigation,
  HdsNavigationBackButtonItemOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleBarStyle,
  HdsNavigationTitleMode,
  TextStyleMode,
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import {
  fnHdsImmersiveSystemMaterialEffect,
  fnHdsChromeButtonBackgroundColor,
  fnHdsChromeButtonFallbackBackgroundColor,
  fnHdsChromeButtonForegroundColor,
  fnHdsNavChromeBackgroundStyle,
  fnHdsNavChromeScrollEffectOpts
} from '../../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../../common/FnImmersiveSettings';

/** pageContent 默认占位：未传入真实内容时渲染空视图。 */
@Builder
function recycleBinChromeEmptyPageContent() {
}

@Component
export struct RecycleBinChrome {
  @Prop selectionMode: boolean = false;
  @Prop selectedCount: number = 0;
  @Prop topSafeInsetVp: number = 0;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;

  /** 真实可滚动内容：回收站列表 Stack，由页面通过尾随闭包传入。 */
  @BuilderParam pageContent: () => void = recycleBinChromeEmptyPageContent;
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

  private titleBarOriginalStyle(): HdsNavigationTitleBarStyle {
    const buttonBg: ResourceColor = this.canUseHds()
      ? fnHdsChromeButtonBackgroundColor()
      : fnHdsChromeButtonFallbackBackgroundColor();
    const buttonFg: ResourceColor = this.canUseHds()
      ? fnHdsChromeButtonForegroundColor()
      : $r('app.color.icon_primary');
    const textFg: ResourceColor = this.canUseHds()
      ? $r('app.color.text_primary')
      : $r('app.color.button_secondary_fg');
    return {
      backgroundStyle: fnHdsNavChromeBackgroundStyle(),
      contentStyle: {
        titleStyle: {
          mainTitleColor: $r('app.color.text_primary'),
          subTitleColor: $r('app.color.text_secondary')
        },
        menuStyle: {
          backgroundColor: buttonBg,
          iconColor: buttonFg,
          textColor: textFg
        },
        backIconStyle: {
          backgroundColor: buttonBg,
          iconColor: buttonFg
        }
      }
    };
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
    return this.canUseHds() ? {
      padding: { start: LengthMetrics.vp(8), end: LengthMetrics.vp(8) },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false,
      style: {
        blurStrategy: BlurStrategy.ADAPTIVE,
        scrollEffectOpts: fnHdsNavChromeScrollEffectOpts(),
        // @SuppressWarnings compatibility
        systemMaterialEffect: fnHdsImmersiveSystemMaterialEffect(),
        originalStyle: this.titleBarOriginalStyle(),
        scrollEffectStyle: {
          backgroundStyle: fnHdsNavChromeBackgroundStyle()
        }
      },
      content: this.titleBarContent()
    } : {
      padding: { start: LengthMetrics.vp(8), end: LengthMetrics.vp(8) },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false,
      style: {
        blurStrategy: BlurStrategy.ADAPTIVE,
        scrollEffectOpts: fnHdsNavChromeScrollEffectOpts(),
        originalStyle: this.titleBarOriginalStyle(),
        scrollEffectStyle: {
          backgroundStyle: fnHdsNavChromeBackgroundStyle()
        }
      },
      content: this.titleBarContent()
    };
  }

  build() {
    HdsNavigation() {
      this.pageContent()
    }
    .width('100%')
    .height('100%')
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(this.selectionMode)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .bindToScrollable(this.scrollerList)
    .titleBar(this.titleBarOptions())
  }
}
