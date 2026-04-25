/**
 * 图库公共：URL 解析、缩略图/原图加载与 LRU、网格缩略图组件。
 * 供 GalleryAlbumTab 与独立预览页共用，避免重复缓存与解码逻辑。
 */
import { image } from '@kit.ImageKit';
import { AppSession } from '../auth/AppSession';
import { GalleryListItem, GalleryThumbnailBlock } from '../model/FnApiTypes';

/** 预览图缩放：最小值固定为 1.0（不允许缩小到比 fit 更小） */
export const GALLERY_PREVIEW_SCALE_MIN = 1.0;
export const GALLERY_PREVIEW_SCALE_MAX = 4;
export const GALLERY_PREVIEW_ZOOM_EPS = 0.02;
export const GALLERY_PREVIEW_SNAP_EPS = 0.12;

/** 缩略图全局缓存上限；HDR 缩略图单张占用大，过高易 OOM；配合 SDR 解码与 release 淘汰 */
export const THUMB_CACHE_MAX = 96;
const thumbPixCache = new Map<string, PixelMap>();
const thumbLoadFailAt = new Map<string, number>();
const THUMB_FAIL_RETRY_COOLDOWN_MS = 1500;
/** 原图下载智能超时：先短后长，兼顾小图响应与大图成功率 */
const FULL_IMAGE_TIMEOUT_STEPS_MS: number[] = [12000, 25000, 45000];

function fullImageTimeoutSteps(expectedBytes?: number): number[] {
  if (expectedBytes === undefined || expectedBytes <= 0) {
    return FULL_IMAGE_TIMEOUT_STEPS_MS;
  }
  const mb = expectedBytes / (1024 * 1024);
  // 大图（如 40MB+）给更长读超时，避免在弱网下“长时间加载后直接消失”
  if (mb >= 64) {
    return [30000, 90000, 150000];
  }
  if (mb >= 32) {
    return [25000, 75000, 120000];
  }
  if (mb >= 16) {
    return [18000, 50000, 90000];
  }
  return FULL_IMAGE_TIMEOUT_STEPS_MS;
}

/**
 * 缩略图并发加载限流器：最多同时进行 MAX_THUMB_CONCURRENT 个网络请求 + 解码。
 * 超出时排入等待队列，前一个完成后自动释放并启动下一个，避免大量并发导致主线程和网络拥塞。
 * 队列采用“可见优先 + 公平退避”：
 * - 常态优先最近进入视区的任务（近似 LIFO）；
 * - 每隔若干次切换到最早排队任务，避免老任务长期饥饿导致“永远不加载”。
 */
/**
 * 缩略图（含视频封面 JPEG）并发上限：网络 + 解码同时进行的最大任务数。
 * - 视频格与图片格共用同一路径，封面往往更大，并发过低时队列排长、体感「带宽没用满」。
 * - 过高会抬升瞬时内存与解码 CPU，低端机或弱网可改回 4～6。
 */
const MAX_THUMB_CONCURRENT = 8;
let thumbLoadActive = 0;
const thumbLoadWaiters: Array<() => void> = [];
let thumbWakeCount = 0;

function thumbCacheKey(fullUrl: string, autoCropBlack: boolean): string {
  return `${autoCropBlack ? '1' : '0'}|${fullUrl}`;
}

function acquireThumbSlot(): Promise<void> {
  if (thumbLoadActive < MAX_THUMB_CONCURRENT) {
    thumbLoadActive++;
    return Promise.resolve();
  }
  return new Promise<void>((resolve) => {
    thumbLoadWaiters.push(resolve);
  });
}

/** 缓存淘汰或显式丢弃时释放原生像素缓冲，降低长列表滑动后的内存峰值 */
function releaseThumbPix(p: PixelMap): void {
  try {
    p.release();
  } catch (_e) {
  }
}

function releaseThumbSlot(): void {
  if (thumbLoadWaiters.length > 0) {
    thumbWakeCount++;
    const next = (thumbWakeCount % 4 === 0) ? thumbLoadWaiters.shift() : thumbLoadWaiters.pop();
    if (next !== undefined) { next(); }
  } else {
    thumbLoadActive--;
  }
}

/**
 * 同步从缩略图缓存中取 PixelMap（不触发网络请求）。
 * 用于预览页首帧立即显示已缓存图片，消除 sharedTransition 期间的空白闪烁。
 */
export function getThumbPixCached(uri: string): PixelMap | undefined {
  if (uri.length === 0) {
    return undefined;
  }
  const v = thumbPixCache.get(thumbCacheKey(uri, false));
  return v;
}

