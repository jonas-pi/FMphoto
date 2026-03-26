/**
 * 原生相册 Tab（对齐 fnos_gallery_mobile.py §2~§4）
 *
 * 数据链路：
 *   timeline → 按日降序 → 每日 getList 顺序分页
 *   偏移量由 dayNextOffsets（非响应式 Map）同步维护，避免 @State 延迟导致重复请求
 *
 * 加载策略：自驱动泵（pumpLoad），每批完成后自动调度下一批（约一帧间隙，避免同帧内连续抢渲染）。
 *   不依赖滚动事件，彻底规避 "Drag gesture has been canceled" 导致的加载停滞。
 *   onDidScroll 仅作备份重启触发（泵因错误暂停时由滚动重启）。
 *
 * 缩略图：鉴权下载 → PixelMap（保持原比例）→ LRU 缓存 → 骨架屏 → 淡入
 * 全屏预览：左右滑动切换、下划关闭、原图按钮、视频播放；图片支持双指缩放与单指拖动查看
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { AppSession } from '../auth/AppSession';
import { SessionPreferences } from '../auth/SessionPreferences';
import {
  GalleryGetListData,
  GalleryListItem,
  GalleryThumbnailBlock,
  GalleryTimelineDayCell
} from '../model/FnApiTypes';

const DOMAIN = 0xFF00;
const TAG = 'GalleryTab';
/** 单日分页条数：适当增大可减少 HTTP 往返（服务端 limit 一般可接受 50～100） */
const DATE_FEED_BATCH = 50;
/** 有新增条数时泵的间隔（ms）；远小于旧版 80ms，多日多批时累计延迟明显降低 */
const PUMP_UI_GAP_MS = 16;
const THUMB_CACHE_MAX = 250;
/** 预览图缩放范围（相对 1） */
const PREVIEW_SCALE_MIN = 0.5;
const PREVIEW_SCALE_MAX = 4;
/** 与 1 的偏差超过此值视为「已缩放」，单指拖动平移；否则横向滑动切图 */
const PREVIEW_ZOOM_EPS = 0.02;
/** 手势结束后缩放落在此区间内则吸附回 1 倍并清零平移 */
const PREVIEW_SNAP_EPS = 0.08;
/** 每天内最大批次循环次数安全上限（兜底，防极端无限循环） */
const DAY_MAX_ROUNDS = 300;
/** 仅在 timeline 未给出 itemCount（0）时：连续空页达到该阈值才切日 */
const EMPTY_PAGE_ADVANCE_THRESHOLD = 2;

// ─── PixelMap 缓存 ─────────────────────────────────────────────────────────
const thumbPixCache = new Map<string, PixelMap | null>();

// ─── 数据模型 ──────────────────────────────────────────────────────────────

interface TimelineDayModel {
  year: number;
  month: number;
  day: number;
  itemCount: number;
}

/**
 * 按日区块：使用 @Observed 以便同日多批追加 items 时子树增量刷新，
 * 避免仅靠 ForEach key 含 items.length 导致整段 Column 反复重挂载（解码/布局成本高、体感慢）。
 */
@Observed
class DaySectionModel {
  year: number = 0;
  month: number = 0;
  day: number = 0;
  itemCount: number = 0;
  items: GalleryListItem[] = [];
  nextOffset: number = 0;
}

// ─── 工具函数 ──────────────────────────────────────────────────────────────

function fmtDayStart(y: number, m: number, d: number): string {
  return `${y}:${m.toString().padStart(2, '0')}:${d.toString().padStart(2, '0')} 00:00:00`;
}

function fmtDayEnd(y: number, m: number, d: number): string {
  return `${y}:${m.toString().padStart(2, '0')}:${d.toString().padStart(2, '0')} 23:59:59`;
}

function ymKey(y: number, m: number): string {
  return `${y}-${m}`;
}

function dayKey(y: number, m: number, d: number): string {
  return `${y}-${m}-${d}`;
}

function parseTimelineDayCells(raw: GalleryTimelineDayCell[]): TimelineDayModel[] {
  const out: TimelineDayModel[] = [];
  for (let i = 0; i < raw.length; i++) {
    const x = raw[i];
    if (x.year === undefined || x.month === undefined || x.day === undefined) {
      continue;
    }
    const yi = Number(x.year);
    const mi = Number(x.month);
    const di = Number(x.day);
    if (!Number.isFinite(yi) || !Number.isFinite(mi) || !Number.isFinite(di)) {
      continue;
    }
    const ic = x.itemCount !== undefined ? x.itemCount : x.item_count;
    const cnt = ic !== undefined && Number.isFinite(Number(ic)) ? Math.max(0, Math.floor(Number(ic))) : 0;
    out.push({ year: Math.floor(yi), month: Math.floor(mi), day: Math.floor(di), itemCount: cnt });
  }
  return out;
}

function sortDaysDesc(cells: TimelineDayModel[]): TimelineDayModel[] {
  return cells.slice().sort((a: TimelineDayModel, b: TimelineDayModel): number => {
    if (a.year !== b.year) {
      return b.year - a.year;
    }
    if (a.month !== b.month) {
      return b.month - a.month;
    }
    return b.day - a.day;
  });
}

