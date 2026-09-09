import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CertPolicy } from '../CertPolicy';
import { buildGallerySortedQuery, FnGalleryGetSignSpec, genFnGalleryAuthxPost, genFnGalleryAuthxPostRaw } from '../FnGalleryAuthx';
import { FN_PHOTO_API_PREFIX, FN_PHOTO_API_V2_PREFIX } from '../FnPhotoRoutes';
import { mergeGalleryWebCookieIntoNativeHeader } from '../FnWebCookies';
import { fnWebViewBaseUrl } from '../ServerUrl';
import { buildFnApiCookieHeader } from './FnHttpClientCookie';
import {
  DEFAULT_TIMEOUT,
  DOMAIN,
  GALLERY_GETLIST_PATH_CANDIDATES,
  GALLERY_GETLIST_SIGN_PATH,
  SEARCH_FILTERLIST_PATH_CANDIDATES,
  SEARCH_FILTERLIST_SIGN_PATH,
  TAG,
} from './FnHttpClientCommon';
import { FnHttpClientGalleryHost } from './FnHttpClientTypes';
import { FnHttpClientGalleryRequest } from './FnHttpClientGalleryRequest';
import {
  FnClientResult,
  FnJsonValue,
  GalleryGetListData,
  GalleryListItem,
  MagicSearchData,
  MediaCategoryItem,
  SearchFilterListData
} from '../../model/FnApiTypes';

export class FnHttpClientSearchOps extends FnHttpClientGalleryRequest {
  constructor(host: FnHttpClientGalleryHost) {
    super(host);
  }

