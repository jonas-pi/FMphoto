import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CertPolicy } from '../CertPolicy';
import { buildGallerySortedQuery, FnGalleryGetSignSpec, genFnGalleryAuthxGet } from '../FnGalleryAuthx';
import { FN_PHOTO_API_PREFIX, FN_PHOTO_API_V2_PREFIX } from '../FnPhotoRoutes';
import { mergeGalleryWebCookieIntoNativeHeader } from '../FnWebCookies';
import { fnWebViewBaseUrl } from '../ServerUrl';
import { buildFnApiCookieHeader } from './FnHttpClientCookie';
import {
  DOMAIN,
  GALLERY_QUERY_EMPTY,
  PERSON_IN_PHOTO_PATH_CANDIDATES,
  PERSON_IN_PHOTO_SIGN_PATH,
  TAG,
} from './FnHttpClientCommon';
import { FnHttpClientGalleryHost } from './FnHttpClientTypes';
import { FnHttpClientGalleryRequest } from './FnHttpClientGalleryRequest';
import {
  AiPersonData,
  AiPersonDetailData,
  FnClientResult,
  GalleryGetListData,
  GalleryListItem,
  GalleryTimelineData,
  MediaCategoryData,
  PersonInPhotoData,
  SmartCategoryData,
  UserAlbumData
} from '../../model/FnApiTypes';

