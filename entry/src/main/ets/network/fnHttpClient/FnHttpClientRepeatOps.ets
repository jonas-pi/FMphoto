import { http } from '@kit.NetworkKit';
import { CertPolicy } from '../CertPolicy';
import { buildGallerySortedQuery, FnGalleryGetSignSpec, genFnGalleryAuthxPostRaw } from '../FnGalleryAuthx';
import { fnWebViewBaseUrl } from '../ServerUrl';
import { mergeGalleryWebCookieIntoNativeHeader } from '../FnWebCookies';
import { buildFnApiCookieHeader } from './FnHttpClientCookie';
import {
  GALLERY_QUERY_EMPTY,
  REPEAT_PHOTO_CHECK_PATH,
  REPEAT_PHOTO_EXCLUDE_PATH,
  REPEAT_PHOTO_GROUP_PATH_CANDIDATES,
  REPEAT_PHOTO_GROUP_SIGN_PATH,
  REPEAT_PHOTO_KEEP_PATH,
  REPEAT_PHOTO_LIST_PATH_CANDIDATES,
  REPEAT_PHOTO_LIST_SIGN_PATH,
  REPEAT_PHOTO_MERGE_PATH,
  TASK_PANEL_LIST_PATH_CANDIDATES,
  TASK_PANEL_LIST_SIGN_PATH,
  escapeJsonString
} from './FnHttpClientCommon';
import { FnHttpClientGalleryHost } from './FnHttpClientTypes';
import { FnHttpClientGalleryRequest } from './FnHttpClientGalleryRequest';
import {
  FnClientResult,
  RepeatPhotoGroup,
  RepeatPhotoListData,
  RepeatPhotoMergeData,
  RepeatPhotoTaskProgress
} from '../../model/FnApiTypes';
import {
  jsonScalarId,
  parseRepeatPhotoGroup,
  parseRepeatPhotoListData,
  parseRepeatPhotoMergeData,
  parseRepeatPhotoTaskProgress
} from './FnRepeatPhotoParse';

export class FnHttpClientRepeatOps extends FnHttpClientGalleryRequest {
  constructor(host: FnHttpClientGalleryHost) {
    super(host);
  }

  async getRepeatPhotoList(
    offset: number,
    size: number,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<RepeatPhotoListData>> {
    const params: Record<string, string | number | boolean> = {};
    params['offset'] = offset;
    params['size'] = size;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [];
    for (let i = 0; i < REPEAT_PHOTO_LIST_PATH_CANDIDATES.length; i++) {
      pathCandidates.push(`${REPEAT_PHOTO_LIST_PATH_CANDIDATES[i]}?${qs}`);
    }
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: REPEAT_PHOTO_LIST_SIGN_PATH,
      queryParams: params
    };
    const res = await this.requestGalleryGetJson<Object>(pathCandidates, gallerySign, timeoutMs, 3);
    if (!res.success) {
      return { success: false, message: res.message, errorBodyPreview: res.errorBodyPreview };
    }
    return { success: true, data: parseRepeatPhotoListData(res.data) };
  }

