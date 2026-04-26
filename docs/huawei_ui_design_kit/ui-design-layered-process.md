# （推荐）分层图标处理

- 页面标题: （推荐）分层图标处理
- slug: `ui-design-layered-process`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-layered-process
- 文档ID: `317db226da534fafb376129d1bd49ad1`
- 更新时间: 2026-04-22 06:37:01

## 锚点目录

- 场景介绍
- 约束条件
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002562807243"></a><a name="ZH-CN_TOPIC_0000002562807243"></a>   <h1>（推荐）分层图标处理</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002562807243__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从5.0.0(12)版本开始， Hds支持分层图标处理能力。</p>     <p>适用于图标为分层资源，且图标展示风格要与华为HarmonyOS Design System设计风格一致的应用场景。以下是一些典型的应用场景：</p>     <ul>      <li>       <p>展示带图标的应用列表：可调用UI Design Kit批量处理分层图标的接口获取处理后的应用图标。</p></li>      <li>       <p>展示应用详情：可调用UI Design Kit处理单个分层图标的接口获取处理后的应用图标。</p></li>      <li>       <p>展示跟随在线主题的应用图标：可调用UI Design Kit处理分层图标的接口获取主题换肤后的应用图标。</p></li>     </ul>     <p><span><img originheight="586" originwidth="307" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/11/v3/o1p22WigTO2fOCI8rao9RQ/zh-cn_image_0000002552958330.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083913Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=AB5AC7C7FB29EC0C08CD7B69A8C04644F57846D5866752840715D4C0840BF028"></span><span><img originheight="587" originwidth="307" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/63/v3/SUILzQutRC2GXbIPhziHQQ/zh-cn_image_0000002583478331.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083913Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=05F0DF9802CE4FC28B83D22BBA71EED7D65891C18F1F3BD218D878FD30474175"></span><span><img originheight="586" originwidth="285" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/ee/v3/d6mnuKrqRN2lpk5g2n79lQ/zh-cn_image_0000002552798682.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083913Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=8B7C6B93094416AC7AAAD73E7EABBB4D4CE4BED579F4186EED38E81F63C7CF5A"></span></p>    </div>    <div class="section" id="约束条件">     <a name="ZH-CN_TOPIC_0000002562807243__%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a><a name="%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a>     <h4>约束条件</h4>     <p>分层图标处理支持Phone、Tablet、PC/2in1设备，并且从5.1.1(19)版本开始，新增支持TV设备。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002562807243__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <p><span><img originheight="950" originwidth="3564" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/b/v3/SyDK8D7oSlm0Yh49soqwiQ/zh-cn_image_0000002583438377.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083913Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=5BE7BFF77E494224944BADF2EADD1F381E19E90C9005595D227D7309BFFD3428"></span></p>     <ol>      <li>       <p>设置分层图标，将前景资源和背景资源放至entry/src/main/resources/base/media文件中，并在该目录下创建一个json文件（例如：drawable.json）：</p>       <pre class="typescript">{
  "layered-image":
  {
    "background" : "$media:background",
    "foreground" : "$media:foreground"
  }
}</pre></li>      <li>       <p>将图标处理的相关类添加至工程。</p>       <pre class="typescript">import { LayeredDrawableDescriptor } from '@kit.ArkUI';
import { hdsDrawable } from '@kit.UIDesignKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { resourceManager } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';</pre></li>      <li>       <p>简单配置页面的布局，调用<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsdrawable#hdsdrawablegethdslayeredicon" target="_blank">分层图标接口</a>获取处理后的图标信息，也可以调用<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsdrawable#hdsdrawablegethdslayeredicons" target="_blank">异步批量处理接口</a>。</p>       <pre class="typescript">@Entry
@Component
struct Index{
  bundleName: string = 'com.example.uidesignkit';
  resManager: resourceManager.ResourceManager | undefined = undefined;
  layeredDrawableDescriptor: LayeredDrawableDescriptor | undefined = undefined;
  @State layeredIconsResult: Array&lt;hdsDrawable.ProcessedIcon&gt; = [];

  build() {
    Column() {
      Column() {
        Text('getHdsLayeredIcon')
          .fontWeight(FontWeight.Bold)
          .fontSize(16)
          .margin(5)

        Image(this.getHdsLayeredIcon())
          .width(48)
          .height(48)
      }
      .margin(20)

      Text('getHdsLayeredIcons')
        .fontWeight(FontWeight.Bold)
        .fontSize(16)
        .margin(5)

      List() {
        ForEach(this.layeredIconsResult,
          (item: hdsDrawable.ProcessedIcon, index?: number) =&gt; {
            ListItem() {
              Column() {
                Text(item.bundleName)
                  .fontWeight(FontWeight.Medium)
                  .fontSize(16)
                  .margin(5)

                Image(item.pixelMap)
                  .width(48)
                  .height(48)
              }
              .margin(15)
            }
            .width('100%')
          }, (item: string) =&gt; item.toString())
      }
      .scrollBar(BarState.On)
      .height('60%')
    }
    .height('100%')
    .width('100%')
  }

  aboutToAppear(): void {
    // 获取资源管理器
    this.resManager = (this.getUIContext().getHostContext() as common.UIAbilityContext)?.resourceManager;
    if (!this.resManager) {
      return;
    }
    // 通过资源管理获取原始分层图标信息
    this.layeredDrawableDescriptor = (this.resManager.getDrawableDescriptor($r('app.media.drawable')
      .id)) as LayeredDrawableDescriptor;
    this.getHdsLayeredIcons();
  }

  private getHdsLayeredIcon(): image.PixelMap | null {
    try {
      // 调用HDS分层图标接口处理图标
      return hdsDrawable.getHdsLayeredIcon(this.bundleName, this.layeredDrawableDescriptor, 48, true);
    } catch (err) {
      let message = (err as BusinessError).message;
      let code = (err as BusinessError).code;
      console.error(`getHdsLayeredIcon failed, code: ${code}, message: ${message}`);
      return null;
    }
  }

  private getHdsLayeredIcons(): void {
    if (!this.layeredDrawableDescriptor) {
      console.error(`getHdsLayeredIcons layeredDrawableDescriptor is undefined.`);
      return;
    }
    
    // 构造批量接口传参
    let options: hdsDrawable.Options = {
      size: 48,
      hasBorder: true,
      parallelNumber: 4
    };

    let layeredIcons: Array&lt;hdsDrawable.LayeredIcon&gt; = [];
    for (let i = 0; i &lt; 10; i++) {
      layeredIcons.push({
        bundleName: `${this.bundleName}-${i}`,
        layeredDrawableDescriptor: this.layeredDrawableDescriptor
      });
    }

    try {
      // 调用HDS批量分层接口处理图标
      hdsDrawable.getHdsLayeredIcons(layeredIcons, options)
        .then((data: Array&lt;hdsDrawable.ProcessedIcon&gt;) =&gt; {
          console.info(`getHdsLayeredIcons data size: ${data.length}`);
          this.layeredIconsResult = data;
        })
        .catch((err: BusinessError) =&gt; {
          console.error(`getHdsLayeredIcons return error, code: ${err.code}, msg: ${err.message}`);
        });
    } catch (err) {
      let message = (err as BusinessError).message;
      let code = (err as BusinessError).code;
      console.error(`getHdsLayeredIcons failed, code: ${code}, message: ${message}`);
    }
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
