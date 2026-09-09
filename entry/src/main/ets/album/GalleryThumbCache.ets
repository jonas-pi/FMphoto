import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppSession } from '../auth/AppSession';
import {
  GalleryThumbDiskCache,
  THUMB_DISK_NONE
} from './GalleryThumbDiskCache';
import {
  galleryPerfCapThumbConcurrent,
  galleryPerfFreezeResumeBatch,
  galleryPerfFreezeResumeDelayMs,
  galleryPerfPaintBatchMax,
  galleryPerfScaleCacheKeep,
  galleryPerfThumbCacheMax,
  galleryPerfThumbConcurrentRaw,
  registerGalleryLanBurstListener
} from './GalleryPerfProfile';

export const THUMB_CACHE_MAX = 288;

export function currentThumbCacheMax(): number {
  const cap = galleryPerfThumbCacheMax();
  return cap < THUMB_CACHE_MAX ? cap : THUMB_CACHE_MAX;
}
export const thumbPixCache = new Map<string, PixelMap>();
const thumbPixIdentityCache = new Map<string, ThumbIdentityCacheEntry>();
const previewMidPixCache = new Map<string, PixelMap>();
const previewMidInflight: Map<string, Promise<PixelMap | undefined>> = new Map();
const thumbLoadFailAt = new Map<string, number>();
/** 方向性预取去重；只约束预取任务，不改变可见缩略图的正常加载优先级。 */
const thumbPrefetchInflight: Set<string> = new Set();
const THUMB_FAIL_RETRY_COOLDOWN_MS = 1500;
/** 原图下载智能超时：先短后长，兼顾小图响应与大图成功率 */
const FULL_IMAGE_TIMEOUT_STEPS_MS: number[] = [12000, 25000, 45000];
const FULL_IMAGE_PREVIEW_MAX_EDGE_PX = 4096;
const FULL_IMAGE_SAFE_DECODE_BYTES = 24 * 1024 * 1024;
const FULL_IMAGE_SAFE_DECODE_PIXELS = FULL_IMAGE_PREVIEW_MAX_EDGE_PX * FULL_IMAGE_PREVIEW_MAX_EDGE_PX;
const FULL_IMAGE_NATIVE_RESPONSE_LIMIT_BYTES = 20 * 1024 * 1024;
/** 宫格缩略图最大边：按显示尺寸降采样解码（官方 Image Kit desiredSize） */
const THUMB_DECODE_MAX_EDGE_PX: number = 360;
/** 预览中档缩略图最大边：接近屏宽，仍走 m 档、不拉原图 */
const PREVIEW_MID_MAX_EDGE_PX: number = 2880;
const PREVIEW_MID_CACHE_MAX: number = 20;

export interface GalleryThumbLoadTelemetry {
  active: number;
  queued: number;
  currentLimit: number;
  avgQueueWaitMs: number;
  avgLoadMs: number;
  sampleCount: number;
}

interface ThumbIdentityCacheEntry {
  cacheKey: string;
  rank: number;
}

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

async function readImageSourceSize(src: image.ImageSource): Promise<image.Size | undefined> {
  try {
    const info = await src.getImageInfo();
    return info.size;
  } catch (_e) {
    return undefined;
  }
}

function shouldUseSafeFullDecode(srcSize?: image.Size, expectedBytes?: number): boolean {
  if (expectedBytes !== undefined && expectedBytes >= FULL_IMAGE_SAFE_DECODE_BYTES) {
    return true;
  }
  if (srcSize === undefined || srcSize.width <= 0 || srcSize.height <= 0) {
    return false;
  }
  return srcSize.width * srcSize.height > FULL_IMAGE_SAFE_DECODE_PIXELS;
}

function buildThumbDecodeSize(srcSize?: image.Size): image.Size | undefined {
  if (srcSize === undefined || srcSize.width <= 0 || srcSize.height <= 0) {
    return undefined;
  }
  const maxEdge = Math.max(srcSize.width, srcSize.height);
  if (maxEdge <= THUMB_DECODE_MAX_EDGE_PX) {
    return undefined;
  }
  const scale = THUMB_DECODE_MAX_EDGE_PX / maxEdge;
  return {
    height: Math.max(1, Math.floor(srcSize.height * scale)),
    width: Math.max(1, Math.floor(srcSize.width * scale))
  };
}

