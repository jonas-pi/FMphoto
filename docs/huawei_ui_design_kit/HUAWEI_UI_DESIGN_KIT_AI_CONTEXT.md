# Huawei UI Design Kit AI Context

## 用途

这份文档用于给 AI 提供 HarmonyOS UI Design Kit 的本地约束上下文。
它不是简单的网页列表，而是把抓取范围、使用原则、目录索引和正文来源统一收敛到一个文件里，方便在提示词、系统约束或项目规范中直接引用。

## 抓取状态

- 已成功拉取页面数: 45
- 文档来源: `https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-kit-guide`
- 本地原始页面目录: `docs/huawei_ui_design_kit/`
- 每个页面均已保存为单独 Markdown 文件，正文保留官方接口返回 HTML。

## 给 AI 的核心约束

- 优先保持 HarmonyOS 风格一致性，不随意替换为通用 Android、iOS 或 Web 视觉语言。
- 涉及导航、侧边栏、底部页签、即时操作、核心操作栏、列表、视效、多窗、沉浸光感时，优先复用 UI Design Kit 对应能力。
- 多设备适配是默认目标，输出方案时同时考虑 Phone、Tablet、PC/2in1、Wearable、TV 的差异与边界。
- 页面与组件应强调高端、精致、沉浸、统一体验，避免廉价装饰、随意阴影和风格拼贴。
- 如果已有 HDS 组件或光影能力可满足需求，优先建议采用官方能力，而不是自造近似控件。
- 做视觉设计时，优先检查是否可用动态模糊、流光、按压阴影、沉浸光感材质等官方能力增强体验。
- 图标与 Symbol 资源优先采用官方推荐流程，避免随意导入不符合规范的图标风格。
- 生成页面、组件或设计说明时，要明确支持设备、交互方式、限制条件和兼容边界。
- 如能力仅支持中国大陆或特定设备，应在方案中明确标注，不默认全区域、全设备可用。

## 顶层设计目标

