/**
 * 回收站页自己的底部入口：「清空回收站」，圆角胶囊玻璃底。
 *
 * 不走 GalleryGridChrome 的更多菜单：useMoreMenu 为 true 时右侧「多选」会被挤掉，
 * 而 FnHdsMoreMenu 是各相册页共用组件，改它会波及所有相册页。
 * 只在回收站页内显示：列表非空且不在多选时。
 *
 * 关于「沉浸光感」：官方《开启沉浸光感》明确限制——
 *   1. 要求应用 targetSDKVersion 不低于 26.0.0（本工程为 24，全局不生效）；
 *   2. 「其他组件仅在 Navigation/NavDestination 标题栏或横向 Tabs 的底部 TabBar 中生效，
 *      在其他区域中设置沉浸光感效果不生效」。
 * 页面正文里的胶囊属于「其他组件」，因此官方 systemMaterial 在这里拿不到效果；
 * 改用本应用既有的液态玻璃配方（ULTRA_THICK 模糊 + 沉浸底色 + 液态渐变 + 描边 + 阴影），
 * 与顶栏胶囊、底栏 dock 同一套观感。
 *
 * 位置：页面根节点 expandSafeArea 到底部，底边就是系统手势区，
 * 必须按导航条避让区加 padding，否则胶囊落进手势区、与系统导航条重叠
 * （官方 FAQ faqs-tri-fold-1：底部按钮与导航栏重叠，需 padding 避让）。
 */
import { GALLERY_BATCH_DESTRUCTIVE_BG } from '../../common/GalleryButtonStyles';
import { fnImmersiveBackgroundEffect, fnLiquidGlassGradient } from '../../common/FnUiCommon';

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

  build() {
    Column() {
      Row() {
        Text('清空回收站')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(GALLERY_BATCH_DESTRUCTIVE_BG)
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }
      .width(RECYCLE_BIN_CLEAR_PILL_WIDTH_VP)
      .height(RECYCLE_BIN_CLEAR_PILL_HEIGHT_VP)
      // Row 主轴是水平方向：不加这句文字会贴在胶囊左边，看起来整体偏左
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .borderRadius(RECYCLE_BIN_CLEAR_PILL_HEIGHT_VP / 2)
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .backgroundEffect(fnImmersiveBackgroundEffect())
      .linearGradient(fnLiquidGlassGradient())
      .borderWidth(1)
      .borderColor($r('app.color.card_border'))
      .shadow({ radius: 12, color: '#18000000', offsetX: 0, offsetY: 4 })
      .clip(true)
      .onClick((): void => {
        this.onClear();
      })
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 + (this.bottomInsetVp > 0 ? this.bottomInsetVp : 0) })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
