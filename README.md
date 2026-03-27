# FNOS for HarmonyOS

非官方 HarmonyOS 客户端，用于连接并访问飞牛 NAS 的常用能力（登录、网页入口、相册浏览、预览与上传等）。

## 功能说明

- 支持服务器地址登录（HTTP/HTTPS，可手动切换）
- 支持账号密码登录与会话保持；前台会按需同步 Web 侧 Cookie / long-token，降低相册接口 401
- 支持首页 Web 内容加载与刷新
- 支持相册时间轴浏览、缩略图查看与大图预览
- 支持从相册页选择图片**上传到飞牛相册**（`POST /upload` + `POST /p/api/v1/photo/upload/notice`）
- 支持基础设置项保存（如地址、账号、相册父目录 `parent_guid` 等）

## 相册上传（实现要点）

与官方 Web 行为对齐时的约定（便于排障与二次开发）：

1. **multipart 字段名**：`trim-upload-file`（非 `file`）。
2. **请求头**：`Trim-Token`、`Trim-Sign`、`Trim-Flags`、`Trim-Overwrite`、`Trim-Mtim`、`Trim-Path` 等；其中 **`Trim-Path`** 为按路径段做 **URL 编码**后的完整目标路径（与浏览器 Network 中显示一致）。
3. **Trim-Sign**：`Base64( HMAC-SHA256( base64_decode(登录返回的 secret), UTF-8(Trim-Path 的完整字符串) ) )`——**仅对 `Trim-Path` 这一串做 HMAC**，`Trim-Mtim`、文件名等不参与签名。
4. **Trim-Mtim**：使用待上传文件的**本地修改时间**（秒级 Unix 时间戳），与常见脚本里的 `getmtime` 一致。
5. **入库通知**：上传成功后调用 `photo/upload/notice`，请求体优先使用 Web 侧形态：`files: [{ file_create_time, original_name, file_name }]`；鉴权仍走图库侧的 `authx` 等逻辑。

若上传返回 **403**，请对照浏览器成功请求核对 **`Trim-Path` 与 `Trim-Sign` 是否针对同一条路径字符串**（含编码是否一致）。

## 使用方法

1. 安装并打开应用（首次启动需阅读并确认应用内免责声明）。
2. 在登录页填写服务器地址、用户名、密码。目前主要验证过 **IPv6** 场景。
3. 按需开启或关闭 HTTPS（未写端口时默认 HTTP:5666、HTTPS:5667）。
4. 点击登录，成功后进入主页或相册页面。
5. 若相册未显示内容，请先在设置中补充 `parent_guid`（相册父目录）后刷新；上传时若接口未返回目标目录，也会用该配置作为 `Trim-Path` 目录回退。

## 环境要求

- 一台可访问的飞牛 NAS（局域网或可达网络）
- 可用的 NAS 账号与密码
- HarmonyOS 设备（已允许网络与读写相册/文件相关权限）

## 常见问题

- 登录失败：优先检查地址、端口、用户名、密码是否正确。
- HTTPS 失败：常见于证书校验问题，可按提示确认是否信任证书。
- 页面空白：先尝试刷新；仍异常时返回登录页重新登录。
- 相册为空：确认账号权限与 `parent_guid` 配置是否正确。
- 上传失败（403）：多为 `Trim-Path` / `Trim-Sign` 与服务器预期不一致，或 Cookie、Origin 与 Web 会话不一致；可开启日志中的 `[upload]` 排障行并对照浏览器抓包。

## 免责声明

此程序未经任何人审核，作者不对程序的功能、安全、合规等作出任何保证；本程序仅供学习交流使用，下载后请于 24 小时内删除，不得私自分发、转载、逆向或破解，否则由行为人自行承担被相关法律主体追责的风险。
