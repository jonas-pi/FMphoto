import { webview } from '@kit.ArkWeb';
import { AppSession } from '../auth/AppSession';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import { GalleryNetworkThumb, nasUrl, pickThumb } from '../album/GalleryAlbumCommon';
import { FnFullLoadingMask, FnInlineLoading, FnTopBar } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import { CertPolicy } from '../network/CertPolicy';
import { FN_PHOTO_H5_MAP, fnPhotoH5Url } from '../network/FnPhotoRoutes';
import { fnWebViewBaseUrl } from '../network/ServerUrl';
import {
  fnWebDocumentCookieBootstrapScript,
  fnWebLocalStorageSecretInjectScript,
  injectFnWebCookies
} from '../network/FnWebCookies';
import {
  GalleryGetListData,
  GalleryListItem,
  MapPreviewAllPointData,
  MapPreviewAllPointItem,
  MapPreviewBoundaryData,
  MapPreviewCenterData,
  MapTimelineData,
  MapTimelineItem
} from '../model/FnApiTypes';

type MapLooseRecord = Record<string, Object | string | number | boolean | undefined | null>;

interface PhotoMapBounds {
  north: number;
  east: number;
  south: number;
  west: number;
}

interface PhotoMapPoint {
  key: string;
  lat: number;
  lon: number;
  count: number;
  coverRel: string;
  poster?: GalleryListItem;
  embedded: GalleryListItem[];
}

interface PhotoMapMarker {
  key: string;
  x: number;
  y: number;
  lat: number;
  lon: number;
  count: number;
  coverRel: string;
  bounds: PhotoMapBounds;
  embedded: GalleryListItem[];
}

interface MapFetchResult {
  items: GalleryListItem[];
  total: number;
  message: string;
}

interface MapLatLon {
  lat: number;
  lon: number;
}

const MAP_PAGE_LIMIT = 220;
const MAP_MARKER_GRID_VP = 92;
const MAP_MARKER_SIZE_VP = 62;
const MAP_MIN_VP_PER_DEGREE = 1.2;
const MAP_MAX_VP_PER_DEGREE = 6400;
const MAP_DEFAULT_WIDTH_VP = 360;
const MAP_DEFAULT_HEIGHT_VP = 720;
const MAP_GRID_LINE_SLOTS: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
const MAP_GRID_STEPS: number[] = [
  0.001, 0.002, 0.005,
  0.01, 0.02, 0.05,
  0.1, 0.2, 0.5,
  1, 2, 5,
  10, 20, 30,
  45, 90
];
const MAP_CONTENT_BG = '#FF101820';

function mapAsRecord(value: Object | string | number | boolean | undefined | null): MapLooseRecord | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }
  return value as MapLooseRecord;
}

function mapTrimmedString(value: Object | string | number | boolean | undefined | null): string {
  if (typeof value === 'string') {
    return value.trim();
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value).trim();
  }
  return '';
}

function mapReadString(raw: MapLooseRecord, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const text = mapTrimmedString(raw[keys[i]]);
    if (text.length > 0 && text !== 'null') {
      return text;
    }
  }
  return '';
}

function mapReadNumber(raw: MapLooseRecord, keys: string[]): number {
  for (let i = 0; i < keys.length; i++) {
    const value = raw[keys[i]];
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
    if (typeof value === 'string') {
      const n = Number(value.trim());
      if (Number.isFinite(n)) {
        return n;
      }
    }
  }
  return Number.NaN;
}

function mapPointCount(raw: MapLooseRecord): number {
  const n = mapReadNumber(raw, ['count', 'itemCount', 'item_count', 'photoCount', 'photo_count', 'total']);
  return Number.isFinite(n) ? Math.max(1, Math.floor(n)) : 1;
}

function mapItemsFromListData(data: GalleryGetListData | undefined): GalleryListItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  return data.list ?? data.items ?? data.photos ?? data.records ?? [];
}

function mapTimelineItemsFromData(data: MapTimelineData | undefined): MapTimelineItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  return data.list ?? data.items ?? data.records ?? data.rows ?? data.points ?? data.markers ?? data.clusters ?? [];
}

function mapPreviewPointsFromData(data: MapPreviewAllPointData | undefined): MapPreviewAllPointItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  return data.list ?? data.items ?? data.records ?? data.rows ?? data.points ?? data.markers ?? data.clusters ?? [];
}

function mapPad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function mapDayRange(year: number, month: number, day: number): string[] {
  return [
    `${year}:${mapPad2(month)}:${mapPad2(day)} 00:00:00`,
    `${year}:${mapPad2(month)}:${mapPad2(day)} 23:59:59`
  ];
}

