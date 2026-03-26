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
import { CertPolicy } from './CertPolicy';
import { genFnAuthx, generateRandomDigits } from './AuthxSigner';
import { buildGallerySortedQuery, FnGalleryGetSignSpec, genFnGalleryAuthxGet, genFnGalleryAuthxPost, genFnGalleryAuthxPostRaw } from './FnGalleryAuthx';
import { FN_PHOTO_API_PREFIX, fnPhotoLongTokenProbePaths } from './FnPhotoRoutes';
import { fnWebDefaultUserAgent, mergeGalleryWebCookieIntoNativeHeader } from './FnWebCookies';
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
  SmartCategoryData,
  AiPersonData,
  AiPersonDetailData,
  SearchResultsData,
  UserInfoData
} from '../model/FnApiTypes';

const DOMAIN = 0xFF00;
const TAG = 'FnHttp';

/** 图库 GET 空 query 参数（避免未类型化的 `{}` 字面量） */
const GALLERY_QUERY_EMPTY: Record<string, string | number | boolean> = {};

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

interface AssetBufferCacheEntry {
  timeMs: number;
  data: ArrayBuffer;
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
  /** 当前仍在进行的 HTTP 请求（用于页面关闭时主动释放连接） */
  private pendingRequests: http.HttpRequest[] = [];
  /** 资源下载去重：同 URL 并发仅发起一次请求 */
  private static readonly inflightAssetReq: Map<string, Promise<ArrayBuffer | undefined>> = new Map();
  /** 资源短时缓存：减少连续滚动/返回时重复下载 */
  private static readonly assetBufferCache: Map<string, AssetBufferCacheEntry> = new Map();
  private static readonly ASSET_CACHE_TTL_MS: number = 15000;
  private static readonly ASSET_CACHE_MAX: number = 120;

