# 点光源效果

- 页面标题: 点光源效果
- slug: `ui-design-visual-effect-point-light`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-visual-effect-point-light
- 文档ID: `d98ff00aaa074b0e9f5bf39e2307316c`
- 更新时间: 2026-04-22 06:37:02

## 锚点目录

- 场景介绍
- 约束与限制
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002522238790"></a><a name="ZH-CN_TOPIC_0000002522238790"></a>   <h1>点光源效果</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002522238790__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdseffect#pointlight" target="_blank">点光源效果</a>。</p>     <p>通过点光源接口可以设置组件的发光效果以及被照亮的受光效果，使得组件交互体验更显沉浸。</p>    </div>    <div class="section" id="约束与限制">     <a name="ZH-CN_TOPIC_0000002522238790__%E7%BA%A6%E6%9D%9F%E4%B8%8E%E9%99%90%E5%88%B6"></a><a name="%E7%BA%A6%E6%9D%9F%E4%B8%8E%E9%99%90%E5%88%B6"></a>     <h4>约束与限制</h4>     <p>单个组件最多同时受12个光源照亮。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002522238790__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入模块。</p>       <pre class="typescript">import { hdsEffect } from '@kit.UIDesignKit';</pre></li>      <li>       <p>创建点光源发光效果。如果需要发光，配置sourceType属性；如果需要被照亮，配置illuminatedType属性。</p>       <p>以下代码表示：当中间的Button点击时，产生点光源效果，重复点击触发不同点光源效果。</p>       <pre class="typescript">@Entry
@Component
struct Index {
  @State bloomValue: number = 0;
  @State index: number = 0;
  @State illuminatedType: hdsEffect.PointLightIlluminatedType = hdsEffect.PointLightIlluminatedType.NONE;
  @State button_gradient_state: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;
  @State lightIntensity: number = 10;
  @State types: hdsEffect.PointLightIlluminatedType[] =
    [hdsEffect.PointLightIlluminatedType.NONE, hdsEffect.PointLightIlluminatedType.BORDER,
      hdsEffect.PointLightIlluminatedType.CONTENT, hdsEffect.PointLightIlluminatedType.BORDER_CONTENT,
      hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER];

  build() {
    Flex({
      direction: FlexDirection.Column,
      justifyContent: FlexAlign.Center,
      alignItems: ItemAlign.Center,
    }) {
      // 纵向循环
      ForEach(Array&lt;number&gt;(4).fill(0), (row: number) =&gt; {
        Flex({
          direction: FlexDirection.Row,
          justifyContent: FlexAlign.Center,
          alignItems: ItemAlign.Center,
        }) {
          // 横向循环
          ForEach(Array&lt;number&gt;(4).fill(0), (col: number) =&gt; {
            Flex()
              .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
                illuminatedType: this.illuminatedType,
              }).buildEffect())
              .backgroundColor(0x808080)
              .size({ width: 60, height: 60 })
              .borderRadius(50)
              .margin({ top: 20, right: 10, left: 10 }) // 添加间距
          })
        }
        .width('100%') // 设置 Row 组件的宽度为 100%
      })

      Flex({
        direction: FlexDirection.Row,
        justifyContent: FlexAlign.Center, // 使用 SpaceBetween 来均匀分布间距
        alignItems: ItemAlign.Center,
      }) {
        Flex()
          .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
            illuminatedType: this.illuminatedType,
          }).buildEffect())
          .backgroundColor(0x808080)
          .size({ width: 60, height: 60 })
          .borderRadius(50)
          .margin({ top: 20, right: 10, left: 10 })

        Button('点击发光')
          .size({ width: 140, height: 60 })
          .backgroundColor(0x808080)
          .fontColor(0xADD8E6)
          .visualEffect(new hdsEffect.HdsEffectBuilder()
            .pressShadow(this.button_gradient_state)
            .pointLight({
              options: {
                color: Color.White,
                intensity: this.lightIntensity,
                height: 150
              }
            })
            .pressShadow(this.button_gradient_state)
            .buildEffect())
          .onClick(() =&gt; {
            if (this.index &lt;= 3) {
              this.index++;
              this.illuminatedType = this.types[this.index];
              this.button_gradient_state = hdsEffect.PressShadowType.BLEND_GRADIENT;
            }
            let message = 'NONE';
            if (this.illuminatedType == 1) {
              message = 'BORDER';
            } else if (this.illuminatedType == 2) {
              message = 'CONTENT';
            } else if (this.illuminatedType == 3) {
              message = 'BORDER_CONTENT';
            } else {
              message = 'DEFAULT_FEATHERING_BORDER';
            }
            this.getUIContext().getPromptAction().showToast({
              message: message,
              duration: 2000,
              bottom: '80%'
            });
          })
          .margin({ top: 20, right: 10, left: 10 })

        Flex()
          .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
            illuminatedType: this.illuminatedType,
          }).buildEffect())
          .backgroundColor(0x808080)
          .size({ width: 60, height: 60 })
          .borderRadius(50)
          .margin({ top: 20, right: 10, left: 10 })
      }
      .width('100%') // 设置 Row 组件的宽度为 100%

      ForEach(Array&lt;number&gt;(4).fill(0), (row: number) =&gt; {
        Flex({
          direction: FlexDirection.Row,
          justifyContent: FlexAlign.Center,
          alignItems: ItemAlign.Center,
        }) {
          // 横向循环
          ForEach(Array&lt;number&gt;(4).fill(0), (col: number) =&gt; {
            Flex()
              .visualEffect(new hdsEffect.HdsEffectBuilder().pointLight({
                illuminatedType: this.illuminatedType,
              }).buildEffect())
              .backgroundColor(0x808080)
              .size({ width: 60, height: 60 })
              .borderRadius(50)
              .margin({ top: 20, right: 10, left: 10 })
          })
        }
        .width('100%') // 设置 Row 组件的宽度为 100%
      })
    }
    .backgroundColor(Color.Black)
  }
}</pre>       <p><span><img originheight="434" originwidth="876" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/7c/v3/FSBOOsaETBKFQdY3D_dEIQ/zh-cn_image_0000002552798702.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083917Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=2F8C3BE39B9819DACE1E38D5BA1B6584FA4B70E278CDC8561C1997B84008B587"></span></p></li>     </ol>    </div>   </div>   <div></div></body></html>
