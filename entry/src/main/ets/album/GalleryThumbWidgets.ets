import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryLivePhotoMark } from './livephoto/GalleryLivePhotoMark';
import { gallerySharedTransitionOptions } from './GallerySharedTransition';
import { GALLERY_THUMB_CACHE_EPOCH_KEY } from './GalleryThumbDiskCache';
import { GALLERY_FLOATING_HERO_BACKDROP_HEIGHT_VP } from './GalleryItemUrls';
import {
  enqueueThumbPaintCommit,
  getThumbIdentityCacheRank,
  getThumbPixCachedByIdentity,
  isGalleryListScrollFrozen,
  loadThumbPix,
  registerGalleryThumbFreezeResume,
  rememberThumbIdentityCache,
  thumbCacheKey,
  thumbPixCache
} from './GalleryThumbCache';

const DOMAIN = 0xFF00;
const TAG = 'GalleryDiag';
const GALLERY_FLOATING_HERO_BACKDROP_FADE_SOFT_VP = 64;
const GALLERY_FLOATING_HERO_BACKDROP_FADE_STRONG_VP = 42;
const GALLERY_FLOATING_HERO_BACKDROP_FADE_SOLID_VP = 28;

@Component
export struct GalleryThumbSkeleton {
  build() {
    Column()
      .width('100%')
      .aspectRatio(1)
      .backgroundColor($r('app.color.page_background'))
      .borderRadius(0)
  }
}

/**
 * 主列表滚动占位：纯本地 Column，不挂载 GalleryNetworkThumb（避免滚动期组件创建/异步解码路径）。
 * 与 GalleryThumbSkeleton 同色，仅语义区分供时间线行在 visualPlaceholderMode 下分支使用。
 */
@Component
export struct GalleryStaticThumbPlaceholder {
  /** 为 true 时启用轻量呼吸动画（用于滚动中提示“占位加载中”） */
  @Prop @Watch('onAnimatePulseChange') animatePulse: boolean = false;
  @State private pulseOpacity: number = 0.88;
  private pulseTimer: number = -1;
  private pulseDim: boolean = false;

  private stopPulse(): void {
    if (this.pulseTimer >= 0) {
      clearInterval(this.pulseTimer);
      this.pulseTimer = -1;
    }
    this.pulseDim = false;
    this.pulseOpacity = 0.88;
  }

  private startPulse(): void {
    this.stopPulse();
    if (!this.animatePulse) {
      return;
    }
    this.pulseTimer = setInterval((): void => {
      this.pulseDim = !this.pulseDim;
      this.pulseOpacity = this.pulseDim ? 0.70 : 0.92;
    }, 420);
  }

  onAnimatePulseChange(): void {
    this.startPulse();
  }

  aboutToAppear(): void {
    this.startPulse();
  }

  aboutToDisappear(): void {
    this.stopPulse();
  }

  build() {
    Column()
      .width('100%')
      .aspectRatio(1)
      .backgroundColor($r('app.color.page_background'))
      .opacity(this.pulseOpacity)
      .animation({ duration: 360, curve: Curve.EaseInOut })
      .borderRadius(0)
  }
}

/**
 * 网格缩略图。@Reusable + freezeWhenInactive：长列表滑出后进复用池并冻结，
 * 避免平板加列后每帧反复创建/销毁 Image（官方 List 性能实践）。
 */
@Reusable
@Component({ freezeWhenInactive: true })
export struct GalleryNetworkThumb {
  @Prop @Watch('onUriChange') uri: string = '';
  @Prop isVideo: boolean = false;
  @Prop isGif: boolean = false;
  /** 与预览页 Image.sharedTransition 配对，实现从哪来回哪去 */
  @Prop sharedTransitionId: string = '';
  /** 实况/动态照片：仅右下角标识，封面仍走静帧缩略图 */
  @Prop isLive: boolean = false;
  /** true 时仅显示骨架占位，不发起真实图加载 */
  @Prop @Watch('onPausedChange') paused: boolean = false;
  @Prop fadeInEnabled: boolean = true;
  @Prop debugLabel: string = '';
  @Prop cacheIdentity: string = '';
  @Prop cacheRank: number = 0;
  /** 磁盘落盘类型：0 不定、1 首屏、2 相册封面；见 GalleryThumbDiskCache */
  @Prop diskPersistKind: number = 0;
  /** 封面圆角；0 表示直角，由外层自行裁切 */
  @Prop clipRadius: number = 0;
  @StorageProp('colorMode') private colorMode: number = 0;
  /** NAS 缓存失效后递增，强制已挂载缩略图丢掉旧 PixelMap 并重拉 */
  @StorageProp(GALLERY_THUMB_CACHE_EPOCH_KEY) @Watch('onThumbCacheEpochChanged')
  private thumbCacheEpoch: number = 0;
  @State private pix: PixelMap | undefined = undefined;
  @State private loading: boolean = false;
  @State private pixAlpha: number = 0;
  /** 递增版本号：避免滚动复用后旧异步任务回写到新卡片 */
  private loadVersion: number = 0;
  /** 失败重试次数：用于弱网/短时请求失败后自动补偿加载 */
  private retryCount: number = 0;
  private needsUpgradeAfterResume: boolean = false;
  /** 快滑冻结时已登记松手补拉，避免重复入队 */
  private freezeResumeQueued: boolean = false;

