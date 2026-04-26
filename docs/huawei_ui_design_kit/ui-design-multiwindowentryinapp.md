# 应用内多窗

- 页面标题: 应用内多窗
- slug: `ui-design-multiwindowentryinapp`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-multiwindowentryinapp
- 文档ID: `7e3244eb87544c1bb426c931c1d7f2d0`
- 更新时间: 2026-04-22 06:36:55

## 锚点目录

- 场景介绍
- 约束条件
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553198753"></a><a name="ZH-CN_TOPIC_0000002553198753"></a>   <h1>应用内多窗</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553198753__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20)Beta3版本开始，新增支持应用内多窗。</p>     <p>通过应用内多窗组件<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-multiwindowentryinapp-api" target="_blank">MultiWindowEntryInAPP</a>提供的单应用多窗口接口，实现一个应用多个窗口并行运行的体验。并且可以设置图标大小颜色、背板大小颜色、文字大小颜色等。</p>     <p>如果开发者未集成HdsNavigation组件，可使用应用内多窗组件实现应用内多窗体验。</p>    </div>    <div class="section" id="约束条件">     <a name="ZH-CN_TOPIC_0000002553198753__%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a><a name="%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a>     <h4>约束条件</h4>     <p>依赖全景多窗特性，只有当前设备及屏幕状态支持全景多窗，才支持设置此功能。目前支持全景多窗的设备形态有：</p>     <ul>      <li>       <p>双折叠：展开态。</p></li>      <li>       <p>三折叠：双屏态，三屏态的横屏态。</p></li>      <li>       <p>平板：横屏态。</p></li>     </ul>     <p>对于不支持的设备形态，该组件不可交互，不响应点击事件。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553198753__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入模块。</p>       <pre class="typescript">// 从6.0.2(22)版本开始，无需手动导入MultiWindowEntryInAPPAttribute。具体请参考MultiWindowEntryInAPP的导入模块说明。
import { MultiWindowEntryInAPP, MultiWindowEntryInAPPAttribute } from '@kit.UIDesignKit';
import { Want } from '@kit.AbilityKit';
import { TextModifier }  from '@kit.ArkUI';</pre></li>      <li>       <p>使用MultiWindowEntryInAPP组件，并且设置组件参数。</p>       <pre class="typescript">@Entry
@Component
struct MultiWindowEntryInAPPTest {
  @State textModifier: TextModifier = new TextModifier();
  private want: Want = {
    // 修改为当前应用的bundleName、moduleName、abilityName，启动应用内的UIAbility
    bundleName: "com.example.myapplication",
    moduleName: "entry",
    abilityName: "FuncAbility",
  };

  build() {
    Row() {
      MultiWindowEntryInAPP({
        want: this.want, isShowSubtitle: true, multiWindowEntryInAPPStyle: {
          iconOptions: {
            iconSize: 24,
            iconColor: $r('sys.color.font_primary'),
            iconWeight: FontWeight.Normal,
            backgroundColor: $r('sys.color.comp_background_tertiary')
          },
          subtitleOptions: {
            modifier: this.textModifier.fontColor(Color.Black)
          }
        }
      })
        .size({ width: 48, height: 48 })
        .position({ x: 400, y: 30 })
    }
  }
}</pre>       <p><span><img originheight="571" originwidth="525" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/9d/v3/RcPwqSfKQzCO-dPpHe8-aA/zh-cn_image_0000002583438399.jpg?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083917Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=3ED866A0B6B541FCF2DD0CCDF50B110CAA4EFAC2F2E08394E19FAAC7C462D2DA"></span></p></li>     </ol>    </div>   </div>   <div></div></body></html>
