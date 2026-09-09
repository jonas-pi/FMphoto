import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { CertPolicy } from '../CertPolicy';
import { genFnGalleryAuthxGet, genFnGalleryAuthxPostRaw } from '../FnGalleryAuthx';
import { FN_PHOTO_API_PREFIX } from '../FnPhotoRoutes';
import { mergeGalleryWebCookieIntoNativeHeader } from '../FnWebCookies';
import { fnWebViewBaseUrl } from '../ServerUrl';
import { buildFnApiCookieHeader } from './FnHttpClientCookie';
import {
  AssetBufferCacheEntry,
  GalleryAssetSignParts,
  escapeJsonString,
} from './FnHttpClientCommon';
import { FnHttpClientGalleryHost, VideoDecodePlayInfo, VideoDecodePlayRequest } from './FnHttpClientTypes';
import { FnClientResult } from '../../model/FnApiTypes';
import { FnHttpClientGalleryRequest } from './FnHttpClientGalleryRequest';

export interface GalleryHlsAuthProbe {
  m3u8Code: number;
  segName: string;
  segAuthxCode: number;
  segCookieCode: number;
}

interface GalleryProbeResp {
  code: number;
  text: string;
}

export class FnHttpClientMediaAssetOps extends FnHttpClientGalleryRequest {
  private static readonly inflightAssetReq: Map<string, Promise<ArrayBuffer | undefined>> = new Map();
  private static readonly assetBufferCache: Map<string, AssetBufferCacheEntry> = new Map();
  private static readonly ASSET_CACHE_TTL_MS: number = 15000;
  private static readonly ASSET_CACHE_MAX: number = 120;
  private static assetCacheGen: number = 0;

  constructor(host: FnHttpClientGalleryHost) {
    super(host);
  }

  async fetchGalleryImageBuffer(fullUrl: string, timeoutMs: number = 8000): Promise<ArrayBuffer | undefined> {
    const now = Date.now();
    const cached = FnHttpClientMediaAssetOps.assetBufferCache.get(fullUrl);
    if (cached !== undefined && now - cached.timeMs <= FnHttpClientMediaAssetOps.ASSET_CACHE_TTL_MS) {
      return cached.data;
    }
    const inflight = FnHttpClientMediaAssetOps.inflightAssetReq.get(fullUrl);
    if (inflight !== undefined) {
      return await inflight;
    }
    const cacheGen = FnHttpClientMediaAssetOps.assetCacheGen;
    const job = this.fetchGalleryImageBufferInternal(fullUrl, timeoutMs);
    FnHttpClientMediaAssetOps.inflightAssetReq.set(fullUrl, job);
    try {
      const out = await job;
      if (out !== undefined && out.byteLength > 0 && cacheGen === FnHttpClientMediaAssetOps.assetCacheGen) {
        FnHttpClientMediaAssetOps.putAssetBufferCache(fullUrl, out);
      }
      return out;
    } finally {
      FnHttpClientMediaAssetOps.inflightAssetReq.delete(fullUrl);
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
      const parsed = FnHttpClientMediaAssetOps.parseGalleryAssetUrl(fullUrl);
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
      const parsed = FnHttpClientMediaAssetOps.parseGalleryAssetUrl(fullUrl);
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
    if (FnHttpClientMediaAssetOps.assetBufferCache.size >= FnHttpClientMediaAssetOps.ASSET_CACHE_MAX) {
      let oldestKey: string | undefined = undefined;
      let oldestTime = Number.MAX_SAFE_INTEGER;
      const keys = Array.from(FnHttpClientMediaAssetOps.assetBufferCache.keys());
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const one = FnHttpClientMediaAssetOps.assetBufferCache.get(key);
        if (one !== undefined && one.timeMs < oldestTime) {
          oldestTime = one.timeMs;
          oldestKey = key;
        }
      }
      if (oldestKey !== undefined) {
        FnHttpClientMediaAssetOps.assetBufferCache.delete(oldestKey);
      }
    }
    const entry: AssetBufferCacheEntry = { timeMs: Date.now(), data: data };
    FnHttpClientMediaAssetOps.assetBufferCache.set(url, entry);
  }

  /** NAS 变更后丢掉短 TTL 的 HTTP 图 buffer，避免 15s 内仍返回旧封面/缩略图 */
  static clearAssetBufferCache(): void {
    FnHttpClientMediaAssetOps.assetCacheGen++;
    FnHttpClientMediaAssetOps.assetBufferCache.clear();
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
    const parsed = FnHttpClientMediaAssetOps.parseGalleryAssetUrl(fullUrl);
    const authx = await genFnGalleryAuthxGet(parsed.signPath, parsed.queryParams);
    const h = this.buildGalleryFetchHeaders(authx, cookie);
    h['Accept'] = '*/*';
    return h;
  }

  /**
   * 仅 Cookie 鉴权的流媒体请求头（贴近浏览器 <video> 行为）。
   * authx 是按“路径+时间戳”签名的，AVPlayer 会把首个 URL 的请求头原样复用给 m3u8 刷新与全部 TS 分片，
   * 携带签名不匹配的 authx 反而可能被 NAS 拒绝；HLS 播放应优先使用本方法返回的头。
   */
  async getGalleryStreamMediaHeaders(): Promise<Record<string, string>> {
    const activeBase = fnWebViewBaseUrl(this.baseUrl);
    const cookie = mergeGalleryWebCookieIntoNativeHeader(
      buildFnApiCookieHeader(this.token, this.longToken),
      activeBase
    );
    return this.buildGalleryMediaCookieHeaders(cookie);
  }

