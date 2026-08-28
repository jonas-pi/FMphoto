# Changelog

本文件记录 FMphoto 各版本的显著变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [Unreleased]

- **许可证**：改为 PolyForm Noncommercial 1.0.0，禁止商用，再分发须保留原作者 jonaspi 署名。

---

## [1.3.3] - 2026-08-28

在 [1.3.2] 上修复转码 HLS 播放。

### 修复

- **转码清晰度可播**：HLS 播放改用可复用的 Cookie 鉴权头，不再把按路径签名的 `authx` 带到 TS 分片请求上；切换 1080p / 720p / 480p 后能正常出画。
- **decode/play 地址**：识别 NAS 返回的相对 `playLink`（如 `/media/.../preset.m3u8`），拼成完整转码流地址。
- **UHD 默认档位**：2160p 及以上片源默认走 1080p 转码，避免一进页就拉 4K 原画。

### 改进

- **转码参数**：清晰度档位码率对齐网页抓包（1080p 30Mbps / 720p 12Mbps / 480p 6Mbps）。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> 本版本仅上传未签名包；`.p12` / `.p7b` / `build-profile.json5` 等密钥材料严禁入库或随 Release 分发。已安装 `1.3.2` 的设备可直接覆盖升级（`versionCode` 1003009）。

---

## [1.3.2] - 2026-08-22

在 [1.3.2-beta.4] 上发布的正式版，纳入 1.3.1 之后的预览一镜到底、幻灯片、搜索输入与连接探测改进。

### 新增

- **共享元素转场**：宫格进预览走官方一镜到底；视频封面参与转场，播放器到位后再揭开。
- **上滑详情 / 下滑退出**：未放大时纵向手势对齐系统图库；详情为官方 `bindSheet`，展开后画面避让半模态。
- **幻灯片播放**：支持顺序 / 随机、2–30 秒间隔滑条；视频等播完再切页；打开详情会暂停计时，关掉后继续。
- **幻灯片作用域**：首页播全库；人物按时间轴边播边补；智能分类 / AI 搜索按当前关键词全集播放，不截断当前屏幕。
- **缩略图落盘缓存**：时间线缩略图可落本地缓存，再次进入图库时首屏更快。

### 改进

- **预览进页**：视频以「能播」为进页条件，不再白屏空等整段下载。
- **官方弹出层**：下载质量、实况保存、幻灯片设置、更多菜单走系统 `bindSheet` / `Menu`。
- **视频播控**：进度条贴在整屏底部；幻灯片中仍可上滑详情、下滑退出。
- **分类子页更多**：人物 / 智能分类等统一「更多」入口，含多选与幻灯片。
- **AI 搜索输入**：逐字输入 / 删除、点「更多」时输入法不再反复收起再弹出。
- **连接与 2FA**：FN Connect 新中继、探测半模态、切换通道时的双因素验证。
- **上传不冻界面**：读待上传文件改走 TaskPool。
- **刷新与触感**：时间线刷新更稳，选择与下拉刷新的触觉反馈更跟手。

### 修复

- **搜索键盘闪断**：输入框与「更多」菜单拆开，避免顶栏重建把 `TextInput` 打掉。
- **幻灯片计时**：查看详情时真正停表，不再后台空转到点又切页。
- **一镜到底配对**：源/目标页转场按官方修正，减少连点进出预览时闪回。
- **分类页点不动**：全屏加载遮罩仅在真正打开预览时挂载。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> 本版本仅上传未签名包；`.p12` / `.p7b` / `build-profile.json5` 等密钥材料严禁入库或随 Release 分发。已安装 `1.3.2-beta.4` 或 `1.3.1` 的设备可直接覆盖升级（`versionCode` 1003008）。

---

## [1.3.2-beta.4] - 2026-08-18

在 [1.3.2-beta.3] 上修「我的」连接探测，并支持切换通道时的 2FA。

### 修复

- **中继探测行**：与公网 DDNS 同主机时不再被去重丢掉；探测结果始终带中继。
- **探测半模态**：2FA 与探测面板分宿主绑定，避免互相覆盖；内容不再被卡片裁切。

### 改进

- **切换通道 2FA**：切公网 / 内网 / 中继遇到双因素时，用官方半模态完成验证。
- **半模态布局**：探测与传输队列改用官方 `SheetSize.MEDIUM` / `LARGE` 档位，列表配 `nestedScroll`，便于滚到中继行。
- **中继连接**：DNS 短间隔重试，避免解析未就绪时误判失败。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> **Beta 预发布**：仅上传未签名包，供测试验证。已安装 `1.3.2-beta.3` 的设备可直接覆盖升级（`versionCode` 1003007）。

