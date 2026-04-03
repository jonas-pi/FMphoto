/**
 * 飞牛 HTTPS 请求封装：Authx、重试、重定向、按站点跳过证书校验（remoteValidation）
 *
 * 命名空间说明：
 * - `/v/api/v1`：OpenAPI（登录、user/info、item/list 等），与路径里的「影视」H5 路由 /v/i/… 不是一回事。
 * - `/p/api/v1`：相册/照片相关 **HTTP API** 前缀；其中 `gallery/getList` 为按时间范围拉取相册 **图片列表（list）** 的接口。
 * 相册 H5 常见为站点根 **`/album`**（另有 **`/p/album`** 等）；`/p/api/v1/...` 为并列的 HTTP API（原生相册已改为 Web 时仍可用于扩展）。
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { CertPolicy } from './CertPolicy';
import { genFnAuthx, generateRandomDigits, sha256DigestSafe } from './AuthxSigner';
import { buildGallerySortedQuery, FnGalleryGetSignSpec, genFnGalleryAuthxGet, genFnGalleryAuthxPost, genFnGalleryAuthxPostRaw } from './FnGalleryAuthx';
import {
  FN_PHOTO_API_PREFIX,
  FN_PHOTO_API_V2_PREFIX,
  FN_PHOTO_H5_ALBUM_PAGE,
  fnPhotoLongTokenProbePaths
} from './FnPhotoRoutes';
import { fnWebDefaultUserAgent, injectFnWebCookies, mergeGalleryWebCookieIntoNativeHeader } from './FnWebCookies';
import { fnWebViewBaseUrl } from './ServerUrl';
import {
  FnClientResult,
  FnJsonValue,
  GalleryGetListData,
  GalleryListItem,
  GalleryPhotoDetailData,
  GalleryTimelineData,
  ItemListRequest,
  ItemListResponse,
  LoginResultData,
  LogoutResultData,
  MagicSearchData,
  MagicSearchDoBody,
  MediaCategoryItem,
  MediaCategoryData,
  RecycleBinListData,
  SmartCategoryData,
  AiPersonData,
  AiPersonDetailData,
  PersonInPhotoData,
  SearchResultsData,
  UserInfoData
} from '../model/FnApiTypes';

const DOMAIN = 0xFF00;
const TAG = 'FnHttp';

/** 图库 GET 空 query 参数（避免未类型化的 `{}` 字面量） */
const GALLERY_QUERY_EMPTY: Record<string, string | number | boolean> = {};

/** 上传前一次性读出文件内容与本地修改时间（秒），对齐 Python `os.path.getmtime` + Trim-Mtim */
interface UploadFileReadResult {
  buffer: ArrayBuffer;
  mtimeSec: number;
}

const DEFAULT_TIMEOUT = 10000;
const MAX_REDIRECTS = 8;

/** 飞牛 OpenAPI 统一前缀 */
const FN_OPENAPI_PREFIX = '/v/api/v1';

/**
 * 与 `FnWebCookies.buildFnWebCookieHeader` 字段顺序一致（long-token 在 Trim-MC 之前），避免与内置 Web 会话不一致。
 */
function buildFnApiCookieHeader(token: string, longToken: string = ''): string {
  if (token.length === 0) {
    return longToken.length > 0 ? `fnos-long-token=${longToken}; mode=relay` : 'mode=relay';
  }
  let s = `fnos-token=${token}; language=zh-CN`;
  if (longToken.length > 0) {
    s += `; fnos-long-token=${longToken}`;
  }
  s += `; Trim-MC-token=${token}; mode=relay`;
  return s;
}

/**
 * /upload 专用 Cookie：只保留与官方 Web 一致的三项，
 * 不含 Trim-MC-token 和 mode=relay，防止 nginx 将上传路由到中继服务。
 */
function buildUploadCookieHeader(token: string, longToken: string = ''): string {
  let s = '';
  if (longToken.length > 0) {
    s = `fnos-long-token=${longToken}`;
  }
  s += (s.length > 0 ? '; ' : '') + 'language=zh-CN';
  if (token.length > 0) {
    s += `; fnos-token=${token}`;
  }
  return s;
}

/**
 * 先合并 WebView 同源 Cookie（可能含仅 H5 下发的键），再剔除上传禁止项。
 * 全精简 Cookie 时部分 NAS 返回 HTTP 403；带 mode=relay / Trim-MC-token 又易 HTTP 400。
 */
function stripUploadForbiddenCookieKeys(cookie: string): string {
  if (cookie.length === 0) {
    return '';
  }
  const parts = cookie.split(';');
  const kept: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const seg = parts[i].trim();
    if (seg.length === 0) {
      continue;
    }
    const eq = seg.indexOf('=');
    const nameRaw = eq > 0 ? seg.substring(0, eq).trim() : seg;
    const nameLow = nameRaw.toLowerCase();
    if (nameLow === 'mode' || nameLow === 'trim-mc-token') {
      continue;
    }
    kept.push(seg);
  }
  return kept.join('; ');
}


