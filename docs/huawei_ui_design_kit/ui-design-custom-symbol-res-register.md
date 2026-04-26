# 应用加载自定义Symbol

- 页面标题: 应用加载自定义Symbol
- slug: `ui-design-custom-symbol-res-register`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-custom-symbol-res-register
- 文档ID: `02f1cdfab41f41ecb5856da3ea7c770b`
- 更新时间: 2026-04-22 06:36:55

## 锚点目录

- 场景介绍
- 约束条件
- 开发步骤
- 开发实例

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553198749"></a><a name="ZH-CN_TOPIC_0000002553198749"></a>   <h1>应用加载自定义Symbol</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553198749__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从5.1.1 (19)版本开始，新增支持资源注册。</p>     <p>适用于需要快速定制应用内<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-symbolregister" target="_blank">Symbol图标</a>，不想强依赖于系统版本中预制的系统Symbol图标资源。</p>    </div>    <div class="section" id="约束条件">     <a name="ZH-CN_TOPIC_0000002553198749__%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a><a name="%E7%BA%A6%E6%9D%9F%E6%9D%A1%E4%BB%B6"></a>     <h4>约束条件</h4>     <p>资源注册支持Phone、Tablet、PC/2in1设备，并且从5.1.1(19)版本开始，新增支持TV设备。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553198749__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>将UX设计师提供的Symbol图标资源（TTF文件）与动效参数资源（JSON文件）放入entry/src/main/resources/rawfile下，可新建目录。</p>       <p>说明：<a href="https://developer.huawei.com/consumer/cn/doc/design-guides/system-icons-0000001929854962" target="_blank">Symbol资源制作流程参考</a></p>       <p><span><img originheight="224" originwidth="391" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/16/v3/wPYndkLAT4ewV9vsmIVVsQ/zh-cn_image_0000002583438395.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083916Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=E92CE1375D4494BDFFE1275BD78A07C099BF4385915C80ECD0585EF5646FBBB1"></span></p></li>      <li>       <p>多语言场景，在entry/src/main/resources目录中对应语言目录下的string.json文件中配置对应的Symbol图标Unicode值。</p>       <p><span><img originheight="135" originwidth="345" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/62/v3/jzV9e27USr2-lndL6TxUlQ/zh-cn_image_0000002552958350.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083916Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=83D933757EE255EDD06FD8A980837D7868A675EB947B3FA156715BB4334D4AD1"></span></p>       <pre class="json">{
  "string": [
    {
      "name": "symbol_custom_phone_fill_1",
      "value": "0x100016"
    }
  ]
}</pre></li>      <li>       <p>导入相关模块。</p>       <pre class="typescript">import { symbolRegister } from '@kit.UIDesignKit';
import { BusinessError } from '@kit.BasicServicesKit';</pre></li>      <li>       <p>在通过SymbolGlyph/SymbolSpan组件展示自定义Symbol图标前，需要注册加载图标资源与动效参数资源。</p>       <pre class="typescript">try {
  let result = symbolRegister.registerSymbol($rawfile("symbol/symbol_register.ttf"), $rawfile("symbol/symbol_register.json"));
} catch (error) {
  let err = error as BusinessError;
  console.error("errCode: " + err.code)
  console.error("error: " + err.message);
}</pre></li>      <li>       <p>在需要展示自定义Symbol图标的页面通过SymbolGlyph/SymbolSpan组件展示该图标。</p>       <pre class="typescript">struct test {
  build() {
    Column(){
      SymbolGlyph($r('app.string.symbol_custom_phone_fill_1'))
    }
  }
}</pre></li>     </ol>    </div>    <div class="section" id="开发实例">     <a name="ZH-CN_TOPIC_0000002553198749__%E5%BC%80%E5%8F%91%E5%AE%9E%E4%BE%8B"></a><a name="%E5%BC%80%E5%8F%91%E5%AE%9E%E4%BE%8B"></a>     <h4>开发实例</h4>     <pre class="typescript">import { symbolRegister } from '@kit.UIDesignKit';
import { BusinessError } from '@ohos.base';

@Entry
@Component
struct test {
  aboutToAppear(): void {
    try {
      let result = symbolRegister.registerSymbol($rawfile("symbol/symbol_register.ttf"), $rawfile("symbol/symbol_register.json"));
    } catch (error) {
      let err = error as BusinessError;
      console.error("errCode: " + err.code)
      console.error("error: " + err.message);
    }
  }
  build() {
    Column(){
      SymbolGlyph($r('app.string.symbol_custom_phone_fill_1'))
    }
  }
}</pre>     <p><span><img originheight="162" originwidth="120" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/28/v3/0RjlyFTqRFGY4dmcGBdVvw/zh-cn_image_0000002583478351.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083916Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=FC6E5C648857F63E59AE649CA4E6992314F3997B9ECC9A1A190044F05B20A5FA"></span></p>    </div>   </div>   <div></div></body></html>
