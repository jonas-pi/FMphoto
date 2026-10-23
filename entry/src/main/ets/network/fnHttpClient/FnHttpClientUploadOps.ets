import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagError, fnDiagMaskPath, fnDiagMaskUrl, fnDiagRecord } from '../../common/FnDiagLog';
import { AppSession } from '../../auth/AppSession';
import { getAlbumBackupSettingsCached } from '../../sync/AlbumBackupSettings';
import { fileIo } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { CertPolicy } from '../CertPolicy';
import { buildGallerySortedQuery, genFnGalleryAuthxGet, genFnGalleryAuthxPostRaw } from '../FnGalleryAuthx';
import { FN_PHOTO_API_PREFIX, FN_PHOTO_API_V2_PREFIX, FN_PHOTO_H5_ALBUM_PAGE } from '../FnPhotoRoutes';
import { fnWebDefaultUserAgent, mergeGalleryWebCookieIntoNativeHeader } from '../FnWebCookies';
import { isFnRelayBaseUrl } from '../FnConnectApi';
import { fnWebUiBaseUrl, fnWebViewBaseUrl } from '../ServerUrl';
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
  fnHttpStatusMessage,
  fnNetErrorParts,
  fnNetErrorText,
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

/**
 * 单次上传尝试的失败记录。
 * kind: 'http' = 服务端返回非 2xx；'biz' = 2xx 但业务 code≠0；'exception' = 连接层异常。
 */
export interface UploadAttemptFail {
  origin: string;
  kind: string;
  httpCode: number;
  detail: string;
}

/**
 * 同步读整文件放到 TaskPool，避免主线程 openSync/readSync 冻 UI。
 * 失败返回空 buffer，调用方按 byteLength<=0 处理。
 */
@Concurrent
function readUploadFileAndMtimeConcurrent(uri: string): UploadFileReadResult {
  const nowSec: number = Math.floor(Date.now() / 1000);
  const empty: UploadFileReadResult = { buffer: new ArrayBuffer(0), mtimeSec: nowSec };
  let fdNum: number = -1;
  try {
    const f = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    fdNum = f.fd;
    const st = fileIo.statSync(fdNum);
    let mtimeSec: number = nowSec;
    const rawMtime = st.mtime;
    if (typeof rawMtime === 'number' && Number.isFinite(rawMtime) && rawMtime > 0) {
      if (rawMtime > 1e15) {
        mtimeSec = Math.floor(rawMtime / 1e9);
      } else if (rawMtime > 1e12) {
        mtimeSec = Math.floor(rawMtime / 1e3);
      } else {
        mtimeSec = Math.floor(rawMtime);
      }
    }
    const size = Number(st.size);
    if (!Number.isFinite(size) || size <= 0) {
      return empty;
    }
    const whole = new ArrayBuffer(Math.floor(size));
    const readLen = fileIo.readSync(fdNum, whole);
    if (!Number.isFinite(readLen) || readLen <= 0) {
      return empty;
    }
    const buffer = readLen < whole.byteLength ? whole.slice(0, readLen) : whole;
    return { buffer: buffer, mtimeSec: mtimeSec };
  } catch (_e) {
    fnDiagRecord('E', TAG, `upload read file fail len=${uri.length}`);
    return empty;
  } finally {
    if (fdNum >= 0) {
      try {
        fileIo.closeSync(fdNum);
      } catch (_e) {
      }
    }
  }
}

/**
 * 只取 JSON 字段名（不取值），用于 notice 请求体诊断：避免把 NAS 路径与原始文件名写进日志。
 */
function jsonFieldNamesOf(bodyStr: string): string {
  const names: string[] = [];
  const collect = (obj: Object, depth: number): void => {
    if (depth > 3) {
      return;
    }
    const rec = obj as Record<string, Object | string | number | boolean | undefined | null>;
    const keys = Object.keys(rec);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (names.indexOf(k) < 0) {
        names.push(k);
      }
      const v = rec[k];
      if (Array.isArray(v)) {
        const arr = v as Array<Object>;
        if (arr.length > 0) {
          const first = arr[0];
          if (first !== undefined && first !== null && typeof first === 'object') {
            collect(first, depth + 1);
          }
        }
      } else if (v !== undefined && v !== null && typeof v === 'object') {
        collect(v, depth + 1);
      }
    }
  };
  try {
    const parsed = JSON.parse(bodyStr) as Object;
    if (parsed !== null && typeof parsed === 'object') {
      collect(parsed, 0);
    }
  } catch (_e) {
  }
  return names.join(',');
}