export function trimThumbPixCache(maxKeep: number): void {
  const keep = Math.max(0, Math.floor(maxKeep));
  while (thumbPixCache.size > keep) {
    let firstKey: string | undefined = undefined;
    for (const k of thumbPixCache.keys()) {
      firstKey = k;
      break;
    }
    if (firstKey === undefined) {
      break;
    }
    const old = thumbPixCache.get(firstKey);
    thumbPixCache.delete(firstKey);
    if (old !== undefined) {
      releaseThumbPix(old);
    }
  }
}

export function itemFileExt(it: GalleryListItem): string {
  const name = it.filename ?? it.fileName ?? it.name ?? it.title ?? '';
  const dot = name.lastIndexOf('.');
  return dot >= 0 ? name.substring(dot + 1).toLowerCase() : (it.fileType ?? '').toLowerCase();
}

export function isVideoItem(it: GalleryListItem): boolean {
  if (it.category === 'video') {
    return true;
  }
  const ext = itemFileExt(it);
  return ext === 'mp4' || ext === 'mov' || ext === 'avi' || ext === 'mkv' || ext === 'webm' || ext === 'm4v';
}

export function isGifItem(it: GalleryListItem): boolean {
  return itemFileExt(it) === 'gif';
}

export function pickThumb(it: GalleryListItem): string {
  const th = it.additional?.thumbnail;
  if (th !== undefined) {
    for (const u of [th.mUrl, th.sUrl, th.xsUrl, th.xxsUrl]) {
      if (u !== undefined && u.trim().length > 0) {
        return u.trim();
      }
    }
  }
  const topTh = it.thumbnail;
  if (topTh !== undefined && typeof topTh === 'object') {
    const tb = topTh as GalleryThumbnailBlock;
    for (const u of [tb.mUrl, tb.sUrl, tb.xsUrl, tb.xxsUrl]) {
      if (u !== undefined && u.trim().length > 0) {
        return u.trim();
      }
    }
  }
  for (const u of [it.thumb, it.small_thumb, it.thumb_url, it.cover, it.poster]) {
    if (u !== undefined && u.trim().length > 0) {
      return u.trim();
    }
  }
  if (typeof topTh === 'string' && topTh.trim().length > 0) {
    return topTh.trim();
  }
  for (const u of [it.url, it.src, it.path]) {
    if (u !== undefined && u.trim().length > 0) {
      return u.trim();
    }
  }
  return '';
}

export function pickOriginal(it: GalleryListItem): string {
  if (it.originalUrl !== undefined && it.originalUrl.trim().length > 0) {
    return it.originalUrl.trim();
  }
  const th = it.additional?.thumbnail;
  if (th?.originalUrl !== undefined && th.originalUrl.trim().length > 0) {
    return th.originalUrl.trim();
  }
  if (typeof it.thumbnail === 'object') {
    const orig = (it.thumbnail as GalleryThumbnailBlock).originalUrl;
    if (orig !== undefined && orig.trim().length > 0) {
      return orig.trim();
    }
  }
  return '';
}

export function pickVideo(it: GalleryListItem): string {
  const th = it.additional?.thumbnail;
  if (th?.videoUrl !== undefined && th.videoUrl.trim().length > 0) {
    return th.videoUrl.trim();
  }
  if (typeof it.thumbnail === 'object') {
    const vUrl = (it.thumbnail as GalleryThumbnailBlock).videoUrl;
    if (vUrl !== undefined && vUrl.trim().length > 0) {
      return vUrl.trim();
    }
  }
  // 兼容部分返回：视频条目未给 videoUrl，仅给 id
  if (it.id !== undefined) {
    const sid = String(it.id).trim();
    if (sid.length > 0) {
      return `/p/api/v1/stream/v/${sid}`;
    }
  }
  for (const u of [it.url, it.src, it.path]) {
    if (u !== undefined && u.trim().length > 0) {
      return u.trim();
    }
  }
  return '';
}

export function nasUrl(base: string, ref: string): string {
  const t = ref.trim();
  if (t.length === 0) {
    return '';
  }
  if (t.startsWith('http://') || t.startsWith('https://') || t.startsWith('data:')) {
    return t;
  }
  let b = base.trim();
  while (b.length > 1 && b.endsWith('/')) {
    b = b.substring(0, b.length - 1);
  }
  return t.startsWith('/') ? `${b}${t}` : `${b}/${t}`;
}

/**
 * 自动检测并裁掉 PixelMap 四周的纯黑边（letterbox/pillarbox）。
 * 仅处理近似正方形图像（服务端预填充为正方形的视频帧缩略图最常见此问题）。
 * 直接修改传入的 PixelMap（in-place crop），无返回值。
 */
