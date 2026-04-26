# 401 参数检查失败的可能原因和解决办法

- 页面标题: 401 参数检查失败的可能原因和解决办法
- slug: `ui-design-faq2`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-faq2
- 文档ID: `092c738c0706421187c6f0c8879aa2df`
- 更新时间: 2026-04-22 06:37:07

## 锚点目录

- 无

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002527085380"></a><a name="ZH-CN_TOPIC_0000002527085380"></a>  <h1>401 参数检查失败的可能原因和解决办法</h1> <div><p><strong>问题现象</strong></p> <p>调用接口报错401 参数检查失败。</p> <p>Parameter error. The value of bundleName is incorrect.</p> <p>Parameter error. The value of layeredDrawableDescriptor is incorrect.</p> <p>Parameter error. The value of size is incorrect.</p> <p>Parameter error. The value of hasBorder is incorrect.</p> <p>Parameter error. The value of pixelMap is incorrect.</p> <p>Parameter error. The value of mask is incorrect.</p> <p>Parameter error. The value of icons is incorrect.</p> <p>Parameter error. The value of parallelNumber is incorrect.</p> <p>Parameter error. The number of parameters is incorrect.</p> <p>Parameter error. The type of ttf resource is error, the type must be resource.</p> <p>Parameter error. The type of json resource is error, the type must be resource.</p> <p>Parameter error. The ttf resource is null.</p> <p>Parameter error. The json resource is null.</p> <p>Parameter error. Load ttf resource failed.</p> <p>Parameter error. Load json resource failed.</p> <p>Parameter error. The ttf resource size is zero.</p> <p>Parameter error. The json resource size is zero.</p> <p>Parameter error. The json resource schema is incorrect.</p> <p><strong>可能原因</strong></p> <p>必选参数没有传入，或者参数类型错误。</p> <p><strong>解决措施</strong></p> <ol><li><p>请检查必选参数是否传入，或者传的参数类型是否错误。</p>  </li><li><p>请检查传入的资源是否为空。</p>  </li><li><p>请检查注册自定义的Symbol资源时传入的JSON资源格式是否正确。</p>  </li></ol> </div> <div></div></body></html>
