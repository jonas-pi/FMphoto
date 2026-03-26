/**
 * 飞牛 OpenAPI 通用结构与登录相关类型（与 fntv-electron fn_api 对齐）
 */

/** POST JSON 可序列化字段（ArkTS 禁用 ESObject 时的替代） */
export type FnJsonValue = string | number | boolean;

/** 登出接口 data 占位（服务端可能无实质字段） */
export class LogoutResultData {
}

/** 服务端统一包裹 */
export interface FnEnvelope<T> {
  code: number;
  msg: string;
  data: T;
}

/** 业务成功时的 data：登录令牌 */
export interface LoginResultData {
  token: string;
}

/** 用户信息（按需扩展字段） */
export interface UserInfoData {
  username?: string;
}

/** item/list 请求体（影视库目录列表，可用于相册媒体库根目录浏览） */
export interface ItemListRequest {
  parent_guid: string;
  exclude_folder: number;
  sort_column: string;
  sort_type: string;
}

/** 列表项（海报等字段用于网格展示） */
export interface PlayListItem {
  guid: string;
  title: string;
  type: string;
  poster: string;
  parent_guid: string;
  file_name?: string;
}

export interface ItemListResponse {
  mdb_name: string;
  mdb_category: string;
  top_dir: string;
  dir: string;
  total: number;
  list: PlayListItem[];
}

/** 与 Web / Python fnos_gallery_mobile：additional.thumbnail 内多档地址 */
export interface GalleryThumbnailBlock {
  mUrl?: string;
  sUrl?: string;
  xsUrl?: string;
  xxsUrl?: string;
  originalUrl?: string;
  /** 视频缩略图配套的流媒体 URL（`_video_stream_rel`） */
  videoUrl?: string;
}

export interface GalleryListItemAdditional {
  thumbnail?: GalleryThumbnailBlock;
}

/**
 * `/p/api/v1/gallery/getList` 返回的 list 中单条图片记录（字段名随版本可能不同）
 */
export interface GalleryListItem {
  additional?: GalleryListItemAdditional;
  /** `_is_video_item`：值为 "video" 时为视频 */
  category?: string;
  /** 文件类型/后缀，如 "jpg"/"mp4"/"gif" */
  fileType?: string;
  /** 原图相对路径（`_pick_original_rel`） */
  originalUrl?: string;
  thumb?: string;
  /** 部分版本为 URL 字符串，部分为与 additional.thumbnail 同结构的嵌套对象 */
  thumbnail?: string | GalleryThumbnailBlock;
  cover?: string;
  poster?: string;
  small_thumb?: string;
  thumb_url?: string;
  url?: string;
  src?: string;
  path?: string;
  name?: string;
  title?: string;
  id?: string;
  guid?: string;
  filename?: string;
}

/** `GET /p/api/v1/gallery/timeline` 的 list 元素（与 Py fnos_gallery_mobile 解析一致） */
export interface GalleryTimelineDayCell {
  year?: number;
  month?: number;
  day?: number;
  itemCount?: number;
  item_count?: number;
}

export interface GalleryTimelineData {
  list?: GalleryTimelineDayCell[];
}

/** `GET /p/api/v1/gallery/getList` 响应中 `data`：含图片 list / total 等 */
export interface GalleryGetListData {
  list?: GalleryListItem[];
  items?: GalleryListItem[];
  photos?: GalleryListItem[];
  records?: GalleryListItem[];
  total?: number;
}

/** POST /p/api/v1/magic-search/do 请求体 */
export interface MagicSearchDoBody {
  keyword: string;
}

/**
 * magic-search/do 返回单条结果：
 * - 新版：通常直接返回与 gallery/getList 接近的完整媒体字段（含 category/fileType/additional.thumbnail）
 * - 旧版：仅返回 id + session，需要客户端拼接缩略图 URL
 */
export interface MagicSearchItem extends GalleryListItem {
  /** 旧版接口常见字段：缩略图会话 */
  session?: string;
}

/** magic-search/do 返回的 data */
export interface MagicSearchData {
  list?: MagicSearchItem[];
  total?: number;
}

/** 本客户端 HTTP 层统一结果 */
export interface FnClientResult<T> {
  success: boolean;
  data?: T;
  message?: string;
  certificateError?: boolean;
  /** 登录重定向后的新站点根 URL（含协议与主机） */
  moveUrl?: string;
  /** 响应 Set-Cookie 中的 fnos-long-token（与浏览器访问首页一致，供 Web 注入） */
  fnosLongToken?: string;
  /** 图库等失败时截取的正文，便于对照 NAS 真实 JSON（不记录完整密钥） */
  errorBodyPreview?: string;
}