  /**
   * @Reusable 组件切换父列表时，未显式传入的 @Prop 在极短窗口内可能为 undefined。
   * 字符串属性进入渲染和缓存逻辑前统一收口，避免复用回调触发未捕获 TypeError。
   */
  private safeString(value: string): string {
    const raw = value as Object | string | number | boolean | undefined | null;
    return typeof raw === 'string' ? raw : '';
  }

  private safeSharedTransitionId(): string {
    return this.safeString(this.sharedTransitionId);
  }

  private logDebug(message: string): void {
    const label = this.safeString(this.debugLabel);
    if (label.length <= 0) {
      return;
    }
    hilog.warn(DOMAIN, TAG, 'thumb %{public}s %{public}s uri=%{public}s',
      label, message, this.safeString(this.uri));
  }

  onUriChange(): void {
    this.logDebug('onUriChange');
    this.reloadFromScratch();
  }

  onThumbCacheEpochChanged(): void {
    this.logDebug(`onThumbCacheEpochChanged epoch=${this.thumbCacheEpoch}`);
    this.reloadFromScratch();
  }

  private reloadFromScratch(): void {
    this.loadVersion++;
    this.pix = undefined;
    this.pixAlpha = 0;
    this.loading = false;
    this.retryCount = 0;
    this.needsUpgradeAfterResume = false;
    this.freezeResumeQueued = false;
    void this.loadPix();
  }

  onPausedChange(): void {
    this.logDebug(this.paused ? 'paused' : 'resumed');
    if (!this.paused && !this.loading && (this.pix === undefined || this.needsUpgradeAfterResume)) {
      void this.loadPix();
    }
  }

  aboutToAppear(): void {
    this.logDebug('aboutToAppear');
    void this.loadPix();
  }

  aboutToReuse(_params: Record<string, Object | undefined | null>): void {
    this.loadVersion++;
    this.retryCount = 0;
    this.needsUpgradeAfterResume = false;
    this.freezeResumeQueued = false;
    this.loading = false;
    this.pix = undefined;
    this.pixAlpha = 0;
    /*
     * aboutToReuse 触发时 @Prop 可能仍是复用前的值，不能在这里按 this.uri
     * 读取缓存，否则会先把上一列表项的 PixelMap 画到新卡片上。
     * 下一事件轮次再加载，确保 uri/cacheIdentity 已完成父子同步。
     */
    const reuseVersion = this.loadVersion;
    setTimeout((): void => {
      if (reuseVersion === this.loadVersion) {
        void this.loadPix();
      }
    }, 0);
  }

  aboutToDisappear(): void {
    // 组件离屏后提升版本号，阻止旧任务回写
    this.loadVersion++;
    this.freezeResumeQueued = false;
    // 不能保留旧任务的 loading 状态，否则返回页面时 aboutToAppear 无法补拉已被淘汰的封面。
    this.loading = false;
  }

  private queueFreezeResumeIfNeeded(): void {
    if (!isGalleryListScrollFrozen() || this.freezeResumeQueued) {
      return;
    }
    this.freezeResumeQueued = true;
    const resumeVersion = this.loadVersion;
    registerGalleryThumbFreezeResume((): void => {
      if (resumeVersion !== this.loadVersion) {
        return;
      }
      this.freezeResumeQueued = false;
      void this.loadPix();
    });
  }