function itemFileExt(it: GalleryListItem): string {
  const name = it.filename ?? it.name ?? it.title ?? '';
  const dot = name.lastIndexOf('.');
  return dot >= 0 ? name.substring(dot + 1).toLowerCase() : (it.fileType ?? '').toLowerCase();
}

function isVideoItem(it: GalleryListItem): boolean {
  if (it.category === 'video') {
    return true;
  }
  const ext = itemFileExt(it);
  return ext === 'mp4' || ext === 'mov' || ext === 'avi' || ext === 'mkv' || ext === 'webm' || ext === 'm4v';
}

function isGifItem(it: GalleryListItem): boolean {
  return itemFileExt(it) === 'gif';
}

function pickThumb(it: GalleryListItem): string {
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

function pickOriginal(it: GalleryListItem): string {
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

function pickVideo(it: GalleryListItem): string {
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
  for (const u of [it.url, it.src, it.path]) {
    if (u !== undefined && u.trim().length > 0) {
      return u.trim();
    }
  }
  return '';
}

function nasUrl(base: string, ref: string): string {
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

function listFromData(data: GalleryGetListData | undefined): GalleryListItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  // 对齐 Python: isinstance(raw_list, list) 检查，非数组类型一律返回空（服务端偶发 null / 数字等异常值）
  const raw = data.list ?? data.items ?? data.photos ?? data.records;
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw as GalleryListItem[];
}

function rowIndexes(n: number): number[] {
  const c = n <= 0 ? 0 : Math.floor((n + 2) / 3);
  const a: number[] = [];
  for (let i = 0; i < c; i++) {
    a.push(i);
  }
  return a;
}

// ─── 图片加载 ──────────────────────────────────────────────────────────────

async function loadThumbPix(fullUrl: string): Promise<PixelMap | undefined> {
  if (fullUrl.length === 0) {
    return undefined;
  }
  const cached = thumbPixCache.get(fullUrl);
  if (cached !== undefined) {
    return cached ?? undefined;
  }
  const client = AppSession.getClient();
  if (client === null) {
    return undefined;
  }
  const buf = await client.fetchGalleryImageBuffer(fullUrl, 8000);
  if (buf === undefined || buf.byteLength === 0) {
    thumbPixCache.set(fullUrl, null);
    return undefined;
  }
  try {
    const src = image.createImageSource(buf);
    // NAS 缩略图（sUrl/xsUrl）本身已是小尺寸，直接解码保持原始宽高比
    // 不指定 desiredSize，避免强制拉伸变形；渲染由 ImageFit.Cover 裁切填满
    const pix = await src.createPixelMap();
    src.release();
    if (thumbPixCache.size >= THUMB_CACHE_MAX) {
      const keys = Array.from(thumbPixCache.keys());
      if (keys.length > 0) {
        thumbPixCache.delete(keys[0]);
      }
    }
    thumbPixCache.set(fullUrl, pix);
    return pix;
  } catch (_e) {
    thumbPixCache.set(fullUrl, null);
    return undefined;
  }
}

async function loadFullPix(fullUrl: string): Promise<PixelMap | undefined> {
  if (fullUrl.length === 0) {
    return undefined;
  }
  const client = AppSession.getClient();
  if (client === null) {
    return undefined;
  }
  const buf = await client.fetchGalleryImageBuffer(fullUrl, 20000);
  if (buf === undefined || buf.byteLength === 0) {
    return undefined;
  }
  try {
    const src = image.createImageSource(buf);
    const pix = await src.createPixelMap();
    src.release();
    return pix;
  } catch (_e) {
    return undefined;
  }
}

// ─── 骨架屏 ────────────────────────────────────────────────────────────────

@Component
struct ThumbSkeleton {
  @State private alpha: number = 0.45;

  aboutToAppear(): void {
    animateTo(
      { duration: 900, iterations: -1, playMode: PlayMode.Alternate, curve: Curve.EaseInOut },
      (): void => {
        this.alpha = 1.0;
      }
    );
  }

  build() {
    Column()
      .width('100%')
      .aspectRatio(1)
      .backgroundColor('#E0E0E0')
      .borderRadius(6)
      .opacity(this.alpha)
  }
}

// ─── 缩略图组件 ────────────────────────────────────────────────────────────

@Component
struct GalleryNetworkThumb {
  @Prop @Watch('onUriChange') uri: string = '';
  @Prop isVideo: boolean = false;
  @Prop isGif: boolean = false;
  @State private pix: PixelMap | undefined = undefined;
  @State private loading: boolean = false;
  @State private pixAlpha: number = 0;

  onUriChange(): void {
    this.pix = undefined;
    this.pixAlpha = 0;
    this.loading = false;
    void this.loadPix();
  }

  aboutToAppear(): void {
    void this.loadPix();
  }

  private async loadPix(): Promise<void> {
    if (this.uri.length === 0 || this.loading) {
      return;
    }
    const cached = thumbPixCache.get(this.uri);
    if (cached !== undefined) {
      this.pix = cached ?? undefined;
      this.pixAlpha = 1;
      return;
    }
    this.loading = true;
    const pix = await loadThumbPix(this.uri);
    this.loading = false;
    if (pix !== undefined) {
      this.pix = pix;
      animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
        this.pixAlpha = 1;
      });
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.loading || this.pix === undefined) {
        ThumbSkeleton()
      }
      if (this.pix !== undefined) {
        Image(this.pix)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .opacity(this.pixAlpha)
      }
      if (this.isVideo) {
        Column() {
          Text('▶').fontSize(20).fontColor(Color.White)
        }
        .width(36).height(36).borderRadius(18)
        .backgroundColor('#80000000')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      if (this.isGif) {
        Text('GIF').fontSize(10).fontColor(Color.White)
          .backgroundColor('#80000000')
          .padding({ left: 4, right: 4, top: 2, bottom: 2 })
          .borderRadius(3)
          .position({ x: 4, y: 4 })
      }
    }
    .width('100%')
    .aspectRatio(1)
  }
}

