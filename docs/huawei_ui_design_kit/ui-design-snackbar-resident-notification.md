# 设置常驻通知弹窗

- 页面标题: 设置常驻通知弹窗
- slug: `ui-design-snackbar-resident-notification`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-snackbar-resident-notification
- 文档ID: `0aa059bbd08449b09a7c95d5dff16308`
- 更新时间: 2026-04-22 06:37:02

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553198745"></a><a name="ZH-CN_TOPIC_0000002553198745"></a>   <h1>设置常驻通知弹窗</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553198745__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持设置常驻通知弹窗。</p>     <p><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdssnackbar" target="_blank">HdsSnackBar</a>支持常驻通知弹窗。当应用开发者需要常驻通知提醒弹窗时，可以通过HdsSnackBar的show方法显示HdsSnackBar弹窗，设置duration是-1表示常驻弹窗。</p>     <p><span><img originheight="324" originwidth="315" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/b1/v3/UxWmNNMQSXKYJpiFHUXZhw/zh-cn_image_0000002583478347.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083915Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=BB45FBC2717C7D46FE93F0F46A729C857F653AC453DDB133A49E1FB0DFAED28F"></span></p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553198745__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">import {
  HdsSnackBar,
  SnackBarIconOptions,
  SnackBarMessageOptions,
  SnackBarOperationOptions,
  SnackBarStyleOptions,
  SnackBarOperationType
} from '@kit.UIDesignKit'</pre></li>      <li>       <p>创建UIContext，创建HdsSnackBar对象hdsSnackBar，调用HdsSnackBar对象的show方法可以显示HdsSnackBar弹窗，入参是左侧图标icon、中间文本message、右侧操作区operation、样式style，其中右侧操作区设置类型是带有关闭按钮的文本按钮，其中style中设置duration是-1表示HdsSnackBar弹窗常驻。</p></li>      <li>       <p>设置textButtonId和nextFocusId两个属性，支持开发者自定义Tab键走焦能力。</p>       <pre class="typescript">@Entry
@ComponentV2
struct TestSnackBar {
  uiContext: UIContext = this.getUIContext();
  hdsSnackBar: HdsSnackBar = new HdsSnackBar(this.uiContext);
  icon: SnackBarIconOptions = {
    icon: $r('sys.symbol.checkmark_circle')
  }
  message: SnackBarMessageOptions = {
    title: $r('sys.string.ohos_id_text_location_button_description_current_position'),
    content: $r('sys.string.ohos_id_text_save_button_description_save')
  }
  operation: SnackBarOperationOptions = {
    operationType: SnackBarOperationType.TEXT_WITH_CLOSE,
    content: $r('sys.string.ohos_id_text_save_button_description_save_image'),
    textButtonId: 'snackBarTextButton'
  }
  style: SnackBarStyleOptions = {
    nextFocusId: 'button',
    duration: -1
  }

  build() {
    Column() {
      Blank()
        .height(400)
      Button('右侧操作区是文字按钮和关闭按钮的SnackBar弹窗，常驻')
        .onClick(() =&gt; {
          this.hdsSnackBar.show(this.icon, this.message, this.operation, this.style);
        })
        .id("button")

      Button('关注')
        .nextFocus({
          // 这里forward的id必须和SnackBarOperationOptions接口中传入的textButtonId相同
          forward: 'snackBarTextButton'
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(0xF1F3F5)
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
