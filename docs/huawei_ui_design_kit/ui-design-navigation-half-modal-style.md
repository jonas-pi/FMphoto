# 半模态样式

- 页面标题: 半模态样式
- slug: `ui-design-navigation-half-modal-style`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-half-modal-style
- 文档ID: `cd321d67245e44798a5e462478ec5613`
- 更新时间: 2026-04-22 06:37:15

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002522078776"></a><a name="ZH-CN_TOPIC_0000002522078776"></a>   <h1>半模态样式</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002522078776__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20)版本开始，导航组件新增支持半模态中的标题栏样式，并在该样式下支持标题栏模糊效果。</p>     <p>用于半模态弹窗中使用导航组件场景。通过设置<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation#hdsnavigationtitlemode" target="_blank">HdsNavigationTitleMode</a>为MODAL可以实现标题栏半模态样式及动态模糊。</p>     <p><span><img height="626.8202220000001" originheight="664" originwidth="317" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/b3/v3/7bR4XnpZSWqJ1L2luVOxGQ/zh-cn_image_0000002552958336.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083914Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=AC8365360D8B212AC463619FCF5A99AC1D27BCE54121F4EC0DD33E55BB991F06" title="点击放大" width="299.25"></span></p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002522078776__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">// 从6.0.2(22)版本开始，无需手动导入HdsNavigationAttribute。具体请参考HdsNavigation的导入模块说明。
import { IconStyleMode, HdsNavigationAttribute, HdsNavigation, HdsNavigationTitleMode } from '@kit.UIDesignKit';</pre></li>      <li>       <p>创建一级导航组件，通过设置titleMode属性为HdsNavigationTitleMode.MODAL实现标题栏半模态样式。</p>       <pre class="typescript">@Entry
@Component
struct SheetTransitionExample {
  @State isShow: boolean = false;
  scroller: Scroller = new Scroller();

  @Builder
  HdsNavigationBuilder() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Image($r('app.media.scenery2'))
          .height('100%')
      }
      .clip(false) // 设置不对子组件超出当前组件范围外的区域进行裁剪，使内容区可以穿透到标题栏下方
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .titleBar({
      enableComponentSafeArea: true, // 将标题栏设置为组件级安全区，内容区可避让标题栏
      content: {
        title: {
          mainTitle: '壁纸',
        },
      // 设置HdsNavigation关闭按钮，与半模态按钮规格一致
      menu: {
        value: [{
          content: {
            icon: $r('sys.symbol.xmark'),
            type: IconStyleMode.SMALL,
            action: () =&gt; {
              this.isShow = false;
            },
          }
        }]
      },
    },
  })
  .titleMode(HdsNavigationTitleMode.MODAL) // 设置导航标题栏模式为半模态
  .bindToScrollable([this.scroller]) // 绑定导航组件和可滚动容器组件
  }

  build() {
    Column({ space: 8 }) {
      Button('open modal')
        .onClick(() =&gt; {
          this.isShow = true;
        })
        .fontSize(20)
        .margin(10)
        .bindSheet($$this.isShow, this.HdsNavigationBuilder(), {
          detents: [SheetSize.MEDIUM, SheetSize.LARGE, 200],
          showClose: false, // 关闭半模态关闭按钮，推荐使用HdsNavigation关闭按钮
          enableFloatingDragBar: true,
        })
    }
    .width('100%')
    .height('100%')
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