以下内容摘自 `UI Design Kit简介` 的本地正文，用于让 AI 理解这套设计体系的总体目标。

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553198733"></a><a name="ZH-CN_TOPIC_0000002553198733"></a>  <h1>UI Design Kit简介</h1> <div><p>UI Design Kit是华为提供的符合HarmonyOS Design System规范的UI界面开发套件集合。通过提供多样式的扩展组件、丰富的光影效果，支撑开发者高效构建高端精致的界面（参见<a href="https://developer.huawei.com/consumer/cn/doc/design-guides/design-concepts-0000001795698445" target="_blank">HarmonyOS设计理念</a>），确保应用在HarmonyOS全场景设备上达成一致的视觉体验与设计品质，遵循<a href="https://developer.huawei.com/consumer/cn/doc/design-guides/general_overview-0000001929599380" target="_blank">HarmonyOS设计规范</a>。</p>  <div class="tablenoborder"><table class="docs-auto"><thead><tr><th align="left" class="cellrowborder" id="mcps1.3.2.1.4.1.1" valign="top" width="33.33333333333333%"><strong>扩展组件</strong></th> <th align="left" class="cellrowborder" id="mcps1.3.2.1.4.1.2" valign="top" width="33.33333333333333%"><strong>光影效果</strong></th> <th align="left" class="cellrowborder" id="mcps1.3.2.1.4.1.3" valign="top" width="33.33333333333333%"><strong>多设备适配</strong></th> </tr> </thead> <tbody><tr><td class="cellrowborder" valign="top" width="33.33333333333333%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/eb/v3/Eh9DSylORiagrQr9nKJ6ow/zh-cn_image_0000002552798674.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=978E8508DA64A75C3FDEBB6769D5FE7C13329CA211167F5DE72A5000153C9924"></span></p> <p>多样化的组件样式</p> </td> <td class="cellrowborder" valign="top" width="33.33333333333333%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/98/v3/91IhZjGES5uYAwZDo0UkQg/zh-cn_image_0000002583438369.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=B04321187425CDDBB3AE98B38B87C3782C79E4454864DD4CAD1FD4EDAD4F23B3"></span></p> <p>丰富UI界面光影</p> </td> <td class="cellrowborder" valign="top" width="33.33333333333333%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/fb/v3/SMX3KiriQ4euxVXDTM0fBg/zh-cn_image_0000002552958324.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=21B606C8AFB3E1577DC889C86685301AF9FAEB391C2F8C3E4AA3CEDC561DE05C"></span></p> <p>全场景一致体验</p> </td> </tr>  </tbody></table> </div>  <div class="section" id="功能全景"><a name="ZH-CN_TOPIC_0000002553198733__%E5%8A%9F%E8%83%BD%E5%85%A8%E6%99%AF"></a><a name="%E5%8A%9F%E8%83%BD%E5%85%A8%E6%99%AF"></a><h4>功能全景</h4></div>  <div class="section" id="增强型ui组件"><a name="ZH-CN_TOPIC_0000002553198733__%E5%A2%9E%E5%BC%BA%E5%9E%8Bui%E7%BB%84%E4%BB%B6"></a><a name="%E5%A2%9E%E5%BC%BA%E5%9E%8Bui%E7%BB%84%E4%BB%B6"></a><h4>[h2]增强型UI组件</h4> <div class="tablenoborder"><table class="docs-auto"><thead><tr><th align="left" class="cellrowborder" id="mcps1.3.4.2.1.3.1.1" valign="top" width="50%">组件分类</th> <th align="left" class="cellrowborder" id="mcps1.3.4.2.1.3.1.2" valign="top" width="50%">组件描述</th> </tr> </thead> <tbody><tr><td class="cellrowborder" valign="top" width="50%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/5f/v3/mlNmm_9hQPeu-Uhw1mEcaA/zh-cn_image_0000002583478325.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=F82300895F08255DA2BC8F5BA58F2E876113AC90BE64AA3AB761AF548CEEA0B0"></span></p> <p><strong><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-dynamic-blur">组件导航（HdsNavigation/HdsNavDestination）</a></strong></p> </td> <td class="cellrowborder" valign="top" width="50%">提供HdsNavigation组件作为路由导航的根视图容器，HdsNavDestination作为子页面的根容器，实现灵活跳转操作；扩展标题栏交互，支持动态模糊与菜单气泡。</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/20/v3/wQObSLjvQW2xp2eYu7OVdg/zh-cn_image_0000002552798676.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=2FCCA69E968BDAFF46FB3C70D8A5669134D30BEBAB93F295026DAC77A84B2988"></span></p> <p><strong><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-sidebar-overlay-mode">侧边栏（HdsSideBar）</a>与<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-side-menu">侧边栏菜单（HdsSideMenu）</a></strong></p> </td> <td class="cellrowborder" valign="top" width="50%"><p>侧边栏：提供可显隐的侧边栏容器，支持自定义内容区。</p> <p>侧边栏菜单：配套菜单组件支持一、二级菜单样式及新消息红点提醒。</p> </td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/1b/v3/Abj9mcCQRl2lQe3q4MKzXQ/zh-cn_image_0000002583438371.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=AE3C00B6B1660C3583C52BD8E75BB9F9105F3A38691EE61F876AF425F2B764B4"></span></p> <p><strong><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-tabs-split-line">底部页签（HdsTabs）</a></strong></p> </td> <td class="cellrowborder" valign="top" width="50%">支持视图切换，提供分割线动态显隐、背景模糊、图标出血及半屏居中布局等增强样式。</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/da/v3/f659eHPrTTK4dcaTfjNv7Q/zh-cn_image_0000002552958326.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=32D7CBF8757D7650E5B3471C9C03D88F22CAB893482AA9BA4C6FBC0D26C9E09D"></span></p> <p><strong><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-snackbar-resident-notification">即时操作（HdsSnackBar）</a>与<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-actionbar-main-buttons">核心操作栏（HdsActionBar）</a></strong></p> </td> <td class="cellrowborder" valign="top" width="50%"><p>即时操作：提供非模态通知组件，支持图文展示与快速操作按钮，用于轻量化交互反馈。</p> <p>核心操作栏：组合多个按钮，支持主按钮展开/收起的联动动效。</p> </td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/ee/v3/UX5ZyrWQRvCtQ1xJsg8UvQ/zh-cn_image_0000002583478327.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=5EB16486238CBD73FE808F4011BB874ADF2BBDCD6C42BD08CF5AE3C2EA65088A"></span></p> <p><strong><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-set-hds-slide-horizon-listitem">列表（HdsListItem）</a></strong></p> </td> <td class="cellrowborder" valign="top" width="50%">封装高端卡片样式，内置横滑删除动效，适配多设备系统风格。</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/51/v3/bm5BpwCvTRe1SX9FvCfpEQ/zh-cn_image_0000002552798678.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=8FB70B6DF784DCE6C7B3E8924C6071715E1AD3B72971E907719DD57554F073D2"></span></p> <p><strong><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-multiwindowentryinapp">应用内多窗（MultiWindowEntryInAPP）</a></strong></p> </td> <td class="cellrowborder" valign="top" width="50%">单应用多窗口入口，支持自定义图标、背板颜色与大小，实现多窗并行。</td> </tr>  </tbody></table> </div> </div>  <div class="section" id="hds沉浸视效"><a name="ZH-CN_TOPIC_0000002553198733__hds%E6%B2%89%E6%B5%B8%E8%A7%86%E6%95%88"></a><a name="hds%E6%B2%89%E6%B5%B8%E8%A7%86%E6%95%88"></a><h4>[h2]HDS沉浸视效</h4> <div class="tablenoborder"><table class="docs-auto"><thead><tr><th align="left" class="cellrowborder" id="mcps1.3.5.2.1.3.1.1" valign="top" width="50%">光效功能</th> <th align="left" class="cellrowborder" id="mcps1.3.5.2.1.3.1.2" valign="top" width="50%">功能描述</th> </tr> </thead> <tbody><tr><td class="cellrowborder" valign="top" width="50%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/d0/v3/4V-ar8SBTa68CWGsdb5uYQ/zh-cn_image_0000002583438373.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=2940DC6EEECA995872424A6B11DA7EBD5447767BA94376F0A3F4FB8D93A23DD4"></span></p> <p><strong><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-visual-effect-point-light">物理光感系统</a></strong></p> </td> <td class="cellrowborder" valign="top" width="50%">提供点光源、边缘流光及背景流光。特有“自带背景双边流光”接口，完美适配胶囊组件与屏幕边缘发光场景。</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/fb/v3/nND58cx3RxC1ZrLboO16jg/zh-cn_image_0000002552958328.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=1F101792B6E93B131D6AD256E95E97F40E7C3CE153F63D7875C7A4B05F15BA5D"></span></p> <p><strong><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-visual-effect-background-color">按压交互阴影</a></strong></p> </td> <td class="cellrowborder" valign="top" width="50%">提供按压阴影接口，自动计算组件在按压交互时的背景色变化效果，增强触控真实感。</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/85/v3/N7RPrsmbRVKm-abJMBYyFw/zh-cn_image_0000002583478329.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=850F61E2C78EE2776D15CEF5E757A360216C75AA984BC508C329725A2A73847D"></span></p> <p><strong><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-component-material">沉浸光感材质</a></strong></p> </td> <td class="cellrowborder" valign="top" width="50%">提供HDS标题栏组件和底部页签组件的沉浸光感材质能力。提升组件层次感和空间感，带来更具沉浸式的视觉和交互反馈。</td> </tr>  </tbody></table> </div> </div>  <div class="section" id="资源与图标能力"><a name="ZH-CN_TOPIC_0000002553198733__%E8%B5%84%E6%BA%90%E4%B8%8E%E5%9B%BE%E6%A0%87%E8%83%BD%E5%8A%9B"></a><a name="%E8%B5%84%E6%BA%90%E4%B8%8E%E5%9B%BE%E6%A0%87%E8%83%BD%E5%8A%9B"></a><h4>[h2]资源与图标能力</h4> <div class="tablenoborder"><table class="docs-auto"><thead><tr><th align="left" class="cellrowborder" id="mcps1.3.6.2.1.3.1.1" valign="top" width="50%">能力分类</th> <th align="left" class="cellrowborder" id="mcps1.3.6.2.1.3.1.2" valign="top" width="50%">能力说明</th> </tr> </thead> <tbody><tr><td class="cellrowborder" valign="top" width="50%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/65/v3/jfYuLV0ORmm7Ypc_je8LZw/zh-cn_image_0000002552798680.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=3D63729B8AEDBADB8577DBFA2A93DC142A8A05137501252650A4F75E1226C161"></span></p> <p><strong><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-layered-process">应用图标处理</a></strong></p> </td> <td class="cellrowborder" valign="top" width="50%">支持单层或分层图标的合成、剪切、缩放及描边，提供高效的批量处理能力。</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><p><span><img originheight="32" originwidth="54" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/d0/v3/wOkptykZR6qi46OoyzzBOg/zh-cn_image_0000002583438375.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083755Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=3AD7B9C0A41829CE7ABED20B2738850EE8BA0387D521040380760683EC9D6155"></span></p> <p><strong><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-custom-symbol-res-register">自定义 Symbol</a></strong></p> </td> <td class="cellrowborder" valign="top" width="50%">支持注册应用侧图标与动效资源，配合 ArkUI 组件展示，保持系统级视觉一致性。</td> </tr>  </tbody></table> </div> </div>  <div class="section" id="与arkui基础能力的关系"><a name="ZH-CN_TOPIC_0000002553198733__%E4%B8%8Earkui%E5%9F%BA%E7%A1%80%E8%83%BD%E5%8A%9B%E7%9A%84%E5%85%B3%E7%B3%BB"></a><a name="%E4%B8%8Earkui%E5%9F%BA%E7%A1%80%E8%83%BD%E5%8A%9B%E7%9A%84%E5%85%B3%E7%B3%BB"></a><h4>与ArkUI基础能力的关系</h4><p>UI Design Kit的导航、页签、列表、光效、应用交互等能力是基于ArkUI以下能力维度的扩展。</p>  <div class="tablenoborder"><table class="docs-auto"><thead><tr><th align="left" class="cellrowborder" id="mcps1.3.7.3.1.4.1.1" valign="top" width="33.33333333333333%">能力维度</th> <th align="left" class="cellrowborder" id="mcps1.3.7.3.1.4.1.2" valign="top" width="33.33333333333333%">ArkUI基础能力</th> <th align="left" class="cellrowborder" id="mcps1.3.7.3.1.4.1.3" valign="top" width="33.33333333333333%">UI Design Kit能力</th> </tr> </thead> <tbody><tr><td class="cellrowborder" valign="top" width="33.33333333333333%">组件导航</td> <td class="cellrowborder" valign="top" width="33.33333333333333%">基础跳转</td> <td class="cellrowborder" valign="top" width="33.33333333333333%"><strong>沉浸式体验</strong>：动态模糊标题栏、半模态样式、标题栏自定义区域、文字/图片双类型图标等</td> </tr> <tr><td class="cellrowborder" valign="top" width="33.33333333333333%">底部页签</td> <td class="cellrowborder" valign="top" width="33.33333333333333%">基础切换</td> <td class="cellrowborder" valign="top" width="33.33333333333333%"><strong>视觉增强</strong>：分割线动态显隐、页签栏模糊、图标出血设计、半屏居中对齐</td> </tr> <tr><td class="cellrowborder" valign="top" width="33.33333333333333%">列表交互</td> <td class="cellrowborder" valign="top" width="33.33333333333333%">普通展示</td> <td class="cellrowborder" valign="top" width="33.33333333333333%"><strong>高端动效：</strong> 内置横滑删除、统一样式卡片、多设备适配</td> </tr> <tr><td class="cellrowborder" valign="top" width="33.33333333333333%">光影视觉</td> <td class="cellrowborder" valign="top" width="33.33333333333333%">基础平面/材质</td> <td class="cellrowborder" valign="top" width="33.33333333333333%"><strong>增强视效</strong>：提供点光源、流光、按压阴影等系统级沉浸渲染能力</td> </tr> <tr><td class="cellrowborder" valign="top" width="33.33333333333333%">应用交互</td> <td class="cellrowborder" valign="top" width="33.33333333333333%">单窗口</td> <td class="cellrowborder" valign="top" width="33.33333333333333%"><strong>多窗并行</strong>：提供应用内多窗组件，支持自定义背板、图标与文字样式</td> </tr> <tr><td class="cellrowborder" valign="top" width="33.33333333333333%">Symbol图标</td> <td class="cellrowborder" valign="top" width="33.33333333333333%">依赖系统预置</td> <td class="cellrowborder" valign="top" width="33.33333333333333%"><strong>解耦灵活：</strong> 应用内注册自定义Symbol，不需提前预置系统</td> </tr>  </tbody></table> </div> </div>  <div class="section" id="约束与限制"><a name="ZH-CN_TOPIC_0000002553198733__%E7%BA%A6%E6%9D%9F%E4%B8%8E%E9%99%90%E5%88%B6"></a><a name="%E7%BA%A6%E6%9D%9F%E4%B8%8E%E9%99%90%E5%88%B6"></a><h4>约束与限制</h4></div>  <div class="section" id="支持的国家和地区"><a name="ZH-CN_TOPIC_0000002553198733__%E6%94%AF%E6%8C%81%E7%9A%84%E5%9B%BD%E5%AE%B6%E5%92%8C%E5%9C%B0%E5%8C%BA"></a><a name="%E6%94%AF%E6%8C%81%E7%9A%84%E5%9B%BD%E5%AE%B6%E5%92%8C%E5%9C%B0%E5%8C%BA"></a><h4>[h2]支持的国家和地区</h4><p>UI Design Kit当前仅支持中国境内（香港特别行政区、澳门特别行政区、中国台湾除外）。</p> </div>  <div class="section" id="支持的设备"><a name="ZH-CN_TOPIC_0000002553198733__%E6%94%AF%E6%8C%81%E7%9A%84%E8%AE%BE%E5%A4%87"></a><a name="%E6%94%AF%E6%8C%81%E7%9A%84%E8%AE%BE%E5%A4%87"></a><h4>[h2]支持的设备</h4> <div class="tablenoborder"><table class="docs-auto"><thead><tr><th align="left" class="cellrowborder" id="mcps1.3.10.2.1.3.1.1" valign="top" width="50%">UI Design Kit提供的能力</th> <th align="left" class="cellrowborder" id="mcps1.3.10.2.1.3.1.2" valign="top" width="50%">支持的设备类型</th> </tr> </thead> <tbody><tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-layered-process">图标处理</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet、PC/2in1、TV</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-dynamic-blur">组件导航</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet、PC/2in1、TV</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-sidebar-overlay-mode">侧边栏样式</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet、PC/2in1、TV</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-side-menu">侧边栏菜单样式</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet、PC/2in1、TV</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-tabs-split-line">底部页签</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet、PC/2in1</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-snackbar-resident-notification">即时操作</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet、PC/2in1、TV</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-actionbar-main-buttons">核心操作栏</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet、PC/2in1、TV</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-set-hds-slide-horizon-listitem">列表</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet、PC/2in1、Wearable、TV</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-custom-symbol-res-register">应用加载自定义Symbol</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet、PC/2in1、TV</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-visual-effect-point-light">HDS视效</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet、PC/2in1</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-multiwindowentryinapp">应用内多窗</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet</td> </tr> <tr><td class="cellrowborder" valign="top" width="50%"><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-component-material">沉浸光感材质</a></td> <td class="cellrowborder" valign="top" width="50%">Phone、Tablet</td> </tr>  </tbody></table> </div> </div>  <div class="section" id="能力限制"><a name="ZH-CN_TOPIC_0000002553198733__%E8%83%BD%E5%8A%9B%E9%99%90%E5%88%B6"></a><a name="%E8%83%BD%E5%8A%9B%E9%99%90%E5%88%B6"></a><h4>[h2]能力限制</h4><p><strong>HdsNavigation/HdsNavDestination：</strong> 横屏且导航栏为<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-navigation#navigationmode9枚举说明" target="_blank">Stack模式</a>时，不支持合并工具栏到菜单栏。标题栏默认采用层叠布局（位于内容区上层）。</p> </div>  <div class="section" id="规格限制"><a name="ZH-CN_TOPIC_0000002553198733__%E8%A7%84%E6%A0%BC%E9%99%90%E5%88%B6"></a><a name="%E8%A7%84%E6%A0%BC%E9%99%90%E5%88%B6"></a><h4>[h2]规格限制</h4><ul><li><p><strong>图标批量处理接口：</strong> 最大并发数为 10，单次最大处理量 500 个。</p>  </li><li><p><strong>Symbol资源注册接口：</strong> 仅支持注册 1 组图标资源与动效参数资源，最大支持 10 个自定义图标与动效参数资源注册。</p>  </li></ul> </div>  <div class="section" id="模拟器支持情况"><a name="ZH-CN_TOPIC_0000002553198733__%E6%A8%A1%E6%8B%9F%E5%99%A8%E6%94%AF%E6%8C%81%E6%83%85%E5%86%B5"></a><a name="%E6%A8%A1%E6%8B%9F%E5%99%A8%E6%94%AF%E6%8C%81%E6%83%85%E5%86%B5"></a><h4>模拟器支持情况</h4><p>本Kit支持模拟器开发，但与真机存在部分能力差异，具体差异如下：</p> <ul><li>通用差异：请参见“<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-specification#section1227613205203" target="_blank">模拟器与真机的差异</a>”。</li><li>不支持HDS沉浸视效，包括点光源效果、按压阴影、双边边缘流光、背景流光、自带背景的双边流光和沉浸光感材质。</li></ul> </div> </div> <div></div></body></html>

