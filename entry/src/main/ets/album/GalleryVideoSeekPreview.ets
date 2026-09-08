/**
 * 拖进度条时的小窗预览。
 *
 * 飞牛原片 HTTPS 抽帧会失败（Range/鉴权/格式），还会和满载下载抢带宽，
 * 表现为缓存条停住、小窗一直黑。因此本会话只读本地预取，不再 setUrlSource。
 *
 * 抽帧优先级：
 * 1) 已封口的连续文件 → AVImageGenerator + 独立 fd
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
const PREVIEW_MAX_W: number = 160;
const PREVIEW_MAX_H: number = 90;
const PREVIEW_BUCKET_MS: number = 400;
/** dataSrc 抽到未下完的偏移时可能一直等 0 字节，超时后放开队列给下一帧 */
const PREVIEW_FETCH_WATCHDOG_MS: number = 2500;

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

  prepare(url: string, _headers: Record<string, string>, onFrame: (pix: image.PixelMap | undefined) => void): void {
    this.wantUrl = url.trim();
    this.onFrame = onFrame;
    this.ensureAttached();
  }

  request(timeMs: number, videoPxW: number, videoPxH: number, durationMs: number): void {
    // 拖动过程中满载可能刚变得可播，每次请求都尝试挂上本地源。
    this.ensureAttached();
    let ms = Math.max(0, timeMs);
    // 尚未下到的时间点抽帧只会失败；改落到已缓存前缀，小窗至少有画。
    if (this.wantUrl.length > 0 && !isGalleryVideoLanPrefetchComplete()) {
      const cap = galleryVideoLanPrefetchBufferedMs(durationMs);
      if (cap > 0 && ms > cap) {
        ms = cap;
      }
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
      // 半成品 extractor 在封口后必须换完整文件，否则仍按流式解析。
      this.detachSources();
    }
    if (this.fd >= 0 && this.attachedUrl === url) {
      // 正在异步 create generator/extractor，不要重复 open。
      return;
    }
    if (this.tryAttachLocal(url)) {
      hilog.info(DOMAIN, TAG, 'attach local file');
      return;
    }
    if (this.tryAttachPrefetchDataSrc(url)) {
      hilog.info(DOMAIN, TAG, 'attach prefetch dataSrc');
      return;
    }
    // 尚未可播或没有本地缓存时不再打原片 HTTPS，避免和满载下载抢带宽。
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

  /** ImageGenerator 建失败时，完整文件改走 extractor.fdSrc */
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

  /**
   * 边下边播：用独立 fd 的 dataSrc 抽帧。
   * 播放器继续播，抽帧不另开 HTTP，缓存条才能继续涨。
   */
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
      const h = even(Math.max(54, Math.round(PREVIEW_MAX_W / ratio)));
      return { width: even(PREVIEW_MAX_W), height: h };
    }
    const w = even(Math.max(80, Math.round(PREVIEW_MAX_H * ratio)));
    return { width: w, height: even(PREVIEW_MAX_H) };
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
    // 半成品优先关键帧，CLOSEST 可能去解尚未下到的非关键帧
    const query = media.AVImageQueryOptions.AV_IMAGE_QUERY_PREVIOUS_SYNC;
    let job: Promise<image.PixelMap>;
    if (gen !== null) {
      job = gen.fetchFrameByTime(timeUs, query, param);
    } else if (ext !== null) {
      job = ext.fetchFrameByTime(timeUs, query, param);
    } else {
      this.inflight = false;
      return;
    }
    job.then((pix: image.PixelMap): void => {
      if (seq !== this.seq) {
        try {
          pix.release();
        } catch (_e) {
        }
        this.finishPump(seq);
        return;
      }
      this.lastBucket = bucket;
      hilog.info(DOMAIN, TAG, 'frame ok t=%{public}s', `${ms}`);
      const cb = this.onFrame;
      if (cb !== null) {
        cb(pix);
      } else {
        try {
          pix.release();
        } catch (_e) {
        }
      }
      this.finishPump(seq);
    }).catch((error: Error): void => {
      hilog.warn(DOMAIN, TAG, 'fetchFrame fail t=%{public}s err=%{public}s', `${ms}`, `${error}`);
      // 拖动期间满载可能刚好下完，立刻切完整文件再抽一次。
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
          hilog.info(DOMAIN, TAG, 'fallback to completed local file');
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
