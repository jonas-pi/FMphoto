import { buildGallerySortedQuery, FnGalleryGetSignSpec } from '../FnGalleryAuthx';
import {
  EXPLORE_GEOS_PATH_CANDIDATES,
  EXPLORE_GEOS_SIGN_PATH,
  GALLERY_QUERY_EMPTY,
  MAP_GET_IDS_PATH_CANDIDATES,
  MAP_GET_IDS_SIGN_PATH,
  MAP_PHOTO_LIST_PATH_CANDIDATES,
  MAP_PHOTO_LIST_SIGN_PATH,
  MAP_PREVIEW_ALL_POINT_PATH_CANDIDATES,
  MAP_PREVIEW_ALL_POINT_SIGN_PATH,
  MAP_PREVIEW_BOUNDARY_PATH_CANDIDATES,
  MAP_PREVIEW_BOUNDARY_SIGN_PATH,
  MAP_PREVIEW_CENTER_PATH_CANDIDATES,
  MAP_PREVIEW_CENTER_SIGN_PATH,
  MAP_TIMELINE_PATH_CANDIDATES,
  MAP_TIMELINE_SIGN_PATH,
} from './FnHttpClientCommon';
import { FnHttpClientGalleryHost } from './FnHttpClientTypes';
import { FnHttpClientGalleryRequest } from './FnHttpClientGalleryRequest';
import {
  ExploreGeosData,
  FnClientResult,
  GalleryGetListData,
  GalleryListItem,
  MapPreviewAllPointData,
  MapPreviewAllPointItem,
  MapPreviewBoundaryData,
  MapPreviewCenterData,
  MapTimelineData
} from '../../model/FnApiTypes';

export class FnHttpClientMapOps extends FnHttpClientGalleryRequest {
  constructor(host: FnHttpClientGalleryHost) {
    super(host);
  }

