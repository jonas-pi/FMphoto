# 单层图标处理

- 页面标题: 单层图标处理
- slug: `ui-design-normal-process`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-normal-process
- 文档ID: `715f8768404e44498a94639490f33a13`
- 更新时间: 2026-04-22 06:37:07

## 锚点目录

- 场景介绍
- 约束条件
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002562647271"></a><a name="ZH-CN_TOPIC_0000002562647271"></a>   <h1>单层图标处理</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002562647271__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从5.0.0(12)版本开始， Hds支持单层图标处理能力。</p>     <p>适用于图标为单层资源，且图标展示风格要与华为HarmonyOS Design System设计风格一致的应用场景，典型应用场景可参考分层图标<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-layered-process#场景介绍">场景介绍</a>。</p>    </div>    <div class="section" id="约束条件">     <a name="ZH-CN_TOPIC_0000002562647271__%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a><a name="%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a>     <h4>约束条件</h4>     <p>单层图标处理支持Phone、Tablet、PC/2in1设备，并且从5.1.1(19)版本开始，新增支持TV设备。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002562647271__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <p><span><img originheight="914" originwidth="2572" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/94/v3/Ax3YQuh0TOqNzoKU-W2m2A/zh-cn_image_0000002552958332.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083913Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=F3BC631C1FF4C984815D2A74FCB0CDFD7BB53FCD5AE789D348E3A6BAD8DD81D3"></span></p>     <ol>      <li>       <p>在entry/src/main/resources/base/media下，配置一张图片资源normal_icon.png。</p></li>      <li>       <p>将图标处理的相关类添加至工程。</p>       <pre class="typescript">import { LayeredDrawableDescriptor, DrawableDescriptor } from '@kit.ArkUI';
import { hdsDrawable } from '@kit.UIDesignKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { resourceManager } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';</pre></li>      <li>       <p>简单配置页面的布局，调用<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsdrawable#hdsdrawablegethdsicon" target="_blank">单层图标接口</a>获取处理后的图标信息，也可以调用<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsdrawable#hdsdrawablegethdsicons" target="_blank">异步批量处理接口</a>。</p>       <pre class="typescript">@Entry
@Component
struct Index{
  bundleName: string = 'com.example.uidesignkit';
  resManager: resourceManager.ResourceManager | undefined = undefined;
  layeredDrawableDescriptor: LayeredDrawableDescriptor | undefined = undefined;
  drawableDescriptor: DrawableDescriptor | undefined = undefined;
  @State iconsResult: Array&lt;hdsDrawable.ProcessedIcon&gt; = [];

  build() {
    Column() {
      Column() {
        Text('getHdsIcon')
          .fontWeight(FontWeight.Bold)
          .fontSize(16)
          .margin(5)

        Image(this.getHdsIcon())
          .width(48)
          .height(48)
      }
      .margin(20)

      Text('getHdsIcons')
        .fontWeight(FontWeight.Bold)
        .fontSize(16)
        .margin(5)

      List() {
        ForEach(this.iconsResult,
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

    // 通过资源管理获取分层图标信息
    this.layeredDrawableDescriptor = (this.resManager.getDrawableDescriptor($r('app.media.drawable').id)) as LayeredDrawableDescriptor;

    // 通过资源管理获取单层图标信息
    this.drawableDescriptor =
      (this.resManager?.getDrawableDescriptor($r('app.media.normal_icon').id)) as DrawableDescriptor;

    this.getHdsIcons();
  }

  private getHdsIcon(): image.PixelMap | null {
    try {
      // 调用HDS单层图标接口
      return hdsDrawable.getHdsIcon(this.bundleName, this.drawableDescriptor?.getPixelMap(), 48,
        this.layeredDrawableDescriptor?.getMask().getPixelMap(), true);
    } catch (err) {
      let message = (err as BusinessError).message;
      let code = (err as BusinessError).code;
      console.error(`getHdsIcon failed, code: ${code}, message: ${message}`);
      return null;
    }
  }

  getHdsIcons(): void {
    if (!this.drawableDescriptor) {
      console.error(`getHdsIcons drawableDescriptor is undefined.`);
      return;
    }

    if (!this.layeredDrawableDescriptor) {
      console.error(`getHdsIcons layeredDrawableDescriptor is undefined.`);
      return;
    }

    // 构造批量接口传参
    let options: hdsDrawable.Options = {
      size: 48,
      hasBorder: true,
      parallelNumber: 4
    };

    let icons: Array&lt;hdsDrawable.Icon&gt; = [];
    for (let i = 0; i &lt; 10; i++) {
      icons.push({
        bundleName: `${this.bundleName}-${i}`,
        pixelMap: this.drawableDescriptor.getPixelMap()
      })
    }

    try {
      // 调用HDS单层批量接口处理图标
      hdsDrawable.getHdsIcons(icons, this.layeredDrawableDescriptor.getMask().getPixelMap(), options)
        .then((data: Array&lt;hdsDrawable.ProcessedIcon&gt;) =&gt; {
          console.info(`getHdsIcons data size: ${data.length}`);
          this.iconsResult = data;
        })
        .catch((err: BusinessError) =&gt; {
          console.error(`getHdsIcons error, code: ${err.code}, msg: ${err.message}`);
        });
    } catch (err) {
      let message = (err as BusinessError).message;
      let code = (err as BusinessError).code;
      console.error(`getHdsIcons callback failed: ${message}, code: ${code}`);
    }
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
