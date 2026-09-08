/**
 * 图库「更多」菜单：各页同一顺序。
 * 多选 → 上传 → 幻灯片 → 跳转到文件夹视图（缺项跳过，不重排）。
 */
import { fnHdsBindMenuOptions } from './FnHdsOverlay';

@Component
export struct FnHdsMoreMenuAnchor {
  @Prop expanded: boolean = false;
  @Prop topSafeInsetVp: number = 0;
  @Prop showMultiselect: boolean = false;
  @Prop showUpload: boolean = false;
  @Prop showSlideshow: boolean = false;
  @Prop showJumpToFolder: boolean = false;
  onDismiss: () => void = () => {};
  onMultiselect: () => void = () => {};
  onUpload: () => void = () => {};
  onSlideshow: () => void = () => {};
  onJumpToFolder: () => void = () => {};

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