---

## [1.3.2-beta.3] - 2026-08-18

在 [1.3.2-beta.2] 上修一镜到底配对，并把 FN Connect 中继切到新集群。

### 改进

- **共享转场配对**：按官方一镜到底修正源/目标页转场；hero 复位加代次校验，减少连点进出预览时闪回。
- **上传不冻界面**：读待上传文件改走 TaskPool，避免主线程同步读整图卡顿。
- **FN Connect 中继**：支持新集群 `{fnId}.5ddd.com`（旧 `fnos.net` 仍识别）；登录可选中继通道，不再误补 5666/5667。
- **幻灯片设置**：改用官方 `bindSheet` 半模态，不再自绘全屏卡片。
- **搜索与菜单**：打开更多菜单时先收键盘，避免输入框和弹出层抢焦点。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> **Beta 预发布**：仅上传未签名包，供测试验证。已安装 `1.3.2-beta.2` 的设备可直接覆盖升级（`versionCode` 1003006）。

---

## [1.3.2-beta.2] - 2026-08-16

在 [1.3.2-beta.1] 上补齐系统图库式预览：宫格进预览走共享元素，未放大时可上滑详情、下滑退出。

### 新增

- **共享元素转场**：宫格缩略图与全屏预览用官方 `sharedTransition` 一镜到底（220ms，EaseInOut）。进页不做整页位移；遮罩延后淡入，避免一开始滤掉网格。视频封面参与转场，播放器等转场结束后再揭开。
- **上滑详情 / 下滑退出**：未放大时纵向手势对齐系统图库。下滑跟手位移并轻微缩小，过阈值走共享元素收回；上滑打开官方 `bindSheet` 详情（MEDIUM / LARGE、`dragBar`）。
- **详情半模态**：展开后媒体限制在剩余区内，上下对称裁剪，画面中心对齐剩余区中心。点剩余区或下滑可收起；返回键先关详情。视频单击优先收详情，不切工具栏。

### 改进

- **跟手不掉帧**：纵向拖动走 `AttributeUpdater`，不每帧写父页状态重建 Swiper。
- **视频侧滑热区**：亮度 / 音量热区避开上下滑区域，避免抢走详情或退出手势。
- **相册顶栏与图标**：滚动后顶栏背景与系统导航栏一致；更多、底栏图标改用系统符号，风格更统一。
- **预览顶底栏**：详情展开时工具栏淡出；去掉全屏预览的沉浸式渐变模糊，按钮背景更清晰。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> **Beta 预发布**：仅上传未签名包，供测试验证。已安装 `1.3.2-beta.1` 的设备可直接覆盖升级（`versionCode` 1003005）。

---

## [1.3.2-beta.1] - 2026-08-16

在 [1.3.1] 上打磨预览进页与系统弹出层：视频以「能播」为进页条件，不再白屏空等，也不再等到整段下完。

### 改进

- **官方弹出层**：下载质量、实况保存、幻灯片设置、更多菜单改用系统 `bindSheet` / `Menu`，不再自绘全屏玻璃层。实况保存的 SaveButton 保持实底，避免模糊父级导致临时授权失败。
- **预览进页闸门**：点进预览先在当前页显示加载；照片 / 实况等首项就绪后再进入全屏预览。
- **视频能播即进**：以预览页自己的 AVPlayer `prepared` 为就绪（官方：播放引擎已就绪）。开启 `showFirstFrameOnPrepare` 送出首帧，并把 `preferredBufferDurationForPlaying` 设为 0.3s。不等整段下载，也不等 `startRenderFrame`（该事件要等 `play()` 之后）。
- **视频加载遮罩**：出画面前用主题实底挡住 Surface，避免浅色白屏、深色空黑窗。
- **实况预览衔接**：静帧垫图保持在树上，优先用 MovingPhoto 同源静帧，就绪后再揭开，减少闪一下。

### 修复

- **视频进预览白屏**：不再用隐藏小播放器的 `prepared` 当进页条件（释放后再新建播放器等于重新拉流）。
- **分类页点不动**：全屏加载遮罩仅在真正打开预览时挂载，避免空层挡住点击。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> **Beta 预发布**：仅上传未签名包，供测试验证。已安装 `1.3.1` 的设备可直接覆盖升级（`versionCode` 1003004）。

