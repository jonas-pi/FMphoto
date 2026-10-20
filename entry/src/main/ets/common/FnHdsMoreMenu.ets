/**
 * 图库「更多」菜单：各页同一顺序。
 * 多选 → 上传 → 同步 → 幻灯片 → 跳转到文件夹视图 → 返回来源（缺项跳过，不重排）。
 */
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { fnHdsBindMenuOptions } from './FnHdsOverlay';

/**
 * 更多菜单的展开状态。
 * 不放进标题栏所在组件的 @State：一点击就重建 titleBar，菜单按钮的按压动画只会播放一次。
 */
export class FnHdsMoreMenuHandle {
  expanded: boolean = false;
  private applyExpanded: (value: boolean) => void = (_value: boolean): void => {
  };

  bind(applyExpanded: (value: boolean) => void): void {
    this.applyExpanded = applyExpanded;
    applyExpanded(this.expanded);
  }

  unbind(applyExpanded: (value: boolean) => void): void {
    if (this.applyExpanded === applyExpanded) {
      this.applyExpanded = (_value: boolean): void => {
      };
    }
  }

  toggle(): void {
    this.setExpanded(!this.expanded);
  }

  dismiss(): void {
    this.setExpanded(false);
  }

  setExpanded(value: boolean): void {
    if (this.expanded === value) {
      return;
    }
    this.expanded = value;
    this.applyExpanded(value);
  }
}

@Component
export struct FnHdsMoreMenuAnchor {
  @Prop expanded: boolean = false;
  @Prop topSafeInsetVp: number = 0;
  @Prop showMultiselect: boolean = false;
  @Prop showUpload: boolean = false;
  @Prop showSync: boolean = false;
  @Prop syncBadgeCount: number = 0;
  @Prop showSlideshow: boolean = false;
  @Prop showJumpToFolder: boolean = false;
  @Prop showReturnToSource: boolean = false;
  onDismiss: () => void = () => {};
  onMultiselect: () => void = () => {};
  onUpload: () => void = () => {};
  onSync: () => void = () => {};
  onSlideshow: () => void = () => {};
  onJumpToFolder: () => void = () => {};
  onReturnToSource: () => void = () => {};

  @Builder
  private moreMenuBuilder() {
    Menu() {
      if (this.showMultiselect) {
        MenuItem({ content: '多选' })
          .onClick((): void => {
            this.onMultiselect();
          })
      }
      if (this.showUpload) {
        MenuItem({ content: '上传' })
          .onClick((): void => {
            this.onUpload();
          })
      }
      if (this.showSync) {
        if (this.syncBadgeCount > 0) {
          MenuItem({
            content: '同步',
            symbolEndIcon: new SymbolGlyphModifier($r('sys.symbol.circle_fill'))
              .fontSize(10)
              .fontColor(['#FFE11D48'])
          })
            .onClick((): void => {
              this.onSync();
            })
        } else {
          MenuItem({ content: '同步' })
            .onClick((): void => {
              this.onSync();
            })
        }
      }
      if (this.showSlideshow) {
        MenuItem({ content: '幻灯片' })
          .onClick((): void => {
            this.onSlideshow();
          })
      }
      if (this.showJumpToFolder) {
        MenuItem({ content: '跳转到文件夹视图' })
          .onClick((): void => {
            this.onJumpToFolder();
          })
      }
      if (this.showReturnToSource) {
        MenuItem({ content: '返回来源' })
          .onClick((): void => {
            this.onReturnToSource();
          })
      }
    }
  }

  build() {
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
}

/** 只刷新菜单锚点，不带动标题栏重绘。 */
@Component
export struct FnHdsMoreMenuHost {
  menuHandle: FnHdsMoreMenuHandle = new FnHdsMoreMenuHandle();
  @Prop topSafeInsetVp: number = 0;
  @Prop showMultiselect: boolean = false;
  @Prop showUpload: boolean = false;
  @Prop showSync: boolean = false;
  @Prop syncBadgeCount: number = 0;
  @Prop showSlideshow: boolean = false;
  @Prop showJumpToFolder: boolean = false;
  @Prop showReturnToSource: boolean = false;
  onDismiss: () => void = () => {};
  onMultiselect: () => void = () => {};
  onUpload: () => void = () => {};
  onSync: () => void = () => {};
  onSlideshow: () => void = () => {};
  onJumpToFolder: () => void = () => {};
  onReturnToSource: () => void = () => {};
  @State private expanded: boolean = false;
  private boundApply: (value: boolean) => void = (_value: boolean): void => {
  };

  aboutToAppear(): void {
    const self = this;
    this.boundApply = (value: boolean): void => {
      self.expanded = value;
    };
    this.menuHandle.bind(this.boundApply);
  }

  aboutToDisappear(): void {
    this.menuHandle.unbind(this.boundApply);
  }

  build() {
    FnHdsMoreMenuAnchor({
      expanded: this.expanded,
      topSafeInsetVp: this.topSafeInsetVp,
      showMultiselect: this.showMultiselect,
      showUpload: this.showUpload,
      showSync: this.showSync,
      syncBadgeCount: this.syncBadgeCount,
      showSlideshow: this.showSlideshow,
      showJumpToFolder: this.showJumpToFolder,
      showReturnToSource: this.showReturnToSource,
      onDismiss: (): void => {
        this.menuHandle.dismiss();
        this.onDismiss();
      },
      onMultiselect: (): void => {
        this.onMultiselect();
      },
      onUpload: (): void => {
        this.onUpload();
      },
      onSync: (): void => {
        this.onSync();
      },
      onSlideshow: (): void => {
        this.onSlideshow();
      },
      onJumpToFolder: (): void => {
        this.onJumpToFolder();
      },
      onReturnToSource: (): void => {
        this.onReturnToSource();
      }
    })
  }
}
