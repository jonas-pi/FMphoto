/**
 * 回收站页自己的底部文字入口：「清空回收站」。
 *
 * 不走 GalleryGridChrome 的更多菜单：useMoreMenu 为 true 时右侧「多选」会被挤掉，
 * 而 FnHdsMoreMenu 是各相册页共用组件，改它会波及所有相册页。
 * 只在回收站页内显示：列表非空且不在多选时。
 */
import { GALLERY_BATCH_DESTRUCTIVE_BG } from '../../common/GalleryButtonStyles';

/** 与批量操作条同高 */
export const RECYCLE_BIN_CLEAR_BAR_HEIGHT_VP: number = 48;

@Component
export struct RecycleBinClearBar {
  onClear: () => void = () => {};

  build() {
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
}