---

## [1.3.1] - 2026-08-16

在 [1.3.0] 基础上补齐实况下载：底栏下载按钮与普通图片统一，点下去后经中间层写入系统动态照片。

### 新增

- **实况保存为系统动态照片**：预览、批量、分类、回收站下载实况时，弹出与「选择下载质量」同形态的中间层；点击官方保存控件后，封面 + 短视频写入 `PhotoSubtype.MOVING_PHOTO`，系统图库可长按播放。
- **封面和视频兜底**：也可在中间层选择「保存封面和视频」，走系统相册确认成对保存。

### 改进

- **下载按钮样式统一**：实况不再替换底栏为蓝色胶囊或叠层伪装控件，外观与点击区域与普通图片一致。
- **实况拆包落盘**：livp / Motion Photo 拆分更稳，写入失败时回退成封面 + 视频。

### 修复

- **下载按钮无响应**：去掉全屏 `bindContentCover` 透明遮罩，避免点下载后底栏被挡住。
- **安全控件黑块**：不再把官方 SaveButton 叠在底栏图标上，避免授权失败、点击无效。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> 本版本仅上传未签名包；`.p12` / `.p7b` / `build-profile.json5` 等密钥材料严禁入库或随 Release 分发。已安装 `1.3.0` 的设备可直接覆盖升级（`versionCode` 1003003）。

---

## [1.3.0] - 2026-08-16

在 [1.3.0-beta.1] 基础上发布的正式版，保留跨系统实况预览，并纳入此后的相册手势、网络选路、分类计数、鸿蒙 6 安装兼容与相册底栏层级改进。

### 新增

- **跨系统实况/动图预览**：支持安卓 Motion Photo、鸿蒙 Moving Photo、iOS Live Photo。宫格仍显示静帧封面 + 右下角同心圆标识；全屏预览长按播放（官方 `MovingPhotoView` 内置长按），开播轻微震动。
- **全屏实况标识**：预览页右下角显示带呼吸动效的同心圆，避开底部工具栏，不拦截长按。
- **HDR Vivid 提示**：加载原图并以 HDR 显示时，左下角展示官方 `hd_square_fill` 图标 + `HDR Vivid` 标签。

### 改进

- **预览工具栏局部刷新**：顶底栏显隐改走 AppStorage，点击切换不再重绘整页 Swiper，避免实况加载被打断。
- **实况播放状态**：全屏预览统一管理实况准备 / 开播 / 停止，减少手势与页面切换时的播放抖动。
- **相册手势**：宫格支持双指捏合切换粒度并恢复滚动位置；预览支持双击缩放。
- **多选与选择态**：相册、分类、回收站、搜索共用选择范围，选中遮罩与批量操作反馈更一致。
- **视频播放控制**：单击显隐控制条并自动隐藏；支持双击、长按；左右滑调节亮度 / 音量，步进更细。
- **网络选路**：登录与会话支持 IPv4 / IPv6、内网 / 公网并行探测；切网后媒体库基础地址与时间轴缓存跟随更新。
- **智能分类计数**：分类项数量优先读取多个非负计数字段，避免空值或异常数据导致计数不准。
- **系统栏沉浸**：统一沉浸栏颜色与透明点击穿透，减少主题切换时的栏色错乱。
- **鸿蒙 6 安装兼容**：`compatibleSdkVersion` 降至 `6.0.0(20)`，未升级鸿蒙 7 的设备可安装；沉浸光感仍仅在鸿蒙 6.1 及以上启用。
- **相册底栏层级**：底部 dock 仅在图库、相册、我的一级页显示；进入子页或全屏加载时隐藏，避免遮罩盖不住底栏。

### 修复

- **照片详情半模态**：同一节点不再挂两个 `bindSheet`（详情与实况保存共用一个），点击详情可正常弹出半屏。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> 本版本仅上传未签名包；`.p12` / `.p7b` / `build-profile.json5` 等密钥材料严禁入库或随 Release 分发。已安装 `1.3.0-beta.1` 的设备可直接覆盖升级（`versionCode` 1003002）。

---

## [1.3.0-beta.1] - 2026-08-15

### 新增

