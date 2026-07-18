/**
 * 媒体分类顶栏：对齐官方 HdsNavigation.titleBar + systemMaterialEffect。
 * 多选 / 更多走 titleBar.menu / backIcon，由系统处理命中与沉浸光感。
 */
import { LengthMetrics } from '@kit.ArkUI';
import {
  BlurStrategy,
  HdsNavigation,
  HdsNavigationBackButtonItemOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarStyle,
  HdsNavigationTitleMode,
  IconStyleMode,
  TextStyleMode,
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import {
  fnHdsImmersiveSystemMaterialEffect,
  fnHdsChromeButtonBackgroundColor,
  fnHdsChromeButtonFallbackBackgroundColor,
  fnHdsChromeButtonForegroundColor,
  fnHdsNavChromeBackgroundStyle,
  fnHdsNavChromeScrollEffectOpts,
  FN_HDS_NAV_CHROME_HEIGHT_VP
} from '../../common/FnUiCommon';
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

  onCancelSelection: () => void = () => {};
  onBack: () => void = () => {};
  onToggleMode: () => void = () => {};
  onShowMoreMenu: () => void = () => {};

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
        icon: $r('sys.symbol.more'),
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
      title: {
        mainTitle: this.mainTitleText(),
        subTitle: this.selectionMode ? '' : this.subTitleText()
      },
      menu: { value: this.buildMenuItems() },
      backIcon: this.backIconOptions()
    };
  }

  @Builder
  private navigationContent() {
    Column()
      .width('100%')
      .height(0)
  }

  build() {
    Column() {
      HdsNavigation() {
        this.navigationContent()
      }
      .width('100%')
      .height(FN_HDS_NAV_CHROME_HEIGHT_VP)
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(this.selectionMode)
      .titleBar(this.canUseHds() ? {
        padding: { start: LengthMetrics.vp(8), end: LengthMetrics.vp(8) },
        avoidLayoutSafeArea: false,
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
        avoidLayoutSafeArea: false,
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
      })
    }
    .width('100%')
    .padding({ top: this.topSafeInsetVp })
  }
}
