# 标题栏动态显隐

- 页面标题: 标题栏动态显隐
- slug: `ui-design-navigation-dynamic-display-and-hiding`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-dynamic-display-and-hiding
- 文档ID: `66ec9b3d0d0e4f5b85d63ebda65ae106`
- 更新时间: 2026-04-22 06:37:13

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553198737"></a><a name="ZH-CN_TOPIC_0000002553198737"></a>   <h1>标题栏动态显隐</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553198737__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20)版本开始，导航组件新增支持设置标题栏动态显隐功能。</p>     <p>用于实现标题栏在特定条件下自动显示或隐藏的效果，适用于需要节省屏幕空间的应用界面。当应用开发者需要动态隐藏标题栏时，可通过使用<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation#dynamichidetitlebar" target="_blank">dynamicHideTitleBar</a>属性实现该功能。在设置动态隐藏标题栏的前提下，才可进一步设置隐藏状态栏。隐藏状态栏表现为状态栏内容区颜色为透明，状态栏区域无模糊。仅在隐藏标题栏区域后，执行隐藏状态栏。</p>     <p><span><img height="626.8202220000001" originheight="664" originwidth="317" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/14/v3/C5JJso8wRWuBJQ7NcENosg/zh-cn_image_0000002583438381.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083914Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=E8E8D8FA0FBC815C21E85B81ECF8D715D2CB91F44A4DA5E92AA909F677F6566A" title="点击放大" width="299.25"></span></p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553198737__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">// 从6.0.2(22)版本开始，无需手动导入HdsNavigationAttribute。具体请参考HdsNavigation的导入模块说明。
import { HdsNavigation, BottomBuilderShowType, HideMode, HdsNavigationAttribute, HdsNavigationTitleMode } from '@kit.UIDesignKit';</pre></li>      <li>       <p>创建一级导航组件，通过设置dynamicHideTitleBar属性，可隐藏状态栏、标题区域、BottomBuilder区域。</p>       <pre class="typescript">@Entry
@Component
struct Index {
  scroller: Scroller = new Scroller();
  private arr: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];

  @Builder
  bottomBuilder() {
    Column() {
      Search({ placeholder: 'Search' })
        .height(40)
        .placeholderColor($r('sys.color.font_primary'))
        .margin({ left: 16, right: 16 })
    }
    .width('100%')
  }

  build() {
    HdsNavigation() { // 创建HdsNavigation组件
      List({ space: 12, initialIndex: 0, scroller: this.scroller }) {
        ForEach(this.arr, (item: number) =&gt; {
          ListItem() {
            Column() {
              Row({ space: 8 }) {
                Button() {
                  SymbolGlyph($r('sys.symbol.wifi'))
                    .fontColor([$r('sys.color.icon_on_primary')])
                    .fontSize(24)
                }
                .width(35)
                .height(35)

                Text('list_' + item)
                  .width('100%')
                  .height(72)
                  .fontSize(16)
                  .fontWeight(500)
              }

              Divider().margin({ left: 40 })
            }
          }
          .height(56)
        }, (item: number) =&gt; item.toString())
      }
      .margin({ left: 16, right: 16 })
      .clip(false) // 设置不对子组件超出当前组件范围外的区域进行裁剪，使内容区可以穿透到标题栏下方
      .cachedCount(3, true) // 设置列表中ListItem/ListItemGroup的预加载数量，列表穿透到标题栏下方不会消失
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .titleBar({
      content: {
        title: { mainTitle: 'MainTitle' },
        // 设置HdsNavigation BottomBuilder区域，包括设置高度，显示类型
        bottomBuilder: {
          builder: (): void =&gt; this.bottomBuilder(),
          height: 56,
          showType: BottomBuilderShowType.DIRECTLY_SHOW
        }
      },
      enableComponentSafeArea: true, // 将标题栏设置为组件级安全区，内容区可避让标题栏
    })
    .bindToScrollable([this.scroller]) // 绑定导航组件和可滚动容器组件
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    // 设置HdsNavigation标题栏动态显隐，包括设置标题区域，bottomBuilder区域，状态栏区域是否动态隐藏，隐藏模式以及开始隐藏时内容区的滚动距离。
    .dynamicHideTitleBar({
      hideTitleArea: true,
      hideBottomBuilder: true,
      hideStatusBar: false,
      mode: HideMode.SCROLL_UP_TO,
      hideOffset: 10
    })
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
