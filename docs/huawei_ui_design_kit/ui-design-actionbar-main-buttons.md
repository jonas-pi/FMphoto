# 设置有主按钮的组件

- 页面标题: 设置有主按钮的组件
- slug: `ui-design-actionbar-main-buttons`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-actionbar-main-buttons
- 文档ID: `a2933784285d4784993a055cee0048c3`
- 更新时间: 2026-04-22 06:37:02

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002522238786"></a><a name="ZH-CN_TOPIC_0000002522238786"></a>   <h1>设置有主按钮的组件</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002522238786__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持设置有主按钮的组件。</p>     <p><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsactionbar" target="_blank">HdsActionBar</a>组件支持多个按钮的样式。当应用开发者需要多个按钮并且有主按钮，支持展开和收缩的动效时，可以通过设置主按钮配置样式。</p>     <p><span><img originheight="145" originwidth="292" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/44/v3/4LljLcKyRJ6X8QScKC5Q5g/zh-cn_image_0000002583438393.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083916Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=C8E772502C43985421EE9F6D42D6414A7A441FC9FDB84CD7DF685A9EE07B0E2B"></span></p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002522238786__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">import { HdsActionBar, ActionBarButton, ActionBarStyle } from '@kit.UIDesignKit';</pre></li>      <li>       <p>创建左边的按钮数组startButtons，创建右边的按钮数组endButtons，创建主按钮primaryButton，设置isExpand初始值是true表示HdsActionBar的初始状态是展开状态，点击主按钮会收起，再次点击可以展开。</p>       <pre class="typescript">@Entry
@ComponentV2
struct TestActionBar {
  @Local isExpand: boolean = true;

  @Local isPrimaryIconChanged: boolean = false;

  @Local primaryHoverTips: ResourceStr = '开始';

  build() {
    Column() {
      HdsActionBar({
        startButtons: [new ActionBarButton({
          baseIcon: $r('sys.symbol.stopwatch_fill')
        })],
        endButtons: [new ActionBarButton({
          baseIcon: $r('sys.symbol.mic_fill')
        })],
        primaryButton: new ActionBarButton({
          baseIcon: $r('sys.symbol.plus'),
          altIcon: $r('sys.symbol.play_fill'),
          onClick: () =&gt; {
            this.isExpand = !this.isExpand;
            this.isPrimaryIconChanged = !this.isPrimaryIconChanged;
            if (this.isPrimaryIconChanged) {
              this.primaryHoverTips = '暂停';
            } else {
              this.primaryHoverTips = '开始';
            }
          },
          hoverTips: this.primaryHoverTips
        }),
        actionBarStyle: new ActionBarStyle({
          isPrimaryIconChanged: this.isPrimaryIconChanged
        }),
        isExpand: this.isExpand!!
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0xF1F3F5)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
