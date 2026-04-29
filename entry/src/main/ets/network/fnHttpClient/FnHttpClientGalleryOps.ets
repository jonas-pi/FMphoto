import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CertPolicy } from '../CertPolicy';
import { buildGallerySortedQuery, FnGalleryGetSignSpec, genFnGalleryAuthxGet, genFnGalleryAuthxPost, genFnGalleryAuthxPostRaw } from '../FnGalleryAuthx';
import { FN_PHOTO_API_PREFIX, FN_PHOTO_API_V2_PREFIX } from '../FnPhotoRoutes';
import { mergeGalleryWebCookieIntoNativeHeader } from '../FnWebCookies';
import { fnWebViewBaseUrl } from '../ServerUrl';
import { buildFnApiCookieHeader } from './FnHttpClientCookie';
import {
  AssetBufferCacheEntry,
  DEFAULT_TIMEOUT,
  DOMAIN,
  GALLERY_FOLDER_FILELIST_PATH_CANDIDATES,
  GALLERY_FOLDER_FILELIST_SIGN_PATH,
  GALLERY_GETLIST_PATH_CANDIDATES,
  GALLERY_GETLIST_SIGN_PATH,
  GALLERY_GETONE_PATH_CANDIDATES,
  GALLERY_GETONE_SIGN_PATH,
  GALLERY_QUERY_EMPTY,
  GALLERY_TIMELINE_PATH_CANDIDATES,
  GALLERY_TIMELINE_SIGN_PATH,
  GalleryAssetSignParts,
  PERSON_IN_PHOTO_PATH_CANDIDATES,
  PERSON_IN_PHOTO_SIGN_PATH,
  RECENT_PHOTOS_PATH_CANDIDATES,
  RECENT_PHOTOS_SIGN_PATH,
  RECENT_TIMELINE_PATH_CANDIDATES,
  RECENT_TIMELINE_SIGN_PATH,
  RECYCLE_BIN_LIST_SIGN_PATH,
  TAG,
  escapeJsonString,
} from './FnHttpClientCommon';
import { FnHttpClientGalleryHost, VideoDecodePlayInfo, VideoDecodePlayRequest } from './FnHttpClientTypes';
import {
  AiPersonItem,
  AiPersonData,
  AiPersonDetailData,
  FnClientResult,
  FnJsonValue,
  GalleryGetListData,
  GalleryListItem,
  GalleryPhotoDetailData,
  GalleryTimelineData,
  MagicSearchData,
  MagicSearchDoBody,
  MediaCategoryData,
  MediaCategoryItem,
  PersonInPhotoData,
  RecycleBinListData,
  SmartCategoryData,
  SmartCategoryItem
} from '../../model/FnApiTypes';

export class FnHttpClientGalleryOps {
  private static readonly inflightAssetReq: Map<string, Promise<ArrayBuffer | undefined>> = new Map();
  private static readonly assetBufferCache: Map<string, AssetBufferCacheEntry> = new Map();
  private static readonly ASSET_CACHE_TTL_MS: number = 15000;
  private static readonly ASSET_CACHE_MAX: number = 120;
  private readonly host: FnHttpClientGalleryHost;

  constructor(host: FnHttpClientGalleryHost) {
    this.host = host;
  }

  private get baseUrl(): string {
    return this.host.getBaseUrl();
  }

  private get token(): string {
    return this.host.getToken();
  }

  private get longToken(): string {
    return this.host.getLongToken();
  }

  private registerPendingRequest(req: http.HttpRequest): void {
    this.host.registerPendingRequest(req);
  }

  private unregisterPendingRequest(req: http.HttpRequest): void {
    this.host.unregisterPendingRequest(req);
  }

  private buildGalleryFetchHeaders(authxVal: string, cookieHeader: string): Record<string, string> {
    return this.host.buildGalleryFetchHeaders(authxVal, cookieHeader);
  }

