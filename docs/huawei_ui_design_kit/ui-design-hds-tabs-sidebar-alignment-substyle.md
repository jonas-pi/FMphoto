# 设置侧边栏半屏居中对齐样式

- 页面标题: 设置侧边栏半屏居中对齐样式
- slug: `ui-design-hds-tabs-sidebar-alignment-substyle`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-tabs-sidebar-alignment-substyle
- 文档ID: `c5bdeef605e844d38a50a17c47d4c74a`
- 更新时间: 2026-04-22 06:37:13

## 锚点目录

- 场景介绍
- 约束条件
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002522078782"></a><a name="ZH-CN_TOPIC_0000002522078782"></a>   <h1>设置侧边栏半屏居中对齐样式</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002522078782__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持设置侧边栏半屏居中对齐样式。</p>     <p><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs" target="_blank">HdsTabs</a>容器组件侧边栏支持半屏居中对齐布局。横向Tabs时，若没有主动设置TabBar高度，则TabBar默认高度为48vp，纵向TabBar默认宽度为96vp，barHeight设成固定值后，TabBar无法扩展底部安全区。当safeAreaPadding不设置bottom或者bottom设置为0时，可以实现扩展安全区。</p>     <ul>      <li>       <p>半屏居中对齐布局</p>       <p><span><img originheight="452" originwidth="281" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/d5/v3/6Rq_n1IUQVGbTHo1VFuUqg/zh-cn_image_0000002583438389.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=858D35019C13DE1B22AA75897211D8AAE3FC6A74353B0225637E7C981F3253EA"></span></p></li>      <li>       <p>默认横向和纵向宽度</p>       <p><span><img originheight="759" originwidth="451" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/0a/v3/ry9YJuokQkeIUedAAVTduA/zh-cn_image_0000002552958344.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=10D951FF335B1628DAF29B6EDFE258AC91554088B936B1F8BD3C0245EB57CBD8"></span></p>       <p><span><img originheight="128" originwidth="451" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/93/v3/C_YyOwRQR76M1-N_JvrTNg/zh-cn_image_0000002583478345.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=56D6DA5C3C81E9A690D587A268E40950937DCBA40B1BE6A725080CE683BD7739"></span></p></li>     </ul>    </div>    <div class="section" id="约束条件">     <a name="ZH-CN_TOPIC_0000002522078782__%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a><a name="%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a>     <h4>约束条件</h4>     <ol>      <li>       <p>依赖页签位于侧边栏，vertical设置为true。</p></li>      <li>       <p>页签使用BottomTabBarStyle样式。</p></li>     </ol>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002522078782__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">// 从6.0.2(22)版本开始，无需手动导入HdsTabsAttribute。具体请参考HdsTabs的导入模块说明。
import { HdsTabs, ExtendBarMode, HdsTabsAttribute } from '@kit.UIDesignKit';</pre></li>      <li>       <p>创建Hds一级容器组件，设置HdsTabs组件的barMode样式为ExtendBarMode.HALF_SCREEN_FIXED，所有页签总高度之和为HdsTabs组件高度的四分之一，且处在二分之一屏的居中位置。</p>       <pre class="typescript">@Entry
@Component
struct Index {
  @State isVertical: boolean = false;

  build() {
    Column() {
      Column() {
        Row() {
          Button('verticalChange')
            .onClick(() =&gt; {
              this.isVertical = !this.isVertical;
            })
        }
      }
      .margin({ top: 20 })
      .width('100%')
      .height('10%')
      HdsTabs({ barPosition: BarPosition.End }) {
        TabContent() {
          Column().width('100%').height('100%').backgroundColor(Color.Yellow)
        }
        .tabBar(new BottomTabBarStyle($r('sys.media.ohos_app_icon'), 'Yellow'))
        TabContent() {
          Column().width('100%').height('100%').backgroundColor(Color.Blue)
        }
        .tabBar(new BottomTabBarStyle($r('sys.media.ohos_app_icon'), 'Blue'))
        TabContent() {
          Column().width('100%').height('100%').backgroundColor(Color.Pink)
        }
        .tabBar(new BottomTabBarStyle($r('sys.media.ohos_app_icon'), 'Pink'))
      }
      .vertical(this.isVertical)
      .barMode(ExtendBarMode.HALF_SCREEN_FIXED)
      .width('100%')
      .height('90%')
    }
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
