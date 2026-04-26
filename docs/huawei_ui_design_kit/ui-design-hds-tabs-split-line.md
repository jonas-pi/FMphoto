# 设置页签栏的分割线

- 页面标题: 设置页签栏的分割线
- slug: `ui-design-hds-tabs-split-line`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-tabs-split-line
- 文档ID: `58848ec7681546b2b5fd9aea930c92b3`
- 更新时间: 2026-04-22 06:37:02

## 锚点目录

- 场景介绍
- 约束条件
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553358705"></a><a name="ZH-CN_TOPIC_0000002553358705"></a>   <h1>设置页签栏的分割线</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553358705__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持设置页签栏的分割线。</p>     <p><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs" target="_blank">HdsTabs</a>容器组件扩展支持页签栏分割线常隐、常显和渐进显隐。当应用开发者需要分割线一直显示、一直隐藏或者内容区超过页签栏8vp后分割线完全消失时，可以通过设置HdsTabs组件的分割线的模式，同时也支持自定义分割线样式。</p>     <div class="tablenoborder">      <table class="docs-auto">       <thead>        <tr>         <th align="left" class="cellrowborder" id="mcps1.3.1.4.1.4.1.1" valign="top" width="33.33333333333333%">常显</th>         <th align="left" class="cellrowborder" id="mcps1.3.1.4.1.4.1.2" valign="top" width="33.33333333333333%">常隐</th>         <th align="left" class="cellrowborder" id="mcps1.3.1.4.1.4.1.3" valign="top" width="33.33333333333333%">跟手</th>        </tr>       </thead>               <tbody><tr>         <td class="cellrowborder" valign="top" width="33.33333333333333%">          <p><span><img originheight="775" originwidth="384" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/b0/v3/fTult3paQoy2IKgtcJANVw/zh-cn_image_0000002583478341.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=7F48F697847C75B235F416CDC8723BF7F4705E6EEE1CC968BB15132A8F2CDD64"></span></p></td>         <td class="cellrowborder" valign="top" width="33.33333333333333%">          <p><span><img originheight="588" originwidth="291" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/8/v3/Pkv7F1pqSNiNoC5ALLnO2Q/zh-cn_image_0000002552798692.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=4E267BF0A23CCBA89E239A5D55C7EF64CE138FD43999A3EED441A10CF465345B"></span></p></td>         <td class="cellrowborder" valign="top" width="33.33333333333333%">          <p><span><img originheight="588" originwidth="291" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/86/v3/k2tpwK7oQs-OoWSc1HoPTw/zh-cn_image_0000002583438387.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=303284FD6548AA5D58439001EEB45AFF0D187046CBEDCEC7CF0E82CFD8F4B97B"></span></p></td>        </tr>             </tbody></table>     </div>    </div>    <div class="section" id="约束条件">     <a name="ZH-CN_TOPIC_0000002553358705__%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a><a name="%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a>     <h4>约束条件</h4>     <ol>      <li>       <p>将页签栏置于容器的底部且支持模糊，即barPosition设置为BarPosition.End，vertical设置为false和barOverlap设置为true。</p></li>      <li>       <p>分割线模式设置为跟手滑动模式时，跟手滑动效果仅限支持滚动的通用接口的组件，其他类型组件由开发者自己实现。</p></li>      <li>       <p>跟手滑动效果依赖HdsTabs控制器绑定需要设置的list滑动控制器。</p></li>     </ol>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553358705__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">// 从6.0.2(22)版本开始，无需手动导入HdsTabsAttribute。具体请参考HdsTabs的导入模块说明。
import { HdsTabs, HdsTabsController, DividerMode, HdsTabsAttribute } from '@kit.UIDesignKit';</pre></li>      <li>       <p>创建Hds一级容器组件，设置的Button可以切换分割线展示效果，分别是常显、常隐和跟手滑动效果。</p>       <ul>        <li>         <p>初始化list滑动控制器和HdsTabs控制器，将list滑动控制器绑定在HdsTabs控制器上，确保联动，否则跟手滑动没有渐变效果。</p>         <pre class="typescript">  private controller: HdsTabsController = new HdsTabsController();
  listScroller0: ListScroller = new ListScroller();
  listScroller1: ListScroller = new ListScroller();

 aboutToAppear(): void {
    this.controller.bindScroller(0, this.listScroller0);
    this.controller.bindScroller(1, this.listScroller1);
  }

  aboutToDisappear(): void {
    this.controller.unbindScroller(this.listScroller0);
    this.controller.unbindScroller(this.listScroller1);
  }</pre></li>        <li>         <p>设置页签栏置于容器的底部且支持模糊，否则跟手滑动没有渐变效果。</p>         <pre class="typescript"> .barOverlap(true)
 .barPosition(BarPosition.End)
 .vertical(false)
 .divider({
   mode: DividerMode.FOLLOW_SCROLL,
   style: {
     color: Color.Black,
     strokeWidth: 1,
     startMargin: 0,
     endMargin: 0
   }
 })</pre></li>        <li>         <p>跟手滑动效果仅限支持滚动的通用接口的组件，如List，Scroll等。</p>         <pre class="typescript">HdsTabs({ controller: this.controller }) {
        TabContent() {
          List({ scroller: this.listScroller0 }) {} // listScroller是开发者设置的滑动控制器，list子组件可以自定义添加。
        }
        .tabBar({ icon: $r('app.media.startIcon'), text: '页签1' })
        TabContent() {
          List({ scroller: this.listScroller1 }) {}
        }
        .tabBar({ icon: $r('app.media.startIcon'), text: '页签2' })
}</pre></li>       </ul></li>     </ol>    </div>   </div>   <div></div></body></html>