// ─── 全屏预览（支持左右滑动切换） ──────────────────────────────────────────

@Component
struct GalleryPreviewOverlay {
  @Prop baseUrl: string = '';
  @Prop @Watch('onItemChange') item: GalleryListItem | undefined = undefined;
  onSwitch: (delta: number) => void = (_: number) => {};
  onClose: () => void = () => {};

  @State private thumbPix: PixelMap | undefined = undefined;
  @State private fullPix: PixelMap | undefined = undefined;
  @State private showingOriginal: boolean = false;
  @State private fullLoading: boolean = false;
  @State private videoSrc: string = '';
  @State private contentOffsetX: number = 0;
  /** 图片预览：捏合缩放（1 为原始） */
  @State private previewScale: number = 1;
  /** 缩放后的平移（屏幕坐标） */
  @State private previewPanX: number = 0;
  @State private previewPanY: number = 0;
  /** 捏合开始时已有缩放倍数（event.scale 相对捏合起点） */
  private pinchBaseScale: number = 1;
  /** 单指拖动开始时已有平移 */
  private panBaseX: number = 0;
  private panBaseY: number = 0;

  private isVideo(): boolean {
    return this.item !== undefined && isVideoItem(this.item);
  }

  private thumbUrl(): string {
    return this.item !== undefined ? nasUrl(this.baseUrl, pickThumb(this.item)) : '';
  }

  private originalUrl(): string {
    return this.item !== undefined ? nasUrl(this.baseUrl, pickOriginal(this.item)) : '';
  }

  /** @Prop item 变化时重置所有内部状态并重新加载（左右滑动切换时触发） */
  onItemChange(): void {
    this.thumbPix = undefined;
    this.fullPix = undefined;
    this.showingOriginal = false;
    this.fullLoading = false;
    this.videoSrc = '';
    this.contentOffsetX = 0;
    this.previewScale = 1;
    this.previewPanX = 0;
    this.previewPanY = 0;
    this.prepareContent();
  }

  aboutToAppear(): void {
    this.prepareContent();
  }

  private prepareContent(): void {
    if (this.item === undefined) {
      return;
    }
    if (this.isVideo()) {
      this.videoSrc = nasUrl(this.baseUrl, pickVideo(this.item as GalleryListItem));
      return;
    }
    const tUrl = this.thumbUrl();
    const cached = tUrl.length > 0 ? thumbPixCache.get(tUrl) : undefined;
    if (cached !== undefined && cached !== null) {
      this.thumbPix = cached;
    } else if (tUrl.length > 0) {
      void loadThumbPix(tUrl).then((p: PixelMap | undefined) => {
        this.thumbPix = p;
      });
    }
  }

  private loadOriginal(): void {
    const oUrl = this.originalUrl();
    if (oUrl.length === 0 || this.fullLoading || this.fullPix !== undefined) {
      if (this.fullPix !== undefined) {
        this.showingOriginal = true;
      }
      return;
    }
    this.fullLoading = true;
    void loadFullPix(oUrl).then((p: PixelMap | undefined) => {
      this.fullLoading = false;
      this.fullPix = p;
      this.showingOriginal = p !== undefined;
    });
  }

  private hasOriginal(): boolean {
    return this.item !== undefined && this.originalUrl().length > 0 && !this.isVideo();
  }

  /** 当前为图片且相对 1 倍有缩放（可单指拖动，含缩小后查看） */
  private isImageZoomed(): boolean {
    return !this.isVideo() && Math.abs(this.previewScale - 1) > PREVIEW_ZOOM_EPS;
  }

  /** 限制平移，避免拖得过远 */
  private clampPreviewPan(): void {
    if (this.isVideo() || Math.abs(this.previewScale - 1) <= PREVIEW_ZOOM_EPS) {
      return;
    }
    const lim = 320 * Math.abs(this.previewScale - 1) + 80;
    this.previewPanX = Math.min(lim, Math.max(-lim, this.previewPanX));
    this.previewPanY = Math.min(lim, Math.max(-lim, this.previewPanY));
  }

