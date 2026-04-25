/**
 * FNOS HTTP client thin shell.
 *
 * Responsibilities here:
 * - hold runtime session fields
 * - keep core request/auth/sign/retry behavior
 * - delegate gallery/upload capabilities to dedicated modules
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CertPolicy } from './CertPolicy';
import { genFnAuthx } from './AuthxSigner';
import { FnGalleryGetSignSpec, genFnGalleryAuthxGet } from './FnGalleryAuthx';
import { fnPhotoLongTokenProbePaths } from './FnPhotoRoutes';
import { fnWebDefaultUserAgent, injectFnWebCookies, mergeGalleryWebCookieIntoNativeHeader } from './FnWebCookies';
import { fnWebViewBaseUrl } from './ServerUrl';
import { buildFnApiCookieHeader } from './fnHttpClient/FnHttpClientCookie';
import { FnHttpClientGalleryOps } from './fnHttpClient/FnHttpClientGalleryOps';
import { FnHttpClientUploadOps } from './fnHttpClient/FnHttpClientUploadOps';
import {
  CERT_CODES,
  DEFAULT_TIMEOUT,
  DOMAIN,
  FN_OPENAPI_PREFIX,
  MAX_REDIRECTS,
  NetErrorLike,
  RawHttpResult,
  TAG,
  getHeader,
  isRedirectCode,
  mergePostBody,
  parseFnosLongTokenFromHeaders,
  resolveLocation,
  splitOrigin
} from './fnHttpClient/FnHttpClientCommon';
import { FnHttpClientGalleryHost, FnHttpClientUploadHost, VideoDecodePlayInfo, VideoDecodePlayRequest } from './fnHttpClient/FnHttpClientTypes';
import {
  AiPersonData,
  AiPersonDetailData,
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
  MediaCategoryData,
  MediaCategoryItem,
  PersonInPhotoData,
  RecycleBinListData,
  SmartCategoryData,
  UserInfoData
} from '../model/FnApiTypes';

export { VideoDecodePlayInfo, VideoDecodePlayRequest } from './fnHttpClient/FnHttpClientTypes';

class FnHttpClientGalleryHostBridge implements FnHttpClientGalleryHost {
  private readonly getBaseUrlFn: () => string;
  private readonly getTokenFn: () => string;
  private readonly getLongTokenFn: () => string;
  private readonly registerPendingRequestFn: (req: http.HttpRequest) => void;
  private readonly unregisterPendingRequestFn: (req: http.HttpRequest) => void;
  private readonly buildGalleryFetchHeadersFn: (authxVal: string, cookieHeader: string) => Record<string, string>;
  private readonly requestGalleryGetJsonFn: (pathCandidates: string[], gallerySign: FnGalleryGetSignSpec, timeoutMs: number, tryTimes: number) => Promise<FnClientResult<Object>>;
  private readonly rawRequestFn: (fullUrl: string, method: http.RequestMethod, header: Record<string, string>, bodyStr: string | undefined, timeoutMs: number, skipRemoteCert: boolean) => Promise<RawHttpResult>;

  constructor(
    getBaseUrlFn: () => string,
    getTokenFn: () => string,
    getLongTokenFn: () => string,
    registerPendingRequestFn: (req: http.HttpRequest) => void,
    unregisterPendingRequestFn: (req: http.HttpRequest) => void,
    buildGalleryFetchHeadersFn: (authxVal: string, cookieHeader: string) => Record<string, string>,
    requestGalleryGetJsonFn: (pathCandidates: string[], gallerySign: FnGalleryGetSignSpec, timeoutMs: number, tryTimes: number) => Promise<FnClientResult<Object>>,
    rawRequestFn: (fullUrl: string, method: http.RequestMethod, header: Record<string, string>, bodyStr: string | undefined, timeoutMs: number, skipRemoteCert: boolean) => Promise<RawHttpResult>
  ) {
    this.getBaseUrlFn = getBaseUrlFn;
    this.getTokenFn = getTokenFn;
    this.getLongTokenFn = getLongTokenFn;
    this.registerPendingRequestFn = registerPendingRequestFn;
    this.unregisterPendingRequestFn = unregisterPendingRequestFn;
    this.buildGalleryFetchHeadersFn = buildGalleryFetchHeadersFn;
    this.requestGalleryGetJsonFn = requestGalleryGetJsonFn;
    this.rawRequestFn = rawRequestFn;
  }

  getBaseUrl(): string {
    return this.getBaseUrlFn();
  }

  getToken(): string {
    return this.getTokenFn();
  }

  getLongToken(): string {
    return this.getLongTokenFn();
  }

  registerPendingRequest(req: http.HttpRequest): void {
    this.registerPendingRequestFn(req);
  }

  unregisterPendingRequest(req: http.HttpRequest): void {
    this.unregisterPendingRequestFn(req);
  }

  buildGalleryFetchHeaders(authxVal: string, cookieHeader: string): Record<string, string> {
    return this.buildGalleryFetchHeadersFn(authxVal, cookieHeader);
  }

  requestGalleryGetJson(pathCandidates: string[], gallerySign: FnGalleryGetSignSpec, timeoutMs: number, tryTimes: number): Promise<FnClientResult<Object>> {
    return this.requestGalleryGetJsonFn(pathCandidates, gallerySign, timeoutMs, tryTimes);
  }

  rawRequest(
    fullUrl: string,
    method: http.RequestMethod,
    header: Record<string, string>,
    bodyStr: string | undefined,
    timeoutMs: number,
    skipRemoteCert: boolean
  ): Promise<RawHttpResult> {
    return this.rawRequestFn(fullUrl, method, header, bodyStr, timeoutMs, skipRemoteCert);
  }
}

class FnHttpClientUploadHostBridge extends FnHttpClientGalleryHostBridge implements FnHttpClientUploadHost {
  private readonly getWsSignKeyB64Fn: () => string;
  private readonly primeWebCookiesForPStackFn: (webHttpsBaseNoSlash: string) => void;
  private readonly getGalleryTimelineFn: (extraParams?: Record<string, string | number | boolean>) => Promise<FnClientResult<GalleryTimelineData>>;
  private readonly getGalleryListFn: (startTime: string, endTime: string, limit: number, offset: number, mode?: string) => Promise<FnClientResult<GalleryGetListData>>;

  constructor(
    getBaseUrlFn: () => string,
    getTokenFn: () => string,
    getLongTokenFn: () => string,
    getWsSignKeyB64Fn: () => string,
    registerPendingRequestFn: (req: http.HttpRequest) => void,
    unregisterPendingRequestFn: (req: http.HttpRequest) => void,
    buildGalleryFetchHeadersFn: (authxVal: string, cookieHeader: string) => Record<string, string>,
    requestGalleryGetJsonFn: (pathCandidates: string[], gallerySign: FnGalleryGetSignSpec, timeoutMs: number, tryTimes: number) => Promise<FnClientResult<Object>>,
    rawRequestFn: (fullUrl: string, method: http.RequestMethod, header: Record<string, string>, bodyStr: string | undefined, timeoutMs: number, skipRemoteCert: boolean) => Promise<RawHttpResult>,
    primeWebCookiesForPStackFn: (webHttpsBaseNoSlash: string) => void,
    getGalleryTimelineFn: (extraParams?: Record<string, string | number | boolean>) => Promise<FnClientResult<GalleryTimelineData>>,
    getGalleryListFn: (startTime: string, endTime: string, limit: number, offset: number, mode?: string) => Promise<FnClientResult<GalleryGetListData>>
  ) {
    super(
      getBaseUrlFn,
      getTokenFn,
      getLongTokenFn,
      registerPendingRequestFn,
      unregisterPendingRequestFn,
      buildGalleryFetchHeadersFn,
      requestGalleryGetJsonFn,
      rawRequestFn
    );
    this.getWsSignKeyB64Fn = getWsSignKeyB64Fn;
    this.primeWebCookiesForPStackFn = primeWebCookiesForPStackFn;
    this.getGalleryTimelineFn = getGalleryTimelineFn;
    this.getGalleryListFn = getGalleryListFn;
  }

  getWsSignKeyB64(): string {
    return this.getWsSignKeyB64Fn();
  }

  primeWebCookiesForPStack(webHttpsBaseNoSlash: string): void {
    this.primeWebCookiesForPStackFn(webHttpsBaseNoSlash);
  }

  getGalleryTimeline(extraParams?: Record<string, string | number | boolean>): Promise<FnClientResult<GalleryTimelineData>> {
    return this.getGalleryTimelineFn(extraParams);
  }

  getGalleryList(startTime: string, endTime: string, limit: number, offset: number, mode?: string): Promise<FnClientResult<GalleryGetListData>> {
    return this.getGalleryListFn(startTime, endTime, limit, offset, mode);
  }
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
  private readonly galleryOps: FnHttpClientGalleryOps;
  private readonly uploadOps: FnHttpClientUploadOps;
  /** 资源下载去重：同 URL 并发仅发起一次请求 */

  constructor(baseUrl: string, token: string = '', longToken: string = '', wsSignKeyB64: string = '') {
    this.baseUrl = baseUrl;
    this.token = token;
    this.longToken = longToken;
    this.wsSignKeyB64 = wsSignKeyB64;
    this.galleryOps = new FnHttpClientGalleryOps(this.asGalleryHost());
    this.uploadOps = new FnHttpClientUploadOps(this.asUploadHost());
  }

  private asGalleryHost(): FnHttpClientGalleryHost {
    const self = this;
    return new FnHttpClientGalleryHostBridge(
      (): string => self.baseUrl,
      (): string => self.token,
      (): string => self.longToken,
      (req: http.HttpRequest): void => self.registerPendingRequest(req),
      (req: http.HttpRequest): void => self.unregisterPendingRequest(req),
      (authxVal: string, cookieHeader: string): Record<string, string> =>
        self.buildGalleryFetchHeaders(authxVal, cookieHeader),
      (pathCandidates: string[], gallerySign: FnGalleryGetSignSpec, timeoutMs: number, tryTimes: number): Promise<FnClientResult<Object>> =>
        self.requestGalleryGetJson<Object>(pathCandidates, gallerySign, timeoutMs, tryTimes),
      (fullUrl: string, method: http.RequestMethod, header: Record<string, string>, bodyStr: string | undefined, timeoutMs: number, skipRemoteCert: boolean): Promise<RawHttpResult> =>
        self.rawRequest(fullUrl, method, header, bodyStr, timeoutMs, skipRemoteCert)
    );
  }

  private asUploadHost(): FnHttpClientUploadHost {
    const self = this;
    return new FnHttpClientUploadHostBridge(
      (): string => self.baseUrl,
      (): string => self.token,
      (): string => self.longToken,
      (): string => self.wsSignKeyB64,
      (req: http.HttpRequest): void => self.registerPendingRequest(req),
      (req: http.HttpRequest): void => self.unregisterPendingRequest(req),
      (authxVal: string, cookieHeader: string): Record<string, string> =>
        self.buildGalleryFetchHeaders(authxVal, cookieHeader),
      (pathCandidates: string[], gallerySign: FnGalleryGetSignSpec, timeoutMs: number, tryTimes: number): Promise<FnClientResult<Object>> =>
        self.requestGalleryGetJson<Object>(pathCandidates, gallerySign, timeoutMs, tryTimes),
      (fullUrl: string, method: http.RequestMethod, header: Record<string, string>, bodyStr: string | undefined, timeoutMs: number, skipRemoteCert: boolean): Promise<RawHttpResult> =>
        self.rawRequest(fullUrl, method, header, bodyStr, timeoutMs, skipRemoteCert),
      (webHttpsBaseNoSlash: string): void => self.primeWebCookiesForPStack(webHttpsBaseNoSlash),
      (extraParams?: Record<string, string | number | boolean>): Promise<FnClientResult<GalleryTimelineData>> =>
        self.galleryOps.getGalleryTimeline(extraParams),
      (startTime: string, endTime: string, limit: number, offset: number, mode: string = 'index'): Promise<FnClientResult<GalleryGetListData>> =>
        self.galleryOps.getGalleryList(startTime, endTime, limit, offset, mode)
    );
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
      let resp: http.HttpResponse;
      try {
        resp = await httpRequest.request(fullUrl, opt);
      } catch (e) {
        throw new Error(`http request failed: ${String(e)}`);
      }
      let text = '';
      if (typeof resp.result === 'string') {
        text = resp.result;
      } else {
        try {
          text = JSON.stringify(resp.result);
        } catch (e) {
          throw new Error(`serialize http response failed: ${String(e)}`);
        }
      }
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
    return this.galleryOps.fetchGalleryImageBuffer(fullUrl, timeoutMs);
  }

  async getGalleryStreamHeaders(fullUrl: string): Promise<Record<string, string>> {
    return this.galleryOps.getGalleryStreamHeaders(fullUrl);
  }

  async requestVideoDecodePlayUrl(req: VideoDecodePlayRequest, timeoutMs: number = 20000): Promise<FnClientResult<VideoDecodePlayInfo>> {
    return this.galleryOps.requestVideoDecodePlayUrl(req, timeoutMs);
  }

  async requestVideoDecodeQuit(photoId: string, timeoutMs: number = 8000): Promise<FnClientResult<Object>> {
    return this.galleryOps.requestVideoDecodeQuit(photoId, timeoutMs);
  }

  async getGalleryTimeline(extraParams?: Record<string, string | number | boolean>): Promise<FnClientResult<GalleryTimelineData>> {
    return this.galleryOps.getGalleryTimeline(extraParams);
  }

  async getCollectGalleryTimeline(): Promise<FnClientResult<GalleryTimelineData>> {
    return this.galleryOps.getCollectGalleryTimeline();
  }

  async getRecentTimeline(extraParams?: Record<string, string | number | boolean>): Promise<FnClientResult<GalleryTimelineData>> {
    return this.galleryOps.getRecentTimeline(extraParams);
  }

  async doMagicSearch(keyword: string, timeoutMs: number = 20000): Promise<FnClientResult<MagicSearchData>> {
    return this.galleryOps.doMagicSearch(keyword, timeoutMs);
  }

  async getMediaCategoryList(timeoutMs: number = 20000): Promise<FnClientResult<MediaCategoryData>> {
    return this.galleryOps.getMediaCategoryList(timeoutMs);
  }

  async getSmartRecCategories(mainCategory: string, limit: number = -1, timeoutMs: number = 20000): Promise<FnClientResult<SmartCategoryData>> {
    return this.galleryOps.getSmartRecCategories(mainCategory, limit, timeoutMs);
  }

  async getAiPersonList(getAll: boolean = true, limit: number = -1, orderBy: number = 0, timeoutMs: number = 20000): Promise<FnClientResult<AiPersonData>> {
    return this.galleryOps.getAiPersonList(getAll, limit, orderBy, timeoutMs);
  }

  async getAiPersonDetail(personId: string, timeoutMs: number = 20000): Promise<FnClientResult<AiPersonDetailData>> {
    return this.galleryOps.getAiPersonDetail(personId, timeoutMs);
  }

  async getPersonInPhoto(photoId: string, timeoutMs: number = 12000): Promise<FnClientResult<PersonInPhotoData>> {
    return this.galleryOps.getPersonInPhoto(photoId, timeoutMs);
  }

  async getAiPersonPhotoTimeline(personId: string, timeoutMs: number = 20000): Promise<FnClientResult<GalleryTimelineData>> {
    return this.galleryOps.getAiPersonPhotoTimeline(personId, timeoutMs);
  }

  async getAiPersonPhotoList(personId: string, startTime: string, endTime: string, limit: number, offset: number, timeoutMs: number = 20000): Promise<FnClientResult<GalleryGetListData>> {
    return this.galleryOps.getAiPersonPhotoList(personId, startTime, endTime, limit, offset, timeoutMs);
  }

  async searchResultsByCategory(item: MediaCategoryItem, timeoutMs: number = 20000): Promise<FnClientResult<GalleryListItem[]>> {
    return this.galleryOps.searchResultsByCategory(item, timeoutMs);
  }

  async getCategoryPhotos(fileType: string, limit: number = 200, offset: number = 0): Promise<FnClientResult<GalleryListItem[]>> {
    return this.galleryOps.getCategoryPhotos(fileType, limit, offset);
  }

  async getCollectGalleryList(startTime: string, endTime: string, limit: number, offset: number): Promise<FnClientResult<GalleryGetListData>> {
    return this.galleryOps.getCollectGalleryList(startTime, endTime, limit, offset);
  }

  async getGalleryList(startTime: string, endTime: string, limit: number, offset: number, mode: string = "index"): Promise<FnClientResult<GalleryGetListData>> {
    return this.galleryOps.getGalleryList(startTime, endTime, limit, offset, mode);
  }

  async getRecentPhotos(startTime: string, endTime: string, limit: number, offset: number, mode: string = "recent"): Promise<FnClientResult<GalleryGetListData>> {
    return this.galleryOps.getRecentPhotos(startTime, endTime, limit, offset, mode);
  }

  async getGalleryPhotoDetail(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<GalleryPhotoDetailData>> {
    return this.galleryOps.getGalleryPhotoDetail(photoId, timeoutMs);
  }

  async getFolderViewFileList(folderPath: string, limit: number = 100, offset: number = 0, desc: boolean = false, orderBy: number = 2, timeoutMs: number = 20000): Promise<FnClientResult<GalleryListItem[]>> {
    return this.galleryOps.getFolderViewFileList(folderPath, limit, offset, desc, orderBy, timeoutMs);
  }

  async getRecycleBinList(offset: number, limit: number, startTime: string, endTime: string, timeoutMs: number = 25000): Promise<FnClientResult<RecycleBinListData>> {
    return this.galleryOps.getRecycleBinList(offset, limit, startTime, endTime, timeoutMs);
  }

  async addPhotoToRecycleBin(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    return this.galleryOps.addPhotoToRecycleBin(photoId, timeoutMs);
  }

  async postPreviewCollect(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    return this.galleryOps.postPreviewCollect(photoId, timeoutMs);
  }

  async postPreviewCollectCancel(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    return this.galleryOps.postPreviewCollectCancel(photoId, timeoutMs);
  }

  async restoreRecycleBinPhotos(ids: number[], timeoutMs: number = 30000): Promise<FnClientResult<Object>> {
    return this.galleryOps.restoreRecycleBinPhotos(ids, timeoutMs);
  }

  async uploadPhotoByUri(uri: string, timeoutMs: number = 120000, albumUploadDirHint?: string): Promise<FnClientResult<Object>> {
    return this.uploadOps.uploadPhotoByUri(uri, timeoutMs, albumUploadDirHint);
  }
}
