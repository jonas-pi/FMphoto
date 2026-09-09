import { webview } from '@kit.ArkWeb';
import { AppSession, FN_MEDIA_BASE_URL } from '../auth/AppSession';
import { GalleryAlbumNavigation } from '../album/GalleryAlbumNavigation';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import { GalleryNetworkThumb, nasUrl, pickThumb } from '../album/GalleryAlbumCommon';
import { FnHdsSimpleChrome } from '../common/FnHdsSimpleChrome';
import { FN_SYSTEM_TOP_INSET_VP_KEY } from '../common/FnSystemAvoidArea';
import { FnFullLoadingMask, FnInlineLoading } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import { FN_PHOTO_H5_MAP, fnPhotoH5Url } from '../network/FnPhotoRoutes';
import { fnWebViewBaseUrl } from '../network/ServerUrl';
import {
  fnWebDefaultUserAgent,
  injectFnWebCookies
} from '../network/FnWebCookies';
import {
  MapPreviewBoundaryData,
  MapPreviewCenterData
} from '../model/FnApiTypes';

import {
  MapFetchResult,
  MapLatLon,
  PhotoMapBounds,
  PhotoMapMarker,
  PhotoMapPoint,
  mapBoundsFromData,
  mapCenterFromData,
  mapClampLat,
  mapClampLon,
  mapFetchMarkerPhotos,
  mapLoadPointsForBounds,
  mapOpenMarkerTitle
} from './map/MapPageData';
import {
  MAP_DEFAULT_HEIGHT_VP,
  MAP_DEFAULT_WIDTH_VP,
  MAP_GRID_LINE_SLOTS,
  MAP_MARKER_SIZE_VP,
  MAP_MIN_VP_PER_DEGREE,
  mapClampScale,
  mapFitBounds,
  mapFormatCoord,
  mapGridLatitude,
  mapGridLongitude,
  mapGridStepDegrees,
  mapScreenX,
  mapScreenY,
  mapUpdateMarkerProjection,
  mapVisibleBounds
} from './map/MapPageNativeProjection';
import {
  isFnOsLoginUrl,
  mapHandleOfficialWebSslError,
  mapOfficialWebBootstrapScript,
  mapOfficialWebHideChromeScript,
  mapOfficialWebScriptRules
} from './map/MapPageWebBridge';

const MAP_CONTENT_BG = '#FF101820';

@Entry
@Component
struct MapPage {
  private albumNavigationMode: boolean = false;
  private webController: webview.WebviewController = new webview.WebviewController();

  @StorageProp(FN_MEDIA_BASE_URL) private baseUrl: string = '';
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
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
  private albumBackHandlerToken: number = 0;

  onBackPress(): boolean {
    this.handleBack();
    return true;
  }

  private handleBack(): void {
    if (this.shouldShowOfficialWebMap()) {
      try {
        if (this.webController.accessBackward()) {
          this.webController.backward();
          return;
        }
      } catch (_e) {
      }
    }
    if (!this.albumNavigationMode || !GalleryAlbumNavigation.pop()) {
      this.getUIContext().getRouter().back();
    }
  }

  aboutToAppear(): void {
    this.albumNavigationMode = GalleryAlbumNavigation.isAvailable();
    try {
      webview.WebviewController.setWebDebuggingAccess(true);
    } catch (_e) {
    }
    if (this.albumNavigationMode) {
      this.albumBackHandlerToken = GalleryAlbumNavigation.registerBackHandler((): boolean => {
        this.handleBack();
        return true;
      });
    } else {
      const rp = this.getUIContext().getRouter().getParams() as Record<string, Object | string> | undefined;
      if (rp !== undefined && rp['baseUrl'] !== undefined) {
        this.baseUrl = String(rp['baseUrl']);
      }
    }
    if (!this.prepareOfficialWebMap()) {
      void this.loadInitialData();
    }
  }

  aboutToDisappear(): void {
    GalleryAlbumNavigation.unregisterBackHandler(this.albumBackHandlerToken);
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
    return mapOfficialWebHideChromeScript();
  }

  private officialWebBootstrapScript(): string {
    return mapOfficialWebBootstrapScript(this.webSecretB64);
  }

  /** 仅在 NAS 照片 H5（/p/...）注入，避免登录页和腾讯地图 iframe 被改写 */
  private officialWebScriptRules(): string[] {
    return mapOfficialWebScriptRules(this.webBaseUrl);
  }

  private mapPageSubtitle(): string {
    if (!this.shouldShowOfficialWebMap() && this.pointCount > 0) {
      return `${this.pointCount} 个位置`;
    }
    return '照片足迹';
  }

  private officialWebStartScripts(): ScriptItem[] {
    const script = this.officialWebBootstrapScript();
    const rules = this.officialWebScriptRules();
    if (script.length <= 0 || rules.length <= 0) {
      return [];
    }
    return [{ script: script, scriptRules: rules }];
  }

  private injectOfficialWebRuntime(): void {
    const script = this.officialWebHideChromeScript();
    if (script.length <= 0) {
      return;
    }
    try {
      void this.webController.runJavaScript(script).catch((_e: Error): void => {
      });
    } catch (_e) {
    }
  }