function mapTimelineRange(item: MapTimelineItem): string[] {
  const raw = item as MapLooseRecord;
  const directStart = mapReadString(raw, ['start_time', 'startTime']);
  const directEnd = mapReadString(raw, ['end_time', 'endTime']);
  if (directStart.length > 0 && directEnd.length > 0) {
    return [directStart, directEnd];
  }
  const year = mapReadNumber(raw, ['year']);
  const month = mapReadNumber(raw, ['month']);
  const day = mapReadNumber(raw, ['day']);
  if (Number.isFinite(year) && Number.isFinite(month) && Number.isFinite(day) && day > 0) {
    return mapDayRange(Math.floor(year), Math.floor(month), Math.floor(day));
  }
  if (Number.isFinite(year) && Number.isFinite(month) && month > 0) {
    const y = Math.floor(year);
    const m = Math.floor(month);
    const last = new Date(y, m, 0).getDate();
    return [`${y}:${mapPad2(m)}:01 00:00:00`, `${y}:${mapPad2(m)}:${mapPad2(last)} 23:59:59`];
  }
  if (Number.isFinite(year)) {
    const y = Math.floor(year);
    return [`${y}:01:01 00:00:00`, `${y}:12:31 23:59:59`];
  }
  return ['', ''];
}

function mapBoundsToParams(bounds: PhotoMapBounds): Record<string, string | number | boolean> {
  const params: Record<string, string | number | boolean> = {};
  params['north'] = bounds.north;
  params['east'] = bounds.east;
  params['south'] = bounds.south;
  params['west'] = bounds.west;
  params['lonVert'] = 0;
  params['isBlank'] = false;
  return params;
}

function mapClampLat(value: number): number {
  return Math.max(-85, Math.min(85, value));
}

function mapClampLon(value: number): number {
  return Math.max(-180, Math.min(180, value));
}

function mapClampScale(value: number): number {
  return Math.max(MAP_MIN_VP_PER_DEGREE, Math.min(MAP_MAX_VP_PER_DEGREE, value));
}

@Entry
@Component
struct MapPage {
  private webController: webview.WebviewController = new webview.WebviewController();

  @State private baseUrl: string = '';
  @State private officialMapUrl: string = '';
  @State private webBaseUrl: string = '';
  @State private webLoading: boolean = false;
  @State private webFailed: boolean = false;
  @State private webError: string = '';
  @State private loading: boolean = false;
  @State private opening: boolean = false;
  @State private error: string = '';
  @State private pointCount: number = 0;
  @State private markers: PhotoMapMarker[] = [];
  @State private viewWidthVp: number = MAP_DEFAULT_WIDTH_VP;
  @State private viewHeightVp: number = MAP_DEFAULT_HEIGHT_VP;
  @State private centerLat: number = 35.8617;
  @State private centerLon: number = 104.1954;
  @State private vpPerDegree: number = 6;

  private points: PhotoMapPoint[] = [];
  private initialCenter: MapLatLon = { lat: 35.8617, lon: 104.1954 };
  private initialBounds: PhotoMapBounds | null = null;
  private hasFittedInitialBounds: boolean = false;
  private loadedAllBoundaryPoints: boolean = false;
  private userMovedMap: boolean = false;
  private panStartCenterLat: number = 35.8617;
  private panStartCenterLon: number = 104.1954;
  private pinchStartVpPerDegree: number = 6;
  private webToken: string = '';
  private webLongToken: string = '';
  private webSecretB64: string = '';

  onBackPress(): boolean {
    if (this.shouldShowOfficialWebMap()) {
      try {
        if (this.webController.accessBackward()) {
          this.webController.backward();
          return true;
        }
      } catch (_e) {
      }
    }
    this.getUIContext().getRouter().back();
    return true;
  }

  aboutToAppear(): void {
    const rp = this.getUIContext().getRouter().getParams() as Record<string, Object | string> | undefined;
    if (rp !== undefined && rp['baseUrl'] !== undefined) {
      this.baseUrl = String(rp['baseUrl']);
    }
    if (!this.prepareOfficialWebMap()) {
      void this.loadInitialData();
    }
  }