  /** 手势结束：接近 1 倍时吸附回初始状态 */
  private snapPreviewIfNeeded(): void {
    if (this.isVideo()) {
      return;
    }
    if (Math.abs(this.previewScale - 1) <= PREVIEW_SNAP_EPS) {
      animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
        this.previewScale = 1;
        this.previewPanX = 0;
        this.previewPanY = 0;
      });
    } else {
      this.clampPreviewPan();
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)

      // 内容区（跟随横向拖拽偏移）
      Column() {
        if (this.isVideo() && this.videoSrc.length > 0) {
          Video({ src: this.videoSrc })
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .autoPlay(true)
            .controls(true)
        } else if (this.showingOriginal && this.fullPix !== undefined) {
          Image(this.fullPix)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        } else if (this.thumbPix !== undefined) {
          Image(this.thumbPix)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        } else {
          LoadingProgress().width(48).height(48).color(Color.White)
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .scale({
        x: this.isVideo() ? 1 : this.previewScale,
        y: this.isVideo() ? 1 : this.previewScale,
        centerX: '50%',
        centerY: '50%'
      })
      .translate({
        x: this.isVideo()
          ? this.contentOffsetX
          : (this.isImageZoomed() ? this.previewPanX : this.contentOffsetX),
        y: this.isVideo() ? 0 : (this.isImageZoomed() ? this.previewPanY : 0)
      })

      // 关闭按钮
      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          Text('✕').fontSize(16).fontColor(Color.White)
        }
        .width(40).height(40)
        .backgroundColor('#60000000')
        .onClick((): void => { this.onClose(); })
        Blank()
      }
      .width('100%')
      .padding({ left: 12, top: 12, right: 12 })

      // 查看原图
      if (!this.isVideo()) {
        Column() {
          if (this.hasOriginal()) {
            if (this.fullLoading) {
              Row({ space: 8 }) {
                LoadingProgress().width(20).height(20).color(Color.White)
                Text('加载原图中…').fontSize(14).fontColor(Color.White)
              }.padding({ bottom: 24 })
            } else if (this.showingOriginal) {
              Text('已显示原图').fontSize(13).fontColor('#AAAAAA').padding({ bottom: 24 })
            } else {
              Button('查看原图', { type: ButtonType.Capsule, stateEffect: true })
                .fontSize(14).fontColor(Color.White).backgroundColor('#60000000')
                .margin({ bottom: 24 })
                .onClick((): void => { this.loadOriginal(); })
            }
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .position({ x: 0, y: '100%' })
        .translate({ y: '-100%' })
      }
    }
    .width('100%')
    .height('100%')
    .gesture(
      GestureGroup(GestureMode.Parallel,
        PinchGesture({ fingers: 2 })
          .onActionStart((): void => {
            if (this.isVideo()) {
              return;
            }
            this.pinchBaseScale = this.previewScale;
          })
          .onActionUpdate((event: GestureEvent): void => {
            if (this.isVideo()) {
              return;
            }
            let s = this.pinchBaseScale * event.scale;
            if (s < PREVIEW_SCALE_MIN) {
              s = PREVIEW_SCALE_MIN;
            }
            if (s > PREVIEW_SCALE_MAX) {
              s = PREVIEW_SCALE_MAX;
            }
            this.previewScale = s;
            this.clampPreviewPan();
          })
          .onActionEnd((): void => {
            if (this.isVideo()) {
              return;
            }
            this.snapPreviewIfNeeded();
          })
          .onActionCancel((): void => {
            if (this.isVideo()) {
              return;
            }
            this.snapPreviewIfNeeded();
          }),
        PanGesture({ direction: PanDirection.All })
          .onActionStart((): void => {
            this.panBaseX = this.previewPanX;
            this.panBaseY = this.previewPanY;
          })
          .onActionUpdate((event: GestureEvent): void => {
            if (this.isImageZoomed()) {
              this.previewPanX = this.panBaseX + event.offsetX;
              this.previewPanY = this.panBaseY + event.offsetY;
              this.clampPreviewPan();
              return;
            }
            if (this.isVideo()) {
              if (Math.abs(event.offsetX) > Math.abs(event.offsetY)) {
                this.contentOffsetX = event.offsetX;
              }
              return;
            }
            // 未缩放图片：横向跟手；纵向以下滑关闭为主，不在此跟手避免与缩放后拖动混淆
            if (Math.abs(event.offsetX) >= Math.abs(event.offsetY)) {
              this.contentOffsetX = event.offsetX;
            }
          })
          .onActionEnd((event: GestureEvent): void => {
            if (this.isImageZoomed()) {
              this.clampPreviewPan();
              return;
            }
            const absX = Math.abs(event.offsetX);
            const absY = Math.abs(event.offsetY);
            if (absX > absY && absX >= 80) {
              animateTo({ duration: 150, curve: Curve.EaseOut }, (): void => {
                this.contentOffsetX = event.offsetX > 0 ? 400 : -400;
              });
              const delta = event.offsetX < 0 ? 1 : -1;
              setTimeout((): void => {
                this.contentOffsetX = 0;
                this.onSwitch(delta);
              }, 160);
            } else if (absY > absX && event.offsetY >= 100) {
              this.onClose();
            } else {
              animateTo({ duration: 150, curve: Curve.EaseOut }, (): void => {
                this.contentOffsetX = 0;
              });
            }
          })
      )
    )
  }
}

