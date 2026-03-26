/**
 * 单页大图/视频预览。
 *
 * 跳变修复：始终使用 objectFit.Contain 真实比例显示，配合同步缓存读取，
 * 首帧即展示正确比例的图片，页面转场用 scale+opacity，无 sharedTransition。
 *
 * 平移限位：基于视口尺寸精确计算，超界 50% 阻力，松手 EaseOut 弹回。
 */
import {
  itemFileExt,
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
import { fileIo } from '@kit.CoreFileKit';
import { GalleryAuthVideo } from './GalleryAuthVideo';
import { AppSession } from '../auth/AppSession';
import { GalleryListItem } from '../model/FnApiTypes';

// 越界阻尼系数：1.0 为无阻尼，拖拽位移与手指位移保持一致
const PAN_RESISTANCE = 1.0;
// 放大状态下的拖拽增益：补偿手势事件位移衰减，提升跟手性
const PAN_DRAG_GAIN = 1.8;
const DISMISS_THRESHOLD_Y = 96;
const DISMISS_FULL_Y = 240;

@Component
export struct GalleryPreviewSlide {
  @Prop baseUrl: string = '';
  @Prop @Watch('onItemChanged') item: GalleryListItem | null = null;
  /** 当前是否为 Swiper 可见页（用于控制视频播放器活跃态，避免串音） */
  @Prop active: boolean = true;
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
   * 父页面（GalleryPreview）触发加载原图：每次设为 true 时执行一次加载。
   * 父页面切换 Slide 后会重置为 false，下次点击"原图"再设为 true。
   */
  @Prop @Watch('onLoadOriginalReqChanged') loadOriginalReq: boolean = false;

  onZoomLockChange: (locked: boolean) => void = () => {};
  onVerticalDragProgress: (progress: number) => void = (_: number) => {};
  onVerticalDismiss: () => void = () => {};
  /** 原图加载完成后通知父页面，父页面可据此隐藏"原图"按钮 */
  onOriginalLoaded: () => void = () => {};

  @State private thumbPix: PixelMap | undefined = undefined;
  @State private fullPix: PixelMap | undefined = undefined;
  @State private showingOriginal: boolean = false;
  @State private fullLoading: boolean = false;
  @State private videoSrc: string = '';
  @State private gifUri: string = '';
  @State private previewScale: number = 1;
  @State private previewPanX: number = 0;
  @State private previewPanY: number = 0;
  @State private viewW: number = 360;
  @State private viewH: number = 780;

  private pinchBaseScale: number = 1;
  private panBaseX: number = 0;
  private panBaseY: number = 0;

  private isDark(): boolean { return this.isDarkTheme; }
  private spinnerColor(): ResourceColor { return this.isDarkTheme ? Color.White : Color.Black; }
  private hintColor(): string { return this.isDarkTheme ? '#CCCCCC' : '#666666'; }

  // ── 事件响应 ─────────────────────────────────────────────────────────────

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
  }

  onLoadOriginalReqChanged(): void {
    if (this.loadOriginalReq) {
      this.loadOriginal();
    }
  }

  onItemChanged(): void {
    this.thumbPix = undefined;
    this.fullPix = undefined;
    this.showingOriginal = false;
    this.fullLoading = false;
    this.videoSrc = '';
    this.gifUri = '';
    this.previewScale = 1;
    this.previewPanX = 0;
    this.previewPanY = 0;
    this.onZoomLockChange(false);
    this.onVerticalDragProgress(0);
    this.prepareContent();
  }

  aboutToAppear(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.prepareContent();
  }

  // ── 数据加载 ─────────────────────────────────────────────────────────────

  private prepareContent(): void {
    if (this.item === null) { return; }
    if (this.isVideo()) {
      this.videoSrc = nasUrl(this.baseUrl, pickVideo(this.item as GalleryListItem));
      return;
    }
    if (this.isGif()) {
      void this.prepareGifContent();
      return;
    }
    const tUrl = this.thumbUrl();
    if (tUrl.length === 0) { return; }
    // 优先同步读缓存，保证页面首帧即有内容（无 loading 空白）
    const cached = getThumbPixCached(tUrl);
    if (cached !== undefined) {
      this.thumbPix = cached;
      return;
    }
    void loadThumbPix(tUrl).then((p: PixelMap | undefined) => {
      this.thumbPix = p;
    });
  }

  private async prepareGifContent(): Promise<void> {
    const src = this.gifSourceUrl();
    if (src.length === 0) { return; }
    this.fullLoading = true;
    try {
      const client = AppSession.getClient();
      if (client === null) {
        this.fullLoading = false;
        return;
      }
      const buf = await client.fetchGalleryImageBuffer(src, 20000);
      if (buf === undefined || buf.byteLength === 0) {
        this.fullLoading = false;
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
      this.gifUri = `file://${tempPath}`;
    } catch (_e) {
    }
    this.fullLoading = false;
  }

  private loadOriginal(): void {
    const oUrl = this.originalUrl();
    if (oUrl.length === 0 || this.fullLoading) {
      if (this.fullPix !== undefined) { this.showingOriginal = true; }
      return;
    }
    this.fullLoading = true;
    void loadFullPix(oUrl).then((p: PixelMap | undefined) => {
      this.fullLoading = false;
      this.fullPix = p;
      this.showingOriginal = p !== undefined;
      if (this.showingOriginal) { this.onOriginalLoaded(); }
    });
  }

  // ── 工具函数 ─────────────────────────────────────────────────────────────

  private isVideo(): boolean { return this.item !== null && isVideoItem(this.item); }
  private isGif(): boolean { return this.item !== null && isGifItem(this.item); }
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
  private emitZoomLock(): void { this.onZoomLockChange(this.isImageZoomed()); }

  private maxPanX(): number { return this.previewScale > 1 ? this.viewW * (this.previewScale - 1) / 2 : 0; }
  private maxPanY(): number { return this.previewScale > 1 ? this.viewH * (this.previewScale - 1) / 2 : 0; }

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

  // ── UI ───────────────────────────────────────────────────────────────────

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.isVideo()) {
        // 视频：鉴权 AVPlayer + Surface；勿在外层挂缩放手势，避免抢占播放控件触摸
        GalleryAuthVideo({ videoUrl: this.videoSrc, active: this.active, bottomPadding: this.videoBottomPadding })
          .width('100%')
          .height('100%')
      } else {
        Column() {
          Stack({ alignContent: Alignment.Center }) {
            if (this.isGif() && this.gifUri.length > 0) {
              // GIF 已下载完成，直接播放
              Image(this.gifUri)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
            } else if (this.isGif()) {
              // GIF 下载中，显示单一加载状态
              Column({ space: 8 }) {
                LoadingProgress().width(48).height(48).color(this.spinnerColor())
                Text('GIF 加载中…').fontSize(13).fontColor(this.hintColor())
              }
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else if (this.thumbPix === undefined) {
              LoadingProgress().width(48).height(48).color(this.spinnerColor())
            } else {
              Image(this.showingOriginal && this.fullPix !== undefined ? this.fullPix : this.thumbPix)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
                .dynamicRangeMode(DynamicRangeMode.HIGH)
            }
            // 原图加载进度叠加层仅对普通图片显示
            if (this.fullLoading && !this.isGif()) {
              Column() {
                LoadingProgress().width(32).height(32).color(this.spinnerColor())
                Text('原图加载中…').fontSize(12).fontColor(this.hintColor()).margin({ top: 8 })
              }
              .position({ x: '50%', y: '50%' })
              .translate({ x: '-50%', y: '-50%' })
            }
          }
          .width('100%').height('100%')
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .scale({
          x: this.previewScale,
          y: this.previewScale,
          centerX: '50%', centerY: '50%'
        })
        .translate({
          x: this.isImageZoomed() ? this.previewPanX : 0,
          y: this.previewPanY
        })
        .gesture(
          GestureGroup(GestureMode.Parallel,
            PinchGesture({ fingers: 2 })
              .onActionStart((): void => {
                this.pinchBaseScale = this.previewScale;
              })
              .onActionUpdate((event: GestureEvent): void => {
                const s = Math.min(GALLERY_PREVIEW_SCALE_MAX,
                  Math.max(GALLERY_PREVIEW_SCALE_MIN, this.pinchBaseScale * event.scale));
                this.previewScale = s;
                this.previewPanX = this.clampedPanX();
                this.previewPanY = this.clampedPanY();
                this.emitZoomLock();
              })
              .onActionEnd((): void => {
                this.snapOrClamp();
                this.emitZoomLock();
              })
              .onActionCancel((): void => {
                this.snapOrClamp();
                this.emitZoomLock();
              }),
            // 未放大时仅处理纵向下拉关闭（保留 Swiper 左右切页）；
            // 放大后切换为全向拖拽，支持单指左右平移。
            PanGesture({ direction: this.isImageZoomed() ? PanDirection.All : PanDirection.Vertical })
              .onActionStart((): void => {
                this.panBaseX = this.previewPanX;
                this.panBaseY = this.previewPanY;
              })
              .onActionUpdate((event: GestureEvent): void => {
                if (this.isImageZoomed()) {
                  const nextX = this.panBaseX + event.offsetX * PAN_DRAG_GAIN;
                  const nextY = this.panBaseY + event.offsetY * PAN_DRAG_GAIN;
                  this.previewPanX = this.resist(nextX, this.maxPanX());
                  this.previewPanY = this.resist(nextY, this.maxPanY());
                  this.onVerticalDragProgress(0);
                  return;
                }
                if (event.offsetY > 0) {
                  this.previewPanY = event.offsetY;
                  this.onVerticalDragProgress(Math.min(1, this.previewPanY / DISMISS_FULL_Y));
                } else {
                  this.previewPanY = 0;
                  this.onVerticalDragProgress(0);
                }
              })
              .onActionEnd((event: GestureEvent): void => {
                if (this.isImageZoomed()) {
                  this.springBackIfNeeded();
                  this.onVerticalDragProgress(0);
                  return;
                }
                if (event.offsetY >= DISMISS_THRESHOLD_Y) {
                  this.previewPanY = 0;
                  this.onVerticalDragProgress(1);
                  this.onVerticalDismiss();
                } else {
                  this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
                    this.previewPanY = 0;
                    this.onVerticalDragProgress(0);
                  });
                }
              })
          )
        )
      }
    }
    .width('100%').height('100%')
    .backgroundColor(this.isDark() ? Color.Black : Color.White)
    .onAreaChange((_old, newArea): void => {
      const w = newArea.width as number;
      const h = newArea.height as number;
      if (w > 0) { this.viewW = w; }
      if (h > 0) { this.viewH = h; }
    })
  }
}
