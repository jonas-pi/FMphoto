# fnOS 图库：获取、解析与排序说明

本文档对应实现文件 `fnos_gallery_mobile.py`，说明图库数据从 HTTP 请求到界面展示的完整链路（**获取 → 解析 → 排序/分组**）。登录与 `FnosClient` 行为见 `fnos_client.py`。

与 **`fnos_gallery_mobile.py` 文件头**、**`show_gallery_mobile()` 的 docstring** 及 **`fnos_client.py` 中 `--mobile-gallery` 相关 help** 描述的是同一套行为（首页 timeline+getList；相册 album/photos）。

---

## 1. 总体架构：两条主路径

图库界面不是单一接口，而是按场景分叉：

| 场景 | 数据来源 | 服务端排序 | 客户端再处理 |
|------|----------|------------|--------------|
| **首页图库**（无 `album_id`） | `gallery/timeline` + 按日 `gallery/getList` | Timeline 给出「按日条目数」；getList 由 `start_time`/`end_time` 限定单日 | 对 timeline **按日期从新到旧排序**；按日顺序拉 getList，`offset` 分页 |
| **指定相册**（`album_id` 或 Hub 点入） | `album/photos`（offset 分页） | `sort_by=date_time`、`sort_direction=desc` | **按条目的 `photoDateTime`/`dateTime` 解析出公历日**，在客户端分组成「年-月 / 月-日」区块；无日期进占位组 |

> 说明：仓库里仍保留 `album/normal/timeline`、`album/normal/getList` 等函数，供兼容或调试；**当前相册主界面与 Web 相册墙一致，走的是 `album/photos`**，不是按日的 `album/normal/getList`。

入口函数为 `show_gallery_mobile()`：根据是否传入 `items`、`album_hub`、`album_id` 决定走 Hub、相册墙或首页时间轴。

**参数备忘**：`show_gallery_mobile(..., start_time=..., end_time=...)` 目前**未接入**主分支（首页单日由 timeline 推导；相册用 `album/photos` 的排序参数）。`fnos_gallery_mobile` 独立 CLI 仍保留 `--start-time` / `--end-time` 以便将来与 `extra_params` 或 getList 打通。

---

## 2. 获取（HTTP）：URL、鉴权与参数

### 2.1 共同约定

- **协议**：HTTPS，端口默认与 `FnosClient.https_port` 一致（常见 `5667`）。
- **Referer**：图库类 XHR 使用 `https://{host}:{https_port}/p/`（与挂在 `/p` 的 SPA 一致）。
- **请求头**：除 Cookie 外，需 **`authx`**（签名）与 **`AccessToken`**（登录后的 token）。签名算法与前端 `galleryApi`/`albumApi` 的 `baseQuery(Ki)` 对齐，由 `build_p_api_authx()` 生成。
- **Query 编码**：键按字典序排序、`urlencode` 后把 `+` 换成 `%20`（`_i_ge`），否则服务端校验 `authx` 会失败。
- **路径前缀**：设备上接口多在 **`/p/api/v1/...`**；裸 `/api/v1/...` 有时返回整站 HTML。`path_prefix=None` 时会**依次尝试**带 `/p` 与不带 `/p` 的候选 URL，直到得到 JSON 200；也可用 CLI `--gallery-api-prefix /p` 固定前缀。

### 2.2 首页：时间轴 `gallery/timeline`

- **函数**：`fetch_gallery_timeline()`
- **方法**：GET
- **候选路径**：`_timeline_url_candidates(path_prefix)` → 如 `/p/api/v1/gallery/timeline`
- **签名路径常量**：`_GALLERY_TIMELINE_SIGN_PATH` = `/p/api/v1/gallery/timeline`（与前端一致，**与实际 GET path 是否带 `/p` 无关**）
- **Query**：`extra_params` 合并进参数字典后 `_i_ge`；若需在「某相册下的首页时间轴」筛选，可把 `album_id` 放进 extra（见 `_merge_timeline_list_extra`）

### 2.3 首页：单日列表 `gallery/getList`

