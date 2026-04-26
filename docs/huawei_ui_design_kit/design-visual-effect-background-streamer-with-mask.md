# 自带背景的双边流光

- 页面标题: 自带背景的双边流光
- slug: `design-visual-effect-background-streamer-with-mask`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/design-visual-effect-background-streamer-with-mask
- 文档ID: `f9499f06a600419b94823c2df016527e`
- 更新时间: 2026-04-22 06:37:15

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002522238792"></a><a name="ZH-CN_TOPIC_0000002522238792"></a>   <h1>自带背景的双边流光</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002522238792__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hds-visual-component#hdsscenetype" target="_blank">自带背景的双边流光</a>。</p>     <p>通过通用视效组件HdsVisualComponent提供的自带背景的双边流光效果场景接口，支持设置两条边缘流光的起始、终止位置、边缘颜色效果以及与流光相叠加的背景板颜色，用于胶囊组件、屏幕边缘发光等。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002522238792__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入模块。</p>       <pre class="typescript">// 从6.0.2(22)版本开始，无需手动导入HdsVisualComponentAttribute。具体请参考HdsVisualComponent的导入模块说明。
import {
  HdsVisualComponent,
  HdsVisualComponentAttribute,
  HdsSceneController,
  HdsSceneType
} from '@kit.UIDesignKit';</pre></li>      <li>       <p>使用HdsVisualComponent组件，指定场景类型为DUAL_EDGE_FLOW_LIGHT_WITH_BACKGROUND_MASK，并且设置场景参数。</p>       <pre class="typescript">@Entry
@Component
struct EdgeFlowLightVisualComponent {
  @State sceneController: HdsSceneController = new HdsSceneController()
    .setSceneParams({
      backgroundMaskColors: [Color.Green, Color.Red],
      firstEdgeFlowLight: {
        startPos: 0,
        endPos: 0.5,
        color: Color.Red
      },
      secondEdgeFlowLight: {
        startPos: 0,
        endPos: -0.5,
        color: Color.Green
      }
    })

  build() {
    Stack() {
      HdsVisualComponent()
        .scene(HdsSceneType.DUAL_EDGE_FLOW_LIGHT_WITH_BACKGROUND_MASK, this.sceneController, () =&gt; {
          console.info('Succeeded in finishing');
        })
        .width('100%')
        .height('50%')
    }
  }
}</pre>       <p><span><img originheight="363" originwidth="360" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/92/v3/DU6A3HUMRKGr2TFrXIbHaA/zh-cn_image_0000002552798704.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083917Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=0C992C8637F42F760FA56F42116731B62D13D4AFDCB1CD5F074C13810A51D8BF"></span></p></li>     </ol>    </div>   </div>   <div></div></body></html>
