# 设置应用内多窗

- 页面标题: 设置应用内多窗
- slug: `ui-design-navigation-set-multi-window`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-set-multi-window
- 文档ID: `23478ad142b846d1a87c0ec585f7b4e1`
- 更新时间: 2026-04-22 06:37:18

## 锚点目录

- 场景介绍
- 约束条件
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002522238778"></a><a name="ZH-CN_TOPIC_0000002522238778"></a>   <h1>设置应用内多窗</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002522238778__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20)版本开始，新增支持应用内多窗。</p>     <p>当应用开发者需要使用应用内多窗图标（分屏按钮）时，可通过配置titleBar中的menu的<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation#hdsnavigationmenucontentoptions" target="_blank">multiWindowEntryInAPPMenu</a>属性实现该功能。</p>    </div>    <div class="section" id="约束条件">     <a name="ZH-CN_TOPIC_0000002522238778__%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a><a name="%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a>     <h4>约束条件</h4>     <p>依赖全景多窗特性，只有当前设备及屏幕状态支持全景多窗，才支持设置此功能。目前支持全景多窗的设备形态有：</p>     <ul>      <li>       <p>双折叠：展开态。</p></li>      <li>       <p>三折叠：双屏态，三屏态的横屏态。</p></li>      <li>       <p>平板：横屏态。</p></li>     </ul>     <p>对于不支持的设备形态，该组件不可交互，不响应点击事件。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002522238778__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入模块。</p>       <pre class="typescript">// 从6.0.2(22)版本开始，无需手动导入HdsNavigationAttribute。具体请参考HdsNavigation的导入模块说明。
import { HdsNavigation, HdsNavigationMenuContentOptions, HdsNavigationAttribute } from '@kit.UIDesignKit';
import { Want } from '@kit.AbilityKit';</pre></li>      <li>       <p>创建一级导航组件，通过配置titleBar中的menu上的multiWindowEntryInAPPMenu属性，实现应用内多窗图标设置。</p>       <pre class="typescript">@Entry
@Component
struct MultiWindowEntryInAPPTest {
  private want: Want = {
    // 修改为当前应用的bundleName、moduleName、abilityName，启动应用内的UIAbility
    bundleName: "com.example.myapplication",
    moduleName: "entry",
    abilityName: "FuncAbility",
  }
  @State menuContent: HdsNavigationMenuContentOptions = {
    multiWindowEntryInAPPMenu: {
      want: this.want,
    },
    maxCount: 3,
    value: [
      { content: { label: 'menu1', icon: $r('sys.symbol.search_things'), } },
      { content: { label: 'menu2', icon: $r('sys.symbol.plus'), } }
    ]
  }

  build() {
    HdsNavigation() {
      Stack() {
        Text("Page1")
      }.alignContent(Alignment.Center)
      .width("100%")
      .height("100%")
    }
    .hideToolBar(false)
    .navBarWidth('100%')
    .titleBar({
      content: {
        title: {
          mainTitle: "Index"
        },
        menu: this.menuContent
      }
    })
  }
}</pre>       <p><span><img originheight="571" originwidth="525" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/36/v3/fWhqZ31HQxe_YOijUP4C-w/zh-cn_image_0000002552798688.jpg?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083914Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=55151BBAAB6AC3F9471022597E4F46B5C3D5C40A3FAC014F7C99999F017FFD54"></span></p></li>     </ol>    </div>   </div>   <div></div></body></html>
