# 双边边缘流光

- 页面标题: 双边边缘流光
- slug: `ui-design-visual-effect-double-edge-streamer`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-visual-effect-double-edge-streamer
- 文档ID: `db1a584f21524583a2ec631e6ca43f88`
- 更新时间: 2026-04-22 06:37:10

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002522078792"></a><a name="ZH-CN_TOPIC_0000002522078792"></a>   <h1>双边边缘流光</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002522078792__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdseffect#effecttype" target="_blank">双边边缘流光</a>。</p>     <p>通过双边边缘流光接口可以设置组件的边缘发光效果，并且可以设置两条边的起始、终止位置和边缘颜色效果，常用于胶囊组件、屏幕边缘发光等。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002522078792__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入模块。</p>       <pre class="typescript">import { hdsEffect } from '@kit.UIDesignKit';</pre></li>      <li>       <p>设置双边边缘流光效果。</p>       <pre class="typescript">@Entry
@Component
struct Index {
  @State controller: hdsEffect.ShaderEffectController = new hdsEffect.ShaderEffectController();

  build() {
    Column() {
      Stack() {
      }
      .visualEffect(new hdsEffect.HdsEffectBuilder()
        .shaderEffect({
          effectType: hdsEffect.EffectType.DUAL_EDGE_FLOW_LIGHT,
          animation: {
            duration: 4000,
            iterations: -1,
            autoPlay: true,
            onFinish: () =&gt; {
              console.info('Succeeded in finishing');
            }
          },
          controller: this.controller,
          params: {
            firstEdgeFlowLight: {
              startPos: 0,
              endPos: 1.0,
              color: '#1AD0F1',
            },
            secondEdgeFlowLight: {
              startPos: 0.5,
              endPos: 1.5,
              color: '#FFA4E5',
            }
          }
        })
        .buildEffect())
      .width(200)
      .borderRadius('50%')
      .clip(true)
      .height(200)
      .backgroundColor('#383838')
    }
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Black)
    .width('100%')
    .height('100%')
  }
}</pre>       <p><span><img originheight="236" originwidth="230" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/91/v3/IRWcEZrlRjyT3yqZOwUxGg/zh-cn_image_0000002552958352.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083917Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=F227B5CE54ED3BCED51AB1BE3580BAE0C83B857020AD491037A86DB0075EA6A5"></span></p></li>     </ol>    </div>   </div>   <div></div></body></html>
