/**
 * 回收站页自己的底部入口：「清空回收站」，圆角胶囊 + 沉浸光感。
 *
 * 不走 GalleryGridChrome 的更多菜单：useMoreMenu 为 true 时右侧「多选」会被挤掉，
 * 而 FnHdsMoreMenu 是各相册页共用组件，改它会波及所有相册页。
 * 只在回收站页内显示：列表非空且不在多选时。
 *
 * 沉浸光感走官方通用属性 .systemMaterial()（官方《组件适配沉浸光感》「按钮与选择类组件」：
 * 材质取较薄样式 THIN）。该属性开启后主动设置的背景色/模糊不再生效，
 * 所以有材质时只画文字，无材质（低版本 SDK）才退回半透明底。
 *
 * 位置：页面根节点 expandSafeArea 到底部，底边就是系统手势区，
 * 必须按导航条避让区加 padding，否则胶囊落进手势区、与系统导航条重叠
 * （官方 FAQ faqs-tri-fold-1：底部按钮与导航栏重叠，需 padding 避让）。
 */
import { uiMaterial } from '@kit.ArkUI';
import { GALLERY_BATCH_DESTRUCTIVE_BG } from '../../common/GalleryButtonStyles';
import { fnHdsPillSystemMaterial } from '../../common/FnHdsOverlay';

/** 胶囊高度（不含导航条避让） */
export const RECYCLE_BIN_CLEAR_PILL_HEIGHT_VP: number = 40;
export const RECYCLE_BIN_CLEAR_PILL_WIDTH_VP: number = 148;
/** 底部区域总高度：胶囊 + 上下呼吸 + 导航条避让，供列表底部留白使用 */
export function recycleBinClearBarTotalHeightVp(bottomInsetVp: number): number {
  const inset: number = bottomInsetVp > 0 ? bottomInsetVp : 0;
  return RECYCLE_BIN_CLEAR_PILL_HEIGHT_VP + 16 + inset;
}

@Component
export struct RecycleBinClearBar {
  /** 导航条 / 手势区避让高度 */
  @Prop bottomInsetVp: number = 0;
  onClear: () => void = () => {};

  private pillMaterial(): uiMaterial.Material | undefined {
    return fnHdsPillSystemMaterial();
  }

  @Builder
  private pillLabel() {
    Text('清空回收站')
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(GALLERY_BATCH_DESTRUCTIVE_BG)
      .textAlign(TextAlign.Center)
      .maxLines(1)
  }

  build() {
    Column() {
      if (this.pillMaterial() !== undefined) {
        // 有沉浸材质：不要再设背景色/模糊，否则会盖住材质
        Row() {
          this.pillLabel()
        }
        .width(RECYCLE_BIN_CLEAR_PILL_WIDTH_VP)
        .height(RECYCLE_BIN_CLEAR_PILL_HEIGHT_VP)
        .borderRadius(RECYCLE_BIN_CLEAR_PILL_HEIGHT_VP / 2)
        .clip(true)
        .systemMaterial(this.pillMaterial())
        .onClick((): void => {
          this.onClear();
        })
      } else {
        // 低版本 SDK 回退：半透明底，保持胶囊形状
        Row() {
          this.pillLabel()
        }
        .width(RECYCLE_BIN_CLEAR_PILL_WIDTH_VP)
        .height(RECYCLE_BIN_CLEAR_PILL_HEIGHT_VP)
        .borderRadius(RECYCLE_BIN_CLEAR_PILL_HEIGHT_VP / 2)
        .clip(true)
        .backgroundColor('#D9FFFFFF')
        .borderWidth(1)
        .borderColor($r('app.color.card_border'))
        .onClick((): void => {
          this.onClear();
        })
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 + (this.bottomInsetVp > 0 ? this.bottomInsetVp : 0) })
    .justifyContent(FlexAlign.Center)
  }
}
