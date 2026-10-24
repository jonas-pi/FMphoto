/**
 * 回收站页自己的底部文字入口：「清空回收站」。
 *
 * 不走 GalleryGridChrome 的更多菜单：useMoreMenu 为 true 时右侧「多选」会被挤掉，
 * 而 FnHdsMoreMenu 是各相册页共用组件，改它会波及所有相册页。
 * 只在回收站页内显示：列表非空且不在多选时。
 *
 * 位置：页面根节点 expandSafeArea 到底部，底边就是系统手势区，
 * 所以必须按导航条避让区加 padding，否则文字落进手势区、与系统导航条重叠
 * （官方 FAQ faqs-tri-fold-1：底部按钮与导航栏重叠，需 padding 避让）。
 */
import { GALLERY_BATCH_DESTRUCTIVE_BG } from '../../common/GalleryButtonStyles';

/** 文字按钮本身的高度（不含导航条避让） */
export const RECYCLE_BIN_CLEAR_BAR_HEIGHT_VP: number = 48;

/** 底部入口占位总高度：文字按钮 + 导航条避让，供列表底部留白使用 */
export function recycleBinClearBarTotalHeightVp(bottomInsetVp: number): number {
  const inset: number = bottomInsetVp > 0 ? bottomInsetVp : 0;
  return RECYCLE_BIN_CLEAR_BAR_HEIGHT_VP + inset;
}

@Component
export struct RecycleBinClearBar {
  /** 导航条 / 手势区避让高度 */
  @Prop bottomInsetVp: number = 0;
  onClear: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text('清空回收站')
          .fontSize(14)
          .fontColor(GALLERY_BATCH_DESTRUCTIVE_BG)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick((): void => {
            this.onClear();
          })
      }
      .width('100%')
      .height(RECYCLE_BIN_CLEAR_BAR_HEIGHT_VP)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ bottom: this.bottomInsetVp > 0 ? this.bottomInsetVp : 0 })
  }
}
