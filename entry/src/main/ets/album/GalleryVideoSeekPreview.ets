/**
 * 拖进度条时的小窗预览。
 *
 * 飞牛原片 HTTPS 抽帧会失败（Range/鉴权/格式），还会和满载下载抢带宽，
 * 表现为缓存条停住、小窗一直黑。因此本会话只读本地预取，不再 setUrlSource。
 *
 * 抽帧优先级：
 * 1) 已封口的连续文件 → AVImageGenerator + 独立 fd（API20 按比例缩放抽帧）
 * 2) 边下边播半成品 → AVMetadataExtractor.dataSrc + 独立 fd（与播放器同一套 fill）
 * 3) 预取尚未可播 → 只显示时间，不出画（避免再打一条 HTTP）
 */
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  fillGalleryVideoLanPrefetchFromFd,
  galleryVideoLanPrefetchBufferedMs,
  galleryVideoLanPrefetchFileSize,
  getGalleryVideoLanPrefetchPath,
  isGalleryVideoLanPrefetchComplete,
  isGalleryVideoLanPrefetchForUrl,
  isGalleryVideoLanPrefetchPlayable,
  openGalleryVideoLanPrefetchPlayFd,
  closeGalleryVideoLanPrefetchFd,
  sealGalleryVideoLanPrefetchFile
} from './GalleryVideoLanPrefetch';

const DOMAIN: number = 0xFF00;
const TAG: string = 'SeekPreview';
/** 小窗约 160×90 vp，按 2x 抽帧避免发糊 */
const PREVIEW_MAX_W: number = 320;
const PREVIEW_MAX_H: number = 180;
const PREVIEW_BUCKET_MS: number = 400;
/** 卡住时尽快让出队列；4K I 帧偶发超过 500ms */
const PREVIEW_FETCH_WATCHDOG_MS: number = 800;
const PREVIEW_CACHE_MAX: number = 40;

export class GalleryVideoSeekPreviewSession {
  private generator: media.AVImageGenerator | null = null;
  private extractor: media.AVMetadataExtractor | null = null;
  private fd: number = -1;
  private attachedUrl: string = '';
  private wantUrl: string = '';
  private inflight: boolean = false;
  private pendingMs: number = -1;
  private pendingVw: number = 0;
  private pendingVh: number = 0;
  private lastBucket: number = -1;
  private seq: number = 0;
  private fetchWatchId: number = 0;
  private onFrame: ((pix: image.PixelMap | undefined) => void) | null = null;
  private cacheKeys: number[] = [];
  private cacheVals: image.PixelMap[] = [];
  private shownBucket: number = -1;

  prepare(url: string, _headers: Record<string, string>, onFrame: (pix: image.PixelMap | undefined) => void): void {
    this.wantUrl = url.trim();
    this.onFrame = onFrame;
    this.ensureAttached();
  }

  /** 松手 seek 时停抽帧，但保留生成器与缓存，下次拖动不用重建。 */
  idle(): void {
    this.clearFetchWatch();
    this.inflight = false;
    this.pendingMs = -1;
  }

  request(timeMs: number, videoPxW: number, videoPxH: number, durationMs: number): void {
    this.ensureAttached();
    let ms = Math.max(0, timeMs);
    if (this.wantUrl.length > 0 && !isGalleryVideoLanPrefetchComplete()) {
      const cap = galleryVideoLanPrefetchBufferedMs(durationMs);
      if (cap > 0 && ms > cap) {
        ms = cap;
      }
    }
    const bucket = Math.floor(ms / PREVIEW_BUCKET_MS);
    const exact = this.cacheGet(bucket);
    if (exact !== undefined) {
      this.pendingMs = -1;
      this.lastBucket = bucket;
      this.emitFrame(bucket, exact);
      return;
    }
    const near = this.cacheNearest(bucket);
    if (near !== undefined) {
      this.emitFrame(this.shownBucket >= 0 ? this.shownBucket : bucket, near);
    }
    this.pendingMs = ms;
    this.pendingVw = videoPxW;
    this.pendingVh = videoPxH;
    if (this.inflight) {
      return;
    }
    this.pump();
  }