  aboutToDisappear(): void {
    const client = AppSession.getClient();
    if (client !== null) {
      client.cancelPendingRequests();
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {
    }
  }

  private shouldShowOfficialWebMap(): boolean {
    return this.officialMapUrl.length > 0 && !this.webFailed;
  }

  private prepareOfficialWebMap(): boolean {
    const stored = AppSession.getStored();
    const base = this.baseUrl.length > 0 ? this.baseUrl : (stored !== null ? stored.baseUrl : '');
    if (stored === null || base.length <= 0 || stored.token.length <= 0) {
      this.webFailed = true;
      this.webError = '飞牛官方地图会话不可用';
      return false;
    }
    this.baseUrl = base;
    this.webBaseUrl = fnWebViewBaseUrl(base);
    this.officialMapUrl = fnPhotoH5Url(this.webBaseUrl, FN_PHOTO_H5_MAP);
    this.webToken = stored.token;
    this.webLongToken = stored.fnosLongToken;
    this.webSecretB64 = stored.wsSignKeyB64;
    this.webFailed = false;
    this.webError = '';
    this.webLoading = true;
    try {
      injectFnWebCookies(
        this.webBaseUrl,
        this.webToken,
        this.webBaseUrl.startsWith('https://'),
        this.webLongToken.length > 0 ? this.webLongToken : undefined
      );
    } catch (_e) {
    }
    return true;
  }

  private officialWebHideChromeScript(): string {
    return `(function(){function hide(){try{document.documentElement.style.paddingTop='0';document.body.style.paddingTop='0';var sels=['header','.header','.app-header','.page-header','.top-header','.layout-header','.nav-header','[class*="Header"]','[class*="header"]','[class*="top-bar"]','[class*="topBar"]','[class*="app-bar"]','[class*="navbar"]','[class*="nav-bar"]'];sels.forEach(function(sel){document.querySelectorAll(sel).forEach(function(el){var st=window.getComputedStyle(el);if(st.position==='fixed'||st.position==='sticky'||el.tagName==='HEADER'){el.style.setProperty('display','none','important');}});});document.querySelectorAll('*').forEach(function(el){if(el.childElementCount>0)return;var t=(el.textContent||'').trim();if(t==='飞牛相册'&&el.offsetHeight>0&&el.offsetHeight<80){var p=el.parentElement;for(var i=0;i<4&&p;i++){if(p.offsetHeight>0&&p.offsetHeight<120){p.style.setProperty('display','none','important');break;}p=p.parentElement;}}});}catch(e){}}hide();try{new MutationObserver(hide).observe(document.documentElement,{childList:true,subtree:true});}catch(e){}setTimeout(hide,300);setTimeout(hide,1000);})();`;
  }

  private officialWebBootstrapScript(): string {
    let script = '';
    if (this.webSecretB64.length > 0) {
      script += fnWebLocalStorageSecretInjectScript(this.webSecretB64);
    }
    if (this.webToken.length > 0) {
      script += fnWebDocumentCookieBootstrapScript(
        this.webToken,
        this.webLongToken.length > 0 ? this.webLongToken : undefined
      );
    }
    script += this.officialWebHideChromeScript();
    return script;
  }

  private mapPageSubtitle(): string {
    if (!this.shouldShowOfficialWebMap() && this.pointCount > 0) {
      return `${this.pointCount} 个位置`;
    }
    return '照片足迹';
  }

  private officialWebStartScripts(): ScriptItem[] {
    const script = this.officialWebBootstrapScript();
    if (script.length <= 0) {
      return [];
    }
    return [{ script: script, scriptRules: ['.*'] }];
  }

  private injectOfficialWebRuntime(): void {
    const script = this.officialWebBootstrapScript();
    if (script.length <= 0) {
      return;
    }
    try {
      void this.webController.runJavaScript(script).catch((_e: Error): void => {
      });
    } catch (_e) {
    }
  }

  private switchToNativeMapFallback(message: string): void {
    if (this.webFailed) {
      return;
    }
    this.webFailed = true;
    this.webLoading = false;
    this.webError = message;
    this.error = '';
    if (this.points.length === 0 && !this.loading) {
      void this.loadInitialData();
    }
  }

  private onOfficialWebError(event: OnErrorReceiveEvent): void {
    try {
      if (!event.request.isMainFrame()) {
        return;
      }
    } catch (_e) {
    }
    this.switchToNativeMapFallback('官方地图页面加载失败，已切换到原生位置视图');
  }

  private onOfficialWebHttpError(event: OnHttpErrorReceiveEvent): void {
    try {
      if (!event.request.isMainFrame()) {
        return;
      }
      if (event.response.getResponseCode() < 400) {
        return;
      }
    } catch (_e) {
    }
    this.switchToNativeMapFallback('官方地图页面返回错误，已切换到原生位置视图');
  }

  private onOfficialWebSslError(event: OnSslErrorEventReceiveEvent): void {
    try {
      if (CertPolicy.isTrusted(this.webBaseUrl) || CertPolicy.isTrusted(this.baseUrl)) {
        event.handler.handleConfirm();
        return;
      }
      event.handler.handleCancel();
    } catch (_e) {
    }
    this.switchToNativeMapFallback('官方地图证书未信任，已切换到原生位置视图');
  }

  private centerFromData(data: MapPreviewCenterData | undefined): MapLatLon | null {
    if (data === undefined || data === null) {
      return null;
    }
    const raw = data as MapLooseRecord;
    const lat = mapReadNumber(raw, ['lat', 'latitude', 'centerLat', 'centerLatitude']);
    const lon = mapReadNumber(raw, ['lon', 'lng', 'longitude', 'centerLng', 'centerLongitude']);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
      return null;
    }
    return { lat: mapClampLat(lat), lon: mapClampLon(lon) };
  }

  private boundsFromData(data: MapPreviewBoundaryData | undefined): PhotoMapBounds | null {
    if (data === undefined || data === null) {
      return null;
    }
    const raw = data as MapLooseRecord;
    let south = mapReadNumber(raw, ['minLat', 'south']);
    let north = mapReadNumber(raw, ['maxLat', 'north']);
    let west = mapReadNumber(raw, ['minLon', 'minLng', 'west']);
    let east = mapReadNumber(raw, ['maxLon', 'maxLng', 'east']);
    const sw = mapAsRecord(raw['southWest']);
    const ne = mapAsRecord(raw['northEast']);
    if ((!Number.isFinite(south) || !Number.isFinite(west)) && sw !== null) {
      south = mapReadNumber(sw, ['lat', 'latitude']);
      west = mapReadNumber(sw, ['lon', 'lng', 'longitude']);
    }
    if ((!Number.isFinite(north) || !Number.isFinite(east)) && ne !== null) {
      north = mapReadNumber(ne, ['lat', 'latitude']);
      east = mapReadNumber(ne, ['lon', 'lng', 'longitude']);
    }
    if (!Number.isFinite(south) || !Number.isFinite(north) ||
      !Number.isFinite(west) || !Number.isFinite(east)) {
      return null;
    }
    const out: PhotoMapBounds = {
      south: mapClampLat(Math.min(south, north)),
      north: mapClampLat(Math.max(south, north)),
      west: mapClampLon(Math.min(west, east)),
      east: mapClampLon(Math.max(west, east))
    };
    if (out.south === out.north && out.west === out.east) {
      out.south = mapClampLat(out.south - 0.05);
      out.north = mapClampLat(out.north + 0.05);
      out.west = mapClampLon(out.west - 0.05);
      out.east = mapClampLon(out.east + 0.05);
    }
    return out;
  }

