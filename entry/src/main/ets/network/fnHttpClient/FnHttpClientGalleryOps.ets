import { FnHttpClientGalleryHost, VideoDecodePlayInfo, VideoDecodePlayRequest } from './FnHttpClientTypes';
import { FnHttpClientMediaAssetOps } from './FnHttpClientMediaAssetOps';
import { FnHttpClientTimelineOps } from './FnHttpClientTimelineOps';
import { FnHttpClientMapOps } from './FnHttpClientMapOps';
import { FnHttpClientSearchOps } from './FnHttpClientSearchOps';
import { FnHttpClientFolderOps } from './FnHttpClientFolderOps';
import { FnHttpClientAlbumMetaOps } from './FnHttpClientAlbumMetaOps';
import { FnHttpClientRecycleOps } from './FnHttpClientRecycleOps';
import { FnHttpClientRepeatOps } from './FnHttpClientRepeatOps';
import {
  AiPersonData,
  AiPersonDetailData,
  ExploreGeosData,
  FnClientResult,
  FolderViewCoverData,
  GalleryGetListData,
  GalleryListItem,
  GalleryPhotoDetailData,
  GalleryTimelineData,
  MagicSearchData,
  MapPreviewAllPointData,
  MapPreviewBoundaryData,
  MapPreviewCenterData,
  MapTimelineData,
  MediaCategoryData,
  MediaCategoryItem,
  PersonInPhotoData,
  PhotoFolderListData,
  RecycleBinListData,
  RepeatPhotoGroup,
  RepeatPhotoListData,
  RepeatPhotoMergeData,
  RepeatPhotoTaskProgress,
  SearchFilterListData,
  SmartCategoryData,
  UserAlbumData
} from '../../model/FnApiTypes';

export interface GalleryHlsAuthProbe {
  m3u8Code: number;
  segName: string;
  segAuthxCode: number;
  segCookieCode: number;
}

export class FnHttpClientGalleryOps {
  private readonly media: FnHttpClientMediaAssetOps;
  private readonly timeline: FnHttpClientTimelineOps;
  private readonly mapOps: FnHttpClientMapOps;
  private readonly search: FnHttpClientSearchOps;
  private readonly folder: FnHttpClientFolderOps;
  private readonly albumMeta: FnHttpClientAlbumMetaOps;
  private readonly recycle: FnHttpClientRecycleOps;
  private readonly repeat: FnHttpClientRepeatOps;

  constructor(host: FnHttpClientGalleryHost) {
    this.media = new FnHttpClientMediaAssetOps(host);
    this.timeline = new FnHttpClientTimelineOps(host);
    this.mapOps = new FnHttpClientMapOps(host);
    this.search = new FnHttpClientSearchOps(host);
    this.folder = new FnHttpClientFolderOps(host);
    this.albumMeta = new FnHttpClientAlbumMetaOps(host);
    this.recycle = new FnHttpClientRecycleOps(host);
    this.repeat = new FnHttpClientRepeatOps(host);
  }

  static clearAssetBufferCache(): void {
    FnHttpClientMediaAssetOps.clearAssetBufferCache();
  }

  async fetchGalleryImageBuffer(fullUrl: string, timeoutMs: number = 8000): Promise<ArrayBuffer | undefined> {
    return this.media.fetchGalleryImageBuffer(fullUrl, timeoutMs);
  }

  async downloadGalleryAssetToFile(
    fullUrl: string,
    filePath: string,
    timeoutMs: number = 300000,
    onProgress?: (receiveSize: number, totalSize: number) => void
  ): Promise<boolean> {
    return this.media.downloadGalleryAssetToFile(fullUrl, filePath, timeoutMs, onProgress);
  }

  async getGalleryStreamHeaders(fullUrl: string): Promise<Record<string, string>> {
    return this.media.getGalleryStreamHeaders(fullUrl);
  }

  async getGalleryStreamMediaHeaders(): Promise<Record<string, string>> {
    return this.media.getGalleryStreamMediaHeaders();
  }

