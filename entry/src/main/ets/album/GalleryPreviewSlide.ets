/**
 * 单页大图/视频预览。
 *
 * 跳变修复：始终使用 objectFit.Contain 真实比例显示，配合同步缓存读取，
 * 首帧即展示正确比例的图片。跨页转场走官方 sharedTransition：
 * 官方示例把转场绑在 clip 容器上、子图铺满，宽高分别插值（非四边等比）。
 *
 * 平移限位：基于视口尺寸精确计算，超界 50% 阻力，松手 EaseOut 弹回。
 * 未放大时纵向手势对齐系统图库：下滑跟手退出（sharedTransition 收回），
 * 上滑打开与照片同层的页内详情面板。
 */
import {
  itemFileExt,
  GALLERY_PREVIEW_DOUBLE_TAP_SCALE,
  GALLERY_PREVIEW_SCALE_MAX,
  GALLERY_PREVIEW_SCALE_MIN,
  GALLERY_PREVIEW_SNAP_EPS,
  GALLERY_PREVIEW_ZOOM_EPS,
  getPreviewMidPixCached,
  getThumbPixCached,
  getThumbPixCachedByIdentity,
  isGifItem,
  isVideoItem,
  loadFullPix,
  loadPreviewMidPix,
  loadThumbPix,
  nasUrl,
  pickOriginal,
  pickPreviewThumb,
  pickThumb,
  pickVideo,
  thumbIdentityOfItem
} from './GalleryAlbumCommon';
import { common } from '@kit.AbilityKit';
import { AnimatorResult, curves, display } from '@kit.ArkUI';
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
  GALLERY_SHARED_TRANSITION_DURATION,
  galleryContainFrame,
  galleryPixelAspect,
  gallerySharedTransitionId,
  gallerySharedTransitionOptions
} from './GallerySharedTransition';
import {
  GALLERY_DETAILS_DISTANCE_VP,
  GALLERY_DETAILS_DRAG_GAIN,
  GALLERY_ANIMATOR_FRAME_RATE,
  GALLERY_SHEET_SPRING_DAMPING,
  GALLERY_SHEET_SPRING_STIFFNESS,
  GALLERY_VERTICAL_ANIMATOR_EASING,
  GALLERY_VERTICAL_PAN_DISTANCE,
  addGalleryPreviewDetailsFitListener,
  galleryDetailsMediumHeightVp,
  galleryDetailsFit,
  galleryDismissProgress,
  galleryDismissScale,
  galleryIsVideoBrightnessVolumeZone,
  GalleryPreviewSlideTransformUpdater,
  galleryShouldCloseDetails,
  galleryShouldDismissPage,
  galleryShouldOpenDetails,
  gallerySheetHeightFromAvoidY,
  galleryVerticalPanIsHorizontal,
  getGalleryPreviewDetailsFitNormVel,
  getGalleryPreviewDetailsSheetHeight,
  isGalleryPreviewDetailsAvoidAnimating,
  quietFinishAnimator,
  removeGalleryPreviewDetailsFitListener,
  setGalleryPreviewDetailsAvoidAnimating,
  setGalleryPreviewDetailsAvoidVelocity,
  setGalleryPreviewDetailsFitNormVel,
  setGalleryPreviewDetailsSheetHeight,
  setGalleryPreviewDismissProgress
} from './GalleryPreviewVerticalGesture';

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
  /** 幻灯片进页即播；普通预览只展示封面 */
  @Prop autoStartVideo: boolean = false;
  /** 页内详情已展开时，下滑改为收起详情而不是退出预览。 */
  @Prop detailsShowing: boolean = false;
  /** 幻灯片关闭上下滑，避免和自动切页抢手势 */
  @Prop allowVerticalGesture: boolean = true;
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
  onVerticalDismiss: () => void = () => {};
  onVerticalDetails: () => void = () => {};
  onRequestPageSwitch: (delta: number) => void = (_: number) => {};
  /** 原图加载完成后通知父页面，父页面可据此隐藏"原图"按钮 */
  onOriginalLoaded: () => void = () => {};
  /** 原图加载失败后通知父页面，父页面可提示用户并保持可重试 */
  onOriginalLoadFailed: (msg: string) => void = (_: string) => {};
  /** 幻灯片：当前视频自然播完，由预览页决定是否切下一张 */
  onSlideshowVideoEnded: () => void = () => {};

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
  /** 一镜到底结束前不挂播放器，避免全屏封面盖住共享元素 */
  @State private videoOverlayRevealed: boolean = false;
  /** 弹出避让走官方 animateTo；为 true 时 translate 由本状态驱动，系统渲染线程插值 */
  @State private avoidAnimOn: boolean = false;
  @State private avoidAnimY: number = 0;
  /** 打断上一次 animateTo 时作废旧 onFinish，避免把位移写回已取消的终点 */
  private avoidAnimGen: number = 0;

  private pinchBaseScale: number = 1;
  private panBaseX: number = 0;
  private panBaseY: number = 0;
  private lastPanUpdateMs: number = 0;
  private thumbLoadToken: number = 0;
  private gifLoadToken: number = 0;
  private liveLoadToken: number = 0;
  private fullLoadToken: number = 0;
  /** 中档图已上屏后，忽略迟到的宫格小图回调，避免把清晰图盖回去 */
  private previewMidShown: boolean = false;
  private livePair: LivePhotoPairFiles | undefined = undefined;
  private liveLoadInFlight: boolean = false;
  private liveController: MovingPhotoViewController = new MovingPhotoViewController();
  /** onComplete 后若迟迟没有 onPrepared，超时揭开控件，避免一直盖着静帧 */
  private liveRevealTimer: number = 0;
  private videoOverlayRevealTimer: number = 0;
  private boundItemKey: string = '';
  /** 转场窗口内冻结共享元素 id，避免 active 短暂翻转变成空串 */
  private frozenHeroShareId: string = '';
  private heroIdFrozen: boolean = false;
  private heroFreezeTimer: number = 0;
  /** 转场窗口内锁住 contain 框，避免中档图比例刷新把共享元素撑飞 */
  private heroFrameFrozen: boolean = false;
  private frozenHeroFrameW: number = 0;
  private frozenHeroFrameH: number = 0;
  /** 转场结束后再升中档图，避免解码/换图打断一镜到底 */
  private pendingMidUpgrade: boolean = false;
  private pinchParticipationActive: boolean = false;
  private pinchGestureRecognizing: boolean = false;
  private deferredParentGestureResetTimer: number = 0;
  private singleFingerPanActive: boolean = false;
  private singleFingerPanLastX: number = 0;
  private singleFingerPanLastY: number = 0;
  private verticalPanActive: boolean = false;
  private verticalOffsetX: number = 0;
  private verticalOffsetY: number = 0;
  private verticalLastOffsetY: number = 0;
  private verticalLastTs: number = 0;
  private verticalVelocityY: number = 0;
  private panScale: number = 1;
  private panX: number = 0;
  private panY: number = 0;
  private transformUpdater: GalleryPreviewSlideTransformUpdater = new GalleryPreviewSlideTransformUpdater();
  private transformAnimator: AnimatorResult | undefined = undefined;
  private readonly onDetailsFitHeight = (): void => {
    this.syncDetailsAvoidTransform();
  };
  private imagePanOptions: PanGestureOptions = new PanGestureOptions({
    fingers: 1,
    direction: PanDirection.All,
    distance: GALLERY_VERTICAL_PAN_DISTANCE
  });

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
    this.previewMidShown = false;
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
    this.previewMidShown = false;
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
    if (this.active) {
      this.armHeroIdFreeze(true);
      this.upgradeToPreviewMid();
    }
    if (!this.active) {
      this.resetVerticalDragInstant();
    }
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
    // 先锁转场窗口，避免 prepare 里升中档图把 contain 框在动画中途改掉
    if (this.enableSharedTransition && this.active) {
      this.heroIdFrozen = true;
    }
    this.syncBoundItemAndPrepare();
    this.armVideoOverlayReveal();
    this.armHeroIdFreeze(this.active);
    addGalleryPreviewDetailsFitListener(this.onDetailsFitHeight);
    this.applyComposedTransform();
  }

  aboutToDisappear(): void {
    removeGalleryPreviewDetailsFitListener(this.onDetailsFitHeight);
    this.transformUpdater.lockTranslate(false);
    this.avoidAnimOn = false;
    this.avoidAnimGen++;
    this.cancelTransformAnimator();
    this.clearVideoOverlayRevealTimer();
    this.clearHeroFreezeTimer();
    if (this.enableSharedTransition && this.active) {
      this.heroIdFrozen = true;
    }
    this.invalidateAsyncLoads();
    this.disposeTransientMedia();
    this.boundItemKey = '';
    this.pinchGestureRecognizing = false;
    this.pinchParticipationActive = false;
    this.scheduleDeferredParentGestureReset();
    this.resetVerticalDragInstant();
  }

  // ── 数据加载 ─────────────────────────────────────────────────────────────

  private prepareContent(): void {
    if (this.item === null) { return; }
    this.seedContentAspectFromItemMeta();
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
    const pUrl = this.previewThumbUrl();
    if (tUrl.length === 0 && pUrl.length === 0) {
      return;
    }
    const token = ++this.thumbLoadToken;
    this.previewMidShown = false;
    const midCached = pUrl.length > 0 ? getPreviewMidPixCached(pUrl) : undefined;
    if (midCached !== undefined) {
      if (token === this.thumbLoadToken) {
        this.previewMidShown = true;
        this.thumbPix = midCached;
        this.syncContentAspect(midCached);
      }
      return;
    }
    const identity = this.item !== null ? thumbIdentityOfItem(this.item) : '';
    const gridCached = (tUrl.length > 0 ? getThumbPixCached(tUrl) : undefined) ??
      getThumbPixCachedByIdentity(identity);
    if (gridCached !== undefined) {
      if (token === this.thumbLoadToken) {
        this.thumbPix = gridCached;
        this.syncContentAspect(gridCached);
      }
    } else if (tUrl.length > 0) {
      void loadThumbPix(tUrl).then((p: PixelMap | undefined) => {
        if (token !== this.thumbLoadToken || this.previewMidShown) {
          return;
        }
        this.thumbPix = p;
        this.syncContentAspect(p);
      });
    }
    this.upgradeToPreviewMid(token);
  }

  /** 阶梯第二档：宫格小图上屏后再拉 m 档、1600px 解码，不请求原图 */
  private upgradeToPreviewMid(token?: number): void {
    if (this.isGif()) {
      return;
    }
    // 转场窗口内不换清晰度，避免宽高跳变把一镜到底撑飞
    if (this.heroIdFrozen && this.enableSharedTransition && this.active) {
      this.pendingMidUpgrade = true;
      return;
    }
    const loadToken = token !== undefined ? token : this.thumbLoadToken;
    const pUrl = this.previewThumbUrl();
    if (pUrl.length === 0) {
      return;
    }
    const midCached = getPreviewMidPixCached(pUrl);
    if (midCached !== undefined) {
      if (loadToken === this.thumbLoadToken) {
        this.previewMidShown = true;
        this.thumbPix = midCached;
        this.syncContentAspect(midCached);
      }
      return;
    }
    void loadPreviewMidPix(pUrl).then((p: PixelMap | undefined) => {
      if (loadToken !== this.thumbLoadToken || p === undefined) {
        return;
      }
      this.previewMidShown = true;
      this.thumbPix = p;
      this.syncContentAspect(p);
    });
  }

  private currentItemKey(): string {
    if (this.item === null || this.item.id === undefined || this.item.id === null) {
      return '';
    }
    return String(this.item.id);
  }

  /** 仅当前可见页参与配对；转场窗口内冻结 id，避免空串导致官方定义下不构成共享元素 */
  private heroShareId(): string {
    if (!this.enableSharedTransition) {
      this.frozenHeroShareId = '';
      this.heroIdFrozen = false;
      return '';
    }
    const nextId = gallerySharedTransitionId(this.currentItemKey());
    if (this.active && nextId.length > 0) {
      this.frozenHeroShareId = nextId;
      return nextId;
    }
    if (this.heroIdFrozen && this.frozenHeroShareId.length > 0) {
      return this.frozenHeroShareId;
    }
    return '';
  }

  private clearHeroFreezeTimer(): void {
    if (this.heroFreezeTimer === 0) {
      return;
    }
    try {
      clearTimeout(this.heroFreezeTimer);
    } catch (_e) {
    }
    this.heroFreezeTimer = 0;
  }

  private armHeroIdFreeze(isActiveSlide: boolean): void {
    if (!this.enableSharedTransition || !isActiveSlide) {
      return;
    }
    const nextId = gallerySharedTransitionId(this.currentItemKey());
    if (nextId.length > 0) {
      this.frozenHeroShareId = nextId;
    }
    this.heroIdFrozen = true;
    this.lockHeroFrameIfPossible();
    this.clearHeroFreezeTimer();
    this.heroFreezeTimer = setTimeout((): void => {
      this.heroFreezeTimer = 0;
      this.finishHeroFreeze();
    }, GALLERY_SHARED_TRANSITION_DURATION + 80);
  }

  private lockHeroFrameIfPossible(): void {
    const frame = galleryContainFrame(this.heroAspectForFrame(), this.viewW, this.viewH);
    if (frame.w > 0 && frame.h > 0) {
      this.frozenHeroFrameW = frame.w;
      this.frozenHeroFrameH = frame.h;
      this.heroFrameFrozen = true;
    }
  }

  private finishHeroFreeze(): void {
    this.heroIdFrozen = false;
    this.heroFrameFrozen = false;
    if (this.pendingMidUpgrade) {
      this.pendingMidUpgrade = false;
      this.upgradeToPreviewMid();
    }
  }

  private seedContentAspectFromItemMeta(): void {
    if (this.contentAspect > 0) {
      return;
    }
    const meta = this.itemMetaAspect();
    if (meta > 0) {
      this.contentAspect = meta;
    }
  }

  private itemMetaAspect(): number {
    if (this.item === null) {
      return 0;
    }
    const raw = this.item as Record<string, string | number | Object | undefined>;
    const w = Number(raw['width']);
    const h = Number(raw['height']);
    if (Number.isFinite(w) && Number.isFinite(h) && w > 0 && h > 0) {
      return w / h;
    }
    return 0;
  }

  /** 宫格源是 1:1；未知比例按正方形 contain，不要先铺满再收缩（那就是动画逃逸） */
  private heroAspectForFrame(): number {
    if (this.contentAspect > 0) {
      return this.contentAspect;
    }
    const meta = this.itemMetaAspect();
    if (meta > 0) {
      return meta;
    }
    return 1;
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
      this.applyComposedTransform();
    }
  }

  /** 全屏预览默认 Contain 框；转场中锁框，未知比例按 1:1 对齐宫格 */
  private heroFrameW(): Length {
    if (this.heroFrameFrozen && this.frozenHeroFrameW > 0) {
      return this.frozenHeroFrameW;
    }
    const frame = galleryContainFrame(this.heroAspectForFrame(), this.viewW, this.viewH);
    if (frame.w <= 0) {
      return 1;
    }
    return frame.w;
  }

  private heroFrameH(): Length {
    if (this.heroFrameFrozen && this.frozenHeroFrameH > 0) {
      return this.frozenHeroFrameH;
    }
    const frame = galleryContainFrame(this.heroAspectForFrame(), this.viewW, this.viewH);
    if (frame.h <= 0) {
      return 1;
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
      this.resetVerticalDragInstant();
      this.singleFingerPanActive = false;
      this.singleFingerPanLastX = 0;
      this.singleFingerPanLastY = 0;
      this.pinchGestureRecognizing = false;
      this.pinchParticipationActive = false;
      this.scheduleDeferredParentGestureReset();
      this.heroFrameFrozen = false;
      this.pendingMidUpgrade = false;
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

  private clearVideoOverlayRevealTimer(): void {
    if (this.videoOverlayRevealTimer !== 0) {
      clearTimeout(this.videoOverlayRevealTimer);
      this.videoOverlayRevealTimer = 0;
    }
  }

  /** 共享元素走完再挂播放器，避免全屏封面抢在动画前面 */
  private armVideoOverlayReveal(): void {
    this.clearVideoOverlayRevealTimer();
    if (!this.isVideo()) {
      this.videoOverlayRevealed = true;
      return;
    }
    if (!this.enableSharedTransition || this.autoStartVideo || !this.active) {
      this.videoOverlayRevealed = true;
      return;
    }
    this.videoOverlayRevealed = false;
    this.videoOverlayRevealTimer = setTimeout((): void => {
      this.videoOverlayRevealTimer = 0;
      this.videoOverlayRevealed = true;
    }, GALLERY_SHARED_TRANSITION_DURATION);
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
    this.resetVerticalDragInstant();
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
  private previewThumbUrl(): string {
    return this.item !== null ? nasUrl(this.baseUrl, pickPreviewThumb(this.item)) : '';
  }
  private originalUrl(): string { return this.item !== null ? nasUrl(this.baseUrl, pickOriginal(this.item)) : ''; }
  private isImageZoomed(): boolean { return !this.isVideo() && this.previewScale > 1 + GALLERY_PREVIEW_ZOOM_EPS; }
  private emitZoomLock(): void {
    this.cancelDeferredParentGestureReset();
    this.onZoomLockChange(this.isImageZoomed());
    this.syncImagePanDistance();
  }

  private syncImagePanDistance(): void {
    this.imagePanOptions.setDistance(
      this.isImageZoomed() ? PREVIEW_ZOOM_PAN_DISTANCE : GALLERY_VERTICAL_PAN_DISTANCE
    );
  }

  private lockParentForVertical(active: boolean): void {
    if (active) {
      this.onPinchGestureActiveChange(true);
      return;
    }
    if (!this.pinchParticipationActive) {
      this.onPinchGestureActiveChange(false);
    }
  }

  private noteVerticalVelocity(offsetY: number): void {
    const now = Date.now();
    if (this.verticalLastTs > 0) {
      const dt = now - this.verticalLastTs;
      if (dt > 0) {
        this.verticalVelocityY = (offsetY - this.verticalLastOffsetY) / dt * 1000;
      }
    }
    this.verticalLastOffsetY = offsetY;
    this.verticalLastTs = now;
  }

  private resetVerticalDragInstant(): void {
    this.cancelTransformAnimator();
    this.verticalPanActive = false;
    this.verticalOffsetX = 0;
    this.verticalOffsetY = 0;
    this.verticalLastOffsetY = 0;
    this.verticalLastTs = 0;
    this.verticalVelocityY = 0;
    this.panScale = 1;
    this.panX = 0;
    this.panY = 0;
    this.applyComposedTransform();
    setGalleryPreviewDismissProgress(0);
  }

  private cancelTransformAnimator(): void {
    quietFinishAnimator(this.transformAnimator);
    this.transformAnimator = undefined;
  }

  private applyComposedTransform(): void {
    // 上滑跟手与页内详情让位共用同一套 translate，避免松手换公式时停一拍。
    const dragH = gallerySheetHeightFromAvoidY(this.panY);
    const sheetH = getGalleryPreviewDetailsSheetHeight();
    const fit = galleryDetailsFit(
      Math.max(sheetH, dragH),
      this.viewW,
      this.viewH,
      this.contentAspect
    );
    const dismissing = this.panY > 0;
    const extraX = dismissing ? this.panX : 0;
    const extraY = dismissing ? this.panY : 0;
    this.transformUpdater.apply(this.panScale * fit.scale, extraX, extraY + fit.translateY);
  }

  /**
   * 页内详情弹出/收回使用 animateTo 弹簧插值 translate。
   * 不要在 onFinish 里切换 translate 绑定来源（会闪一帧）；结束回调尽量不用。
   * 文档：arkts-attribute-animation-apis、bpta-fair-use-animation、arkts-spring-curve
   */
  private syncDetailsAvoidTransform(): void {
    if (!this.active) {
      this.applyComposedTransform();
      return;
    }
    const dragH = gallerySheetHeightFromAvoidY(this.panY);
    const sheetH = getGalleryPreviewDetailsSheetHeight();
    const fit = galleryDetailsFit(
      Math.max(sheetH, dragH),
      this.viewW,
      this.viewH,
      this.contentAspect
    );
    const toScale = this.panScale * fit.scale;
    const toY = (this.panY > 0 ? this.panY : 0) + fit.translateY;
    if (!isGalleryPreviewDetailsAvoidAnimating()) {
      // 详情已展开：继续停在让位位置，不要把 translate 清 0（会跳回全屏中心）。
      if (this.avoidAnimOn) {
        this.avoidAnimY = toY;
        this.transformUpdater.apply(toScale, 0, toY);
        return;
      }
      this.applyComposedTransform();
      return;
    }
    const fromY = this.avoidAnimOn ? this.avoidAnimY : this.transformUpdater.getTranslateY();
    if (Math.abs(fromY - toY) < 0.5) {
      this.avoidAnimGen++;
      this.settleAvoidPropertyAnim(toY, toScale);
      return;
    }
    this.transformUpdater.lockTranslate(true);
    this.avoidAnimGen++;
    const gen = this.avoidAnimGen;
    const vel = getGalleryPreviewDetailsFitNormVel();
    // overlapDuration：官方弹簧打断时平滑衔接，避免先跳到旧终点再归位
    const curve = Math.abs(vel) > 0.02 ?
      curves.interpolatingSpring(vel, 1, GALLERY_SHEET_SPRING_STIFFNESS, GALLERY_SHEET_SPRING_DAMPING) :
      curves.springMotion(0.347, 1.0, 0.25);
    this.getUIContext().animateTo({
      curve: curve,
      expectedFrameRateRange: GALLERY_ANIMATOR_FRAME_RATE,
      onFinish: (): void => {
        // 官方：被打断的动画会 REMOVED 并立刻 onFinish；旧回调不能再写终点
        if (gen !== this.avoidAnimGen) {
          return;
        }
        this.settleAvoidPropertyAnim(toY, toScale);
      }
    }, (): void => {
      this.avoidAnimOn = true;
      this.avoidAnimY = toY;
      // scale 与 translate 在同一个 animateTo 中提交，确保图片一次到达最终几何，
      // 不再在位置弹簧结束后由 settle 突然切到另一缩放值。
      this.transformUpdater.apply(toScale, 0, toY);
    });
  }

  /** 只同步终点，不切换 .translate 绑定来源（官方：尽量不要用结束回调做时序） */
  private settleAvoidPropertyAnim(toY: number, toScale: number): void {
    setGalleryPreviewDetailsAvoidAnimating(false);
    this.avoidAnimY = toY;
    this.transformUpdater.apply(toScale, 0, toY);
    if (Math.abs(toY) >= 0.5) {
      this.transformUpdater.lockTranslate(true);
      this.avoidAnimOn = true;
      return;
    }
    // 归位后仍走 avoidAnimY=0，跟手开始时再交给 AttributeUpdater
    this.transformUpdater.lockTranslate(false);
  }

  private beginVerticalPan(): void {
    if (!this.allowVerticalGesture) {
      return;
    }
    this.cancelTransformAnimator();
    this.haltLivePlayback();
    this.verticalPanActive = true;
    this.verticalLastTs = 0;
    this.verticalVelocityY = 0;
    this.lockParentForVertical(true);
    // 跟手改走 AttributeUpdater；先对齐再关 avoidAnimOn，避免 translate 换绑闪一帧
    if (this.avoidAnimOn) {
      this.transformUpdater.lockTranslate(false);
      this.avoidAnimOn = false;
      // 从详情态开始下滑时先按当前详情高度恢复组合变换，避免解锁 translate 的一帧缩放跳变。
      this.applyComposedTransform();
    }
  }

  private applyVerticalOffset(offsetX: number, offsetY: number): void {
    if (!this.allowVerticalGesture) {
      return;
    }
    this.verticalOffsetX = offsetX;
    this.verticalOffsetY = offsetY;
    this.noteVerticalVelocity(offsetY);
    if (this.detailsShowing) {
      // 详情已展开时，下滑先收详情，不进入预览页退出缩放。
      const expandedH = galleryDetailsMediumHeightVp(this.viewH);
      const nextH = Math.max(0, Math.min(expandedH, expandedH - Math.max(0, offsetY)));
      setGalleryPreviewDetailsAvoidAnimating(false);
      setGalleryPreviewDetailsSheetHeight(nextH);
      this.panScale = 1;
      this.panX = 0;
      this.panY = 0;
      this.applyComposedTransform();
      setGalleryPreviewDismissProgress(0);
      return;
    }
    if (offsetY >= 0) {
      if (getGalleryPreviewDetailsSheetHeight() > 0) {
        setGalleryPreviewDetailsAvoidAnimating(false);
        setGalleryPreviewDetailsSheetHeight(0);
      }
      const progress = galleryDismissProgress(offsetY, this.viewH);
      // 起手已锁定为纵向退出后，横向分量继续跟手，不再交给 Swiper 切图。
      this.panX = offsetX;
      this.panY = offsetY;
      this.panScale = galleryDismissScale(progress);
      this.applyComposedTransform();
      setGalleryPreviewDismissProgress(progress);
      return;
    }
    const capped = Math.max(offsetY, -this.viewH * 0.36);
    this.panX = 0;
    this.panY = capped * GALLERY_DETAILS_DRAG_GAIN;
    this.panScale = 1;
    // 面板与照片一起从底部跟手出现，松手后再吸附到展开或关闭终点。
    setGalleryPreviewDetailsAvoidAnimating(false);
    setGalleryPreviewDetailsSheetHeight(gallerySheetHeightFromAvoidY(this.panY));
    this.applyComposedTransform();
    // 上滑只用于详情页，保持预览背景完全遮挡上一级页面。
    setGalleryPreviewDismissProgress(0);
  }

  private springVerticalHome(): void {
    this.verticalOffsetY = 0;
    this.verticalLastTs = 0;
    this.verticalVelocityY = 0;
    const fromScale = this.panScale;
    const fromX = this.panX;
    const fromY = this.panY;
    if (!this.detailsShowing && getGalleryPreviewDetailsSheetHeight() > 0) {
      setGalleryPreviewDetailsAvoidAnimating(true);
      setGalleryPreviewDetailsSheetHeight(0);
    }
    if (Math.abs(fromScale - 1) < 0.002 && Math.abs(fromY) < 0.5) {
      this.panScale = 1;
      this.panX = 0;
      this.panY = 0;
      this.applyComposedTransform();
      setGalleryPreviewDismissProgress(0);
      return;
    }
    this.cancelTransformAnimator();
    try {
      const animator = this.getUIContext().createAnimator({
        duration: 350,
        easing: GALLERY_VERTICAL_ANIMATOR_EASING,
        delay: 0,
        fill: 'forwards',
        direction: 'normal',
        iterations: 1,
        begin: 0,
        end: 1
      });
      animator.setExpectedFrameRateRange(GALLERY_ANIMATOR_FRAME_RATE);
      animator.onFrame = (t: number): void => {
        this.panScale = fromScale + (1 - fromScale) * t;
        this.panX = fromX * (1 - t);
        this.panY = fromY * (1 - t);
        this.applyComposedTransform();
        // 遮罩与图片使用同一弹簧进度回弹，避免松手取消时背景先瞬间恢复。
        setGalleryPreviewDismissProgress(galleryDismissProgress(this.panY, this.viewH));
      };
      animator.onFinish = (): void => {
        this.transformAnimator = undefined;
        this.panScale = 1;
        this.panX = 0;
        this.panY = 0;
        this.applyComposedTransform();
        setGalleryPreviewDismissProgress(0);
      };
      this.transformAnimator = animator;
      animator.play();
    } catch (_e) {
      this.panScale = 1;
      this.panX = 0;
      this.panY = 0;
      this.applyComposedTransform();
      setGalleryPreviewDismissProgress(0);
    }
  }

  private finishVerticalPan(cancelled: boolean): void {
    if (!this.allowVerticalGesture) {
      this.verticalPanActive = false;
      return;
    }
    this.verticalPanActive = false;
    if (cancelled) {
      this.lockParentForVertical(false);
      if (this.detailsShowing) {
        setGalleryPreviewDetailsAvoidAnimating(true);
        setGalleryPreviewDetailsSheetHeight(galleryDetailsMediumHeightVp(this.viewH));
        return;
      }
      this.springVerticalHome();
      return;
    }
    if (this.detailsShowing) {
      this.lockParentForVertical(false);
      if (galleryShouldCloseDetails(this.verticalOffsetY, this.verticalVelocityY)) {
        this.onVerticalDismiss();
        return;
      }
      // 未越过关闭阈值时吸附回完全展开位置，图片和页内详情使用同一弹簧。
      const expandedH = galleryDetailsMediumHeightVp(this.viewH);
      const delta = expandedH - getGalleryPreviewDetailsSheetHeight();
      const panelVelocity = -this.verticalVelocityY;
      setGalleryPreviewDetailsFitNormVel(Math.abs(delta) > 1 ? panelVelocity / delta : 0);
      setGalleryPreviewDetailsAvoidAnimating(true);
      setGalleryPreviewDetailsSheetHeight(expandedH);
      return;
    }
    if (galleryShouldDismissPage(this.verticalOffsetY, this.verticalVelocityY, this.viewH)) {
      this.lockParentForVertical(false);
      this.onVerticalDismiss();
      return;
    }
    if (galleryShouldOpenDetails(this.verticalOffsetY, this.verticalVelocityY)) {
      // 官方：离手弹簧要继承跟手速度，从 0 起速会像急刹停顿。sheetH = -panY*2。
      // 文档：arkts-animation-smoothing
      const velSheet = -this.verticalVelocityY * GALLERY_DETAILS_DRAG_GAIN * 2;
      setGalleryPreviewDetailsAvoidVelocity(velSheet);
      this.cancelTransformAnimator();
      this.verticalOffsetY = 0;
      this.verticalLastOffsetY = 0;
      this.verticalLastTs = 0;
      this.verticalVelocityY = 0;
      const startH = gallerySheetHeightFromAvoidY(this.panY);
      this.panScale = 1;
      this.panX = 0;
      this.panY = 0;
      setGalleryPreviewDetailsSheetHeight(startH);
      this.applyComposedTransform();
      setGalleryPreviewDismissProgress(0);
      this.onVerticalDetails();
      this.lockParentForVertical(false);
      return;
    }
    this.lockParentForVertical(false);
    this.springVerticalHome();
  }

  private canAcceptVerticalPagePan(event: BaseGestureEvent): boolean {
    if (!this.allowVerticalGesture || this.isImageZoomed() || this.pinchGestureRecognizing) {
      return false;
    }
    const pan = event as PanGestureEvent;
    if (galleryVerticalPanIsHorizontal(pan.offsetX, pan.offsetY)) {
      return false;
    }
    return true;
  }

  private canAcceptVideoPagePan(event: BaseGestureEvent): boolean {
    if (!this.canAcceptVerticalPagePan(event)) {
      return false;
    }
    const pan = event as PanGestureEvent;
    const fingers = pan.fingerList;
    if (fingers !== undefined && fingers.length > 0 &&
      galleryIsVideoBrightnessVolumeZone(fingers[0].localX, fingers[0].localY, this.viewW, this.viewH)) {
      return false;
    }
    return true;
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
      event.stopPropagation();
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      event.stopPropagation();
      this.finishSingleFingerPan();
    }
  }

  /**
   * 唯一共享元素容器：id 只挂这一层，内层封面/实况/GIF/原图切换不改配对。
   * 官方 Exchange 只过渡位置与大小，不支持内容过渡；转场窗口内勿拆掉此节点。
   */
  @Builder
  private heroSharedLayer() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isVideo()) {
        if (this.thumbPix !== undefined) {
          Image(this.thumbPix)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .autoResize(false)
            .hitTestBehavior(HitTestMode.None)
            .draggable(false)
        }
        // 播控挂在整页 Stack 上，不能放进 contain 画框，否则矮视频会把进度条抬到屏幕中间
      } else if (this.isLive()) {
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
      } else if (this.isGif() && this.gifUri.length > 0) {
        Image(this.gifUri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .autoResize(false)
          .syncLoad(true)
          .draggable(false)
      } else if (this.isGif() || this.thumbPix === undefined) {
        Column()
          .width('100%')
          .height('100%')
      } else {
        Image(this.showingOriginal && this.fullPix !== undefined ? this.fullPix : this.thumbPix)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .autoResize(false)
          .interpolation(ImageInterpolation.High)
          .dynamicRangeMode(DynamicRangeMode.HIGH)
          .syncLoad(true)
          .draggable(false)
      }
    }
    .width(this.heroFrameW())
    .height(this.heroFrameH())
    .clip(true)
    .sharedTransition(this.heroShareId(), gallerySharedTransitionOptions())
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.Center }) {
      if (this.isVideo()) {
        Stack({ alignContent: Alignment.Center }) {
          this.heroSharedLayer()
          if (this.videoOverlayRevealed) {
            GalleryAuthVideo({
              videoUrl: this.videoSrc,
              active: this.active,
              bottomPadding: this.videoBottomPadding,
              maxResolutionP: this.videoMaxResolutionP(),
              autoStart: this.autoStartVideo,
              detailsShowing: this.detailsShowing,
              onDetailsTapDismiss: (): void => {
                this.onVerticalDismiss();
              },
              onAutoplayEnded: (): void => {
                this.onSlideshowVideoEnded();
              }
            })
              .width('100%')
              .height('100%')
          }
        }
        .width('100%')
        .height('100%')
        .priorityGesture(
          PanGesture({
            fingers: 1,
            direction: PanDirection.All,
            distance: GALLERY_VERTICAL_PAN_DISTANCE
          })
            .onActionStart((): void => {
              this.beginVerticalPan();
            })
            .onActionUpdate((event: GestureEvent): void => {
              this.applyVerticalOffset(event.offsetX, event.offsetY);
            })
            .onActionEnd((): void => {
              this.finishVerticalPan(false);
            })
            .onActionCancel((): void => {
              this.finishVerticalPan(true);
            })
        )
        .onGestureJudgeBegin((info: GestureInfo, event: BaseGestureEvent): GestureJudgeResult => {
          if (info.type !== GestureControl.GestureType.PAN_GESTURE) {
            return GestureJudgeResult.CONTINUE;
          }
          return this.canAcceptVideoPagePan(event) ? GestureJudgeResult.CONTINUE : GestureJudgeResult.REJECT;
        })
      } else {
        Column() {
          this.heroSharedLayer()
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
        // 未放大：纵向跟手（上滑详情 / 下滑退出），横向 REJECT 给 Swiper。
        // 放大后全向拖拽平移。距离用 PanGestureOptions 动态切换。
        .gesture(
          PanGesture(this.imagePanOptions)
            .onActionStart((event: GestureEvent): void => {
              if (this.isImageZoomed()) {
                this.panBaseX = this.clampedPanX();
                this.panBaseY = this.clampedPanY();
                this.lastPanUpdateMs = 0;
                return;
              }
              this.beginVerticalPan();
              this.applyVerticalOffset(event.offsetX, event.offsetY);
            })
            .onActionUpdate((event: GestureEvent): void => {
              if (!this.isImageZoomed()) {
                this.applyVerticalOffset(event.offsetX, event.offsetY);
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
            })
            .onActionEnd((): void => {
              if (!this.isImageZoomed()) {
                this.finishVerticalPan(false);
                return;
              }
              this.springBackIfNeeded();
            })
            .onActionCancel((): void => {
              if (!this.isImageZoomed()) {
                this.finishVerticalPan(true);
                return;
              }
              this.springBackIfNeeded();
            })
        )
        .onGestureJudgeBegin((gestureInfo: GestureInfo, event: BaseGestureEvent): GestureJudgeResult => {
          if (gestureInfo.type === GestureControl.GestureType.LONG_PRESS_GESTURE) {
            return this.pinchGestureRecognizing ? GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE;
          }
          if (gestureInfo.type !== GestureControl.GestureType.PAN_GESTURE) {
            return GestureJudgeResult.CONTINUE;
          }
          if (this.isImageZoomed()) {
            return GestureJudgeResult.CONTINUE;
          }
          return this.canAcceptVerticalPagePan(event) ? GestureJudgeResult.CONTINUE : GestureJudgeResult.REJECT;
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
    .width('100%')
    .height('100%')
    .translate({ y: this.avoidAnimOn ? this.avoidAnimY : this.transformUpdater.getTranslateY() })
    .attributeModifier(this.transformUpdater)
    }
    .width('100%').height('100%')
    .clip(true)
    .backgroundColor(this.slideBackgroundColor())
    .onAreaChange((_old, newArea): void => {
      if (this.verticalPanActive || isGalleryPreviewDetailsAvoidAnimating() ||
        getGalleryPreviewDetailsSheetHeight() > 0.5) {
        return;
      }
      const w = newArea.width as number;
      const h = newArea.height as number;
      let changed = false;
      if (w > 0 && Math.abs(w - this.viewW) > 0.5) {
        this.viewW = w;
        changed = true;
      }
      if (h > 0 && Math.abs(h - this.viewH) > 0.5) {
        this.viewH = h;
        changed = true;
      }
      if (changed) {
        this.applyComposedTransform();
      }
    })
  }
}