async function autoCropBlackBorders(pix: PixelMap): Promise<void> {
  try {
    const info = pix.getImageInfoSync();
    const w = info.size.width;
    const h = info.size.height;
    if (w < 8 || h < 8) { return; }

    // 只处理近似正方形（约 2:3 ~ 3:2），真正的横幅/竖幅图片不会有此问题
    const ratio = w / h;
    if (ratio < 0.67 || ratio > 1.5) { return; }

    // 只处理 4 字节/像素的格式（RGBA_8888=3, BGRA_8888=4）
    const fmt = info.pixelFormat as number;
    if (fmt !== 3 && fmt !== 4) { return; }

    const totalBytes = w * h * 4;
    const buf = new ArrayBuffer(totalBytes);
    await pix.readPixelsToBuffer(buf);
    const v = new Uint8Array(buf);

    // 判断某行中间 80% 像素是否绝大多数为纯黑（前三通道 < 18）
    const isRowBlack = (y: number): boolean => {
      const x0 = Math.floor(w * 0.1);
      const x1 = Math.floor(w * 0.9);
      let dark = 0;
      for (let x = x0; x < x1; x++) {
        const i = (y * w + x) * 4;
        if (v[i] < 18 && v[i + 1] < 18 && v[i + 2] < 18) { dark++; }
      }
      return (x1 - x0) > 0 && dark >= (x1 - x0) * 0.9;
    };

    const isColBlack = (x: number): boolean => {
      const y0 = Math.floor(h * 0.1);
      const y1 = Math.floor(h * 0.9);
      let dark = 0;
      for (let y = y0; y < y1; y++) {
        const i = (y * w + x) * 4;
        if (v[i] < 18 && v[i + 1] < 18 && v[i + 2] < 18) { dark++; }
      }
      return (y1 - y0) > 0 && dark >= (y1 - y0) * 0.9;
    };

    let top = 0;
    while (top < h / 2 && isRowBlack(top)) { top++; }

    let bottom = h;
    while (bottom > h / 2 && isRowBlack(bottom - 1)) { bottom--; }

    let left = 0;
    while (left < w / 2 && isColBlack(left)) { left++; }

    let right = w;
    while (right > w / 2 && isColBlack(right - 1)) { right--; }

    const trimW = right - left;
    const trimH = bottom - top;
    // 只有裁掉 > 3% 才值得处理，避免误裁正常图片
    if (trimW > 0 && trimH > 0 &&
      (top > h * 0.03 || bottom < h * 0.97 || left > w * 0.03 || right < w * 0.97)) {
      await pix.crop({ x: left, y: top, size: { width: trimW, height: trimH } });
    }
  } catch (_e) {}
}

export async function loadThumbPix(fullUrl: string, autoCropBlack: boolean = false): Promise<PixelMap | undefined> {
  if (fullUrl.length === 0) { return undefined; }
  const key = thumbCacheKey(fullUrl, autoCropBlack);
  const cached = thumbPixCache.get(key);
  if (cached !== undefined) { return cached; }
  const failAt = thumbLoadFailAt.get(key);
  if (failAt !== undefined && Date.now() - failAt < THUMB_FAIL_RETRY_COOLDOWN_MS) {
    return undefined;
  }

  // 等待并发槽位，避免大量同时下载解码导致卡顿
  await acquireThumbSlot();
  try {
    // 二次检查：等待期间可能已由其他协程填充缓存
    const cached2 = thumbPixCache.get(key);
    if (cached2 !== undefined) { return cached2; }

    const client = AppSession.getClient();
    if (client === null) { return undefined; }
    const buf = await client.fetchGalleryImageBuffer(fullUrl, 8000);
    if (buf === undefined || buf.byteLength === 0) {
      thumbLoadFailAt.set(key, Date.now());
      return undefined;
    }
    const src = image.createImageSource(buf);
    // 网格缩略图用 SDR 解码，显著低于 HDR/F16 的内存占用，降低大图库滑动崩溃风险；预览大图仍走 loadFullPix(HDR)
    const pix = await src.createPixelMap({ desiredDynamicRange: image.DecodingDynamicRange.SDR });
    src.release();
    // 裁掉服务端已预烘焙的 letterbox/pillarbox 黑边
    if (autoCropBlack) {
      await autoCropBlackBorders(pix);
    }
    if (thumbPixCache.size >= THUMB_CACHE_MAX) {
      let firstKey: string | undefined = undefined;
      for (const k of thumbPixCache.keys()) {
        firstKey = k;
        break;
      }
      if (firstKey !== undefined) {
        const old = thumbPixCache.get(firstKey);
        thumbPixCache.delete(firstKey);
        if (old !== undefined) {
          releaseThumbPix(old);
        }
      }
    }
    thumbPixCache.set(key, pix);
    thumbLoadFailAt.delete(key);
    return pix;
  } catch (_e) {
    thumbLoadFailAt.set(key, Date.now());
    return undefined;
  } finally {
    releaseThumbSlot();
  }
}

