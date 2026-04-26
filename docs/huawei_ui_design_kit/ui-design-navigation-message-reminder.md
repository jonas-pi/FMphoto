# 设置信息提醒

- 页面标题: 设置信息提醒
- slug: `ui-design-navigation-message-reminder`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-message-reminder
- 文档ID: `1cf36855e16c4885ac37da3d25676216`
- 更新时间: 2026-04-22 06:37:07

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553358699"></a><a name="ZH-CN_TOPIC_0000002553358699"></a>   <h1>设置信息提醒</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553358699__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从5.1.0(18)版本开始，导航组件新增支持菜单栏设置信息提醒能力。</p>     <p>当应用开发者需要在导航组件菜单项右上角附加消息提醒时，可以通过设置标题栏菜单中的<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation#hdsnavigationbadgeiconoptions" target="_blank">badge</a>属性，实现信息提醒能力。</p>     <p><span><img height="95.38600400000001" originheight="459" originwidth="1440" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/45/v3/SEs1StHeTnmaxEz7v7X7Hg/zh-cn_image_0000002552958334.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083913Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=DBB8407669E090208A963A396492A7EFC4ACD26C1C316ECB7CA46B2DA50B018B" title="点击放大" width="299.25"></span></p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553358699__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">// 从6.0.2(22)版本开始，无需手动导入HdsNavigationAttribute。具体请参考HdsNavigation的导入模块说明。
import { HdsNavigation, HdsNavigationAttribute, HdsNavigationTitleMode } from '@kit.UIDesignKit';</pre></li>      <li>       <p>创建一级导航组件，通过配置titleBar中menu的badge属性，设置信息提醒样式。</p>       <pre class="typescript">@Entry
@Component
struct Index {
  build() {
    HdsNavigation() { // 创建HdsNavigation组件
    }
    .titleBar({
      content: {
        // HdsNavigation标题栏内容设置
        menu: {
          // HdsNavigation标题栏菜单区域内容设置
          value: [{
            content: {
              // 第一个菜单项内容设置
              label: 'menu1',
              icon: $r('sys.symbol.AI_search'),
              isEnabled: true,
            },
            badge: {
              // 第一个菜单项信息提醒设置
              count: 1,
            }
          }, {
            content: {
              // 设置第一个菜单项内容，设置为普通文本按钮
              label: 'menu2',
              icon: $r('sys.symbol.wifi'),
              isEnabled: true,
              componentId: 'menu_1',
              action: () =&gt; {
              },
            },
            badge: {
              // 第二个菜单项信息提醒设置
              value: '消息'
            }
          }]
        },
        title: { mainTitle: 'MainTitle' },
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