function buildPreviewMidDecodeSize(srcSize?: image.Size): image.Size | undefined {
  if (srcSize === undefined || srcSize.width <= 0 || srcSize.height <= 0) {
    return undefined;
  }
  const maxEdge = Math.max(srcSize.width, srcSize.height);
  if (maxEdge <= PREVIEW_MID_MAX_EDGE_PX) {
    return undefined;
  }
  const scale = PREVIEW_MID_MAX_EDGE_PX / maxEdge;
  return {
    height: Math.max(1, Math.floor(srcSize.height * scale)),
    width: Math.max(1, Math.floor(srcSize.width * scale))
  };
}

function buildSafeFullDecodeSize(srcSize?: image.Size): image.Size | undefined {
  if (srcSize === undefined || srcSize.width <= 0 || srcSize.height <= 0) {
    return undefined;
  }
  const maxEdge = Math.max(srcSize.width, srcSize.height);
  if (maxEdge <= FULL_IMAGE_PREVIEW_MAX_EDGE_PX) {
    return undefined;
  }
  const scale = FULL_IMAGE_PREVIEW_MAX_EDGE_PX / maxEdge;
  return {
    height: Math.max(1, Math.floor(srcSize.height * scale)),
    width: Math.max(1, Math.floor(srcSize.width * scale))
  };
}

async function tryCreateFullPixelMap(
  src: image.ImageSource,
  desiredDynamicRange: image.DecodingDynamicRange,
  desiredSize?: image.Size
): Promise<PixelMap | undefined> {
  try {
    const options: image.DecodingOptions = { desiredDynamicRange };
    if (desiredSize !== undefined) {
      options.desiredSize = desiredSize;
    }
    return await src.createPixelMap(options);
  } catch (_e) {
    return undefined;
  }
}

async function decodeFullPixFromSource(src: image.ImageSource, expectedBytes?: number): Promise<PixelMap | undefined> {
  const srcSize = await readImageSourceSize(src);
  const safeSize = buildSafeFullDecodeSize(srcSize);
  const safeDecode = shouldUseSafeFullDecode(srcSize, expectedBytes);
  let pix: PixelMap | undefined = undefined;
  if (!safeDecode) {
    pix = await tryCreateFullPixelMap(src, image.DecodingDynamicRange.HDR);
    if (pix !== undefined) {
      return pix;
    }
    pix = await tryCreateFullPixelMap(src, image.DecodingDynamicRange.SDR);
    if (pix !== undefined) {
      return pix;
    }
  }
  if (safeSize !== undefined) {
    pix = await tryCreateFullPixelMap(src, image.DecodingDynamicRange.SDR, safeSize);
    if (pix !== undefined) {
      return pix;
    }
    pix = await tryCreateFullPixelMap(src, image.DecodingDynamicRange.HDR, safeSize);
    if (pix !== undefined) {
      return pix;
    }
  }
  if (safeDecode) {
    return await tryCreateFullPixelMap(src, image.DecodingDynamicRange.SDR);
  }
  return undefined;
}

function fullImagePreviewFallbackUrl(fullUrl: string): string {
  return fullUrl.replace('/o/', '/m/');
}

function shouldAvoidNativeFullFetch(expectedBytes?: number): boolean {
  return expectedBytes !== undefined && expectedBytes >= FULL_IMAGE_NATIVE_RESPONSE_LIMIT_BYTES;
}

function shouldUseTempFileFullDecode(expectedBytes?: number, cacheDir?: string): boolean {
  return cacheDir !== undefined &&
    cacheDir.length > 0 &&
    shouldAvoidNativeFullFetch(expectedBytes);
}

