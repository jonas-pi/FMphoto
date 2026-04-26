# 设置页签栏的悬浮样式

- 页面标题: 设置页签栏的悬浮样式
- slug: `ui-design-hds-tabs-bar-floating`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-tabs-bar-floating
- 文档ID: `777ff09ce79c45dbae27677be4b29120`
- 更新时间: 2026-04-22 06:37:15

## 锚点目录

- 场景介绍
- 页签栏
- 迷你栏
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553358707"></a><a name="ZH-CN_TOPIC_0000002553358707"></a>  <h1>设置页签栏的悬浮样式</h1> <div> <div class="section" id="场景介绍"><a name="ZH-CN_TOPIC_0000002553358707__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><h4>场景介绍</h4><p>从6.1.0(23) 版本开始，新增支持设置页签栏的悬浮样式以及迷你栏。</p> </div>  <div class="section" id="页签栏"><a name="ZH-CN_TOPIC_0000002553358707__%E9%A1%B5%E7%AD%BE%E6%A0%8F"></a><a name="%E9%A1%B5%E7%AD%BE%E6%A0%8F"></a><h4>页签栏</h4><p>页签栏悬浮样式如下图所示：</p> <p><span><img originheight="131" originwidth="415" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/f8/v3/-eAAl2kLTVOJTn-vkXyuqA/zh-cn_image_0000002552798696.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=2AA622C2C8ECE849DB3BECC8CD1697C4E527E39B6B479E3ABB483338D2976BFA"></span></p> </div>  <div class="section" id="迷你栏"><a name="ZH-CN_TOPIC_0000002553358707__%E8%BF%B7%E4%BD%A0%E6%A0%8F"></a><a name="%E8%BF%B7%E4%BD%A0%E6%A0%8F"></a><h4>迷你栏</h4><p>迷你栏是新增的自定义区域，跟页签栏高度相等且水平对齐，支持展开和折叠两种样式。</p> <p>迷你栏的折叠样式如下图所示：</p> <p><span><img originheight="220" originwidth="452" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/6b/v3/gn7OvdIlRCalIuPq6as4Qw/zh-cn_image_0000002583438391.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=FD61DB9ECFCDD99B60975FAD60FFF04A773AA13C32D98B71C8E4B08DA7B3D98A"></span></p> <p>迷你栏的展开样式如下图所示：</p> <p><span><img originheight="149" originwidth="470" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/90/v3/8ItPrwkIS_ypLG-OWCaL8A/zh-cn_image_0000002552958346.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=A59F21DADFCBD9F660F38765B6DF09F461BAACFCABE874E22C1CDB2A16A7350B"></span></p> </div>  <div class="section" id="开发步骤"><a name="ZH-CN_TOPIC_0000002553358707__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><h4>开发步骤</h4><ol><li><p>导入相关模块。</p>  <pre class="typescript"> // 从6.0.2(22)版本开始，无需手动导入HdsTabsAttribute。具体请参考HdsTabs的导入模块说明。
 import { hdsMaterial } from '@hms.hds.hdsMaterial'
 import { HdsTabs, HdsTabsAttribute, HdsTabsController } from '@kit.UIDesignKit';</pre>  </li><li><p>创建Hds一级容器组件，设置HdsTabs组件的barFloatingStyle样式，并设置barOverlap为true，vertical为false，barPosition为BarPosition.End，可实现页签栏的悬浮样式。若在barFloatingStyle中设置miniBar，则可实现迷你栏。</p>  <pre class="typescript">@Entry
@Component
struct Index {
  // 初始化HdsTabs控制器。
  private controller: HdsTabsController = new HdsTabsController();

  @Builder
  tabContentBuilder(color: Color) {
    List() {
      ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], (item: number) =&gt; {
        ListItem() {
          Column() {
            Row() {
            }.height(200)
            .width('100%')

            Row() {
            }.width('100%')
            .height(50)
            .background(color)
          }
        }
      })
    }
  }

  @Builder
  miniBarBuilder() {
    Row() {
      Column() {
        Image($r('app.media.alarm_stop'))
          .width(40)
          .height(40)
          .borderRadius(40)
      }.width(48).height(48).justifyContent(FlexAlign.Center)

      Text('Hello')

      Column() {
        Image($r('sys.media.ohos_ic_public_pause'))
          .width(40)
          .height(40)
          .borderRadius(40)
      }.width(48).height(48).justifyContent(FlexAlign.Center)
    }
  }

  build() {
    Column() {
      HdsTabs({ controller: this.controller }) {
        TabContent() {
          this.tabContentBuilder(Color.Green)
        }
        .tabBar(new BottomTabBarStyle($r('sys.media.ohos_ic_public_clock'), 'Green'))

        TabContent() {
          this.tabContentBuilder(Color.Blue)
        }
        .tabBar(new BottomTabBarStyle($r('sys.media.wifi_router_fill'), 'Blue'))

        TabContent() {
          this.tabContentBuilder(Color.Yellow)
        }
        .tabBar(new BottomTabBarStyle($r('sys.media.ohos_ic_public_clock'), 'Yellow'))
      }
      // 设置barOverlap为true，vertical为false，barPosition为BarPosition.End
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      // 设置页签栏悬浮样式。
      .barFloatingStyle({
        barWidth: { smallWidth: 200, mediumWidth: 300, largeWidth: 400 },
        barBottomMargin: 28,
        gradientMask: { maskColor: '#66F1F3F5', maskHeight: 92 },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        // 设置迷你栏，若不设置，则仅有页签栏。
        miniBar: {
          miniBarBuilder: () =&gt; this.miniBarBuilder()
        }
      })
    }
  }
}</pre>  </li></ol> </div> </div> <div></div></body></html>