- **跨系统实况/动图预览**：支持安卓 Motion Photo、鸿蒙 Moving Photo、iOS Live Photo。宫格仍显示静帧封面 + 右下角同心圆标识；全屏预览长按播放（官方 `MovingPhotoView` 内置长按），开播轻微震动。
- **全屏实况标识**：预览页右下角显示带呼吸动效的同心圆，避开底部工具栏，不拦截长按。
- **HDR Vivid 提示**：加载原图并以 HDR 显示时，左下角展示官方 `hd_square_fill` 图标 + `HDR Vivid` 标签。

### 改进

- **预览工具栏局部刷新**：顶底栏显隐改走 AppStorage，点击切换不再重绘整页 Swiper，避免实况加载被打断。

### 修复

- **照片详情半模态**：同一节点不再挂两个 `bindSheet`（详情与实况保存共用一个），点击详情可正常弹出半屏。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> **Beta 预发布**：仅上传未签名包，供测试验证。已安装 `1.2.0` 的设备可直接覆盖升级（`versionCode` 1003001）。

---

## [1.2.0] - 2026-08-15

在 [1.2.0-beta.1] 验证通过后发布的正式版，功能与预发布一致。

### 新增

- **FN ID 登录**：登录页可直接填写 FN ID（或 `xxx.fnos.net` / `fnos.net/xxx`），经 FN Connect 云端解析后自动选路登录；「我的」页可在公网 / 内网 / 中继间切换。公网支持「域名 + 公网 IP」双探测，都通则优先域名。

### 改进

- **NAS 同步去重**：增强相册自动同步的指纹去重与索引处理，降低重复上传与同步抖动。
- **「我的」页样式**：优化登录态与端点切换相关界面展示。

### 修复

- **HarmonyOS 7 布局**：修复部分页面在 HarmonyOS 7 下的布局问题（底部 dock 显式设置 `barWidth` / `barSideMargin`，关闭智感握姿偏移）。
- **ArkTS 编译**：`NavigationMode` 改为使用 ArkUI 内置全局枚举，不再从 `@kit.ArkUI` 错误导入，兼容当前 SDK。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> 本版本仅上传未签名包；`.p12` / `.p7b` / `build-profile.json5` 等密钥材料严禁入库或随 Release 分发。已安装 `1.2.0-beta.1` 的设备可直接覆盖升级（`versionCode` 1002001）。

---

## [1.2.0-beta.1] - 2026-07-30

### 新增

- **FN ID 登录**：登录页可直接填写 FN ID（或 `xxx.fnos.net` / `fnos.net/xxx`），经 FN Connect 云端解析后自动选路登录；「我的」页可在公网 / 内网 / 中继间切换。公网支持「域名 + 公网 IP」双探测，都通则优先域名。

### 改进

- **NAS 同步去重**：增强相册自动同步的指纹去重与索引处理，降低重复上传与同步抖动。
- **「我的」页样式**：优化登录态与端点切换相关界面展示。

### 修复

- **HarmonyOS 7 布局**：修复部分页面在 HarmonyOS 7 下的布局问题。
- **ArkTS 编译**：`NavigationMode` 改为使用 ArkUI 内置全局枚举，不再从 `@kit.ArkUI` 错误导入，兼容当前 SDK。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> **Beta 预发布**：仅上传未签名包，供测试验证；稳定性与正式版可能有差异。

---

## [1.1.1] - 2026-07-20

### 改进

- **相册顶栏与沉浸滚动**：`GalleryAlbumTopBar` 对齐 HDS 导航样式；相册 / 分类 / 回收站等页统一滚动沉浸效果，移除废弃浮动顶栏层。
- **传输队列与预览详情**：传输队列、预览详情补充标题并恢复关闭按钮，布局更清晰。
- **自动同步性能**：NAS 指纹改为去重索引；列表拉取加并发上限；本机相册改用游标迭代，降低内存占用。
- **同步刷新体验**：下拉刷新时相册分区静默合并并通知变更，减少界面闪烁与重复加载。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（自行签名安装） |

> 本版本起 **不再上传签名包**；`.p12` / `.p7b` / `build-profile.json5` 等密钥材料也严禁入库或随 Release 分发。

---

## [1.1] - 2026-07-06

### 新增

- **全自动相册同步（开发者自用）**：对比本机相册与 NAS 全库指纹，支持待同步角标、一键批量上传；无 `READ_IMAGEVIDEO` 权限时自动回退为系统相册 Picker 手动选图（最多 500 张）。
- **传输队列**：上传、下载、同步任务统一进度展示。
- **媒体分类加载修复**：照片/视频/RAW/动图等分类页首屏裁剪后，通过 `prefetchedRemainder` 与 `getCategoryPhotos` 续拉全量，避免只显示部分条目。

