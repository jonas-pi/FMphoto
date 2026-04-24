import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { CertPolicy } from '../CertPolicy';
import { buildGallerySortedQuery, genFnGalleryAuthxGet, genFnGalleryAuthxPostRaw } from '../FnGalleryAuthx';
import { FN_PHOTO_API_PREFIX, FN_PHOTO_H5_ALBUM_PAGE } from '../FnPhotoRoutes';
import { fnWebDefaultUserAgent, mergeGalleryWebCookieIntoNativeHeader } from '../FnWebCookies';
import { fnWebViewBaseUrl } from '../ServerUrl';
import { buildFnApiCookieHeader, buildUploadCookieHeader, stripUploadForbiddenCookieKeys } from './FnHttpClientCookie';
import {
  DOMAIN,
  GALLERY_QUERY_EMPTY,
  LocalDayRange,
  TAG,
  UploadFileReadResult,
  UploadNoticeResult,
  buildMultipartUploadBody,
  buildTrimSignCandidates,
  cookieKeysSummary,
  decodeUriPartSafely,
  encodeTrimPath,
  escapeJsonString,
  lastUnixPathSegment,
  localDayRangeByYmd,
  localDayRangeNow,
  lowerExtFromName,
  nameStem,
  pad2,
  redactCookieHeaderForLog,
  trimJoinPath,
} from './FnHttpClientCommon';
import { FnHttpClientUploadHost } from './FnHttpClientTypes';
import { FnClientResult, GalleryListItem } from '../../model/FnApiTypes';

export class FnHttpClientUploadOps {
  private readonly host: FnHttpClientUploadHost;

  constructor(host: FnHttpClientUploadHost) {
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

  private get wsSignKeyB64(): string {
    return this.host.getWsSignKeyB64();
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

  private async rawRequest(fullUrl: string, method: http.RequestMethod, header: Record<string, string>, bodyStr: string | undefined, timeoutMs: number, skipRemoteCert: boolean) {
    return this.host.rawRequest(fullUrl, method, header, bodyStr, timeoutMs, skipRemoteCert);
  }

  private primeWebCookiesForPStack(webHttpsBaseNoSlash: string): void {
    this.host.primeWebCookiesForPStack(webHttpsBaseNoSlash);
  }

  private async getGalleryTimeline() {
    return this.host.getGalleryTimeline();
  }

  private async getGalleryList(startTime: string, endTime: string, limit: number, offset: number, mode: string = "index") {
    return this.host.getGalleryList(startTime, endTime, limit, offset, mode);
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

  private static galleryEnvelopeBizOk(body: Record<string, string | number | Object | undefined>): boolean {
    const c = body['code'];
    if (c === undefined || c === null) {
      const err = FnHttpClientUploadOps.envelopeErrorLine(body);
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

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: (v: void) => void) => {
      setTimeout((): void => {
        resolve();
      }, ms);
    });
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
      const mtimeSec = FnHttpClientUploadOps.statMtimeToUnixSec(st);
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
    const root = FnHttpClientUploadOps.firstPathLikeFromRecord(parsed);
    if (root.length > 0) {
      return root;
    }
    const dataObj = parsed['data'];
    if (dataObj !== undefined && dataObj !== null && typeof dataObj === 'object' && !Array.isArray(dataObj)) {
      const nested = dataObj as Record<string, string | number | Object | undefined>;
      return FnHttpClientUploadOps.firstPathLikeFromRecord(nested);
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
          const p = FnHttpClientUploadOps.firstUploadPathFromResponse(raw.body);
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
        if (FnHttpClientUploadOps.galleryEnvelopeBizOk(parsed)) {
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
    const fc = FnHttpClientUploadOps.formatNoticeFileCreateTime(mtimForNotice);
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
        if (!FnHttpClientUploadOps.galleryEnvelopeBizOk(parsed)) {
          const em = FnHttpClientUploadOps.envelopeErrorLine(parsed);
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
        await FnHttpClientUploadOps.sleep(800 + i * 700);
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
    const filePack = FnHttpClientUploadOps.readUploadFileAndMtime(oneUri);
    if (filePack === undefined || filePack.buffer.byteLength <= 0) {
      hilog.warn(DOMAIN, TAG, '[upload] abort read file failed uriLen=%{public}d', oneUri.length);
      return { success: false, message: '读取待上传文件失败' };
    }
    const payload = filePack.buffer;
    const fileName = FnHttpClientUploadOps.fileNameFromUri(oneUri);
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
                const em = FnHttpClientUploadOps.envelopeErrorLine(parsed);
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
              if (!FnHttpClientUploadOps.galleryEnvelopeBizOk(parsed)) {
                const em = FnHttpClientUploadOps.envelopeErrorLine(parsed);
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
    const pathHintFromUpload = FnHttpClientUploadOps.firstUploadPathFromResponse(uploadRespText);
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
      const uploadPhotoId = FnHttpClientUploadOps.firstUploadPhotoIdFromResponse(uploadRespText);
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