## 完整目录索引

- UI Design Kit（UI设计套件） | `ui-design-kit-guide`
- UI Design Kit��� | `ui-design-introduction`
- ͼ�괦�� | `ui-design-icon-process`
-   ���Ƽ����ֲ�ͼ�괦�� | `ui-design-layered-process`
-   ����ͼ�괦�� | `ui-design-normal-process`
- ������� | `ui-design-navigation`
-   ���ö�̬ģ����ʽ | `ui-design-navigation-dynamic-blur`
-   ������Ϣ���� | `ui-design-navigation-message-reminder`
-   �����Զ������� | `ui-design-navigation-customized-area`
-   ��������̬���� | `ui-design-navigation-dynamic-display-and-hiding`
-   ��ģ̬��ʽ | `ui-design-navigation-half-modal-style`
-   ͼ���������� | `ui-design-navigation-icon-type`
-   ����Ӧ���ڶര | `ui-design-navigation-set-multi-window`
-   ����ʵ�� | `ui-design-navigation-dynamic-blur-demo`
- �������ʽ | `ui-design-sidebar`
-   ����overlayģʽ�Ĳ���� | `ui-design-sidebar-overlay-mode`
-   ����embedģʽ�Ĳ���� | `ui-design-sidebar-enbed-mode`
- ������˵���ʽ | `ui-design-side-menu`
- �ײ�ҳǩ | `ui-design-hds-tabs`
-   ����ҳǩ���ķָ��� | `ui-design-hds-tabs-split-line`
-   ����ҳǩ����ģ����ʽ | `ui-design-hds-tabs-fuzzy-style`
-   ����ҳǩ��ͼ���Ѫ��ʽ | `ui-design-hds-tabs-icon-bleed-substyle`
-   ���ò�����������ж�����ʽ | `ui-design-hds-tabs-sidebar-alignment-substyle`
-   ����ҳǩ����������ʽ | `ui-design-hds-tabs-bar-floating`
- ��ʱ���� | `ui-design-snackbar`
-   ���ó�פ֪ͨ���� | `ui-design-snackbar-resident-notification`
-   ���ö�ʱ֪ͨ���� | `ui-design-snackbar-scheduled-notification`
- ���Ĳ����� | `ui-design-actionbar`
-   ����������ť����� | `ui-design-actionbar-main-buttons`
-   ����������ť����� | `ui-design-actionbar-without-master-button`
- �б� | `ui-design-list-item-card`
-   ���ø����Ử���б���ʽ | `ui-design-set-hds-slide-horizon-listitem`
-   �����б���Ƭ��ʽ | `ui-design-set-listitem-style`
- Ӧ�ü����Զ���Symbol | `ui-design-custom-symbol-res-register`
- ��Ч | `ui-design-visual-effect`
-   ���ԴЧ�� | `ui-design-visual-effect-point-light`
-   ��ѹ��Ӱ | `ui-design-visual-effect-background-color`
-   ˫�߱�Ե���� | `ui-design-visual-effect-double-edge-streamer`
-   �������� | `ui-design-visual-effect-background-streamer`
-   �Դ�������˫������ | `design-visual-effect-background-streamer-with-mask`
- Ӧ���ڶര | `ui-design-multiwindowentryinapp`
- ������� | `ui-design-hds-component-material`
- UI Design Kit�������� | `ui-design-faq`
-   ��ô��ȡlayeredDrawableDescriptor������Ϣ�� | `ui-design-faq1`
-   401 �������ʧ�ܵĿ���ԭ��ͽ���취 | `ui-design-faq2`