/** 飞牛官方上传前存在性检查结果 */
export type PhotoUploadExistCheck = 'exists' | 'missing' | 'unknown';

export class FnHttpClientUploadOps {
  /** 入库通知串行。四路上传同时 notice 时飞牛会回 system busy。 */
  private static noticeTail: Promise<void> = Promise.resolve();
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
   * 一次 open 读出全文 + 修改时间，供 /upload 的 Trim-Mtim、Trim-Sign 与 notice 使用。
   * 文件 IO 在 TaskPool 执行，避免主线程同步读整图冻 UI。
   */
  private static async readUploadFileAndMtime(uri: string): Promise<UploadFileReadResult | undefined> {
    try {
      const pack = await taskpool.execute(readUploadFileAndMtimeConcurrent, uri) as UploadFileReadResult;
      if (pack.buffer.byteLength <= 0) {
        return undefined;
      }
      return pack;
    } catch (e) {
      fnDiagError(TAG, 'upload taskpool read fail', e);
      return undefined;
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

  private static isDuplicateUploadMessage(msg: string): boolean {
    const text = msg.trim();
    if (text.length === 0) {
      return false;
    }
    const lower = text.toLowerCase();
    return lower.indexOf('duplicate') >= 0 || lower.indexOf('already') >= 0 ||
      text.indexOf('重复') >= 0 || text.indexOf('已存在') >= 0 || text.indexOf('已上传') >= 0;
  }

  private static appendUploadOrigin(list: string[], raw: string): void {
    let u = raw.trim();
    if (u.length > 1 && u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.length === 0 || isFnRelayBaseUrl(u) || list.indexOf(u) >= 0) {
      return;
    }
    list.push(u);
  }

  /**
   * 当前会话在前。走飞牛中继时先打中继，Cookie 带 mode=relay，由中继把 /upload 转到 NAS。
   * 本机地址只在中继上传失败后才试。
   */
  private collectUploadOrigins(webHttpsBase: string, sessionNorm: string): string[] {
    const list: string[] = [];
    if (isFnRelayBaseUrl(sessionNorm) && sessionNorm.length > 0) {
      list.push(sessionNorm);
    } else {
      FnHttpClientUploadOps.appendUploadOrigin(list, webHttpsBase);
      FnHttpClientUploadOps.appendUploadOrigin(list, sessionNorm);
      FnHttpClientUploadOps.appendUploadOrigin(list, fnWebUiBaseUrl(sessionNorm, false));
    }
    const directs = this.host.getDirectUploadBases();
    for (let i = 0; i < directs.length; i++) {
      const one = directs[i];
      if (isFnRelayBaseUrl(one)) {
        continue;
      }
      FnHttpClientUploadOps.appendUploadOrigin(list, fnWebUiBaseUrl(one, false));
      FnHttpClientUploadOps.appendUploadOrigin(list, one);
      FnHttpClientUploadOps.appendUploadOrigin(list, fnWebViewBaseUrl(one));
    }
    return list;
  }

  /** /upload 打到网页入口时会回相册首页 HTML，不能当成文件已经落盘。 */
  private static uploadBodyLooksLikeSpa(body: string): boolean {
    const head = body.trimStart().substring(0, 64).toLowerCase();
    return head.startsWith('<!doctype') || head.startsWith('<html');
  }

  /**
   * 从非 2xx 响应头里挑出可能带错误码的项（不记录 Cookie/Token 等敏感值）。
   * 403 在飞牛有多重成因，响应头若带 errno 之类就能进一步定位。
   */
  private static errorHeaderHint(headers: Object): string {
    const out: string[] = [];
    try {
      const rec = headers as Record<string, Object | undefined>;
      const keys: string[] = Object.keys(rec);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i].toLowerCase();
        if (k.indexOf('cookie') >= 0 || k.indexOf('token') >= 0 || k.indexOf('auth') >= 0 ||
          k.indexOf('session') >= 0) {
          continue;
        }
        if (k.indexOf('err') >= 0 || k.indexOf('code') >= 0 || k.indexOf('reason') >= 0 ||
          k.indexOf('message') >= 0 || k.indexOf('status') >= 0) {
          const v = rec[keys[i]];
          if (typeof v === 'string' && v.length > 0) {
            out.push(`${keys[i]}=${v.substring(0, 60)}`);
          }
        }
      }
    } catch (_e) {
    }
    return out.join('; ');
  }

  /** 飞牛相册入库锁被占用时的文案。这时换请求体没有用，只能等锁放开再发同一份。 */
  private static isBusyNoticeMessage(msg: string): boolean {
    const text = msg.trim().toLowerCase();
    if (text.length === 0) {
      return false;
    }
    return text.indexOf('system busy') >= 0 || text.indexOf('busy') >= 0 || text.indexOf('系统繁忙') >= 0;
  }

