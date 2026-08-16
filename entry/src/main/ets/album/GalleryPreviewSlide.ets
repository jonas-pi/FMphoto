/**
 * 单页大图/视频预览。
 *
 * 跳变修复：始终使用 objectFit.Contain 真实比例显示，配合同步缓存读取，
 * 首帧即展示正确比例的图片。跨页转场走官方 sharedTransition：
 * 官方示例把转场绑在 clip 容器上、子图铺满，宽高分别插值（非四边等比）。
 *
 * 平移限位：基于视口尺寸精确计算，超界 50% 阻力，松手 EaseOut 弹回。
 */
import {
  itemFileExt,
  GALLERY_PREVIEW_DOUBLE_TAP_SCALE,
  GALLERY_PREVIEW_SCALE_MAX,
  GALLERY_PREVIEW_SCALE_MIN,
  GALLERY_PREVIEW_SNAP_EPS,
  GALLERY_PREVIEW_ZOOM_EPS,
  getThumbPixCached,
  isGifItem,
  isVideoItem,
  loadFullPix,
  loadThumbPix,
  nasUrl,
  pickOriginal,
  pickThumb,
  pickVideo
} from './GalleryAlbumCommon';
import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper, MovingPhotoView, MovingPhotoViewController } from '@kit.MediaLibraryKit';
import { GalleryAuthVideo } from './GalleryAuthVideo';
import { AppSession } from '../auth/AppSession';
import { GalleryListItem } from '../model/FnApiTypes';
import { isLivePhotoItem } from './livephoto/LivePhotoDetect';
import { GalleryLivePlayState, galleryLiveIsPlaying } from './livephoto/GalleryLivePlayState';
import { playGalleryLivePhotoHaptic } from './GallerySelectionHaptic';
import { GalleryLivePreviewLayer } from './livephoto/GalleryLivePreviewLayer';
import { GalleryLivePhotoMark } from './livephoto/GalleryLivePhotoMark';
import { GalleryHdrVividBadge } from './GalleryHdrVividBadge';
import {
  LivePhotoPairFiles,
  loadMovingPhotoFromPair,
  materializeLivePhotoPair,
  unlinkLivePhotoPair
} from './livephoto/LivePhotoSandbox';
import { GalleryPreviewEntryCache } from './GalleryPreviewEntryGate';
import {
  galleryContainFrame,
  galleryPixelAspect,
  gallerySharedTransitionId,
  gallerySharedTransitionOptions
} from './GallerySharedTransition';

// 越界阻尼系数：减小阻尼穿透，降低大图拖动时的重绘压力与抖动
const PAN_RESISTANCE = 0.55;
// 放大状态下的拖拽增益：适当降低，减少单指拖动瞬时位移导致的卡顿
const PAN_DRAG_GAIN = 1;
// 轻度放大区间（刚超过 1x）改用更保守的拖拽参数，避免“刚放大一点就卡”
const PAN_UPDATE_MIN_INTERVAL_MS = 0;
const PREVIEW_ZOOM_PAN_DISTANCE = 1;

interface GalleryPreviewTouchPoint {
  x: number;
  y: number;
}

@Component
export struct GalleryPreviewSlide {
  @Prop baseUrl: string = '';
  @Prop @Watch('onItemChanged') item: GalleryListItem | null = null;
  /** 当前是否为 Swiper 可见页（用于控制视频/实况播放器活跃态，避免串音） */
  @Prop @Watch('onActiveChanged') active: boolean = true;
  /** 幻灯片模式关闭共享元素，避免与切页动画叠在一起 */
  @Prop enableSharedTransition: boolean = true;
  /** 视频模式下，控件距屏幕底部的额外偏移（避开外部工具栏） */
  @Prop videoBottomPadding: number = 0;
  /** 跟随系统深浅色模式，用于 loading 指示器颜色 */
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  /**
   * 用 @State 镜像深色标志：@StorageProp 在嵌套方法链中依赖追踪可能丢失，
   * @State 变更则必定触发 build() 重渲染。
   */
  @State private isDarkTheme: boolean = false;
  /**
   * 父页面（GalleryPreview）触发加载原图：每次 token 变化都会执行一次加载。
   * 使用递增 token 而不是布尔值，确保“同页多次点击原图”每次都能触发。
   */
  @Prop @Watch('onLoadOriginalReqChanged') loadOriginalToken: number = 0;
  @Prop @Watch('onOriginalPreviewEnabledChanged') originalPreviewEnabled: boolean = false;

  onZoomLockChange: (locked: boolean) => void = () => {};
  onPinchGestureActiveChange: (active: boolean) => void = (_: boolean) => {};
  onVerticalDragProgress: (progress: number) => void = (_: number) => {};
  onVerticalDismiss: () => void = () => {};
  onRequestPageSwitch: (delta: number) => void = (_: number) => {};
  /** 原图加载完成后通知父页面，父页面可据此隐藏"原图"按钮 */
  onOriginalLoaded: () => void = () => {};
  /** 原图加载失败后通知父页面，父页面可提示用户并保持可重试 */
  onOriginalLoadFailed: (msg: string) => void = (_: string) => {};
  /** 当前页视频已送出首帧（或播放失败需揭层） */
  onVideoFirstFrame: () => void = () => {};

