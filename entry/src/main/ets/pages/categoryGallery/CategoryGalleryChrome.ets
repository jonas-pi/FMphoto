/**
 * 媒体分类顶栏：对齐官方 HdsNavigation.titleBar + systemMaterialEffect。
 * 多选 / 更多走 titleBar.menu / backIcon，由系统处理命中与沉浸光感。
 */
import {
  BlurStrategy,
  HdsNavigation,
  HdsNavigationBackButtonItemOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleBarStyle,
  HdsNavigationTitleMode,
  IconStyleMode,
  TextStyleMode,
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import { fnHdsBindMenuOptions } from '../../common/FnHdsOverlay';
import {
  fnHdsImmersiveSystemMaterialEffect,
  fnHdsChromeButtonBackgroundColor,
  fnHdsChromeButtonFallbackBackgroundColor,
  fnHdsChromeButtonForegroundColor,
  fnHdsNavChromeBackgroundStyle,
  fnHdsNavChromeScrolledBackgroundStyle,
  fnHdsNavChromeScrollEffectOpts,
  fnHdsNavTitleBarPadding
} from '../../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../../common/FnImmersiveSettings';

/** pageContent 默认占位：未传入真实内容时渲染空视图。 */
@Builder
function categoryGalleryChromeEmptyPageContent() {
}

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

  /** 真实可滚动内容：媒体分类列表 Stack，由页面通过尾随闭包传入。 */
  @BuilderParam pageContent: () => void = categoryGalleryChromeEmptyPageContent;
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

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    return this.canUseHds() ? {
      padding: fnHdsNavTitleBarPadding(),
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false,
      style: {
        blurStrategy: BlurStrategy.ADAPTIVE,
        scrollEffectOpts: fnHdsNavChromeScrollEffectOpts(),
        // @SuppressWarnings compatibility
        systemMaterialEffect: fnHdsImmersiveSystemMaterialEffect(),
        originalStyle: this.titleBarOriginalStyle(),
        scrollEffectStyle: {
          backgroundStyle: fnHdsNavChromeScrolledBackgroundStyle()
        }
      },
      content: this.titleBarContent()
    } : {
      padding: fnHdsNavTitleBarPadding(),
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false,
      style: {
        blurStrategy: BlurStrategy.ADAPTIVE,
        scrollEffectOpts: fnHdsNavChromeScrollEffectOpts(),
        originalStyle: this.titleBarOriginalStyle(),
        scrollEffectStyle: {
          backgroundStyle: fnHdsNavChromeScrolledBackgroundStyle()
        }
      },
      content: this.titleBarContent()
    };
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
      HdsNavigation() {
        this.pageContent()
      }
      .width('100%')
      .height('100%')
      // 整页壳禁用 Auto 分栏，避免平板上内容只显示在左半屏
      .mode(NavigationMode.Stack)
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(this.selectionMode)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .bindToScrollable(this.scrollerList)
      .titleBar(this.titleBarOptions())

      Row()
        .width(40)
        .height(40)
        .margin({ top: this.topSafeInsetVp + 8, right: $r('app.float.hds_title_bar_padding_end') })
        .hitTestBehavior(HitTestMode.None)
        .bindMenu(this.moreMenuExpanded, this.moreMenuBuilder, fnHdsBindMenuOptions(
          Placement.BottomLeft,
          (): void => {
            this.onDismissMoreMenu();
          }
        ))
    }
    .width('100%')
    .height('100%')
  }
}