  release(): void {
    this.wantUrl = '';
    this.onFrame = null;
    this.detachSources();
  }

  /** 本地源已挂上则复用；下载完成后从 dataSrc 升级到完整文件。 */
  private ensureAttached(): void {
    const url = this.wantUrl;
    if (url.length === 0) {
      return;
    }
    if (this.generator !== null && this.attachedUrl === url) {
      return;
    }
    if (this.extractor !== null && this.attachedUrl === url) {
      if (!isGalleryVideoLanPrefetchComplete()) {
        return;
      }
      this.detachSources();
    }
    if (this.fd >= 0 && this.attachedUrl === url) {
      return;
    }
    if (this.tryAttachLocal(url)) {
      return;
    }
    if (this.tryAttachPrefetchDataSrc(url)) {
      return;
    }
  }

  private clearFetchWatch(): void {
    if (this.fetchWatchId === 0) {
      return;
    }
    try {
      clearTimeout(this.fetchWatchId);
    } catch (_e) {
    }
    this.fetchWatchId = 0;
  }

  private detachSources(): void {
    this.seq++;
    this.clearFetchWatch();
    this.inflight = false;
    this.pendingMs = -1;
    this.lastBucket = -1;
    this.shownBucket = -1;
    this.clearCache();
    const gen = this.generator;
    this.generator = null;
    const ext = this.extractor;
    this.extractor = null;
    this.attachedUrl = '';
    if (gen !== null) {
      gen.release().catch((): void => {});
    }
    if (ext !== null) {
      ext.release().catch((): void => {});
    }
    if (this.fd >= 0) {
      closeGalleryVideoLanPrefetchFd(this.fd);
      this.fd = -1;
    }
  }

  /** 仅完整封口后的连续文件才能给 AVImageGenerator */
  private tryAttachLocal(url: string): boolean {
    if (!isGalleryVideoLanPrefetchForUrl(url) || !isGalleryVideoLanPrefetchComplete()) {
      return false;
    }
    if (!sealGalleryVideoLanPrefetchFile()) {
      return false;
    }
    const path = getGalleryVideoLanPrefetchPath();
    if (path.length === 0) {
      return false;
    }
    const fd = openGalleryVideoLanPrefetchPlayFd();
    if (fd < 0) {
      return false;
    }
    this.fd = fd;
    this.attachedUrl = url;
    const self = this;
    media.createAVImageGenerator().then((gen: media.AVImageGenerator): void => {
      if (self.attachedUrl !== url || self.fd !== fd) {
        try {
          gen.release();
        } catch (_e) {
        }
        return;
      }
      let length = -1;
      try {
        length = Number(fileIo.statSync(path).size);
      } catch (_e) {
      }
      const src: media.AVFileDescriptor = length > 0 ?
        { fd: fd, offset: 0, length: length } :
        { fd: fd };
      gen.fdSrc = src;
      self.generator = gen;
      hilog.info(DOMAIN, TAG, 'local generator ready size=%{public}s', `${length}`);
      self.pump();
    }).catch((): void => {
      hilog.warn(DOMAIN, TAG, 'local generator create fail, try extractor fd');
      self.tryAttachExtractorFd(url, fd);
    });
    return true;
  }

  private tryAttachExtractorFd(url: string, fd: number): void {
    const self = this;
    media.createAVMetadataExtractor().then((ext: media.AVMetadataExtractor): void => {
      if (self.attachedUrl !== url || self.fd !== fd) {
        try {
          ext.release();
        } catch (_e) {
        }
        return;
      }
      let length = -1;
      try {
        length = Number(fileIo.statSync(getGalleryVideoLanPrefetchPath()).size);
      } catch (_e) {
      }
      ext.fdSrc = length > 0 ? { fd: fd, offset: 0, length: length } : { fd: fd };
      self.extractor = ext;
      hilog.info(DOMAIN, TAG, 'local extractor fd ready size=%{public}s', `${length}`);
      self.pump();
    }).catch((): void => {
      hilog.warn(DOMAIN, TAG, 'local extractor fd create fail');
      if (self.fd === fd) {
        closeGalleryVideoLanPrefetchFd(fd);
        self.fd = -1;
        self.attachedUrl = '';
      }
    });
  }