/**
 * 单日时间轴区块：通过 @ObjectLink 订阅 @Observed 的 DaySectionModel，
 * 同日多批追加 items 时仅刷新本块，无需把 items.length 塞进 ForEach key 导致整段重挂载。
 */
@Component
struct GalleryDaySection {
  @ObjectLink sec: DaySectionModel;
  @Prop baseUrl: string = '';
  @Prop showMonthTitle: boolean = false;
  onThumbClick: (sec: DaySectionModel, rowIdx: number, col: number) => void = () => {};

  private itemAt(rowIdx: number, col: number): GalleryListItem | undefined {
    const idx = rowIdx * 3 + col;
    return idx >= 0 && idx < this.sec.items.length ? this.sec.items[idx] : undefined;
  }

  @Builder
  private thumbCell(rowIdx: number, col: number) {
    if (this.itemAt(rowIdx, col) === undefined) {
      Blank()
    } else {
      GalleryNetworkThumb({
        uri: nasUrl(this.baseUrl, pickThumb(this.itemAt(rowIdx, col) as GalleryListItem)),
        isVideo: isVideoItem(this.itemAt(rowIdx, col) as GalleryListItem),
        isGif: isGifItem(this.itemAt(rowIdx, col) as GalleryListItem)
      })
        .onClick((): void => {
          this.onThumbClick(this.sec, rowIdx, col);
        })
    }
  }

  build() {
    Column({ space: 6 }) {
      if (this.showMonthTitle) {
        Text(`${this.sec.year}年${this.sec.month}月`)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .padding({ left: 8, top: 10, bottom: 4 })
      }
      Text(`${this.sec.month}月${this.sec.day}日`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 8, bottom: 2 })

      Column({ space: 6 }) {
        ForEach(rowIndexes(this.sec.items.length), (rowIdx: number) => {
          Row({ space: 6 }) {
            ForEach([0, 1, 2], (col: number) => {
              Column() {
                this.thumbCell(rowIdx, col);
              }
              .layoutWeight(1)
            }, (col: number) => `c_${this.sec.year}_${this.sec.month}_${this.sec.day}_${rowIdx}_${col}`)
          }
          .width('100%')
        }, (rowIdx: number) => `r_${this.sec.year}_${this.sec.month}_${this.sec.day}_${rowIdx}`)
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 10 })
    }
    .width('100%')
  }
}

// ─── 主 Tab 组件 ───────────────────────────────────────────────────────────

@Component
export struct GalleryAlbumTab {
  @Prop baseUrl: string = '';
  @Prop @Watch('onEpochChange') albumReloadEpoch: number = 0;
  @Consume galleryHasPreview: boolean;
  @Consume @Watch('handleCloseReq') closeGalleryPreview: number;

  @State private bootLoading: boolean = false;
  @State private loadError: string = '';
  @State private footText: string = '';
  @State private sections: DaySectionModel[] = [];
  /** 当前全屏预览的扁平索引（-1 = 无预览） */
  @State private previewFlatIndex: number = -1;
  @State private previewOpacity: number = 0;
  @State private previewScale: number = 0.96;

  private loadGen: number = 0;
  private orderedDays: TimelineDayModel[] = [];
  private dayIndex: number = 0;
  private loadingMore: boolean = false;
  private exhausted: boolean = false;
  private dayOffsets: Map<string, number> = new Map<string, number>();
  /** 每天已请求的批次数（安全上限，防止 itemCount 不准时无限循环） */
  private dayRounds: Map<string, number> = new Map<string, number>();
  /** 每天连续空页计数（防止单次空页误切日） */
  private dayEmptyRounds: Map<string, number> = new Map<string, number>();
  private scrollerRef: Scroller = new Scroller();

  // ── 扁平索引辅助（用于左右滑动切换预览） ───────────────────────────────

  private flatItems(): GalleryListItem[] {
    const out: GalleryListItem[] = [];
    for (let i = 0; i < this.sections.length; i++) {
      const items = this.sections[i].items;
      for (let j = 0; j < items.length; j++) {
        out.push(items[j]);
      }
    }
    return out;
  }

  private flatItem(index: number): GalleryListItem | undefined {
    let cur = 0;
    for (let i = 0; i < this.sections.length; i++) {
      const items = this.sections[i].items;
      if (index < cur + items.length) {
        return items[index - cur];
      }
      cur += items.length;
    }
    return undefined;
  }

  private flatTotal(): number {
    let n = 0;
    for (let i = 0; i < this.sections.length; i++) {
      n += this.sections[i].items.length;
    }
    return n;
  }