  private static enqueueNotice(job: () => Promise<UploadNoticeResult>): Promise<UploadNoticeResult> {
    const prev = FnHttpClientUploadOps.noticeTail;
    let done: (result: UploadNoticeResult) => void = (_result: UploadNoticeResult): void => {};
    const gate = new Promise<UploadNoticeResult>((resolve: (result: UploadNoticeResult) => void) => {
      done = resolve;
    });
    const run = (): Promise<void> => {
      return job().then((result: UploadNoticeResult): void => {
        done(result);
      }, (): void => {
        fnDiagRecord('W', TAG, 'notice job reject');
        const fail: UploadNoticeResult = { ok: false, message: '入库通知失败' };
        done(fail);
      });
    };
    FnHttpClientUploadOps.noticeTail = prev.then(run, run);
    return gate;
  }

  private static parseUploadExistFromBody(rawBody: string): PhotoUploadExistCheck {
    if (rawBody.length === 0) {
      return 'unknown';
    }
    if (FnHttpClientUploadOps.isDuplicateUploadMessage(rawBody)) {
      return 'exists';
    }
    let parsed: Record<string, string | number | boolean | Object | undefined>;
    try {
      parsed = JSON.parse(rawBody) as Record<string, string | number | boolean | Object | undefined>;
    } catch (_e) {
      return 'unknown';
    }
    const scan = (obj: Record<string, string | number | boolean | Object | undefined>): PhotoUploadExistCheck => {
      const flags = ['exist', 'exists', 'duplicate', 'duplicated', 'skip', 'skipped', 'isExist', 'is_exists'];
      for (let i = 0; i < flags.length; i++) {
        const v = obj[flags[i]];
        if (v === true || v === 1 || v === '1' || v === 'true') {
          return 'exists';
        }
      }
      const missFlags = ['needUpload', 'need_upload', 'shouldUpload'];
      for (let j = 0; j < missFlags.length; j++) {
        const mv = obj[missFlags[j]];
        if (mv === true || mv === 1 || mv === '1' || mv === 'true') {
          return 'missing';
        }
      }
      return 'unknown';
    };
    const root = scan(parsed);
    if (root !== 'unknown') {
      return root;
    }
    const dataObj = parsed['data'];
    if (dataObj !== undefined && dataObj !== null && typeof dataObj === 'object' && !Array.isArray(dataObj)) {
      return scan(dataObj as Record<string, string | number | boolean | Object | undefined>);
    }
    return 'unknown';
  }

