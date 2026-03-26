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

export const THUMB_CACHE_MAX = 250;
const thumbPixCache = new Map<string, PixelMap | null>();

/**
 * 缩略图并发加载限流器：最多同时进行 MAX_THUMB_CONCURRENT 个网络请求 + 解码。
 * 超出时排入等待队列，前一个完成后自动释放并启动下一个，避免大量并发导致主线程和网络拥塞。
 */
const MAX_THUMB_CONCURRENT = 4;
let thumbLoadActive = 0;
const thumbLoadWaiters: Array<() => void> = [];

function acquireThumbSlot(): Promise<void> {
  if (thumbLoadActive < MAX_THUMB_CONCURRENT) {
    thumbLoadActive++;
    return Promise.resolve();
  }
  return new Promise<void>((resolve) => {
    thumbLoadWaiters.push(resolve);
  });
}

function releaseThumbSlot(): void {
  if (thumbLoadWaiters.length > 0) {
    const next = thumbLoadWaiters.shift();
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
  const v = thumbPixCache.get(uri);
  return v !== undefined ? (v ?? undefined) : undefined;
}

export function itemFileExt(it: GalleryListItem): string {
  const name = it.filename ?? it.name ?? it.title ?? '';
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

export async function loadThumbPix(fullUrl: string): Promise<PixelMap | undefined> {
  if (fullUrl.length === 0) { return undefined; }
  const cached = thumbPixCache.get(fullUrl);
  if (cached !== undefined) { return cached ?? undefined; }

  // 等待并发槽位，避免大量同时下载解码导致卡顿
  await acquireThumbSlot();
  try {
    // 二次检查：等待期间可能已由其他协程填充缓存
    const cached2 = thumbPixCache.get(fullUrl);
    if (cached2 !== undefined) { return cached2 ?? undefined; }

    const client = AppSession.getClient();
    if (client === null) { return undefined; }
    const buf = await client.fetchGalleryImageBuffer(fullUrl, 8000);
    if (buf === undefined || buf.byteLength === 0) {
      thumbPixCache.set(fullUrl, null);
      return undefined;
    }
    const src = image.createImageSource(buf);
    // 不指定 desiredSize：按服务端缩略图原始尺寸解码，避免强制方形缩放导致发糊、比例失真；网格由 ImageFit.Cover 裁切
    const pix = await src.createPixelMap();
    src.release();
    if (thumbPixCache.size >= THUMB_CACHE_MAX) {
      let firstKey: string | undefined = undefined;
      for (const k of thumbPixCache.keys()) {
        firstKey = k;
        break;
      }
      if (firstKey !== undefined) { thumbPixCache.delete(firstKey); }
    }
    thumbPixCache.set(fullUrl, pix);
    return pix;
  } catch (_e) {
    thumbPixCache.set(fullUrl, null);
    return undefined;
  } finally {
    releaseThumbSlot();
  }
}

export async function loadFullPix(fullUrl: string): Promise<PixelMap | undefined> {
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

@Component
export struct GalleryThumbSkeleton {
  @State private alpha: number = 0.45;

  aboutToAppear(): void {
    this.getUIContext().animateTo(
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
      .backgroundColor('#E8EAED')
      .borderRadius(8)
      .opacity(this.alpha)
  }
}

@Component
export struct GalleryNetworkThumb {
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
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
        this.pixAlpha = 1;
      });
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.loading || this.pix === undefined) {
        GalleryThumbSkeleton()
      }
      if (this.pix !== undefined) {
        Image(this.pix)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
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
    .borderRadius(6)
    .clip(true)
  }
}
