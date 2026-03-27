# FMphoto

第三方**飞牛 fnOS 相册**原生鸿蒙应用（demo / 预编译包分发仓库）。源码与主开发仓库见：[FNOSforohos](https://github.com/jonas-pi/FNOSforohos)。

## 预编译包

根目录 **`entry-default-unsigned.hap`** 为未签名调试包，仅供开发机或已开启调试安装的环境使用；正式设备安装需自行签名或通过应用市场分发流程。

## 已实现功能

- **登录与会话**：服务器地址登录（HTTP/HTTPS 可切换，默认 HTTP:5666 / HTTPS:5667）；账号密码经 WebSocket 加密登录；会话保持；前台同步 Web 侧 Cookie / long-token，降低图库接口 401。
- **首页 Web**：加载飞牛 Web 入口并支持刷新。
- **相册浏览**：时间轴列表、缩略图、大图预览；支持搜索、分类/智能分类/人物等入口（随服务端能力）。
- **HDR**：缩略图与大图解码侧启用 HDR，**HDR Vivid** 等素材需查看原图时在支持设备上呈现（与解码管线一致）。
- **分享**：预览页通过 **HarmonyOS 系统分享**（`@kit.ShareKit`）调起华为分享等目标应用。
- **上传到 NAS**：相册内选择图片上传至飞牛相册；`POST /upload`（`trim-upload-file` + `Trim-*` 头）+ `POST /p/api/v1/photo/upload/notice`；**Trim-Sign** 为对 **`Trim-Path`（与请求头完全一致，含分段 URL 编码）** 的 HMAC-SHA256(secret) 后 Base64；**Trim-Mtim** 使用文件本地修改时间（秒）。
- **设置**：保存服务器地址、账号、相册父目录 `parent_guid` 等；上传路径未由接口返回时可用 `parent_guid` 作目录回退。

## 使用说明

1. 将 `entry-default-unsigned.hap` 安装到鸿蒙设备（需允许调试或未签名安装，视系统策略而定）。
2. 首次打开阅读并同意应用内免责声明。
3. 填写 NAS 地址（目前主要验证 **IPv6** 场景）、用户名、密码登录。
4. 相册无数据时，在设置中配置 **`parent_guid`** 后刷新；上传依赖相册 API 与 Web 会话一致，若 403 请对照浏览器抓包检查 `Trim-Path` / `Trim-Sign` 与 Cookie。

## 环境要求

- 可访问的飞牛 NAS 与有效账号  
- HarmonyOS 设备，已授予网络及相册/文件相关权限  

## 免责声明

此程序未经任何人审核，作者不对程序的功能、安全、合规等作出任何保证；本程序仅供学习交流使用，下载后请于 24 小时内删除，不得私自分发、转载、逆向或破解，否则由行为人自行承担被相关法律主体追责的风险。

## 相关链接

- 主仓库（源码）：<https://github.com/jonas-pi/FNOSforohos>  
- 本仓库（HAP 与简要说明）：<https://github.com/jonas-pi/FMphoto>
