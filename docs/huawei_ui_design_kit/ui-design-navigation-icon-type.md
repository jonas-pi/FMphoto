# 图标类型设置

- 页面标题: 图标类型设置
- slug: `ui-design-navigation-icon-type`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-icon-type
- 文档ID: `78386983a1634bb38cba6784de21bb0d`
- 更新时间: 2026-04-22 06:37:16

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553358701"></a><a name="ZH-CN_TOPIC_0000002553358701"></a>   <h1>图标类型设置</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553358701__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20)版本开始，导航组件新增了对文本型与图片型图标类型的支持。</p>     <p>当应用开发者需要配置图片型图标，或者使用普通文字型图标、单字图标时，可通过设置titleBar图标内容配置中的<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation#hdsnavigationiconoptions" target="_blank">type</a>属性实现该功能。</p>     <p>图片型图标(<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation#iconstylemode" target="_blank">IconStyleMode.LARGE</a>)：适用于需要展示完整图像的场景，例如应用的Logo、用户头像、宣传图或自定义图形按钮。</p>     <p>普通文字型图标(<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation#textstylemode" target="_blank">TextStyleMode.NORMAL</a>)：常规的文本按钮，适用于功能选项、操作按钮等需要清晰表达文本含义的场景。</p>     <p>单字图标(<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation#textstylemode" target="_blank">TextStyleMode.SINGLE_CHARACTER</a>)：适用于需要节省空间的紧凑布局，常用于快速操作入口，建议仅在单个文字或字母的场景使用。</p>     <p><span><img height="55.256712" originheight="243" originwidth="1316" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/d5/v3/k0H-Opa2RQWLquW8cI3HlQ/zh-cn_image_0000002583478337.jpg?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083914Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=D5D05A871581E4BEBEFFD601767C171838E209607F2319FA53E44A0FD6225DC8" title="点击放大" width="299.25"></span></p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553358701__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">// 从6.0.2(22)版本开始，无需手动导入HdsNavigationAttribute。具体请参考HdsNavigation的导入模块说明。
import { TextStyleMode, IconStyleMode, HdsNavigation, HdsNavigationAttribute, HdsNavigationTitleMode } from '@kit.UIDesignKit';</pre></li>      <li>       <p>创建一级导航组件，通过配置titleBar中的menu上的type属性，实现文字型图标以及图片型图标大小设置。</p>       <pre class="typescript">@Entry
@Component
struct Index {
  build() {
    HdsNavigation() { // 创建HdsNavDestination组件
    }
    .titleBar({
      content: {
        title: { mainTitle: '标题' },
        subIcon: {
          content: {
            // 设置用户头像
            icon: $r('app.media.contacts'), // contacts为自定义资源，开发者需替换本地资源
            type: IconStyleMode.LARGE,
            label: 'subIcon', // 无障碍播报内容
            isEnabled: true,
            action: () =&gt; {
            },
          }
        },
        menu: {
          // 设置HdsNavigation菜单内容
          value: [{
            content: {
              // 设置第一个菜单项内容，设置为普通文本按钮
              label: '文本',
              type: TextStyleMode.NORMAL,
              isEnabled: true,
              componentId: 'menu_1',
              action: () =&gt; {
              },
            }
          }, {
            content: {
              // 设置第二个菜单项内容，设置为单字按钮
              label: '单',
              type: TextStyleMode.SINGLE_CHARACTER,
              isEnabled: true,
              componentId: 'menu_2',
              action: () =&gt; {
              },
            }
          }, {
            content: {
              // 设置第三个菜单项内容，设置为图标按钮
              label: 'largeIcon',
              icon: $r('sys.symbol.AI_search'),
              type: IconStyleMode.NORMAL,
              isEnabled: true,
              componentId: 'menu_3',
              action: () =&gt; {
              },
            }
          }],
          maxCount: 3 // 最大菜单显示个数配置
        },
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