  private flatIndexOf(sec: DaySectionModel, rowIdx: number, col: number): number {
    const localIdx = rowIdx * 3 + col;
    let base = 0;
    for (let i = 0; i < this.sections.length; i++) {
      const s = this.sections[i];
      if (s.year === sec.year && s.month === sec.month && s.day === sec.day) {
        return base + localIdx;
      }
      base += s.items.length;
    }
    return -1;
  }

  // ── back 协调 ──────────────────────────────────────────────────────────

  handleCloseReq(): void {
    if (this.previewFlatIndex >= 0) {
      this.closePreview();
    }
  }

  // ── 生命周期 ─────────────────────────────────────────────────────────────

  private onEpochChange(): void {
    setTimeout((): void => { void this.bootstrap(); }, 0);
  }

  aboutToAppear(): void {
    setTimeout((): void => { void this.bootstrap(); }, 0);
  }

  // ── sections 更新 ────────────────────────────────────────────────────────

  private upsertSection(day: TimelineDayModel, newItems: GalleryListItem[], newOffset: number): void {
    const idx = this.sections.findIndex(
      (s: DaySectionModel): boolean =>
        s.year === day.year && s.month === day.month && s.day === day.day
    );
    if (idx < 0) {
      const sec = new DaySectionModel();
      sec.year = day.year;
      sec.month = day.month;
      sec.day = day.day;
      sec.itemCount = day.itemCount;
      sec.items = newItems.slice();
      sec.nextOffset = newOffset;
      this.sections = this.sections.concat([sec]);
    } else {
      const sec = this.sections[idx];
      for (let i = 0; i < newItems.length; i++) {
        sec.items.push(newItems[i]);
      }
      sec.nextOffset = newOffset;
    }
  }

  // ── 数据加载 ─────────────────────────────────────────────────────────────

  private async bootstrap(): Promise<void> {
    const gen = ++this.loadGen;
    this.exhausted = false;
    this.dayIndex = 0;
    this.orderedDays = [];
    this.dayOffsets.clear();
    this.dayRounds.clear();
    this.dayEmptyRounds.clear();
    this.bootLoading = true;
    this.loadError = '';
    this.sections = [];
    this.footText = '';
    this.previewFlatIndex = -1;
    this.galleryHasPreview = false;

    const client = AppSession.getClient();
    if (client === null) {
      if (gen !== this.loadGen) { return; }
      this.bootLoading = false;
      this.loadError = '未登录';
      return;
    }

    let workClient = client;
    if (workClient.getLongToken().length === 0) {
      const tok = await workClient.fetchFnosLongTokenProbe(12000);
      if (tok.length > 0) {
        const cur = AppSession.getStored();
        if (cur !== null) {
          cur.fnosLongToken = tok;
          AppSession.apply(cur);
          try {
            const ctx = getContext(this) as common.UIAbilityContext;
            void SessionPreferences.save(ctx, cur);
          } catch (_e) { /* ignore */ }
          const refreshed = AppSession.getClient();
          if (refreshed !== null) { workClient = refreshed; }
        }
      }
    }

    const tl = await workClient.getGalleryTimeline();
    if (gen !== this.loadGen) { return; }
    if (tl.success !== true || tl.data === undefined) {
      const em = tl.message !== undefined && tl.message.length > 0 ? tl.message : '时间轴加载失败';
      const prev = tl.errorBodyPreview ?? '';
      hilog.warn(DOMAIN, TAG, 'timeline fail: %{public}s body: %{public}s', em, prev || '(none)');
      this.bootLoading = false;
      this.loadError = prev.length > 0 ? `${em}\n${prev}` : em;
      return;
    }

    const rawList = tl.data.list ?? [];
    const cellsIn: GalleryTimelineDayCell[] = [];
    for (let i = 0; i < rawList.length; i++) {
      const el = rawList[i];
      if (typeof el === 'object' && el !== null) {
        cellsIn.push(el as GalleryTimelineDayCell);
      }
    }
    const cells = sortDaysDesc(parseTimelineDayCells(cellsIn)).filter(
      (c: TimelineDayModel): boolean => c.itemCount > 0
    );
    if (cells.length === 0) {
      this.bootLoading = false;
      this.footText = '时间轴暂无数据';
      return;
    }

    this.orderedDays = cells;
    this.bootLoading = false;
    // 启动自驱动加载泵
    this.pumpLoad();
  }