  private tryAttachPrefetchDataSrc(url: string): boolean {
    if (!isGalleryVideoLanPrefetchPlayable(url) || isGalleryVideoLanPrefetchComplete()) {
      return false;
    }
    const fd = openGalleryVideoLanPrefetchPlayFd();
    if (fd < 0) {
      return false;
    }
    this.fd = fd;
    this.attachedUrl = url;
    const self = this;
    media.createAVMetadataExtractor().then((ext: media.AVMetadataExtractor): void => {
      if (self.attachedUrl !== url || self.fd !== fd) {
        try {
          ext.release();
        } catch (_e) {
        }
        closeGalleryVideoLanPrefetchFd(fd);
        return;
      }
      const dataSrc: media.AVDataSrcDescriptor = {
        fileSize: galleryVideoLanPrefetchFileSize(),
        callback: (buffer: ArrayBuffer, length: number, pos?: number): number => {
          return fillGalleryVideoLanPrefetchFromFd(fd, buffer, length, pos);
        }
      };
      ext.dataSrc = dataSrc;
      self.extractor = ext;
      hilog.info(DOMAIN, TAG, 'prefetch dataSrc extractor ready');
      self.pump();
    }).catch((): void => {
      hilog.warn(DOMAIN, TAG, 'prefetch dataSrc extractor create fail');
      if (self.fd === fd) {
        closeGalleryVideoLanPrefetchFd(fd);
        self.fd = -1;
        self.attachedUrl = '';
      }
    });
    return true;
  }

  private previewParam(videoPxW: number, videoPxH: number): media.PixelMapParams {
    const aw = videoPxW > 0 ? videoPxW : 16;
    const ah = videoPxH > 0 ? videoPxH : 9;
    const ratio = aw / ah;
    const boxR = PREVIEW_MAX_W / PREVIEW_MAX_H;
    const even = (n: number): number => Math.max(2, n - (n % 2));
    if (ratio >= boxR) {
      const h = even(Math.max(108, Math.round(PREVIEW_MAX_W / ratio)));
      return { width: even(PREVIEW_MAX_W), height: h };
    }
    const w = even(Math.max(160, Math.round(PREVIEW_MAX_H * ratio)));
    return { width: w, height: even(PREVIEW_MAX_H) };
  }

  private emitFrame(bucket: number, pix: image.PixelMap): void {
    this.shownBucket = bucket;
    const cb = this.onFrame;
    if (cb !== null) {
      cb(pix);
    }
  }

  private cacheGet(bucket: number): image.PixelMap | undefined {
    for (let i = 0; i < this.cacheKeys.length; i++) {
      if (this.cacheKeys[i] === bucket) {
        return this.cacheVals[i];
      }
    }
    return undefined;
  }

  private cacheNearest(bucket: number): image.PixelMap | undefined {
    const prev = this.cacheGet(bucket - 1);
    if (prev !== undefined) {
      return prev;
    }
    const next = this.cacheGet(bucket + 1);
    if (next !== undefined) {
      return next;
    }
    if (this.shownBucket >= 0) {
      return this.cacheGet(this.shownBucket);
    }
    return undefined;
  }

  private cachePut(bucket: number, pix: image.PixelMap): void {
    for (let i = 0; i < this.cacheKeys.length; i++) {
      if (this.cacheKeys[i] === bucket) {
        const old = this.cacheVals[i];
        if (old !== pix) {
          try {
            old.release();
          } catch (_e) {
          }
        }
        this.cacheVals[i] = pix;
        return;
      }
    }
    this.cacheKeys.push(bucket);
    this.cacheVals.push(pix);
    while (this.cacheKeys.length > PREVIEW_CACHE_MAX) {
      let dropAt = 0;
      if (this.cacheKeys[0] === this.shownBucket && this.cacheKeys.length > 1) {
        dropAt = 1;
      }
      const drop = this.cacheVals[dropAt];
      this.cacheKeys.splice(dropAt, 1);
      this.cacheVals.splice(dropAt, 1);
      try {
        drop.release();
      } catch (_e) {
      }
    }
  }