  private bindOfficialWebController(): void {
    try {
      this.webController.setCustomUserAgent(fnWebDefaultUserAgent());
    } catch (_e) {
    }
    if (this.webToken.length <= 0 || this.webBaseUrl.length <= 0) {
      return;
    }
    try {
      injectFnWebCookies(
        this.webBaseUrl,
        this.webToken,
        this.webBaseUrl.startsWith('https://'),
        this.webLongToken.length > 0 ? this.webLongToken : undefined
      );
    } catch (_e) {
    }
  }

  /** 拦截飞牛 /login，避免「登录成功后又被 401 踢回登录页」 */
  private blockOfficialWebLogin(url: string): boolean {
    if (!isFnOsLoginUrl(url)) {
      return false;
    }
    this.switchToNativeMapFallback('官方地图需要网页登录，已切换到原生位置视图');
    return true;
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
      const code = event.response.getResponseCode();
      const url = event.request.getRequestUrl();
      // 照片接口 401 会触发 H5 跳 /login；直接切原生图，避免登录循环
      if (code === 401 && url.indexOf('/p/api/') >= 0) {
        this.switchToNativeMapFallback('官方地图会话无效，已切换到原生位置视图');
        return;
      }
      if (!event.request.isMainFrame()) {
        return;
      }
      if (code < 400) {
        return;
      }
    } catch (_e) {
    }
    this.switchToNativeMapFallback('官方地图页面返回错误，已切换到原生位置视图');
  }

  private onOfficialWebSslError(event: OnSslErrorEventReceiveEvent): void {
    if (mapHandleOfficialWebSslError(event, this.webBaseUrl, this.baseUrl)) {
      return;
    }
    this.switchToNativeMapFallback('官方地图证书未信任，已切换到原生位置视图');
  }

  private centerFromData(data: MapPreviewCenterData | undefined): MapLatLon | null {
    return mapCenterFromData(data);
  }

  private boundsFromData(data: MapPreviewBoundaryData | undefined): PhotoMapBounds | null {
    return mapBoundsFromData(data);
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
    const fitted = mapFitBounds(bounds, this.viewWidthVp, this.viewHeightVp);
    this.centerLat = fitted.centerLat;
    this.centerLon = fitted.centerLon;
    this.vpPerDegree = fitted.vpPerDegree;
    this.updateMarkerProjection();
  }

  private visibleBounds(): PhotoMapBounds {
    return mapVisibleBounds(this.viewWidthVp, this.viewHeightVp, this.centerLat, this.centerLon, this.vpPerDegree);
  }

  private async loadPointsForBounds(bounds: PhotoMapBounds, append: boolean): Promise<void> {
    const client = AppSession.getClient();
    if (client === null) {
      this.error = '未登录';
      return;
    }
    this.points = await mapLoadPointsForBounds(bounds, this.points, append);
    this.pointCount = this.points.length;
    this.updateMarkerProjection();
  }

  private screenX(lon: number): number {
    return mapScreenX(lon, this.viewWidthVp, this.centerLon, this.vpPerDegree);
  }

  private screenY(lat: number): number {
    return mapScreenY(lat, this.viewHeightVp, this.centerLat, this.vpPerDegree);
  }

  private updateMarkerProjection(): void {
    this.markers = mapUpdateMarkerProjection(this.points, this.viewWidthVp, this.viewHeightVp, this.centerLat, this.centerLon, this.vpPerDegree);
  }

  private async fetchMarkerPhotos(marker: PhotoMapMarker): Promise<MapFetchResult> {
    return mapFetchMarkerPhotos(marker);
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
      const title = mapOpenMarkerTitle(marker.count);
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
    return mapGridStepDegrees(this.vpPerDegree);
  }

  private gridLongitude(slot: number): number {
    return mapGridLongitude(slot, this.centerLon, this.viewWidthVp, this.vpPerDegree);
  }

  private gridLatitude(slot: number): number {
    return mapGridLatitude(slot, this.centerLat, this.viewHeightVp, this.vpPerDegree);
  }

  private formatCoord(value: number, lat: boolean): string {
    return mapFormatCoord(value, lat);
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
      .onControllerAttached((): void => {
        this.bindOfficialWebController();
      })
      .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
        try {
          if (!event.data.isMainFrame()) {
            return false;
          }
          return this.blockOfficialWebLogin(event.data.getRequestUrl());
        } catch (_e) {
          return false;
        }
      })
      .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
        try {
          if (!request.isMainFrame()) {
            return false;
          }
          return this.blockOfficialWebLogin(request.getRequestUrl());
        } catch (_e) {
          return false;
        }
      })
      .onPageBegin((event: OnPageBeginEvent): void => {
        if (this.blockOfficialWebLogin(event.url)) {
          this.webLoading = false;
          return;
        }
        this.webLoading = true;
      })
      .onPageEnd((event: OnPageEndEvent): void => {
        this.webLoading = false;
        if (isFnOsLoginUrl(event.url)) {
          return;
        }
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
      FnHdsSimpleChrome({
        title: '地图',
        subtitle: this.mapPageSubtitle(),
        topSafeInsetVp: this.systemTopInsetVp,
        onBack: (): void => {
          this.handleBack();
        }
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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

@Builder
export function MapPageNavigationContent() {
  MapPage()
}
