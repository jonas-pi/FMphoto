# fnOS 第三方复现登录说明

本文说明如何在 **不打开官方浏览器手动操作** 的前提下，用自有程序完成与 Web 管理端等效的登录态，并在启动后 **直接进入已登录界面**。实现参考本仓库中的 `fnos_client.py`、`fnos_window.py`。

---

## 1. 目标与结论摘要

| 目标 | 要点 |
|------|------|
| **鉴权** | 通过 **WebSocket** 完成 `util.crypto.getRSAPub` → 加密 `user.login` → `user.authToken`（HMAC），拿到 **token** 与经 AES 解密的 **secret 材料**。 |
| **浏览器侧会话** | 仅设置 **Cookie** 不够；前端还会读 **`localStorage['fnos-Secret']`**（值为解密后 secret 的 Base64，与官方前端 `VHe`/`mz` 一致）。二者齐备后，SPA 才会认为已登录。 |
| **WebSocket 保活** | **多数情况下不必**由第三方进程单独保活一条主 WebSocket：页面加载后会自行建立 `wss`。仅当设备或版本明确要求「双连接」时，再在后台维持一条已 `authToken` 的连接（见 §5）。 |
| **直接显示登录后界面** | 使用 **嵌入式 WebView**（如 Qt WebEngine）加载 `https://<主机>:5667/`，并 **忽略自签证书**，同时注入 Cookie + 上述 localStorage。 |

---

## 2. 鉴权流程（与官方前端对齐）

### 2.1 连接

- URL 形态：`wss://<主机>:5667/websocket?type=main`（端口以实际部署为准）。
- TLS：若使用自签证书，客户端需 **关闭证书校验** 或等价处理。

### 2.2 获取 RSA 公钥

发送 JSON（示例字段）：

```json
{ "reqid": "<十六进制时间戳风格>", "req": "util.crypto.getRSAPub" }
```

响应中取 **`pub`**（PEM 公钥）、**`si`**（会话标识，后续请求需一致或按登录响应更新）。

### 2.3 加密登录包 `user.login`

1. 构造明文 JSON（与官方字段一致），包含：`reqid`、`req: "user.login"`、`user`、`password`、`deviceType`、`deviceName`、`stay`、`si` 等。
2. 生成 **32 字节 AES 密钥**、**16 字节 IV**（CBC）。
3. 用 AES-CBC + PKCS7 加密明文 JSON。
4. 用服务端 RSA 公钥（PKCS#1 v1.5）加密 **该 32 字节 AES 密钥**。
5. 发送外层 JSON：

```json
{
  "req": "encrypted",
  "iv": "<IV 的 Base64>",
  "rsa": "<RSA(AES密钥) 的 Base64>",
  "aes": "<密文 的 Base64>"
}
```

### 2.4 登录响应

成功时响应含 **`token`**、**`secret`**（Base64 密文）、可能含 **`longToken` / `long_token`**、以及可能刷新的 **`si`**。

### 2.5 `secret` 与 HMAC 密钥

- **`secret`** 不是直接的 HMAC 密钥：需用 **本次登录使用的同一 AES 密钥与 IV** 对 `secret` 做 **AES-CBC 解密并去填充**，得到二进制密钥材料 **`K`**（与官方在内存中的用法一致）。
- 后续 **`user.authToken`** 的 HMAC-SHA256：**以 `K` 为密钥**，对 **一段确定性的 UTF-8 字符串** 做 HMAC，再 Base64。

### 2.6 `user.authToken` 报文格式（易错点）

1. 构造 JSON 对象（键顺序与官方一致）：  
   `req: "user.authToken"`、`token`、`si`（**不要**默认带 `"main": true`，与官方默认 `gg(..., false)` 的 `JSON.stringify` 行为一致）。
2. `payload_str = JSON.stringify(obj)`（紧凑、无多余空格，与官方一致）。
3. `sig_b64 = Base64( HMAC_SHA256(K, payload_str 的 UTF-8 字节) )`。
4. **WebSocket 上发送的文本帧**为：  
   **`sig_b64 + payload_str`**（**中间没有 `=`**；与官方 `mz(e)+e` 一致）。

### 2.7 成功判据