  private clearCache(): void {
    for (let i = 0; i < this.cacheVals.length; i++) {
      try {
        this.cacheVals[i].release();
      } catch (_e) {
      }
    }
    this.cacheKeys = [];
    this.cacheVals = [];
  }

  private startFetch(
    gen: media.AVImageGenerator | null,
    ext: media.AVMetadataExtractor | null,
    timeUs: number,
    query: media.AVImageQueryOptions,
    param: media.PixelMapParams
  ): Promise<image.PixelMap> {
    if (gen !== null) {
      const g = gen;
      const size: media.OutputSize = { width: param.width, height: param.height };
      return g.fetchScaledFrameByTime(timeUs, query, size).catch((): Promise<image.PixelMap> => {
        return g.fetchFrameByTime(timeUs, query, param);
      });
    }
    if (ext !== null) {
      return ext.fetchFrameByTime(timeUs, query, param);
    }
    return Promise.reject(new Error('no source'));
  }

  private pump(): void {
    const ms = this.pendingMs;
    if (ms < 0) {
      return;
    }
    const gen = this.generator;
    const ext = this.extractor;
    if (gen === null && ext === null) {
      return;
    }
    const bucket = Math.floor(ms / PREVIEW_BUCKET_MS);
    const cached = this.cacheGet(bucket);
    if (cached !== undefined) {
      this.pendingMs = -1;
      this.lastBucket = bucket;
      this.emitFrame(bucket, cached);
      return;
    }
    if (bucket === this.lastBucket) {
      this.pendingMs = -1;
      return;
    }
    this.inflight = true;
    this.pendingMs = -1;
    const seq = this.seq;
    this.clearFetchWatch();
    this.fetchWatchId = setTimeout((): void => {
      this.fetchWatchId = 0;
      if (seq !== this.seq || !this.inflight) {
        return;
      }
      hilog.warn(DOMAIN, TAG, 'fetchFrame watchdog t=%{public}s', `${ms}`);
      this.inflight = false;
      if (this.pendingMs >= 0) {
        this.pump();
      }
    }, PREVIEW_FETCH_WATCHDOG_MS);
    const timeUs = ms * 1000;
    const param = this.previewParam(this.pendingVw, this.pendingVh);
    const query = media.AVImageQueryOptions.AV_IMAGE_QUERY_PREVIOUS_SYNC;
    this.startFetch(gen, ext, timeUs, query, param).then((pix: image.PixelMap): void => {
      if (seq !== this.seq) {
        try {
          pix.release();
        } catch (_e) {
        }
        this.finishPump(seq);
        return;
      }
      this.lastBucket = bucket;
      this.cachePut(bucket, pix);
      this.emitFrame(bucket, pix);
      this.finishPump(seq);
    }).catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'fetchFrame fail t=%{public}s err=%{public}s', `${ms}`, `${error}`);
      if (seq === this.seq && gen === null &&
        isGalleryVideoLanPrefetchForUrl(this.attachedUrl) &&
        isGalleryVideoLanPrefetchComplete()) {
        const keepUrl = this.attachedUrl;
        const keepCb = this.onFrame;
        const keepWant = this.wantUrl;
        this.detachSources();
        this.wantUrl = keepWant.length > 0 ? keepWant : keepUrl;
        this.onFrame = keepCb;
        if (this.pendingMs < 0) {
          this.pendingMs = ms;
        }
        if (this.tryAttachLocal(this.wantUrl)) {
          return;
        }
      }
      this.finishPump(seq);
    });
  }

  private finishPump(seq: number): void {
    if (seq !== this.seq) {
      return;
    }
    this.clearFetchWatch();
    this.inflight = false;
    if (this.pendingMs >= 0) {
      this.pump();
    }
  }
}
