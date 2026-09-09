import { http } from '@kit.NetworkKit';
import { CertPolicy } from '../CertPolicy';
import { buildGallerySortedQuery, FnGalleryGetSignSpec, genFnGalleryAuthxPostRaw } from '../FnGalleryAuthx';
import { FN_PHOTO_API_PREFIX } from '../FnPhotoRoutes';
import { mergeGalleryWebCookieIntoNativeHeader } from '../FnWebCookies';
import { fnWebViewBaseUrl } from '../ServerUrl';
import { buildFnApiCookieHeader } from './FnHttpClientCookie';
import {
  RECYCLE_BIN_LIST_SIGN_PATH,
  escapeJsonString,
} from './FnHttpClientCommon';
import { FnHttpClientGalleryHost } from './FnHttpClientTypes';
import { FnHttpClientGalleryRequest } from './FnHttpClientGalleryRequest';
import {
  FnClientResult,
  RecycleBinListData
} from '../../model/FnApiTypes';

export class FnHttpClientRecycleOps extends FnHttpClientGalleryRequest {
  constructor(host: FnHttpClientGalleryHost) {
    super(host);
  }

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
          if (FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
            return { success: true, data: parsed['data'] as Object };
          }
          const errLine = FnHttpClientGalleryRequest.envelopeErrorLine(parsed);
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
          if (FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
            return { success: true, data: parsed['data'] as Object };
          }
          const errLine = FnHttpClientGalleryRequest.envelopeErrorLine(parsed);
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
          if (FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
            return { success: true, data: parsed['data'] as Object };
          }
          const errLine = FnHttpClientGalleryRequest.envelopeErrorLine(parsed);
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
      if (FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
        return { success: true, data: parsed['data'] as Object };
      }
      const errLine = FnHttpClientGalleryRequest.envelopeErrorLine(parsed);
      return { success: false, message: errLine.length > 0 ? errLine : '恢复失败' };
    } catch (e) {
      return { success: false, message: String(e) || '恢复请求异常' };
    }
  }
}