`authToken` 响应中 `result == "succ"` 即协议侧登录完成。此时已具备 **token** 与 **localStorage 所需的 Base64(secret 明文)**（对 **`K`** 再 Base64，与官方写入 storage 的形式一致）。

---

## 3. 浏览器 / WebView 侧：为何仍跳登录页

仅设置 **`fnos-token`**（及可选 **`fnos-long-token`**）Cookie，**往往仍会进入登录页**，因为官方脚本还会读取：

- **`localStorage['fnos-Secret']`**：值为 **`Base64(K)`**（`K` 为 §2.5 解密结果）。

第三方需在 **同一 origin**（`https://主机:5667`）下、且在 **业务脚本大量执行前** 写入该项。实践中可在 WebEngine 里用 **`DocumentCreation` + `MainWorld`** 的注入脚本调用 `localStorage.setItem('fnos-Secret', ...)`，再加载首页。

---

## 4. 启动后直接显示「登录后」界面

推荐步骤：

1. 在本进程或子流程中完成 §2 全流程（得到 `token`、`longToken`（若有）、`K`）。
2. 启动 **Qt WebEngine**（或等价内核），并设置：
   - **`QTWEBENGINE_CHROMIUM_FLAGS`** 含 **`--ignore-certificate-errors`**（自签证书场景；须在 **首次加载 WebEngine 前** 设置）。
   - 自定义 **`QWebEnginePage.certificateError`** 中 **`acceptCertificate()`**（部分错误仍依赖 Chromium 标志）。
3. 注入 **Cookie**：`fnos-token`（及 `fnos-long-token` 若有），`Path=/`、`Secure`。
4. 注入 **localStorage**：`fnos-Secret` = `Base64(K)`。
5. **`load(QUrl("https://<主机>:5667/"))`**。

完成后，由 SPA 自行拉取 `/assets/*` 并建立 **页面内 WebSocket**；一般 **无需** Python 侧再挂一条主连接即可看到桌面。

---

## 5. WebSocket 保活（可选）

| 场景 | 建议 |
|------|------|
| 默认 | **不**在第三方进程内长期占用 `type=main` 连接；登录完成后关闭即可。 |
| 设备强制要求会话与某条 WS 绑定 | 在 **独立线程** 内 `asyncio.run`：**`login(keep_websocket_open=True)`** 后 **`async for _ in ws` 或 ping 循环**，与 UI 线程分离；注意 **同一条连接必须留在创建它的 asyncio 循环内**。 |

本仓库 **`--window-keep-ws`** / **`fnos_window.py --keep-ws`** 即此模式，供对比验证。

---

## 6. 与本仓库文件的对应关系

| 模块 | 作用 |
|------|------|
| `fnos_client.py` · `FnosClient` | WebSocket 登录、`authToken`、HTTP 辅助、`web_local_storage_secret_b64` 等。 |
| `fnos_window.py` · `show_fnos_window` | 注入 Cookie + `fnos-Secret`、加载 HTTPS、证书忽略。 |
| `fnos_window.py` · `show_fnos_url_only` / `--window-browse-only` | **不鉴权**，仅打开管理 URL（等同手动开浏览器）。 |

---

## 7. 安全与合规

- **token / secret / 密码** 属高敏感信息，勿写入日志、截图或版本库。
- **`--ignore-certificate-errors`** 仅适用于 **可信内网管理口**；勿用于访问不可信公网站点。
- 第三方接入应遵守设备厂商服务条款与本地法规。

---

## 8. 常见问题

**Q：控制台出现 Tolgee / `[object Object]` / i18n 报错？**  
A：多为翻译资源拉取失败，与登录态无必然关系，一般不影响是否进入桌面。

**Q：HTTP 5666 与 HTTPS 5667？**  
A：管理界面通常以 **5667 HTTPS** 为准；5666 常被重定向或行为不一致，实现上应以 **5667 + wss 同端口** 为参考。

**Q：仍进登录页？**  
A：核对 **`fnos-Secret` 是否为 `Base64(K)`**、Cookie 名是否 **`fnos-token`**、`authToken` 拼接是否 **无 `=`**、JSON 是否 **不含多余的 `main`**。

---

*文档版本：与本仓库实现同步描述；协议细节以实际设备固件与前端 bundle 为准。*