  @State private thumbPix: PixelMap | undefined = undefined;
  @State private fullPix: PixelMap | undefined = undefined;
  @State private showingOriginal: boolean = false;
  @State private fullLoading: boolean = false;
  @State private videoSrc: string = '';
  @State private gifUri: string = '';
  @State private gifTempPath: string = '';
  @State private movingPhoto: photoAccessHelper.MovingPhoto | undefined = undefined;
  @State private liveReady: boolean = false;
  /** MovingPhotoView 已出静帧且视频层就绪；此前用静帧盖住，避免切层闪烁 */
  @State private liveViewPrepared: boolean = false;
  @State private livePlayState: GalleryLivePlayState = GalleryLivePlayState.Idle;
  /** 沙箱静帧 URI，缩略图缓存未命中时垫图 */
  @State private liveStillUri: string = '';
  @State private previewScale: number = 1;
  @State private previewPanX: number = 0;
  @State private previewPanY: number = 0;
  @State private viewW: number = 360;
  @State private viewH: number = 780;
  /** 当前展示图宽高比，用于 Contain 默认框 */
  @State private contentAspect: number = 0;

  private pinchBaseScale: number = 1;
  private panBaseX: number = 0;
  private panBaseY: number = 0;
  private lastPanUpdateMs: number = 0;
  private thumbLoadToken: number = 0;
  private gifLoadToken: number = 0;
  private liveLoadToken: number = 0;
  private fullLoadToken: number = 0;
  private livePair: LivePhotoPairFiles | undefined = undefined;
  private liveLoadInFlight: boolean = false;
  private liveController: MovingPhotoViewController = new MovingPhotoViewController();
  /** onComplete 后若迟迟没有 onPrepared，超时揭开控件，避免一直盖着静帧 */
  private liveRevealTimer: number = 0;
  private boundItemKey: string = '';
  private pinchParticipationActive: boolean = false;
  private pinchGestureRecognizing: boolean = false;
  private deferredParentGestureResetTimer: number = 0;
  private singleFingerPanActive: boolean = false;
  private singleFingerPanLastX: number = 0;
  private singleFingerPanLastY: number = 0;

  private isDark(): boolean { return this.isDarkTheme; }
  private spinnerColor(): ResourceColor { return this.isDarkTheme ? Color.White : Color.Black; }
  private hintColor(): string { return this.isDarkTheme ? '#CCCCCC' : '#666666'; }
  private slideBackgroundColor(): ResourceColor {
    if (this.enableSharedTransition) {
      return Color.Transparent;
    }
    return this.isDark() ? Color.Black : Color.White;
  }

  private invalidateAsyncLoads(): void {
    this.thumbLoadToken++;
    this.gifLoadToken++;
    this.liveLoadToken++;
    this.liveLoadInFlight = false;
    this.fullLoadToken++;
  }

  private cancelDeferredParentGestureReset(): void {
    if (this.deferredParentGestureResetTimer === 0) {
      return;
    }
    try {
      clearTimeout(this.deferredParentGestureResetTimer);
    } catch (_e) {
    }
    this.deferredParentGestureResetTimer = 0;
  }

  private scheduleDeferredParentGestureReset(): void {
    this.cancelDeferredParentGestureReset();
    this.deferredParentGestureResetTimer = setTimeout((): void => {
      this.deferredParentGestureResetTimer = 0;
      this.onZoomLockChange(false);
      this.onPinchGestureActiveChange(false);
    }, 0);
  }

  private reportPinchParticipation(active: boolean): void {
    this.cancelDeferredParentGestureReset();
    if (this.pinchParticipationActive === active) {
      return;
    }
    this.pinchParticipationActive = active;
    this.onPinchGestureActiveChange(active);
  }

  private disposeTransientMedia(): void {
    this.stopLivePlayback();
    const oldGifPath = this.gifTempPath;
    const oldLive = this.livePair;
    this.thumbPix = undefined;
    this.fullPix = undefined;
    this.contentAspect = 0;
    this.showingOriginal = false;
    this.fullLoading = false;
    this.videoSrc = '';
    this.gifUri = '';
    this.gifTempPath = '';
    this.movingPhoto = undefined;
    this.liveReady = false;
    this.liveViewPrepared = false;
    this.clearLiveRevealTimer();
    this.liveStillUri = '';
    this.liveLoadInFlight = false;
    this.livePair = undefined;
    if (oldGifPath.length > 0) {
      void fileIo.unlink(oldGifPath).catch((_e: Error): void => {});
    }
    void unlinkLivePhotoPair(oldLive);
  }