  /**
   * 上传前向 NAS 查询是否已存在（对齐官方 upload/path / upload/check）。
   * 无法判定时返回 unknown，由客户端指纹索引兜底。
   */
  async checkPhotoUploadExists(
    originalName: string,
    fileSize: number,
    mtimeSec: number,
    timeoutMs: number = 15000
  ): Promise<PhotoUploadExistCheck> {
    const name = originalName.trim();
    if (name.length === 0 || fileSize <= 0) {
      return 'unknown';
    }
    const activeBase = fnWebViewBaseUrl(this.baseUrl);
    const cookie = mergeGalleryWebCookieIntoNativeHeader(
      buildFnApiCookieHeader(this.token, this.longToken),
      activeBase
    );
    const pathBases: string[] = [
      `${FN_PHOTO_API_V2_PREFIX}/photo/upload/check`,
      `${FN_PHOTO_API_V2_PREFIX}/photo/upload/exists`,
      `${FN_PHOTO_API_V2_PREFIX}/photo/upload/path`,
      `${FN_PHOTO_API_PREFIX}/photo/upload/path`
    ];
    const fc = FnHttpClientUploadOps.formatNoticeFileCreateTime(String(mtimeSec));
    const paramsCandidates: Array<Record<string, string | number | boolean>> = [
      { 'original_name': name, 'file_size': fileSize, 'file_create_time': fc, 'mtime': mtimeSec },
      { 'fileName': name, 'fileSize': fileSize, 'mtime': mtimeSec, 'file_create_time': fc },
      { 'name': name, 'size': fileSize, 'mtime': mtimeSec },
      { 'filename': name, 'file_size': fileSize },
      { 'name': name }
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
          const exist = FnHttpClientUploadOps.parseUploadExistFromBody(raw.body);
          if (exist !== 'unknown') {
            return exist;
          }
        } catch (_e) {}
      }
    }
    fnDiagRecord('W', TAG, 'upload exists probe exhausted');
    return 'unknown';
  }

  /**
   * 对齐 Web 侧上传前预请求：
   * GET /p/api/v2 或 v1 /photo/upload/path（不同 NAS 版本只实现其一）。
   * 返回可用的路径提示（若服务端未返回则为空串，不阻断上传）。
   */
  private static appendAlbumBackupPolicyJsonFields(bodyJson: string): string {
    const trimmed = bodyJson.trim();
    if (trimmed.length < 2 || !trimmed.endsWith('}')) {
      return bodyJson;
    }
    const s = getAlbumBackupSettingsCached();
    const inner = trimmed.substring(0, trimmed.length - 1);
    const comma = inner.endsWith('{') ? '' : ',';
    // album_id 不再塞进上传体：相册归档统一走 /gallery/addTo/album（按本机相册名建同名相册）。
    const extra =
      `${comma}"folder_manage_mode":${s.folderManageMode},"rename_strategy":${s.renameStrategy}`;
    return `${inner}${extra}}`;
  }

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
    const backup = getAlbumBackupSettingsCached();
    const paramsCandidates: Array<Record<string, string | number | boolean>> = [
      GALLERY_QUERY_EMPTY,
      { 'name': fileName },
      { 'fileName': fileName },
      { 'filename': fileName },
      {
        'name': fileName,
        'folder_manage_mode': backup.folderManageMode,
        'rename_strategy': backup.renameStrategy
      }
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
    fnDiagRecord('W', TAG, 'upload path hint probe exhausted');
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
          fnDiagRecord('W', TAG, 'restore parse fail');
          continue;
        }
        if (FnHttpClientUploadOps.galleryEnvelopeBizOk(parsed)) {
          return true;
        }
      } catch (_e) {}
    }
    fnDiagRecord('W', TAG, 'restore call fail');
    return false;
  }

  private async notifyPhotoUploaded(
    fileName: string,
    sourceUri: string,
    timeoutMs: number,
    pathHints: string[] = [],
    uploadMtimSec: string = '',
    hintedFullPathPlain: string = '',
    fileSize: number = 0
  ): Promise<UploadNoticeResult> {
    const activeBase = fnWebViewBaseUrl(this.baseUrl);
    const path = `${FN_PHOTO_API_PREFIX}/photo/upload/notice`;
    const cookie = mergeGalleryWebCookieIntoNativeHeader(
      buildFnApiCookieHeader(this.token, this.longToken),
      activeBase
    );
    const escName = escapeJsonString(fileName);
    const bodyCandidates: string[] = [];
    const pushCandidate = (v: string): void => {
      const withPolicy = FnHttpClientUploadOps.appendAlbumBackupPolicyJsonFields(v);
      if (bodyCandidates.indexOf(withPolicy) < 0) {
        bodyCandidates.push(withPolicy);
      }
    };
    // 服务端要求 files 非空，并且要能对上刚才 /upload 落到磁盘的那份文件。
    // 不带 files 的请求体只会得到 "files can not be empty"，不再发送。
    const mtimForNotice = uploadMtimSec.trim().length > 0 ? uploadMtimSec.trim() : String(Math.floor(Date.now() / 1000));
    const fc = FnHttpClientUploadOps.formatNoticeFileCreateTime(mtimForNotice);
    const seg = lastUnixPathSegment(hintedFullPathPlain);
    const escFileOnDisk = seg.length > 0 ? escapeJsonString(seg) : escName;
    const sizeNum = Number.isFinite(fileSize) && fileSize > 0 ? Math.floor(fileSize) : 0;
    const fullPath = hintedFullPathPlain.trim();
    if (fullPath.length > 0) {
      const escPath = escapeJsonString(fullPath);
      pushCandidate(
        `{"files":[{"path":"${escPath}","file":"${escPath}",` +
        `"file_create_time":"${fc}","fileCreateTime":"${fc}",` +
        `"original_name":"${escName}","originalName":"${escName}",` +
        `"file_name":"${escFileOnDisk}","fileName":"${escFileOnDisk}",` +
        `"file_size":${sizeNum},"fileSize":${sizeNum}}]}`
      );
      pushCandidate(`{"files":["${escPath}"]}`);
    }
    pushCandidate(
      `{"files":[{"file_create_time":"${fc}","fileCreateTime":"${fc}",` +
      `"original_name":"${escName}","originalName":"${escName}",` +
      `"file_name":"${escFileOnDisk}","fileName":"${escFileOnDisk}",` +
      `"file_size":${sizeNum},"fileSize":${sizeNum}}]}`
    );
    pushCandidate(
      `{"files":[{"file_create_time":"${fc}","fileCreateTime":"${fc}",` +
      `"original_name":"${escName}","originalName":"${escName}",` +
      `"file_name":"${escName}","fileName":"${escName}",` +
      `"file_size":${sizeNum},"fileSize":${sizeNum}}]}`
    );
    for (let i = 0; i < pathHints.length; i++) {
      const p = pathHints[i].trim();
      if (p.length === 0 || p === fullPath) {
        continue;
      }
      const ep = escapeJsonString(p);
      pushCandidate(
        `{"files":[{"path":"${ep}","file":"${ep}",` +
        `"file_create_time":"${fc}","fileCreateTime":"${fc}",` +
        `"original_name":"${escName}","originalName":"${escName}",` +
        `"file_name":"${escFileOnDisk}","fileName":"${escFileOnDisk}",` +
        `"file_size":${sizeNum},"fileSize":${sizeNum}}]}`
      );
    }
    let lastMsg = '入库通知失败';
    let noticePhotoId = '';
    const busyWaits: number[] = [800, 1600, 3200, 4800];
    for (let i = 0; i < bodyCandidates.length; i++) {
      const bodyStr = bodyCandidates[i];
      let stopCandidates = false;
      for (let attempt = 0; attempt <= busyWaits.length; attempt++) {
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
            lastMsg = `notice HTTP ${raw.code}`;
            break;
          }
          let parsed: Record<string, string | number | Object | undefined>;
          try {
            parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
          } catch (_e) {
            lastMsg = 'notice 响应解析失败';
            break;
          }
          if (!FnHttpClientUploadOps.galleryEnvelopeBizOk(parsed)) {
            const em = FnHttpClientUploadOps.envelopeErrorLine(parsed);
            lastMsg = em.length > 0 ? em : 'notice 业务失败';
            const preview = raw.body.length > 180 ? raw.body.substring(0, 180) : raw.body;
            fnDiagRecord('W', TAG, `notice fail i=${i} try=${attempt} ${lastMsg} bodyLen=${preview.length}`);
            if (FnHttpClientUploadOps.isBusyNoticeMessage(lastMsg) && attempt < busyWaits.length) {
              await FnHttpClientUploadOps.sleep(busyWaits[attempt]);
              continue;
            }
            stopCandidates = FnHttpClientUploadOps.isBusyNoticeMessage(lastMsg);
            break;
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
                if (noticePhotoId.length === 0) {
                  const idRaw = fr['id'] ?? fr['photoId'] ?? fr['itemId'] ?? fr['fileId'];
                  if (idRaw !== undefined && idRaw !== null) {
                    const idText = String(idRaw).trim();
                    if (idText.length > 0 && idText !== 'null' && idText !== 'undefined') {
                      noticePhotoId = idText;
                    }
                  }
                }
                const errTxtRaw = fr['error'];
                const errTxt = errTxtRaw !== undefined && errTxtRaw !== null ? String(errTxtRaw).trim() : '';
                const errCodeRaw = fr['errorCode'];
                const errCode = errCodeRaw !== undefined && Number.isFinite(Number(errCodeRaw))
                  ? Math.floor(Number(errCodeRaw))
                  : 0;
                if (errTxt.length > 0 || errCode !== 0) {
                  if (FnHttpClientUploadOps.isDuplicateUploadMessage(errTxt)) {
                    const dupRes: UploadNoticeResult = { ok: true, message: '已存在', photoId: noticePhotoId };
                    return dupRes;
                  }
                  lastMsg = errTxt.length > 0 ? errTxt : `notice errorCode=${errCode}`;
                  const preview = raw.body.length > 180 ? raw.body.substring(0, 180) : raw.body;
                  if (attempt === 0) {
                    fnDiagRecord('W', TAG, `notice req i=${i} fields=${jsonFieldNamesOf(bodyStr)} len=${bodyStr.length}`);
                  }
                  fnDiagRecord('W', TAG, `notice item fail i=${i} try=${attempt} ${lastMsg} bodyLen=${preview.length}`);
                  if (FnHttpClientUploadOps.isBusyNoticeMessage(lastMsg) && attempt < busyWaits.length) {
                    await FnHttpClientUploadOps.sleep(busyWaits[attempt]);
                    continue;
                  }
                  stopCandidates = FnHttpClientUploadOps.isBusyNoticeMessage(lastMsg);
                  break;
                }
              }
            }
          }
          const okRes: UploadNoticeResult = { ok: true, message: '', photoId: noticePhotoId };
          return okRes;
        } catch (e) {
          lastMsg = fnNetErrorText(e, 'notice 请求异常');
          fnDiagError(TAG, 'notice request exception', e);
          break;
        }
      }
      if (stopCandidates) {
        break;
      }
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
    albumUploadDirHint?: string,
    forceDirHint: boolean = false
  ): Promise<FnClientResult<Object>> {
    const oneUri = uri.trim();
    if (oneUri.length === 0) {
      hilog.warn(DOMAIN, TAG, '[upload] abort empty uri');
      return { success: false, message: '文件 URI 为空' };
    }
    hilog.warn(DOMAIN, TAG, '[upload] enter uriLen=%{public}d timeoutMs=%{public}d', oneUri.length, timeoutMs);
    const filePack = await FnHttpClientUploadOps.readUploadFileAndMtime(oneUri);
    if (filePack === undefined || filePack.buffer.byteLength <= 0) {
      hilog.warn(DOMAIN, TAG, '[upload] abort read file failed uriLen=%{public}d', oneUri.length);
      return { success: false, message: '读取待上传文件失败' };
    }
    const payload = filePack.buffer;
    const fileName = FnHttpClientUploadOps.fileNameFromUri(oneUri);
    let pathHintBeforeUpload = '';
    // forceDirHint：备份目录偏好不是「默认」时，必须用客户端按偏好算出来的目录，
    // 不能被 NAS 的 upload/path 提示（形如 <库根>/PhotoLibrary/YYYY/MM）覆盖。
    if (!forceDirHint) {
      // 「默认」档走官方流程：先落到 <备份位置>/.@#local 中转目录，再由 notice 让 NAS 归档。
      const stagingDir = albumUploadDirHint !== undefined ? albumUploadDirHint.trim() : '';
      if (stagingDir.length > 0) {
        pathHintBeforeUpload = `${stagingDir}/.@#local`;
      } else {
        pathHintBeforeUpload = await this.requestUploadPathHint(fileName, Math.min(15000, timeoutMs));
      }
    }
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
    const uploadOrigins = this.collectUploadOrigins(webHttpsBase, sessionNorm);
    const maskedOrigins: string[] = [];
    for (let oi = 0; oi < uploadOrigins.length; oi++) {
      maskedOrigins.push(fnDiagMaskUrl(uploadOrigins[oi]));
    }
    fnDiagRecord('I', TAG, `upload origins ${maskedOrigins.length > 0 ? maskedOrigins.join(' | ') : '(none)'}`);
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
      /** lastDetail 是否来自非 JSON 响应原文（含路径时只记长度） */
      let lastDetailIsRawBody = false;
      let softUploadAccepted = false;
      let lastCookieForLog = '';
      let lastUploadUrl = '';
      /**
       * 逐次尝试的失败清单。
       * 之前只留 lastHttpCode/lastDetail（且不按 origin 重置），语义是"最后一次尝试"，
       * 真实首因（通常是内网 origin 的连接异常）会被后面 origin 的状态码整个覆盖，
       * 用户和排查者都只能看到最后那个 origin 的码。
       */
      const attemptFails: UploadAttemptFail[] = [];
      outerUpload:
      for (let bi = 0; bi < uploadOrigins.length; bi++) {
        const originBase = uploadOrigins[bi];
        const uploadUrl = `${originBase}${uploadPath}`;
        const relayUpload = isFnRelayBaseUrl(originBase);
        const uploadCookieBase = relayUpload
          ? buildFnApiCookieHeader(this.token, this.longToken)
          : buildUploadCookieHeader(this.token, this.longToken);
        const uploadCookieMerged = mergeGalleryWebCookieIntoNativeHeader(uploadCookieBase, originBase);
        const uploadCookie = relayUpload ? uploadCookieMerged : stripUploadForbiddenCookieKeys(uploadCookieMerged);
        const uploadReferer = `${originBase}${FN_PHOTO_H5_ALBUM_PAGE}`;
        lastCookieForLog = uploadCookie;
        lastUploadUrl = uploadUrl;
        hilog.warn(
          DOMAIN,
          TAG,
          '[upload] start origin=%{public}s url=%{public}s nameLen=%{public}d bytes=%{public}d pathHint=%{public}s cookieKeys=%{public}s referer=%{public}s',
          fnDiagMaskUrl(originBase),
          fnDiagMaskUrl(uploadUrl),
          fileName.length,
          payload.byteLength,
          pathHintBeforeUpload.length > 0 ? fnDiagMaskPath(pathHintBeforeUpload) : '(none)',
          cookieKeysSummary(uploadCookie),
          fnDiagMaskUrl(uploadReferer)
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
            connectTimeout: Math.min(12000, timeoutMs),
            readTimeout: timeoutMs,
            extraData: multipart.body
          };
          if (CertPolicy.isTrusted(this.baseUrl) || CertPolicy.isTrusted(originBase) || originBase.startsWith('http://')) {
            opt.remoteValidation = 'skip';
          }
          let rawResp: http.HttpResponse;
          try {
            rawResp = await req.request(uploadUrl, opt);
          } catch (e) {
            // NetStack 异常是 BusinessError，直接 String(e) 只有 "[object Object]"，错误码会丢。
            const parts = fnNetErrorParts(e);
            const detail = parts.message.length > 0 ? parts.message : '连接异常';
            attemptFails.push({ origin: originBase, kind: 'exception', httpCode: 0, detail: detail });
            lastDetail = detail;
            fnDiagError(TAG, `upload origin fail url=${fnDiagMaskUrl(uploadUrl)} code=${parts.code}`, e);
            break;
          }
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
                lastDetailIsRawBody = true;
                lastDetail = uploadRespText.length > 120 ? `${uploadRespText.substring(0, 120)}...` : uploadRespText;
              }
            }
            attemptFails.push({
              origin: originBase,
              kind: 'http',
              httpCode: code,
              detail: lastDetail
            });
            if (code === 403) {
              // 403 在飞牛有多重成因（空间不足 / 目录权限 / 目录路径不合法 / Cookie 被精简），
              // 响应头里若带 errno 之类就留个证据，便于进一步定位到底是哪一种。
              const hint = FnHttpClientUploadOps.errorHeaderHint(rawResp.header);
              if (hint.length > 0) {
                fnDiagRecord('W', TAG, `upload 403 header hint ${hint}`);
              }
            }
            continue;
          }
          if (FnHttpClientUploadOps.uploadBodyLooksLikeSpa(uploadRespText)) {
            lastDetail = '上传接口返回了网页';
            attemptFails.push({ origin: originBase, kind: 'http', httpCode: code, detail: lastDetail });
            fnDiagRecord('W', TAG, `upload spa shell url=${fnDiagMaskUrl(uploadUrl)} http=${code}`);
            break;
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
                attemptFails.push({ origin: originBase, kind: 'biz', httpCode: code, detail: lastDetail });
                continue;
              }
            } catch (_e) {
              fnDiagRecord('W', TAG, 'upload resp parse fail');
            }
          }
          uploadOk = true;
          fnDiagRecord('I', TAG, `upload ok url=${fnDiagMaskUrl(uploadUrl)} bytes=${payload.byteLength} respLen=${uploadRespText.length}`);
          break outerUpload;
        }
      }
      if (!uploadOk) {
        if (softUploadAccepted && lastHttpCode >= 200 && lastHttpCode < 300) {
          // 走后续 notice/verify 流程，由入库侧再确认最终结果。
        } else {
          const bodyPrev =
            uploadRespText.length > 256 ? `${uploadRespText.substring(0, 256)}…` : uploadRespText;
          // 主因优先取"服务端给的判定"（HTTP 非 2xx / 业务错误），
          // 没有才取连接层异常 —— 服务端的判定才是可执行的原因。
          let primary: UploadAttemptFail | undefined = undefined;
          for (let i = 0; i < attemptFails.length; i++) {
            if (attemptFails[i].kind !== 'exception') {
              primary = attemptFails[i];
              break;
            }
          }
          if (primary === undefined && attemptFails.length > 0) {
            primary = attemptFails[0];
          }
          const attemptSummary = attemptFails
            .map((f: UploadAttemptFail): string => {
              const one = f.kind === 'exception'
                ? '连接异常'
                : (f.kind === 'biz' ? `业务错误${f.detail.length > 0 ? ':' + f.detail : ''}` : `HTTP${f.httpCode}`);
              return `${fnDiagMaskUrl(f.origin)}=${one}`;
            })
            .join('|');
          fnDiagRecord('W', TAG, `upload POST failed attempts=${attemptSummary}`);
          hilog.warn(
            DOMAIN,
            TAG,
            '[upload] POST /upload failed url=%{public}s http=%{public}d detail=%{public}s trimPathLen=%{public}d sign×origins=%{public}d×%{public}d cookie(redacted)=%{public}s bodyLen=%{public}d attempts=%{public}s',
            lastUploadUrl.length > 0 ? fnDiagMaskUrl(lastUploadUrl) : '(none)',
            primary !== undefined ? primary.httpCode : lastHttpCode,
            primary !== undefined ? primary.detail : (lastDetail.length > 0 ? lastDetail : '(none)'),
            encodedTrimPath.length,
            allSigns.length,
            uploadOrigins.length,
            redactCookieHeaderForLog(lastCookieForLog),
            bodyPrev.length,
            attemptSummary.length > 0 ? attemptSummary : '(none)'
          );
          let msg = '上传失败';
          if (primary !== undefined) {
            if (primary.kind === 'exception') {
              msg = `上传失败：连接 ${fnDiagMaskUrl(primary.origin)} 出错（${primary.detail}）`;
            } else if (primary.kind === 'biz') {
              msg = `上传失败：${primary.detail.length > 0 ? primary.detail : 'NAS 拒绝了该请求'}`;
            } else {
              msg = `上传失败 ${fnHttpStatusMessage(primary.httpCode)}`;
              if (primary.detail.length > 0) {
                msg += `：${primary.detail}`;
              }
            }
            if (attemptFails.length > 1) {
              msg += `（另有 ${attemptFails.length - 1} 次其它地址尝试失败，详见诊断日志）`;
            }
          } else {
            msg = `上传失败 ${fnHttpStatusMessage(lastHttpCode)}`;
          }
          return {
            success: false,
            message: msg
          };
        }
      }
    } catch (e) {
      const em = fnNetErrorText(e, '上传请求异常');
      hilog.warn(DOMAIN, TAG, '[upload] exception %{public}s', em.length > 0 ? em : 'unknown');
      const safeEm = em.split(oneUri).join('<local-uri>');
      fnDiagError(TAG, `upload exception ${safeEm.length > 0 ? safeEm.substring(0, 160) : 'unknown'}`, e);
      return { success: false, message: em.length > 0 ? em : '上传请求异常' };
    } finally {
      this.unregisterPendingRequest(req);
      try {
        req.destroy();
      } catch (_e) {}
    }
    // 客户端指定目录的档位（按拍摄日期 / 按设备文件夹 / 保存在一个文件夹下）：
    // 文件已经被 Trim-Path 直接写到最终目录，不在 <库根>/.@#local 中转目录里，
    // 服务端 notice 找不到文件只会回 system busy，重试无用 → 直接跳过 notice。
    // 代价：照片 id 要等 NAS 扫盘才生成，因此这条路径不能在上传当下建相册。
    if (forceDirHint) {
      hilog.warn(DOMAIN, TAG, '[upload] client-dir mode, notice skipped');
      fnDiagRecord('I', TAG, 'upload landed to client dir, notice skipped');
      return { success: true, message: '已落盘，待 NAS 扫描入库', uploadedPhotoId: '' };
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
    const noticeRes = await FnHttpClientUploadOps.enqueueNotice((): Promise<UploadNoticeResult> => {
      return this.notifyPhotoUploaded(
        fileName,
        oneUri,
        noticeTimeout,
        noticePathHints,
        trimMtim,
        hintedFullPath,
        payload.byteLength
      );
    });
    let noticed = noticeRes.ok;
    let failReason = noticeRes.message;
    let uploadPhotoId = noticeRes.photoId !== undefined && noticeRes.photoId.length > 0
      ? noticeRes.photoId
      : FnHttpClientUploadOps.firstUploadPhotoIdFromResponse(uploadRespText);
    if (!noticed) {
      // 上传成功但 notice 失败时，尝试用上传响应里的 photoId 做 restore 兼容兜底。
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
      if (FnHttpClientUploadOps.isDuplicateUploadMessage(failReason)) {
        return { success: true, message: '照片已存在', uploadedPhotoId: uploadPhotoId };
      }
      const verified = await this.verifyUploadedAppeared(fileName, payload.byteLength);
      if (verified) {
        return { success: true, message: '上传成功（已入库）', uploadedPhotoId: uploadPhotoId };
      }
      const em = failReason.length > 0 ? `上传完成但入库通知失败：${failReason}` : '上传完成但入库通知失败';
      const maskedHints: string[] = [];
      for (let hi = 0; hi < noticePathHints.length; hi++) {
        maskedHints.push(fnDiagMaskPath(noticePathHints[hi]));
      }
      const hintsStr =
        maskedHints.length > 0 ? maskedHints.join(' | ') : '(none)';
      const uploadPreviewLen = uploadRespText.length;
      hilog.warn(
        DOMAIN,
        TAG,
        '[upload] notice/verify failed reason=%{public}s pathHints=%{public}s uploadBodyLen=%{public}d',
        failReason.length > 0 ? failReason : '(empty)',
        hintsStr,
        uploadPreviewLen
      );
      fnDiagRecord('W', TAG, `notice/verify failed ${failReason} hints=${hintsStr} uploadLen=${uploadPreviewLen}`);
      return { success: false, message: em };
    }
    return { success: true, uploadedPhotoId: uploadPhotoId };
  }
}