/** 与 fnos_gallery_mobile._GALLERY_TIMELINE_SIGN_PATH / 双路径候选一致 */
const GALLERY_TIMELINE_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/gallery/timeline`;
const GALLERY_TIMELINE_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/gallery/timeline`,
  '/api/v1/gallery/timeline'
];
/** getList 实际 URL 可为 /api/v1/...，但 authx 签名 path 恒为 /p/api/v1/gallery/getList */
const GALLERY_GETLIST_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/gallery/getList`;
const GALLERY_GETLIST_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/gallery/getList`,
  '/api/v1/gallery/getList'
];
/** 最近添加：时间轴与列表接口（抓包：/p/api/v1/explore/recent_timeline, /p/api/v1/explore/recent_photos） */
const RECENT_TIMELINE_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/explore/recent_timeline`;
const RECENT_TIMELINE_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/explore/recent_timeline`,
  '/api/v1/explore/recent_timeline'
];
const RECENT_PHOTOS_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/explore/recent_photos`;
const RECENT_PHOTOS_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/explore/recent_photos`,
  '/api/v1/explore/recent_photos'
];
/** getOne 详情接口：与 getList 同签名体系 */
const GALLERY_GETONE_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/gallery/getOne`;
const GALLERY_GETONE_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/gallery/getOne`,
  '/api/v1/gallery/getOne'
];
/** folder_view 文件列表（按文件夹路径取媒体） */
const GALLERY_FOLDER_FILELIST_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/folder_view/getFileList`;
const GALLERY_FOLDER_FILELIST_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/folder_view/getFileList`,
  '/api/v1/folder_view/getFileList'
];
/** 回收站列表：签名 path 与 gallery 系列一致为 /p/api/v1/... */
const RECYCLE_BIN_LIST_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/recycle-bin/list`;
/** 照片中人物识别：GET /p/api/v1/ai-person/personInPhoto?id=xxx */
const PERSON_IN_PHOTO_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/ai-person/personInPhoto`;
const PERSON_IN_PHOTO_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/ai-person/personInPhoto`,
  '/api/v1/ai-person/personInPhoto'
];

/** 疑似证书类错误码（NetStack） */
const CERT_CODES: number[] = [2300060, 2300058, 2300059, 2300077];

/** 重定向解析结果 */
interface ResolvedLocation {
  newBase: string;
  newPath: string;
}

/** 底层 HTTP 原始响应 */
interface RawHttpResult {
  code: number;
  headers: object;
  body: string;
}

/** 网络异常形态（catch 用） */
interface NetErrorLike {
  code?: number;
  message?: string;
}

interface GalleryAssetSignParts {
  signPath: string;
  queryParams: Record<string, string | number | boolean>;
}

interface LocalDayRange {
  start: string;
  end: string;
}

interface AssetBufferCacheEntry {
  timeMs: number;
  data: ArrayBuffer;
}

interface UploadNoticeResult {
  ok: boolean;
  message: string;
}

/** 视频转码播放参数（对齐 /p/api/v1/video/decode/play 抓包字段） */
export interface VideoDecodePlayRequest {
  id: string;
  resolution: string;
  bitrate: number;
  audioIndex: number;
  videoEncoder: string;
  channels: number;
}

/** 视频转码播放结果（供播放器展示调试信息） */
export interface VideoDecodePlayInfo {
  playUrl: string;
  hlsTimeSec: number;
}

class MultipartBodyData {
  contentType: string = '';
  body: ArrayBuffer = new ArrayBuffer(0);
}

/** 从响应头解析 Set-Cookie 中的 fnos-long-token（与浏览器首页 Cookie 一致） */
function parseFnosLongTokenFromHeaders(headers: object): string | undefined {
  const h = headers as Record<string, string | Array<string>>;
  const keys = Object.keys(h);
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    if (k.toLowerCase() !== 'set-cookie') {
      continue;
    }
    const v = h[k];
    const arr: Array<string> = Array.isArray(v) ? v as string[] : [String(v)];
    const mark = 'fnos-long-token=';
    for (let j = 0; j < arr.length; j++) {
      const line = arr[j];
      const idx = line.indexOf(mark);
      if (idx < 0) {
        continue;
      }
      let rest = line.substring(idx + mark.length);
      const semi = rest.indexOf(';');
      if (semi >= 0) {
        rest = rest.substring(0, semi);
      }
      const trimmed = rest.trim();
      if (trimmed.length > 0) {
        return trimmed;
      }
    }
  }
  return undefined;
}

function getHeader(headers: object, key: string): string | undefined {
  const h = headers as Record<string, string | Array<string>>;
  const tryKeys: string[] = [key, key.toLowerCase(), key.toUpperCase()];
  for (let i = 0; i < tryKeys.length; i++) {
    const k = tryKeys[i];
    const v = h[k];
    if (v === undefined) {
      continue;
    }
    if (Array.isArray(v)) {
      return v.length > 0 ? v[0] : undefined;
    }
    return v;
  }
  return undefined;
}

function mergePostBody(data: Record<string, FnJsonValue> | undefined): Record<string, FnJsonValue> {
  const out: Record<string, FnJsonValue> = {};
  if (data) {
    const keys = Object.keys(data);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      out[k] = data[k];
    }
  }
  out['nonce'] = generateRandomDigits();
  return out;
}

function escapeJsonString(input: string): string {
  return input.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function decodeUriPartSafely(input: string): string {
  try {
    return decodeURIComponent(input);
  } catch (_e) {
    return input;
  }
}

function trimJoinPath(dirPath: string, fileName: string): string {
  const d = dirPath.trim();
  const f = fileName.trim();
  if (d.length === 0) {
    return f;
  }
  if (f.length === 0) {
    return d;
  }
  if (d.endsWith('/')) {
    return `${d}${f}`;
  }
  return `${d}/${f}`;
}

/** 取 Unix 风格路径最后一段（用于 notice 的 file_name 与 trim-path 末段对齐） */
function lastUnixPathSegment(fullPath: string): string {
  const t = fullPath.trim().replace(/\/+$/, '');
  if (t.length === 0) {
    return '';
  }
  const i = t.lastIndexOf('/');
  return i >= 0 ? t.substring(i + 1) : t;
}

/**
 * trim-path 头的编码：保留 "/"，仅编码路径段字符（与浏览器抓包形态一致）。
 */
function encodeTrimPath(path: string): string {
  const p = path.trim();
  if (p.length === 0) {
    return '';
  }
  const segs = p.split('/');
  const out: string[] = [];
  for (let i = 0; i < segs.length; i++) {
    const one = segs[i];
    if (one.length === 0) {
      out.push('');
      continue;
    }
    out.push(encodeURIComponent(one));
  }
  return out.join('/');
}

function pad2(v: number): string {
  return v < 10 ? `0${v}` : String(v);
}

function localDayRangeNow(): LocalDayRange {
  const d = new Date();
  const y = d.getFullYear();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  const start = `${y}:${pad2(m)}:${pad2(day)} 00:00:00`;
  const end = `${y}:${pad2(m)}:${pad2(day)} 23:59:59`;
  const out: LocalDayRange = { start: start, end: end };
  return out;
}

/**
 * 按时间轴单元（year/month/day）构造 getList 所需的日范围字符串。
 * 上传后的入库日期不一定等于“今天”（例如按 EXIF 回写历史日期），
 * 因此校验时优先依据 timeline 分桶来查对应日期。
 */
function localDayRangeByYmd(year: number, month: number, day: number): LocalDayRange {
  const start = `${year}:${pad2(month)}:${pad2(day)} 00:00:00`;
  const end = `${year}:${pad2(month)}:${pad2(day)} 23:59:59`;
  const out: LocalDayRange = { start: start, end: end };
  return out;
}

function lowerExtFromName(fileName: string): string {
  const n = fileName.trim();
  const dot = n.lastIndexOf('.');
  if (dot < 0 || dot >= n.length - 1) {
    return '';
  }
  return n.substring(dot + 1).toLowerCase();
}

function nameStem(fileName: string): string {
  const n = fileName.trim();
  const dot = n.lastIndexOf('.');
  return dot > 0 ? n.substring(0, dot) : n;
}

function utf8EncodeLocal(str: string): Uint8Array {
  const utf8: number[] = [];
  for (let i = 0; i < str.length; i++) {
    let c = str.charCodeAt(i);
    if (c < 0x80) {
      utf8.push(c);
    } else if (c < 0x800) {
      utf8.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c < 0xd800 || c >= 0xe000) {
      utf8.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    } else {
      i++;
      c = 0x10000 + (((c & 0x3ff) << 10) | (str.charCodeAt(i) & 0x3ff));
      utf8.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(utf8);
}

function escapeMultipartFileName(fileName: string): string {
  return fileName.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function uint8ArrayToBase64Local(data: Uint8Array): string {
  const helper = new util.Base64Helper();
  return helper.encodeToStringSync(data);
}

function base64ToUint8Local(b64: string): Uint8Array {
  const helper = new util.Base64Helper();
  return helper.decodeSync(b64);
}

/** 与 AuthxSigner：鸿蒙 HCF 对 SHA256.update 偶发抛「update failed」，统一走安全摘要 */
async function sha256DigestLocal(data: Uint8Array): Promise<Uint8Array> {
  return sha256DigestSafe(data);
}

function concatUint8Local(a: Uint8Array, b: Uint8Array): Uint8Array {
  const r = new Uint8Array(a.length + b.length);
  r.set(a, 0);
  r.set(b, a.length);
  return r;
}

async function hmacSha256DigestLocal(key: Uint8Array, message: Uint8Array): Promise<Uint8Array> {
  const block = 64;
  let k = key;
  if (k.length > block) {
    k = await sha256DigestLocal(k);
  }
  const kb = new Uint8Array(block);
  kb.set(k, 0);
  const ipad = new Uint8Array(block);
  const opad = new Uint8Array(block);
  for (let i = 0; i < block; i++) {
    const x = kb[i] as number;
    ipad[i] = x ^ 0x36;
    opad[i] = x ^ 0x5c;
  }
  const inner = await sha256DigestLocal(concatUint8Local(ipad, message));
  return sha256DigestLocal(concatUint8Local(opad, inner));
}

/**
 * 飞牛 /upload：Trim-Sign = base64( HMAC-SHA256( secret, Trim-Path ) )
 * 仅对请求头 `Trim-Path` 的完整值（UTF-8）做 HMAC；其它头字段不参与。
 *
 * @param trimPathHeaderValue 必须与最终设置的 `Trim-Path` 头完全一致（一般为 encodeTrimPath 输出）
 */
async function buildTrimSignCandidates(
  trimPathHeaderValue: string,
  token: string,
  wsSignKeyB64: string
): Promise<string[]> {
  const out: string[] = [];
  const pushDistinct = (s: string): void => {
    if (s.length > 0 && out.indexOf(s) < 0) {
      out.push(s);
    }
  };
  const msgBytes = utf8EncodeLocal(trimPathHeaderValue);
  if (wsSignKeyB64.length > 0) {
    try {
      const secKey = base64ToUint8Local(wsSignKeyB64);
      const mac = await hmacSha256DigestLocal(secKey, msgBytes);
      pushDistinct(uint8ArrayToBase64Local(mac));
    } catch (_e) {}
  }
  if (token.length > 0) {
    try {
      const key = utf8EncodeLocal(token);
      const mac = await hmacSha256DigestLocal(key, msgBytes);
      pushDistinct(uint8ArrayToBase64Local(mac));
    } catch (_e) {}
  }
  return out;
}

/** 根据扩展名返回 MIME 类型，对齐浏览器 FormData 默认行为 */
function mimeFromExt(ext: string): string {
  const e = ext.toLowerCase();
  if (e === 'png') return 'image/png';
  if (e === 'jpg' || e === 'jpeg') return 'image/jpeg';
  if (e === 'gif') return 'image/gif';
  if (e === 'webp') return 'image/webp';
  if (e === 'bmp') return 'image/bmp';
  if (e === 'heic' || e === 'heif') return 'image/heif';
  if (e === 'mp4') return 'video/mp4';
  if (e === 'mov') return 'video/quicktime';
  return 'application/octet-stream';
}

/**
 * 组装 multipart/form-data，字段名 trim-upload-file（与浏览器 Network 抓包一致；旧版曾用 name="file"）。
 */
function buildMultipartUploadBody(fileName: string, payload: ArrayBuffer): MultipartBodyData {
  const boundary = `----WebKitFormBoundary${Date.now()}${Math.floor(Math.random() * 1000000)}`;
  const safeName = escapeMultipartFileName(fileName);
  const ext = lowerExtFromName(fileName);
  const mime = mimeFromExt(ext);
  const head =
    `--${boundary}\r\n` +
    `Content-Disposition: form-data; name="trim-upload-file"; filename="${safeName}"\r\n` +
    `Content-Type: ${mime}\r\n\r\n`;
  const tail = `\r\n--${boundary}--\r\n`;
  const a = utf8EncodeLocal(head);
  const b = new Uint8Array(payload);
  const d = utf8EncodeLocal(tail);
  const out = new Uint8Array(a.length + b.length + d.length);
  out.set(a, 0);
  out.set(b, a.length);
  out.set(d, a.length + b.length);
  const ret = new MultipartBodyData();
  ret.contentType = `multipart/form-data; boundary=${boundary}`;
  const bodyBuf = new ArrayBuffer(out.byteLength);
  const bodyView = new Uint8Array(bodyBuf);
  bodyView.set(out);
  ret.body = bodyBuf;
  return ret;
}

/**
 * 上传排障：HiLog 中对照浏览器 Network 里的 Request Headers（Cookie 值脱敏，避免泄露会话）。
 * 日志统一用与本文件相同的 TAG（FnHttp）+ 前缀 [upload]，避免单独标签在部分机型/日志级别下不可见。
 */
function redactCookieHeaderForLog(cookie: string): string {
  if (cookie.length === 0) {
    return '(empty)';
  }
  const parts = cookie.split(';');
  const out: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const seg = parts[i].trim();
    if (seg.length === 0) {
      continue;
    }
    const eq = seg.indexOf('=');
    const nameRaw = eq > 0 ? seg.substring(0, eq).trim() : seg;
    const nameLow = nameRaw.toLowerCase();
    if (nameLow === 'fnos-token' || nameLow === 'fnos-long-token' || nameLow === 'trim-mc-token') {
      out.push(`${nameRaw}=<redacted>`);
    } else {
      out.push(seg);
    }
  }
  return out.join('; ');
}

/** 列出 Cookie 键名，便于与浏览器 Request Headers 逐项核对 */
function cookieKeysSummary(cookie: string): string {
  if (cookie.length === 0) {
    return '(none)';
  }
  const keys: string[] = [];
  const parts = cookie.split(';');
  for (let i = 0; i < parts.length; i++) {
    const seg = parts[i].trim();
    const eq = seg.indexOf('=');
    const name = eq > 0 ? seg.substring(0, eq).trim() : seg;
    if (name.length > 0 && keys.indexOf(name) < 0) {
      keys.push(name);
    }
  }
  keys.sort();
  return keys.join(',');
}

function isRedirectCode(code: number): boolean {
  return code === 301 || code === 302 || code === 307 || code === 308;
}

/** 解析出协议+主机（不含路径），不含末尾 / */
function splitOrigin(full: string): string {
  let u = full.trim();
  if (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  const pe = u.indexOf('://');
  if (pe < 0) {
    return u;
  }
  const after = u.substring(pe + 3);
  const sp = after.indexOf('/');
  if (sp < 0) {
    return u;
  }
  return u.substring(0, pe + 3 + sp);
}

/** 绝对重定向地址拆成 origin + path+query（不依赖全局 URL，兼容 ArkTS） */
function resolveLocation(baseUrl: string, pathOrUrl: string): ResolvedLocation {
  const loc = pathOrUrl.trim();
  if (loc.startsWith('http://') || loc.startsWith('https://')) {
    const pe = loc.indexOf('://');
    const after = loc.substring(pe + 3);
    const sp = after.indexOf('/');
    if (sp < 0) {
      const nb = loc.endsWith('/') ? loc.substring(0, loc.length - 1) : loc;
      const r: ResolvedLocation = { newBase: nb, newPath: '/' };
      return r;
    }
    const newBase = loc.substring(0, pe + 3 + sp);
    const newPath = loc.substring(pe + 3 + sp);
    const r2: ResolvedLocation = { newBase: newBase, newPath: newPath };
    return r2;
  }
  const origin = splitOrigin(baseUrl);
  if (loc.startsWith('/')) {
    const r3: ResolvedLocation = { newBase: origin, newPath: loc };
    return r3;
  }
  const r4: ResolvedLocation = { newBase: origin, newPath: `/${loc}` };
  return r4;
}

export class FnHttpClient {
  private baseUrl: string = '';
  private token: string = '';
  /** 与 Web Cookie「fnos-long-token」一致，/p/api 等相册接口常依赖 */
  private longToken: string = '';
  /** WebSocket secret 解密后的 key（Base64），用于 upload trim-sign 兼容签名 */
  private wsSignKeyB64: string = '';
  /** 当前仍在进行的 HTTP 请求（用于页面关闭时主动释放连接） */
  private pendingRequests: http.HttpRequest[] = [];
  /** 资源下载去重：同 URL 并发仅发起一次请求 */
  private static readonly inflightAssetReq: Map<string, Promise<ArrayBuffer | undefined>> = new Map();
  /** 资源短时缓存：减少连续滚动/返回时重复下载 */
  private static readonly assetBufferCache: Map<string, AssetBufferCacheEntry> = new Map();
  private static readonly ASSET_CACHE_TTL_MS: number = 15000;
  private static readonly ASSET_CACHE_MAX: number = 120;

  constructor(baseUrl: string, token: string = '', longToken: string = '', wsSignKeyB64: string = '') {
    this.baseUrl = baseUrl;
    this.token = token;
    this.longToken = longToken;
    this.wsSignKeyB64 = wsSignKeyB64;
  }

  private cookieHeader(): string {
    return buildFnApiCookieHeader(this.token, this.longToken);
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  setBaseUrl(url: string): void {
    this.baseUrl = url;
  }

  setToken(t: string): void {
    this.token = t;
  }

  getToken(): string {
    return this.token;
  }

  getLongToken(): string {
    return this.longToken;
  }

  /** 页面关闭时可主动取消未完成请求，避免连接长期占用导致其他页面卡顿 */
  cancelPendingRequests(): void {
    const reqs = this.pendingRequests.slice();
    this.pendingRequests = [];
    for (let i = 0; i < reqs.length; i++) {
      try {
        reqs[i].destroy();
      } catch (_e) {
      }
    }
  }

  private registerPendingRequest(req: http.HttpRequest): void {
    this.pendingRequests.push(req);
  }

  private unregisterPendingRequest(req: http.HttpRequest): void {
    const idx = this.pendingRequests.indexOf(req);
    if (idx >= 0) {
      this.pendingRequests.splice(idx, 1);
    }
  }

  /**
   * 与 fnos_client.fetch_gallery_*：`p_referer = f"https://{host}:{https_port}/p/"`（固定 https:5667）
   * 不可使用会话里的 http://…:5666，否则与 Python use_https=True 不一致，图库易失败。
   */
  private galleryPhotoReferer(): string {
    return `${fnWebViewBaseUrl(this.baseUrl)}/p/`;
  }

  /**
   * 原生 POST https:5667/upload 前，把会话写入 WebCookieManager 的 **5667 与登录 base**。
   * 否则 merge 时 fetchCookieSync(5667/p/) 常为「空」：Cookie 只写在 http:5666 登录 origin 上，与图库 HTTPS 不同源。
   */
  private primeWebCookiesForPStack(webHttpsBaseNoSlash: string): void {
    const lt = this.longToken.length > 0 ? this.longToken : undefined;
    try {
      injectFnWebCookies(webHttpsBaseNoSlash, this.token, true, lt);
    } catch (_e) {
    }
    const raw = this.baseUrl.trim();
    try {
      if (raw.length > 0 && raw !== webHttpsBaseNoSlash) {
        injectFnWebCookies(raw, this.token, raw.startsWith('https://'), lt);
      }
    } catch (_e2) {
    }
  }

  /** 服务端错误文案：根级 + 部分版本嵌套在 data 内 */
  private static envelopeErrorLine(body: Record<string, string | number | Object | undefined>): string {
    const tryKeys: string[] = ['msg', 'message', 'errmsg', 'error', 'detail', 'errorMessage', 'reason'];
    for (let i = 0; i < tryKeys.length; i++) {
      const v = body[tryKeys[i]];
      if (typeof v === 'string' && v.length > 0) {
        return v;
      }
    }
    const d = body['data'];
    if (d !== undefined && d !== null && typeof d === 'object' && !Array.isArray(d)) {
      const o = d as Record<string, string | Object | undefined>;
      for (let j = 0; j < tryKeys.length; j++) {
        const k = tryKeys[j];
        const v2 = o[k];
        if (typeof v2 === 'string' && v2.length > 0) {
          return v2;
        }
      }
    }
    return '';
  }

  /** 图库失败：用 warn 与 GalleryTab 同级，便于只开 WARN 也能看到正文片段 */
  private static galleryFailBodyHint(rawBody: string, reason: string): void {
    const hint = FnHttpClient.galleryErrorBodyPreview(rawBody);
    hilog.warn(DOMAIN, TAG, 'gallery fail %{public}s body: %{public}s', reason, hint);
  }

  /** 供界面与日志共用，与 galleryFailBodyHint 同长度上限 */
  private static galleryErrorBodyPreview(rawBody: string | undefined): string {
    if (rawBody === undefined) {
      return '';
    }
    const max = 640;
    if (rawBody.length <= max) {
      return rawBody;
    }
    return `${rawBody.substring(0, max)}…`;
  }

  /** 与 Py `fnos_gallery_mobile._response_looks_like_spa_shell`：404 / HTML 壳则换 URL 候选 */
  private static galleryResponseShouldTryAlternatePath(raw: RawHttpResult): boolean {
    if (raw.code === 404) {
      return true;
    }
    const ct = (getHeader(raw.headers, 'content-type') || '').toLowerCase();
    if (ct.indexOf('html') >= 0) {
      return true;
    }
    const t = raw.body.trimStart().substring(0, 64).toLowerCase();
    return t.startsWith('<!doctype') || t.startsWith('<html');
  }

  /**
   * 图库 XHR：与 Py / 浏览器 `/p/search` 一致项 — Cookie、authx、双写 Token 头、Origin、Referer…/p/、Accept json、Sec-Fetch-*。
   * UA/Client Hint 与 **本应用 WebView**（`fnWebDefaultUserAgent`）一致：鸿蒙上若冒充 Windows 桌面，部分 NAS 会返回模糊业务错误（如 update failed）。
   */
  private buildGalleryFetchHeaders(authxVal: string, cookieHeader: string): Record<string, string> {
    const webBase = fnWebViewBaseUrl(this.baseUrl);
    const originOnly = splitOrigin(webBase);
    const h: Record<string, string> = {
      'Cookie': cookieHeader,
      'User-Agent': fnWebDefaultUserAgent(),
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
      'Accept-Encoding': 'identity',
      /** 与 Edge 访问 `https://host/p/search` 时 POST `/p/api/v2/search/results` 一致，部分网关依赖 Origin 做会话校验 */
      'Origin': originOnly,
      'Referer': this.galleryPhotoReferer(),
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Ch-Ua': '"Chromium";v="120", "Google Chrome";v="120", "Not_A Brand";v="24"',
      'Sec-Ch-Ua-Mobile': '?1',
      'Sec-Ch-Ua-Platform': '"Android"',
      'authx': authxVal
    };
    /**
     * 浏览器常见同时带 `AccessToken`（CORS 暴露名）与全小写 `accesstoken`；服务端若只读其一，缺了会 200 但业务 data 空或非 0 code。
     * 勿在此加 `Authorization`，易与 OpenAPI 会话冲突被 NAS 拒。
     */
    if (this.token.length > 0) {
      h['AccessToken'] = this.token;
      h['accesstoken'] = this.token;
    }
    return h;
  }

  /** 图库 GET：合并 Web 内核 Cookie 后请求（对齐 fnos_gallery_mobile.fetch_gallery_*）。 */
  private async requestGalleryGetJson<T>(
    pathCandidates: string[],
    gallerySign: FnGalleryGetSignSpec,
    timeoutMs: number,
    tryTimes: number
  ): Promise<FnClientResult<T>> {
    const activeBase = fnWebViewBaseUrl(this.baseUrl);
    const cookie = mergeGalleryWebCookieIntoNativeHeader(
      buildFnApiCookieHeader(this.token, this.longToken),
      activeBase
    );
    return this.requestGalleryGetJsonWithCookie<T>(pathCandidates, gallerySign, timeoutMs, tryTimes, cookie);
  }

  /**
   * 图库 GET：多 URL 候选 + SPA 壳回退 + invalid sign 重试（对齐 fnos_gallery_mobile.fetch_gallery_*）。
   */
  private async requestGalleryGetJsonWithCookie<T>(
    pathCandidates: string[],
    gallerySign: FnGalleryGetSignSpec,
    timeoutMs: number,
    tryTimes: number,
    cookieHeader: string
  ): Promise<FnClientResult<T>> {
    const activeBase = fnWebViewBaseUrl(this.baseUrl);
    const lastPi = pathCandidates.length - 1;

    pathLoop: for (let pi = 0; pi < pathCandidates.length; pi++) {
      const activePath = pathCandidates[pi];
      for (let attempt = 0; attempt <= tryTimes; attempt++) {
        try {
          const authx = await genFnGalleryAuthxGet(gallerySign.signPathOnly, gallerySign.queryParams);
          const headers = this.buildGalleryFetchHeaders(authx, cookieHeader);
          const fullUrl = `${activeBase}${activePath}`;
          let raw = await this.rawRequest(
            fullUrl,
            http.RequestMethod.GET,
            headers,
            undefined,
            timeoutMs,
            CertPolicy.isTrusted(activeBase)
          );

          if (isRedirectCode(raw.code)) {
            FnHttpClient.galleryFailBodyHint(raw.body, `redirect ${raw.code}`);
            return {
              success: false,
              message: '重定向次数过多或未返回 Location',
              errorBodyPreview: FnHttpClient.galleryErrorBodyPreview(raw.body)
            };
          }

          if (raw.code < 200 || raw.code >= 300) {
            if (pi < lastPi && FnHttpClient.galleryResponseShouldTryAlternatePath(raw)) {
              continue pathLoop;
            }
            FnHttpClient.galleryFailBodyHint(raw.body, `HTTP ${raw.code}`);
            return {
              success: false,
              message: `HTTP ${raw.code}`,
              errorBodyPreview: FnHttpClient.galleryErrorBodyPreview(raw.body)
            };
          }

          if (pi < lastPi && FnHttpClient.galleryResponseShouldTryAlternatePath(raw)) {
            continue pathLoop;
          }

          let parsed: Record<string, string | number | Object | undefined>;
          try {
            parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
          } catch (_e) {
            if (pi < lastPi && FnHttpClient.galleryResponseShouldTryAlternatePath(raw)) {
              continue pathLoop;
            }
            FnHttpClient.galleryFailBodyHint(raw.body, 'non-json');
            return {
              success: false,
              message: '响应非 JSON',
              errorBodyPreview: FnHttpClient.galleryErrorBodyPreview(raw.body)
            };
          }

          const codeNum = FnHttpClient.envelopeCodeNum(parsed);
          const errLine = FnHttpClient.envelopeErrorLine(parsed);

          if (codeNum === 5000 && errLine === 'invalid sign') {
            if (attempt >= tryTimes) {
              return {
                success: false,
                message: '签名错误，重试次数已用尽',
                errorBodyPreview: FnHttpClient.galleryErrorBodyPreview(raw.body)
              };
            }
            hilog.warn(DOMAIN, TAG, 'gallery invalid sign, retry %{public}d', attempt + 1);
            await FnHttpClient.sleep(100);
            continue;
          }

          /** 与 docs/fnos-gallery-data-flow §3.1：code 为 0、缺省、字符串 "0" 均成功（对齐 Py payload.get("code")） */
          if (!FnHttpClient.galleryEnvelopeBizOk(parsed)) {
            const showCode = FnHttpClient.envelopeCodeNum(parsed);
            FnHttpClient.galleryFailBodyHint(raw.body, `biz ${showCode}`);
            const em = errLine.length > 0 ? errLine : `业务错误 ${showCode}`;
            let preview = FnHttpClient.galleryErrorBodyPreview(raw.body);
            if (preview.length === 0) {
              preview = FnHttpClient.galleryErrorBodyPreview(JSON.stringify(parsed));
            }
            return {
              success: false,
              message: em,
              errorBodyPreview: preview
            };
          }

          const dataOut = parsed['data'] as T;
          const fnosLongToken = parseFnosLongTokenFromHeaders(raw.headers);
          return {
            success: true,
            data: dataOut,
            fnosLongToken: fnosLongToken
          };
        } catch (e) {
          const err = e as NetErrorLike;
          const code = err.code !== undefined ? err.code : 0;
          const msg = err.message !== undefined && err.message.length > 0 ? err.message : '网络错误';
          const exPrev = FnHttpClient.galleryErrorBodyPreview(String(e));
          if (CERT_CODES.indexOf(code) >= 0 && !CertPolicy.isTrusted(activeBase)) {
            return {
              success: false,
              message: msg,
              certificateError: true,
              errorBodyPreview: exPrev.length > 0 ? exPrev : FnHttpClient.galleryErrorBodyPreview(msg)
            };
          }
          if (attempt >= tryTimes) {
            return {
              success: false,
              message: msg,
              errorBodyPreview: exPrev.length > 0 ? exPrev : FnHttpClient.galleryErrorBodyPreview(msg)
            };
          }
          await FnHttpClient.sleep(100);
        }
      }
    }
    return {
      success: false,
      message: '请求异常',
      errorBodyPreview: FnHttpClient.galleryErrorBodyPreview('gallery: 已尝试全部 URL 候选与重试，仍未取得有效 JSON 响应')
    };
  }

  private static envelopeCodeNum(body: Record<string, string | number | Object | undefined>): number {
    const c = body['code'];
    if (typeof c === 'number' && !isNaN(c)) {
      return c;
    }
    if (typeof c === 'string') {
      const n = parseInt(c, 10);
      return isNaN(n) ? -1 : n;
    }
    return -1;
  }

  /**
   * 图库 JSON 外壳：与 fnos-gallery-data-flow §3.1 / Python `code not in (0, None, "0")` 的反面。
   * 无 `code` 时若已有错误文案且无 `data`，不按成功（避免仅 `{ "message":"update failed" }` 被误判成功）。
   */
  private static galleryEnvelopeBizOk(body: Record<string, string | number | Object | undefined>): boolean {
    const c = body['code'];
    if (c === undefined || c === null) {
      const err = FnHttpClient.envelopeErrorLine(body);
      const data = body['data'];
      const result = body['result'];
      // v2 部分接口用 result 承载业务体；仅 message 且既无 data 也无 result 时再判失败
      if (err.length > 0 && (data === undefined || data === null) &&
        (result === undefined || result === null)) {
        return false;
      }
      return true;
    }
    if (typeof c === 'number' && !isNaN(c)) {
      return c === 0;
    }
    if (typeof c === 'string') {
      const n = parseInt(c, 10);
      return !isNaN(n) && n === 0;
    }
    return false;
  }

  /**
   * 图库/照片接口响应体：多数为 `data`，新版 v2 常见为 `result`；统一取有效对象再解析 list。
   */
  private static galleryEnvelopeData(body: Record<string, string | number | Object | undefined>): Object | undefined {
    const d = body['data'];
    if (d !== undefined && d !== null) {
      return d as Object;
    }
    const r = body['result'];
    if (r !== undefined && r !== null) {
      return r as Object;
    }
    return undefined;
  }

  /** 与内置 Web 一致，便于首页下发 Set-Cookie */
  private static readonly PROBE_BROWSER_UA: string =
    'Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /**
   * 跟随重定向探测 fnos-long-token；headers 由 makeHeaders(activePath) 生成。
   * @param initialBase 须与图库/Web 一致：登录为 http:5666 时仍应用 `fnWebViewBaseUrl`，否则 long-token 与 `/p/api`（https:5667）不同源，易报业务 update failed。
   */
  private async probeLongTokenWithHeaders(
    initialBase: string,
    makeHeaders: (activePath: string) => Promise<Record<string, string>>,
    timeoutMs: number
  ): Promise<string> {
    const tryPaths: string[] = fnPhotoLongTokenProbePaths();
    for (let pi = 0; pi < tryPaths.length; pi++) {
      let activeBase = initialBase;
      let activePath = tryPaths[pi];
      if (!activePath.startsWith('/')) {
        activePath = `/${activePath}`;
      }
      let redirectLeft = MAX_REDIRECTS;
      while (true) {
        try {
          const headers = await makeHeaders(activePath);
          const fullUrl = `${activeBase}${activePath}`;
          let raw: RawHttpResult;
          try {
            raw = await this.rawRequest(
              fullUrl,
              http.RequestMethod.GET,
              headers,
              undefined,
              timeoutMs,
              CertPolicy.isTrusted(activeBase)
            );
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'longToken probe rawRequest: %{public}s', String(e));
            break;
          }
          const tok = parseFnosLongTokenFromHeaders(raw.headers);
          if (tok !== undefined && tok.length > 0) {
            return tok;
          }
          if (isRedirectCode(raw.code) && redirectLeft > 0) {
            const loc = getHeader(raw.headers, 'location');
            if (loc === undefined || loc.length === 0) {
              break;
            }
            const resolved = resolveLocation(activeBase, loc);
            activeBase = resolved.newBase;
            activePath = resolved.newPath.startsWith('/') ? resolved.newPath : `/${resolved.newPath}`;
            redirectLeft--;
            continue;
          }
          break;
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'longToken probe iter: %{public}s', String(e));
          break;
        }
      }
    }
    return '';
  }

  /**
   * 浏览器首次进站会 Set-Cookie 下发 fnos-long-token；纯 OpenAPI 登录往往没有。
   * WebSocket 登录的 token 与 OpenAPI Authx 体系无关，原先用 Authx 探测首页易被拒，故先模拟浏览器 GET，再回退带 Authx。
   */
  /**
   * 仅作增强：失败或未下发 cookie 时返回空串，不向调用方抛异常（避免登录流程被误判为「网络异常」）。
   */
  async fetchFnosLongTokenProbe(timeoutMs: number = 12000): Promise<string> {
    if (this.token.length === 0) {
      return '';
    }
    const ua = FnHttpClient.PROBE_BROWSER_UA;
    const probeBase = fnWebViewBaseUrl(this.baseUrl);

    let got = await this.probeLongTokenWithHeaders(probeBase, async (_path: string) => {
      return {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'User-Agent': ua,
        'Cookie': buildFnApiCookieHeader(this.token, '')
      };
    }, timeoutMs);
    if (got.length > 0) {
      return got;
    }

    got = await this.probeLongTokenWithHeaders(probeBase, async (_path: string) => {
      return {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'User-Agent': ua,
        'Cookie': buildFnApiCookieHeader(this.token, ''),
        'Authorization': this.token
      };
    }, timeoutMs);
    if (got.length > 0) {
      return got;
    }

    return this.probeLongTokenWithHeaders(probeBase, async (activePath: string) => {
      const authx = await genFnAuthx(activePath, null);
      return {
        'Content-Type': 'application/json',
        'Authorization': this.token,
        'Cookie': this.cookieHeader(),
        'Authx': authx
      };
    }, timeoutMs);
  }

  /**
   * 底层单次请求（不跟业务 code）；若 3xx 且带 Location 则返回给上层做递归
   */
  private async rawRequest(
    fullUrl: string,
    method: http.RequestMethod,
    header: Record<string, string>,
    bodyStr: string | undefined,
    timeoutMs: number,
    skipRemoteCert: boolean
  ): Promise<RawHttpResult> {
    const httpRequest = http.createHttp();
    this.registerPendingRequest(httpRequest);
    try {
      const opt: http.HttpRequestOptions = {
        method: method,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      };
      if (bodyStr !== undefined && bodyStr.length > 0) {
        opt.extraData = bodyStr;
      }
      if (skipRemoteCert) {
        opt.remoteValidation = 'skip';
      }
      const resp = await httpRequest.request(fullUrl, opt);
      const text = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
      const out: RawHttpResult = {
        code: resp.responseCode as number,
        headers: resp.header,
        body: text
      };
      return out;
    } finally {
      this.unregisterPendingRequest(httpRequest);
      try {
        httpRequest.destroy();
      } catch (_e) {
      }
    }
  }

  /**
   * @param photoCookieOnly 为 true 时不带 Authorization，与浏览器访问 /p/api 一致（仅 Cookie 会话）；
   * 避免与 OpenAPI 头混用导致服务端判定「会话冲突 / token 不能复用」。
   */
  async requestJson<T>(
    path: string,
    method: http.RequestMethod,
    data?: Record<string, FnJsonValue>,
    timeoutMs: number = DEFAULT_TIMEOUT,
    tryTimes: number = 5,
    photoCookieOnly: boolean = false
  ): Promise<FnClientResult<T>> {
    for (let attempt = 0; attempt <= tryTimes; attempt++) {
      try {
        const postBody: Record<string, FnJsonValue> | undefined =
          (method === http.RequestMethod.POST || method === http.RequestMethod.PUT)
            ? mergePostBody(data)
            : undefined;
        let activeBase = this.baseUrl;
        let activePath = path;
        let redirectLeft = MAX_REDIRECTS;
        let lastMoveUrl: string | undefined = undefined;

        const makeHeaders = (authxVal: string): Record<string, string> => {
          const h: Record<string, string> = {
            'Cookie': this.cookieHeader(),
          'Content-Type': 'application/json',
            'Authx': authxVal
          };
          if (!photoCookieOnly && this.token.length > 0) {
            h['Authorization'] = this.token;
          }
          return h;
        };
        const bodyStr =
          postBody !== undefined ? JSON.stringify(postBody) : undefined;

        let authx = await genFnAuthx(activePath, postBody !== undefined ? postBody : null);
        let headers: Record<string, string> = makeHeaders(authx);
        let fullUrl = `${activeBase}${activePath}`;
        let raw = await this.rawRequest(
          fullUrl,
          method,
          headers,
          bodyStr,
          timeoutMs,
          CertPolicy.isTrusted(activeBase)
        );

        while (isRedirectCode(raw.code) && redirectLeft > 0) {
          const loc = getHeader(raw.headers, 'location');
          if (!loc) {
            break;
          }
          const resolved = resolveLocation(activeBase, loc);
          activeBase = resolved.newBase;
          activePath = resolved.newPath.startsWith('/') ? resolved.newPath : `/${resolved.newPath}`;
          lastMoveUrl = activeBase;
          redirectLeft--;
          authx = await genFnAuthx(activePath, postBody !== undefined ? postBody : null);
          headers = makeHeaders(authx);
          fullUrl = `${activeBase}${activePath}`;
          raw = await this.rawRequest(
            fullUrl,
            method,
            headers,
            bodyStr,
            timeoutMs,
            CertPolicy.isTrusted(activeBase)
          );
        }

        if (isRedirectCode(raw.code)) {
          return { success: false, message: '重定向次数过多或未返回 Location' };
        }

        if (raw.code < 200 || raw.code >= 300) {
          return { success: false, message: `HTTP ${raw.code}` };
        }

        let parsed: Record<string, string | number | Object | undefined>;
        try {
          parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
        } catch (_e) {
          return { success: false, message: '响应非 JSON' };
        }

        const codeNum = FnHttpClient.envelopeCodeNum(parsed);
        const errLine = FnHttpClient.envelopeErrorLine(parsed);

        if (codeNum === 5000 && errLine === 'invalid sign') {
          if (attempt >= tryTimes) {
            return { success: false, message: '签名错误，重试次数已用尽' };
          }
          hilog.warn(DOMAIN, TAG, 'invalid sign, retry %{public}d', attempt + 1);
          await FnHttpClient.sleep(100);
          continue;
        }

        if (codeNum !== 0) {
          const em = errLine.length > 0 ? errLine : `业务错误 ${codeNum}`;
          return { success: false, message: em };
        }

        const dataOut = parsed['data'] as T;
        const move = lastMoveUrl !== undefined ? lastMoveUrl : undefined;
        const fnosLongToken = parseFnosLongTokenFromHeaders(raw.headers);
        return {
          success: true,
          data: dataOut,
          moveUrl: move,
          fnosLongToken: fnosLongToken
        };
      } catch (e) {
        const err = e as NetErrorLike;
        const code = err.code !== undefined ? err.code : 0;
        const msg = err.message !== undefined && err.message.length > 0 ? err.message : '网络错误';
        if (CERT_CODES.indexOf(code) >= 0 && !CertPolicy.isTrusted(this.baseUrl)) {
          return { success: false, message: msg, certificateError: true };
        }
        if (attempt >= tryTimes) {
          return { success: false, message: msg };
        }
        await FnHttpClient.sleep(100);
      }
    }
    return { success: false, message: '请求异常' };
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: (v: void) => void) => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
  }

  /**
   * 登录：须 POST 开放 API（根路径 `/` 多为 GET 首页，POST 会 405）。路径属 /v/api/v1，非影视 H5。
   */
  async login(username: string, password: string): Promise<FnClientResult<LoginResultData>> {
    const body: Record<string, FnJsonValue> = {
      'app_name': 'trimemedia-web',
      'username': username,
      'password': password
    };
    return this.requestJson<LoginResultData>(`${FN_OPENAPI_PREFIX}/login`, http.RequestMethod.POST, body);
  }

  async getUserInfo(timeoutMs: number = 5000, tryTimes: number = 2): Promise<FnClientResult<UserInfoData>> {
    return this.requestJson<UserInfoData>(`${FN_OPENAPI_PREFIX}/user/info`, http.RequestMethod.GET, undefined,
      timeoutMs, tryTimes);
  }

  async logout(): Promise<FnClientResult<LogoutResultData>> {
    return this.requestJson<LogoutResultData>(`${FN_OPENAPI_PREFIX}/logout`, http.RequestMethod.POST, undefined);
  }

  /** 影视媒体库 item/list（主界面未使用；保留供扩展）。 */
  async getItemList(req: ItemListRequest): Promise<FnClientResult<ItemListResponse>> {
    const body: Record<string, FnJsonValue> = {
      'parent_guid': req.parent_guid,
      'exclude_folder': req.exclude_folder,
      'sort_column': req.sort_column,
      'sort_type': req.sort_type
    };
    return this.requestJson<ItemListResponse>(`${FN_OPENAPI_PREFIX}/item/list`, http.RequestMethod.POST, body);
  }

  /**
   * 图库资源鉴权下载（缩略图/原图/视频封面）：与 getList 相同 Cookie/authx/AccessToken/Referer。
   * 失败返回 undefined，不抛出。
   */
  async fetchGalleryImageBuffer(fullUrl: string, timeoutMs: number = 8000): Promise<ArrayBuffer | undefined> {
    const now = Date.now();
    const cached = FnHttpClient.assetBufferCache.get(fullUrl);
    if (cached !== undefined && now - cached.timeMs <= FnHttpClient.ASSET_CACHE_TTL_MS) {
      return cached.data;
    }
    const inflight = FnHttpClient.inflightAssetReq.get(fullUrl);
    if (inflight !== undefined) {
      return await inflight;
    }
    const job = this.fetchGalleryImageBufferInternal(fullUrl, timeoutMs);
    FnHttpClient.inflightAssetReq.set(fullUrl, job);
    try {
      const out = await job;
      if (out !== undefined && out.byteLength > 0) {
        FnHttpClient.putAssetBufferCache(fullUrl, out);
      }
      return out;
    } finally {
      FnHttpClient.inflightAssetReq.delete(fullUrl);
    }
  }

  private async fetchGalleryImageBufferInternal(
    fullUrl: string,
    timeoutMs: number = 8000
  ): Promise<ArrayBuffer | undefined> {
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const parsed = FnHttpClient.parseGalleryAssetUrl(fullUrl);
      const authx = await genFnGalleryAuthxGet(parsed.signPath, parsed.queryParams);
      const headers = this.buildGalleryFetchHeaders(authx, cookie);
      const req = http.createHttp();
      this.registerPendingRequest(req);
      try {
        const opt: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          header: headers,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: timeoutMs,
          readTimeout: timeoutMs
        };
        if (CertPolicy.isTrusted(activeBase)) {
          opt.remoteValidation = 'skip';
        }
        const resp = await req.request(fullUrl, opt);
        if (resp.responseCode >= 200 && resp.responseCode < 300) {
          return resp.result as ArrayBuffer;
        }
      } finally {
        this.unregisterPendingRequest(req);
        try {
          req.destroy();
        } catch (_e) {
        }
      }
    } catch (_e) {
    }
    return undefined;
  }

  private static putAssetBufferCache(url: string, data: ArrayBuffer): void {
    if (FnHttpClient.assetBufferCache.size >= FnHttpClient.ASSET_CACHE_MAX) {
      let oldestKey: string | undefined = undefined;
      let oldestTime = Number.MAX_SAFE_INTEGER;
      const keys = Array.from(FnHttpClient.assetBufferCache.keys());
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const one = FnHttpClient.assetBufferCache.get(key);
        if (one !== undefined && one.timeMs < oldestTime) {
          oldestTime = one.timeMs;
          oldestKey = key;
        }
      }
      if (oldestKey !== undefined) {
        FnHttpClient.assetBufferCache.delete(oldestKey);
      }
    }
    const entry: AssetBufferCacheEntry = { timeMs: Date.now(), data: data };
    FnHttpClient.assetBufferCache.set(url, entry);
  }

  /**
   * 图库流媒体（如 `/p/api/v1/stream/v/{id}`）的 HTTP 请求头，与 `fetchGalleryImageBuffer` 鉴权一致。
   * 原生 `Video` 组件直连 URL 不会携带 Cookie/authx，需用 `AVPlayer` + `createMediaSourceWithUrl` 拉流。
   * 媒体请求将 Accept 改为通配（见方法内对 h['Accept'] 的赋值），避免沿用 JSON 的 Accept 导致部分网关异常。
   */
  async getGalleryStreamHeaders(fullUrl: string): Promise<Record<string, string>> {
    const activeBase = fnWebViewBaseUrl(this.baseUrl);
    const cookie = mergeGalleryWebCookieIntoNativeHeader(
      buildFnApiCookieHeader(this.token, this.longToken),
      activeBase
    );
    const parsed = FnHttpClient.parseGalleryAssetUrl(fullUrl);
    const authx = await genFnGalleryAuthxGet(parsed.signPath, parsed.queryParams);
    const h = this.buildGalleryFetchHeaders(authx, cookie);
    h['Accept'] = '*/*';
    return h;
  }

  /**
   * 请求视频转码播放地址（/p/api/v1/video/decode/play）。
   * - 成功时返回可直接用于 AVPlayer 的 m3u8/流地址；
   * - 失败时返回 success=false，不抛异常，调用方可回退到原始直链播放。
   */
  async requestVideoDecodePlayUrl(
    req: VideoDecodePlayRequest,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<VideoDecodePlayInfo>> {
    const id = req.id.trim();
    if (id.length === 0) {
      return { success: false, message: '视频 ID 不能为空' };
    }
    const res = req.resolution.trim();
    if (res.length === 0) {
      return { success: false, message: 'resolution 不能为空' };
    }
    const bitrate = Math.max(100000, Math.floor(req.bitrate));
    const audioIndex = Math.max(0, Math.floor(req.audioIndex));
    const channels = Math.max(1, Math.floor(req.channels));
    const encoder = req.videoEncoder.trim().length > 0 ? req.videoEncoder.trim() : 'h264';
    const activeBase = fnWebViewBaseUrl(this.baseUrl);
    const path = `${FN_PHOTO_API_PREFIX}/video/decode/play`;
    const cookie = mergeGalleryWebCookieIntoNativeHeader(
      buildFnApiCookieHeader(this.token, this.longToken),
      activeBase
    );
    const idNum = Number(id);
    const idJson = Number.isFinite(idNum) && idNum > 0 ? `${Math.floor(idNum)}` : `"${escapeJsonString(id)}"`;
    const bodyStr =
      `{"id":${idJson},"bitrate":${bitrate},"resolution":"${escapeJsonString(res)}",` +
      `"audioIndex":${audioIndex},"videoEncoder":"${escapeJsonString(encoder)}","channels":${channels}}`;
    try {
      const authx = await genFnGalleryAuthxPostRaw(path, bodyStr);
      const headers = this.buildGalleryFetchHeaders(authx, cookie);
      headers['Content-Type'] = 'application/json';
      const raw = await this.rawRequest(
        `${activeBase}${path}`,
        http.RequestMethod.POST,
        headers,
        bodyStr,
        timeoutMs,
        CertPolicy.isTrusted(activeBase)
      );
      if (raw.code < 200 || raw.code >= 300) {
        return { success: false, message: `HTTP ${raw.code}` };
      }
      let parsed: Record<string, string | number | Object | undefined>;
      try {
        parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
      } catch (_e) {
        return { success: false, message: '转码播放响应解析失败' };
      }
      if (!FnHttpClient.galleryEnvelopeBizOk(parsed)) {
        const errLine = FnHttpClient.envelopeErrorLine(parsed);
        return { success: false, message: errLine.length > 0 ? errLine : '转码播放失败' };
      }
      const resolved = FnHttpClient.extractDecodePlayUrl(parsed, activeBase);
      if (resolved.length === 0) {
        return { success: false, message: '未返回可播放地址' };
      }
      const hls = FnHttpClient.extractDecodeHlsTimeSec(parsed);
      return {
        success: true,
        data: { playUrl: resolved, hlsTimeSec: hls }
      };
    } catch (e) {
      return { success: false, message: String(e) || '转码请求异常' };
    }
  }

  /**
   * 终止服务器端当前视频的转码会话（对齐浏览器抓包：POST /p/api/v1/video/decode/quit）。
   * 切换预览项或清晰度前调用，避免旧转码任务占用资源或与新区冲突。
   * 失败不抛异常，由调用方决定是否提示。
   */
  async requestVideoDecodeQuit(photoId: string, timeoutMs: number = 8000): Promise<FnClientResult<Object>> {
    const id = photoId.trim();
    if (id.length === 0) {
      return { success: false, message: 'photoId 为空' };
    }
    const activeBase = fnWebViewBaseUrl(this.baseUrl);
    const path = `${FN_PHOTO_API_PREFIX}/video/decode/quit`;
    const cookie = mergeGalleryWebCookieIntoNativeHeader(
      buildFnApiCookieHeader(this.token, this.longToken),
      activeBase
    );
    const idNum = Number(id);
    const idJson = Number.isFinite(idNum) && idNum > 0 ? `${Math.floor(idNum)}` : `"${escapeJsonString(id)}"`;
    const bodyStr = `{"id":${idJson}}`;
    try {
      const authx = await genFnGalleryAuthxPostRaw(path, bodyStr);
      const headers = this.buildGalleryFetchHeaders(authx, cookie);
      headers['Content-Type'] = 'application/json';
      const raw = await this.rawRequest(
        `${activeBase}${path}`,
        http.RequestMethod.POST,
        headers,
        bodyStr,
        timeoutMs,
        CertPolicy.isTrusted(activeBase)
      );
      if (raw.code < 200 || raw.code >= 300) {
        return { success: false, message: `HTTP ${raw.code}` };
      }
      let parsed: Record<string, string | number | Object | undefined>;
      try {
        parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
      } catch (_e) {
        // quit 返回非 JSON 时按“已尽力发送成功”处理，避免阻断后续重建播放。
        return { success: true, data: new Object() };
      }
      if (FnHttpClient.galleryEnvelopeBizOk(parsed)) {
        return { success: true, data: parsed['data'] as Object };
      }
      return { success: false, message: FnHttpClient.envelopeErrorLine(parsed) || 'quit 业务失败' };
    } catch (e) {
      return { success: false, message: String(e) || 'quit 请求异常' };
    }
  }

  /** 兼容不同版本响应字段，提取可播放地址并补全相对路径 */
  private static extractDecodePlayUrl(
    body: Record<string, string | number | Object | undefined>,
    activeBase: string
  ): string {
    const toAbs = (u: string): string => {
      const t = u.trim();
      if (t.length === 0) {
        return '';
      }
      /**
       * decode/play 常返回短链接：/media/{mediaId}/preset.m3u8
       * 真实可播放地址需补成：
       * /p/api/v1/video/decode/stream/media/{mediaId}/preset.m3u8
       */
      if (t.startsWith('/media/')) {
        return `${activeBase}${FN_PHOTO_API_PREFIX}/video/decode/stream${t}`;
      }
      if (t.startsWith('http://') || t.startsWith('https://') || t.startsWith('data:')) {
        return t;
      }
      return t.startsWith('/') ? `${activeBase}${t}` : `${activeBase}/${t}`;
    };
    const pickUrlFromObj = (o: Record<string, string | number | Object | undefined>): string => {
      const keys: string[] = ['url', 'playUrl', 'playLink', 'm3u8', 'm3u8Url', 'streamUrl', 'playlist'];
      for (let i = 0; i < keys.length; i++) {
        const v = o[keys[i]];
        if (typeof v === 'string' && v.trim().length > 0) {
          return toAbs(v);
        }
      }
      // 兜底：部分版本可能仅返回 mediaId，按抓包规则拼接 preset.m3u8
      const mediaId = o['mediaId'] ?? o['media_id'] ?? o['taskId'] ?? o['task_id'];
      if (mediaId !== undefined && mediaId !== null) {
        const sid = String(mediaId).trim();
        if (sid.length > 0) {
          return `${activeBase}${FN_PHOTO_API_PREFIX}/video/decode/stream/media/${sid}/preset.m3u8`;
        }
      }
      return '';
    };
    const root = pickUrlFromObj(body);
    if (root.length > 0) {
      return root;
    }
    const dataObj = body['data'];
    if (dataObj !== undefined && dataObj !== null && typeof dataObj === 'object' && !Array.isArray(dataObj)) {
      const fromData = pickUrlFromObj(dataObj as Record<string, string | number | Object | undefined>);
      if (fromData.length > 0) {
        return fromData;
      }
    }

    /**
     * 深度兜底（兼容更多 NAS 返回形态）：
     * 1) 先在完整 JSON 字符串里提取 m3u8 URL/相对路径；
     * 2) 再提取 mediaId 并拼接标准 preset.m3u8。
     * 说明：部分版本 decode/play 返回结构层级较深，字段名不固定，直接按键取值会漏。
     */
    let raw = '';
    try {
      raw = JSON.stringify(body);
    } catch (_e) {
      raw = '';
    }
    if (raw.length > 0) {
      // 优先匹配完整 URL
      let m = raw.match(/https?:\/\/[^"\\\s]+\/video\/decode\/stream\/media\/[^"\\\s]+\.m3u8/i);
      if (m !== null && m.length > 0) {
        return m[0];
      }
      // 再匹配相对路径（包含被 JSON 转义的斜杠）
      m = raw.match(/(?:\/|\\\/)p(?:\/|\\\/)api(?:\/|\\\/)v1(?:\/|\\\/)video(?:\/|\\\/)decode(?:\/|\\\/)stream(?:\/|\\\/)media(?:\/|\\\/)[^"\\\s]+\.m3u8/i);
      if (m !== null && m.length > 0) {
        const rel = m[0].replace(/\\\//g, '/');
        return toAbs(rel.startsWith('/') ? rel : `/${rel}`);
      }
      // 最后尝试提取 mediaId / media_id（如 ff416b...）并拼接标准 m3u8
      m = raw.match(/"(?:mediaId|media_id|taskId|task_id)"\s*:\s*"([a-zA-Z0-9_-]{8,})"/i);
      if (m !== null && m.length > 1) {
        const sid = m[1].trim();
        if (sid.length > 0) {
          return `${activeBase}${FN_PHOTO_API_PREFIX}/video/decode/stream/media/${sid}/preset.m3u8`;
        }
      }
    }
    return '';
  }

  /** 提取 decode/play 返回的 hlsTime（秒），未知时返回 0 */
  private static extractDecodeHlsTimeSec(
    body: Record<string, string | number | Object | undefined>
  ): number {
    const pickNum = (o: Record<string, string | number | Object | undefined>): number => {
      const v = o['hlsTime'] ?? o['hls_time'];
      if (typeof v === 'number' && Number.isFinite(v) && v > 0) {
        return Math.floor(v);
      }
      if (typeof v === 'string') {
        const n = Number(v);
        if (Number.isFinite(n) && n > 0) {
          return Math.floor(n);
        }
      }
      return 0;
    };
    const root = pickNum(body);
    if (root > 0) {
      return root;
    }
    const dataObj = body['data'];
    if (dataObj !== undefined && dataObj !== null && typeof dataObj === 'object' && !Array.isArray(dataObj)) {
      return pickNum(dataObj as Record<string, string | number | Object | undefined>);
    }
    return 0;
  }

  /** 从完整 URL 中提取签名路径与 query 参数（供 genFnGalleryAuthxGet） */
  private static parseGalleryAssetUrl(fullUrl: string): GalleryAssetSignParts {
    const qIdx = fullUrl.indexOf('?');
    const beforeQ = qIdx >= 0 ? fullUrl.substring(0, qIdx) : fullUrl;
    const queryStr = qIdx >= 0 ? fullUrl.substring(qIdx + 1) : '';
    const schemeEnd = beforeQ.indexOf('://');
    const pathStart = schemeEnd >= 0 ? beforeQ.indexOf('/', schemeEnd + 3) : beforeQ.indexOf('/');
    const signPath = pathStart >= 0 ? beforeQ.substring(pathStart) : '/';
    const queryParams: Record<string, string | number | boolean> = {};
    if (queryStr.length > 0) {
      const parts = queryStr.split('&');
      for (let i = 0; i < parts.length; i++) {
        const part = parts[i];
        const eqIdx = part.indexOf('=');
        if (eqIdx > 0) {
          try {
            const k = decodeURIComponent(part.substring(0, eqIdx));
            const v = decodeURIComponent(part.substring(eqIdx + 1));
            queryParams[k] = v;
          } catch (_e) {
          }
        }
      }
    }
    const out: GalleryAssetSignParts = {
      signPath: signPath,
      queryParams: queryParams
    };
    return out;
  }

  /**
   * 相册时间轴：GET gallery/timeline（与 Py fetch_gallery_timeline：双路径候选 + Cookie/authx/AccessToken）
   */
  async getGalleryTimeline(
    extraParams?: Record<string, string | number | boolean>
  ): Promise<FnClientResult<GalleryTimelineData>> {
    const params: Record<string, string | number | boolean> =
      extraParams !== undefined ? extraParams : GALLERY_QUERY_EMPTY;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [];
    for (let i = 0; i < GALLERY_TIMELINE_PATH_CANDIDATES.length; i++) {
      const rel = GALLERY_TIMELINE_PATH_CANDIDATES[i];
      pathCandidates.push(qs.length > 0 ? `${rel}?${qs}` : rel);
    }
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: GALLERY_TIMELINE_SIGN_PATH,
      queryParams: params
    };
    return this.requestGalleryGetJson<GalleryTimelineData>(pathCandidates, gallerySign, DEFAULT_TIMEOUT, 3);
  }

  /**
   * 收藏夹时间轴：GET /p/api/v1/gallery/timeline?is_collect=1（与 Web /collect 一致）
   */
  async getCollectGalleryTimeline(): Promise<FnClientResult<GalleryTimelineData>> {
    const p: Record<string, string | number | boolean> = {};
    p['is_collect'] = 1;
    return this.getGalleryTimeline(p);
  }

  /**
   * 最近添加时间轴：GET /p/api/v1/explore/recent_timeline
   * 返回结构与 gallery/timeline 对齐（data.list: [{year,month,day,itemCount}...]）。
   */
  async getRecentTimeline(
    extraParams?: Record<string, string | number | boolean>
  ): Promise<FnClientResult<GalleryTimelineData>> {
    const params: Record<string, string | number | boolean> =
      extraParams !== undefined ? extraParams : GALLERY_QUERY_EMPTY;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [];
    for (let i = 0; i < RECENT_TIMELINE_PATH_CANDIDATES.length; i++) {
      const rel = RECENT_TIMELINE_PATH_CANDIDATES[i];
      pathCandidates.push(qs.length > 0 ? `${rel}?${qs}` : rel);
    }
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: RECENT_TIMELINE_SIGN_PATH,
      queryParams: params
    };
    return this.requestGalleryGetJson<GalleryTimelineData>(pathCandidates, gallerySign, DEFAULT_TIMEOUT, 3);
  }

  /**
   * 相册图片列表：GET gallery/getList（签名 path 恒为 /p/api/v1/gallery/getList，与 Py 一致）
   * 时间格式须为「年:月:日 时:分:秒」空格分隔（与前端 dayjs / Python _day_time_range_str 一致）。
   */
  /**
   * AI 语义搜索（magic search）：POST /p/api/v1/magic-search/do
   * 使用与图库 GET 相同的 Cookie + authx 认证体系。
   */
  async doMagicSearch(keyword: string, timeoutMs: number = 20000): Promise<FnClientResult<MagicSearchData>> {
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const path = `${FN_PHOTO_API_PREFIX}/magic-search/do`;
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const body: MagicSearchDoBody = { keyword: keyword };
      // ArkTS 禁止无对应接口的对象字面量：先建空 Record 再逐字段赋值
      const signBody: Record<string, FnJsonValue> = {};
      signBody['keyword'] = keyword;
      const authx = await genFnGalleryAuthxPost(path, signBody);
      const headers = this.buildGalleryFetchHeaders(authx, cookie);
      headers['Content-Type'] = 'application/json';
      const bodyStr = JSON.stringify(body);
      const raw = await this.rawRequest(
        `${activeBase}${path}`,
        http.RequestMethod.POST,
        headers,
        bodyStr,
        timeoutMs,
        CertPolicy.isTrusted(activeBase)
      );
      if (raw.code < 200 || raw.code >= 300) {
        return { success: false, message: `HTTP ${raw.code}` };
      }
      let parsed: Record<string, string | number | Object | undefined>;
      try {
        parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
      } catch (_e) {
        return { success: false, message: '搜索结果解析失败' };
      }
      if (!FnHttpClient.galleryEnvelopeBizOk(parsed)) {
        const code = FnHttpClient.envelopeCodeNum(parsed);
        const errLine = FnHttpClient.envelopeErrorLine(parsed);
        const show = errLine.length > 0 ? `: ${errLine}` : '';
        return { success: false, message: `搜索请求失败 (${code})${show}` };
      }
      return { success: true, data: parsed['data'] as MagicSearchData };
    } catch (e) {
      return { success: false, message: String(e) || '搜索请求异常' };
    }
  }

  /**
   * 媒体分类：GET media_category/list（与 Web 一致走 Cookie + authx）。
   * 飞牛新版与 search/results 类似，优先 `/p/api/v2/...`，失败或无列表时再回退 v1。
   */
  async getMediaCategoryList(timeoutMs: number = 20000): Promise<FnClientResult<MediaCategoryData>> {
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const pathCandidates: string[] = [
        `${FN_PHOTO_API_V2_PREFIX}/media_category/list`,
        `${FN_PHOTO_API_PREFIX}/media_category/list`,
      ];
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      let lastHttp = -1;
      let lastBizMsg = '';
      /** 最近一次「HTTP+biz 均成功」的解析结果；v2 空列表但 v1 请求失败时仍返回该兜底，避免误报失败 */
      let lastOkData: MediaCategoryData | undefined = undefined;
      for (let pi = 0; pi < pathCandidates.length; pi++) {
        const path = pathCandidates[pi];
        const authx = await genFnGalleryAuthxGet(path, GALLERY_QUERY_EMPTY);
        const headers = this.buildGalleryFetchHeaders(authx, cookie);
        const raw = await this.rawRequest(
          `${activeBase}${path}`,
          http.RequestMethod.GET,
          headers,
          undefined,
          timeoutMs,
          CertPolicy.isTrusted(activeBase)
        );
        lastHttp = raw.code;
        if (raw.code < 200 || raw.code >= 300) {
          continue;
        }
        let parsed: Record<string, string | number | Object | undefined>;
        try {
          parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
        } catch (_e) {
          lastBizMsg = '媒体分类结果解析失败';
          continue;
        }
        if (!FnHttpClient.galleryEnvelopeBizOk(parsed)) {
          const code = FnHttpClient.envelopeCodeNum(parsed);
          const errLine = FnHttpClient.envelopeErrorLine(parsed);
          lastBizMsg = errLine.length > 0 ? errLine : `媒体分类请求失败 (${code})`;
          continue;
        }
        hilog.info(DOMAIN, TAG, 'mediaCat path=%{public}s body(600): %{public}s', path, raw.body.substring(0, 600));
        const payload = FnHttpClient.galleryEnvelopeData(parsed);
        const normList = FnHttpClient.mediaCategoryItemsFromData(payload);
        hilog.info(DOMAIN, TAG, 'mediaCat normCount=%{public}d', normList.length);
        if (normList.length > 0) {
          hilog.info(DOMAIN, TAG, 'mediaCat[0] name=%{public}s key=%{public}s id=%{public}s count=%{public}d cover=%{public}s',
            normList[0].name ?? '(none)', normList[0].key ?? '(none)', normList[0].id ?? '(none)',
            normList[0].count ?? -1, normList[0].cover ?? '(none)');
        }
        lastOkData = { list: normList };
        if (normList.length > 0) {
          return { success: true, data: lastOkData };
        }
      }
      if (lastOkData !== undefined) {
        return { success: true, data: lastOkData };
      }
      const hint = lastBizMsg.length > 0 ? lastBizMsg : `HTTP ${lastHttp}`;
      return { success: false, message: `媒体分类加载失败: ${hint}` };
    } catch (e) {
      return { success: false, message: String(e) || '媒体分类请求异常' };
    }
  }

  /**
   * 智能分类：GET /p/api/v1/ai-smart-rec/categories
   * mainCategory: scene | information
   */
  async getSmartRecCategories(
    mainCategory: string,
    limit: number = -1,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<SmartCategoryData>> {
    try {
      const mc = mainCategory.trim();
      if (mc.length === 0) {
        return { success: false, message: 'mainCategory 不能为空' };
      }
      const params: Record<string, string | number | boolean> = {};
      params['limit'] = limit;
      params['mainCategory'] = mc;
      const qs = buildGallerySortedQuery(params);
      const signPath = `${FN_PHOTO_API_PREFIX}/ai-smart-rec/categories`;
      const pathCandidates: string[] = [
        `${signPath}?${qs}`,
        `/api/v1/ai-smart-rec/categories?${qs}`
      ];
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: signPath,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<SmartCategoryData>(pathCandidates, gallerySign, timeoutMs, 3);
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '智能分类加载失败' };
      }
      return { success: true, data: res.data };
    } catch (e) {
      return { success: false, message: String(e) || '智能分类加载异常' };
    }
  }

  /**
   * 人物：GET /p/api/v1/ai-person/list?getAll=true&limit=-1&orderBy=0
   */
  async getAiPersonList(
    getAll: boolean = true,
    limit: number = -1,
    orderBy: number = 0,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<AiPersonData>> {
    try {
      const params: Record<string, string | number | boolean> = {};
      params['getAll'] = getAll;
      params['limit'] = limit;
      params['orderBy'] = orderBy;
      const qs = buildGallerySortedQuery(params);
      const signPath = `${FN_PHOTO_API_PREFIX}/ai-person/list`;
      const pathCandidates: string[] = [
        `${signPath}?${qs}`,
        `/api/v1/ai-person/list?${qs}`
      ];
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: signPath,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<AiPersonData>(pathCandidates, gallerySign, timeoutMs, 3);
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '人物列表加载失败' };
      }
      return { success: true, data: res.data };
    } catch (e) {
      return { success: false, message: String(e) || '人物列表加载异常' };
    }
  }

  /** 人物详情：GET /p/api/v1/ai-person/detail?id=xxx */
  async getAiPersonDetail(
    personId: string,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<AiPersonDetailData>> {
    try {
      if (personId.length === 0) {
        return { success: false, message: 'personId 不能为空' };
      }
      const params: Record<string, string | number | boolean> = {};
      params['id'] = personId;
      const qs = buildGallerySortedQuery(params);
      const signPath = `${FN_PHOTO_API_PREFIX}/ai-person/detail`;
      const pathCandidates: string[] = [
        `${signPath}?${qs}`,
        `/api/v1/ai-person/detail?${qs}`
      ];
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: signPath,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<AiPersonDetailData>(
        pathCandidates, gallerySign, timeoutMs, 3
      );
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '人物详情加载失败' };
      }
      return { success: true, data: res.data };
    } catch (e) {
      return { success: false, message: String(e) || '人物详情加载异常' };
    }
  }

  /**
   * 单张照片中的人物：GET /p/api/v1/ai-person/personInPhoto?id=照片ID
   * 与 Web 预览详情一致，用于展示「人物」标签与图库内该人物总张数等。
   */
  async getPersonInPhoto(
    photoId: string,
    timeoutMs: number = 12000
  ): Promise<FnClientResult<PersonInPhotoData>> {
    try {
      const id = photoId.trim();
      if (id.length === 0) {
        return { success: false, message: 'photoId 不能为空' };
      }
      const params: Record<string, string | number | boolean> = {};
      params['id'] = id;
      const qs = buildGallerySortedQuery(params);
      const pathCandidates: string[] = [];
      for (let i = 0; i < PERSON_IN_PHOTO_PATH_CANDIDATES.length; i++) {
        pathCandidates.push(`${PERSON_IN_PHOTO_PATH_CANDIDATES[i]}?${qs}`);
      }
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: PERSON_IN_PHOTO_SIGN_PATH,
        queryParams: params
      };
      return this.requestGalleryGetJson<PersonInPhotoData>(pathCandidates, gallerySign, timeoutMs, 3);
    } catch (e) {
      return { success: false, message: String(e) || '人物识别加载异常' };
    }
  }

  /** 人物时间线：GET /p/api/v1/ai-person/photoLibrary/timeLine?id=xxx */
  async getAiPersonPhotoTimeline(
    personId: string,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryTimelineData>> {
    try {
      if (personId.length === 0) {
        return { success: false, message: 'personId 不能为空' };
      }
      const params: Record<string, string | number | boolean> = {};
      params['id'] = personId;
      const qs = buildGallerySortedQuery(params);
      const signPath = `${FN_PHOTO_API_PREFIX}/ai-person/photoLibrary/timeLine`;
      const pathCandidates: string[] = [
        `${signPath}?${qs}`,
        `/api/v1/ai-person/photoLibrary/timeLine?${qs}`
      ];
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: signPath,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<GalleryTimelineData>(pathCandidates, gallerySign, timeoutMs, 3);
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '人物时间线加载失败' };
      }
      return { success: true, data: res.data };
    } catch (e) {
      return { success: false, message: String(e) || '人物时间线加载异常' };
    }
  }

  /**
   * 人物照片列表：GET /p/api/v1/ai-person/photoLibrary/list
   * 与官方抓包一致，兼容同时下发 start_time/startTime 与 end_time/endTime、personId 与 album_id。
   */
  async getAiPersonPhotoList(
    personId: string,
    startTime: string,
    endTime: string,
    limit: number,
    offset: number,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryGetListData>> {
    try {
      if (personId.length === 0) {
        return { success: false, message: 'personId 不能为空' };
      }
      const params: Record<string, string | number | boolean> = {};
      params['personId'] = personId;
      params['album_id'] = personId;
      params['start_time'] = startTime;
      params['end_time'] = endTime;
      params['startTime'] = startTime;
      params['endTime'] = endTime;
      params['limit'] = limit;
      params['offset'] = offset;
      const qs = buildGallerySortedQuery(params);
      const signPath = `${FN_PHOTO_API_PREFIX}/ai-person/photoLibrary/list`;
      const pathCandidates: string[] = [
        `${signPath}?${qs}`,
        `/api/v1/ai-person/photoLibrary/list?${qs}`
      ];
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: signPath,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<GalleryGetListData | GalleryListItem[]>(
        pathCandidates, gallerySign, timeoutMs, 3
      );
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '人物照片加载失败' };
      }
      const payload = res.data as GalleryGetListData | GalleryListItem[];
      if (Array.isArray(payload)) {
        return { success: true, data: { list: payload } };
      }
      return { success: true, data: payload as GalleryGetListData };
    } catch (e) {
      return { success: false, message: String(e) || '人物照片加载异常' };
    }
  }

  /**
   * 从接口 data 字段提取分类数组，尝试多种键名。
   * 每条原始记录都经过 normalizeCategoryItem 做字段名映射。
   */
  private static mediaCategoryItemsFromData(dataObj: Object | undefined): MediaCategoryItem[] {
    if (dataObj === undefined || dataObj === null) {
      return [];
    }
    let rawArr: Object[];
    if (Array.isArray(dataObj)) {
      rawArr = dataObj as Object[];
    } else {
      const d = dataObj as Record<string, Object | undefined>;
      const found =
        d['list'] ?? d['items'] ?? d['categoryList'] ?? d['categories'] ??
        d['mediaCategoryList'] ?? d['rows'] ??
        d['records'] ?? d['data'] ?? d['result'];
      if (!Array.isArray(found)) {
        return [];
      }
      rawArr = found as Object[];
    }
    const result: MediaCategoryItem[] = [];
    for (let i = 0; i < rawArr.length; i++) {
      const el = rawArr[i];
      if (typeof el === 'object' && el !== null) {
        result.push(FnHttpClient.normalizeCategoryItem(el as Record<string, Object | undefined>));
      }
    }
    return result;
  }

  /**
   * 已知 file_type / 分类 slug → 列表展示名（media_category/list 常不带 name 时的兜底）
   */
  private static mediaCategoryLabelForKey(key: string): string | undefined {
    const k = key.trim();
    if (k.length === 0) {
      return undefined;
    }
    if (k === 'photo') {
      return '照片';
    }
    if (k === 'video') {
      return '视频';
    }
    if (k === 'live_photo') {
      return '实况 / 动态照片';
    }
    if (k === 'gif') {
      return '动图';
    }
    if (k === 'raw') {
      return 'RAW';
    }
    if (k === 'screenshot') {
      return '屏幕截图';
    }
    /** 与 Web `zp(t)` 一致：searchValue `"360"`、`panorama` */
    if (k === '360') {
      return '360° 全景';
    }
    if (k === 'panorama') {
      return '全景照片';
    }
    return undefined;
  }

  /**
   * 服务端偶发「未命名分类」占位文案：若当作有效名称会挡住后面的 key → 屏幕截图 等兜底。
   */
  private static isPlaceholderCategoryDisplayName(s: string): boolean {
    const t = s.trim();
    if (t.length === 0) {
      return true;
    }
    const lower = t.toLowerCase();
    return t === '未命名分类' || t === '未命名' ||
      lower === 'unnamed' || lower === 'unknown' || lower === 'n/a' ||
      t === '-' || t === '—' || t === '--';
  }

  /**
   * 接口偶发把枚举包一层对象：mediaCategory: { type: 6 }、{ slug: 'screenshot' } 等，剥一层取标量。
   */
  private static unwrapCategoryNested(v: Object): Object | undefined {
    if (typeof v !== 'object' || v === null || Array.isArray(v)) {
      return v;
    }
    const o = v as Record<string, Object | undefined>;
    // 不读嵌套里的 name：可能是「未命名分类」等占位，会被误当成 file_type 字符串
    const inner =
      o['category'] ?? o['type'] ?? o['slug'] ?? o['key'] ?? o['code'] ??
      o['value'] ?? o['id'];
    return inner !== undefined && inner !== null ? inner : v;
  }

  /**
   * 分类行上的「类型」原始字段：不同版本字段名不同。
   * 注意：`categoryId` 在部分 payload 里是**封面照片 id**（很大），不能当枚举；仅当值为 **1–8**（飞牛 Web 媒体类型枚举）时才采纳。
   * `type` / `mediaType` 同理，避免把无关数字当成分类。
   */
  private static pickCategoryScalar(raw: Record<string, Object | undefined>): Object | undefined {
    const preferKeys: string[] = [
      'category', 'categoryType', 'category_type',
      'mediaCategory', 'media_category', 'cat',
      'categoryCode', 'category_code', 'enumValue', 'enum',
    ];
    const narrowKeys: string[] = [
      'type', 'mediaType', 'media_type',
      'categoryId', 'category_id',
    ];
    const tryVal = (v: Object | undefined, onlySmallEnum: boolean): Object | undefined => {
      if (v === undefined || v === null) {
        return undefined;
      }
      if (typeof v === 'string' && v.trim().length === 0) {
        return undefined;
      }
      let x: Object | undefined = FnHttpClient.unwrapCategoryNested(v as Object);
      if (x === undefined || x === null) {
        return undefined;
      }
      if (typeof x === 'number' && Number.isFinite(x)) {
        const n = Math.floor(x as number);
        if (onlySmallEnum && (n < 1 || n > 8)) {
          return undefined;
        }
        return n;
      }
      return x;
    };
    for (let i = 0; i < preferKeys.length; i++) {
      const got = tryVal(raw[preferKeys[i]], false);
      if (got !== undefined) {
        return got;
      }
    }
    for (let j = 0; j < narrowKeys.length; j++) {
      const gotN = tryVal(raw[narrowKeys[j]], true);
      if (gotN !== undefined) {
        return gotN;
      }
    }
    return undefined;
  }

  /**
   * 飞牛 **Web 前端 `zp(i18n)`**（见 /p/assets 打包）：媒体类型枚举 1–8 → 展示名 + v2 search 的 filterValue（searchValue）。
   * 旧版文档写「1–6 且 6=截图」已过时：**6=360°、7=全景、8=截图**。
   */
  private static applyMediaCategoryEnumByIndex(out: MediaCategoryItem, idx: number): void {
    if (idx === 1) {
      out.name = '照片';
      out.key = 'photo';
    } else if (idx === 2) {
      out.name = '视频';
      out.key = 'video';
    } else if (idx === 3) {
      out.name = '实况 / 动态照片';
      out.key = 'live_photo';
    } else if (idx === 4) {
      out.name = '动图';
      out.key = 'gif';
    } else if (idx === 5) {
      out.name = 'RAW';
      out.key = 'raw';
    } else if (idx === 6) {
      out.name = '360° 全景';
      out.key = '360';
    } else if (idx === 7) {
      out.name = '全景照片';
      out.key = 'panorama';
    } else if (idx === 8) {
      out.name = '屏幕截图';
      out.key = 'screenshot';
    }
  }

  /**
   * 将原始 JSON 对象规范化为 MediaCategoryItem。
   *
   * 依据飞牛 Web 打包（如 `Cl8WJe889GVKre8N.js` 内 `zp`）：`category` 为整数 **1–8** 或 slug；
   * **8=截图、6=360°**（勿再按旧版把 6 当成截图）。
   *   - `count` 为该分类的媒体数量
   *   - 封面：`id` + `uuid` / `photoUUID`（接口字段不一致）
   *   - 筛选：`/p/api/v2/search/results` 的 body 与 Web 一致：`filters: [{ filterName:"file_type", filterValue:"photo"|"screenshot" ... }]`
   * 新版列表项可能带 `filterValue`、`displayName`；部分设备用 `specialType: 3` 表示截图类（与单张照片上的标记一致）。
   */
  private static normalizeCategoryItem(raw: Record<string, Object | undefined>): MediaCategoryItem {
    const out: MediaCategoryItem = {};

    let catNum = NaN;
    const catRaw = FnHttpClient.pickCategoryScalar(raw);
    if (typeof catRaw === 'number' && Number.isFinite(catRaw)) {
      const n = Math.floor(catRaw as number);
      // 枚举段 1–8（与 Web zp 一致）；超出则不当成分类序号
      catNum = (n >= 1 && n <= 8) ? n : NaN;
    } else if (typeof catRaw === 'string') {
      const t = (catRaw as string).trim();
      if (t.length > 0) {
        const asInt = parseInt(t, 10);
        if (Number.isFinite(asInt) && String(asInt) === t && asInt >= 1 && asInt <= 8) {
          catNum = asInt;
        } else {
          // 非纯数字：直接作为 file_type（如 screenshot）
          out.key = t;
        }
      }
    }

    if (Number.isFinite(catNum) && catNum >= 1 && catNum <= 8) {
      FnHttpClient.applyMediaCategoryEnumByIndex(out, Math.floor(catNum));
    }

    const nameCand =
      raw['name'] ?? raw['title'] ?? raw['label'] ?? raw['categoryName'] ?? raw['displayName'];
    if (typeof nameCand === 'string' && nameCand.trim().length > 0) {
      const nt = nameCand.trim();
      // 占位「未命名分类」不能覆盖已由枚举推出来的「屏幕截图」等
      if (!FnHttpClient.isPlaceholderCategoryDisplayName(nt)) {
        out.name = nt;
      }
    }
    const keyCand =
      raw['key'] ?? raw['searchValue'] ?? raw['filterValue'] ??
      raw['file_type'] ?? raw['fileType'] ?? raw['mimeCategory'] ?? raw['mime_category'];
    if (typeof keyCand === 'string' && keyCand.trim().length > 0) {
      const kt = keyCand.trim();
      const kInt = parseInt(kt, 10);
      // 列表下发数字枚举时与 Web zp 一致（8=截图，6=360 等）
      if (Number.isFinite(kInt) && String(kInt) === kt && kInt >= 1 && kInt <= 8) {
        FnHttpClient.applyMediaCategoryEnumByIndex(out, kInt);
      } else {
        out.key = kt;
      }
    }

    // 分类枚举 id（与 file_type 筛选一致）；纯 slug 行不强行写 id，避免与封面照片 id 混淆
    out.id = undefined;
    if (Number.isFinite(catNum) && catNum >= 1 && catNum <= 8) {
      out.id = String(Math.floor(catNum));
    } else if (typeof keyCand === 'string' && keyCand.trim().length > 0) {
      const kInt = parseInt(keyCand.trim(), 10);
      if (Number.isFinite(kInt) && String(kInt) === keyCand.trim() && kInt >= 1 && kInt <= 8) {
        out.id = String(kInt);
      }
    }

    /** 部分版本仅通过 specialType 区分截图（常见值 3），与 v2 search 的 file_type=screenshot 对应 */
    const stRaw = raw['specialType'] ?? raw['special_type'];
    let stNum = NaN;
    if (typeof stRaw === 'number' && Number.isFinite(stRaw)) {
      stNum = Math.floor(stRaw as number);
    } else if (typeof stRaw === 'string' && stRaw.trim().length > 0) {
      const st = parseInt(stRaw.trim(), 10);
      if (Number.isFinite(st)) {
        stNum = st;
      }
    }
    const keyBeforeSpecial = out.key !== undefined ? out.key : '';
    // 照片维度 specialType：常见 3=截图（与 category 枚举 8 并列）；勿再用 6（Web 上 6 已为 360°）
    if (keyBeforeSpecial.length === 0 && stNum === 3) {
      out.key = 'screenshot';
      if (out.name === undefined || out.name.length === 0 ||
        FnHttpClient.isPlaceholderCategoryDisplayName(out.name)) {
        out.name = '屏幕截图';
      }
    }

    const keyForLabel = out.key !== undefined ? out.key : '';
    const nameNow = out.name !== undefined ? out.name : '';
    if (keyForLabel.length > 0 &&
      (nameNow.length === 0 || FnHttpClient.isPlaceholderCategoryDisplayName(nameNow))) {
      const lb = FnHttpClient.mediaCategoryLabelForKey(keyForLabel);
      if (lb !== undefined) {
        out.name = lb;
      }
    }

    const countRaw = raw['count'] ?? raw['total'];
    if (countRaw !== undefined) {
      const n = Number(countRaw);
      if (Number.isFinite(n) && n >= 0) {
        const c = Math.floor(n);
        out.count = c;
        out.total = c;
      }
    }

    const photoId = raw['id'];
    const photoUuid = raw['uuid'] ?? raw['photoUUID'];
    if (photoId !== undefined && photoId !== null &&
      photoUuid !== undefined && photoUuid !== null) {
      const idStr = String(photoId);
      const uuidStr = String(photoUuid);
      if (idStr.length > 0 && uuidStr.length > 0 &&
        idStr !== 'null' && uuidStr !== 'null') {
        out.cover = `${FN_PHOTO_API_PREFIX}/stream/p/t/${idStr}/m/${uuidStr}`;
      }
    }

    // v2 filters 与 Web 一致为小写 slug（photo、screenshot、live_photo…）
    if (out.key !== undefined && out.key.length > 0) {
      out.key = out.key.trim().toLowerCase();
    }

    return out;
  }

  private static searchResultItemsFromData(dataObj: Object | undefined): GalleryListItem[] {
    if (dataObj === undefined || dataObj === null) {
      return [];
    }
    if (Array.isArray(dataObj)) {
      return dataObj as GalleryListItem[];
    }
    const d = dataObj as Record<string, Object | undefined>;
    const topRaw = d['list'];
    const topList: GalleryListItem[] | undefined = Array.isArray(topRaw) ? topRaw as GalleryListItem[] : undefined;
    // 与抓包一致：code=0 且 data.list 为照片数组；优先非空 list，避免误用 timeline
    if (topList !== undefined && topList.length > 0) {
      return topList;
    }
    // list 缺失 / null / [] 时尝试剥内层 data（少数网关或旧版套层）
    const inner = d['data'];
    if (inner !== undefined && typeof inner === 'object' && !Array.isArray(inner)) {
      const nested = FnHttpClient.searchResultItemsFromData(inner);
      if (nested.length > 0) {
        return nested;
      }
    }
    if (topList !== undefined) {
      return topList;
    }
    if (Array.isArray(d['items'])) {
      return d['items'] as GalleryListItem[];
    }
    const KEYS: string[] = [
      'photos', 'records', 'results', 'photoList', 'photo_list',
      'data', 'mediaList', 'media_list',
      'fileList', 'file_list', 'pageList', 'page_list',
    ];
    for (let ki = 0; ki < KEYS.length; ki++) {
      const v = d[KEYS[ki]];
      if (Array.isArray(v) && (v as Object[]).length > 0) {
        return v as GalleryListItem[];
      }
    }
    return [];
  }

  /**
   * v2 /search/results 下单条与 gallery/getList 字段略有差异（如 fileName、relative mUrl），
   * 补齐后分类相册页日期键、扩展名与标题与主时间线一致。
   */
  private static normalizeSearchResultGalleryItems(items: GalleryListItem[]): GalleryListItem[] {
    for (let i = 0; i < items.length; i++) {
      const rec = items[i] as Record<string, string | number | Object | undefined>;
      const fileNameVal = rec['fileName'];
      if (typeof fileNameVal === 'string') {
        const baseName = fileNameVal.trim();
        if (baseName.length > 0) {
          const fnLo = rec['filename'];
          if (fnLo === undefined || String(fnLo).trim().length === 0) {
            rec['filename'] = baseName;
          }
          const nm = rec['name'];
          if (nm === undefined || String(nm).trim().length === 0) {
            rec['name'] = baseName;
          }
        }
      }
      // additional.thumbnail 常为站点相对路径；网格里 nasUrl(base, pickThumb) 会拼完整 URL，此处不重复写
    }
    return items;
  }

  /**
   * folder_view/getFileList 常见只返回 id + photoUUID + filePath 等基础字段，
   * 不带 additional.thumbnail。这里补齐缩略图/原图路径，供网格与预览共用。
   */
  private static normalizeFolderViewItems(items: GalleryListItem[]): GalleryListItem[] {
    for (let i = 0; i < items.length; i++) {
      const it = items[i] as Record<string, string | number | Object | undefined>;
      const idVal = it['id'];
      const uuidVal = it['photoUUID'];
      if (idVal === undefined || idVal === null || uuidVal === undefined || uuidVal === null) {
        continue;
      }
      const id = String(idVal).trim();
      const uuid = String(uuidVal).trim();
      if (id.length === 0 || uuid.length === 0) {
        continue;
      }
      // 1) 顶层 thumb / originalUrl 兜底（GalleryAlbumCommon.pickThumb/pickOriginal 会读取）
      const thumbNow = it['thumb'];
      if (thumbNow === undefined || String(thumbNow).trim().length === 0) {
        // 目录视图优先使用 m 档，避免跳转后缩略图明显发糊
        it['thumb'] = `${FN_PHOTO_API_PREFIX}/stream/p/t/${id}/m/${uuid}`;
      }
      const origNow = it['originalUrl'];
      if (origNow === undefined || String(origNow).trim().length === 0) {
        it['originalUrl'] = `${FN_PHOTO_API_PREFIX}/stream/p/t/${id}/o/${uuid}`;
      }

      // 2) 为避免 ArkTS 未类型化对象字面量限制，这里只补顶层字段；
      //    GalleryAlbumCommon.pickThumb/pickOriginal 已能读取 thumb/originalUrl。
    }
    return items;
  }

  /**
   * 分类列表无内嵌 items 时：POST search/results（filters / 旧 body）。
   * 新版 NAS 仅 v2 返回有效列表（如 /p/api/v2/search/results），v1 可能空包；故按 v2 → v1 依次尝试。
   */
  async searchResultsByCategory(item: MediaCategoryItem, timeoutMs: number = 20000): Promise<FnClientResult<GalleryListItem[]>> {
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const searchResultPaths: string[] = [
        `${FN_PHOTO_API_V2_PREFIX}/search/results`,
        `${FN_PHOTO_API_PREFIX}/search/results`,
      ];
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const keyVal = item.key !== undefined ? item.key : '';
      const idVal = item.id !== undefined ? String(item.id) : '';
      const nameVal = item.name ?? item.title ?? item.label ?? '';
      if (keyVal.length > 0) {
        // 与 Web / 抓包一致：POST /p/api/v2/search/results；filterValue 用 JSON.stringify(keyVal) 转义，避免 ArkTS 禁止的内联未类型化对象字面量
        const fv = JSON.stringify(keyVal);
        const filterBodyStr =
          `{"keyword":"","filters":[{"filterName":"file_type","filterValue":${fv}}],"antiFilters":[]}`;
        hilog.info(DOMAIN, TAG, 'catSearch filters body: %{public}s', filterBodyStr);
        for (let pi = 0; pi < searchResultPaths.length; pi++) {
          const pathTry = searchResultPaths[pi];
          const authxFilters = await genFnGalleryAuthxPostRaw(pathTry, filterBodyStr);
          const headersFilters = this.buildGalleryFetchHeaders(authxFilters, cookie);
          headersFilters['Content-Type'] = 'application/json';
          const rawFilters = await this.rawRequest(
            `${activeBase}${pathTry}`,
            http.RequestMethod.POST,
            headersFilters,
            filterBodyStr,
            timeoutMs,
            CertPolicy.isTrusted(activeBase)
          );
          hilog.info(DOMAIN, TAG, 'catSearch path=%{public}s http=%{public}d body500: %{public}s',
            pathTry, rawFilters.code, rawFilters.body.substring(0, 500));
          if (rawFilters.code >= 200 && rawFilters.code < 300) {
            let parsedFilters: Record<string, string | number | Object | undefined> | undefined;
            try {
              parsedFilters = JSON.parse(rawFilters.body) as Record<string, string | number | Object | undefined>;
            } catch (_e) {
              parsedFilters = undefined;
            }
            if (parsedFilters !== undefined && FnHttpClient.galleryEnvelopeBizOk(parsedFilters)) {
              const arrFilters =
                FnHttpClient.searchResultItemsFromData(FnHttpClient.galleryEnvelopeData(parsedFilters));
              hilog.info(DOMAIN, TAG, 'catSearch filters arr.length=%{public}d', arrFilters.length);
              if (arrFilters.length > 0) {
                return {
                  success: true,
                  data: FnHttpClient.normalizeSearchResultGalleryItems(arrFilters),
                };
              }
            }
          }
        }
      }

      const candidates: Array<Record<string, FnJsonValue>> = [];
      const pushCandidate = (k: string, v: string): void => {
        const body: Record<string, FnJsonValue> = {};
        body[k] = v;
        body['limit'] = 200;
        body['offset'] = 0;
        candidates.push(body);
      };
      if (keyVal.length > 0) {
        pushCandidate('file_type', keyVal);
      }
      if (idVal.length > 0) {
        pushCandidate('category_type', idVal);
        pushCandidate('person_id', idVal);
        pushCandidate('id', idVal);
      }
      if (nameVal.length > 0) {
        pushCandidate('keyword', nameVal);
      }
      for (let i = 0; i < candidates.length; i++) {
        const body = candidates[i];
        const bodyStr = JSON.stringify(body);
        for (let pi = 0; pi < searchResultPaths.length; pi++) {
          const pathTry = searchResultPaths[pi];
          const authx = await genFnGalleryAuthxPost(pathTry, body);
          const headers = this.buildGalleryFetchHeaders(authx, cookie);
          headers['Content-Type'] = 'application/json';
          const raw = await this.rawRequest(
            `${activeBase}${pathTry}`,
            http.RequestMethod.POST,
            headers,
            bodyStr,
            timeoutMs,
            CertPolicy.isTrusted(activeBase)
          );
          if (raw.code < 200 || raw.code >= 300) {
            continue;
          }
          let parsed: Record<string, string | number | Object | undefined>;
          try {
            parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
          } catch (_e) {
            continue;
          }
          if (!FnHttpClient.galleryEnvelopeBizOk(parsed)) {
            continue;
          }
          const arr = FnHttpClient.searchResultItemsFromData(FnHttpClient.galleryEnvelopeData(parsed));
          if (arr.length > 0) {
            return { success: true, data: FnHttpClient.normalizeSearchResultGalleryItems(arr) };
          }
        }
      }
      return { success: false, message: '分类结果为空' };
    } catch (e) {
      return { success: false, message: String(e) || '分类检索异常' };
    }
  }

  /**
   * 按媒体类型（file_type）查询图库，用于媒体分类点击后展示该分类所有媒体。
   * file_type 值来自 fnOS 前端：photo / video / gif / raw / live_photo
   * 使用与图库时间轴相同的 gallery/getList 接口，附加 file_type 参数。
   */
  async getCategoryPhotos(
    fileType: string,
    limit: number = 200,
    offset: number = 0
  ): Promise<FnClientResult<GalleryListItem[]>> {
    const params: Record<string, string | number | boolean> = {};
    params['file_type'] = fileType;
    params['mode'] = 'index';
    params['start_time'] = '2000-01-01 00:00:00';
    params['end_time'] = '2099-12-31 23:59:59';
    params['offset'] = offset;
    params['limit'] = limit;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [];
    for (let i = 0; i < GALLERY_GETLIST_PATH_CANDIDATES.length; i++) {
      pathCandidates.push(`${GALLERY_GETLIST_PATH_CANDIDATES[i]}?${qs}`);
    }
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: GALLERY_GETLIST_SIGN_PATH,
      queryParams: params
    };
    const res = await this.requestGalleryGetJson<GalleryGetListData | GalleryListItem[]>(
      pathCandidates,
      gallerySign,
      DEFAULT_TIMEOUT,
      3
    );
    if (!res.success || res.data === undefined) {
      return { success: false, message: res.message ?? '分类照片加载失败' };
    }
    const payload = res.data as GalleryGetListData | GalleryListItem[];
    let list: GalleryListItem[];
    if (Array.isArray(payload)) {
      list = payload as GalleryListItem[];
    } else {
      list = (payload as GalleryGetListData).list ?? [];
    }
    hilog.info(DOMAIN, TAG, 'getCategoryPhotos fileType=%{public}s count=%{public}d', fileType, list.length);
    if (list.length === 0) {
      return { success: false, message: '分类结果为空' };
    }
    return { success: true, data: list };
  }

  /**
   * 收藏夹列表：GET gallery/getList，抓包形态为 mode=collect & is_collect=1，与时间轴参数一致。
   */
  async getCollectGalleryList(
    startTime: string,
    endTime: string,
    limit: number,
    offset: number
  ): Promise<FnClientResult<GalleryGetListData>> {
    const params: Record<string, string | number | boolean> = {};
    params['start_time'] = startTime;
    params['end_time'] = endTime;
    params['mode'] = 'collect';
    params['is_collect'] = 1;
    params['offset'] = offset;
    params['limit'] = limit;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [];
    for (let i = 0; i < GALLERY_GETLIST_PATH_CANDIDATES.length; i++) {
      pathCandidates.push(`${GALLERY_GETLIST_PATH_CANDIDATES[i]}?${qs}`);
    }
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: GALLERY_GETLIST_SIGN_PATH,
      queryParams: params
    };
    const res = await this.requestGalleryGetJson<GalleryGetListData | GalleryListItem[]>(
      pathCandidates,
      gallerySign,
      DEFAULT_TIMEOUT,
      3
    );
    if (!res.success || res.data === undefined) {
      return res as FnClientResult<GalleryGetListData>;
    }
    const payload = res.data as GalleryGetListData | GalleryListItem[];
    if (Array.isArray(payload)) {
      const norm: GalleryGetListData = { list: payload };
      return {
        success: true,
        data: norm,
        moveUrl: res.moveUrl,
        fnosLongToken: res.fnosLongToken
      };
    }
    return res as FnClientResult<GalleryGetListData>;
  }

  async getGalleryList(
    startTime: string,
    endTime: string,
    limit: number,
    offset: number,
    mode: string = 'index'
  ): Promise<FnClientResult<GalleryGetListData>> {
    const params: Record<string, string | number | boolean> = {};
    params['start_time'] = startTime;
    params['end_time'] = endTime;
    params['mode'] = mode;
    params['offset'] = offset;
    params['limit'] = limit;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [];
    for (let i = 0; i < GALLERY_GETLIST_PATH_CANDIDATES.length; i++) {
      pathCandidates.push(`${GALLERY_GETLIST_PATH_CANDIDATES[i]}?${qs}`);
    }
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: GALLERY_GETLIST_SIGN_PATH,
      queryParams: params
    };
    const res = await this.requestGalleryGetJson<GalleryGetListData | GalleryListItem[]>(
      pathCandidates,
      gallerySign,
      DEFAULT_TIMEOUT,
      3
    );
    if (!res.success || res.data === undefined) {
      return res as FnClientResult<GalleryGetListData>;
    }
    const payload = res.data as GalleryGetListData | GalleryListItem[];
    if (Array.isArray(payload)) {
      const norm: GalleryGetListData = { list: payload };
      return {
        success: true,
        data: norm,
        moveUrl: res.moveUrl,
        fnosLongToken: res.fnosLongToken
      };
    }
    return res as FnClientResult<GalleryGetListData>;
  }

  /**
   * 最近添加列表：GET /p/api/v1/explore/recent_photos
   * 参数形态与 gallery/getList 类似，mode 需使用 "recent"。
   */
  async getRecentPhotos(
    startTime: string,
    endTime: string,
    limit: number,
    offset: number,
    mode: string = 'recent'
  ): Promise<FnClientResult<GalleryGetListData>> {
    const params: Record<string, string | number | boolean> = {};
    params['start_time'] = startTime;
    params['end_time'] = endTime;
    params['mode'] = mode;
    params['offset'] = offset;
    params['limit'] = limit;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [];
    for (let i = 0; i < RECENT_PHOTOS_PATH_CANDIDATES.length; i++) {
      pathCandidates.push(`${RECENT_PHOTOS_PATH_CANDIDATES[i]}?${qs}`);
    }
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: RECENT_PHOTOS_SIGN_PATH,
      queryParams: params
    };
    const res = await this.requestGalleryGetJson<GalleryGetListData | GalleryListItem[]>(
      pathCandidates,
      gallerySign,
      DEFAULT_TIMEOUT,
      3
    );
    if (!res.success || res.data === undefined) {
      return res as FnClientResult<GalleryGetListData>;
    }
    const payload = res.data as GalleryGetListData | GalleryListItem[];
    if (Array.isArray(payload)) {
      const norm: GalleryGetListData = { list: payload };
      return {
        success: true,
        data: norm,
        moveUrl: res.moveUrl,
        fnosLongToken: res.fnosLongToken
      };
    }
    return res as FnClientResult<GalleryGetListData>;
  }

  /**
   * 相册单条详情：GET /p/api/v1/gallery/getOne?id=xxx
   * 用于预览页右上角「详情」展示完整 EXIF/位置信息。
   */
  async getGalleryPhotoDetail(
    photoId: string,
    timeoutMs: number = 15000
  ): Promise<FnClientResult<GalleryPhotoDetailData>> {
    const id = photoId.trim();
    if (id.length === 0) {
      return { success: false, message: 'photoId 不能为空' };
    }
    const params: Record<string, string | number | boolean> = {};
    params['id'] = id;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [];
    for (let i = 0; i < GALLERY_GETONE_PATH_CANDIDATES.length; i++) {
      pathCandidates.push(`${GALLERY_GETONE_PATH_CANDIDATES[i]}?${qs}`);
    }
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: GALLERY_GETONE_SIGN_PATH,
      queryParams: params
    };
    return this.requestGalleryGetJson<GalleryPhotoDetailData>(pathCandidates, gallerySign, timeoutMs, 3);
  }

  /**
   * 目录媒体列表：GET /p/api/v1/folder_view/getFileList
   * 点击详情中的文件夹路径时，用该接口打开同目录下全部媒体。
   */
  async getFolderViewFileList(
    folderPath: string,
    limit: number = 100,
    offset: number = 0,
    desc: boolean = false,
    orderBy: number = 2,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryListItem[]>> {
    const fp = folderPath.trim();
    if (fp.length === 0) {
      return { success: false, message: 'folderPath 不能为空' };
    }
    const params: Record<string, string | number | boolean> = {};
    params['folderPath'] = fp;
    params['desc'] = desc;
    params['orderBy'] = orderBy;
    params['limit'] = limit;
    params['offset'] = offset;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [];
    for (let i = 0; i < GALLERY_FOLDER_FILELIST_PATH_CANDIDATES.length; i++) {
      pathCandidates.push(`${GALLERY_FOLDER_FILELIST_PATH_CANDIDATES[i]}?${qs}`);
    }
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: GALLERY_FOLDER_FILELIST_SIGN_PATH,
      queryParams: params
    };
    const res = await this.requestGalleryGetJson<GalleryGetListData | GalleryListItem[]>(
      pathCandidates,
      gallerySign,
      timeoutMs,
      3
    );
    if (!res.success || res.data === undefined) {
      return { success: false, message: res.message ?? '文件夹媒体加载失败' };
    }
    const payload = res.data as GalleryGetListData | GalleryListItem[];
    if (Array.isArray(payload)) {
      return { success: true, data: FnHttpClient.normalizeFolderViewItems(payload as GalleryListItem[]) };
    }
    const dataObj = payload as GalleryGetListData;
    const list = dataObj.list ?? dataObj.items ?? dataObj.photos ?? dataObj.records ?? [];
    if (!Array.isArray(list)) {
      return { success: true, data: [] };
    }
    return { success: true, data: FnHttpClient.normalizeFolderViewItems(list as GalleryListItem[]) };
  }

  /**
   * 回收站列表：GET /p/api/v1/recycle-bin/list
   * start_time / end_time 与相册接口一致：`YYYY:MM:DD HH:mm:ss`（空格分隔日期与时间）。
   */
  async getRecycleBinList(
    offset: number,
    limit: number,
    startTime: string,
    endTime: string,
    timeoutMs: number = 25000
  ): Promise<FnClientResult<RecycleBinListData>> {
    const params: Record<string, string | number | boolean> = {};
    params['offset'] = offset;
    params['limit'] = limit;
    params['start_time'] = startTime;
    params['end_time'] = endTime;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [
      `${RECYCLE_BIN_LIST_SIGN_PATH}?${qs}`,
      `/api/v1/recycle-bin/list?${qs}`
    ];
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: RECYCLE_BIN_LIST_SIGN_PATH,
      queryParams: params
    };
    return this.requestGalleryGetJson<RecycleBinListData>(pathCandidates, gallerySign, timeoutMs, 3);
  }

  /**
   * 将媒体移入回收站：POST /p/api/v1/recycle-bin/add
   * 由于不同版本 NAS 请求体字段存在差异，这里按多种候选 body 依次尝试，提升兼容性。
   */
  async addPhotoToRecycleBin(
    photoId: string,
    timeoutMs: number = 15000
  ): Promise<FnClientResult<Object>> {
    const id = photoId.trim();
    if (id.length === 0) {
      return { success: false, message: 'photoId 不能为空' };
    }
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const path = `${FN_PHOTO_API_PREFIX}/recycle-bin/add`;
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const escapedId = escapeJsonString(id);
      const parsedNum = Number(id);
      const hasNumericId = Number.isFinite(parsedNum) && parsedNum >= 0;
      const bodyCandidates: string[] = [];
      // 优先命中抓包实参：{ ids: [84238] }
      if (hasNumericId) {
        bodyCandidates.push(`{"ids":[${Math.floor(parsedNum)}]}`);
      }
      bodyCandidates.push(
        `{"ids":["${escapedId}"]}`,
        `{"id":"${escapedId}"}`,
        `{"photoId":"${escapedId}"}`,
        `{"photoIds":["${escapedId}"]}`,
        `{"list":["${escapedId}"]}`,
        `{"itemIds":["${escapedId}"]}`
      );
      let lastMsg = '移入回收站失败';
      for (let i = 0; i < bodyCandidates.length; i++) {
        const bodyStr = bodyCandidates[i];
        try {
          const authx = await genFnGalleryAuthxPostRaw(path, bodyStr);
          const headers = this.buildGalleryFetchHeaders(authx, cookie);
          headers['Content-Type'] = 'application/json';
          const raw = await this.rawRequest(
            `${activeBase}${path}`,
            http.RequestMethod.POST,
            headers,
            bodyStr,
            timeoutMs,
            CertPolicy.isTrusted(activeBase)
          );
          if (raw.code < 200 || raw.code >= 300) {
            lastMsg = `HTTP ${raw.code}`;
            continue;
          }
          let parsed: Record<string, string | number | Object | undefined>;
          try {
            parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
          } catch (_e) {
            lastMsg = '删除响应解析失败';
            continue;
          }
          if (FnHttpClient.galleryEnvelopeBizOk(parsed)) {
            return { success: true, data: parsed['data'] as Object };
          }
          const errLine = FnHttpClient.envelopeErrorLine(parsed);
          if (errLine.length > 0) {
            lastMsg = errLine;
            const low = errLine.toLowerCase();
            if (errLine.indexOf('已在回收站') >= 0 || low.indexOf('already') >= 0) {
              return { success: true, data: parsed['data'] as Object };
            }
          }
        } catch (e) {
          lastMsg = String(e) || '删除请求异常';
        }
      }
      return { success: false, message: lastMsg };
    } catch (e) {
      return { success: false, message: String(e) || '删除请求异常' };
    }
  }

  /**
   * 将照片加入收藏：POST /p/api/v1/preview/collect
   * 不同版本 body 字段可能为 id / ids / photoId 等，按候选依次尝试。
   */
  async postPreviewCollect(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    const id = photoId.trim();
    if (id.length === 0) {
      return { success: false, message: 'photoId 不能为空' };
    }
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const path = `${FN_PHOTO_API_PREFIX}/preview/collect`;
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const escapedId = escapeJsonString(id);
      const parsedNum = Number(id);
      const hasNumericId = Number.isFinite(parsedNum) && parsedNum >= 0;
      const bodyCandidates: string[] = [];
      if (hasNumericId) {
        bodyCandidates.push(`{"id":${Math.floor(parsedNum)}}`);
        bodyCandidates.push(`{"ids":[${Math.floor(parsedNum)}]}`);
      }
      bodyCandidates.push(
        `{"id":"${escapedId}"}`,
        `{"ids":["${escapedId}"]}`,
        `{"photoId":"${escapedId}"}`,
        `{"photoIds":["${escapedId}"]}`
      );
      let lastMsg = '收藏失败';
      for (let i = 0; i < bodyCandidates.length; i++) {
        const bodyStr = bodyCandidates[i];
        try {
          const authx = await genFnGalleryAuthxPostRaw(path, bodyStr);
          const headers = this.buildGalleryFetchHeaders(authx, cookie);
          headers['Content-Type'] = 'application/json';
          const raw = await this.rawRequest(
            `${activeBase}${path}`,
            http.RequestMethod.POST,
            headers,
            bodyStr,
            timeoutMs,
            CertPolicy.isTrusted(activeBase)
          );
          if (raw.code < 200 || raw.code >= 300) {
            lastMsg = `HTTP ${raw.code}`;
            continue;
          }
          let parsed: Record<string, string | number | Object | undefined>;
          try {
            parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
          } catch (_e) {
            lastMsg = '收藏响应解析失败';
            continue;
          }
          if (FnHttpClient.galleryEnvelopeBizOk(parsed)) {
            return { success: true, data: parsed['data'] as Object };
          }
          const errLine = FnHttpClient.envelopeErrorLine(parsed);
          if (errLine.length > 0) {
            lastMsg = errLine;
            const low = errLine.toLowerCase();
            if (errLine.indexOf('已收藏') >= 0 || low.indexOf('already') >= 0 || low.indexOf('collected') >= 0) {
              return { success: true, data: parsed['data'] as Object };
            }
          }
        } catch (e) {
          lastMsg = String(e) || '收藏请求异常';
        }
      }
      return { success: false, message: lastMsg };
    } catch (e) {
      return { success: false, message: String(e) || '收藏请求异常' };
    }
  }

  /**
   * 取消收藏：POST /p/api/v1/preview/collect/cancel（与 Web 收藏页取消一致）
   * body 形态与 preview/collect 相同，按候选依次尝试。
   */
  async postPreviewCollectCancel(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    const id = photoId.trim();
    if (id.length === 0) {
      return { success: false, message: 'photoId 不能为空' };
    }
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const path = `${FN_PHOTO_API_PREFIX}/preview/collect/cancel`;
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const escapedId = escapeJsonString(id);
      const parsedNum = Number(id);
      const hasNumericId = Number.isFinite(parsedNum) && parsedNum >= 0;
      const bodyCandidates: string[] = [];
      if (hasNumericId) {
        bodyCandidates.push(`{"id":${Math.floor(parsedNum)}}`);
        bodyCandidates.push(`{"ids":[${Math.floor(parsedNum)}]}`);
      }
      bodyCandidates.push(
        `{"id":"${escapedId}"}`,
        `{"ids":["${escapedId}"]}`,
        `{"photoId":"${escapedId}"}`,
        `{"photoIds":["${escapedId}"]}`
      );
      let lastMsg = '取消收藏失败';
      for (let i = 0; i < bodyCandidates.length; i++) {
        const bodyStr = bodyCandidates[i];
        try {
          const authx = await genFnGalleryAuthxPostRaw(path, bodyStr);
          const headers = this.buildGalleryFetchHeaders(authx, cookie);
          headers['Content-Type'] = 'application/json';
          const raw = await this.rawRequest(
            `${activeBase}${path}`,
            http.RequestMethod.POST,
            headers,
            bodyStr,
            timeoutMs,
            CertPolicy.isTrusted(activeBase)
          );
          if (raw.code < 200 || raw.code >= 300) {
            lastMsg = `HTTP ${raw.code}`;
            continue;
          }
          let parsed: Record<string, string | number | Object | undefined>;
          try {
            parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
          } catch (_e) {
            lastMsg = '取消收藏响应解析失败';
            continue;
          }
          if (FnHttpClient.galleryEnvelopeBizOk(parsed)) {
            return { success: true, data: parsed['data'] as Object };
          }
          const errLine = FnHttpClient.envelopeErrorLine(parsed);
          if (errLine.length > 0) {
            lastMsg = errLine;
            const low = errLine.toLowerCase();
            if (errLine.indexOf('未收藏') >= 0 || errLine.indexOf('未在收藏') >= 0 ||
              low.indexOf('not collect') >= 0 || low.indexOf('no favorite') >= 0) {
              return { success: true, data: parsed['data'] as Object };
            }
          }
        } catch (e) {
          lastMsg = String(e) || '取消收藏请求异常';
        }
      }
      return { success: false, message: lastMsg };
    } catch (e) {
      return { success: false, message: String(e) || '取消收藏请求异常' };
    }
  }

  /**
   * 从回收站恢复：POST /p/api/v1/recycle-bin/restore，body `{"ids":[84291,84290,...]}`
   */
  async restoreRecycleBinPhotos(
    ids: number[],
    timeoutMs: number = 30000
  ): Promise<FnClientResult<Object>> {
    const clean: number[] = [];
    for (let i = 0; i < ids.length; i++) {
      const n = Math.floor(Number(ids[i]));
      if (Number.isFinite(n) && n > 0) {
        clean.push(n);
      }
    }
    if (clean.length === 0) {
      return { success: false, message: 'ids 无效' };
    }
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const path = `${FN_PHOTO_API_PREFIX}/recycle-bin/restore`;
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const bodyStr = `{"ids":[${clean.join(',')}]}`;
      const authx = await genFnGalleryAuthxPostRaw(path, bodyStr);
      const headers = this.buildGalleryFetchHeaders(authx, cookie);
      headers['Content-Type'] = 'application/json';
      const raw = await this.rawRequest(
        `${activeBase}${path}`,
        http.RequestMethod.POST,
        headers,
        bodyStr,
        timeoutMs,
        CertPolicy.isTrusted(activeBase)
      );
      if (raw.code < 200 || raw.code >= 300) {
        return { success: false, message: `HTTP ${raw.code}` };
      }
      let parsed: Record<string, string | number | Object | undefined>;
      try {
        parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
      } catch (_e) {
        return { success: false, message: '响应解析失败' };
      }
      if (FnHttpClient.galleryEnvelopeBizOk(parsed)) {
        return { success: true, data: parsed['data'] as Object };
      }
      const errLine = FnHttpClient.envelopeErrorLine(parsed);
      return { success: false, message: errLine.length > 0 ? errLine : '恢复失败' };
    } catch (e) {
      return { success: false, message: String(e) || '恢复请求异常' };
    }
  }

  private static fileNameFromUri(uri: string): string {
    const q = uri.indexOf('?');
    const base = q >= 0 ? uri.substring(0, q) : uri;
    const slash = Math.max(base.lastIndexOf('/'), base.lastIndexOf('\\'));
    const raw = slash >= 0 ? base.substring(slash + 1) : base;
    const out = decodeUriPartSafely(raw.trim());
    return out.length > 0 ? out : `upload_${Date.now()}.jpg`;
  }

  /**
   * 飞牛相册 upload/notice 抓包中的 file_create_time：对齐 Python `strftime("%Y:%m:%d %H:%M:%S")`（如 2026:03:27 14:53:36）
   */
  private static formatNoticeFileCreateTime(mtimSec: string): string {
    const sec = Number(mtimSec.trim());
    const ms = Number.isFinite(sec) && sec > 0 ? sec * 1000 : Date.now();
    const d = new Date(ms);
    const y = d.getFullYear();
    const m = pad2(d.getMonth() + 1);
    const day = pad2(d.getDate());
    const h = pad2(d.getHours());
    const mi = pad2(d.getMinutes());
    const s = pad2(d.getSeconds());
    return `${y}:${m}:${day} ${h}:${mi}:${s}`;
  }

  /**
   * 将 @kit.CoreFileKit stat 的 mtime 规范为 Unix 秒（对齐 `getmtime` / Trim-Mtim）。
   * 文档常见为纳秒时间戳；部分环境可能为毫秒或秒。
   */
  private static statMtimeToUnixSec(st: object): number {
    const o = st as Record<string, number | bigint | string | undefined>;
    const rawVal = o['mtime'];
    if (rawVal === undefined || rawVal === null) {
      return Math.floor(Date.now() / 1000);
    }
    const raw =
      typeof rawVal === 'bigint' ? Number(rawVal) : Number(String(rawVal));
    if (!Number.isFinite(raw) || raw <= 0) {
      return Math.floor(Date.now() / 1000);
    }
    if (raw > 1e15) {
      return Math.floor(raw / 1e9);
    }
    if (raw > 1e12) {
      return Math.floor(raw / 1e3);
    }
    return Math.floor(raw);
  }

  /**
   * 一次 open 读出全文 + 修改时间，供 /upload 的 Trim-Mtim、Trim-Sign 与 notice 使用。
   */
  private static readUploadFileAndMtime(uri: string): UploadFileReadResult | undefined {
    let fdNum = -1;
    try {
      const f = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      fdNum = f.fd;
      const st = fileIo.statSync(fdNum);
      const mtimeSec = FnHttpClient.statMtimeToUnixSec(st);
      const size = Number(st.size);
      if (!Number.isFinite(size) || size <= 0) {
        return undefined;
      }
      const whole = new ArrayBuffer(Math.floor(size));
      const readLen = fileIo.readSync(fdNum, whole);
      if (!Number.isFinite(readLen) || readLen <= 0) {
        return undefined;
      }
      const buffer = readLen < whole.byteLength ? whole.slice(0, readLen) : whole;
      return { buffer: buffer, mtimeSec: mtimeSec };
    } catch (_e) {
      return undefined;
    } finally {
      if (fdNum >= 0) {
        try {
          fileIo.closeSync(fdNum);
        } catch (_e) {}
      }
    }
  }

  /**
   * 从上传接口响应中尽量提取可用于后续补偿的 photoId。
   * 兼容常见结构：
   * - { id: 1 } / { photoId: 1 }
   * - { data: { id: 1 } }
   * - { data: { ids: [1] } } / { ids: [1] }
   */
  private static firstUploadPhotoIdFromResponse(rawBody: string): string {
    if (rawBody.length === 0) {
      return '';
    }
    let parsed: Record<string, string | number | Object | undefined>;
    try {
      parsed = JSON.parse(rawBody) as Record<string, string | number | Object | undefined>;
    } catch (_e) {
      return '';
    }
    const pickDirect = (obj: Record<string, string | number | Object | undefined>): string => {
      const one = obj['id'] ?? obj['photoId'] ?? obj['fileId'] ?? obj['itemId'];
      if (one !== undefined && one !== null) {
        const s = String(one).trim();
        if (s.length > 0 && s !== 'null' && s !== 'undefined') {
          return s;
        }
      }
      const arrOne = obj['ids'] ?? obj['photoIds'] ?? obj['list'] ?? obj['itemIds'];
      if (Array.isArray(arrOne) && arrOne.length > 0) {
        // ArkTS 禁止隐式 any/unknown：对数组元素做显式类型约束。
        const typedArr = arrOne as Array<string | number | Object | undefined>;
        const first = typedArr[0];
        if (first !== undefined && first !== null) {
          const fs = String(first).trim();
          if (fs.length > 0 && fs !== 'null' && fs !== 'undefined') {
            return fs;
          }
        }
      }
      return '';
    };
    const rootPicked = pickDirect(parsed);
    if (rootPicked.length > 0) {
      return rootPicked;
    }
    const dataObj = parsed['data'];
    if (dataObj !== undefined && dataObj !== null && typeof dataObj === 'object' && !Array.isArray(dataObj)) {
      const nested = dataObj as Record<string, string | number | Object | undefined>;
      return pickDirect(nested);
    }
    return '';
  }

  /**
   * 从对象中提取“路径类”字段，兼容常见命名。
   */
  private static firstPathLikeFromRecord(obj: Record<string, string | number | Object | undefined>): string {
    const direct = obj['path'] ?? obj['filePath'] ?? obj['uploadPath'] ?? obj['targetPath'] ?? obj['dstPath'] ?? obj['destPath'];
    if (direct !== undefined && direct !== null) {
      const s = String(direct).trim();
      if (s.length > 0 && s !== 'null' && s !== 'undefined') {
        return s;
      }
    }
    const arrLike = obj['paths'] ?? obj['filePaths'] ?? obj['uploadPaths'] ?? obj['list'];
    if (Array.isArray(arrLike) && arrLike.length > 0) {
      const typedArr = arrLike as Array<string | number | Object | undefined>;
      const first = typedArr[0];
      if (first !== undefined && first !== null) {
        const fs = String(first).trim();
        if (fs.length > 0 && fs !== 'null' && fs !== 'undefined') {
          return fs;
        }
      }
    }
    return '';
  }

  /**
   * 从响应 JSON 中提取上传路径提示（用于 notice 入参兼容）。
   */
  private static firstUploadPathFromResponse(rawBody: string): string {
    if (rawBody.length === 0) {
      return '';
    }
    let parsed: Record<string, string | number | Object | undefined>;
    try {
      parsed = JSON.parse(rawBody) as Record<string, string | number | Object | undefined>;
    } catch (_e) {
      return '';
    }
    const root = FnHttpClient.firstPathLikeFromRecord(parsed);
    if (root.length > 0) {
      return root;
    }
    const dataObj = parsed['data'];
    if (dataObj !== undefined && dataObj !== null && typeof dataObj === 'object' && !Array.isArray(dataObj)) {
      const nested = dataObj as Record<string, string | number | Object | undefined>;
      return FnHttpClient.firstPathLikeFromRecord(nested);
    }
    return '';
  }

  /**
   * 对齐 Web 侧上传前预请求：
   * GET /p/api/v2 或 v1 /photo/upload/path（不同 NAS 版本只实现其一）。
   * 返回可用的路径提示（若服务端未返回则为空串，不阻断上传）。
   */
  private async requestUploadPathHint(fileName: string, timeoutMs: number): Promise<string> {
    const activeBase = fnWebViewBaseUrl(this.baseUrl);
    const cookie = mergeGalleryWebCookieIntoNativeHeader(
      buildFnApiCookieHeader(this.token, this.longToken),
      activeBase
    );
    const pathBases: string[] = [
      '/p/api/v2/photo/upload/path',
      `${FN_PHOTO_API_PREFIX}/photo/upload/path`
    ];
    const paramsCandidates: Array<Record<string, string | number | boolean>> = [
      GALLERY_QUERY_EMPTY,
      { 'name': fileName },
      { 'fileName': fileName },
      { 'filename': fileName }
    ];
    for (let pi = 0; pi < pathBases.length; pi++) {
      const path = pathBases[pi];
      for (let i = 0; i < paramsCandidates.length; i++) {
        try {
          const oneParams = paramsCandidates[i];
          const qs = buildGallerySortedQuery(oneParams);
          const urlPath = qs.length > 0 ? `${path}?${qs}` : path;
          const authx = await genFnGalleryAuthxGet(path, oneParams);
          const headers = this.buildGalleryFetchHeaders(authx, cookie);
          const raw = await this.rawRequest(
            `${activeBase}${urlPath}`,
            http.RequestMethod.GET,
            headers,
            undefined,
            timeoutMs,
            CertPolicy.isTrusted(activeBase)
          );
          if (raw.code < 200 || raw.code >= 300) {
            continue;
          }
          const p = FnHttpClient.firstUploadPathFromResponse(raw.body);
          if (p.length > 0) {
            return p;
          }
        } catch (_e) {}
      }
    }
    return '';
  }

  /**
   * 上传后兜底恢复：某些版本会把新文件先挂到回收站，再要求显式 restore。
   * 仅在 photo/upload/notice 失败时触发，不影响现有已可用链路。
   */
  private async restoreUploadedPhoto(
    photoId: string,
    timeoutMs: number
  ): Promise<boolean> {
    const id = photoId.trim();
    if (id.length === 0) {
      return false;
    }
    const activeBase = fnWebViewBaseUrl(this.baseUrl);
    const path = `${FN_PHOTO_API_PREFIX}/recycle-bin/restore`;
    const cookie = mergeGalleryWebCookieIntoNativeHeader(
      buildFnApiCookieHeader(this.token, this.longToken),
      activeBase
    );
    const escapedId = escapeJsonString(id);
    const parsedNum = Number(id);
    const hasNumericId = Number.isFinite(parsedNum) && parsedNum >= 0;
    const bodyCandidates: string[] = [];
    if (hasNumericId) {
      bodyCandidates.push(`{"ids":[${Math.floor(parsedNum)}]}`);
    }
    bodyCandidates.push(
      `{"ids":["${escapedId}"]}`,
      `{"id":"${escapedId}"}`,
      `{"photoId":"${escapedId}"}`
    );
    for (let i = 0; i < bodyCandidates.length; i++) {
      try {
        const bodyStr = bodyCandidates[i];
        const authx = await genFnGalleryAuthxPostRaw(path, bodyStr);
        const headers = this.buildGalleryFetchHeaders(authx, cookie);
        headers['Content-Type'] = 'application/json';
        const raw = await this.rawRequest(
          `${activeBase}${path}`,
          http.RequestMethod.POST,
          headers,
          bodyStr,
          timeoutMs,
          CertPolicy.isTrusted(activeBase)
        );
        if (raw.code < 200 || raw.code >= 300) {
          continue;
        }
        let parsed: Record<string, string | number | Object | undefined>;
        try {
          parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
        } catch (_e) {
          continue;
        }
        if (FnHttpClient.galleryEnvelopeBizOk(parsed)) {
          return true;
        }
      } catch (_e) {}
    }
    return false;
  }

  private async notifyPhotoUploaded(
    fileName: string,
    sourceUri: string,
    timeoutMs: number,
    pathHints: string[] = [],
    uploadMtimSec: string = '',
    hintedFullPathPlain: string = ''
  ): Promise<UploadNoticeResult> {
    const activeBase = fnWebViewBaseUrl(this.baseUrl);
    const path = `${FN_PHOTO_API_PREFIX}/photo/upload/notice`;
    const cookie = mergeGalleryWebCookieIntoNativeHeader(
      buildFnApiCookieHeader(this.token, this.longToken),
      activeBase
    );
    const escName = escapeJsonString(fileName);
    const escUri = escapeJsonString(sourceUri);
    const bodyCandidates: string[] = [];
    const pushCandidate = (v: string): void => {
      if (bodyCandidates.indexOf(v) < 0) {
        bodyCandidates.push(v);
      }
    };
    // 与 Web 一致：files 数组 + file_create_time / original_name / file_name（优先尝试）
    const mtimForNotice = uploadMtimSec.trim().length > 0 ? uploadMtimSec.trim() : String(Math.floor(Date.now() / 1000));
    const fc = FnHttpClient.formatNoticeFileCreateTime(mtimForNotice);
    const seg = lastUnixPathSegment(hintedFullPathPlain);
    const escFileOnDisk = seg.length > 0 ? escapeJsonString(seg) : escName;
    pushCandidate(`{"files":[{"file_create_time":"${fc}","original_name":"${escName}","file_name":"${escFileOnDisk}"}]}`);
    pushCandidate(`{"files":[{"file_create_time":"${fc}","original_name":"${escName}","file_name":"${escName}"}]}`);
    pushCandidate(`{"name":"${escName}"}`);
    pushCandidate(`{"fileName":"${escName}"}`);
    pushCandidate(`{"filename":"${escName}"}`);
    pushCandidate(`{"uri":"${escUri}","name":"${escName}"}`);
    pushCandidate(`{"items":[{"name":"${escName}"}]}`);
    for (let i = 0; i < pathHints.length; i++) {
      const p = pathHints[i].trim();
      if (p.length === 0) {
        continue;
      }
      const ep = escapeJsonString(p);
      pushCandidate(`{"path":"${ep}"}`);
      pushCandidate(`{"filePath":"${ep}"}`);
      pushCandidate(`{"uploadPath":"${ep}"}`);
      pushCandidate(`{"paths":["${ep}"]}`);
      pushCandidate(`{"name":"${escName}","path":"${ep}"}`);
      pushCandidate(`{"fileName":"${escName}","path":"${ep}"}`);
      pushCandidate(`{"uri":"${escUri}","name":"${escName}","path":"${ep}"}`);
      pushCandidate(`{"items":[{"name":"${escName}","path":"${ep}"}]}`);
    }
    let lastMsg = '入库通知失败';
    for (let i = 0; i < bodyCandidates.length; i++) {
      try {
        const bodyStr = bodyCandidates[i];
        const authx = await genFnGalleryAuthxPostRaw(path, bodyStr);
        const headers = this.buildGalleryFetchHeaders(authx, cookie);
        headers['Content-Type'] = 'application/json';
        const raw = await this.rawRequest(
          `${activeBase}${path}`,
          http.RequestMethod.POST,
          headers,
          bodyStr,
          timeoutMs,
          CertPolicy.isTrusted(activeBase)
        );
        if (raw.code < 200 || raw.code >= 300) {
          lastMsg = `notice HTTP ${raw.code}`;
          continue;
        }
        let parsed: Record<string, string | number | Object | undefined>;
        try {
          parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
        } catch (_e) {
          lastMsg = 'notice 响应解析失败';
          continue;
        }
        if (!FnHttpClient.galleryEnvelopeBizOk(parsed)) {
          const em = FnHttpClient.envelopeErrorLine(parsed);
          lastMsg = em.length > 0 ? em : 'notice 业务失败';
          continue;
        }
        // 对齐 upload.worker：code==0 但 list[0].error 非空也算失败。
        const dataObj = parsed['data'];
        if (dataObj !== undefined && dataObj !== null && typeof dataObj === 'object' && !Array.isArray(dataObj)) {
          const dataRec = dataObj as Record<string, string | number | Object | undefined>;
          const listObj = dataRec['list'];
          if (Array.isArray(listObj) && listObj.length > 0) {
            const typedArr = listObj as Array<Object>;
            const first = typedArr[0];
            if (first !== undefined && first !== null && typeof first === 'object' && !Array.isArray(first)) {
              const fr = first as Record<string, string | number | Object | undefined>;
              const errTxtRaw = fr['error'];
              const errTxt = errTxtRaw !== undefined && errTxtRaw !== null ? String(errTxtRaw).trim() : '';
              const errCodeRaw = fr['errorCode'];
              const errCode = errCodeRaw !== undefined && Number.isFinite(Number(errCodeRaw))
                ? Math.floor(Number(errCodeRaw))
                : 0;
              if (errTxt.length > 0 || errCode !== 0) {
                lastMsg = errTxt.length > 0 ? errTxt : `notice errorCode=${errCode}`;
                continue;
              }
            }
          }
        }
        const okRes: UploadNoticeResult = { ok: true, message: '' };
        return okRes;
      } catch (_e) {}
    }
    const failRes: UploadNoticeResult = { ok: false, message: lastMsg };
    return failRes;
  }

  /**
   * 上传后核验：某些后端返回口径不稳定（notice 失败但实际已入库），
   * 这里短轮询当天列表，按文件名词干/后缀/大小匹配，命中即视为成功。
   */
  private async verifyUploadedAppeared(
    fileName: string,
    payloadBytes: number
  ): Promise<boolean> {
    const ext = lowerExtFromName(fileName);
    const stem = nameStem(fileName).toLowerCase();
    const attempts = 3;
    const checkedDays: Record<string, boolean> = {};
    const ranges: LocalDayRange[] = [];
    // 兜底：无论 timeline 是否可用，都至少检查“今天”。
    const today = localDayRangeNow();
    ranges.push(today);
    checkedDays[today.start] = true;
    // 先取官方 timeline 的最新日期分桶，再按桶查 getList。
    // 这样能覆盖“上传成功但归档日期不是当天”的场景，减少误判失败。
    const timelineRes = await this.getGalleryTimeline();
    if (timelineRes.success && timelineRes.data !== undefined) {
      const dayList = timelineRes.data.list;
      if (Array.isArray(dayList) && dayList.length > 0) {
        // 只取最近若干天，避免单次校验请求过多。
        const maxDays = Math.min(dayList.length, 8);
        for (let di = 0; di < maxDays; di++) {
          const cell = dayList[di];
          const y = Number(cell.year);
          const m = Number(cell.month);
          const d = Number(cell.day);
          if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) {
            continue;
          }
          const yy = Math.floor(y);
          const mm = Math.floor(m);
          const dd = Math.floor(d);
          if (yy <= 0 || mm <= 0 || mm > 12 || dd <= 0 || dd > 31) {
            continue;
          }
          const oneRange = localDayRangeByYmd(yy, mm, dd);
          if (checkedDays[oneRange.start]) {
            continue;
          }
          ranges.push(oneRange);
          checkedDays[oneRange.start] = true;
        }
      }
    }
    for (let i = 0; i < attempts; i++) {
      if (i > 0) {
        await FnHttpClient.sleep(800 + i * 700);
      }
      for (let ri = 0; ri < ranges.length; ri++) {
        const range = ranges[ri];
        const one = await this.getGalleryList(range.start, range.end, 60, 0, 'index');
        if (!one.success || one.data === undefined) {
          continue;
        }
        const rawList = one.data.list ?? one.data.items ?? one.data.photos ?? one.data.records;
        if (!Array.isArray(rawList) || rawList.length === 0) {
          continue;
        }
        const typed: GalleryListItem[] = [];
        for (let ti = 0; ti < rawList.length; ti++) {
          const row = rawList[ti];
          if (typeof row === 'object' && row !== null) {
            typed.push(row as GalleryListItem);
          }
        }
        for (let k = 0; k < typed.length; k++) {
          const it = typed[k];
          const rec = it as Record<string, string | number | Object | undefined>;
          const itNameRaw = rec['fileName'] ?? rec['filename'];
          const itName = (itNameRaw !== undefined && itNameRaw !== null ? String(itNameRaw) : '').toLowerCase();
          const itExt = (it.fileType ?? '').toLowerCase();
          const itSizeRaw = rec['fileSize'] ?? rec['filesize'];
          const itSize = Number(itSizeRaw);
          const nameHit = stem.length > 0 && itName.indexOf(stem) >= 0;
          const extHit = ext.length === 0 || itExt === ext;
          const sizeHit = Number.isFinite(itSize) && Math.abs(Math.floor(itSize) - payloadBytes) <= 8;
          if ((nameHit && extHit) || (extHit && sizeHit)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /**
   * 通过 photo picker 选择的 URI 上传单文件：
   * 1) POST /upload 上传二进制；
   * 2) POST /p/api/v1/photo/upload/notice 通知服务端入库（失败时尝试 restore 兜底）。
   *
   * 兼容策略：
   * - 上传前尝试请求 /p/api/v2/photo/upload/path，拿到路径提示用于 notice；
   * - /upload 若返回 JSON 外壳 code!=0，则按失败处理（不再仅看 HTTP 200）；
   * - notice / restore 都失败时，明确返回失败，避免“假成功”。
   *
   * @param albumUploadDirHint 设置里「相册父目录」fv_xxx 等：当 upload/path 接口无返回时用作 trim-path 目录回退
   */
  async uploadPhotoByUri(
    uri: string,
    timeoutMs: number = 120000,
    albumUploadDirHint?: string
  ): Promise<FnClientResult<Object>> {
    const oneUri = uri.trim();
    if (oneUri.length === 0) {
      hilog.warn(DOMAIN, TAG, '[upload] abort empty uri');
      return { success: false, message: '文件 URI 为空' };
    }
    hilog.warn(DOMAIN, TAG, '[upload] enter uriLen=%{public}d timeoutMs=%{public}d', oneUri.length, timeoutMs);
    const filePack = FnHttpClient.readUploadFileAndMtime(oneUri);
    if (filePack === undefined || filePack.buffer.byteLength <= 0) {
      hilog.warn(DOMAIN, TAG, '[upload] abort read file failed uriLen=%{public}d', oneUri.length);
      return { success: false, message: '读取待上传文件失败' };
    }
    const payload = filePack.buffer;
    const fileName = FnHttpClient.fileNameFromUri(oneUri);
    let pathHintBeforeUpload = await this.requestUploadPathHint(fileName, Math.min(15000, timeoutMs));
    if (pathHintBeforeUpload.length === 0 && albumUploadDirHint !== undefined) {
      const d = albumUploadDirHint.trim();
      if (d.length > 0) {
        pathHintBeforeUpload = d;
      }
    }
    const hintedFullPath = pathHintBeforeUpload.length > 0 ? trimJoinPath(pathHintBeforeUpload, fileName) : '';
    const uploadPath = '/upload';
    const webHttpsBase = fnWebViewBaseUrl(this.baseUrl);
    let sessionNorm = this.baseUrl.trim();
    if (sessionNorm.length > 1 && sessionNorm.endsWith('/')) {
      sessionNorm = sessionNorm.substring(0, sessionNorm.length - 1);
    }
    /** 部分 NAS 上 /upload 只接受 http:5666 或只接受 https:5667；Origin/Cookie 合并须与 POST 的 origin 一致 */
    const uploadOrigins: string[] = [webHttpsBase];
    if (sessionNorm.length > 0 && sessionNorm !== webHttpsBase) {
      uploadOrigins.push(sessionNorm);
    }
    const req = http.createHttp();
    this.registerPendingRequest(req);
    let uploadRespText = '';
    /** 与 Trim-Mtim 头一致，并传给 notice；使用文件 mtime（秒），对齐 Python os.path.getmtime */
    let trimMtim = String(filePack.mtimeSec);
    try {
      this.primeWebCookiesForPStack(webHttpsBase);
      const multipart = buildMultipartUploadBody(fileName, payload);
      const encodedTrimPath = hintedFullPath.length > 0 ? encodeTrimPath(hintedFullPath) : '';

      // Trim-Sign = base64(HMAC-SHA256(secret, Trim-Path))；优先正确签名，空签名仅作兜底
      const signCandidates = await buildTrimSignCandidates(encodedTrimPath, this.token, this.wsSignKeyB64);
      const maxSignTries = 5;
      const allSigns: string[] = [];
      for (let i = 0; i < signCandidates.length && allSigns.length < maxSignTries; i++) {
        const c = signCandidates[i];
        if (c.length > 0 && allSigns.indexOf(c) < 0) {
          allSigns.push(c);
        }
      }
      if (allSigns.length < maxSignTries && allSigns.indexOf('') < 0) {
        allSigns.push('');
      }

      let uploadOk = false;
      let lastHttpCode = 0;
      let lastDetail = '';
      let softUploadAccepted = false;
      let lastCookieForLog = '';
      let lastUploadUrl = '';
      outerUpload:
      for (let bi = 0; bi < uploadOrigins.length; bi++) {
        const originBase = uploadOrigins[bi];
        const uploadUrl = `${originBase}${uploadPath}`;
        const uploadCookie = stripUploadForbiddenCookieKeys(
          mergeGalleryWebCookieIntoNativeHeader(
            buildUploadCookieHeader(this.token, this.longToken),
            originBase
          )
        );
        const uploadReferer = `${originBase}${FN_PHOTO_H5_ALBUM_PAGE}`;
        lastCookieForLog = uploadCookie;
        lastUploadUrl = uploadUrl;
        hilog.warn(
          DOMAIN,
          TAG,
          '[upload] start origin=%{public}s url=%{public}s file=%{public}s bytes=%{public}d pathHint=%{public}s cookieKeys=%{public}s referer=%{public}s',
          originBase,
          uploadUrl,
          fileName,
          payload.byteLength,
          pathHintBeforeUpload.length > 0 ? pathHintBeforeUpload : '(none)',
          cookieKeysSummary(uploadCookie),
          uploadReferer
        );
        for (let si = 0; si < allSigns.length; si++) {
          const oneSign = allSigns[si];
          const headers: Record<string, string> = {
            'Cookie': uploadCookie,
            'User-Agent': fnWebDefaultUserAgent(),
            'Origin': originBase,
            'Referer': uploadReferer,
            'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
            'Accept-Encoding': 'identity',
            'Content-Type': multipart.contentType,
            'Accept': 'application/json, text/plain, */*',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'same-origin',
            // 与浏览器 DevTools 展示一致：Title-Case（虽 HTTP 规范不区分大小写，部分网关实现较严）
            'Trim-Flags': '1',
            'Trim-Overwrite': '1',
            'Trim-Mtim': trimMtim
          };
          if (this.token.length > 0) {
            headers['AccessToken'] = this.token;
          }
          if (encodedTrimPath.length > 0) {
            headers['Trim-Path'] = encodedTrimPath;
          }
          if (this.token.length > 0) {
            headers['Trim-Token'] = this.token;
          }
          if (oneSign.length > 0) {
            headers['Trim-Sign'] = oneSign;
          }
          const opt: http.HttpRequestOptions = {
            method: http.RequestMethod.POST,
            header: headers,
            expectDataType: http.HttpDataType.STRING,
            connectTimeout: timeoutMs,
            readTimeout: timeoutMs,
            extraData: multipart.body
          };
          if (CertPolicy.isTrusted(this.baseUrl) || CertPolicy.isTrusted(originBase)) {
            opt.remoteValidation = 'skip';
          }
          const rawResp = await req.request(uploadUrl, opt);
          const code = Number(rawResp.responseCode);
          lastHttpCode = code;
          uploadRespText = typeof rawResp.result === 'string' ? rawResp.result : JSON.stringify(rawResp.result);
          if (!(code >= 200 && code < 300)) {
            if (uploadRespText.length > 0) {
              try {
                const parsed = JSON.parse(uploadRespText) as Record<string, string | number | Object | undefined>;
                const em = FnHttpClient.envelopeErrorLine(parsed);
                lastDetail = em.length > 0 ? em : '';
              } catch (_e) {
                lastDetail = uploadRespText.length > 120 ? `${uploadRespText.substring(0, 120)}...` : uploadRespText;
              }
            }
            continue;
          }
          if (uploadRespText.length > 0) {
            try {
              const parsed = JSON.parse(uploadRespText) as Record<string, string | number | Object | undefined>;
              if (!FnHttpClient.galleryEnvelopeBizOk(parsed)) {
                const em = FnHttpClient.envelopeErrorLine(parsed);
                lastDetail = em.length > 0 ? em : '上传失败';
                const low = lastDetail.toLowerCase();
                if (low.indexOf('update failed') >= 0) {
                  softUploadAccepted = true;
                }
                continue;
              }
            } catch (_e) {
            }
          }
          uploadOk = true;
          break outerUpload;
        }
      }
      if (!uploadOk) {
        if (softUploadAccepted && lastHttpCode >= 200 && lastHttpCode < 300) {
          // 走后续 notice/verify 流程，由入库侧再确认最终结果。
        } else {
          const bodyPrev =
            uploadRespText.length > 256 ? `${uploadRespText.substring(0, 256)}…` : uploadRespText;
          hilog.warn(
            DOMAIN,
            TAG,
            '[upload] POST /upload failed url=%{public}s http=%{public}d detail=%{public}s trimPathLen=%{public}d sign×origins=%{public}d×%{public}d cookie(redacted)=%{public}s body=%{public}s',
            lastUploadUrl.length > 0 ? lastUploadUrl : '(none)',
            lastHttpCode,
            lastDetail.length > 0 ? lastDetail : '(none)',
            encodedTrimPath.length,
            allSigns.length,
            uploadOrigins.length,
            redactCookieHeaderForLog(lastCookieForLog),
            bodyPrev.length > 0 ? bodyPrev : '(empty)'
          );
          return {
            success: false,
            message: lastDetail.length > 0 ? `上传失败 HTTP ${lastHttpCode}：${lastDetail}` : `上传失败 HTTP ${lastHttpCode}`
          };
        }
      }
    } catch (e) {
      const em = String(e);
      hilog.warn(DOMAIN, TAG, '[upload] exception %{public}s', em.length > 0 ? em : 'unknown');
      return { success: false, message: em.length > 0 ? em : '上传请求异常' };
    } finally {
      this.unregisterPendingRequest(req);
      try {
        req.destroy();
      } catch (_e) {}
    }
    const noticeTimeout = Math.min(30000, timeoutMs);
    const pathHintFromUpload = FnHttpClient.firstUploadPathFromResponse(uploadRespText);
    const noticePathHints: string[] = [];
    if (pathHintBeforeUpload.length > 0) {
      noticePathHints.push(pathHintBeforeUpload);
    }
    if (hintedFullPath.length > 0 && noticePathHints.indexOf(hintedFullPath) < 0) {
      noticePathHints.push(hintedFullPath);
    }
    if (pathHintFromUpload.length > 0 && noticePathHints.indexOf(pathHintFromUpload) < 0) {
      noticePathHints.push(pathHintFromUpload);
    }
    const noticeRes = await this.notifyPhotoUploaded(
      fileName,
      oneUri,
      noticeTimeout,
      noticePathHints,
      trimMtim,
      hintedFullPath
    );
    let noticed = noticeRes.ok;
    let failReason = noticeRes.message;
    if (!noticed) {
      // 上传成功但 notice 失败时，尝试用上传响应里的 photoId 做 restore 兼容兜底。
      const uploadPhotoId = FnHttpClient.firstUploadPhotoIdFromResponse(uploadRespText);
      if (uploadPhotoId.length > 0) {
        noticed = await this.restoreUploadedPhoto(uploadPhotoId, noticeTimeout);
        if (!noticed && failReason.length === 0) {
          failReason = 'restore 补偿失败';
        }
      } else if (failReason.length === 0) {
        failReason = 'notice 失败且未返回 photoId';
      }
    }
    if (!noticed) {
      const verified = await this.verifyUploadedAppeared(fileName, payload.byteLength);
      if (verified) {
        return { success: true, message: '上传成功（已入库）' };
      }
      const em = failReason.length > 0 ? `上传完成但入库通知失败：${failReason}` : '上传完成但入库通知失败';
      const hintsStr =
        noticePathHints.length > 0 ? noticePathHints.join(' | ') : '(none)';
      hilog.warn(
        DOMAIN,
        TAG,
        '[upload] notice/verify failed reason=%{public}s pathHints=%{public}s uploadBodyPreview=%{public}s',
        failReason.length > 0 ? failReason : '(empty)',
        hintsStr,
        uploadRespText.length > 200 ? `${uploadRespText.substring(0, 200)}…` : uploadRespText
      );
      return { success: false, message: em };
    }
    return { success: true };
  }
}
