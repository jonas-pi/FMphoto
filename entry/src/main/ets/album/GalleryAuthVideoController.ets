import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isGalleryVideoLanPrefetchComplete } from './GalleryVideoLanPrefetch';
import { GalleryVideoSeekPreviewSession } from './GalleryVideoSeekPreview';

const DOMAIN = 0xFF00;
const TAG = 'FMHLS';
const GALLERY_VIDEO_LOAD_WATCHDOG_MS = 12000;
const GALLERY_VIDEO_PLAYBACK_INFO_INTERVAL_MS = 2000;
const GALLERY_VIDEO_SEEK_BUFFER_POLL_MS = 250;
const GALLERY_VIDEO_SEEK_DONE_WATCHDOG_MS = 2500;

export interface GalleryAuthVideoControllerHost {
  isPlaying: boolean;
  currentMs: number;
  durationMs: number;
  videoRebuffering: boolean;
  draggingSeek: boolean;
  userStartedOnce: boolean;
  playbackEnded: boolean;
  videoUrl: string;
  currentQualityLabel(): string;
  setPlaybackFailureHint(msg: string): void;
  syncBufferFromLanCache(): boolean;
  canPlayFromLanCache(): boolean;
  startPlay(): Promise<void>;
  userSeekMode(): media.SeekMode;
  formatMediaErr(e: Error): string;
}

export class GalleryAuthVideoController {
  avPlayer: media.AVPlayer | null = null;
  playGen: number = 0;
  surfaceReady: boolean = false;
  dragStartRatio: number = 0;
  seekInFlight: boolean = false;
  seekPreviewSession: GalleryVideoSeekPreviewSession = new GalleryVideoSeekPreviewSession();
  restartTimerId: number = 0;
  pendingRestoreMs: number = -1;
  pendingQualitySwitch: boolean = false;
  decodeSessionPhotoId: string = '';
  deferPlaybackRateUntilPlaying: boolean = false;
  autoRecoverCount: number = 0;
  lastAvTimeUpdateWallMs: number = 0;
  playbackFalsePositiveGuardUntilMs: number = 0;
  playbackInfoTimerId: number = 0;
  seekBufferPollId: number = 0;
  seekDoneWatchId: number = 0;
  loadWatchdogId: number = 0;
  lastCachedDurationMs: number = 0;
  lastCachedDurationWarnMs: number = 0;
  bufferEndMs: number = 0;
  playingFromPrefetch: boolean = false;
  playingFromLocalFd: boolean = false;
  lanPlayFd: number = -1;
  private host: GalleryAuthVideoControllerHost | null = null;

  bind(host: GalleryAuthVideoControllerHost): void {
    this.host = host;
  }

  private requireHost(): GalleryAuthVideoControllerHost {
    return this.host as GalleryAuthVideoControllerHost;
  }

  stopPlaybackInfoWatch(): void {
    if (this.playbackInfoTimerId === 0) {
      return;
    }
    try {
      clearInterval(this.playbackInfoTimerId);
    } catch (_e) {
    }
    this.playbackInfoTimerId = 0;
  }

  startSeekBufferPoll(): void {
    this.stopSeekBufferPoll();
    this.seekBufferPollId = setInterval((): void => {
      this.requireHost().syncBufferFromLanCache();
    }, GALLERY_VIDEO_SEEK_BUFFER_POLL_MS);
  }

  stopSeekBufferPoll(): void {
    if (this.seekBufferPollId === 0) {
      return;
    }
    try {
      clearInterval(this.seekBufferPollId);
    } catch (_e) {
    }
    this.seekBufferPollId = 0;
  }

  clearSeekDoneWatch(): void {
    if (this.seekDoneWatchId === 0) {
      return;
    }
    try {
      clearTimeout(this.seekDoneWatchId);
    } catch (_e) {
    }
    this.seekDoneWatchId = 0;
  }

  armSeekDoneWatch(): void {
    this.clearSeekDoneWatch();
    this.seekDoneWatchId = setTimeout((): void => {
      this.seekDoneWatchId = 0;
      if (!this.seekInFlight) {
        return;
      }
      hilog.warn(DOMAIN, TAG, 'seekDone timeout pos=%{public}s', `${this.requireHost().currentMs}`);
      this.seekInFlight = false;
    }, GALLERY_VIDEO_SEEK_DONE_WATCHDOG_MS);
  }

  clearLoadWatchdog(): void {
    if (this.loadWatchdogId === 0) {
      return;
    }
    try {
      clearTimeout(this.loadWatchdogId);
    } catch (_e) {
    }
    this.loadWatchdogId = 0;
  }

