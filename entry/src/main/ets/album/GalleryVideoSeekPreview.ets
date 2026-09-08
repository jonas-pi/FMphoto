/**
 * 拖进度条时的小窗预览：从本地预取 mp4 抽帧。
 * AVImageGenerator 只认独立 fdSrc，不能和 AVPlayer 共用同一个文件句柄。
 * 网络 HLS / 尚未可播的半成品文件抽不出帧，调用方仍应展示时间条。
 */
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import {
  getGalleryVideoLanPrefetchPath,
  isGalleryVideoLanPrefetchPlayable,
  openGalleryVideoLanPrefetchPlayFd,
  closeGalleryVideoLanPrefetchFd
} from './GalleryVideoLanPrefetch';

const PREVIEW_MAX_W: number = 160;
const PREVIEW_MAX_H: number = 90;
/** 同一时间桶复用上一帧，拖动时不必每像素都解码 */
const PREVIEW_BUCKET_MS: number = 400;

export class GalleryVideoSeekPreviewSession {
  private generator: media.AVImageGenerator | null = null;
  private fd: number = -1;
  private attachedUrl: string = '';
  private inflight: boolean = false;
  private pendingMs: number = -1;
  private pendingVw: number = 0;
  private pendingVh: number = 0;
  private lastBucket: number = -1;
  private seq: number = 0;
  private onFrame: ((pix: image.PixelMap | undefined) => void) | null = null;

  /** 开始拖动时准备生成器；失败则只靠时间条 */
  prepare(url: string, onFrame: (pix: image.PixelMap | undefined) => void): void {
    this.onFrame = onFrame;
    if (this.generator !== null && this.attachedUrl === url) {
      return;
    }
    this.release();
    this.onFrame = onFrame;
    if (!isGalleryVideoLanPrefetchPlayable(url)) {
      return;
    }
    const path = getGalleryVideoLanPrefetchPath();
    if (path.length === 0) {
      return;
    }
    const fd = openGalleryVideoLanPrefetchPlayFd();
    if (fd < 0) {
      return;
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
      self.pump();
    }).catch((): void => {
      if (self.fd === fd) {
        closeGalleryVideoLanPrefetchFd(fd);
        self.fd = -1;
        self.attachedUrl = '';
      }
    });
  }

  /** 拖动中请求目标时刻预览；进行中的解码只保留最新一次 */
  request(timeMs: number, videoPxW: number, videoPxH: number): void {
    this.pendingMs = Math.max(0, timeMs);
    this.pendingVw = videoPxW;
    this.pendingVh = videoPxH;
    if (this.inflight) {
      return;
    }
    this.pump();
  }

  release(): void {
    this.seq++;
    this.inflight = false;
    this.pendingMs = -1;
    this.lastBucket = -1;
    this.onFrame = null;
    const gen = this.generator;
    this.generator = null;
    this.attachedUrl = '';
    if (gen !== null) {
      gen.release().catch((): void => {});
    }
    if (this.fd >= 0) {
      closeGalleryVideoLanPrefetchFd(this.fd);
      this.fd = -1;
    }
  }

  private previewParam(videoPxW: number, videoPxH: number): media.PixelMapParams {
    const aw = videoPxW > 0 ? videoPxW : 16;
    const ah = videoPxH > 0 ? videoPxH : 9;
    const ratio = aw / ah;
    const boxR = PREVIEW_MAX_W / PREVIEW_MAX_H;
    if (ratio >= boxR) {
      return { width: PREVIEW_MAX_W, height: Math.max(54, Math.round(PREVIEW_MAX_W / ratio)) };
    }
    return { width: Math.max(80, Math.round(PREVIEW_MAX_H * ratio)), height: PREVIEW_MAX_H };
  }

  private pump(): void {
    const gen = this.generator;
    const ms = this.pendingMs;
    if (gen === null || ms < 0) {
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
    const timeUs = ms * 1000;
    const param = this.previewParam(this.pendingVw, this.pendingVh);
    gen.fetchFrameByTime(timeUs, media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC, param)
      .then((pix: image.PixelMap): void => {
        if (seq !== this.seq) {
          try {
            pix.release();
          } catch (_e) {
          }
          this.finishPump(seq);
          return;
        }
        this.lastBucket = bucket;
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
      })
      .catch((): void => {
        this.finishPump(seq);
      });
  }

  private finishPump(seq: number): void {
    if (seq !== this.seq) {
      return;
    }
    this.inflight = false;
    if (this.pendingMs >= 0) {
      this.pump();
    }
  }
}
