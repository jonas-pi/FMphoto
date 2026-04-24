import { http } from '@kit.NetworkKit';
import { FnGalleryGetSignSpec } from '../FnGalleryAuthx';
import { FnClientResult, GalleryGetListData, GalleryTimelineData } from '../../model/FnApiTypes';
import { RawHttpResult } from './FnHttpClientCommon';

export interface VideoDecodePlayRequest {
  id: string;
  resolution: string;
  bitrate: number;
  audioIndex: number;
  videoEncoder: string;
  channels: number;
}

export interface VideoDecodePlayInfo {
  playUrl: string;
  hlsTimeSec: number;
}

export interface FnHttpClientGalleryHost {
  getBaseUrl(): string;
  getToken(): string;
  getLongToken(): string;
  registerPendingRequest(req: http.HttpRequest): void;
  unregisterPendingRequest(req: http.HttpRequest): void;
  buildGalleryFetchHeaders(authxVal: string, cookieHeader: string): Record<string, string>;
  requestGalleryGetJson(pathCandidates: string[], gallerySign: FnGalleryGetSignSpec, timeoutMs: number, tryTimes: number): Promise<FnClientResult<Object>>;
  rawRequest(fullUrl: string, method: http.RequestMethod, header: Record<string, string>, bodyStr: string | undefined, timeoutMs: number, skipRemoteCert: boolean): Promise<RawHttpResult>;
}

export interface FnHttpClientUploadHost extends FnHttpClientGalleryHost {
  getWsSignKeyB64(): string;
  primeWebCookiesForPStack(webHttpsBaseNoSlash: string): void;
  getGalleryTimeline(extraParams?: Record<string, string | number | boolean>): Promise<FnClientResult<GalleryTimelineData>>;
  getGalleryList(startTime: string, endTime: string, limit: number, offset: number, mode?: string): Promise<FnClientResult<GalleryGetListData>>;
}