  private async requestGalleryGetJson<T>(pathCandidates: string[], gallerySign: FnGalleryGetSignSpec, timeoutMs: number, tryTimes: number): Promise<FnClientResult<T>> {
    return this.host.requestGalleryGetJson(pathCandidates, gallerySign, timeoutMs, tryTimes) as Promise<FnClientResult<T>>;
  }

  private async rawRequest(fullUrl: string, method: http.RequestMethod, header: Record<string, string>, bodyStr: string | undefined, timeoutMs: number, skipRemoteCert: boolean) {
    return this.host.rawRequest(fullUrl, method, header, bodyStr, timeoutMs, skipRemoteCert);
  }

  private static envelopeErrorLine(body: Record<string, string | number | Object | undefined>): string {
    const tryKeys: string[] = ['msg', 'message', 'errmsg', 'error', 'detail', 'errorMessage', 'reason'];
    for (let i = 0; i < tryKeys.length; i++) {
      const v = body[tryKeys[i]];
      if (typeof v === "string" && v.length > 0) {
        return v;
      }
    }
    const d = body['data'];
    if (d !== undefined && d !== null && typeof d === "object" && !Array.isArray(d)) {
      const o = d as Record<string, string | Object | undefined>;
      for (let j = 0; j < tryKeys.length; j++) {
        const k = tryKeys[j];
        const v2 = o[k];
        if (typeof v2 === "string" && v2.length > 0) {
          return v2;
        }
      }
    }
    return '';
  }

  private static galleryErrorBodyPreview(rawBody: string | undefined): string {
    if (rawBody === undefined) {
      return '';
    }
    const max = 640;
    if (rawBody.length <= max) {
      return rawBody;
    }
    return `${rawBody.substring(0, max)}...`;
  }

  private static envelopeCodeNum(body: Record<string, string | number | Object | undefined>): number {
    const c = body['code'];
    if (typeof c === "number" && !isNaN(c)) {
      return c;
    }
    if (typeof c === "string") {
      const n = parseInt(c, 10);
      return isNaN(n) ? -1 : n;
    }
    return -1;
  }

  private static galleryEnvelopeBizOk(body: Record<string, string | number | Object | undefined>): boolean {
    const c = body['code'];
    if (c === undefined || c === null) {
      const err = FnHttpClientGalleryOps.envelopeErrorLine(body);
      const data = body['data'];
      const result = body['result'];
      if (err.length > 0 && (data === undefined || data === null) && (result === undefined || result === null)) {
        return false;
      }
      return true;
    }
    if (typeof c === "number" && !isNaN(c)) {
      return c === 0;
    }
    if (typeof c === "string") {
      const n = parseInt(c, 10);
      return !isNaN(n) && n === 0;
    }
    return false;
  }

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
  async fetchGalleryImageBuffer(fullUrl: string, timeoutMs: number = 8000): Promise<ArrayBuffer | undefined> {
    const now = Date.now();
    const cached = FnHttpClientGalleryOps.assetBufferCache.get(fullUrl);
    if (cached !== undefined && now - cached.timeMs <= FnHttpClientGalleryOps.ASSET_CACHE_TTL_MS) {
      return cached.data;
    }
    const inflight = FnHttpClientGalleryOps.inflightAssetReq.get(fullUrl);
    if (inflight !== undefined) {
      return await inflight;
    }
    const job = this.fetchGalleryImageBufferInternal(fullUrl, timeoutMs);
    FnHttpClientGalleryOps.inflightAssetReq.set(fullUrl, job);
    try {
      const out = await job;
      if (out !== undefined && out.byteLength > 0) {
        FnHttpClientGalleryOps.putAssetBufferCache(fullUrl, out);
      }
      return out;
    } finally {
      FnHttpClientGalleryOps.inflightAssetReq.delete(fullUrl);
    }
  }

