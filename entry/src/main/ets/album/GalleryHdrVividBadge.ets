/**
 * 原图 HDR Vivid 开启提示。
 * 图标取自官方 HarmonyOS Symbol：hd_square_fill（中文名「HD」）。
 */
@Component
export struct GalleryHdrVividBadge {
  build() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.hd_square_fill'))
        .fontSize(16)
        .fontColor([Color.White])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)

      Text('HDR Vivid')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .padding({ left: 8, right: 10, top: 5, bottom: 5 })
    .backgroundColor('#66000000')
    .borderRadius(8)
    .hitTestBehavior(HitTestMode.None)
  }
}
