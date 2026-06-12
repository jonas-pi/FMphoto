import { util } from '@kit.ArkTS';
import { generateRandomDigits, sha256DigestSafe } from '../AuthxSigner';
import { FN_PHOTO_API_PREFIX } from '../FnPhotoRoutes';
import { FnJsonValue } from '../../model/FnApiTypes';

/**
 * Shared constants, routes and pure helpers used by FnHttpClient capability modules.
 */
export const DOMAIN = 0xFF00;
export const TAG = 'FnHttp';

/** 图库 GET 空 query 参数（避免未类型化的 `{}` 字面量） */
export const GALLERY_QUERY_EMPTY: Record<string, string | number | boolean> = {};

/** 上传前一次性读出文件内容与本地修改时间（秒），对齐 Python `os.path.getmtime` + Trim-Mtim */
export interface UploadFileReadResult {
  buffer: ArrayBuffer;
  mtimeSec: number;
}

export const DEFAULT_TIMEOUT = 10000;
export const MAX_REDIRECTS = 8;

/** 飞牛 OpenAPI 统一前缀 */
export const FN_OPENAPI_PREFIX = '/v/api/v1';

/**
 * 与 `FnWebCookies.buildFnWebCookieHeader` 字段顺序一致（long-token 在 Trim-MC 之前），避免与内置 Web 会话不一致。
 */