  async downloadGalleryAssetToFile(
    fullUrl: string,
    filePath: string,
    timeoutMs: number = 300000,
    onProgress?: (receiveSize: number, totalSize: number) => void
  ): Promise<boolean> {
    let targetFd = -1;
    const req = http.createHttp();
    this.registerPendingRequest(req);
    let writeQueue: Promise<void> = Promise.resolve();
    let writeFailed = false;
    let dataEndResolve: (() => void) | undefined = undefined;
    const dataEndPromise = new Promise<void>((resolve) => {
      dataEndResolve = resolve;
    });
    const onDataReceive = (chunk: ArrayBuffer): void => {
      if (writeFailed || chunk.byteLength === 0) {
        return;
      }
      const piece = chunk.slice(0);
      writeQueue = writeQueue.then(async (): Promise<void> => {
        if (writeFailed || targetFd < 0) {
          return;
        }
        await fileIo.write(targetFd, piece);
      }).catch((_e: Error): void => {
        writeFailed = true;
      });
    };
    const onDataEnd = (): void => {
      if (dataEndResolve !== undefined) {
        dataEndResolve();
      }
    };
    const onDataReceiveProgress = (info: http.DataReceiveProgressInfo): void => {
      if (onProgress === undefined) {
        return;
      }
      const receiveSize = Number(info.receiveSize);
      const totalSize = Number(info.totalSize);
      onProgress(
        Number.isFinite(receiveSize) ? receiveSize : 0,
        Number.isFinite(totalSize) ? totalSize : 0
      );
    };
    req.on('dataReceive', onDataReceive);
    req.on('dataEnd', onDataEnd);
    req.on('dataReceiveProgress', onDataReceiveProgress);
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const parsed = FnHttpClientGalleryOps.parseGalleryAssetUrl(fullUrl);
      const authx = await genFnGalleryAuthxGet(parsed.signPath, parsed.queryParams);
      const headers = this.buildGalleryFetchHeaders(authx, cookie);
      headers['Accept'] = '*/*';
      const targetFile = await fileIo.open(
        filePath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      targetFd = targetFile.fd;
      const opt: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs,
        maxLimit: 100 * 1024 * 1024
      };
      if (CertPolicy.isTrusted(activeBase)) {
        opt.remoteValidation = 'skip';
      }
      const responseCode = await req.requestInStream(fullUrl, opt);
      if (responseCode < 200 || responseCode >= 300) {
        return false;
      }
      await dataEndPromise;
      await writeQueue;
      if (writeFailed) {
        return false;
      }
      return true;
    } catch (_e) {
      return false;
    } finally {
      req.off('dataReceive', onDataReceive);
      req.off('dataEnd', onDataEnd);
      req.off('dataReceiveProgress', onDataReceiveProgress);
      this.unregisterPendingRequest(req);
      try {
        req.destroy();
      } catch (_e) {
      }
      if (targetFd >= 0) {
        try {
          await fileIo.close(targetFd);
        } catch (_e) {
        }
      }
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
      const parsed = FnHttpClientGalleryOps.parseGalleryAssetUrl(fullUrl);
      const authx = await genFnGalleryAuthxGet(parsed.signPath, parsed.queryParams);
      const headers = this.buildGalleryFetchHeaders(authx, cookie);
      headers['Accept'] = '*/*';
      const req = http.createHttp();
      this.registerPendingRequest(req);
      try {
        const opt: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          header: headers,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: timeoutMs,
          readTimeout: timeoutMs,
          maxLimit: 20 * 1024 * 1024
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
    if (FnHttpClientGalleryOps.assetBufferCache.size >= FnHttpClientGalleryOps.ASSET_CACHE_MAX) {
      let oldestKey: string | undefined = undefined;
      let oldestTime = Number.MAX_SAFE_INTEGER;
      const keys = Array.from(FnHttpClientGalleryOps.assetBufferCache.keys());
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const one = FnHttpClientGalleryOps.assetBufferCache.get(key);
        if (one !== undefined && one.timeMs < oldestTime) {
          oldestTime = one.timeMs;
          oldestKey = key;
        }
      }
      if (oldestKey !== undefined) {
        FnHttpClientGalleryOps.assetBufferCache.delete(oldestKey);
      }
    }
    const entry: AssetBufferCacheEntry = { timeMs: Date.now(), data: data };
    FnHttpClientGalleryOps.assetBufferCache.set(url, entry);
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
    const parsed = FnHttpClientGalleryOps.parseGalleryAssetUrl(fullUrl);
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
      if (!FnHttpClientGalleryOps.galleryEnvelopeBizOk(parsed)) {
        const errLine = FnHttpClientGalleryOps.envelopeErrorLine(parsed);
        return { success: false, message: errLine.length > 0 ? errLine : '转码播放失败' };
      }
      const resolved = FnHttpClientGalleryOps.extractDecodePlayUrl(parsed, activeBase);
      if (resolved.length === 0) {
        return { success: false, message: '未返回可播放地址' };
      }
      const hls = FnHttpClientGalleryOps.extractDecodeHlsTimeSec(parsed);
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
      if (FnHttpClientGalleryOps.galleryEnvelopeBizOk(parsed)) {
        return { success: true, data: parsed['data'] as Object };
      }
      return { success: false, message: FnHttpClientGalleryOps.envelopeErrorLine(parsed) || 'quit 业务失败' };
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
      if (!FnHttpClientGalleryOps.galleryEnvelopeBizOk(parsed)) {
        const code = FnHttpClientGalleryOps.envelopeCodeNum(parsed);
        const errLine = FnHttpClientGalleryOps.envelopeErrorLine(parsed);
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
        if (!FnHttpClientGalleryOps.galleryEnvelopeBizOk(parsed)) {
          const code = FnHttpClientGalleryOps.envelopeCodeNum(parsed);
          const errLine = FnHttpClientGalleryOps.envelopeErrorLine(parsed);
          lastBizMsg = errLine.length > 0 ? errLine : `媒体分类请求失败 (${code})`;
          continue;
        }
        hilog.info(DOMAIN, TAG, 'mediaCat path=%{public}s body(600): %{public}s', path, raw.body.substring(0, 600));
        const payload = FnHttpClientGalleryOps.galleryEnvelopeData(parsed);
        const normList = FnHttpClientGalleryOps.mediaCategoryItemsFromData(payload);
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
      const normList = FnHttpClientGalleryOps.smartCategoryItemsFromData(res.data as Object);
      if (normList.length > 0) {
        const first = normList[0] as Record<string, Object | string | number | boolean | undefined | null>;
        hilog.info(
          DOMAIN,
          TAG,
          'smartCat normCount=%{public}d firstCover=%{public}s',
          normList.length,
          FnHttpClientGalleryOps.readFirstString(first, ['cover', 'thumb', 'posterUrl', 'imageUrl'])
        );
      }
      return { success: true, data: { list: normList } };
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
      const normList = FnHttpClientGalleryOps.aiPersonItemsFromData(res.data as Object);
      if (normList.length > 0) {
        const first = normList[0] as Record<string, Object | string | number | boolean | undefined | null>;
        hilog.info(
          DOMAIN,
          TAG,
          'person normCount=%{public}d firstFace=%{public}s',
          normList.length,
          FnHttpClientGalleryOps.readFirstString(first, ['faceUrl', 'cover', 'thumb'])
        );
      }
      return { success: true, data: { list: normList } };
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
        result.push(FnHttpClientGalleryOps.normalizeCategoryItem(el as Record<string, Object | undefined>));
      }
    }
    return result;
  }

  private static readTrimmedString(
    value: Object | string | number | boolean | undefined | null
  ): string {
    if (typeof value === 'string') {
      return value.trim();
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return String(value).trim();
    }
    return '';
  }

  private static asLooseJsonRecord(
    value: Object | string | number | boolean | undefined | null
  ): Record<string, Object | string | number | boolean | undefined | null> | null {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      return null;
    }
    return value as Record<string, Object | string | number | boolean | undefined | null>;
  }

  private static readFirstString(
    raw: Record<string, Object | string | number | boolean | undefined | null>,
    keys: string[]
  ): string {
    for (let i = 0; i < keys.length; i++) {
      const text = FnHttpClientGalleryOps.readTrimmedString(raw[keys[i]]);
      if (text.length > 0) {
        return text;
      }
    }
    return '';
  }

  private static readThumbnailLikeUrl(
    raw: Record<string, Object | string | number | boolean | undefined | null>
  ): string {
    const thumbVal = raw['thumbnail'];
    if (typeof thumbVal === 'string') {
      const text = thumbVal.trim();
      if (text.length > 0) {
        return text;
      }
    }
    const thumbObj = FnHttpClientGalleryOps.asLooseJsonRecord(thumbVal);
    if (thumbObj === null) {
      return '';
    }
    return FnHttpClientGalleryOps.readFirstString(thumbObj, [
      'mUrl',
      'sUrl',
      'xsUrl',
      'xxsUrl',
      'originalUrl',
      'videoUrl',
      'url',
      'src'
    ]);
  }

  private static buildPhotoThumbStream(
    raw: Record<string, Object | string | number | boolean | undefined | null>,
    mode: 'm' | 's' = 'm'
  ): string {
    const id = FnHttpClientGalleryOps.readFirstString(raw, ['photoId', 'id']);
    const uuid = FnHttpClientGalleryOps.readFirstString(raw, ['uuid', 'photoUUID', 'session']);
    if (id.length === 0 || uuid.length === 0 || id === 'null' || uuid === 'null') {
      return '';
    }
    return `${FN_PHOTO_API_PREFIX}/stream/p/t/${id}/${mode}/${uuid}`;
  }

  private static pickBestCoverUrl(
    raw: Record<string, Object | string | number | boolean | undefined | null>,
    nestedKeys: string[]
  ): string {
    const direct = FnHttpClientGalleryOps.readFirstString(raw, [
      'cover',
      'thumb',
      'small_thumb',
      'thumb_url',
      'poster',
      'posterUrl',
      'avatarUrl',
      'faceUrl',
      'imageUrl',
      'imgUrl',
      'photoUrl',
      'url',
      'src',
      'path'
    ]);
    if (direct.length > 0) {
      return direct;
    }
    const thumbnailUrl = FnHttpClientGalleryOps.readThumbnailLikeUrl(raw);
    if (thumbnailUrl.length > 0) {
      return thumbnailUrl;
    }
    for (let i = 0; i < nestedKeys.length; i++) {
      const nested = FnHttpClientGalleryOps.asLooseJsonRecord(raw[nestedKeys[i]]);
      if (nested === null) {
        continue;
      }
      const nestedDirect = FnHttpClientGalleryOps.readFirstString(nested, [
        'cover',
        'thumb',
        'small_thumb',
        'thumb_url',
        'poster',
        'posterUrl',
        'avatarUrl',
        'faceUrl',
        'imageUrl',
        'imgUrl',
        'photoUrl',
        'url',
        'src',
        'path'
      ]);
      if (nestedDirect.length > 0) {
        return nestedDirect;
      }
      const nestedThumbUrl = FnHttpClientGalleryOps.readThumbnailLikeUrl(nested);
      if (nestedThumbUrl.length > 0) {
        return nestedThumbUrl;
      }
      const nestedPhotoStream = FnHttpClientGalleryOps.buildPhotoThumbStream(nested);
      if (nestedPhotoStream.length > 0) {
        return nestedPhotoStream;
      }
    }
    return FnHttpClientGalleryOps.buildPhotoThumbStream(raw);
  }

  private static normalizeSmartCategoryItem(
    raw: Record<string, Object | string | number | boolean | undefined | null>
  ): SmartCategoryItem {
    const out = raw as SmartCategoryItem;
    const coverUrl = FnHttpClientGalleryOps.pickBestCoverUrl(raw, ['poster', 'coverInfo', 'coverPhoto']);
    if (coverUrl.length > 0) {
      raw['cover'] = coverUrl;
      if (FnHttpClientGalleryOps.readTrimmedString(raw['thumb']).length <= 0) {
        raw['thumb'] = coverUrl;
      }
    }
    return out;
  }

  private static smartCategoryItemsFromData(dataObj: Object | undefined): SmartCategoryItem[] {
    if (dataObj === undefined || dataObj === null) {
      return [];
    }
    let rawArr: Object[];
    if (Array.isArray(dataObj)) {
      rawArr = dataObj as Object[];
    } else {
      const d = dataObj as Record<string, Object | undefined>;
      const found = d['list'] ?? d['items'] ?? d['records'] ?? d['rows'] ?? d['data'] ?? d['result'];
      if (!Array.isArray(found)) {
        return [];
      }
      rawArr = found as Object[];
    }
    const result: SmartCategoryItem[] = [];
    for (let i = 0; i < rawArr.length; i++) {
      const el = rawArr[i];
      const raw = FnHttpClientGalleryOps.asLooseJsonRecord(el);
      if (raw !== null) {
        result.push(FnHttpClientGalleryOps.normalizeSmartCategoryItem(raw));
      }
    }
    return result;
  }

  private static normalizeAiPersonItem(
    raw: Record<string, Object | string | number | boolean | undefined | null>
  ): AiPersonItem {
    const out = raw as AiPersonItem;
    let faceUrl = FnHttpClientGalleryOps.pickBestCoverUrl(raw, ['face', 'avatar', 'poster', 'coverInfo', 'coverPhoto']);
    if (faceUrl.length <= 0) {
      const faceId = FnHttpClientGalleryOps.readFirstString(raw, ['faceId', 'avatarId', 'posterId', 'coverId', 'id']);
      if (faceId.length > 0) {
        faceUrl = `${FN_PHOTO_API_PREFIX}/stream/face/${faceId}`;
      }
    }
    if (faceUrl.length > 0) {
      raw['faceUrl'] = faceUrl;
      if (FnHttpClientGalleryOps.readTrimmedString(raw['cover']).length <= 0) {
        raw['cover'] = faceUrl;
      }
      if (FnHttpClientGalleryOps.readTrimmedString(raw['thumb']).length <= 0) {
        raw['thumb'] = faceUrl;
      }
    }
    return out;
  }

  private static aiPersonItemsFromData(dataObj: Object | undefined): AiPersonItem[] {
    if (dataObj === undefined || dataObj === null) {
      return [];
    }
    let rawArr: Object[];
    if (Array.isArray(dataObj)) {
      rawArr = dataObj as Object[];
    } else {
      const d = dataObj as Record<string, Object | undefined>;
      const found = d['list'] ?? d['items'] ?? d['records'] ?? d['rows'] ?? d['data'] ?? d['result'];
      if (!Array.isArray(found)) {
        return [];
      }
      rawArr = found as Object[];
    }
    const result: AiPersonItem[] = [];
    for (let i = 0; i < rawArr.length; i++) {
      const el = rawArr[i];
      const raw = FnHttpClientGalleryOps.asLooseJsonRecord(el);
      if (raw !== null) {
        result.push(FnHttpClientGalleryOps.normalizeAiPersonItem(raw));
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
      let x: Object | undefined = FnHttpClientGalleryOps.unwrapCategoryNested(v as Object);
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
    const catRaw = FnHttpClientGalleryOps.pickCategoryScalar(raw);
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
      FnHttpClientGalleryOps.applyMediaCategoryEnumByIndex(out, Math.floor(catNum));
    }

    const nameCand =
      raw['name'] ?? raw['title'] ?? raw['label'] ?? raw['categoryName'] ?? raw['displayName'];
    if (typeof nameCand === 'string' && nameCand.trim().length > 0) {
      const nt = nameCand.trim();
      // 占位「未命名分类」不能覆盖已由枚举推出来的「屏幕截图」等
      if (!FnHttpClientGalleryOps.isPlaceholderCategoryDisplayName(nt)) {
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
        FnHttpClientGalleryOps.applyMediaCategoryEnumByIndex(out, kInt);
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
        FnHttpClientGalleryOps.isPlaceholderCategoryDisplayName(out.name)) {
        out.name = '屏幕截图';
      }
    }

    const keyForLabel = out.key !== undefined ? out.key : '';
    const nameNow = out.name !== undefined ? out.name : '';
    if (keyForLabel.length > 0 &&
      (nameNow.length === 0 || FnHttpClientGalleryOps.isPlaceholderCategoryDisplayName(nameNow))) {
      const lb = FnHttpClientGalleryOps.mediaCategoryLabelForKey(keyForLabel);
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
      const nested = FnHttpClientGalleryOps.searchResultItemsFromData(inner);
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
            if (parsedFilters !== undefined && FnHttpClientGalleryOps.galleryEnvelopeBizOk(parsedFilters)) {
              const arrFilters =
                FnHttpClientGalleryOps.searchResultItemsFromData(FnHttpClientGalleryOps.galleryEnvelopeData(parsedFilters));
              hilog.info(DOMAIN, TAG, 'catSearch filters arr.length=%{public}d', arrFilters.length);
              if (arrFilters.length > 0) {
                return {
                  success: true,
                  data: FnHttpClientGalleryOps.normalizeSearchResultGalleryItems(arrFilters),
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
          if (!FnHttpClientGalleryOps.galleryEnvelopeBizOk(parsed)) {
            continue;
          }
          const arr = FnHttpClientGalleryOps.searchResultItemsFromData(FnHttpClientGalleryOps.galleryEnvelopeData(parsed));
          if (arr.length > 0) {
            return { success: true, data: FnHttpClientGalleryOps.normalizeSearchResultGalleryItems(arr) };
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
      return { success: true, data: FnHttpClientGalleryOps.normalizeFolderViewItems(payload as GalleryListItem[]) };
    }
    const dataObj = payload as GalleryGetListData;
    const list = dataObj.list ?? dataObj.items ?? dataObj.photos ?? dataObj.records ?? [];
    if (!Array.isArray(list)) {
      return { success: true, data: [] };
    }
    return { success: true, data: FnHttpClientGalleryOps.normalizeFolderViewItems(list as GalleryListItem[]) };
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
          if (FnHttpClientGalleryOps.galleryEnvelopeBizOk(parsed)) {
            return { success: true, data: parsed['data'] as Object };
          }
          const errLine = FnHttpClientGalleryOps.envelopeErrorLine(parsed);
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
          if (FnHttpClientGalleryOps.galleryEnvelopeBizOk(parsed)) {
            return { success: true, data: parsed['data'] as Object };
          }
          const errLine = FnHttpClientGalleryOps.envelopeErrorLine(parsed);
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
          if (FnHttpClientGalleryOps.galleryEnvelopeBizOk(parsed)) {
            return { success: true, data: parsed['data'] as Object };
          }
          const errLine = FnHttpClientGalleryOps.envelopeErrorLine(parsed);
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
      if (FnHttpClientGalleryOps.galleryEnvelopeBizOk(parsed)) {
        return { success: true, data: parsed['data'] as Object };
      }
      const errLine = FnHttpClientGalleryOps.envelopeErrorLine(parsed);
      return { success: false, message: errLine.length > 0 ? errLine : '恢复失败' };
    } catch (e) {
      return { success: false, message: String(e) || '恢复请求异常' };
    }
  }

}