  async doMagicSearch(
    keyword: string,
    timeoutMs: number = 20000,
    antiFiltersJson: string = '[]',
    filtersJson: string = '[]'
  ): Promise<FnClientResult<MagicSearchData>> {
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const path = `${FN_PHOTO_API_PREFIX}/magic-search/do`;
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const antiJson = antiFiltersJson.trim().length > 0 ? antiFiltersJson.trim() : '[]';
      const filters = filtersJson.trim().length > 0 ? filtersJson.trim() : '[]';
      let bodyStr = `{"keyword":${JSON.stringify(keyword)},"antiFilters":${antiJson}}`;
      if (filters !== '[]') {
        bodyStr =
          `{"keyword":${JSON.stringify(keyword)},"filters":${filters},"antiFilters":${antiJson}}`;
      }
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
        return { success: false, message: '搜索结果解析失败' };
      }
      if (!FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
        const code = FnHttpClientGalleryRequest.envelopeCodeNum(parsed);
        const errLine = FnHttpClientGalleryRequest.envelopeErrorLine(parsed);
        const show = errLine.length > 0 ? `: ${errLine}` : '';
        return { success: false, message: `搜索请求失败 (${code})${show}` };
      }
      return { success: true, data: parsed['data'] as MagicSearchData };
    } catch (e) {
      return { success: false, message: String(e) || '搜索请求异常' };
    }
  }

  async getSearchFilterList(
    showShootingInformation: boolean = true,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<SearchFilterListData>> {
    try {
      const params: Record<string, string | number | boolean> = {};
      params['show_shooting_information'] = showShootingInformation ? 1 : 0;
      const qs = buildGallerySortedQuery(params);
      const pathCandidates: string[] = [];
      for (let i = 0; i < SEARCH_FILTERLIST_PATH_CANDIDATES.length; i++) {
        pathCandidates.push(`${SEARCH_FILTERLIST_PATH_CANDIDATES[i]}?${qs}`);
      }
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: SEARCH_FILTERLIST_SIGN_PATH,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<Object>(pathCandidates, gallerySign, timeoutMs, 3);
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '筛选项加载失败' };
      }
      return { success: true, data: FnHttpClientGalleryRequest.parseSearchFilterListData(res.data) };
    } catch (e) {
      return { success: false, message: String(e) || '筛选项加载异常' };
    }
  }

  async searchResultsByFilters(
    keyword: string,
    filtersJson: string,
    antiFiltersJson: string,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryListItem[]>> {
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
      const filters = filtersJson.trim().length > 0 ? filtersJson.trim() : '[]';
      const anti = antiFiltersJson.trim().length > 0 ? antiFiltersJson.trim() : '[]';
      const bodyStr =
        `{"keyword":${JSON.stringify(keyword)},"filters":${filters},"antiFilters":${anti}}`;
      hilog.info(DOMAIN, TAG, 'searchFilters body: %{public}s', bodyStr);
      for (let pi = 0; pi < searchResultPaths.length; pi++) {
        const pathTry = searchResultPaths[pi];
        const authx = await genFnGalleryAuthxPostRaw(pathTry, bodyStr);
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
        let parsed: Record<string, string | number | Object | undefined> | undefined;
        try {
          parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
        } catch (_e) {
          parsed = undefined;
        }
        if (parsed === undefined || !FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
          continue;
        }
        const arr = FnHttpClientGalleryRequest.searchResultItemsFromData(
          FnHttpClientGalleryRequest.galleryEnvelopeData(parsed)
        );
        return {
          success: true,
          data: FnHttpClientGalleryRequest.normalizeSearchResultGalleryItems(arr)
        };
      }
      return { success: false, message: '搜索结果为空' };
    } catch (e) {
      return { success: false, message: String(e) || '筛选搜索异常' };
    }
  }

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
            if (parsedFilters !== undefined && FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsedFilters)) {
              const arrFilters =
                FnHttpClientGalleryRequest.searchResultItemsFromData(FnHttpClientGalleryRequest.galleryEnvelopeData(parsedFilters));
              hilog.info(DOMAIN, TAG, 'catSearch filters arr.length=%{public}d', arrFilters.length);
              if (arrFilters.length > 0) {
                return {
                  success: true,
                  data: FnHttpClientGalleryRequest.normalizeSearchResultGalleryItems(arrFilters),
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
          if (!FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
            continue;
          }
          const arr = FnHttpClientGalleryRequest.searchResultItemsFromData(FnHttpClientGalleryRequest.galleryEnvelopeData(parsed));
          if (arr.length > 0) {
            return { success: true, data: FnHttpClientGalleryRequest.normalizeSearchResultGalleryItems(arr) };
          }
        }
      }
      return { success: false, message: '分类结果为空' };
    } catch (e) {
      return { success: false, message: String(e) || '分类检索异常' };
    }
  }

  /** 地理位置照片：POST /p/api/v2/search/results，filter 与官方 /geo -> /search 一致 */
  async searchResultsByLocation(
    country: string,
    city: string,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryListItem[]>> {
    try {
      const countryVal = country.trim();
      const cityVal = city.trim();
      const firstVal = countryVal.length > 0 ? countryVal : cityVal;
      if (firstVal.length <= 0) {
        return { success: false, message: '地点参数为空' };
      }
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const searchResultPaths: string[] = [
        `${FN_PHOTO_API_V2_PREFIX}/search/results`,
        `${FN_PHOTO_API_PREFIX}/search/results`,
      ];
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const firstJson = JSON.stringify(firstVal);
      const bodyStr = cityVal.length > 0 && countryVal.length > 0
        ? `{"keyword":"","filters":[{"filterName":"photo_location","filterValue":${firstJson},"subFilters":[{"filterName":${firstJson},"filterValue":${JSON.stringify(cityVal)}}]}],"antiFilters":[]}`
        : `{"keyword":"","filters":[{"filterName":"photo_location","filterValue":${firstJson}}],"antiFilters":[]}`;
      for (let pi = 0; pi < searchResultPaths.length; pi++) {
        const pathTry = searchResultPaths[pi];
        const authx = await genFnGalleryAuthxPostRaw(pathTry, bodyStr);
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
        hilog.info(DOMAIN, TAG, 'geoSearch path=%{public}s http=%{public}d body500: %{public}s',
          pathTry, raw.code, raw.body.substring(0, 500));
        if (raw.code < 200 || raw.code >= 300) {
          continue;
        }
        let parsed: Record<string, string | number | Object | undefined> | undefined;
        try {
          parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
        } catch (_e) {
          parsed = undefined;
        }
        if (parsed === undefined || !FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
          continue;
        }
        const arr = FnHttpClientGalleryRequest.searchResultItemsFromData(
          FnHttpClientGalleryRequest.galleryEnvelopeData(parsed)
        );
        if (arr.length > 0) {
          return {
            success: true,
            data: FnHttpClientGalleryRequest.normalizeSearchResultGalleryItems(arr)
          };
        }
      }
      return { success: false, message: '地点结果为空' };
    } catch (e) {
      return { success: false, message: String(e) || '地点检索异常' };
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
}