  /** 地图初始化中心点：GET /p/api/v1/map/preview/initCenter（官方 mapApi.getCenter） */
  async getMapPreviewCenter(timeoutMs: number = 15000): Promise<FnClientResult<MapPreviewCenterData>> {
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: MAP_PREVIEW_CENTER_SIGN_PATH,
      queryParams: GALLERY_QUERY_EMPTY
    };
    return this.requestGalleryGetJson<MapPreviewCenterData>(
      MAP_PREVIEW_CENTER_PATH_CANDIDATES,
      gallerySign,
      timeoutMs,
      3
    );
  }

  /** 地图边界：GET /p/api/v1/map/preview/mapBoundary（官方 mapApi.getBoundary） */
  async getMapPreviewBoundary(timeoutMs: number = 15000): Promise<FnClientResult<MapPreviewBoundaryData>> {
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: MAP_PREVIEW_BOUNDARY_SIGN_PATH,
      queryParams: GALLERY_QUERY_EMPTY
    };
    return this.requestGalleryGetJson<MapPreviewBoundaryData>(
      MAP_PREVIEW_BOUNDARY_PATH_CANDIDATES,
      gallerySign,
      timeoutMs,
      3
    );
  }

  /** Map photo points: GET /p/api/v1/map/previewAllPoint (official mapApi). */
  async getMapPreviewAllPoint(
    north: number,
    east: number,
    south: number,
    west: number,
    lonVert: number = 0,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<MapPreviewAllPointData>> {
    const params: Record<string, string | number | boolean> = {};
    params['north'] = north;
    params['east'] = east;
    params['south'] = south;
    params['west'] = west;
    params['lonVert'] = lonVert;
    const qs = buildGallerySortedQuery(params);
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: MAP_PREVIEW_ALL_POINT_SIGN_PATH,
      queryParams: params
    };
    const res = await this.requestGalleryGetJson<MapPreviewAllPointData | MapPreviewAllPointItem[]>(
      FnHttpClientGalleryRequest.buildMapGetPathCandidates(MAP_PREVIEW_ALL_POINT_PATH_CANDIDATES, qs),
      gallerySign,
      timeoutMs,
      3
    );
    if (!res.success || res.data === undefined) {
      return res as FnClientResult<MapPreviewAllPointData>;
    }
    const payload = res.data as MapPreviewAllPointData | MapPreviewAllPointItem[];
    if (Array.isArray(payload)) {
      return {
        success: true,
        data: { list: payload },
        moveUrl: res.moveUrl,
        fnosLongToken: res.fnosLongToken
      };
    }
    return {
      success: true,
      data: {
        list: FnHttpClientGalleryRequest.mapPreviewPointItemsFromData(payload as Object),
        total: (payload as MapPreviewAllPointData).total
      },
      moveUrl: res.moveUrl,
      fnosLongToken: res.fnosLongToken
    };
  }

  /** 地图时间轴/地点聚合：GET /p/api/v1/map/timeLine（官方 mapApi.getTimeline） */
  async getMapTimeline(
    extraParams?: Record<string, string | number | boolean>,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<MapTimelineData>> {
    const params: Record<string, string | number | boolean> =
      extraParams !== undefined ? extraParams : GALLERY_QUERY_EMPTY;
    const qs = buildGallerySortedQuery(params);
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: MAP_TIMELINE_SIGN_PATH,
      queryParams: params
    };
    return this.requestGalleryGetJson<MapTimelineData>(
      FnHttpClientGalleryRequest.buildMapGetPathCandidates(MAP_TIMELINE_PATH_CANDIDATES, qs),
      gallerySign,
      timeoutMs,
      3
    );
  }

  /**
   * 地图照片列表：GET /p/api/v1/map/photoList。
   * 官方 Web 会把 start_time/end_time 转成 startTime/endTime，这里直接按官方最终请求参数发送。
   */
  async getMapPhotoList(
    startTime: string,
    endTime: string,
    limit: number,
    offset: number,
    extraParams?: Record<string, string | number | boolean>,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryGetListData>> {
    const params: Record<string, string | number | boolean> = {};
    if (extraParams !== undefined) {
      const keys = Object.keys(extraParams);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        if (k === 'mode' || k === 'start_time' || k === 'end_time' ||
          k === 'startTime' || k === 'endTime' || k === 'limit' || k === 'offset') {
          continue;
        }
        params[k] = extraParams[k];
      }
    }
    params['startTime'] = startTime;
    params['endTime'] = endTime;
    params['offset'] = offset;
    params['limit'] = limit;
    const qs = buildGallerySortedQuery(params);
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: MAP_PHOTO_LIST_SIGN_PATH,
      queryParams: params
    };
    const res = await this.requestGalleryGetJson<GalleryGetListData | GalleryListItem[]>(
      FnHttpClientGalleryRequest.buildMapGetPathCandidates(MAP_PHOTO_LIST_PATH_CANDIDATES, qs),
      gallerySign,
      timeoutMs,
      3
    );
    if (!res.success || res.data === undefined) {
      return res as FnClientResult<GalleryGetListData>;
    }
    const payload = res.data as GalleryGetListData | GalleryListItem[];
    if (Array.isArray(payload)) {
      return {
        success: true,
        data: { list: payload },
        moveUrl: res.moveUrl,
        fnosLongToken: res.fnosLongToken
      };
    }
    return res as FnClientResult<GalleryGetListData>;
  }

  async getMapPhotoListByBounds(
    boundsParams: Record<string, string | number | boolean>,
    limit: number,
    offset: number,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryGetListData>> {
    const params: Record<string, string | number | boolean> = {};
    const keys = Object.keys(boundsParams);
    for (let i = 0; i < keys.length; i++) {
      params[keys[i]] = boundsParams[keys[i]];
    }
    params['offset'] = offset;
    params['limit'] = limit;
    const qs = buildGallerySortedQuery(params);
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: MAP_PHOTO_LIST_SIGN_PATH,
      queryParams: params
    };
    const res = await this.requestGalleryGetJson<GalleryGetListData | GalleryListItem[]>(
      FnHttpClientGalleryRequest.buildMapGetPathCandidates(MAP_PHOTO_LIST_PATH_CANDIDATES, qs),
      gallerySign,
      timeoutMs,
      3
    );
    if (!res.success || res.data === undefined) {
      return res as FnClientResult<GalleryGetListData>;
    }
    const payload = res.data as GalleryGetListData | GalleryListItem[];
    if (Array.isArray(payload)) {
      return {
        success: true,
        data: { list: payload },
        moveUrl: res.moveUrl,
        fnosLongToken: res.fnosLongToken
      };
    }
    const items = FnHttpClientGalleryRequest.searchResultItemsFromData(payload as Object);
    if (items.length > 0) {
      return {
        success: true,
        data: { list: items, total: (payload as GalleryGetListData).total },
        moveUrl: res.moveUrl,
        fnosLongToken: res.fnosLongToken
      };
    }
    return res as FnClientResult<GalleryGetListData>;
  }

  /** 地图照片 ID 列表：GET /p/api/v1/map/getIds（官方 map/getIds） */
  async getMapPhotoIds(
    extraParams?: Record<string, string | number | boolean>,
    timeoutMs: number = 15000
  ): Promise<FnClientResult<Object>> {
    const params: Record<string, string | number | boolean> =
      extraParams !== undefined ? extraParams : GALLERY_QUERY_EMPTY;
    const qs = buildGallerySortedQuery(params);
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: MAP_GET_IDS_SIGN_PATH,
      queryParams: params
    };
    return this.requestGalleryGetJson<Object>(
      FnHttpClientGalleryRequest.buildMapGetPathCandidates(MAP_GET_IDS_PATH_CANDIDATES, qs),
      gallerySign,
      timeoutMs,
      3
    );
  }

  /** 地理位置列表：GET /p/api/v1/explore/geos（官方 /geo 入口） */
  async getExploreGeos(
    offset: number = 0,
    limit: number = -1,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<ExploreGeosData>> {
    try {
      const params: Record<string, string | number | boolean> = {};
      params['offset'] = offset;
      params['limit'] = limit;
      const qs = buildGallerySortedQuery(params);
      const pathCandidates: string[] = [];
      for (let i = 0; i < EXPLORE_GEOS_PATH_CANDIDATES.length; i++) {
        pathCandidates.push(`${EXPLORE_GEOS_PATH_CANDIDATES[i]}?${qs}`);
      }
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: EXPLORE_GEOS_SIGN_PATH,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<ExploreGeosData>(
        pathCandidates,
        gallerySign,
        timeoutMs,
        3
      );
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '地理位置加载失败' };
      }
      const payload = res.data as ExploreGeosData;
      const normList = FnHttpClientGalleryRequest.geoItemsFromData(payload as Object);
      return {
        success: true,
        data: {
          list: normList,
          total: payload.total
        },
        moveUrl: res.moveUrl,
        fnosLongToken: res.fnosLongToken
      };
    } catch (e) {
      return { success: false, message: String(e) || '地理位置加载异常' };
    }
  }
}