export const GALLERY_TIMELINE_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/gallery/timeline`;
export const GALLERY_TIMELINE_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/gallery/timeline`,
  '/api/v1/gallery/timeline'
];
/** getList 实际 URL 可为 /api/v1/...，但 authx 签名 path 恒为 /p/api/v1/gallery/getList */
export const GALLERY_GETLIST_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/gallery/getList`;
export const GALLERY_GETLIST_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/gallery/getList`,
  '/api/v1/gallery/getList'
];
/** 最近添加：时间轴与列表接口（抓包：/p/api/v1/explore/recent_timeline, /p/api/v1/explore/recent_photos） */
export const RECENT_TIMELINE_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/explore/recent_timeline`;
export const RECENT_TIMELINE_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/explore/recent_timeline`,
  '/api/v1/explore/recent_timeline'
];
export const RECENT_PHOTOS_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/explore/recent_photos`;
export const RECENT_PHOTOS_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/explore/recent_photos`,
  '/api/v1/explore/recent_photos'
];
/** getOne 详情接口：与 getList 同签名体系 */
export const GALLERY_GETONE_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/gallery/getOne`;
export const GALLERY_GETONE_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/gallery/getOne`,
  '/api/v1/gallery/getOne'
];
/** folder_view 文件列表（按文件夹路径取媒体） */
export const GALLERY_FOLDER_FILELIST_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/folder_view/getFileList`;
export const GALLERY_FOLDER_FILELIST_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/folder_view/getFileList`,
  '/api/v1/folder_view/getFileList'
];
/** 回收站列表：签名 path 与 gallery 系列一致为 /p/api/v1/... */
export const RECYCLE_BIN_LIST_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/recycle-bin/list`;
/** 照片中人物识别：GET /p/api/v1/ai-person/personInPhoto?id=xxx */
export const PERSON_IN_PHOTO_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/ai-person/personInPhoto`;
export const PERSON_IN_PHOTO_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/ai-person/personInPhoto`,
  '/api/v1/ai-person/personInPhoto'
];
/** 地图：官方 Web 端 mapApi / map/photoList 接口 */
export const MAP_PREVIEW_CENTER_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/map/preview/initCenter`;
export const MAP_PREVIEW_CENTER_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/map/preview/initCenter`,
  '/api/v1/map/preview/initCenter'
];
export const MAP_PREVIEW_BOUNDARY_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/map/preview/mapBoundary`;
export const MAP_PREVIEW_BOUNDARY_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/map/preview/mapBoundary`,
  '/api/v1/map/preview/mapBoundary'
];
export const MAP_PREVIEW_ALL_POINT_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/map/previewAllPoint`;
export const MAP_PREVIEW_ALL_POINT_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/map/previewAllPoint`,
  '/api/v1/map/previewAllPoint'
];
export const MAP_TIMELINE_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/map/timeLine`;
export const MAP_TIMELINE_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/map/timeLine`,
  '/api/v1/map/timeLine'
];
export const MAP_PHOTO_LIST_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/map/photoList`;
export const MAP_PHOTO_LIST_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/map/photoList`,
  '/api/v1/map/photoList'
];
export const MAP_GET_IDS_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/map/getIds`;
export const MAP_GET_IDS_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/map/getIds`,
  '/api/v1/map/getIds'
];
/** 地理位置列表：官方 Web 端 /geo 使用 exploreApi.getGeos */
export const EXPLORE_GEOS_SIGN_PATH = `${FN_PHOTO_API_PREFIX}/explore/geos`;
export const EXPLORE_GEOS_PATH_CANDIDATES: string[] = [
  `${FN_PHOTO_API_PREFIX}/explore/geos`,
  '/api/v1/explore/geos'
];

/** 疑似证书类错误码（NetStack） */
export const CERT_CODES: number[] = [2300060, 2300058, 2300059, 2300077];

/** 重定向解析结果 */
export interface ResolvedLocation {
  newBase: string;
  newPath: string;
}

/** 底层 HTTP 原始响应 */
export interface RawHttpResult {
  code: number;
  headers: object;
  body: string;
}

/** 网络异常形态（catch 用） */
export interface NetErrorLike {
  code?: number;
  message?: string;
}

export interface GalleryAssetSignParts {
  signPath: string;
  queryParams: Record<string, string | number | boolean>;
}

export interface LocalDayRange {
  start: string;
  end: string;
}

export interface AssetBufferCacheEntry {
  timeMs: number;
  data: ArrayBuffer;
}

export interface UploadNoticeResult {
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

export class MultipartBodyData {
  contentType: string = '';
  body: ArrayBuffer = new ArrayBuffer(0);
}

/** 从响应头解析 Set-Cookie 中的 fnos-long-token（与浏览器首页 Cookie 一致） */
export function parseFnosLongTokenFromHeaders(headers: object): string | undefined {
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

export function getHeader(headers: object, key: string): string | undefined {
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

export function mergePostBody(data: Record<string, FnJsonValue> | undefined): Record<string, FnJsonValue> {
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

export function escapeJsonString(input: string): string {
  return input.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

export function decodeUriPartSafely(input: string): string {
  try {
    return decodeURIComponent(input);
  } catch (_e) {
    return input;
  }
}

export function trimJoinPath(dirPath: string, fileName: string): string {
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
export function lastUnixPathSegment(fullPath: string): string {
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
export function encodeTrimPath(path: string): string {
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

export function pad2(v: number): string {
  return v < 10 ? `0${v}` : String(v);
}

export function localDayRangeNow(): LocalDayRange {
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
export function localDayRangeByYmd(year: number, month: number, day: number): LocalDayRange {
  const start = `${year}:${pad2(month)}:${pad2(day)} 00:00:00`;
  const end = `${year}:${pad2(month)}:${pad2(day)} 23:59:59`;
  const out: LocalDayRange = { start: start, end: end };
  return out;
}

export function lowerExtFromName(fileName: string): string {
  const n = fileName.trim();
  const dot = n.lastIndexOf('.');
  if (dot < 0 || dot >= n.length - 1) {
    return '';
  }
  return n.substring(dot + 1).toLowerCase();
}

export function nameStem(fileName: string): string {
  const n = fileName.trim();
  const dot = n.lastIndexOf('.');
  return dot > 0 ? n.substring(0, dot) : n;
}

export function utf8EncodeLocal(str: string): Uint8Array {
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

export function escapeMultipartFileName(fileName: string): string {
  return fileName.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

export function uint8ArrayToBase64Local(data: Uint8Array): string {
  const helper = new util.Base64Helper();
  return helper.encodeToStringSync(data);
}

export function base64ToUint8Local(b64: string): Uint8Array {
  const helper = new util.Base64Helper();
  return helper.decodeSync(b64);
}

/** 与 AuthxSigner：鸿蒙 HCF 对 SHA256.update 偶发抛「update failed」，统一走安全摘要 */
async function sha256DigestLocal(data: Uint8Array): Promise<Uint8Array> {
  return sha256DigestSafe(data);
}

export function concatUint8Local(a: Uint8Array, b: Uint8Array): Uint8Array {
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
export async function buildTrimSignCandidates(
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
export function mimeFromExt(ext: string): string {
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
export function buildMultipartUploadBody(fileName: string, payload: ArrayBuffer): MultipartBodyData {
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
export function redactCookieHeaderForLog(cookie: string): string {
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
export function cookieKeysSummary(cookie: string): string {
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

export function isRedirectCode(code: number): boolean {
  return code === 301 || code === 302 || code === 307 || code === 308;
}

/** 解析出协议+主机（不含路径），不含末尾 / */
export function splitOrigin(full: string): string {
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
export function resolveLocation(baseUrl: string, pathOrUrl: string): ResolvedLocation {
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
