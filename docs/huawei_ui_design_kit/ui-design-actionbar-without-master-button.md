# 设置无主按钮的组件

- 页面标题: 设置无主按钮的组件
- slug: `ui-design-actionbar-without-master-button`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-actionbar-without-master-button
- 文档ID: `82cc2f8035d749c08ebca57de80803b6`
- 更新时间: 2026-04-22 06:37:07

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553198747"></a><a name="ZH-CN_TOPIC_0000002553198747"></a>   <h1>设置无主按钮的组件</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553198747__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持设置无主按钮的组件。</p>     <p><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsactionbar" target="_blank">HdsActionBar</a>组件支持多个按钮的样式。当应用开发者需要多个按钮并且没有主按钮，没有展开和收缩的动效时，可以通过设置左按钮和右按钮配置样式。</p>     <p><span><img originheight="113" originwidth="246" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/a3/v3/iwNDCtyWQNewJUze5W1_fA/zh-cn_image_0000002552958348.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083916Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=9A8925B5BF120C300F6BD0328AA4F3EDB6C5AFC04C81C588855FB866D2CF420B"></span></p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553198747__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">import { HdsActionBar, ActionBarButton } from '@kit.UIDesignKit'</pre></li>      <li>       <p>创建左边的按钮数组startButtons，创建右边的按钮数组endButtons，无主按钮，不支持切换展开和收缩状态。</p>       <pre class="typescript">@Entry
@ComponentV2
struct TestNoPrimaryButton {

  build() {
    Column() {
      HdsActionBar({
        startButtons: [new ActionBarButton({
          baseIcon: $r('sys.symbol.stopwatch_fill')
        }), new ActionBarButton({
          baseIcon: $r('sys.symbol.stopwatch_fill')
        })],
        endButtons: [new ActionBarButton({
          baseIcon: $r('sys.symbol.mic_fill')
        })]
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0xF1F3F5)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
