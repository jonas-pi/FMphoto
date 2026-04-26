# 按压阴影

- 页面标题: 按压阴影
- slug: `ui-design-visual-effect-background-color`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-visual-effect-background-color
- 文档ID: `145ba87188684b7cbb1b17251eab03f7`
- 更新时间: 2026-04-22 06:37:07

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553198751"></a><a name="ZH-CN_TOPIC_0000002553198751"></a>   <h1>按压阴影</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553198751__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdseffect#pressshadow" target="_blank">按压阴影</a>。</p>     <p>通过按压阴影接口可以设置组件的背景色变化效果，一般常用于组件按压交互时的背景色变化场景。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553198751__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入模块。</p>       <pre class="typescript">import { hdsEffect } from '@kit.UIDesignKit';</pre></li>      <li>       <p>创建按压阴影效果。</p>       <pre class="typescript">@Entry
@Component
struct PressShadowExample {
  @State button_blend_state: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;
  @State button_gradient_state: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;

  build() {
    NavDestination() {
      Column({ space: 50 }) {
        Button("BLEND_WHITE", { buttonStyle: ButtonStyleMode.EMPHASIZED, role: ButtonRole.ERROR, stateEffect: false })
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pressShadow(this.button_blend_state)
            .buildEffect())
          .onTouch((event: TouchEvent) =&gt; {
            if (event.type === TouchType.Down) {
              this.button_blend_state =  hdsEffect.PressShadowType.BLEND_WHITE;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.button_blend_state =  hdsEffect.PressShadowType.NONE;
            }
          })

        Button("GRADIENT", { buttonStyle: ButtonStyleMode.NORMAL, stateEffect: false })
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pressShadow(this.button_gradient_state)
            .buildEffect())
          .onTouch((event: TouchEvent) =&gt; {
            if (event.type === TouchType.Down) {
              this.button_gradient_state =  hdsEffect.PressShadowType.BLEND_GRADIENT;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.button_gradient_state =  hdsEffect.PressShadowType.NONE;
            }
          })
      }
      .height('70%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .title('Button example')
    .backgroundColor('#040404')
  }
}</pre>       <p><span><img originheight="193" originwidth="236" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/b3/v3/XpcNAviGQ9ue7AgTFZzIlw/zh-cn_image_0000002583438397.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083917Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=8B44E8F12642B141739B93AE9D8876936F6BAE6C01DAF9C7A89A6E410690F3EE"></span></p></li>     </ol>    </div>   </div>   <div></div></body></html>