async function decodeFullPixFromTempFile(
  fullUrl: string,
  expectedBytes: number | undefined,
  cacheDir: string
): Promise<PixelMap | undefined> {
  const client = AppSession.getClient();
  if (client === null) {
    return undefined;
  }
  const timeoutSteps = fullImageTimeoutSteps(expectedBytes);
  const timeoutMs = timeoutSteps[timeoutSteps.length - 1];
  const tempPath = `${cacheDir}/preview_original_${Date.now()}_${Math.floor(Math.random() * 1000000)}.img`;
  const downloaded = await client.downloadGalleryAssetToFile(fullUrl, tempPath, timeoutMs);
  if (!downloaded) {
    return undefined;
  }
  let fd = -1;
  try {
    // 下载接口返回成功后仍可能被并发清理；先确认临时文件存在，避免直接 open 产生 file_api -2。
    await fileIo.access(tempPath);
    const f = await fileIo.open(tempPath, fileIo.OpenMode.READ_ONLY);
    fd = f.fd;
    const src = image.createImageSource(fd);
    try {
      return await decodeFullPixFromSource(src, expectedBytes);
    } finally {
      src.release();
    }
  } catch (_e) {
    return undefined;
  } finally {
    if (fd >= 0) {
      try {
        await fileIo.close(fd);
      } catch (_e) {
      }
    }
    try {
      await fileIo.unlink(tempPath);
    } catch (_e) {
    }
  }
}

/**
 * 缩略图并发加载限流器：最多同时进行若干个网络请求 + 解码。
 * 超出时排入等待队列，前一个完成后自动释放并启动下一个。
 * 队列采用“可见优先 + 公平退避”：常态近似 LIFO，每隔若干次唤醒最早排队任务。
 * 公网保持克制；内网爆发把原始并发拉到 32～64，再按内存档封顶。
 * 快滑 / 时间轴跳转仍走解码闸门，避免为打满带宽把 UI 再次打卡。
 */
const THUMB_LOAD_EWMA_ALPHA = 0.24;
const THUMB_PAINT_BATCH_DELAY_MS = 18;
let thumbLoadActive = 0;
const thumbLoadWaiters: Array<() => void> = [];
let thumbWakeCount = 0;
let thumbHighThroughputDemand = 0;
let thumbAvgQueueWaitMs = 0;
let thumbAvgLoadMs = 0;
let thumbLoadSampleCount = 0;
const thumbPaintCommitQueue: Array<() => void> = [];
let thumbPaintCommitTimer: number = -1;

/** 内存 PixelMap 与磁盘 JPEG 共用：`裁黑标记|完整 URL` */
export function thumbCacheKey(fullUrl: string, autoCropBlack: boolean): string {
  return `${autoCropBlack ? '1' : '0'}|${fullUrl}`;
}

function dropThumbIdentityEntriesForCacheKey(cacheKey: string): void {
  const staleKeys: string[] = [];
  thumbPixIdentityCache.forEach((entry: ThumbIdentityCacheEntry, identity: string): void => {
    if (entry.cacheKey === cacheKey) {
      staleKeys.push(identity);
    }
  });
  for (let i = 0; i < staleKeys.length; i++) {
    thumbPixIdentityCache.delete(staleKeys[i]);
  }
}

function evictThumbCacheEntry(cacheKey: string): void {
  thumbPixCache.delete(cacheKey);
  dropThumbIdentityEntriesForCacheKey(cacheKey);
  /*
   * PixelMap 同时作为 Image 入参被页面组件持有。缓存淘汰只代表 Map 不再保留，
   * 不能调用 release() 销毁共享实例；否则导航栈下仍存活的缩略图会立即变空。
   * 移除 Map 强引用后，待 UI 也解除引用时由运行时回收底层资源。
   */
}

/** NAS 变更后丢掉全部内存 PixelMap，避免同 URL 脏读。 */
export function clearThumbPixCache(): void {
  const keys: string[] = [];
  thumbPixCache.forEach((_pix: PixelMap, key: string): void => {
    keys.push(key);
  });
  for (let i = 0; i < keys.length; i++) {
    evictThumbCacheEntry(keys[i]);
  }
  thumbPixIdentityCache.clear();
  thumbLoadFailAt.clear();
}

export function rememberThumbIdentityCache(identity: string, cacheKey: string, rank: number): void {
  if (identity.length <= 0 || rank <= 0) {
    return;
  }
  if (!thumbPixCache.has(cacheKey)) {
    return;
  }
  const existing = thumbPixIdentityCache.get(identity);
  if (existing !== undefined) {
    const existingPix = thumbPixCache.get(existing.cacheKey);
    if (existingPix !== undefined && existing.rank > rank) {
      return;
    }
  }
  thumbPixIdentityCache.set(identity, { cacheKey, rank });
}

