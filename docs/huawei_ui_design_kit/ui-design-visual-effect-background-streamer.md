# 背景流光

- 页面标题: 背景流光
- slug: `ui-design-visual-effect-background-streamer`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-visual-effect-background-streamer
- 文档ID: `7742156becc94d44a7aaa36e54fcecbe`
- 更新时间: 2026-04-22 06:37:13

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553358715"></a><a name="ZH-CN_TOPIC_0000002553358715"></a>   <h1>背景流光</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553358715__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdseffect#effecttype" target="_blank">背景流光</a>。</p>     <p>通过背景流光接口可以设置组件的背景流动发光效果，并且可以设置背景色及渐变背景色，常用于全屏幕背景流光等。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553358715__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入模块。</p>       <pre class="typescript">import { hdsEffect } from '@kit.UIDesignKit';</pre></li>      <li>       <p>设置背景流光效果。</p>       <pre class="typescript">@Entry
@Component
struct UVFlowLight {
  @State controller: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();

  build() {
    Stack() {
    }
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .shaderEffect({
        effectType: hdsEffect.EffectType.UV_BACKGROUND_FLOW_LIGHT,
        animation: {
          duration: 10000,
          iterations: -1,
          autoPlay: true,
          onFinish: ()=&gt; {
            console.info('Succeeded in finishing');
          }
        },
        controller: this.controller,
      })
      .buildEffect())
    .width('100%')
    .height('100%')
  }
}</pre>       <p><span><img originheight="527" originwidth="269" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/68/v3/lnwWxemGTCufrinW7Im4Qw/zh-cn_image_0000002583478353.jpg?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083917Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=5E80F03170AEE8F70C11ED8CC6C5A3C46E059732086985188882FA1843C4C128"></span></p></li>     </ol>    </div>   </div>   <div></div></body></html>