  armLoadWatchdog(gen: number): void {
    const host = this.requireHost();
    this.clearLoadWatchdog();
    this.loadWatchdogId = setTimeout((): void => {
      this.loadWatchdogId = 0;
      if (gen !== this.playGen || host.isPlaying) {
        return;
      }
      hilog.error(DOMAIN, TAG,
        'load watchdog timeout quality=%{public}s pos=%{public}s cachedMs=%{public}s',
        host.currentQualityLabel(), `${host.currentMs}`, `${this.lastCachedDurationMs}`);
      host.setPlaybackFailureHint('加载超时，请改用较低清晰度后重试');
    }, GALLERY_VIDEO_LOAD_WATCHDOG_MS);
  }

  startPlaybackInfoWatch(player: media.AVPlayer, gen: number): void {
    const host = this.requireHost();
    this.stopPlaybackInfoWatch();
    this.playbackInfoTimerId = setInterval((): void => {
      if (gen !== this.playGen || this.avPlayer !== player) {
        this.stopPlaybackInfoWatch();
        return;
      }
      // 满载缓冲条跟磁盘进度，不要等 getPlaybackInfo 回来才刷新。
      host.syncBufferFromLanCache();
      player.getPlaybackInfo().then((info: media.PlaybackInfo): void => {
        if (gen !== this.playGen || this.avPlayer !== player) {
          return;
        }
        const rate = Number(info[media.PlaybackInfoKey.DOWNLOAD_RATE]);
        const avg = Number(info[media.PlaybackInfoKey.AVG_DOWNLOAD_RATE]);
        hilog.info(DOMAIN, TAG,
          'playbackInfo pos=%{public}s dur=%{public}s cachedMs=%{public}s down=%{public}s avgDown=%{public}s playing=%{public}s rebuffer=%{public}s',
          `${host.currentMs}`, `${host.durationMs}`, `${this.lastCachedDurationMs}`,
          `${rate}`, `${avg}`, `${host.isPlaying}`, `${host.videoRebuffering}`);
        if (host.syncBufferFromLanCache()) {
          return;
        }
      }).catch((e: BusinessError): void => {
        if (gen !== this.playGen) {
          return;
        }
        hilog.warn(DOMAIN, TAG, 'getPlaybackInfo err: %{public}s', host.formatMediaErr(e));
      });
    }, GALLERY_VIDEO_PLAYBACK_INFO_INTERVAL_MS);
  }

  scheduleStartPlay(): void {
    const host = this.requireHost();
    // 拖动期间重建播放器会黑屏并打断边下边播；松手 seek 时若需要再切 fd://。
    if (host.draggingSeek) {
      hilog.info(DOMAIN, TAG, 'defer startPlay while dragging');
      return;
    }
    if (this.restartTimerId !== 0) {
      try {
        clearTimeout(this.restartTimerId);
      } catch (_e) {
      }
      this.restartTimerId = 0;
    }
    this.restartTimerId = setTimeout((): void => {
      this.restartTimerId = 0;
      void host.startPlay();
    }, 30);
  }

  seekByRatio(ratio: number): void {
    const host = this.requireHost();
    const p = this.avPlayer;
    if (p === null || host.durationMs <= 0) {
      return;
    }
    const clamped = Math.max(0, Math.min(1, ratio));
    const toMs = Math.floor(host.durationMs * clamped);
    this.seekInFlight = true;
    // 网络直链上 seek 会再开一条 HTTP；缓存已可播则切到 dataSrc，避免同一条视频拉两次。
    if (!this.playingFromPrefetch && host.canPlayFromLanCache()) {
      this.pendingRestoreMs = toMs;
      host.currentMs = toMs;
      host.userStartedOnce = true;
      host.playbackEnded = false;
      this.scheduleStartPlay();
      return;
    }
    // 缓冲条已满但仍走 dataSrc 时，4K seek 会按流式起播水线再灌数秒；改 fd:// 走本地文件
    if (this.playingFromPrefetch && !this.playingFromLocalFd && isGalleryVideoLanPrefetchComplete()) {
      this.pendingRestoreMs = toMs;
      host.currentMs = toMs;
      host.userStartedOnce = true;
      host.playbackEnded = false;
      this.scheduleStartPlay();
      return;
    }
    try {
      p.seek(toMs, host.userSeekMode());
      host.currentMs = toMs;
      this.armSeekDoneWatch();
    } catch (_e) {
      this.seekInFlight = false;
      this.clearSeekDoneWatch();
    }
  }
}
