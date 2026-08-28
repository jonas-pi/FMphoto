# FMphoto（HarmonyOS）

面向鸿蒙设备的飞牛 NAS 相册客户端。交互贴近系统图库，预览支持 HDR 与实况照片。

> 如果这个项目对你有用，欢迎点亮 **Star**。

飞牛官方鸿蒙 App 已开放内测申请：[社区帖](https://club.fnnas.com/forum.php?mod=viewthread&tid=67389&extra=page%3D1)。本项目为**非官方**客户端。

## 功能

- **登录**：FN ID、HTTP/HTTPS、会话保持，可打开飞牛网页。
- **图库**：时间线日 / 月 / 年浏览，双指捏合切换粒度，长按多选、连续划选。
- **预览**：图片、GIF、视频、跨系统实况（安卓 / 鸿蒙 / iOS）；宫格进预览一镜到底；未放大时可上滑详情、下滑退出。
- **智能能力**：AI 搜索、智能分类、人物相册（需 NAS 侧开通）。
- **文件操作**：上传、下载、收藏、删除与回收站、批量操作、幻灯片。
- **本机同步**：可将手机相册备份到 NAS。公开发布包走系统选图（单次最多 500 张）；自行申请相册读取权限并签名后，可全自动扫描上传。

## 介绍图

| 智能分类 | 时间线网格 | 搜索结果 | 大图预览（HDR） |
| --- | --- | --- | --- |
| <img src="./docs/screenshots/01-smart-category.png" alt="智能分类页面" width="180" /> | <img src="./docs/screenshots/02-timeline-grid.png" alt="时间线网格浏览" width="180" /> | <img src="./docs/screenshots/03-search-result.png" alt="搜索结果页" width="180" /> | <img src="./docs/screenshots/04-viewer-hdr.png" alt="大图预览与HDR观感" width="180" /> |
| 按日聚合浏览 | 月视图 | 年视图 | 相册首页 |
| <img src="./docs/screenshots/05-grid-day.png" alt="按日聚合浏览" width="180" /> | <img src="./docs/screenshots/06-month-view.png" alt="按月聚合浏览" width="180" /> | <img src="./docs/screenshots/07-year-view.png" alt="按年聚合浏览" width="180" /> | <img src="./docs/screenshots/08-album-home.png" alt="相册首页入口总览" width="180" /> |

## 下载

Release 只提供**未签名 HAP**（`entry-default-unsigned.hap`），不能直接点开安装。

[![正式版](https://img.shields.io/github/v/release/jonas-pi/FMphoto?label=stable)](https://github.com/jonas-pi/FMphoto/releases/latest)
[![Beta](https://img.shields.io/github/v/release/jonas-pi/FMphoto?include_prereleases&filter=*beta*&label=beta)](https://github.com/jonas-pi/FMphoto/releases)
[![License: Noncommercial](https://img.shields.io/badge/License-PolyForm--Noncommercial-blue.svg)](./LICENSE)

| 渠道 | 说明 | 入口 |
| --- | --- | --- |
| **正式版** | 最新稳定版，GitHub 会自动跳转 | [Latest Release](https://github.com/jonas-pi/FMphoto/releases/latest) |
| **Beta 版** | 预发布，功能更新、可能不稳定 | [Releases](https://github.com/jonas-pi/FMphoto/releases) 里带 **Pre-release** 的最新一条 |

## 安装（鸿蒙侧载）

纯血鸿蒙不能像安卓那样随便装未知来源包。HAP **必须用华为开发者证书签名** 后，才能装到真机；未签名会报「签名文件不存在」（9568320）。官方说明见 [配置调试签名](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-signing)。

推荐普通用户用开源工具 [小白调试助手 Auto-Installer](https://github.com/likuai2010/auto-installer)（会用你的华为账号给 HAP 签调试证书并安装）：

1. 从上方 Release 下载 `entry-default-unsigned.hap`。
2. 手机：设置 → 关于本机，连续点击 **软件版本**，开启开发者模式（会重启）。
3. 设置 → 系统 → 开发者选项，打开 **USB 调试**（或无线调试）。
4. 电脑安装 Auto-Installer，用 USB 连接手机（首次需在手机上点允许调试）。
5. 把 HAP 拖进工具，登录华为账号，按提示签名并安装。

开发者也可在 [DevEco Studio](https://developer.huawei.com/consumer/cn/deveco-studio/) 里对工程自动签名后，用 `hdc install` 安装。

安装后填写 NAS 地址与账号即可使用。部分入口无数据时，请先在 NAS 确认相册服务、AI 能力与账户权限已开启。

**注意**：请只从本仓库 GitHub Release 下载；签名材料（`.p12` / `.p7b` / `.cer`）不要发给他人。侧载应用一般需保持开发者模式开启。

## 许可证

本项目由 **jonaspi** 原创并持有著作权，采用 [PolyForm Noncommercial License 1.0.0](./LICENSE)（[NOTICE](./NOTICE)）。

- **允许**：个人学习、自用、非商业再分发与修改。
- **禁止**：任何商用，包括售卖、收费分发，以及作为商业产品或服务的一部分。
- **署名**：复制、修改或再分发时必须保留原作者 **jonaspi** 及许可证中的 `Required Notice`。