  private applyLoadedPix(pix: PixelMap, versionAtStart: number, uriAtStart: string): void {
    if (versionAtStart !== this.loadVersion || uriAtStart !== this.safeString(this.uri)) {
      return;
    }
    this.pix = pix;
    this.retryCount = 0;
    this.needsUpgradeAfterResume = false;
    this.logDebug('load-success');
    if (!this.fadeInEnabled) {
      this.pixAlpha = 1;
      return;
    }
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
      this.pixAlpha = 1;
    });
  }

  private async loadPix(): Promise<void> {
    const safeUri = this.safeString(this.uri);
    const safeIdentity = this.safeString(this.cacheIdentity);
    if (safeUri.length === 0 || this.loading) {
      return;
    }
    const cacheKey = thumbCacheKey(safeUri, this.isVideo);
    const cached = thumbPixCache.get(cacheKey);
    if (cached !== undefined) {
      this.pix = cached;
      this.pixAlpha = 1;
      this.retryCount = 0;
      rememberThumbIdentityCache(safeIdentity, cacheKey, this.cacheRank);
      this.needsUpgradeAfterResume = false;
      this.logDebug('cache-hit');
      return;
    }
    const reused = getThumbPixCachedByIdentity(safeIdentity);
    if (reused !== undefined) {
      this.pix = reused;
      this.pixAlpha = 1;
      this.retryCount = 0;
      const reusedRank = getThumbIdentityCacheRank(safeIdentity);
      if (reusedRank >= this.cacheRank) {
        this.needsUpgradeAfterResume = false;
        this.logDebug(`identity-hit-r${reusedRank}`);
        return;
      }
      this.needsUpgradeAfterResume = true;
      this.logDebug(`identity-hit-upgrade-r${reusedRank}->${this.cacheRank}`);
    }
    if (this.paused || isGalleryListScrollFrozen()) {
      this.logDebug(this.needsUpgradeAfterResume ? 'upgrade-deferred-paused' : 'load-skipped-paused');
      this.queueFreezeResumeIfNeeded();
      return;
    }
    this.logDebug('load-start');
    const versionAtStart = this.loadVersion;
    const uriAtStart = safeUri;
    this.loading = true;
    const pix = await loadThumbPix(
      uriAtStart,
      this.isVideo,
      safeIdentity,
      this.cacheRank,
      this.diskPersistKind
    );
    if (versionAtStart !== this.loadVersion || uriAtStart !== this.safeString(this.uri)) {
      this.loading = false;
      this.logDebug('load-stale');
      return;
    }
    this.loading = false;
    if (pix !== undefined) {
      if (!this.fadeInEnabled) {
        enqueueThumbPaintCommit((): void => {
          this.applyLoadedPix(pix, versionAtStart, uriAtStart);
        });
      } else {
        this.applyLoadedPix(pix, versionAtStart, uriAtStart);
      }
    } else if (this.retryCount < 2) {
      this.retryCount++;
      this.logDebug(`load-retry-${this.retryCount}`);
      const retryVersion = this.loadVersion;
      const delay = this.retryCount * 700;
      setTimeout((): void => {
        if (retryVersion !== this.loadVersion || (this.pix !== undefined && !this.needsUpgradeAfterResume)) {
          return;
        }
        void this.loadPix();
      }, delay);
    } else {
      this.logDebug('load-failed');
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      GalleryThumbSkeleton()
        .visibility(this.pix === undefined ? Visibility.Visible : Visibility.Hidden)
      if (this.pix !== undefined) {
        // PixelMap 已按宫格边长降采样；缩小显示用 Medium 插值（官方 Image 清晰度建议）
        Image(this.pix)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .autoResize(false)
          .interpolation(ImageInterpolation.Medium)
          .opacity(this.pixAlpha)
          .draggable(false)
      }
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(34).height(34)
          .fill('#66000000')
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(16)
          .fontColor([Color.White])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      }
      .visibility(this.isVideo ? Visibility.Visible : Visibility.None)
      .hitTestBehavior(HitTestMode.None)
      Text('GIF')
        .fontSize(10)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#66000000')
        .padding({ left: 5, right: 5, top: 2, bottom: 2 })
        .borderRadius(4)
        .position({ x: 5, y: 5 })
        .visibility(this.isGif ? Visibility.Visible : Visibility.None)
        .hitTestBehavior(HitTestMode.None)
      Column() {
        Blank().layoutWeight(1)
        Row() {
          Blank().layoutWeight(1)
          GalleryLivePhotoMark({ sizeVp: 22 })
            .margin({ right: 6, bottom: 6 })
        }
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .visibility(this.isLive && !this.isVideo ? Visibility.Visible : Visibility.None)
    }
    .width('100%')
    .aspectRatio(1)
    .borderRadius(this.clipRadius)
    .backgroundColor(this.colorMode === 1 ? '#1C1C1E' : '#F0F0F0')
    .clip(true)
    .id(this.safeSharedTransitionId().length > 0 ? `${this.safeSharedTransitionId()}_source` : '')
    .sharedTransition(this.safeSharedTransitionId(), gallerySharedTransitionOptions())
    // 防止子节点未覆盖区域仍响应系统拖拽
    .draggable(false)
    // Image/骨架会参与命中并吞掉长按与 Pan，父级 Stack 上的多选手势永远收不到；整卡不参与命中，事件落到外层图库格
    .hitTestBehavior(HitTestMode.None)
  }
}