export class FnHttpClientAlbumMetaOps extends FnHttpClientGalleryRequest {
  constructor(host: FnHttpClientGalleryHost) {
    super(host);
  }

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
        if (!FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
          const code = FnHttpClientGalleryRequest.envelopeCodeNum(parsed);
          const errLine = FnHttpClientGalleryRequest.envelopeErrorLine(parsed);
          lastBizMsg = errLine.length > 0 ? errLine : `媒体分类请求失败 (${code})`;
          continue;
        }
        hilog.info(DOMAIN, TAG, 'mediaCat path=%{public}s body(600): %{public}s', path, raw.body.substring(0, 600));
        const payload = FnHttpClientGalleryRequest.galleryEnvelopeData(parsed);
        const normList = FnHttpClientGalleryRequest.mediaCategoryItemsFromData(payload);
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
      const normList = FnHttpClientGalleryRequest.smartCategoryItemsFromData(res.data as Object);
      if (normList.length > 0) {
        const first = normList[0] as Record<string, Object | string | number | boolean | undefined | null>;
        hilog.info(
          DOMAIN,
          TAG,
          'smartCat normCount=%{public}d firstCover=%{public}s',
          normList.length,
          FnHttpClientGalleryRequest.readFirstString(first, ['cover', 'thumb', 'posterUrl', 'imageUrl'])
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
      const normList = FnHttpClientGalleryRequest.aiPersonItemsFromData(res.data as Object);
      if (normList.length > 0) {
        const first = normList[0] as Record<string, Object | string | number | boolean | undefined | null>;
        hilog.info(
          DOMAIN,
          TAG,
          'person normCount=%{public}d firstFace=%{public}s',
          normList.length,
          FnHttpClientGalleryRequest.readFirstString(first, ['faceUrl', 'cover', 'thumb'])
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
   * 用户相册列表：GET /p/api/v1/album/list?sort_direction=desc&sort_by=date_time&offset=0&limit=1000
   */
  async getUserAlbumList(timeoutMs: number = 20000): Promise<FnClientResult<UserAlbumData>> {
    try {
      const params: Record<string, string | number | boolean> = {};
      params['sort_direction'] = 'desc';
      params['sort_by'] = 'date_time';
      params['offset'] = 0;
      params['limit'] = 1000;
      const qs = buildGallerySortedQuery(params);
      const signPath = `${FN_PHOTO_API_PREFIX}/album/list`;
      const pathCandidates: string[] = [
        `${signPath}?${qs}`,
        `/api/v1/album/list?${qs}`
      ];
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: signPath,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<UserAlbumData>(pathCandidates, gallerySign, timeoutMs, 3);
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '相册列表加载失败' };
      }
      const normList = FnHttpClientGalleryRequest.userAlbumItemsFromData(res.data as Object);
      return { success: true, data: { list: normList } };
    } catch (e) {
      return { success: false, message: String(e) || '相册列表加载异常' };
    }
  }

  /**
   * 用户相册时间线：普通 GET /p/api/v1/album/normal/timeline，宝宝 GET /p/api/v1/album/baby/timeline
   */
  async getUserAlbumTimeline(
    albumId: string,
    isBaby: boolean,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryTimelineData>> {
    try {
      if (albumId.length === 0) {
        return { success: false, message: 'albumId 不能为空' };
      }
      const params: Record<string, string | number | boolean> = {};
      params['albumId'] = albumId;
      if (!isBaby) {
        params['sortBy'] = 'date_time';
        params['sortDirection'] = 'desc';
      }
      const qs = buildGallerySortedQuery(params);
      const sub = isBaby ? 'baby' : 'normal';
      const signPath = `${FN_PHOTO_API_PREFIX}/album/${sub}/timeline`;
      const pathCandidates: string[] = [
        `${signPath}?${qs}`,
        `/api/v1/album/${sub}/timeline?${qs}`
      ];
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: signPath,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<GalleryTimelineData>(pathCandidates, gallerySign, timeoutMs, 3);
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '相册时间线加载失败' };
      }
      return { success: true, data: res.data };
    } catch (e) {
      return { success: false, message: String(e) || '相册时间线加载异常' };
    }
  }

  /**
   * 用户相册按日列表：普通 GET /p/api/v1/album/normal/getList，宝宝 GET /p/api/v1/album/baby/getList
   */
  async getUserAlbumPhotoList(
    albumId: string,
    isBaby: boolean,
    startTime: string,
    endTime: string,
    limit: number,
    offset: number,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryGetListData>> {
    try {
      if (albumId.length === 0) {
        return { success: false, message: 'albumId 不能为空' };
      }
      const params: Record<string, string | number | boolean> = {};
      params['albumId'] = albumId;
      params['startTime'] = startTime;
      params['endTime'] = endTime;
      params['offset'] = offset;
      params['limit'] = limit;
      if (!isBaby) {
        params['sortDirection'] = 'desc';
      }
      const qs = buildGallerySortedQuery(params);
      const sub = isBaby ? 'baby' : 'normal';
      const signPath = `${FN_PHOTO_API_PREFIX}/album/${sub}/getList`;
      const pathCandidates: string[] = [
        `${signPath}?${qs}`,
        `/api/v1/album/${sub}/getList?${qs}`
      ];
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: signPath,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<GalleryGetListData | GalleryListItem[]>(
        pathCandidates, gallerySign, timeoutMs, 3
      );
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '相册照片加载失败' };
      }
      const payload = res.data as GalleryGetListData | GalleryListItem[];
      if (Array.isArray(payload)) {
        return { success: true, data: { list: payload } };
      }
      return { success: true, data: payload as GalleryGetListData };
    } catch (e) {
      return { success: false, message: String(e) || '相册照片加载异常' };
    }
  }

  /**
   * 用户相册平铺列表兜底：GET /p/api/v1/album/photos
   */
  async getUserAlbumPhotos(
    albumId: string,
    offset: number,
    limit: number,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryGetListData>> {
    try {
      if (albumId.length === 0) {
        return { success: false, message: 'albumId 不能为空' };
      }
      const params: Record<string, string | number | boolean> = {};
      params['album_id'] = albumId;
      params['sort_by'] = 'date_time';
      params['sort_direction'] = 'desc';
      params['offset'] = offset;
      params['limit'] = limit;
      const qs = buildGallerySortedQuery(params);
      const signPath = `${FN_PHOTO_API_PREFIX}/album/photos`;
      const pathCandidates: string[] = [
        `${signPath}?${qs}`,
        `/api/v1/album/photos?${qs}`
      ];
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: signPath,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<GalleryGetListData | GalleryListItem[]>(
        pathCandidates, gallerySign, timeoutMs, 3
      );
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '相册照片加载失败' };
      }
      const payload = res.data as GalleryGetListData | GalleryListItem[];
      if (Array.isArray(payload)) {
        return { success: true, data: { list: payload } };
      }
      return { success: true, data: payload as GalleryGetListData };
    } catch (e) {
      return { success: false, message: String(e) || '相册照片加载异常' };
    }
  }
}
