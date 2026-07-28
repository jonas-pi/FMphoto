# FMphoto（HarmonyOS）
面向鸿蒙设备的飞牛 NAS 第三方相册客户端，专注**原生图库交互体验 + 高质量影像呈现**。

> ⭐点亮 STAR 支持项目持续更新

飞牛鸿蒙版官方APP已开启内测申请，感兴趣可前往社区帖子查看详情：
https://club.fnnas.com/forum.php?mod=viewthread&tid=67389&extra=page%3D1

## ✨ 项目亮点
- **HDR Vivid 完整显示链路**：缩略图、大图均支持HDR解码；支持机型查看原图可呈现更高动态范围与画面层次。
- **沉浸光感视效**：以全屏浏览、时间线组织、高质量缩略图为核心，最大化照片氛围感与临场观感。
- **贴合鸿蒙原生图库操作习惯**：长按多选、连续划选、下拉刷新、触觉反馈等交互针对性优化，上手零成本。

## 📸 界面预览
| 智能分类 | 时间线网格 | 搜索结果 | 大图预览（HDR） |
| --- | --- | --- | --- |
| <img src="./docs/screenshots/01-smart-category.png" alt="智能分类页面" width="180" /> | <img src="./docs/screenshots/02-timeline-grid.png" alt="时间线网格浏览" width="180" /> | <img src="./docs/screenshots/03-search-result.png" alt="搜索结果页" width="180" /> | <img src="./docs/screenshots/04-viewer-hdr.png" alt="大图预览与HDR观感" width="180" /> |
| 按日聚合浏览 | 月视图 | 年视图 | 相册首页 |
| <img src="./docs/screenshots/05-grid-day.png" alt="按日聚合浏览" width="180" /> | <img src="./docs/screenshots/06-month-view.png" alt="按月聚合浏览" width="180" /> | <img src="./docs/screenshots/07-year-view.png" alt="按年聚合浏览" width="180" /> | <img src="./docs/screenshots/08-album-home.png" alt="相册首页入口总览" width="180" /> |

## 🧩 当前功能
- **登录与首页**：支持 HTTP/HTTPS 登录、会话保持，内置飞牛网页快捷入口。
- **图库浏览**：时间线浏览模式，支持日 / 月 / 年视图切换，网格预览与全屏看图无缝联动。
- **智能能力**：AI搜索、智能分类、媒体类型筛选、人物聚合（能力依赖NAS端功能开启）。
- **媒体预览**：图片、GIF、视频预览；支持查看媒体详情、加载原图、系统原生分享。
- **文件操作**：上传、下载、删除（回收站机制）、批量多选操作、收藏、回收站管理。
- **本地相册同步**：本机照片备份至NAS（权限限制说明见下方章节）。

## 📂 本地相册同步与受控权限
### 功能说明
源码内置**全自动相册同步逻辑**：扫描本机相册、与NAS媒体库指纹比对、统计待同步文件并批量上传。

鸿蒙系统将 `ohos.permission.READ_IMAGEVIDEO` 列为**受控权限**，除在 `module.json5` 声明外，还需要在签名Profile ACL列表中添加该权限，带来以下限制：
- **公开发布的通用安装包**：无法自动获取完整相册读取权限，全自动扫描功能不可用；
- **自行编译并本地签名**：在华为开发者中心为对应包名申请ACL权限，即可拥有完整自动同步能力；
- **无ACL权限降级方案**：自动切换为系统 `PhotoViewPicker` 手动选图上传，单次最多选择500张，无需受控权限。

### 自行申请 `READ_IMAGEVIDEO`（无需上架应用市场）
适合个人自用、小范围内部分发：
1. **注册开发者账号**
登录 [华为开发者联盟](https://developer.huawei.com/consumer/cn/) 与 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)。

2. **创建/选择应用**
应用包名必须与工程 `AppScope/app.json5` 内 `bundleName` 保持一致。

3. **申请受限开放权限**
- AGC → 目标应用 → 应用服务 → 权限管理（受限开放权限）
- 申请 `ohos.permission.READ_IMAGEVIDEO`
- 用途参考文案：`个人NAS相册备份工具，仅扫描本机未同步照片并上传至用户自有服务器，数据不会上传第三方平台。`
- 等待官方审核，个人自用场景一般可顺利通过。

4. **生成携带ACL的Profile（.p7b）**
DevEco Studio：`File → Project Structure → Signing Configs`
或 AGC → 用户与访问 → 证书管理；
创建调试/发布证书，生成Profile时勾选已获批的相册权限；
下载 `.p7b`、`.p12`、`.cer`，**请勿提交至Git仓库**。

5. **配置本地签名**
```bash
cp build-profile.json5.example build-profile.json5
```
编辑 `build-profile.json5`，填入证书路径与密码（该文件已加入 `.gitignore`）。

6. **编译安装**
通过 DevEco Studio 或 `hvigorw` 签名打包，安装至设备；首次同步照片时在系统弹窗选择**允许**。

7. **分发给其他设备（可选）**
使用同一套带ACL权限的Profile签名；调试证书需要把对方设备UDID加入Profile设备列表（存在数量上限），再安装签名后的 `.hap`。

### 无ACL权限使用方式
图库 → 更多 → 同步本地照片；若无完整相册权限，将唤起系统相册选择器手动挑选图片上传。

## 📈 开发进展
- ✅ 已完成：时间轴浏览、收藏时间线、日/月/年视图切换、本地相册同步（NAS文件指纹比对+本地同步账本）
- 🔄 持续优化：鸿蒙风格动画、页面转场体验
- 📋 规划中：文件夹分类等功能

## 🔨 构建与产物
### 首次克隆仓库
```bash
cp build-profile.json5.example build-profile.json5
# 编辑 build-profile.json5，填写本地签名配置（切勿提交到代码仓库）
```

### 产物路径
- 未签名包默认路径：`entry/build/default/outputs/default/entry-default-unsigned.hap`
- 推送 `v*` 标签后，GitHub Actions 将自动构建**未签名包**上传至Release。

> 🛡️ 安全约定：仓库仅提交/发布未签名 HAP。签名包、`.p12` / `.p7b` / `.cer`、包含密码的 `build-profile.json5` **禁止入库与上传Release**。

## 📖 使用说明
安装完成后填写NAS地址、账号密码登录即可使用。
如页面无媒体数据，请先登录飞牛NAS后台确认相册服务、AI能力、账户访问权限已正常启用。

## ⚠️ 注意事项
- 本项目为**非官方第三方客户端**，功能可用性受飞牛NAS系统版本、后台服务状态影响；
- 涉及账号登录、HTTPS证书、网络访问，请自行确认网络环境与服务可信性；
- **严禁将 `build-profile.json5`、各类证书私钥文件提交至公开代码仓库。**

## 🤝 参与贡献
欢迎提交 Issue 反馈问题、提出功能建议；同时**欢迎提交 Pull Request**，共同完善项目！
提交PR前建议先新建Issue沟通方案，保证改动方向一致。