  constructor(baseUrl: string, token: string = '', longToken: string = '') {
    this.baseUrl = baseUrl;
    this.token = token;
    this.longToken = longToken;
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
   * 图库 XHR：与 Py 一致项 — Cookie、authx、AccessToken、Referer…/p/、Accept json、Sec-Fetch-*。
   * UA/Client Hint 与 **本应用 WebView**（`fnWebDefaultUserAgent`）一致：鸿蒙上若冒充 Windows 桌面，部分 NAS 会返回模糊业务错误（如 update failed）。
   */
  private buildGalleryFetchHeaders(authxVal: string, cookieHeader: string): Record<string, string> {
    const h: Record<string, string> = {
      'Cookie': cookieHeader,
      'User-Agent': fnWebDefaultUserAgent(),
      'Accept': 'application/json',
      'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
      'Accept-Encoding': 'identity',
      'Referer': this.galleryPhotoReferer(),
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'same-origin',
      'Sec-Ch-Ua': '"Chromium";v="120", "Google Chrome";v="120", "Not_A Brand";v="24"',
      'Sec-Ch-Ua-Mobile': '?1',
      'Sec-Ch-Ua-Platform': '"Android"',
      'authx': authxVal
    };
    /** 与 Py `extra_headers` 一致：仅 AccessToken，勿加 Authorization（易与 OpenAPI 头混淆被 NAS 拒） */
    if (this.token.length > 0) {
      h['AccessToken'] = this.token;
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
      if (err.length > 0 && (data === undefined || data === null)) {
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
   * 媒体分类：GET /p/api/v1/media_category/list
   * 使用与图库一致的 Cookie + authx 认证。
   */
  async getMediaCategoryList(timeoutMs: number = 20000): Promise<FnClientResult<MediaCategoryData>> {
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const path = `${FN_PHOTO_API_PREFIX}/media_category/list`;
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
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
      if (raw.code < 200 || raw.code >= 300) {
        return { success: false, message: `HTTP ${raw.code}` };
      }
      let parsed: Record<string, string | number | Object | undefined>;
      try {
        parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
      } catch (_e) {
        return { success: false, message: '媒体分类结果解析失败' };
      }
      if (!FnHttpClient.galleryEnvelopeBizOk(parsed)) {
        const code = FnHttpClient.envelopeCodeNum(parsed);
        const errLine = FnHttpClient.envelopeErrorLine(parsed);
        const show = errLine.length > 0 ? `: ${errLine}` : '';
        return { success: false, message: `媒体分类请求失败 (${code})${show}` };
      }
      // 诊断：打印原始响应体前 600 字符，便于排查字段名
      hilog.info(DOMAIN, TAG, 'mediaCat body(600): %{public}s', raw.body.substring(0, 600));
      const normList = FnHttpClient.mediaCategoryItemsFromData(parsed['data'] as Object | undefined);
      hilog.info(DOMAIN, TAG, 'mediaCat normCount=%{public}d', normList.length);
      if (normList.length > 0) {
        hilog.info(DOMAIN, TAG, 'mediaCat[0] name=%{public}s id=%{public}s count=%{public}d cover=%{public}s',
          normList[0].name ?? '(none)', normList[0].id ?? '(none)',
          normList[0].count ?? -1, normList[0].cover ?? '(none)');
      }
      const norm: MediaCategoryData = { list: normList };
      return { success: true, data: norm };
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
   * 将原始 JSON 对象规范化为 MediaCategoryItem。
   *
   * 依据 fnOS Web 前端源码（media_category.lazy-DstI0gUv.js）：
   *   - `category`（整数 1-5）是类型标识符，**名称由前端硬编码，JSON 中无 name 字段**
   *   - `count` 为该分类的媒体数量
   *   - `id` + `uuid` 用于拼接封面缩略图 URL：/p/api/v1/stream/p/t/{id}/m/{uuid}
   *   - 点击分类跳转 /search?file_type={searchValue}（photo/video/gif/raw/live_photo）
   */
  private static normalizeCategoryItem(raw: Record<string, Object | undefined>): MediaCategoryItem {
    const out: MediaCategoryItem = {};

    // ── category 类型编号 → 名称 + searchValue（key 字段） ─────────────────
    const catRaw = raw['category'];
    const catNum = (typeof catRaw === 'number') ? catRaw as number :
      (typeof catRaw === 'string' ? parseInt(catRaw as string, 10) : NaN);
    if (catNum === 1) { out.name = '照片'; out.key = 'photo'; }
    else if (catNum === 2) { out.name = '视频'; out.key = 'video'; }
    else if (catNum === 3) { out.name = '实况 / 动态照片'; out.key = 'live_photo'; }
    else if (catNum === 4) { out.name = '动图'; out.key = 'gif'; }
    else if (catNum === 5) { out.name = 'RAW'; out.key = 'raw'; }
    out.id = Number.isFinite(catNum) ? String(catNum) : undefined;

    // ── 数量（count 字段） ──────────────────────────────────────────────────
    const countRaw = raw['count'];
    if (countRaw !== undefined) {
      const n = Number(countRaw);
      if (Number.isFinite(n) && n >= 0) {
        out.count = Math.floor(n);
      }
    }

    // ── 封面：由 id（照片 ID）+ uuid（照片 UUID）拼成缩略图路径 ──────────────
    // 格式：/p/api/v1/stream/p/t/{photo_id}/m/{photo_uuid}
    const photoId = raw['id'];
    const photoUuid = raw['uuid'];
    if (photoId !== undefined && photoId !== null &&
        photoUuid !== undefined && photoUuid !== null) {
      const idStr = String(photoId);
      const uuidStr = String(photoUuid);
      if (idStr.length > 0 && uuidStr.length > 0 &&
          idStr !== 'null' && uuidStr !== 'null') {
        out.cover = `${FN_PHOTO_API_PREFIX}/stream/p/t/${idStr}/m/${uuidStr}`;
      }
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
    // 尝试所有常见键名
    const KEYS: string[] = [
      'list', 'items', 'photos', 'records',
      'results', 'photoList', 'photo_list',
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
   * 分类空列表时的兜底查询：POST /p/api/v1/search/results
   * 按 id/key/name 多种字段顺序尝试，适配不同版本。
   */
  async searchResultsByCategory(item: MediaCategoryItem, timeoutMs: number = 20000): Promise<FnClientResult<GalleryListItem[]>> {
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const path = `${FN_PHOTO_API_PREFIX}/search/results`;
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      // keyVal 存放 fnOS 的 file_type 值（photo/video/gif/raw/live_photo）
      // idVal  存放 category 数字（1-5）
      const keyVal = item.key !== undefined ? item.key : '';
      const idVal = item.id !== undefined ? String(item.id) : '';
      const nameVal = item.name ?? item.title ?? item.label ?? '';
      // ── 首选：Web 端真实格式：filters 数组 + keyword="" ─────────────────────
      // 完整格式：{"keyword":"","filters":[{"filterName":"file_type","filterValue":"photo"}],"antiFilters":[]}
      if (keyVal.length > 0) {
        const filterBodyStr =
          `{"keyword":"","filters":[{"filterName":"file_type","filterValue":"${keyVal}"}],"antiFilters":[]}`;
        hilog.info(DOMAIN, TAG, 'catSearch filters body: %{public}s', filterBodyStr);
        const authxFilters = await genFnGalleryAuthxPostRaw(path, filterBodyStr);
        const headersFilters = this.buildGalleryFetchHeaders(authxFilters, cookie);
        headersFilters['Content-Type'] = 'application/json';
        const rawFilters = await this.rawRequest(
          `${activeBase}${path}`,
          http.RequestMethod.POST,
          headersFilters,
          filterBodyStr,
          timeoutMs,
          CertPolicy.isTrusted(activeBase)
        );
        hilog.info(DOMAIN, TAG, 'catSearch filters httpCode=%{public}d body500: %{public}s',
          rawFilters.code, rawFilters.body.substring(0, 500));
        if (rawFilters.code >= 200 && rawFilters.code < 300) {
          let parsedFilters: Record<string, string | number | Object | undefined> | undefined;
          try {
            parsedFilters = JSON.parse(rawFilters.body) as Record<string, string | number | Object | undefined>;
          } catch (_e) {
            parsedFilters = undefined;
          }
          if (parsedFilters !== undefined && FnHttpClient.galleryEnvelopeBizOk(parsedFilters)) {
            const arrFilters = FnHttpClient.searchResultItemsFromData(parsedFilters['data'] as Object | undefined);
            hilog.info(DOMAIN, TAG, 'catSearch filters arr.length=%{public}d', arrFilters.length);
            if (arrFilters.length > 0) {
              return { success: true, data: arrFilters };
            }
          }
        }
      }

      // ── 兜底候选列表（旧格式，用于兼容其他版本） ─────────────────────────────
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
        const authx = await genFnGalleryAuthxPost(path, body);
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
        if (!FnHttpClient.galleryEnvelopeBizOk(parsed)) {
          continue;
        }
        const arr = FnHttpClient.searchResultItemsFromData(parsed['data'] as Object | undefined);
        if (arr.length > 0) {
          return { success: true, data: arr };
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
}
