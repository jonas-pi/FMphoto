# Changelog

本文件记录 FMphoto 各版本的显著变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [Unreleased]

### 新增

- **FN ID 登录**：登录页可直接填写 FN ID（或 `xxx.fnos.net` / `fnos.net/xxx`），经 FN Connect 云端解析后自动选路登录；「我的」页可在公网 / 内网 / 中继间切换。公网支持「域名 + 公网 IP」双探测，都通则优先域名。

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

[1.2.0-beta.1]: https://github.com/jonas-pi/FMphoto/compare/v1.1.1...v1.2.0-beta.1
[1.1.1]: https://github.com/jonas-pi/FMphoto/compare/v1.1...v1.1.1
[1.1]: https://github.com/jonas-pi/FMphoto/compare/v1.0.10...v1.1
[1.0.10]: https://github.com/jonas-pi/FMphoto/compare/v1.0.9...v1.0.10
[1.0.9]: https://github.com/jonas-pi/FMphoto/compare/v1.0.8...v1.0.9