function currentMaxThumbConcurrent(): number {
  return galleryPerfCapThumbConcurrent(galleryPerfThumbConcurrentRaw(thumbHighThroughputDemand));
}

function updateThumbEwma(current: number, next: number): number {
  if (current <= 0) {
    return next;
  }
  return current * (1 - THUMB_LOAD_EWMA_ALPHA) + next * THUMB_LOAD_EWMA_ALPHA;
}

function noteThumbLoadSample(queueWaitMs: number, loadMs: number): void {
  thumbAvgQueueWaitMs = updateThumbEwma(thumbAvgQueueWaitMs, Math.max(0, queueWaitMs));
  thumbAvgLoadMs = updateThumbEwma(thumbAvgLoadMs, Math.max(1, loadMs));
  thumbLoadSampleCount++;
}

export function getThumbLoadTelemetry(): GalleryThumbLoadTelemetry {
  const telemetry: GalleryThumbLoadTelemetry = {
    active: thumbLoadActive,
    queued: thumbLoadWaiters.length,
    currentLimit: currentMaxThumbConcurrent(),
    avgQueueWaitMs: thumbAvgQueueWaitMs,
    avgLoadMs: thumbAvgLoadMs,
    sampleCount: thumbLoadSampleCount
  };
  return telemetry;
}

function flushThumbPaintCommitQueue(): void {
  if (thumbPaintCommitTimer >= 0) {
    clearTimeout(thumbPaintCommitTimer);
    thumbPaintCommitTimer = -1;
  }
  const batchCount = Math.min(galleryPerfPaintBatchMax(), thumbPaintCommitQueue.length);
  for (let i = 0; i < batchCount; i++) {
    const next = thumbPaintCommitQueue.shift();
    if (next !== undefined) {
      next();
    }
  }
  if (thumbPaintCommitQueue.length > 0) {
    thumbPaintCommitTimer = setTimeout((): void => {
      flushThumbPaintCommitQueue();
    }, THUMB_PAINT_BATCH_DELAY_MS);
  }
}

export function enqueueThumbPaintCommit(task: () => void): void {
  thumbPaintCommitQueue.push(task);
  if (thumbPaintCommitQueue.length >= galleryPerfPaintBatchMax()) {
    flushThumbPaintCommitQueue();
    return;
  }
  if (thumbPaintCommitTimer < 0) {
    thumbPaintCommitTimer = setTimeout((): void => {
      flushThumbPaintCommitQueue();
    }, THUMB_PAINT_BATCH_DELAY_MS);
  }
}

/**
 * 主时间线快滑冻结：模块级开关，不走 @Prop/@State，避免整屏缩略图变脏。
 * 已上屏的 PixelMap 继续显示；未命中缓存的网络解码推迟到松手后 resume。
 */
let galleryListScrollFrozen: boolean = false;
let gallerySeekDecodeHold: boolean = false;
let gallerySeekDecodeHoldTimer: number = -1;
const galleryThumbFreezeResumes: Array<() => void> = [];
let galleryThumbFreezeResumeTimer: number = -1;

export function isGalleryListScrollFrozen(): boolean {
  return galleryListScrollFrozen || gallerySeekDecodeHold;
}

function pumpGalleryThumbFreezeResumes(): void {
  if (isGalleryListScrollFrozen()) {
    return;
  }
  const batch = Math.max(1, galleryPerfFreezeResumeBatch());
  const chunk = galleryThumbFreezeResumes.splice(0, batch);
  for (let i = 0; i < chunk.length; i++) {
    chunk[i]();
  }
  if (galleryThumbFreezeResumes.length <= 0 || isGalleryListScrollFrozen()) {
    return;
  }
  if (galleryThumbFreezeResumeTimer >= 0) {
    return;
  }
  galleryThumbFreezeResumeTimer = setTimeout((): void => {
    galleryThumbFreezeResumeTimer = -1;
    pumpGalleryThumbFreezeResumes();
  }, galleryPerfFreezeResumeDelayMs());
}

export function setGalleryListScrollFrozen(frozen: boolean): void {
  if (galleryListScrollFrozen === frozen) {
    return;
  }
  galleryListScrollFrozen = frozen;
  if (frozen || gallerySeekDecodeHold) {
    return;
  }
  pumpGalleryThumbFreezeResumes();
}

