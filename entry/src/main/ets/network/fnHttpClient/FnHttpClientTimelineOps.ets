import { buildGallerySortedQuery, FnGalleryGetSignSpec } from '../FnGalleryAuthx';
import {
  DEFAULT_TIMEOUT,
  GALLERY_GETLIST_PATH_CANDIDATES,
  GALLERY_GETLIST_SIGN_PATH,
  GALLERY_GETONE_PATH_CANDIDATES,
  GALLERY_GETONE_SIGN_PATH,
  GALLERY_QUERY_EMPTY,
  GALLERY_TIMELINE_PATH_CANDIDATES,
  GALLERY_TIMELINE_SIGN_PATH,
  RECENT_PHOTOS_PATH_CANDIDATES,
  RECENT_PHOTOS_SIGN_PATH,
  RECENT_TIMELINE_PATH_CANDIDATES,
  RECENT_TIMELINE_SIGN_PATH,
} from './FnHttpClientCommon';
import { FnHttpClientGalleryHost } from './FnHttpClientTypes';
import { FnHttpClientGalleryRequest } from './FnHttpClientGalleryRequest';
import {
  FnClientResult,
  GalleryGetListData,
  GalleryListItem,
  GalleryPhotoDetailData,
  GalleryTimelineData
} from '../../model/FnApiTypes';

export class FnHttpClientTimelineOps extends FnHttpClientGalleryRequest {
  constructor(host: FnHttpClientGalleryHost) {
    super(host);
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
}