  private buildGalleryMediaCookieHeaders(cookie: string): Record<string, string> {
    const full = this.buildGalleryFetchHeaders('', cookie);
    const h: Record<string, string> = {
      'Cookie': cookie,
      'User-Agent': full['User-Agent'],
      'Referer': full['Referer'],
      'Accept': '*/*'
    };
    return h;
  }

  /**
   * HLS 鉴权探针：用 App 的 HTTP 栈（可跳过自签证书校验）实测转码流的鉴权要求。
   * 1) 带按路径签名的 authx 拉 m3u8（基线，应为 2xx）；
   * 2) 取第一个 TS 分片，分别以“按路径 authx”与“仅 Cookie”两种头请求（Range 前 2KB），记录响应码。
   * 结论用于决定交给 AVPlayer 的请求头，也为后续是否需要本地代理提供证据。
   */
  async probeGalleryHlsAuth(m3u8Url: string, timeoutMs: number = 6000): Promise<GalleryHlsAuthProbe> {
    const probe: GalleryHlsAuthProbe = { m3u8Code: -1, segName: '', segAuthxCode: -1, segCookieCode: -1 };
    const m3u8 = await this.requestGalleryProbe(m3u8Url, true, true, timeoutMs);
    probe.m3u8Code = m3u8.code;
    if (m3u8.code < 200 || m3u8.code >= 300 || m3u8.text.length === 0) {
      return probe;
    }
    const lines = m3u8.text.split('\n');
    let seg = '';
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length > 0 && !line.startsWith('#')) {
        seg = line;
        break;
      }
    }
    if (seg.length === 0) {
      return probe;
    }
    probe.segName = seg;
    let segUrl = '';
    if (seg.startsWith('http://') || seg.startsWith('https://')) {
      segUrl = seg;
    } else if (seg.startsWith('/')) {
      const schemeEnd = m3u8Url.indexOf('://') + 3;
      const slash = m3u8Url.indexOf('/', schemeEnd);
      segUrl = (slash > 0 ? m3u8Url.slice(0, slash) : m3u8Url) + seg;
    } else {
      segUrl = m3u8Url.slice(0, m3u8Url.lastIndexOf('/') + 1) + seg;
    }
    const withAuthx = await this.requestGalleryProbe(segUrl, true, false, timeoutMs);
    probe.segAuthxCode = withAuthx.code;
    const cookieOnly = await this.requestGalleryProbe(segUrl, false, false, timeoutMs);
    probe.segCookieCode = cookieOnly.code;
    return probe;
  }

  /** 探针单次请求：wantBody=true 时按文本返回 m3u8 内容；否则仅取前 2KB（Range）拿响应码 */
  private async requestGalleryProbe(
    fullUrl: string,
    withAuthx: boolean,
    wantBody: boolean,
    timeoutMs: number
  ): Promise<GalleryProbeResp> {
    const resp: GalleryProbeResp = { code: -1, text: '' };
    const req = http.createHttp();
    this.registerPendingRequest(req);
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      let headers: Record<string, string>;
      if (withAuthx) {
        const parsed = FnHttpClientMediaAssetOps.parseGalleryAssetUrl(fullUrl);
        const authx = await genFnGalleryAuthxGet(parsed.signPath, parsed.queryParams);
        headers = this.buildGalleryFetchHeaders(authx, cookie);
        headers['Accept'] = '*/*';
      } else {
        headers = this.buildGalleryMediaCookieHeaders(cookie);
      }
      const opt: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: timeoutMs,
        readTimeout: timeoutMs
      };
      if (CertPolicy.isTrusted(activeBase)) {
        opt.remoteValidation = 'skip';
      }
      if (wantBody) {
        opt.expectDataType = http.HttpDataType.STRING;
        opt.maxLimit = 1024 * 1024;
        const r = await req.request(fullUrl, opt);
        resp.code = r.responseCode;
        if (typeof r.result === 'string') {
          resp.text = r.result;
        }
      } else {
        // 分片可能有十几 MB：requestInStream 收到响应头即返回状态码，finally 中 destroy 会中止剩余下载
        headers['Range'] = 'bytes=0-2047';
        resp.code = await req.requestInStream(fullUrl, opt);
      }
    } catch (_e) {
    } finally {
      this.unregisterPendingRequest(req);
      try {
        req.destroy();
      } catch (_e) {
      }
    }
    return resp;
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
      if (!FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
        const errLine = FnHttpClientGalleryRequest.envelopeErrorLine(parsed);
        return { success: false, message: errLine.length > 0 ? errLine : '转码播放失败' };
      }
      const resolved = FnHttpClientMediaAssetOps.extractDecodePlayUrl(parsed, activeBase);
      if (resolved.length === 0) {
        return { success: false, message: '未返回可播放地址' };
      }
      const hls = FnHttpClientMediaAssetOps.extractDecodeHlsTimeSec(parsed);
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
      if (FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
        return { success: true, data: parsed['data'] as Object };
      }
      return { success: false, message: FnHttpClientGalleryRequest.envelopeErrorLine(parsed) || 'quit 业务失败' };
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
}