  private async loadInitialData(): Promise<void> {
    this.loading = true;
    this.error = '';
    this.points = [];
    this.markers = [];
    this.pointCount = 0;
    this.loadedAllBoundaryPoints = false;
    const client = AppSession.getClient();
    if (client === null) {
      this.loading = false;
      this.error = '未登录';
      return;
    }
    try {
      const pair = await Promise.all([
        client.getMapPreviewCenter(),
        client.getMapPreviewBoundary()
      ]);
      if (pair[0].success) {
        const center = this.centerFromData(pair[0].data);
        if (center !== null) {
          this.initialCenter = center;
          this.centerLat = center.lat;
          this.centerLon = center.lon;
        }
      }
      if (pair[1].success) {
        this.initialBounds = this.boundsFromData(pair[1].data);
      }
      this.fitInitialViewport();
      if (this.initialBounds !== null) {
        await this.loadPointsForBounds(this.initialBounds, false);
        this.loadedAllBoundaryPoints = true;
      } else {
        await this.loadPointsForBounds(this.visibleBounds(), false);
      }
      if (this.points.length === 0) {
        this.error = '暂无带位置信息的照片';
      }
    } catch (e) {
      this.error = String(e) || '地图数据加载异常';
    }
    this.loading = false;
  }

  private fitInitialViewport(): void {
    if (this.userMovedMap) {
      return;
    }
    if (this.initialBounds !== null) {
      this.fitBounds(this.initialBounds);
      this.hasFittedInitialBounds = true;
      return;
    }
    this.centerLat = this.initialCenter.lat;
    this.centerLon = this.initialCenter.lon;
    if (!this.hasFittedInitialBounds) {
      this.vpPerDegree = 6;
      this.hasFittedInitialBounds = true;
    }
    this.updateMarkerProjection();
  }

  private fitBounds(bounds: PhotoMapBounds): void {
    const lonSpan = Math.max(0.05, bounds.east - bounds.west);
    const latSpan = Math.max(0.05, bounds.north - bounds.south);
    const usableW = Math.max(180, this.viewWidthVp - 80);
    const usableH = Math.max(220, this.viewHeightVp - 210);
    this.centerLat = mapClampLat((bounds.north + bounds.south) / 2);
    this.centerLon = mapClampLon((bounds.east + bounds.west) / 2);
    this.vpPerDegree = mapClampScale(Math.min(usableW / lonSpan, usableH / latSpan));
    this.updateMarkerProjection();
  }

  private visibleBounds(): PhotoMapBounds {
    const halfLon = Math.max(0.05, this.viewWidthVp / Math.max(MAP_MIN_VP_PER_DEGREE, this.vpPerDegree) / 2);
    const halfLat = Math.max(0.05, this.viewHeightVp / Math.max(MAP_MIN_VP_PER_DEGREE, this.vpPerDegree) / 2);
    return {
      north: mapClampLat(this.centerLat + halfLat),
      south: mapClampLat(this.centerLat - halfLat),
      east: mapClampLon(this.centerLon + halfLon),
      west: mapClampLon(this.centerLon - halfLon)
    };
  }

  private async loadPointsForBounds(bounds: PhotoMapBounds, append: boolean): Promise<void> {
    const client = AppSession.getClient();
    if (client === null) {
      this.error = '未登录';
      return;
    }
    const out: PhotoMapPoint[] = append ? this.points.slice() : [];
    const latParts = Math.max(1, Math.ceil(Math.max(0.01, bounds.north - bounds.south) / 45));
    const lonParts = Math.max(1, Math.ceil(Math.max(0.01, bounds.east - bounds.west) / 60));
    for (let latIdx = 0; latIdx < latParts; latIdx++) {
      for (let lonIdx = 0; lonIdx < lonParts; lonIdx++) {
        const south = bounds.south + latIdx * 45;
        const north = Math.min(south + 45, bounds.north);
        const west = bounds.west + lonIdx * 60;
        const east = Math.min(west + 60, bounds.east);
        const res = await client.getMapPreviewAllPoint(north, east, south, west, 0, 20000);
        if (!res.success || res.data === undefined) {
          continue;
        }
        const items = mapPreviewPointsFromData(res.data);
        for (let i = 0; i < items.length; i++) {
          const point = this.pointFromApiItem(items[i]);
          if (point !== null) {
            out.push(point);
          }
        }
      }
    }
    this.points = this.mergePoints(out);
    this.pointCount = this.points.length;
    this.updateMarkerProjection();
  }