- **函数**：`fetch_gallery_list()`
- **方法**：GET
- **候选路径**：`_getlist_url_candidates(path_prefix)`
- **签名路径常量**：`_GALLERY_GETLIST_SIGN_PATH` = `/p/api/v1/gallery/getList`
- **固定/默认参数**（与前端 dayjs `YYYY:MM:DD HH:mm:ss` 一致）：
  - `start_time` / `end_time`：单日窗口，由 `_day_time_range_str(y,m,d)` 生成，例如 `2025:03:25 00:00:00` ～ `2025:03:25 23:59:59`
  - `mode`：默认 `index`（首页）；搜索等可为 `search`、`ai_search` 等
  - `offset`、`limit`：分页；界面每批 `_DATE_FEED_BATCH`（30）
- **extra_params**：可覆盖或追加任意 query 字段（如 `album_id`）

### 2.4 相册墙：`album/photos`

- **函数**：`fetch_album_photos()`
- **方法**：GET
- **候选路径**：`_album_photos_url_candidates(path_prefix)`
- **签名路径**：`_ALBUM_PHOTOS_SIGN_PATH` = `/p/api/v1/album/photos`
- **Query**（与 Z8 `tfe` 一致）：
  - `album_id`：数字相册 ID
  - `sort_by`：默认 `date_time`
  - `sort_direction`：默认 `desc`
  - `offset`、`limit`：分页（界面同样按批 `_DATE_FEED_BATCH`）

### 2.5 相册列表（Hub）

- **函数**：`fetch_album_list()`  
- 用于 `album_hub=True` 时先展示相册列表，点击后再打开上述相册墙窗口。

### 2.6 静态模式

若 `show_gallery_mobile(items=[...])` 传入已构造好的列表，则**不再请求** timeline/getList/photos，仅做缩略图网格展示（解析/排序由调用方保证）。

---

## 3. 解析：从 HTTP 正文到「条目」列表

### 3.1 响应外壳（所有 JSON API 共性）

1. `json.loads` 得到根对象。
2. **`code`**：`0`、`None`、`"0"` 视为成功，否则抛出业务错误（`message`/`msg`）。
3. **`data`**：期望为 `dict`；若不是则当作空 `{}`。
4. **`data.list`**：期望为 `list`；逐项过滤 **`isinstance(x, dict)`**，得到统一类型的 **`list[dict]`** 条目列表。

若响应像 HTML（404 壳、`<!doctype` 等），`_response_looks_like_spa_shell()` 为真，实现会换 URL 候选或报错。

### 3.2 时间轴 `timeline` 条目 → 「日单元」

原始 `data.list` 中每一项经 **`_parse_timeline_day_cells()`** 转为：

```text
{ "year": int, "month": int, "day": int, "itemCount": int }
```

- 字段名优先 `year` / `month` / `day`；数量优先 `itemCount`，否则 `item_count`。
- 缺字段或类型无法转 `int` 的项会被跳过。
- `itemCount` 下限为 0（`max(0, int(ic))`）。

### 3.3 `getList` / `album/photos` 条目（媒体项）

每条为自由 `dict`，界面与工具函数常用字段包括：

| 用途 | 字段（多选一或嵌套） |
|------|----------------------|
| 缩略图 | `additional.thumbnail` 或 `thumbnail` 下的 `mUrl`、`sUrl`、`xsUrl` 等（`_pick_thumb_rel`） |
| 原图 | `originalUrl`（`_pick_original_rel`） |
| 视频 | `category == "video"`、`fileType`、`thumbnail.videoUrl` 等（`_is_video_item`、`_video_stream_rel`） |
| 相册按日分组 | `photoDateTime`、`dateTime` 等（`_calendar_day_from_item`） |

---

## 4. 排序与分组

### 4.1 首页：时间轴日的顺序

1. `_parse_timeline_day_cells()` 得到若干日单元。
2. **`_sort_timeline_days_newest_first()`**：按 `(year, month, day)` **字典序逆序**，即**新日期在前**。
3. 过滤 **`itemCount > 0`** 的日，避免空日占位。

之后 UI 按该顺序维护 `_day_i`，逐日请求 getList。