@Component
export struct GalleryNetworkBackdropImage {
  @Prop @Watch('onUriChange') uri: string = '';
  @Prop @Watch('onPausedChange') paused: boolean = false;
  @StorageProp('colorMode') private colorMode: number = 0;
  @StorageProp(GALLERY_THUMB_CACHE_EPOCH_KEY) @Watch('onThumbCacheEpochChanged')
  private thumbCacheEpoch: number = 0;
  @State private pix: PixelMap | undefined = undefined;
  @State private loading: boolean = false;
  @State private pixAlpha: number = 0;
  private loadVersion: number = 0;
  private retryCount: number = 0;

  onUriChange(): void {
    this.loadVersion++;
    this.pix = undefined;
    this.pixAlpha = 0;
    this.loading = false;
    this.retryCount = 0;
    void this.loadPix();
  }

  onThumbCacheEpochChanged(): void {
    if (this.thumbCacheEpoch < 0) {
      return;
    }
    this.onUriChange();
  }

  onPausedChange(): void {
    if (!this.paused && this.pix === undefined && !this.loading) {
      void this.loadPix();
    }
  }

  aboutToAppear(): void {
    void this.loadPix();
  }

  aboutToDisappear(): void {
    this.loadVersion++;
  }

  private async loadPix(): Promise<void> {
    if (this.uri.length === 0 || this.loading) {
      return;
    }
    const cacheKey = thumbCacheKey(this.uri, false);
    const cached = thumbPixCache.get(cacheKey);
    if (cached !== undefined) {
      this.pix = cached;
      this.pixAlpha = 1;
      this.retryCount = 0;
      return;
    }
    if (this.paused) {
      return;
    }
    const versionAtStart = this.loadVersion;
    this.loading = true;
    const pix = await loadThumbPix(this.uri, false);
    if (versionAtStart !== this.loadVersion) {
      this.loading = false;
      return;
    }
    this.loading = false;
    if (pix !== undefined) {
      this.pix = pix;
      this.retryCount = 0;
      this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
        this.pixAlpha = 1;
      });
    } else if (this.retryCount < 2) {
      this.retryCount++;
      const retryVersion = this.loadVersion;
      const delay = this.retryCount * 700;
      setTimeout((): void => {
        if (retryVersion !== this.loadVersion || this.pix !== undefined) {
          return;
        }
        void this.loadPix();
      }, delay);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.loading || this.pix === undefined) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.colorMode === 1 ? '#14181F' : '#E8EEF6')
      }
      if (this.pix !== undefined) {
        Image(this.pix)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.pixAlpha)
          .draggable(false)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }
}

@Component
export struct GalleryFloatingHeroBackdrop {
  @Prop imageUri: string = '';
  @Prop topSafeInsetVp: number = 0;
  @Prop heightVp: number = GALLERY_FLOATING_HERO_BACKDROP_HEIGHT_VP;

  build() {
    if (this.imageUri.length === 0) {
      Blank()
        .width('100%')
        .height(0)
        .hitTestBehavior(HitTestMode.None)
    } else {
      Stack({ alignContent: Alignment.Bottom }) {
        GalleryNetworkBackdropImage({
          uri: this.imageUri,
          paused: false,
        })
          .width('100%')
          .height('100%')
          .opacity(0.94)

        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#1AFFFFFF')
          .hitTestBehavior(HitTestMode.None)

        Column() {
          Blank()
            .layoutWeight(1)

          Column()
            .width('100%')
            .height(GALLERY_FLOATING_HERO_BACKDROP_FADE_SOFT_VP)
            .backgroundColor($r('app.color.page_background'))
            .opacity(0.36)

          Column()
            .width('100%')
            .height(GALLERY_FLOATING_HERO_BACKDROP_FADE_STRONG_VP)
            .backgroundColor($r('app.color.page_background'))
            .opacity(0.62)

          Column()
            .width('100%')
            .height(GALLERY_FLOATING_HERO_BACKDROP_FADE_SOLID_VP)
            .backgroundColor($r('app.color.page_background'))
            .opacity(0.92)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height(this.heightVp + this.topSafeInsetVp)
      .clip(true)
      .hitTestBehavior(HitTestMode.None)
    }
  }
}