  /**
   * 自驱动批量加载泵（self-pumping）。
   *
   * 原理：每批完成后自动在短暂暂停后继续下一批，完全不依赖滚动事件。
   * 这是解决 "Drag gesture has been canceled" 导致 onDidScroll 不触发的根本方案。
   * loadingMore 守卫防止并发调用；loadGen 保证刷新后旧泵自动停止。
   */
  private pumpLoad(): void {
    if (this.loadingMore || this.exhausted) {
      return;
    }
    this.loadingMore = true;
    const gen = this.loadGen;
    void this.loadOneBatch().then((added: number): void => {
      this.loadingMore = false;
      if (gen !== this.loadGen || this.exhausted) {
        return;
      }
      if (added === -1) {
        // 耗尽或已被新的 loadGen 取消，停止泵
        return;
      }
      if (added === -2) {
        // 网络错误，3 秒后重试（避免频繁失败）
        setTimeout((): void => {
          this.pumpLoad();
        }, 3000);
        return;
      }
      if (added === -3) {
        // 时间轴显示仍有剩余但本批空：同一 offset 稍后重试（避免误切日 + 减轻压力）
        setTimeout((): void => {
          this.pumpLoad();
        }, 500);
        return;
      }
      // added >= 0：有数据时等一帧供 UI；切日时立即继续
      setTimeout((): void => {
        this.pumpLoad();
      }, added > 0 ? PUMP_UI_GAP_MS : 0);
    });
  }

  /**
   * 加载单批数据。返回：
   *   >0  = 本批新增条数
   *    0  = 本批无新增（已切日或当日结束）
   *   -1  = 耗尽/已刷新（应停止）
   *   -2  = 网络错误（泵应延迟重试）
   *   -3  = 暂态空页：timeline 仍显示有剩余条数但本批为空，需延迟后同 offset 重试（永不因此强制切日）
   *
   * 切日策略（对齐 fnos_gallery_mobile.py `_load_batch`）：
   *   1) `len==0` 或 `newOff>=itemCount` 或 **`len<limit`（短页）** → 进入下一日
   *   2) 当 `itemCount>0` 且 `newOff<itemCount` 时空页为暂态，只重试不切日（禁止「空页 N 次放弃当日」丢图）
   */
  private async loadOneBatch(): Promise<number> {
    if (this.exhausted) {
      return -1;
    }
    if (this.dayIndex >= this.orderedDays.length) {
      this.exhausted = true;
      this.footText = '已加载全部照片';
      return -1;
    }

    const gen = this.loadGen;
    const day = this.orderedDays[this.dayIndex];
    const key = dayKey(day.year, day.month, day.day);
    const off = this.dayOffsets.get(key) ?? 0;
    const rounds = this.dayRounds.get(key) ?? 0;
    const emptyRounds = this.dayEmptyRounds.get(key) ?? 0;
    const itemCountBasedMax = day.itemCount > 0
      ? Math.ceil(day.itemCount / DATE_FEED_BATCH) + 20
      : DAY_MAX_ROUNDS;
    const dayMaxRounds = Math.max(DAY_MAX_ROUNDS, itemCountBasedMax);

    // 动态安全上限：单日请求超过上限仍未结束，强制切日（避免极端无限循环）
    if (rounds >= dayMaxRounds) {
      hilog.warn(DOMAIN, TAG, 'day %{public}s exceeded max rounds %{public}d, force advance', key, dayMaxRounds);
      this.dayIndex++;
      return 0;
    }

    const client = AppSession.getClient();
    if (client === null) {
      this.footText = '未登录';
      this.exhausted = true;
      return -1;
    }

    try {
      const st = fmtDayStart(day.year, day.month, day.day);
      const et = fmtDayEnd(day.year, day.month, day.day);
      const res = await client.getGalleryList(st, et, DATE_FEED_BATCH, off, 'index');
      if (gen !== this.loadGen) {
        return -1;
      }

      if (res.success !== true) {
        const em = res.message !== undefined && res.message.length > 0 ? res.message : '加载失败';
        hilog.warn(DOMAIN, TAG, 'getList fail %{public}s off=%{public}d: %{public}s', key, off, em);
        this.footText = em;
        return -2; // 网络错误，通知泵延迟重试
      }

      // res.data 可能运行时为 null（服务端异常），与 Python isinstance 检查对齐：视同空列表 → 切日
      const list = listFromData(res.data as GalleryGetListData | undefined);
      const total = res.data?.total;
      const newOff = off + list.length;
      this.dayOffsets.set(key, newOff);

      if (list.length > 0) {
        this.upsertSection(day, list, newOff);
        this.dayEmptyRounds.set(key, 0);
      } else {
        this.dayEmptyRounds.set(key, emptyRounds + 1);
      }

      // 与 Python 一致：本批条数 < limit 即视为当日已结束（最后一页），无需再请求下一 offset
      if (list.length > 0 && list.length < DATE_FEED_BATCH) {
        this.dayRounds.set(key, rounds + 1);
        hilog.warn(DOMAIN, TAG,
          'short page end day %{public}s off=%{public}d got=%{public}d newOff=%{public}d itemCount=%{public}d',
          key, off, list.length, newOff, day.itemCount);
        this.dayIndex++;
        return list.length;
      }

      const emptyNow = list.length === 0 ? (emptyRounds + 1) : 0;
      const timelineSaysMore = day.itemCount > 0 && newOff < day.itemCount;
      const transientEmpty = list.length === 0 && timelineSaysMore;

      hilog.warn(DOMAIN, TAG,
        'batch %{public}s off=%{public}d got=%{public}d newOff=%{public}d itemCount=%{public}d total=%{public}s emptyRounds=%{public}d transient=%{public}d',
        key, off, list.length, newOff, day.itemCount,
        total !== undefined ? String(total) : 'n/a',
        list.length === 0 ? (emptyRounds + 1) : 0,
        transientEmpty ? 1 : 0);

      if (!transientEmpty) {
        this.dayRounds.set(key, rounds + 1);
      }

      if (transientEmpty) {
        return -3;
      }

      const reachTimelineEnd = day.itemCount > 0 && newOff >= day.itemCount;
      const shouldAdvanceDay = list.length === 0 && (
        reachTimelineEnd ||
        (day.itemCount <= 0 && emptyNow >= EMPTY_PAGE_ADVANCE_THRESHOLD)
      );
      if (shouldAdvanceDay) {
        this.dayIndex++;
      }

      return list.length;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadOneBatch error: %{public}s', String(e));
      this.footText = String(e) || '请求异常';
      return -2;
    }
  }