### 4.2 首页：单日内的顺序与分页

- **服务端**：`getList` 在 `start_time`～`end_time` 内按产品默认顺序返回（客户端未再排序）。
- **客户端**：对每个 `(y,m,d)` 维护 `_off[key]`，请求 `offset=_off[key]`、`limit=_DATE_FEED_BATCH`；直到该日 `off >= itemCount` 或返回条数 `< limit`，再进入下一日。

单日时间字符串与前端一致：**`YYYY:MM:DD 00:00:00`** 与 **`23:59:59`**（`_day_time_range_str`）。

### 4.3 相册：`album/photos` 流

1. **服务端排序**：请求里写死 `sort_by=date_time`、`sort_direction=desc`，即全相册按时间**新→旧**分页。
2. **客户端分组**：对每一批 `items`：
   - 用 **`_calendar_day_from_item(it)`** 从字符串头解析 `年[:/-]月[:/-]日`（支持 `photoDateTime`、`dateTime` 等键）。
   - 解析成功：归入 `groups[(y,m,d)]`。
   - 解析失败：放入 **`unparsed`**，最后统一挂到占位日 **`_ALBUM_FALLBACK_CALENDAR_DAY = (9000, 1, 1)`**，界面标题为「相册 / （条目无拍摄日期字段）」。

注意：同一批 API 返回可能跨多天，因此是**按批拆分后插入多个日区块**；区块之间的先后顺序由**该批内条目出现的分组顺序**决定（Python 3.7+ `dict` 保序），若需与 Web 完全一致可再按日期键排序后 `add_thumbs`（当前实现未做额外全局排序）。

### 4.4 与「排序」相关的 authx 细节

- `authx` 的签名原文来自 **排序后的 query 键值**（GET）或 body（POST）。
- `getList` 的 `sign_url_path` 固定为 **`/p/api/v1/gallery/getList`**（无 query），与 axios 的 `prepareHeaders` 一致；**实际请求的 path 可以是 `/p/...` 或 `/api/...`**，但签名用常量 path。

---

## 5. 界面加载节奏（与排序的配合）

`_create_gallery_date_feed_window()` 内：

- **相册模式**（`album_normal_api=True`）：滚动接近底部时反复调用 `_load_album_photos_page()`，只增 `offset`，直到返回条数 `< limit`。
- **首页模式**：滚动触发 `_load_batch()`，按 `_days[self._day_i]` 取当前日，用 `_off` 做 getList 分页；一日耗尽则 `_day_i += 1`。

首屏若内容不足以产生滚动条，**`_fill_viewport`** 会定时再触发加载，直到撑满或数据耗尽。

---

## 6. 调试清单

1. **401/签名错误**：检查 `authx` 参数是否与 URL query 完全一致（键序、`%20`、布尔与数字的字符串形式）。
2. **HTML 而非 JSON**：尝试 `--gallery-api-prefix /p` 或抓包确认真实 path。
3. **相册空或不对**：确认相册详情是否应走 **`album/photos`** 而非 `album/normal/getList`。
4. **缩略图裂图**：流式 URL 需 Cookie + Referer；图片路径还需 `authx` + `AccessToken`（视频 `/stream/v/` 仅 Cookie + Referer）。

---

## 7. 关键符号索引（代码中）

| 符号 | 含义 |
|------|------|
| `_i_ge` | Query 字符串构造（排序 + 编码） |
| `build_p_api_authx` | `authx` 请求头 |
| `fetch_gallery_timeline` / `fetch_gallery_list` | 首页时间轴 + 按日列表 |
| `fetch_album_photos` | 相册墙分页 |
| `_parse_timeline_day_cells` / `_sort_timeline_days_newest_first` | 时间轴解析与排序 |
| `_calendar_day_from_item` | 相册条目解析到 (年,月,日) |
| `_day_time_range_str` | 单日 getList 时间窗 |
| `show_gallery_mobile` | CLI/GUI 入口与分支 |

如需对照前端 bundle，可搜索 `index-CMMtM_XE.js` 中的 `galleryApi`、`albumApi` 与 `baseQuery(Ki)` 签名逻辑。