### 说明

- **关于全自动同步的开放范围**：功能已在源码中实现，但依赖鸿蒙受控权限 `ohos.permission.READ_IMAGEVIDEO`（须签名 Profile 含 ACL）。**公开发布的安装包无法默认向所有用户开放该能力**；如有需要请自行在华为开发者中心为**你的包名**申请权限并本地签名安装。详见 [README — 本地相册同步与受控权限](README.md#本地相册同步与受控权限)。
- **仓库安全**：`build-profile.json5` 及 `.p12` / `.p7b` 等签名材料已移出版本库，请使用 `build-profile.json5.example` 在本地配置。

### 改进

- 登录端点选择、会话偏好与分类打开逻辑抽取为共用模块（`MediaCategoryOpenHelper` 等）。

---

## [1.0.10] - 2026-06-24

### 新增

- **随机幻灯片**：支持全库、人物相册、智能分类三种来源的流式随机播放；可在设置中调整间隔与过渡效果。
- **更多菜单**：人物相册、智能分类、搜索结果页顶栏新增「更多」，内含「多选」与「幻灯片」入口（搜索模式保留多选）。

### 改进

- **开屏体验**：简化 Index 启动页，与系统 `StartWindow` 保持同色背景与居中图标；`startIcon` 缩至 192px，按原图像素绘制，减少尺寸跳变。
- **开屏对齐**：`EntryAbility` / `Index` 在首帧前全屏并隐藏系统栏（`setSpecificSystemBarEnabled`），使图标几何中心与系统启动窗一致；深浅色启动背景随系统同步（浅色 `#F4F7FB`，深色 `#000000`）。
- **启动性能**：会话恢复并行读取 Preferences；Home 延后 long token 探测，减轻冷启动主线程压力。
- **占位视觉**：时间轴缩略图骨架色改为 `page_background`，减轻灰块到图片的对比跳变。

### 修复

- **ArkTS 编译**：`SessionPreferences.load()` 不再使用解构赋值，兼容 ArkTS 限制。

### 构建产物

| 文件 | 说明 |
| --- | --- |
| `entry/build/release/outputs/default/entry-default-signed.hap` | **Release 签名包**（推荐安装） |
| `entry/build/release/outputs/default/entry-default-unsigned.hap` | Release 未签名包 |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 未签名包（CI / 自行签名用） |

---

## [1.0.9] - 2026-06-12

### 新增

- fnOS **双因素认证（2FA）** 登录：WebSocket 两步验证、可信设备 ID 持久化。

---

## [1.0.8] 及更早

详见 Git 标签与 Release 页面历史记录。

[1.3.3]: https://github.com/jonas-pi/FMphoto/compare/v1.3.2...v1.3.3
[1.3.2]: https://github.com/jonas-pi/FMphoto/compare/v1.3.2-beta.4...v1.3.2
[1.3.2-beta.4]: https://github.com/jonas-pi/FMphoto/compare/v1.3.2-beta.3...v1.3.2-beta.4
[1.3.2-beta.3]: https://github.com/jonas-pi/FMphoto/compare/v1.3.2-beta.2...v1.3.2-beta.3
[1.3.2-beta.2]: https://github.com/jonas-pi/FMphoto/compare/v1.3.2-beta.1...v1.3.2-beta.2
[1.3.2-beta.1]: https://github.com/jonas-pi/FMphoto/compare/v1.3.1...v1.3.2-beta.1
[1.3.1]: https://github.com/jonas-pi/FMphoto/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/jonas-pi/FMphoto/compare/v1.3.0-beta.1...v1.3.0
[1.3.0-beta.1]: https://github.com/jonas-pi/FMphoto/compare/v1.2.0...v1.3.0-beta.1
[1.2.0]: https://github.com/jonas-pi/FMphoto/compare/v1.2.0-beta.1...v1.2.0
[1.2.0-beta.1]: https://github.com/jonas-pi/FMphoto/compare/v1.1.1...v1.2.0-beta.1
[1.1.1]: https://github.com/jonas-pi/FMphoto/compare/v1.1...v1.1.1
[1.1]: https://github.com/jonas-pi/FMphoto/compare/v1.0.10...v1.1
[1.0.10]: https://github.com/jonas-pi/FMphoto/compare/v1.0.9...v1.0.10
[1.0.9]: https://github.com/jonas-pi/FMphoto/compare/v1.0.8...v1.0.9