  async getRepeatPhotoGroup(groupId: string, timeoutMs: number = 15000): Promise<FnClientResult<RepeatPhotoGroup>> {
    const id = groupId.trim();
    if (id.length === 0) {
      return { success: false, message: 'groupId 不能为空' };
    }
    const params: Record<string, string | number | boolean> = {};
    params['groupId'] = id;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [];
    for (let i = 0; i < REPEAT_PHOTO_GROUP_PATH_CANDIDATES.length; i++) {
      pathCandidates.push(`${REPEAT_PHOTO_GROUP_PATH_CANDIDATES[i]}?${qs}`);
    }
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: REPEAT_PHOTO_GROUP_SIGN_PATH,
      queryParams: params
    };
    const res = await this.requestGalleryGetJson<Object>(pathCandidates, gallerySign, timeoutMs, 3);
    if (!res.success) {
      return { success: false, message: res.message, errorBodyPreview: res.errorBodyPreview };
    }
    const group = parseRepeatPhotoGroup(res.data);
    if (group === undefined) {
      return { success: false, message: '组数据为空' };
    }
    return { success: true, data: group };
  }

  async getTaskPanelList(timeoutMs: number = 15000): Promise<FnClientResult<RepeatPhotoTaskProgress>> {
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: TASK_PANEL_LIST_SIGN_PATH,
      queryParams: GALLERY_QUERY_EMPTY
    };
    const res = await this.requestGalleryGetJson<Object>(TASK_PANEL_LIST_PATH_CANDIDATES, gallerySign, timeoutMs, 2);
    if (!res.success) {
      return { success: false, message: res.message, errorBodyPreview: res.errorBodyPreview };
    }
    return { success: true, data: parseRepeatPhotoTaskProgress(res.data) };
  }

  /**
   * 官方 similarApi：startCheckSimilar / startCheckRepeat 同走 `/repeat-photo/check`，
   * 仅 body.checkSimilarity 不同。
   */
  async startRepeatPhotoCheck(
    checkSimilarity: boolean,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<Object>> {
    const bodyStr = checkSimilarity ? '{"checkSimilarity":true}' : '{"checkSimilarity":false}';
    return this.postRepeatJson(REPEAT_PHOTO_CHECK_PATH, bodyStr, timeoutMs, '启动检查失败');
  }

  async keepRepeatPhoto(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    const id = photoId.trim();
    if (id.length === 0) {
      return { success: false, message: 'photoId 不能为空' };
    }
    return this.postRepeatJson(REPEAT_PHOTO_KEEP_PATH, `{"photoId":${this.jsonId(id)}}`, timeoutMs, '更改推荐保留项失败');
  }

  async excludeRepeatPhoto(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    const id = photoId.trim();
    if (id.length === 0) {
      return { success: false, message: 'photoId 不能为空' };
    }
    return this.postRepeatJson(
      REPEAT_PHOTO_EXCLUDE_PATH,
      `{"type":"PhotoId","photoIds":[${this.jsonId(id)}]}`,
      timeoutMs,
      '保留失败'
    );
  }

  async excludeRepeatPhotoGroup(groupId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    const id = groupId.trim();
    if (id.length === 0) {
      return { success: false, message: 'groupId 不能为空' };
    }
    return this.postRepeatJson(
      REPEAT_PHOTO_EXCLUDE_PATH,
      `{"type":"Group","groupId":${this.jsonId(id)}}`,
      timeoutMs,
      '保留此组失败'
    );
  }

  async mergeRepeatPhotos(
    groupId: string,
    timeoutMs: number = 30000
  ): Promise<FnClientResult<RepeatPhotoMergeData>> {
    const id = groupId.trim();
    const bodyStr = id.length > 0 ?
      `{"type":"Group","groupId":${this.jsonId(id)}}` :
      '{"type":"All"}';
    const res = await this.postRepeatJson(REPEAT_PHOTO_MERGE_PATH, bodyStr, timeoutMs, '合并失败');
    if (!res.success) {
      return { success: false, message: res.message, errorBodyPreview: res.errorBodyPreview };
    }
    return { success: true, data: parseRepeatPhotoMergeData(res.data) };
  }

  private jsonId(id: string): string {
    const numeric = jsonScalarId(id);
    if (numeric.length > 0) {
      return numeric;
    }
    return `"${escapeJsonString(id)}"`;
  }

  private async postRepeatJson(
    path: string,
    bodyStr: string,
    timeoutMs: number,
    failText: string
  ): Promise<FnClientResult<Object>> {
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
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
        const data = parsed['data'];
        return { success: true, data: data as Object };
      }
      const errLine = FnHttpClientGalleryRequest.envelopeErrorLine(parsed);
      return { success: false, message: errLine.length > 0 ? errLine : failText };
    } catch (e) {
      return { success: false, message: String(e) || failText };
    }
  }
}