export async function loadFullPix(fullUrl: string, expectedBytes?: number): Promise<PixelMap | undefined> {
  if (fullUrl.length === 0) {
    return undefined;
  }
  const client = AppSession.getClient();
  if (client === null) {
    return undefined;
  }
  let buf: ArrayBuffer | undefined = undefined;
  /**
   * 智能下载策略：
   * 1) 首轮用较短超时，保证普通图片快速失败/快速成功；
   * 2) 若失败则逐步放宽超时，提升超大原图（弱网/高时延）成功率；
   * 3) 任一阶段成功即停止，避免无谓等待。
   */
  const timeoutSteps = fullImageTimeoutSteps(expectedBytes);
  for (let i = 0; i < timeoutSteps.length; i++) {
    buf = await client.fetchGalleryImageBuffer(fullUrl, timeoutSteps[i]);
    if (buf !== undefined && buf.byteLength > 0) {
      break;
    }
  }
  if (buf === undefined || buf.byteLength === 0) {
    return undefined;
  }
  try {
    const src = image.createImageSource(buf);
    // 启用 HDR 解码：若源图为 HDR Vivid/HEIF 则保留增益图，输出 RGBA_F16 PixelMap；
    // 普通 SDR 图片不受影响，仍按原始格式解码。
    const pix = await src.createPixelMap({ desiredDynamicRange: image.DecodingDynamicRange.HDR });
    src.release();
    return pix;
  } catch (_e) {
    return undefined;
  }
}

@Component
export struct GalleryThumbSkeleton {
  @StorageProp('colorMode') private colorMode: number = 0;

  build() {
    Column()
      .width('100%')
      .aspectRatio(1)
      .backgroundColor(this.colorMode === 1 ? '#2C2C2E' : '#E8EAED')
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
  @StorageProp('colorMode') private colorMode: number = 0;
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
      .backgroundColor(this.colorMode === 1 ? '#2C2C2E' : '#E8EAED')
      .opacity(this.pulseOpacity)
      .animation({ duration: 360, curve: Curve.EaseInOut })
      .borderRadius(0)
  }
}

@Component
export struct GalleryNetworkThumb {
  @Prop @Watch('onUriChange') uri: string = '';
  @Prop isVideo: boolean = false;
  @Prop isGif: boolean = false;
  /** true 时仅显示骨架占位，不发起真实图加载 */
  @Prop @Watch('onPausedChange') paused: boolean = false;
  @StorageProp('colorMode') private colorMode: number = 0;
  @State private pix: PixelMap | undefined = undefined;
  @State private loading: boolean = false;
  @State private pixAlpha: number = 0;
  /** 递增版本号：避免滚动复用后旧异步任务回写到新卡片 */
  private loadVersion: number = 0;
  /** 失败重试次数：用于弱网/短时请求失败后自动补偿加载 */
  private retryCount: number = 0;

  onUriChange(): void {
    this.loadVersion++;
    this.pix = undefined;
    this.pixAlpha = 0;
    this.loading = false;
    this.retryCount = 0;
    void this.loadPix();
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
    // 组件离屏后提升版本号，阻止旧任务回写
    this.loadVersion++;
  }

  private async loadPix(): Promise<void> {
    if (this.uri.length === 0 || this.loading) {
      return;
    }
    const cacheKey = thumbCacheKey(this.uri, this.isVideo);
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
    const pix = await loadThumbPix(this.uri, this.isVideo);
    if (versionAtStart !== this.loadVersion) {
      this.loading = false;
      return;
    }
    this.loading = false;
    if (pix !== undefined) {
      this.pix = pix;
      this.retryCount = 0;
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
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
        GalleryThumbSkeleton()
      }
      if (this.pix !== undefined) {
        // 官方：Image 默认 draggable=true，长按易拖入系统「中转站」；相册缩略图关闭拖拽
        Image(this.pix)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.pixAlpha)
          .draggable(false)
      }
      if (this.isVideo) {
        // 使用鸿蒙官方 Symbol 图标
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(34).height(34)
            .fill('#66000000')
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(16)
            .fontColor([Color.White])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        }
      }
      if (this.isGif) {
        Text('GIF')
          .fontSize(10)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#66000000')
          .padding({ left: 5, right: 5, top: 2, bottom: 2 })
          .borderRadius(4)
          .position({ x: 5, y: 5 })
      }
    }
    .width('100%')
    .aspectRatio(1)
    .borderRadius(0)
    .backgroundColor(this.colorMode === 1 ? '#1C1C1E' : '#F0F0F0')
    .clip(true)
    // 防止子节点未覆盖区域仍响应系统拖拽
    .draggable(false)
    // Image/骨架会参与命中并吞掉长按与 Pan，父级 Stack 上的多选手势永远收不到；整卡不参与命中，事件落到外层图库格
    .hitTestBehavior(HitTestMode.None)
  }
}