  private mergePoints(points: PhotoMapPoint[]): PhotoMapPoint[] {
    const mapByKey: Map<string, PhotoMapPoint> = new Map();
    for (let i = 0; i < points.length; i++) {
      const item = points[i];
      const key = `${item.lat.toFixed(6)},${item.lon.toFixed(6)}`;
      const old = mapByKey.get(key);
      if (old === undefined) {
        mapByKey.set(key, item);
      } else {
        old.count = Math.max(old.count, item.count);
        if (old.coverRel.length <= 0) {
          old.coverRel = item.coverRel;
        }
        if (old.embedded.length <= 0 && item.embedded.length > 0) {
          old.embedded = item.embedded;
        }
      }
    }
    return Array.from(mapByKey.values());
  }

  private pointFromApiItem(item: MapPreviewAllPointItem): PhotoMapPoint | null {
    const raw = item as MapLooseRecord;
    const lat = mapReadNumber(raw, ['lat', 'latitude']);
    const lon = mapReadNumber(raw, ['lon', 'lng', 'longitude']);
    if (!Number.isFinite(lat) || !Number.isFinite(lon) ||
      lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      return null;
    }
    const poster = mapAsRecord(raw['poster']);
    let coverRel = mapReadString(raw, ['cover', 'posterUrl', 'thumb', 'thumbnail']);
    let posterItem: GalleryListItem | undefined = undefined;
    if (poster !== null) {
      posterItem = poster as GalleryListItem;
      if (coverRel.length <= 0) {
        coverRel = this.coverFromPoster(poster);
      }
    }
    const embedded = this.embeddedPhotos(item);
    if (posterItem !== undefined && embedded.length === 0) {
      embedded.push(this.posterToGalleryItem(posterItem));
    }
    return {
      key: `${lat.toFixed(6)},${lon.toFixed(6)}`,
      lat: lat,
      lon: lon,
      count: mapPointCount(raw),
      coverRel: coverRel,
      poster: posterItem,
      embedded: embedded
    };
  }

  private coverFromPoster(raw: MapLooseRecord): string {
    const direct = mapReadString(raw, ['thumb', 'cover', 'poster', 'url', 'src']);
    if (direct.length > 0) {
      return direct;
    }
    const id = mapReadString(raw, ['id']);
    const uuid = mapReadString(raw, ['photoUUID', 'uuid']);
    if (id.length > 0 && uuid.length > 0) {
      return `/p/api/v1/stream/p/t/${id}/m/${uuid}`;
    }
    return '';
  }

  private posterToGalleryItem(item: GalleryListItem): GalleryListItem {
    const raw = item as MapLooseRecord;
    const id = mapReadString(raw, ['id']);
    const uuid = mapReadString(raw, ['photoUUID', 'uuid']);
    const out = item as GalleryListItem;
    if (id.length > 0) {
      out.id = id;
    }
    if (uuid.length > 0) {
      out.photoUUID = uuid;
    }
    if (out.thumb === undefined && id.length > 0 && uuid.length > 0) {
      out.thumb = `/p/api/v1/stream/p/t/${id}/m/${uuid}`;
    }
    if (out.originalUrl === undefined && id.length > 0 && uuid.length > 0) {
      out.originalUrl = `/p/api/v1/stream/p/t/${id}/o/${uuid}`;
    }
    return out;
  }