/**
 * 时间轴跳转后的解码闸门：与列表 fling 冻结独立。
 * 跳转落点未稳住前不解开网络解码，松手后按批 resume，避免一次灌入整月缩略图。
 */
export function setGallerySeekDecodeHold(hold: boolean, maxHoldMs: number = 0): void {
  if (gallerySeekDecodeHoldTimer >= 0) {
    clearTimeout(gallerySeekDecodeHoldTimer);
    gallerySeekDecodeHoldTimer = -1;
  }
  if (gallerySeekDecodeHold === hold) {
    if (hold && maxHoldMs > 0) {
      gallerySeekDecodeHoldTimer = setTimeout((): void => {
        gallerySeekDecodeHoldTimer = -1;
        setGallerySeekDecodeHold(false);
      }, maxHoldMs);
    }
    return;
  }
  gallerySeekDecodeHold = hold;
  if (hold) {
    if (maxHoldMs > 0) {
      gallerySeekDecodeHoldTimer = setTimeout((): void => {
        gallerySeekDecodeHoldTimer = -1;
        setGallerySeekDecodeHold(false);
      }, maxHoldMs);
    }
    return;
  }
  if (!galleryListScrollFrozen) {
    pumpGalleryThumbFreezeResumes();
  }
}

export function registerGalleryThumbFreezeResume(resume: () => void): void {
  if (!isGalleryListScrollFrozen()) {
    resume();
    return;
  }
  galleryThumbFreezeResumes.push(resume);
}

function takeNextThumbWaiter(): (() => void) | undefined {
  thumbWakeCount++;
  return (thumbWakeCount % 4 === 0) ? thumbLoadWaiters.shift() : thumbLoadWaiters.pop();
}

function pumpThumbWaiters(): void {
  while (thumbLoadWaiters.length > 0 && thumbLoadActive < currentMaxThumbConcurrent()) {
    const next = takeNextThumbWaiter();
    if (next === undefined) {
      break;
    }
    thumbLoadActive++;
    next();
  }
}

registerGalleryLanBurstListener((): void => {
  pumpThumbWaiters();
});

function acquireThumbSlot(): Promise<void> {
  if (thumbLoadActive < currentMaxThumbConcurrent()) {
    thumbLoadActive++;
    return Promise.resolve();
  }
  return new Promise<void>((resolve) => {
    thumbLoadWaiters.push(resolve);
  });
}

function updateThumbHighThroughputDemand(delta: number): void {
  thumbHighThroughputDemand = Math.max(0, thumbHighThroughputDemand + delta);
  pumpThumbWaiters();
}

export function setThumbHighThroughputMode(enabled: boolean): void {
  thumbHighThroughputDemand = enabled ? 1 : 0;
  pumpThumbWaiters();
}

export function setThumbHighThroughputLevel(level: number): void {
  thumbHighThroughputDemand = Math.max(0, Math.floor(level));
  pumpThumbWaiters();
}

/** 仅释放尚未交给缓存或 UI 的废弃 PixelMap。共享实例不得在缓存淘汰时调用。 */
function releaseThumbPix(p: PixelMap): void {
  try {
    p.release();
  } catch (_e) {
  }
}

function releaseThumbSlot(): void {
  if (thumbLoadActive > 0) {
    thumbLoadActive--;
  }
  pumpThumbWaiters();
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

export function getThumbPixCachedByIdentity(identity: string): PixelMap | undefined {
  if (identity.length === 0) {
    return undefined;
  }
  const entry = thumbPixIdentityCache.get(identity);
  if (entry === undefined) {
    return undefined;
  }
  const pix = thumbPixCache.get(entry.cacheKey);
  if (pix === undefined) {
    thumbPixIdentityCache.delete(identity);
    return undefined;
  }
  return pix;
}

export function getThumbIdentityCacheRank(identity: string): number {
  if (identity.length === 0) {
    return 0;
  }
  const entry = thumbPixIdentityCache.get(identity);
  if (entry === undefined) {
    return 0;
  }
  if (!thumbPixCache.has(entry.cacheKey)) {
    thumbPixIdentityCache.delete(identity);
    return 0;
  }
  return entry.rank;
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
    evictThumbCacheEntry(firstKey);
  }
}