  // ── 事件响应 ─────────────────────────────────────────────────────────────

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
  }

  onActiveChanged(): void {
    if (!this.isLive()) {
      return;
    }
    if (this.active) {
      void this.prepareLiveContent();
    } else {
      this.stopLivePlayback();
    }
  }

  onLoadOriginalReqChanged(): void {
    if (this.originalPreviewEnabled) {
      this.loadOriginal();
    }
  }

  onOriginalPreviewEnabledChanged(): void {
    if (this.originalPreviewEnabled) {
      this.loadOriginal();
    } else {
      this.showingOriginal = false;
    }
  }

  onItemChanged(): void {
    this.syncBoundItemAndPrepare();
  }

  aboutToAppear(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.initViewportFromDisplay();
    this.syncBoundItemAndPrepare();
  }

  aboutToDisappear(): void {
    this.invalidateAsyncLoads();
    this.disposeTransientMedia();
    this.boundItemKey = '';
    this.pinchGestureRecognizing = false;
    this.pinchParticipationActive = false;
    this.scheduleDeferredParentGestureReset();
    this.onVerticalDragProgress(0);
  }

  // ── 数据加载 ─────────────────────────────────────────────────────────────

  private prepareContent(): void {
    if (this.item === null) { return; }
    if (this.isVideo()) {
      this.videoSrc = nasUrl(this.baseUrl, pickVideo(this.item as GalleryListItem));
      this.prepareStillThumb();
      return;
    }
    if (this.isGif()) {
      this.prepareStillThumb();
      void this.prepareGifContent();
      return;
    }
    this.prepareStillThumb();
    if (this.isLive() && this.active) {
      void this.prepareLiveContent();
    }
  }

  private prepareStillThumb(): void {
    const tUrl = this.thumbUrl();
    if (tUrl.length === 0) { return; }
    const token = ++this.thumbLoadToken;
    // 优先同步读缓存，保证页面首帧即有内容（无 loading 空白）
    const cached = getThumbPixCached(tUrl);
    if (cached !== undefined) {
      if (token === this.thumbLoadToken) {
        this.thumbPix = cached;
        this.syncContentAspect(cached);
      }
      return;
    }
    void loadThumbPix(tUrl).then((p: PixelMap | undefined) => {
      if (token === this.thumbLoadToken) {
        this.thumbPix = p;
        this.syncContentAspect(p);
      }
    });
  }

  private currentItemKey(): string {
    if (this.item === null || this.item.id === undefined || this.item.id === null) {
      return '';
    }
    return String(this.item.id);
  }

  /** 仅当前可见页参与配对，左右滑后回到对应缩略图 */
  private heroShareId(): string {
    if (!this.enableSharedTransition || !this.active) {
      return '';
    }
    return gallerySharedTransitionId(this.currentItemKey());
  }

  private initViewportFromDisplay(): void {
    try {
      const d = display.getDefaultDisplaySync();
      const w = this.getUIContext().px2vp(d.width);
      const h = this.getUIContext().px2vp(d.height);
      if (w > 1) {
        this.viewW = w;
      }
      if (h > 1) {
        this.viewH = h;
      }
    } catch (_e) {
    }
  }

  private syncContentAspect(pix: PixelMap | undefined): void {
    const aspect = galleryPixelAspect(pix);
    if (aspect > 0) {
      this.contentAspect = aspect;
    }
  }

  /** 全屏预览默认 Contain 框；未知比例时铺满，避免首帧空白 */
  private heroFrameW(): Length {
    const frame = galleryContainFrame(this.contentAspect, this.viewW, this.viewH);
    if (frame.w <= 0) {
      return '100%';
    }
    return frame.w;
  }

  private heroFrameH(): Length {
    const frame = galleryContainFrame(this.contentAspect, this.viewW, this.viewH);
    if (frame.h <= 0) {
      return '100%';
    }
    return frame.h;
  }

  /** 点击切工具栏会重绘父页，@Prop item 深拷贝会被当成新对象；同一张不得中断实况加载。 */
  private syncBoundItemAndPrepare(): void {
    const key = this.currentItemKey();
    if (key.length > 0 && key === this.boundItemKey) {
      return;
    }
    if (this.boundItemKey.length > 0) {
      this.invalidateAsyncLoads();
      this.disposeTransientMedia();
      this.previewScale = 1;
      this.previewPanX = 0;
      this.previewPanY = 0;
      this.singleFingerPanActive = false;
      this.singleFingerPanLastX = 0;
      this.singleFingerPanLastY = 0;
      this.pinchGestureRecognizing = false;
      this.pinchParticipationActive = false;
      this.scheduleDeferredParentGestureReset();
      this.onVerticalDragProgress(0);
    }
    this.boundItemKey = key;
    this.prepareContent();
  }

  private stopLivePlayback(): void {
    this.haltLivePlayback();
    this.movingPhoto = undefined;
    this.liveReady = false;
    this.liveViewPrepared = false;
    this.clearLiveRevealTimer();
    this.livePlayState = GalleryLivePlayState.Idle;
  }

  private clearLiveRevealTimer(): void {
    if (this.liveRevealTimer !== 0) {
      clearTimeout(this.liveRevealTimer);
      this.liveRevealTimer = 0;
    }
  }

  /** 仅 Playing 时 stop，对齐官方「非播放态不要空 stop」。 */
  private haltLivePlayback(): void {
    if (!galleryLiveIsPlaying(this.livePlayState)) {
      return;
    }
    try {
      this.liveController.stopPlayback();
    } catch (_e) {
    }
    this.livePlayState = GalleryLivePlayState.Prepared;
  }

  private onLivePrepared(): void {
    this.livePlayState = GalleryLivePlayState.Prepared;
    this.clearLiveRevealTimer();
    // 视频层贴上后还可能有一帧合成，稍后再揭垫图
    this.liveRevealTimer = setTimeout((): void => {
      this.liveRevealTimer = 0;
      this.liveViewPrepared = true;
    }, 120);
  }

  /**
   * 静帧已进控件，但视频层可能尚未贴上。延迟揭开，避免 onComplete 瞬间卸垫图闪一帧。
   */
  private onLiveImageComplete(): void {
    if (this.liveViewPrepared) {
      return;
    }
    this.clearLiveRevealTimer();
    this.liveRevealTimer = setTimeout((): void => {
      this.liveRevealTimer = 0;
      this.liveViewPrepared = true;
    }, 180);
  }

  private onLiveStart(): void {
    this.livePlayState = GalleryLivePlayState.Playing;
    playGalleryLivePhotoHaptic();
  }

  private onLivePlaybackSettled(): void {
    if (this.liveReady) {
      this.livePlayState = GalleryLivePlayState.Prepared;
    } else {
      this.livePlayState = GalleryLivePlayState.Idle;
    }
  }

  private onPreviewPinchStart(): void {
    this.haltLivePlayback();
    this.pinchGestureRecognizing = true;
    this.pinchBaseScale = this.previewScale;
    this.reportPinchParticipation(true);
  }

  private onPreviewPinchUpdate(event: GestureEvent): void {
    const s = Math.min(GALLERY_PREVIEW_SCALE_MAX,
      Math.max(GALLERY_PREVIEW_SCALE_MIN, this.pinchBaseScale * event.scale));
    this.previewScale = s;
    this.previewPanX = this.clampedPanX();
    this.previewPanY = this.clampedPanY();
    this.emitZoomLock();
  }

  private onPreviewPinchEnd(): void {
    this.pinchGestureRecognizing = false;
    this.snapOrClamp();
    this.emitZoomLock();
    this.reportPinchParticipation(false);
  }

  private async prepareLiveContent(): Promise<void> {
    if (this.item === null || !this.isLive() || !this.active) {
      return;
    }
    if (this.liveReady && this.movingPhoto !== undefined) {
      return;
    }
    if (this.liveLoadInFlight) {
      return;
    }
    const requestKey = this.currentItemKey();
    const warmed = GalleryPreviewEntryCache.takeLive(requestKey);
    if (warmed !== undefined) {
      this.livePair = warmed.pair;
      if (warmed.pair !== undefined && warmed.pair.imageUri.length > 0) {
        this.liveStillUri = warmed.pair.imageUri;
      }
      if (warmed.moving !== undefined) {
        this.liveController = new MovingPhotoViewController();
        this.movingPhoto = warmed.moving;
        this.liveViewPrepared = false;
        this.liveReady = true;
        this.livePlayState = GalleryLivePlayState.Idle;
        return;
      }
    }
    this.liveLoadInFlight = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      let pair = this.livePair;
      if (pair === undefined) {
        pair = await materializeLivePhotoPair(ctx, this.baseUrl, this.item as GalleryListItem, false);
      }
      if (!this.active || this.currentItemKey() !== requestKey) {
        if (pair !== undefined && this.livePair === undefined) {
          void unlinkLivePhotoPair(pair);
        }
        return;
      }
      if (pair === undefined) {
        return;
      }
      this.livePair = pair;
      if (pair.imageUri.length > 0) {
        this.liveStillUri = pair.imageUri;
      }
      const moving = await loadMovingPhotoFromPair(ctx, pair);
      if (!this.active || this.currentItemKey() !== requestKey) {
        return;
      }
      if (moving === undefined) {
        return;
      }
      this.liveController = new MovingPhotoViewController();
      this.movingPhoto = moving;
      this.liveViewPrepared = false;
      this.liveReady = true;
      this.livePlayState = GalleryLivePlayState.Idle;
    } catch (_e) {
    } finally {
      if (this.currentItemKey() === requestKey) {
        this.liveLoadInFlight = false;
      }
    }
  }

  private async prepareGifContent(): Promise<void> {
    const src = this.gifSourceUrl();
    if (src.length === 0) {
      return;
    }
    const token = ++this.gifLoadToken;
    this.fullLoading = true;
    try {
      const client = AppSession.getClient();
      if (client === null) {
        return;
      }
      const buf = await client.fetchGalleryImageBuffer(src, 20000);
      if (buf === undefined || buf.byteLength === 0) {
        return;
      }
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const sid = this.item !== null && this.item.id !== undefined ? String(this.item.id) : `${Date.now()}`;
      const safeId = sid.replace(/[^a-zA-Z0-9_-]/g, '_');
      const tempPath = `${ctx.cacheDir}/preview_${safeId}.gif`;
      const f = await fileIo.open(tempPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(f.fd, buf);
      } finally {
        await fileIo.close(f.fd);
      }
      if (token !== this.gifLoadToken) {
        void fileIo.unlink(tempPath).catch(() => {});
        return;
      }
      this.gifTempPath = tempPath;
      this.gifUri = `file://${tempPath}`;
    } catch (_e) {
    } finally {
      if (token === this.gifLoadToken) {
        this.fullLoading = false;
      }
    }
  }

  private loadOriginal(): void {
    const oUrl = this.originalUrl();
    if (this.fullPix !== undefined) {
      this.showingOriginal = this.originalPreviewEnabled;
      if (this.showingOriginal) {
        this.onOriginalLoaded();
      }
      return;
    }
    if (oUrl.length === 0 || this.fullLoading) {
      if (oUrl.length === 0) {
        this.onOriginalLoadFailed('原图地址无效');
      }
      return;
    }
    this.fullLoading = true;
    const token = ++this.fullLoadToken;
    const expectedBytes = this.tryReadOriginalBytes();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void loadFullPix(oUrl, expectedBytes, ctx.cacheDir).then((p: PixelMap | undefined) => {
      if (token !== this.fullLoadToken) {
        return;
      }
      this.fullLoading = false;
      this.fullPix = p;
      if (p !== undefined && this.originalPreviewEnabled) {
        this.syncContentAspect(p);
      }
      this.showingOriginal = p !== undefined && this.originalPreviewEnabled;
      if (this.showingOriginal) {
        this.onOriginalLoaded();
      } else if (p === undefined && this.originalPreviewEnabled) {
        this.onOriginalLoadFailed('原图加载失败，已保留重试入口');
      }
    });
  }

  // ── 工具函数 ─────────────────────────────────────────────────────────────

  private isVideo(): boolean { return this.item !== null && isVideoItem(this.item); }
  private isGif(): boolean { return this.item !== null && isGifItem(this.item); }
  private isLive(): boolean { return this.item !== null && isLivePhotoItem(this.item); }

  /** 原图已走 HDR 解码并正在以 DynamicRangeMode.HIGH 显示 */
  private showHdrVividBadge(): boolean {
    if (this.isVideo() || this.isGif()) {
      return false;
    }
    if (this.originalPreviewEnabled && this.fullLoading) {
      return true;
    }
    return this.showingOriginal && this.fullPix !== undefined;
  }

  /**
   * 估算当前视频原始清晰度上限（p）：
   * - 优先使用条目里的 width/height（若服务端下发）；
   * - 采用短边作为 p 档位上限（如 1920x1080 -> 1080p）；
   * - 缺失时回退 1080，避免误伤现有流程。
   */
  private videoMaxResolutionP(): number {
    if (this.item === null) {
      return 1080;
    }
    const raw = this.item as Record<string, string | number | Object | undefined>;
    const wRaw = raw['width'];
    const hRaw = raw['height'];
    const w = Number(wRaw);
    const h = Number(hRaw);
    const wOk = Number.isFinite(w) && w > 0;
    const hOk = Number.isFinite(h) && h > 0;
    if (wOk && hOk) {
      return Math.floor(Math.min(w, h));
    }
    if (wOk) {
      return Math.floor(w);
    }
    if (hOk) {
      return Math.floor(h);
    }
    return 1080;
  }
  private tryReadOriginalBytes(): number | undefined {
    if (this.item === null) {
      return undefined;
    }
    const raw = this.item.originalSize !== undefined ? this.item.originalSize : this.item.fileSize;
    if (raw === undefined || raw === null) {
      return undefined;
    }
    const n = Number(raw);
    if (!Number.isFinite(n) || n <= 0) {
      return undefined;
    }
    return Math.floor(n);
  }
  private gifSourceUrl(): string {
    if (this.item === null) { return ''; }
    const ext = itemFileExt(this.item);
    if (ext !== 'gif') { return ''; }
    const orig = nasUrl(this.baseUrl, pickOriginal(this.item));
    if (orig.length > 0) { return orig; }
    return nasUrl(this.baseUrl, pickThumb(this.item));
  }
  private thumbUrl(): string { return this.item !== null ? nasUrl(this.baseUrl, pickThumb(this.item)) : ''; }
  private originalUrl(): string { return this.item !== null ? nasUrl(this.baseUrl, pickOriginal(this.item)) : ''; }
  private isImageZoomed(): boolean { return !this.isVideo() && this.previewScale > 1 + GALLERY_PREVIEW_ZOOM_EPS; }
  private emitZoomLock(): void {
    this.cancelDeferredParentGestureReset();
    this.onZoomLockChange(this.isImageZoomed());
  }

  private readTouchPointWindow(ev: TouchEvent): GalleryPreviewTouchPoint | null {
    if (ev.touches === undefined || ev.touches.length < 1) {
      return null;
    }
    const f0 = ev.touches[0];
    const x = f0.windowX ?? f0.displayX ?? f0.x;
    const y = f0.windowY ?? f0.displayY ?? f0.y;
    if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
      return null;
    }
    const pt: GalleryPreviewTouchPoint = { x, y };
    return pt;
  }

  private maxPanX(): number { return this.previewScale > 1 ? this.viewW * (this.previewScale - 1) / 2 : 0; }
  private maxPanY(): number { return this.previewScale > 1 ? this.viewH * (this.previewScale - 1) / 2 : 0; }
  private clampToLimit(value: number, limit: number): number {
    if (limit <= 0) { return 0; }
    return Math.min(limit, Math.max(-limit, value));
  }

  private resist(value: number, limit: number): number {
    if (limit <= 0) { return 0; }
    if (Math.abs(value) <= limit) { return value; }
    return (value > 0 ? 1 : -1) * (limit + (Math.abs(value) - limit) * PAN_RESISTANCE);
  }

  private clampedPanX(): number {
    const lx = this.maxPanX();
    return lx > 0 ? Math.min(lx, Math.max(-lx, this.previewPanX)) : 0;
  }

  private clampedPanY(): number {
    const ly = this.maxPanY();
    return ly > 0 ? Math.min(ly, Math.max(-ly, this.previewPanY)) : 0;
  }

  private snapOrClamp(): void {
    if (this.isVideo()) { return; }
    if (this.previewScale <= 1 + GALLERY_PREVIEW_SNAP_EPS) {
      this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, (): void => {
        this.previewScale = 1;
        this.previewPanX = 0;
        this.previewPanY = 0;
      });
      this.onZoomLockChange(false);
    } else {
      const cx = this.clampedPanX();
      const cy = this.clampedPanY();
      if (cx !== this.previewPanX || cy !== this.previewPanY) {
        this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, (): void => {
          this.previewPanX = cx;
          this.previewPanY = cy;
        });
      }
    }
  }

  private readGestureLocalPoint(event: GestureEvent): GalleryPreviewTouchPoint | null {
    const fl = event.fingerList;
    if (fl === undefined || fl.length < 1) {
      return null;
    }
    const f0 = fl[0];
    const x = f0.localX;
    const y = f0.localY;
    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      return null;
    }
    const pt: GalleryPreviewTouchPoint = { x: x, y: y };
    return pt;
  }

  /**
   * 官方图片预览：双击在默认尺寸与固定倍率之间切换；
   * 放大时以点击点为锚，保持该点相对视口位置不变。
   */
  private onPreviewDoubleTap(event: GestureEvent): void {
    if (this.isVideo()) {
      return;
    }
    this.haltLivePlayback();
    if (this.isImageZoomed()) {
      this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, (): void => {
        this.previewScale = 1;
        this.previewPanX = 0;
        this.previewPanY = 0;
      });
      this.onZoomLockChange(false);
      return;
    }
    const target = Math.min(GALLERY_PREVIEW_SCALE_MAX, GALLERY_PREVIEW_DOUBLE_TAP_SCALE);
    let nx = 0.5;
    let ny = 0.5;
    const tap = this.readGestureLocalPoint(event);
    if (tap !== null && this.viewW > 1 && this.viewH > 1) {
      nx = Math.max(0, Math.min(1, tap.x / this.viewW));
      ny = Math.max(0, Math.min(1, tap.y / this.viewH));
    }
    const panX = this.clampToLimit((0.5 - nx) * this.viewW * (target - 1), this.viewW * (target - 1) / 2);
    const panY = this.clampToLimit((0.5 - ny) * this.viewH * (target - 1), this.viewH * (target - 1) / 2);
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, (): void => {
      this.previewScale = target;
      this.previewPanX = panX;
      this.previewPanY = panY;
    });
    this.emitZoomLock();
  }

  private springBackIfNeeded(): void {
    const cx = this.clampedPanX();
    const cy = this.clampedPanY();
    if (cx !== this.previewPanX || cy !== this.previewPanY) {
      this.getUIContext().animateTo({ duration: 350, curve: Curve.EaseOut }, (): void => {
        this.previewPanX = cx;
        this.previewPanY = cy;
      });
    }
  }

  private finishSingleFingerPan(): void {
    if (!this.singleFingerPanActive) {
      return;
    }
    this.singleFingerPanActive = false;
    this.springBackIfNeeded();
    this.onVerticalDragProgress(0);
  }

  private handleZoomedSingleFingerTouch(event: TouchEvent): void {
    if (!this.isImageZoomed()) {
      this.finishSingleFingerPan();
      return;
    }
    if (event.touches === undefined || event.touches.length !== 1) {
      this.finishSingleFingerPan();
      return;
    }
    const pt = this.readTouchPointWindow(event);
    if (pt === null) {
      return;
    }
    if (event.type === TouchType.Down) {
      this.singleFingerPanActive = true;
      this.singleFingerPanLastX = pt.x;
      this.singleFingerPanLastY = pt.y;
      event.stopPropagation();
      return;
    }
    if (event.type === TouchType.Move) {
      if (!this.singleFingerPanActive) {
        this.singleFingerPanActive = true;
        this.singleFingerPanLastX = pt.x;
        this.singleFingerPanLastY = pt.y;
        event.stopPropagation();
        return;
      }
      const dx = pt.x - this.singleFingerPanLastX;
      const dy = pt.y - this.singleFingerPanLastY;
      this.singleFingerPanLastX = pt.x;
      this.singleFingerPanLastY = pt.y;
      this.previewPanX = this.resist(this.previewPanX + dx * PAN_DRAG_GAIN, this.maxPanX());
      this.previewPanY = this.resist(this.previewPanY + dy * PAN_DRAG_GAIN, this.maxPanY());
      this.onVerticalDragProgress(0);
      event.stopPropagation();
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      event.stopPropagation();
      this.finishSingleFingerPan();
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.isVideo()) {
        // 底层静帧参与 sharedTransition；播放器盖在上面
        Stack({ alignContent: Alignment.Center }) {
          if (this.thumbPix !== undefined) {
            Stack() {
              Image(this.thumbPix)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .autoResize(false)
                .hitTestBehavior(HitTestMode.None)
                .draggable(false)
            }
            .width(this.heroFrameW())
            .height(this.heroFrameH())
            .clip(true)
            .hitTestBehavior(HitTestMode.None)
            .sharedTransition(this.heroShareId(), gallerySharedTransitionOptions())
          }
          GalleryAuthVideo({
            videoUrl: this.videoSrc,
            active: this.active,
            bottomPadding: this.videoBottomPadding,
            maxResolutionP: this.videoMaxResolutionP(),
            onFirstFrame: (): void => {
              if (this.active) {
                this.onVideoFirstFrame();
              }
            }
          })
            .width('100%')
            .height('100%')
        }
        .width('100%')
        .height('100%')
      } else {
        Column() {
          if (this.isLive()) {
            Stack({ alignContent: Alignment.Center }) {
              if (this.liveReady && this.movingPhoto !== undefined) {
                MovingPhotoView({
                  movingPhoto: this.movingPhoto,
                  controller: this.liveController
                })
                  .width('100%')
                  .height('100%')
                  .autoPlay(false)
                  .repeatPlay(false)
                  .enableAnalyzer(false)
                  .objectFit(ImageFit.Cover)
                  .onComplete((): void => {
                    this.onLiveImageComplete();
                  })
                  .onPrepared((): void => {
                    this.onLivePrepared();
                  })
                  .onStart((): void => {
                    this.onLiveStart();
                  })
                  .onFinish((): void => {
                    this.onLivePlaybackSettled();
                  })
                  .onStop((): void => {
                    this.onLivePlaybackSettled();
                  })
                  .onPause((): void => {
                    this.onLivePlaybackSettled();
                  })
                  .onError((): void => {
                    this.livePlayState = GalleryLivePlayState.Idle;
                  })
              }
              GalleryLivePreviewLayer({
                stillUri: this.liveStillUri,
                hintColor: this.hintColor(),
                showLoading: !this.liveReady,
                thumbPix: this.liveStillUri.length > 0 ? undefined : this.thumbPix,
                fullPix: this.fullPix,
                showOriginal: this.showingOriginal,
                spinnerColor: this.spinnerColor()
              })
                .width('100%')
                .height('100%')
                .visibility(this.liveViewPrepared ? Visibility.Hidden : Visibility.Visible)
                .hitTestBehavior(HitTestMode.Transparent)
            }
            .width(this.heroFrameW())
            .height(this.heroFrameH())
            .clip(true)
            .sharedTransition(this.heroShareId(), gallerySharedTransitionOptions())
          } else {
            Stack({ alignContent: Alignment.Center }) {
              if (this.isGif() && this.gifUri.length > 0) {
                Stack() {
                  Image(this.gifUri)
                    .width('100%')
                    .height('100%')
                    .objectFit(ImageFit.Cover)
                    .autoResize(false)
                    .syncLoad(true)
                    .draggable(false)
                }
                .width(this.heroFrameW())
                .height(this.heroFrameH())
                .clip(true)
                .sharedTransition(this.heroShareId(), gallerySharedTransitionOptions())
              } else if (this.isGif()) {
                Blank()
                  .width('100%')
                  .height('100%')
              } else if (this.thumbPix === undefined) {
                Blank()
                  .width('100%')
                  .height('100%')
              } else {
                Stack() {
                  Image(this.showingOriginal && this.fullPix !== undefined ? this.fullPix : this.thumbPix)
                    .width('100%')
                    .height('100%')
                    .objectFit(ImageFit.Cover)
                    .autoResize(false)
                    .dynamicRangeMode(DynamicRangeMode.HIGH)
                    .syncLoad(true)
                    .draggable(false)
                }
                .width(this.heroFrameW())
                .height(this.heroFrameH())
                .clip(true)
                .sharedTransition(this.heroShareId(), gallerySharedTransitionOptions())
              }
            }
            .width('100%')
            .height('100%')
          }
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .parallelGesture(
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2 })
              .onAction((event: GestureEvent): void => {
                this.onPreviewDoubleTap(event);
              }),
            PinchGesture({ fingers: 2, distance: 1 })
              .onActionStart((): void => {
                this.onPreviewPinchStart();
              })
              .onActionUpdate((event: GestureEvent): void => {
                this.onPreviewPinchUpdate(event);
              })
              .onActionEnd((): void => {
                this.onPreviewPinchEnd();
              })
              .onActionCancel((): void => {
                this.onPreviewPinchEnd();
              })
          )
        , this.isLive() ? GestureMask.Normal : GestureMask.IgnoreInternal)
        // 未放大时仅处理纵向下拉关闭（保留 Swiper 左右切页）；
        // 放大后切换为全向拖拽，支持单指左右平移。
        .gesture(
          PanGesture({
            fingers: 1,
            direction: PanDirection.All,
            distance: PREVIEW_ZOOM_PAN_DISTANCE
          })
            .onActionStart((): void => {
              if (!this.isImageZoomed()) {
                return;
              }
              this.panBaseX = this.clampedPanX();
              this.panBaseY = this.clampedPanY();
              this.lastPanUpdateMs = 0;
            })
            .onActionUpdate((event: GestureEvent): void => {
              if (!this.isImageZoomed()) {
                return;
              }
              const now = Date.now();
              const minInterval = PAN_UPDATE_MIN_INTERVAL_MS;
              if (this.lastPanUpdateMs > 0 && now - this.lastPanUpdateMs < minInterval) {
                return;
              }
              this.lastPanUpdateMs = now;
              const gain = PAN_DRAG_GAIN * Math.max(1, this.previewScale);
              const nextX = this.panBaseX + event.offsetX * gain;
              const nextY = this.panBaseY + event.offsetY * gain;
              this.previewPanX = this.resist(nextX, this.maxPanX());
              this.previewPanY = this.resist(nextY, this.maxPanY());
              this.onVerticalDragProgress(0);
            })
            .onActionEnd((): void => {
              if (!this.isImageZoomed()) {
                return;
              }
              this.springBackIfNeeded();
              this.onVerticalDragProgress(0);
            })
            // 与 Swiper/系统手势竞争时 Pan 可能被 Cancel 而不走 onActionEnd，残留 previewPanY 或 dismiss 进度会导致后续上下滑「失灵」
            .onActionCancel((): void => {
              if (!this.isImageZoomed()) {
                return;
              }
              this.springBackIfNeeded();
              this.onVerticalDragProgress(0);
            })
        )
        .onGestureJudgeBegin((gestureInfo: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
          if (gestureInfo.type === GestureControl.GestureType.LONG_PRESS_GESTURE) {
            return this.pinchGestureRecognizing ? GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE;
          }
          if (gestureInfo.type !== GestureControl.GestureType.PAN_GESTURE) {
            return GestureJudgeResult.CONTINUE;
          }
          if (galleryLiveIsPlaying(this.livePlayState)) {
            return GestureJudgeResult.REJECT;
          }
          return this.isImageZoomed() ? GestureJudgeResult.CONTINUE : GestureJudgeResult.REJECT;
        })
        .scale({
          x: this.previewScale,
          y: this.previewScale,
          centerX: '50%', centerY: '50%'
        })
        .translate({
          x: this.isImageZoomed() ? this.previewPanX : 0,
          y: this.previewPanY
        })
        if (this.isGif() && this.gifUri.length === 0) {
          Column({ space: 8 }) {
            LoadingProgress().width(48).height(48).color(this.spinnerColor())
            Text('GIF 加载中…').fontSize(13).fontColor(this.hintColor())
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .hitTestBehavior(HitTestMode.Transparent)
        }
        if (!this.isGif() && this.thumbPix === undefined && !this.fullLoading) {
          Column() {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(this.spinnerColor())
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .hitTestBehavior(HitTestMode.Transparent)
        }
        if (this.fullLoading && !this.isGif()) {
          Column() {
            LoadingProgress().width(32).height(32).color(this.spinnerColor())
            Text('原图加载中…').fontSize(12).fontColor(this.hintColor()).margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }

      if (this.isLive()) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          GalleryLivePhotoMark({ sizeVp: 32, animated: true })
            .margin({ right: 16, bottom: this.videoBottomPadding + 12 })
            .hitTestBehavior(HitTestMode.Transparent)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // 外层 Stack 是 TopStart，自定义组件上的 align 不可靠；
      // 用独立 BottomStart 层定位，Transparent 让预览捏合仍可穿透。
      if (this.showHdrVividBadge()) {
        Stack({ alignContent: Alignment.BottomStart }) {
          GalleryHdrVividBadge()
            .margin({ left: 16, bottom: this.videoBottomPadding + 12 })
            .hitTestBehavior(HitTestMode.Transparent)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.slideBackgroundColor())
    .onAreaChange((_old, newArea): void => {
      const w = newArea.width as number;
      const h = newArea.height as number;
      if (w > 0) { this.viewW = w; }
      if (h > 0) { this.viewH = h; }
    })
  }
}