  // ── 预览 ──────────────────────────────────────────────────────────────────

  private openPreview(sec: DaySectionModel, rowIdx: number, col: number): void {
    const fi = this.flatIndexOf(sec, rowIdx, col);
    if (fi < 0) {
      return;
    }
    this.previewFlatIndex = fi;
    this.galleryHasPreview = true;
    this.previewOpacity = 0;
    this.previewScale = 0.96;
    setTimeout((): void => {
      animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
        this.previewOpacity = 1;
        this.previewScale = 1;
      });
    }, 0);
  }

  private closePreview(): void {
    animateTo({ duration: 180, curve: Curve.EaseIn }, (): void => {
      this.previewOpacity = 0;
      this.previewScale = 0.96;
    });
    setTimeout((): void => {
      this.previewFlatIndex = -1;
      this.galleryHasPreview = false;
    }, 190);
  }

  private switchPreview(delta: number): void {
    const total = this.flatTotal();
    const next = this.previewFlatIndex + delta;
    if (next < 0 || next >= total) {
      return;
    }
    this.previewFlatIndex = next;
  }

  // ── build ──────────────────────────────────────────────────────────────────

  build() {
    Stack() {
      Column() {
        Row() {
          Text('图库')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Button($r('app.string.gallery_refresh'), { type: ButtonType.Capsule, stateEffect: true })
            .fontSize(14)
            .height(32)
            .onClick((): void => {
              void this.bootstrap();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 12, right: 12, top: 10, bottom: 6 })

        if (this.bootLoading) {
          Column({ space: 6 }) {
            ForEach([0, 1, 2, 3], (row: number) => {
              Row({ space: 6 }) {
                ForEach([0, 1, 2], (_: number) => {
                  ThumbSkeleton().layoutWeight(1)
                }, (n: number) => `sk_${row}_${n}`)
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: row === 0 ? 40 : 0 })
            }, (r: number) => `skr_${r}`)
          }
          .width('100%')
        }

        if (!this.bootLoading && this.loadError.length > 0) {
          Text(this.loadError)
            .fontSize(14)
            .fontColor(Color.Red)
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })
        }

        if (!this.bootLoading) {
          Scroll(this.scrollerRef) {
            Column({ space: 0 }) {
              ForEach(this.sections, (sec: DaySectionModel, secIdx: number) => {
                GalleryDaySection({
                  sec: sec,
                  baseUrl: this.baseUrl,
                  showMonthTitle: secIdx === 0 ||
                    ymKey(sec.year, sec.month) !==
                      ymKey(this.sections[secIdx - 1].year, this.sections[secIdx - 1].month),
                  onThumbClick: (s: DaySectionModel, rowIdx: number, col: number): void => {
                    this.openPreview(s, rowIdx, col);
                  }
                })
              },
              (sec: DaySectionModel) => `sec_${sec.year}_${sec.month}_${sec.day}`)

              if (this.footText.length > 0) {
                Text(this.footText)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding(16)
              }

              if (!this.exhausted && this.sections.length > 0) {
                Row() {
                  LoadingProgress().width(24).height(24)
                  Text('加载中…').fontSize(12).fontColor($r('app.color.text_secondary')).margin({ left: 8 })
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding(12)
              }

              Blank().height(24)
            }
            .width('100%')
            .padding({ bottom: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
          .onDidScroll((_xOffset: number, _yOffset: number, _scrollState: ScrollState): void => {
            // 作为备份触发器：若泵因错误暂停，用户滚动时重新启动
            if (!this.exhausted && !this.loadingMore && !this.bootLoading) {
              this.pumpLoad();
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      // 全屏预览
      if (this.previewFlatIndex >= 0) {
        GalleryPreviewOverlay({
          baseUrl: this.baseUrl,
          item: this.flatItem(this.previewFlatIndex),
          onSwitch: (delta: number): void => {
            this.switchPreview(delta);
          },
          onClose: (): void => {
            this.closePreview();
          }
        })
          .width('100%')
          .height('100%')
          .opacity(this.previewOpacity)
          .scale({ x: this.previewScale, y: this.previewScale })
          .zIndex(100)
      }
    }
    .width('100%')
    .height('100%')
  }
}