export function recommendedThumbCacheKeep(itemCount: number, aggressive: boolean = false): number {
  const total = Math.max(0, Math.floor(itemCount));
  if (aggressive) {
    if (total > 1200) {
      return galleryPerfScaleCacheKeep(20);
    }
    if (total > 720) {
      return galleryPerfScaleCacheKeep(24);
    }
    if (total > 360) {
      return galleryPerfScaleCacheKeep(28);
    }
    if (total > 180) {
      return galleryPerfScaleCacheKeep(32);
    }
    return galleryPerfScaleCacheKeep(40);
  }
  if (total > 2400) {
    return galleryPerfScaleCacheKeep(48);
  }
  if (total > 1200) {
    return galleryPerfScaleCacheKeep(56);
  }
  if (total > 720) {
    return galleryPerfScaleCacheKeep(64);
  }
  if (total > 360) {
    return galleryPerfScaleCacheKeep(80);
  }
  if (total > 180) {
    return galleryPerfScaleCacheKeep(96);
  }
  return galleryPerfScaleCacheKeep(120);
}

export function trimThumbPixCacheForList(itemCount: number, aggressive: boolean = false): void {
  trimThumbPixCache(recommendedThumbCacheKeep(itemCount, aggressive));
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

async function decodeThumbPixFromBuffer(buf: ArrayBuffer, autoCropBlack: boolean): Promise<PixelMap | undefined> {
  const src = image.createImageSource(buf);
  try {
    const srcSize = await readImageSourceSize(src);
    const desired = buildThumbDecodeSize(srcSize);
    let pix = await tryCreateFullPixelMap(src, image.DecodingDynamicRange.SDR, desired);
    if (pix === undefined && desired !== undefined) {
      pix = await tryCreateFullPixelMap(src, image.DecodingDynamicRange.SDR);
    }
    if (pix === undefined) {
      return undefined;
    }
    if (autoCropBlack) {
      await autoCropBlackBorders(pix);
    }
    return pix;
  } finally {
    src.release();
  }
}

async function decodePreviewMidPixFromBuffer(buf: ArrayBuffer): Promise<PixelMap | undefined> {
  const src = image.createImageSource(buf);
  try {
    const srcSize = await readImageSourceSize(src);
    const desired = buildPreviewMidDecodeSize(srcSize);
    let pix = await tryCreateFullPixelMap(src, image.DecodingDynamicRange.SDR, desired);
    if (pix === undefined && desired !== undefined) {
      pix = await tryCreateFullPixelMap(src, image.DecodingDynamicRange.SDR);
    }
    return pix;
  } finally {
    src.release();
  }
}

function previewMidCacheKey(url: string): string {
  return `mid|${url}`;
}

function rememberPreviewMidPix(key: string, pix: PixelMap): void {
  if (previewMidPixCache.size >= PREVIEW_MID_CACHE_MAX && !previewMidPixCache.has(key)) {
    let firstKey: string | undefined = undefined;
    for (const k of previewMidPixCache.keys()) {
      firstKey = k;
      break;
    }
    if (firstKey !== undefined) {
      previewMidPixCache.delete(firstKey);
      // 中清图也可能仍由预览页 Image 持有；只移除缓存引用，不主动销毁共享 PixelMap。
    }
  }
  previewMidPixCache.set(key, pix);
}

export function getPreviewMidPixCached(uri: string): PixelMap | undefined {
  if (uri.length === 0) {
    return undefined;
  }
  return previewMidPixCache.get(previewMidCacheKey(uri));
}

/**
 * 预览中档缩略图：优先复用宫格已落盘的 JPEG，按 1600px 边长解码，不拉原图。
 */
export async function loadPreviewMidPix(fullUrl: string): Promise<PixelMap | undefined> {
  if (fullUrl.length === 0) {
    return undefined;
  }
  const midKey = previewMidCacheKey(fullUrl);
  const cached = previewMidPixCache.get(midKey);
  if (cached !== undefined) {
    return cached;
  }
  const pending = previewMidInflight.get(fullUrl);
  if (pending !== undefined) {
    return pending;
  }
  const task = thisLoadPreviewMidPix(fullUrl, midKey);
  previewMidInflight.set(fullUrl, task);
  try {
    return await task;
  } finally {
    previewMidInflight.delete(fullUrl);
  }
}

async function thisLoadPreviewMidPix(fullUrl: string, midKey: string): Promise<PixelMap | undefined> {
  const genAtStart = GalleryThumbDiskCache.generation;
  const gridKey = thumbCacheKey(fullUrl, false);
  let buf = await GalleryThumbDiskCache.tryRead(gridKey);
  if (buf === undefined || buf.byteLength === 0) {
    const client = AppSession.getClient();
    if (client === null) {
      return undefined;
    }
    buf = await client.fetchGalleryImageBuffer(fullUrl, 15000);
  }
  if (buf === undefined || buf.byteLength === 0) {
    return undefined;
  }
  if (genAtStart !== GalleryThumbDiskCache.generation) {
    return undefined;
  }
  const pix = await decodePreviewMidPixFromBuffer(buf);
  if (pix === undefined) {
    return undefined;
  }
  if (genAtStart !== GalleryThumbDiskCache.generation) {
    releaseThumbPix(pix);
    return undefined;
  }
  rememberPreviewMidPix(midKey, pix);
  return pix;
}

function rememberDecodedThumbPix(key: string, pix: PixelMap, cacheIdentity: string, cacheRank: number): void {
  if (thumbPixCache.size >= currentThumbCacheMax() && !thumbPixCache.has(key)) {
    let firstKey: string | undefined = undefined;
    for (const k of thumbPixCache.keys()) {
      firstKey = k;
      break;
    }
    if (firstKey !== undefined) {
      evictThumbCacheEntry(firstKey);
    }
  }
  thumbPixCache.set(key, pix);
  rememberThumbIdentityCache(cacheIdentity, key, cacheRank);
  thumbLoadFailAt.delete(key);
}

export async function loadThumbPix(
  fullUrl: string,
  autoCropBlack: boolean = false,
  cacheIdentity: string = '',
  cacheRank: number = 0,
  diskKind: number = THUMB_DISK_NONE
): Promise<PixelMap | undefined> {
  if (fullUrl.length === 0) { return undefined; }
  const key = thumbCacheKey(fullUrl, autoCropBlack);
  const persistKind = GalleryThumbDiskCache.resolveKind(key, diskKind);
  const genAtStart = GalleryThumbDiskCache.generation;
  const cached = thumbPixCache.get(key);
  if (cached !== undefined) {
    rememberThumbIdentityCache(cacheIdentity, key, cacheRank);
    if (persistKind !== THUMB_DISK_NONE) {
      GalleryThumbDiskCache.ensurePersisted(key, persistKind);
    }
    return cached;
  }
  const failAt = thumbLoadFailAt.get(key);
  if (failAt !== undefined && Date.now() - failAt < THUMB_FAIL_RETRY_COOLDOWN_MS) {
    return undefined;
  }

  const diskBuf = await GalleryThumbDiskCache.tryRead(key);
  if (diskBuf !== undefined && diskBuf.byteLength > 0) {
    try {
      const diskPix = await decodeThumbPixFromBuffer(diskBuf, autoCropBlack);
      if (diskPix !== undefined) {
        if (genAtStart !== GalleryThumbDiskCache.generation) {
          releaseThumbPix(diskPix);
          return undefined;
        }
        rememberDecodedThumbPix(key, diskPix, cacheIdentity, cacheRank);
        return diskPix;
      }
    } catch (_e) {
    }
    // 缓存内容无法解码时立即丢弃，防止每次进入视区都重复触发 JPEG 解码失败。
    GalleryThumbDiskCache.discard(key);
  }

  // 等待并发槽位，避免大量同时下载解码导致卡顿
  const queueWaitStartedAt = Date.now();
  await acquireThumbSlot();
  const slotAcquiredAt = Date.now();
  try {
    // 二次检查：等待期间可能已由其他协程填充缓存
    const cached2 = thumbPixCache.get(key);
    if (cached2 !== undefined) {
      rememberThumbIdentityCache(cacheIdentity, key, cacheRank);
      return cached2;
    }
    if (genAtStart !== GalleryThumbDiskCache.generation) {
      return undefined;
    }

    const client = AppSession.getClient();
    if (client === null) { return undefined; }
    const buf = await client.fetchGalleryImageBuffer(fullUrl, 8000);
    if (buf === undefined || buf.byteLength === 0) {
      thumbLoadFailAt.set(key, Date.now());
      return undefined;
    }
    if (genAtStart !== GalleryThumbDiskCache.generation) {
      return undefined;
    }
    // 网格缩略图用 SDR 解码，显著低于 HDR/F16 的内存占用，降低大图库滑动崩溃风险；预览大图仍走 loadFullPix(HDR)
    const pix = await decodeThumbPixFromBuffer(buf, autoCropBlack);
    if (pix === undefined) {
      thumbLoadFailAt.set(key, Date.now());
      return undefined;
    }
    if (genAtStart !== GalleryThumbDiskCache.generation) {
      releaseThumbPix(pix);
      return undefined;
    }
    // 只有确认数据可以解码后才落盘，避免把截断响应或错误页持久化为损坏 JPEG。
    if (persistKind !== THUMB_DISK_NONE) {
      GalleryThumbDiskCache.put(key, buf, persistKind);
    }
    rememberDecodedThumbPix(key, pix, cacheIdentity, cacheRank);
    return pix;
  } catch (_e) {
    thumbLoadFailAt.set(key, Date.now());
    return undefined;
  } finally {
    noteThumbLoadSample(slotAcquiredAt - queueWaitStartedAt, Date.now() - slotAcquiredAt);
    releaseThumbSlot();
  }
}

/**
 * 将即将进入视口的单张缩略图送入现有下载/解码队列。
 *
 * 本函数不写响应式状态，也不直接更新 Image；完成后只进入 PixelMap LRU。
 * 当 LazyForEach 真正挂载该格子时会同步命中缓存，因此滚动帧不会承担解码和批量上屏。
 */
export function prefetchThumbPix(
  fullUrl: string,
  autoCropBlack: boolean = false,
  cacheIdentity: string = '',
  cacheRank: number = 0
): void {
  if (fullUrl.length === 0) {
    return;
  }
  const key = thumbCacheKey(fullUrl, autoCropBlack);
  if (thumbPixCache.has(key) || thumbPrefetchInflight.has(key)) {
    return;
  }
  thumbPrefetchInflight.add(key);
  void loadThumbPix(fullUrl, autoCropBlack, cacheIdentity, cacheRank).then((): void => {
    thumbPrefetchInflight.delete(key);
  }).catch((): void => {
    thumbPrefetchInflight.delete(key);
  });
}

export async function loadFullPix(
  fullUrl: string,
  expectedBytes?: number,
  cacheDir?: string
): Promise<PixelMap | undefined> {
  if (fullUrl.length === 0) {
    return undefined;
  }
  if (shouldUseTempFileFullDecode(expectedBytes, cacheDir)) {
    const filePix = await decodeFullPixFromTempFile(fullUrl, expectedBytes, cacheDir as string);
    if (filePix !== undefined) {
      return filePix;
    }
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
  const fallbackUrl = fullImagePreviewFallbackUrl(fullUrl);
  const fetchUrl = shouldAvoidNativeFullFetch(expectedBytes) && fallbackUrl !== fullUrl
    ? fallbackUrl
    : fullUrl;
  const timeoutSteps = fullImageTimeoutSteps(fetchUrl === fullUrl ? expectedBytes : undefined);
  for (let i = 0; i < timeoutSteps.length; i++) {
    buf = await client.fetchGalleryImageBuffer(fetchUrl, timeoutSteps[i]);
    if (buf !== undefined && buf.byteLength > 0) {
      break;
    }
  }
  if ((buf === undefined || buf.byteLength === 0) && fallbackUrl !== fullUrl && fetchUrl === fullUrl) {
    for (let i = 0; i < FULL_IMAGE_TIMEOUT_STEPS_MS.length; i++) {
      buf = await client.fetchGalleryImageBuffer(fallbackUrl, FULL_IMAGE_TIMEOUT_STEPS_MS[i]);
      if (buf !== undefined && buf.byteLength > 0) {
        break;
      }
    }
  }
  if (buf === undefined || buf.byteLength === 0) {
    return undefined;
  }
  const src = image.createImageSource(buf);
  try {
    // Avoid full-resolution HDR decode for large originals; it can allocate hundreds of MB.
    return await decodeFullPixFromSource(src, fetchUrl === fullUrl ? expectedBytes : undefined);
  } finally {
    src.release();
  }
}
