# 设置页签栏的模糊样式

- 页面标题: 设置页签栏的模糊样式
- slug: `ui-design-hds-tabs-fuzzy-style`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-tabs-fuzzy-style
- 文档ID: `aded337a6f834d49baadc2106af22a38`
- 更新时间: 2026-04-22 06:37:07

## 锚点目录

- 场景介绍
- 约束条件
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002522238782"></a><a name="ZH-CN_TOPIC_0000002522238782"></a>   <h1>设置页签栏的模糊样式</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002522238782__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持设置页签栏的模糊样式。</p>     <p><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs" target="_blank">HdsTabs</a>容器组件扩展支持页签栏设置直接模糊和渐变模糊效果。</p>     <ul>      <li>       <p>直接模糊</p>       <p><span><img originheight="133" originwidth="328" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/bd/v3/lx6un6RQTZKnVBRUrN_uFg/zh-cn_image_0000002552958342.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=08F15494ED6905512DC190B1BD9B9E8A2D3784E34209835F232323BF63BA1333"></span></p></li>      <li>       <p>渐变模糊</p>       <p><span><img originheight="207" originwidth="325" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/94/v3/T_qHLepBTNSk__JN4Wzcbg/zh-cn_image_0000002583478343.jpg?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=39DBCB6DEAE5F30594B213A35544C5224364F0BEA312099FABA82695591037C7"></span></p></li>     </ul>    </div>    <div class="section" id="约束条件">     <a name="ZH-CN_TOPIC_0000002522238782__%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a><a name="%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a>     <h4>约束条件</h4>     <ol>      <li>       <p>依赖页签栏位于容器底部，barPosition设置为BarPosition.End，vertical设置为false。</p></li>      <li>       <p>TabBar叠加在TabContent之上，barOverlap设置为true。</p></li>      <li>       <p>去掉TabBar节点，barBackgroundBlurStyle默认设置的模糊的属性值为BlurStyle.NONE。</p></li>     </ol>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002522238782__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">// 从6.0.2(22)版本开始，无需手动导入HdsTabsAttribute。具体请参考HdsTabs的导入模块说明。
import { HdsTabs, HdsTabsAttribute, HdsTabsController } from '@kit.UIDesignKit';</pre></li>      <li>       <p>创建Hds一级容器组件，设置HdsTabs组件的barBackgroundStyle样式，可以自定义模糊的颜色和高度，实现渐变模糊。</p>       <div class="note">        <img originheight="38" originwidth="102" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/27/v3/9v9ZisohSgiqwqB4S2WwbA/note_3.0-zh-cn.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=D4E889BE479081114D3C348939EC571E5D8A6ED978A4CD0569EF378F306C196E"><span class="notetitle"> </span>        <div class="notebody">         <ol>          <li>当开发者通过Tabs组件属性barBackgroundBlurStyle设置模糊时，HdsTabs的默认模糊效果失效。</li>          <li>当开发者通过Tabs组件属性barBackgroundEffect设置模糊时，HdsTabs的默认模糊效果失效。</li>          <li>当开发者通过Tabs组件属性barBackgroundColor设置背景色时，HdsTabs的默认模糊效果只有模糊半径生效，模糊半径为80vp。</li>         </ol>        </div>       </div>       <pre class="typescript">@Entry
@Component
struct Index {
  private controller: HdsTabsController = new HdsTabsController();

  build() {
    Column() {
      HdsTabs({ controller: this.controller }) {
        TabContent() {
          Column().width('100%').height('100%').backgroundColor(Color.Pink)
        }
        .tabBar({ icon: $r('app.media.startIcon'), text: '页签1' })

        TabContent() {
          Column().width('100%').height('100%').backgroundColor(Color.Blue)
        }
        .tabBar({ icon: $r('app.media.startIcon'), text: '页签2' })
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barBackgroundStyle({
        maskColor: Color.Yellow,
        maskHeight: 80
      })
    }
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