  private embeddedPhotos(item: MapPreviewAllPointItem): GalleryListItem[] {
    const arr = item.list ?? item.items ?? item.photos ?? item.records ?? [];
    const out: GalleryListItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      const one = arr[i];
      if (typeof one === 'object' && one !== null) {
        out.push(one as GalleryListItem);
      }
    }
    return out;
  }

  private screenX(lon: number): number {
    return this.viewWidthVp / 2 + (lon - this.centerLon) * this.vpPerDegree;
  }

  private screenY(lat: number): number {
    return this.viewHeightVp / 2 + (this.centerLat - lat) * this.vpPerDegree;
  }

  private updateMarkerProjection(): void {
    if (this.points.length === 0 || this.viewWidthVp <= 1 || this.viewHeightVp <= 1) {
      this.markers = [];
      return;
    }
    const buckets: Map<string, PhotoMapMarker> = new Map();
    const margin = MAP_MARKER_SIZE_VP * 2;
    for (let i = 0; i < this.points.length; i++) {
      const point = this.points[i];
      const x = this.screenX(point.lon);
      const y = this.screenY(point.lat);
      if (x < -margin || x > this.viewWidthVp + margin || y < -margin || y > this.viewHeightVp + margin) {
        continue;
      }
      const bx = Math.floor(x / MAP_MARKER_GRID_VP);
      const by = Math.floor(y / MAP_MARKER_GRID_VP);
      const key = `${bx}_${by}`;
      let marker = buckets.get(key);
      if (marker === undefined) {
        marker = {
          key: key,
          x: x - MAP_MARKER_SIZE_VP / 2,
          y: y - MAP_MARKER_SIZE_VP / 2,
          lat: point.lat,
          lon: point.lon,
          count: point.count,
          coverRel: point.coverRel,
          bounds: { north: point.lat, east: point.lon, south: point.lat, west: point.lon },
          embedded: point.embedded
        };
        buckets.set(key, marker);
      } else {
        marker.count += point.count;
        marker.lat = (marker.lat + point.lat) / 2;
        marker.lon = (marker.lon + point.lon) / 2;
        marker.bounds.north = Math.max(marker.bounds.north, point.lat);
        marker.bounds.south = Math.min(marker.bounds.south, point.lat);
        marker.bounds.east = Math.max(marker.bounds.east, point.lon);
        marker.bounds.west = Math.min(marker.bounds.west, point.lon);
        marker.x = this.screenX(marker.lon) - MAP_MARKER_SIZE_VP / 2;
        marker.y = this.screenY(marker.lat) - MAP_MARKER_SIZE_VP / 2;
        if (marker.coverRel.length <= 0) {
          marker.coverRel = point.coverRel;
        }
        if (marker.embedded.length < MAP_PAGE_LIMIT && point.embedded.length > 0) {
          marker.embedded = marker.embedded.concat(point.embedded);
        }
      }
    }
    this.markers = Array.from(buckets.values());
  }

  private async fetchMarkerPhotos(marker: PhotoMapMarker): Promise<MapFetchResult> {
    const client = AppSession.getClient();
    if (client === null) {
      return { items: [], total: 0, message: '未登录' };
    }
    const params = mapBoundsToParams(marker.bounds);
    const timeline = await client.getMapTimeline(params, 20000);
    let photos: GalleryListItem[] = [];
    if (timeline.success && timeline.data !== undefined) {
      const ranges = mapTimelineItemsFromData(timeline.data);
      for (let i = 0; i < ranges.length && photos.length < MAP_PAGE_LIMIT; i++) {
        const range = mapTimelineRange(ranges[i]);
        if (range[0].length <= 0 || range[1].length <= 0) {
          continue;
        }
        const res = await client.getMapPhotoList(
          range[0],
          range[1],
          Math.min(80, MAP_PAGE_LIMIT - photos.length),
          0,
          params,
          20000
        );
        if (res.success && res.data !== undefined) {
          photos = photos.concat(mapItemsFromListData(res.data));
        }
      }
    }
    if (photos.length === 0) {
      const direct = await client.getMapPhotoListByBounds(params, MAP_PAGE_LIMIT, 0, 20000);
      if (direct.success && direct.data !== undefined) {
        photos = mapItemsFromListData(direct.data);
      }
    }
    if (photos.length === 0 && marker.embedded.length > 0) {
      photos = marker.embedded;
    }
    const expectedTotal = Math.max(marker.count, photos.length);
    return {
      items: photos,
      total: expectedTotal,
      message: photos.length > 0 ? '' : '该位置暂无可预览媒体'
    };
  }

  private async openMarker(marker: PhotoMapMarker): Promise<void> {
    if (this.opening) {
      return;
    }
    this.opening = true;
    try {
      const loaded = await this.fetchMarkerPhotos(marker);
      if (loaded.items.length === 0) {
        this.toast(loaded.message);
        return;
      }
      const firstThumb = pickThumb(loaded.items[0]);
      const title = marker.count > 1 ? `地图位置 ${marker.count} 项` : '地图位置';
      const ok = await CategoryGalleryNavStore.open(
        this.baseUrl,
        title,
        loaded.items,
        this.getUIContext(),
        false,
        {
          expectedTotalCount: loaded.total,
          heroImageUri: firstThumb.length > 0 ? nasUrl(this.baseUrl, firstThumb) : '',
          columnsPerRow: 3,
          sourceKind: 'map'
        }
      );
      if (!ok) {
        this.toast('打开位置照片失败');
      }
    } finally {
      this.opening = false;
    }
  }

  private onMapAreaChange(area: Area): void {
    const width = area.width as number;
    const height = area.height as number;
    let changed = false;
    if (width > 1 && Math.abs(width - this.viewWidthVp) > 0.5) {
      this.viewWidthVp = width;
      changed = true;
    }
    if (height > 1 && Math.abs(height - this.viewHeightVp) > 0.5) {
      this.viewHeightVp = height;
      changed = true;
    }
    if (!changed) {
      return;
    }
    if (!this.userMovedMap && this.initialBounds !== null) {
      this.fitInitialViewport();
    } else {
      this.updateMarkerProjection();
    }
  }

  private onPanStart(): void {
    this.panStartCenterLat = this.centerLat;
    this.panStartCenterLon = this.centerLon;
  }

  private onPanUpdate(event: GestureEvent): void {
    this.userMovedMap = true;
    const scale = Math.max(MAP_MIN_VP_PER_DEGREE, this.vpPerDegree);
    this.centerLon = mapClampLon(this.panStartCenterLon - event.offsetX / scale);
    this.centerLat = mapClampLat(this.panStartCenterLat + event.offsetY / scale);
    this.updateMarkerProjection();
  }

  private onPanEnd(): void {
    if (!this.loadedAllBoundaryPoints && !this.loading) {
      void this.loadPointsForBounds(this.visibleBounds(), true);
    }
  }

  private onPinchStart(): void {
    this.pinchStartVpPerDegree = this.vpPerDegree;
  }

  private onPinchUpdate(event: GestureEvent): void {
    this.userMovedMap = true;
    this.vpPerDegree = mapClampScale(this.pinchStartVpPerDegree * event.scale);
    this.updateMarkerProjection();
  }

  private zoomBy(factor: number): void {
    this.userMovedMap = true;
    this.vpPerDegree = mapClampScale(this.vpPerDegree * factor);
    this.updateMarkerProjection();
  }

  private resetViewport(): void {
    this.userMovedMap = false;
    this.hasFittedInitialBounds = false;
    this.fitInitialViewport();
  }

  private gridStepDegrees(): number {
    const target = 110 / Math.max(MAP_MIN_VP_PER_DEGREE, this.vpPerDegree);
    for (let i = 0; i < MAP_GRID_STEPS.length; i++) {
      if (MAP_GRID_STEPS[i] >= target) {
        return MAP_GRID_STEPS[i];
      }
    }
    return 180;
  }

  private gridLongitude(slot: number): number {
    const step = this.gridStepDegrees();
    const leftLon = this.centerLon - this.viewWidthVp / 2 / Math.max(MAP_MIN_VP_PER_DEGREE, this.vpPerDegree);
    return Math.floor(leftLon / step) * step + slot * step;
  }

  private gridLatitude(slot: number): number {
    const step = this.gridStepDegrees();
    const topLat = this.centerLat + this.viewHeightVp / 2 / Math.max(MAP_MIN_VP_PER_DEGREE, this.vpPerDegree);
    return Math.floor(topLat / step) * step - slot * step;
  }

  private formatCoord(value: number, lat: boolean): string {
    const abs = Math.abs(value);
    const suffix = lat ? (value >= 0 ? 'N' : 'S') : (value >= 0 ? 'E' : 'W');
    if (abs >= 10) {
      return `${abs.toFixed(0)}°${suffix}`;
    }
    if (abs >= 1) {
      return `${abs.toFixed(1)}°${suffix}`;
    }
    return `${abs.toFixed(2)}°${suffix}`;
  }

  @Builder
  private gridLayer() {
    Stack() {
      ForEach(MAP_GRID_LINE_SLOTS, (slot: number) => {
        Row()
          .width(1)
          .height('100%')
          .backgroundColor('#334D6475')
          .position({ x: this.screenX(this.gridLongitude(slot)), y: 0 })
      }, (slot: number) => `lon-${slot}-${this.gridStepDegrees()}`)

      ForEach(MAP_GRID_LINE_SLOTS, (slot: number) => {
        Row()
          .width('100%')
          .height(1)
          .backgroundColor('#334D6475')
          .position({ x: 0, y: this.screenY(this.gridLatitude(slot)) })
      }, (slot: number) => `lat-${slot}-${this.gridStepDegrees()}`)

      ForEach(MAP_GRID_LINE_SLOTS, (slot: number) => {
        Text(this.formatCoord(this.gridLongitude(slot), false))
          .fontSize(10)
          .fontColor('#66FFFFFF')
          .position({ x: this.screenX(this.gridLongitude(slot)) + 4, y: 82 })
      }, (slot: number) => `lon-label-${slot}-${this.gridStepDegrees()}`)

      ForEach(MAP_GRID_LINE_SLOTS, (slot: number) => {
        Text(this.formatCoord(this.gridLatitude(slot), true))
          .fontSize(10)
          .fontColor('#66FFFFFF')
          .position({ x: 10, y: this.screenY(this.gridLatitude(slot)) + 4 })
      }, (slot: number) => `lat-label-${slot}-${this.gridStepDegrees()}`)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private mapBackdrop() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor('#FF101820')

      Row()
        .width('115%')
        .height('48%')
        .borderRadius(220)
        .backgroundColor('#1F24545F')
        .position({ x: -30, y: 110 })

      Row()
        .width('82%')
        .height('34%')
        .borderRadius(180)
        .backgroundColor('#1B435A49')
        .position({ x: 72, y: 310 })

      Row()
        .width('52%')
        .height('28%')
        .borderRadius(120)
        .backgroundColor('#183E5268')
        .position({ x: -40, y: 500 })

      this.gridLayer()
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private markerView(marker: PhotoMapMarker) {
    Stack({ alignContent: Alignment.Center }) {
      if (marker.coverRel.length > 0) {
        GalleryNetworkThumb({
          uri: nasUrl(this.baseUrl, marker.coverRel),
          isVideo: false,
          isGif: false,
          paused: false
        })
          .width(54)
          .height(54)
          .borderRadius(8)
          .clip(true)
      } else {
        Text('图')
          .width(54)
          .height(54)
          .borderRadius(8)
          .backgroundColor('#FF263238')
          .fontColor('#FFFFFFFF')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
      }
      Text(`${marker.count}`)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFFFF')
        .padding({ left: 7, right: 7, top: 3, bottom: 3 })
        .borderRadius(12)
        .backgroundColor('#FF0A84FF')
        .position({ x: 38, y: -7 })
    }
    .width(MAP_MARKER_SIZE_VP)
    .height(MAP_MARKER_SIZE_VP)
    .borderRadius(10)
    .backgroundColor('#CCFFFFFF')
    .border({ width: 2, color: '#FFFFFFFF' })
    .shadow({ radius: 14, color: '#66000000', offsetX: 0, offsetY: 6 })
    .position({ x: marker.x, y: marker.y })
    .onClick((): void => {
      void this.openMarker(marker);
    })
  }

  @Builder
  private zoomControls() {
    Column({ space: 8 }) {
      Text('+')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFFFF')
        .width(42)
        .height(42)
        .textAlign(TextAlign.Center)
        .borderRadius(10)
        .backgroundColor('#99000000')
        .onClick((): void => {
          this.zoomBy(1.7);
        })

      Text('−')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFFFF')
        .width(42)
        .height(42)
        .textAlign(TextAlign.Center)
        .borderRadius(10)
        .backgroundColor('#99000000')
        .onClick((): void => {
          this.zoomBy(1 / 1.7);
        })

      Text('⌖')
        .fontSize(21)
        .fontColor('#FFFFFFFF')
        .width(42)
        .height(42)
        .textAlign(TextAlign.Center)
        .borderRadius(10)
        .backgroundColor('#99000000')
        .onClick((): void => {
          this.resetViewport();
        })
    }
    .position({ x: this.viewWidthVp - 58, y: this.viewHeightVp - 188 })
  }

  @Builder
  private bottomStatus() {
    if (this.error.length > 0) {
      Text(this.error)
        .fontSize(13)
        .fontColor('#FFFFFFFF')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius(16)
        .backgroundColor('#AA000000')
        .position({ x: 16, y: this.viewHeightVp - 72 })
    } else if (this.loading) {
      Row({ space: 8 }) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color('#FFFFFFFF')
        Text('加载地图照片点...')
          .fontSize(13)
          .fontColor('#FFFFFFFF')
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .borderRadius(16)
      .backgroundColor('#AA000000')
      .position({ x: 16, y: this.viewHeightVp - 72 })
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private officialWebMap() {
    Web({
      src: this.officialMapUrl.length > 0 ? this.officialMapUrl : 'about:blank',
      controller: this.webController
    })
      .width('100%')
      .height('100%')
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .databaseAccess(true)
      .imageAccess(true)
      .onlineImageAccess(true)
      .zoomAccess(true)
      .geolocationAccess(false)
      .mixedMode(MixedMode.All)
      .cacheMode(CacheMode.Default)
      .runJavaScriptOnDocumentStart(this.officialWebStartScripts())
      .onPageBegin((_event: OnPageBeginEvent): void => {
        this.webLoading = true;
      })
      .onPageEnd((_event: OnPageEndEvent): void => {
        this.webLoading = false;
        this.injectOfficialWebRuntime();
      })
      .onErrorReceive((event: OnErrorReceiveEvent): void => {
        this.onOfficialWebError(event);
      })
      .onHttpErrorReceive((event: OnHttpErrorReceiveEvent): void => {
        this.onOfficialWebHttpError(event);
      })
      .onSslErrorEventReceive((event: OnSslErrorEventReceiveEvent): void => {
        this.onOfficialWebSslError(event);
      })
      .backgroundColor(MAP_CONTENT_BG)
  }

  @Builder
  private nativeFallbackMap() {
    Stack() {
      this.mapBackdrop()

      ForEach(this.markers, (marker: PhotoMapMarker) => {
        this.markerView(marker)
      }, (marker: PhotoMapMarker) => marker.key)

      this.zoomControls()
      this.bottomStatus()

      if (this.loading && this.markers.length === 0 && this.error.length === 0) {
        FnInlineLoading({ text: '加载地图照片点...' })
      }

      if (this.opening) {
        FnFullLoadingMask({ text: '加载位置照片中...' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(MAP_CONTENT_BG)
    .clip(true)
    .onAreaChange((_old: Area, area: Area): void => {
      this.onMapAreaChange(area);
    })
    .parallelGesture(
      GestureGroup(GestureMode.Parallel,
        PanGesture({
          fingers: 1,
          direction: PanDirection.All,
          distance: 2
        })
          .onActionStart((): void => {
            this.onPanStart();
          })
          .onActionUpdate((event: GestureEvent): void => {
            this.onPanUpdate(event);
          })
          .onActionEnd((): void => {
            this.onPanEnd();
          })
          .onActionCancel((): void => {
            this.onPanEnd();
          }),
        PinchGesture({ fingers: 2, distance: 1 })
          .onActionStart((): void => {
            this.onPinchStart();
          })
          .onActionUpdate((event: GestureEvent): void => {
            this.onPinchUpdate(event);
          })
      )
    )
  }

  build() {
    Column() {
      FnTopBar({
        title: '地图',
        subtitle: this.mapPageSubtitle()
      })

      Stack({ alignContent: Alignment.Center }) {
        if (this.shouldShowOfficialWebMap()) {
          this.officialWebMap()
        } else {
          this.nativeFallbackMap()
        }

        if (this.shouldShowOfficialWebMap() && this.webLoading) {
          FnInlineLoading({ text: '加载官方地图...' })
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 12, y: 0 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: -8, y: 0 });
  }
}