## 使用方式建议

- 如果你要让 AI 生成 HarmonyOS 页面或组件，可把本文件整体作为上下文输入。
- 如果任务只涉及某一类能力，可再补充对应子页面原文，例如导航、页签、列表或视效页面。
- 如果你想进一步提高稳定性，建议再额外写一份项目内的“允许/禁止事项”清单，与本文一起使用。

## 本地页面映射

- UI Design Kit（UI设计套件）: `docs/huawei_ui_design_kit/ui-design-kit-guide.md`
- UI Design Kit���: `docs/huawei_ui_design_kit/ui-design-introduction.md`
- ͼ�괦��: `docs/huawei_ui_design_kit/ui-design-icon-process.md`
- ���Ƽ����ֲ�ͼ�괦��: `docs/huawei_ui_design_kit/ui-design-layered-process.md`
- ����ͼ�괦��: `docs/huawei_ui_design_kit/ui-design-normal-process.md`
- �������: `docs/huawei_ui_design_kit/ui-design-navigation.md`
- ���ö�̬ģ����ʽ: `docs/huawei_ui_design_kit/ui-design-navigation-dynamic-blur.md`
- ������Ϣ����: `docs/huawei_ui_design_kit/ui-design-navigation-message-reminder.md`
- �����Զ�������: `docs/huawei_ui_design_kit/ui-design-navigation-customized-area.md`
- ��������̬����: `docs/huawei_ui_design_kit/ui-design-navigation-dynamic-display-and-hiding.md`
- ��ģ̬��ʽ: `docs/huawei_ui_design_kit/ui-design-navigation-half-modal-style.md`
- ͼ����������: `docs/huawei_ui_design_kit/ui-design-navigation-icon-type.md`
- ����Ӧ���ڶര: `docs/huawei_ui_design_kit/ui-design-navigation-set-multi-window.md`
- ����ʵ��: `docs/huawei_ui_design_kit/ui-design-navigation-dynamic-blur-demo.md`
- �������ʽ: `docs/huawei_ui_design_kit/ui-design-sidebar.md`
- ����overlayģʽ�Ĳ����: `docs/huawei_ui_design_kit/ui-design-sidebar-overlay-mode.md`
- ����embedģʽ�Ĳ����: `docs/huawei_ui_design_kit/ui-design-sidebar-enbed-mode.md`
- ������˵���ʽ: `docs/huawei_ui_design_kit/ui-design-side-menu.md`
- �ײ�ҳǩ: `docs/huawei_ui_design_kit/ui-design-hds-tabs.md`
- ����ҳǩ���ķָ���: `docs/huawei_ui_design_kit/ui-design-hds-tabs-split-line.md`
- ����ҳǩ����ģ����ʽ: `docs/huawei_ui_design_kit/ui-design-hds-tabs-fuzzy-style.md`
- ����ҳǩ��ͼ���Ѫ��ʽ: `docs/huawei_ui_design_kit/ui-design-hds-tabs-icon-bleed-substyle.md`
- ���ò�����������ж�����ʽ: `docs/huawei_ui_design_kit/ui-design-hds-tabs-sidebar-alignment-substyle.md`
- ����ҳǩ����������ʽ: `docs/huawei_ui_design_kit/ui-design-hds-tabs-bar-floating.md`
- ��ʱ����: `docs/huawei_ui_design_kit/ui-design-snackbar.md`
- ���ó�פ֪ͨ����: `docs/huawei_ui_design_kit/ui-design-snackbar-resident-notification.md`
- ���ö�ʱ֪ͨ����: `docs/huawei_ui_design_kit/ui-design-snackbar-scheduled-notification.md`
- ���Ĳ�����: `docs/huawei_ui_design_kit/ui-design-actionbar.md`
- ����������ť�����: `docs/huawei_ui_design_kit/ui-design-actionbar-main-buttons.md`
- ����������ť�����: `docs/huawei_ui_design_kit/ui-design-actionbar-without-master-button.md`
- �б�: `docs/huawei_ui_design_kit/ui-design-list-item-card.md`
- ���ø����Ử���б���ʽ: `docs/huawei_ui_design_kit/ui-design-set-hds-slide-horizon-listitem.md`
- �����б���Ƭ��ʽ: `docs/huawei_ui_design_kit/ui-design-set-listitem-style.md`
- Ӧ�ü����Զ���Symbol: `docs/huawei_ui_design_kit/ui-design-custom-symbol-res-register.md`
- ��Ч: `docs/huawei_ui_design_kit/ui-design-visual-effect.md`
- ���ԴЧ��: `docs/huawei_ui_design_kit/ui-design-visual-effect-point-light.md`
- ��ѹ��Ӱ: `docs/huawei_ui_design_kit/ui-design-visual-effect-background-color.md`
- ˫�߱�Ե����: `docs/huawei_ui_design_kit/ui-design-visual-effect-double-edge-streamer.md`
- ��������: `docs/huawei_ui_design_kit/ui-design-visual-effect-background-streamer.md`
- �Դ�������˫������: `docs/huawei_ui_design_kit/design-visual-effect-background-streamer-with-mask.md`
- Ӧ���ڶര: `docs/huawei_ui_design_kit/ui-design-multiwindowentryinapp.md`
- �������: `docs/huawei_ui_design_kit/ui-design-hds-component-material.md`
- UI Design Kit��������: `docs/huawei_ui_design_kit/ui-design-faq.md`
- ��ô��ȡlayeredDrawableDescriptor������Ϣ��: `docs/huawei_ui_design_kit/ui-design-faq1.md`
- 401 �������ʧ�ܵĿ���ԭ��ͽ���취: `docs/huawei_ui_design_kit/ui-design-faq2.md`

## 附录

- 本文件偏向 AI 约束与检索入口。
- 需要完整原文时，请直接读取 `docs/huawei_ui_design_kit/` 中对应页面。
- 需要重新抓取时，可运行 `node scripts/fetch_huawei_ui_design_kit.js`。