  async probeGalleryHlsAuth(m3u8Url: string, timeoutMs: number = 6000): Promise<GalleryHlsAuthProbe> {
    return this.media.probeGalleryHlsAuth(m3u8Url, timeoutMs);
  }

  async requestVideoDecodePlayUrl(
    req: VideoDecodePlayRequest,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<VideoDecodePlayInfo>> {
    return this.media.requestVideoDecodePlayUrl(req, timeoutMs);
  }

  async requestVideoDecodeQuit(photoId: string, timeoutMs: number = 8000): Promise<FnClientResult<Object>> {
    return this.media.requestVideoDecodeQuit(photoId, timeoutMs);
  }

  async getGalleryTimeline(
    extraParams?: Record<string, string | number | boolean>
  ): Promise<FnClientResult<GalleryTimelineData>> {
    return this.timeline.getGalleryTimeline(extraParams);
  }

  async getCollectGalleryTimeline(): Promise<FnClientResult<GalleryTimelineData>> {
    return this.timeline.getCollectGalleryTimeline();
  }

  async getRecentTimeline(
    extraParams?: Record<string, string | number | boolean>
  ): Promise<FnClientResult<GalleryTimelineData>> {
    return this.timeline.getRecentTimeline(extraParams);
  }

  async getMapPreviewCenter(timeoutMs: number = 15000): Promise<FnClientResult<MapPreviewCenterData>> {
    return this.mapOps.getMapPreviewCenter(timeoutMs);
  }

  async getMapPreviewBoundary(timeoutMs: number = 15000): Promise<FnClientResult<MapPreviewBoundaryData>> {
    return this.mapOps.getMapPreviewBoundary(timeoutMs);
  }

  async getMapPreviewAllPoint(
    north: number,
    east: number,
    south: number,
    west: number,
    lonVert: number = 0,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<MapPreviewAllPointData>> {
    return this.mapOps.getMapPreviewAllPoint(north, east, south, west, lonVert, timeoutMs);
  }

  async getMapTimeline(
    extraParams?: Record<string, string | number | boolean>,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<MapTimelineData>> {
    return this.mapOps.getMapTimeline(extraParams, timeoutMs);
  }

  async getMapPhotoList(
    startTime: string,
    endTime: string,
    limit: number,
    offset: number,
    extraParams?: Record<string, string | number | boolean>,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryGetListData>> {
    return this.mapOps.getMapPhotoList(startTime, endTime, limit, offset, extraParams, timeoutMs);
  }

  async getMapPhotoListByBounds(
    boundsParams: Record<string, string | number | boolean>,
    limit: number,
    offset: number,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryGetListData>> {
    return this.mapOps.getMapPhotoListByBounds(boundsParams, limit, offset, timeoutMs);
  }

  async getMapPhotoIds(
    extraParams?: Record<string, string | number | boolean>,
    timeoutMs: number = 15000
  ): Promise<FnClientResult<Object>> {
    return this.mapOps.getMapPhotoIds(extraParams, timeoutMs);
  }

  async getExploreGeos(
    offset: number = 0,
    limit: number = -1,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<ExploreGeosData>> {
    return this.mapOps.getExploreGeos(offset, limit, timeoutMs);
  }

  async doMagicSearch(
    keyword: string,
    timeoutMs: number = 20000,
    antiFiltersJson: string = '[]',
    filtersJson: string = '[]'
  ): Promise<FnClientResult<MagicSearchData>> {
    return this.search.doMagicSearch(keyword, timeoutMs, antiFiltersJson, filtersJson);
  }

  async getSearchFilterList(
    showShootingInformation: boolean = true,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<SearchFilterListData>> {
    return this.search.getSearchFilterList(showShootingInformation, timeoutMs);
  }

  async getPhotoFolderList(
    timeoutMs: number = 20000,
    folderPath: string = '',
    desc: boolean = false,
    orderBy: number = 2
  ): Promise<FnClientResult<PhotoFolderListData>> {
    return this.folder.getPhotoFolderList(timeoutMs, folderPath, desc, orderBy);
  }

  async getFolderViewFolderList(
    folderPath: string,
    desc: boolean = false,
    orderBy: number = 2,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<PhotoFolderListData>> {
    return this.folder.getFolderViewFolderList(folderPath, desc, orderBy, timeoutMs);
  }

  async getFolderViewCover(
    currentPath: string,
    dirNames: string[],
    timeoutMs: number = 20000
  ): Promise<FnClientResult<FolderViewCoverData>> {
    return this.folder.getFolderViewCover(currentPath, dirNames, timeoutMs);
  }

  async searchResultsByFilters(
    keyword: string,
    filtersJson: string,
    antiFiltersJson: string,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryListItem[]>> {
    return this.search.searchResultsByFilters(keyword, filtersJson, antiFiltersJson, timeoutMs);
  }

  async getMediaCategoryList(timeoutMs: number = 20000): Promise<FnClientResult<MediaCategoryData>> {
    return this.albumMeta.getMediaCategoryList(timeoutMs);
  }

  async getSmartRecCategories(
    mainCategory: string,
    limit: number = -1,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<SmartCategoryData>> {
    return this.albumMeta.getSmartRecCategories(mainCategory, limit, timeoutMs);
  }

  async getAiPersonList(
    getAll: boolean = true,
    limit: number = -1,
    orderBy: number = 0,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<AiPersonData>> {
    return this.albumMeta.getAiPersonList(getAll, limit, orderBy, timeoutMs);
  }

  async getAiPersonDetail(personId: string, timeoutMs: number = 20000): Promise<FnClientResult<AiPersonDetailData>> {
    return this.albumMeta.getAiPersonDetail(personId, timeoutMs);
  }

  async getPersonInPhoto(photoId: string, timeoutMs: number = 12000): Promise<FnClientResult<PersonInPhotoData>> {
    return this.albumMeta.getPersonInPhoto(photoId, timeoutMs);
  }

  async getAiPersonPhotoTimeline(personId: string, timeoutMs: number = 20000): Promise<FnClientResult<GalleryTimelineData>> {
    return this.albumMeta.getAiPersonPhotoTimeline(personId, timeoutMs);
  }

  async getAiPersonPhotoList(
    personId: string,
    startTime: string,
    endTime: string,
    limit: number,
    offset: number,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryGetListData>> {
    return this.albumMeta.getAiPersonPhotoList(personId, startTime, endTime, limit, offset, timeoutMs);
  }

  async getUserAlbumList(timeoutMs: number = 20000): Promise<FnClientResult<UserAlbumData>> {
    return this.albumMeta.getUserAlbumList(timeoutMs);
  }

  async getUserAlbumTimeline(
    albumId: string,
    isBaby: boolean,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryTimelineData>> {
    return this.albumMeta.getUserAlbumTimeline(albumId, isBaby, timeoutMs);
  }

  async getUserAlbumPhotoList(
    albumId: string,
    isBaby: boolean,
    startTime: string,
    endTime: string,
    limit: number,
    offset: number,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryGetListData>> {
    return this.albumMeta.getUserAlbumPhotoList(albumId, isBaby, startTime, endTime, limit, offset, timeoutMs);
  }

  async getUserAlbumPhotos(
    albumId: string,
    offset: number,
    limit: number,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryGetListData>> {
    return this.albumMeta.getUserAlbumPhotos(albumId, offset, limit, timeoutMs);
  }

  async searchResultsByCategory(item: MediaCategoryItem, timeoutMs: number = 20000): Promise<FnClientResult<GalleryListItem[]>> {
    return this.search.searchResultsByCategory(item, timeoutMs);
  }

  async searchResultsByLocation(
    country: string,
    city: string,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryListItem[]>> {
    return this.search.searchResultsByLocation(country, city, timeoutMs);
  }

  async getCategoryPhotos(
    fileType: string,
    limit: number = 200,
    offset: number = 0
  ): Promise<FnClientResult<GalleryListItem[]>> {
    return this.search.getCategoryPhotos(fileType, limit, offset);
  }

  async getCollectGalleryList(
    startTime: string,
    endTime: string,
    limit: number,
    offset: number
  ): Promise<FnClientResult<GalleryGetListData>> {
    return this.timeline.getCollectGalleryList(startTime, endTime, limit, offset);
  }

  async getGalleryList(
    startTime: string,
    endTime: string,
    limit: number,
    offset: number,
    mode?: string
  ): Promise<FnClientResult<GalleryGetListData>> {
    return this.timeline.getGalleryList(startTime, endTime, limit, offset, mode);
  }

  async getRecentPhotos(
    startTime: string,
    endTime: string,
    limit: number,
    offset: number,
    mode?: string
  ): Promise<FnClientResult<GalleryGetListData>> {
    return this.timeline.getRecentPhotos(startTime, endTime, limit, offset, mode);
  }

  async getGalleryPhotoDetail(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<GalleryPhotoDetailData>> {
    return this.timeline.getGalleryPhotoDetail(photoId, timeoutMs);
  }

  async getFolderViewFileList(
    folderPath: string,
    limit: number = 100,
    offset: number = 0,
    desc: boolean = false,
    orderBy: number = 2,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryListItem[]>> {
    return this.folder.getFolderViewFileList(folderPath, limit, offset, desc, orderBy, timeoutMs);
  }

  async getRecycleBinList(
    offset: number,
    limit: number,
    startTime: string,
    endTime: string,
    timeoutMs: number = 25000
  ): Promise<FnClientResult<RecycleBinListData>> {
    return this.recycle.getRecycleBinList(offset, limit, startTime, endTime, timeoutMs);
  }

  async addPhotoToRecycleBin(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    return this.recycle.addPhotoToRecycleBin(photoId, timeoutMs);
  }

  async postPreviewCollect(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    return this.recycle.postPreviewCollect(photoId, timeoutMs);
  }

  async postPreviewCollectCancel(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    return this.recycle.postPreviewCollectCancel(photoId, timeoutMs);
  }

  async restoreRecycleBinPhotos(ids: number[], timeoutMs: number = 30000): Promise<FnClientResult<Object>> {
    return this.recycle.restoreRecycleBinPhotos(ids, timeoutMs);
  }

  async getRepeatPhotoList(offset: number, size: number, timeoutMs: number = 20000): Promise<FnClientResult<RepeatPhotoListData>> {
    return this.repeat.getRepeatPhotoList(offset, size, timeoutMs);
  }

  async getRepeatPhotoGroup(groupId: string, timeoutMs: number = 15000): Promise<FnClientResult<RepeatPhotoGroup>> {
    return this.repeat.getRepeatPhotoGroup(groupId, timeoutMs);
  }

  async getTaskPanelList(timeoutMs: number = 15000): Promise<FnClientResult<RepeatPhotoTaskProgress>> {
    return this.repeat.getTaskPanelList(timeoutMs);
  }

  async startRepeatPhotoCheck(checkSimilarity: boolean, timeoutMs: number = 20000): Promise<FnClientResult<Object>> {
    return this.repeat.startRepeatPhotoCheck(checkSimilarity, timeoutMs);
  }

  async keepRepeatPhoto(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    return this.repeat.keepRepeatPhoto(photoId, timeoutMs);
  }

  async excludeRepeatPhoto(photoId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    return this.repeat.excludeRepeatPhoto(photoId, timeoutMs);
  }

  async excludeRepeatPhotoGroup(groupId: string, timeoutMs: number = 15000): Promise<FnClientResult<Object>> {
    return this.repeat.excludeRepeatPhotoGroup(groupId, timeoutMs);
  }

  async mergeRepeatPhotos(groupId: string, timeoutMs: number = 30000): Promise<FnClientResult<RepeatPhotoMergeData>> {
    return this.repeat.mergeRepeatPhotos(groupId, timeoutMs);
  }
}
