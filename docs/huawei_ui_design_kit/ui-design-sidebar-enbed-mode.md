# 设置embed模式的侧边栏

- 页面标题: 设置embed模式的侧边栏
- slug: `ui-design-sidebar-enbed-mode`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-sidebar-enbed-mode
- 文档ID: `12304a7126fc400aa65f57acf90202e2`
- 更新时间: 2026-04-22 06:37:07

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002522238780"></a><a name="ZH-CN_TOPIC_0000002522238780"></a>   <h1>设置embed模式的侧边栏</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002522238780__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持设置embed模式的侧边栏。</p>     <p><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdssidebar" target="_blank">HdsSideBar</a>提供可以显示和隐藏的侧边栏容器，通过子组件定义侧边栏和内容区，第一个子组件表示侧边栏，第二个子组件表示内容区，通过设置<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-sidebarcontainer#sidebarcontainertype枚举说明" target="_blank">sideBarContainerType</a>的值为SideBarContainerType.Embed，使得当前HdsSideBar为嵌入样式。</p>     <p><span><img originheight="348" originwidth="525" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/a0/v3/pVuTZWBNRXC-p9fjkpQBXw/zh-cn_image_0000002552798690.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083914Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=00869124B37893509DC47432F8A859D04398387D4A593FC193E43374B5D51EA9"></span></p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002522238780__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">import { HdsSideBar } from '@kit.UIDesignKit';</pre></li>      <li>       <p>设置图片。</p>       <p>将图片资源，放到entry/src/main/resources/base/media下。</p>       <p><span><img originheight="178" originwidth="479" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/f7/v3/fPr4MUbxTFOzzpctHg3DxQ/zh-cn_image_0000002583438385.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083914Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=D349E566DF29EF7354BC72F4AC00F9BE486D61A6C05114624527DD7361A3D5C8"></span></p></li>      <li>       <p>创建HdsSideBar侧边栏组件，设置展开模式为embed。</p>       <pre class="typescript">@Entry
@ComponentV2
struct Index {
  @Local isSideBarContainerMask: boolean = true;
  @Local blankHeight: number = 48;
  @Local isAutoHide: boolean = false;
  @Local isShowSidebar: boolean = true;
  @Local triggerValueReplace: number = 0;
  //左侧侧边栏区
  @Builder
  SideBarPanelBuilder() {
    Column() {
      Blank().height(this.blankHeight)
      Text('HDSSideBar Menu 1')
        .fontSize(14)
      Text('HDSSideBar Menu 2')
        .fontSize(14)
    }
    .width('100%')
    .height('100%')
  }
  //右侧内容区
  @Builder
  ContentPanelBuilder() {
    Column(){
      Blank().height(this.blankHeight)
      Image($r('app.media.view')) // view为自定义资源，开发者需替换本地资源
        .width('80%')
        .height('50%')
        .margin({ top: 8 })
        .padding({
          right: '16vp',
          left: '16vp',
          bottom: '16vp',
        })
        .borderRadius(8)
      Column() {
        Text('HDSSideBar content text1')
          .fontSize(14)
        Text('HDSSideBar content text2')
          .fontSize(14)
      }
      Button() {
        SymbolGlyph(this.isShowSidebar ? $r('sys.symbol.open_sidebar') : $r('sys.symbol.close_sidebar'))
          .fontWeight(FontWeight.Normal)
          .fontSize($r('sys.float.ohos_id_text_size_headline7'))
          .fontColor([$r('sys.color.ohos_id_color_titlebar_icon')])
          .hitTestBehavior(HitTestMode.None)
      }
      .id('side_bar_button')
      .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
      .height(24)
      .width(24)
      .animation({ curve: Curve.Sharp, duration: 100 })
      .onClick(() =&gt; {
        this.isShowSidebar = !this.isShowSidebar;
      })
    }
  }
  @BuilderParam contentBuilder: () =&gt; void = this.ContentPanelBuilder
  @BuilderParam sideBarBuilder: () =&gt; void = this.SideBarPanelBuilder
  @Builder
  HDSSideBarBuilder() {
    HdsSideBar({
      sideBarPanelBuilder: (): void =&gt; {
        this.sideBarBuilder()
      },
      contentPanelBuilder: (): void =&gt; {
        this.contentBuilder()
      },
      autoHide: this.isAutoHide,
      contentAreaMask: this.isSideBarContainerMask,
      sideBarContainerType: SideBarContainerType.Embed,
      isShowSideBar: this.isShowSidebar,
      $isShowSideBar: (isShowSidebar: boolean) =&gt; {
        this.isShowSidebar = !isShowSidebar
      },
    })
  }
  @Builder
  build() {
    Stack() {
      this.HDSSideBarBuilder()
    }
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
