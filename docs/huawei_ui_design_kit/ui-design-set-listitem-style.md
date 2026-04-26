# 设置列表卡片样式

- 页面标题: 设置列表卡片样式
- slug: `ui-design-set-listitem-style`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-set-listitem-style
- 文档ID: `4c939364a8534e008a15bed0a33b478d`
- 更新时间: 2026-04-22 06:37:07

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002522238788"></a><a name="ZH-CN_TOPIC_0000002522238788"></a>   <h1>设置列表卡片样式</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002522238788__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持设置列表卡片样式。</p>     <p>应用使用<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdslistitemcard" target="_blank">HdsListItemCard</a>组件实现多设备上的系统列表样式。</p>     <p><span><img originheight="157" originwidth="525" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/de/v3/8UedxEEORO-ozSUlrtT1tQ/zh-cn_image_0000002552798700.jpg?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083916Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=AA7799B4F51A76C456E25A88A3E9BBD347383F3F89BBBBDAA3DC99B248EBDE17"></span></p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002522238788__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">import { HdsListItemCard, PrefixImage, SuffixSwitch} from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';</pre></li>      <li>       <p>创建HdsListItemCard组件，设置左边为Image，中间为Text，右边为Switch的场景。</p>       <pre class="typescript">@Entry
@Component
struct Test {
  private scroller: ListScroller = new ListScroller();

  build() {
    Column() {
      List({ space: 10, scroller: this.scroller }) {
        ListItem() {
          HdsListItemCard({
            // A区图片
            prefixItem: new PrefixImage({
              image: $r('app.media.background'),
              onClick: () =&gt; {
                promptAction.openToast({ message: 'left image' });
              }
            }),
            // B区文本
            textItem: {
              primaryText: {
                text: 'Primary Text'
              },
              secondaryText: {
                text: 'Secondary Text'
              },
              description: {
                text: 'Description Text'
              }
            },
            // C区Switch
            suffixItem: new SuffixSwitch({
              isCheck: false,
              onChange: (num: boolean) =&gt; {
                if (num) {
                  promptAction.openToast({ message: 'switch is true' });
                } else {
                  promptAction.openToast({ message: 'switch is false' });
                }
              }
            }),
            onClick: () =&gt; {
              promptAction.openToast({ message: 'hdslistitem' });
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .margin(10)
    }.backgroundColor(0x1a0a59f7).height('100%')
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
