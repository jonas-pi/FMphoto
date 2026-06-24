# Changelog

本文件记录 FMphoto 各版本的显著变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

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

[1.0.10]: https://github.com/jonas-pi/FMphoto/compare/v1.0.9...v1.0.10
[1.0.9]: https://github.com/jonas-pi/FMphoto/compare/v1.0.8...v1.0.9
