# 设置页签的图标出血样式

- 页面标题: 设置页签的图标出血样式
- slug: `ui-design-hds-tabs-icon-bleed-substyle`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-tabs-icon-bleed-substyle
- 文档ID: `b0772a0952e74cd395e49c35a44b152a`
- 更新时间: 2026-04-22 06:37:10

## 锚点目录

- 场景介绍
- 约束条件
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553198743"></a><a name="ZH-CN_TOPIC_0000002553198743"></a>   <h1>设置页签的图标出血样式</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553198743__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持设置页签的图标出血样式。</p>     <p><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs" target="_blank">HdsTabs</a>容器组件扩展支持出血图标样式。当应用开发者需要tabBar内的页签高度超出tabBar时，可以通过设置对应页签的属性，添加出血效果的自定义组件，图标超出容器部分最大高度为4vp。</p>     <p><span><img originheight="111" originwidth="377" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/1a/v3/rmvJG0Y1QUi-nf31B-SiFQ/zh-cn_image_0000002552798694.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=2A354A0C09609243EAA7640746383300408D5CD7C2786F18D5128CEB903B52D7"></span></p>    </div>    <div class="section" id="约束条件">     <a name="ZH-CN_TOPIC_0000002553198743__%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a><a name="%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a>     <h4>约束条件</h4>     <p>依赖页签栏位于容器底部，barPosition设置为BarPosition.End，vertical设置为false。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553198743__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">// 从6.0.2(22)版本开始，无需手动导入HdsTabsAttribute。具体请参考HdsTabs的导入模块说明。
import { HdsTabs, HdsTabsAttribute } from '@kit.UIDesignKit';
import { bleedIconStyle } from '@hms.hds.HdsStyle';</pre></li>      <li>       <p>创建Hds一级容器组件，设置HdsTabs组件的子组件TabContent的tabBar样式。</p>       <pre class="typescript">@Entry
@Component
struct Index {
  build() {
    Stack() {
      HdsTabs() {
        TabContent() {
          Column().width('100%').height('100%').backgroundColor(Color.Yellow)
        }
        .tabBar(bleedIconStyle(() =&gt; {
          this.tabBuilder()
        }))
        TabContent() {
          Column().width('100%').height('100%').backgroundColor(Color.Blue)
        }
        .tabBar(this.tabBuilder())
      }
      .vertical(false)
      .barPosition(BarPosition.End)
    }
  }

  @Builder
  tabBuilder() {
    Column() {
      Image($r('app.media.startIcon'))
        .width(48)
        .height(48)
        .borderRadius(24)
    }
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
