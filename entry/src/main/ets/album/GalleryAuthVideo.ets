/**
 * 带图库鉴权的视频播放：Cookie、authx、AccessToken、Referer 与缩略图一致。
 *
 * 关键设计：
 *   1. setMediaSource() 的 Promise resolve 时 state 仍为 idle，
 *      必须等 stateChange 回调触发 'initialized' 才能设置 surfaceId 并调用 prepare。
 *   2. 使用 generation token (playGen) 保证并发安全：
 *      每次 startPlay() 入口同步递增 gen，后续所有异步检查点均比较 gen，
 *      不匹配则说明已被更新的调用取代，直接退出。
 *   3. 进页只展示网格封面，不自动 prepare/play；点击播放后再拉流。
 *      全屏海报会盖住 sharedTransition，封面由预览页 clip 容器承担。
 *   4. 网络缓冲策略必须在 setMediaSource 时一并传入（官方：该接口开始预下载）。
 *      长视频/高码率取 preferredBufferDuration=20；不要把起播水线锁死成 0.3s。
 */
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { audio, AVVolumePanel } from '@kit.AudioKit';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { FnHdsPillButton } from '../common/FnUiCommon';
import {
  GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY,
  setGalleryPreviewToolbarVisible
} from '../pages/galleryPreview/GalleryPreviewToolbarStore';
import {
  GALLERY_PREVIEW_VIDEO_TOGGLE_MUTE_SEQ_KEY,
  GALLERY_PREVIEW_VIDEO_TOGGLE_PLAY_SEQ_KEY,
  restoreGalleryPreviewPortrait,
  setGalleryPreviewVideoActive,
  setGalleryPreviewVideoDockExpanded,
  setGalleryPreviewVideoLandscape,
  setGalleryPreviewVideoMuted,
  setGalleryPreviewVideoPlaying
} from '../pages/galleryPreview/GalleryPreviewVideoStore';
import { FN_SYSTEM_BOTTOM_INSET_VP_KEY } from '../common/FnSystemAvoidArea';
import { GalleryVideoGestureHud } from './GalleryVideoGestureHud';
import { GalleryVideoOverlayChrome } from './GalleryVideoOverlayChrome';

const DOMAIN = 0xFF00;
const TAG = 'GalleryAuthVideo';
const LONG_PRESS_RATE = 2.0;
const GALLERY_VIDEO_ADJUST_HUD_HIDE_MS = 3000;
/** 播放中无操作时收起顶底栏与浮层控件 */
const GALLERY_VIDEO_CHROME_AUTOHIDE_MS = 2500;
const GALLERY_VIDEO_VOLUME_MAX_FALLBACK = 15;
/** 滑过屏高约 1/3 即走完全量程，避免按整屏换算发闷 */
const GALLERY_VIDEO_ADJUST_TRAVEL_RATIO: number = 0.32;
/**
 * 官方 PlaybackStrategy.preferredBufferDuration：单位秒，缓冲区大小 ≈ 该值 MB，范围 [1, 20]。
 * 片源超过 20MB（长视频/高清原片几乎都超过）时应取最大值，否则卡顿率显著升高。
 */
const GALLERY_VIDEO_PREFERRED_BUFFER_DURATION_SEC = 20;
/**
 * 起播水线必须能被 20MB 缓冲区装下，否则 prepare 会一直等（4K 原片 3s 约 30MB+，永远达不到）。
 * 高码率直链取短水线快起播；转码 HLS 略长一点等分片。
 */
const GALLERY_VIDEO_START_BUFFER_DIRECT_SEC = 0.6;
const GALLERY_VIDEO_START_BUFFER_TRANSCODE_SEC = 0.8;
/** 短边超过该值视为超高清，默认走 1080p 转码而不是原始直链 */
const GALLERY_VIDEO_UHD_MIN_P = 1440;
/** prepared 之后若迟迟进不了 playing，视为拉流卡住 */
const GALLERY_VIDEO_LOAD_WATCHDOG_MS = 12000;
/** 清晰度切换后先起播，进度超过该值再 seek，避免在未缓存位置卡死 */
const GALLERY_VIDEO_DEFER_SEEK_MIN_MS = 800;
/** getPlaybackInfo 最短统计周期 500ms；诊断日志用 2s，避免刷屏 */
const GALLERY_VIDEO_PLAYBACK_INFO_INTERVAL_MS = 2000;
/** CACHED_DURATION 低于该值时打告警（毫秒） */
const GALLERY_VIDEO_CACHED_DURATION_WARN_MS = 2000;

interface QualityOption {
  label: string;
  resolution: string;
  bitrate: number;
  /** true 表示走原始直链（/stream/v/{id}），不走 decode/play */
  directStream: boolean;
}

const QUALITY_OPTIONS: QualityOption[] = [
  { label: '原始', resolution: '1080', bitrate: 8000000, directStream: true },
  // 转码码率按可流畅起播来取；30Mbps 的 1080p 转码和 4K 原片一样重，NAS 出片极慢。
  { label: '高清 1080p', resolution: '1080', bitrate: 8000000, directStream: false },
  { label: '均衡 720p', resolution: '720', bitrate: 4000000, directStream: false },
  { label: '流畅 480p', resolution: '480', bitrate: 2000000, directStream: false }
];
/**
 * 全局记忆的视频倍速：
 * - 进入下一个视频时沿用最近一次手动选择的倍速；
 * - 默认值仍为 1.0x；
 * - 使用 static 让同一进程内所有预览页实例共享该值。
 */
let LAST_VIDEO_SPEED_RATE = 1.0;
/** 全局记忆清晰度档位索引，切换到下一个视频时沿用 */
let LAST_VIDEO_QUALITY_INDEX = 0;

@Component
export struct GalleryAuthVideo {
  @Prop @Watch('onUrlChange') videoUrl: string = '';
  /** 当前是否为 Swiper 可见页；不可见时暂停以避免后台串音 */
  @Prop @Watch('onActiveChanged') active: boolean = true;
  /** 底部额外安全间距，由父页面传入以避开底部工具栏 */
  @Prop bottomPadding: number = 0;
  /** 预览顶底栏显隐：本地订阅，避免父页因 padding 变化重绘全部 slide */
  @StorageProp(GALLERY_PREVIEW_TOOLBAR_VISIBLE_KEY) private previewToolbarVisible: boolean = true;
  @StorageProp(FN_SYSTEM_BOTTOM_INSET_VP_KEY) private systemBottomInsetVp: number = 0;
  /** 当前视频允许的最大清晰度（p），由上游按原始分辨率估算传入 */
  @Prop maxResolutionP: number = 1080;
  /** 幻灯片等场景需要进页即起播；普通预览保持封面等待点击 */
  @Prop autoStart: boolean = false;
  /** 详情半模态展开时，单击剩余区优先收起详情，不切工具栏 */
  @Prop detailsShowing: boolean = false;
  onDetailsTapDismiss: () => void = () => {};
  /** 自动起播且自然播到片尾（或失败无法继续）时回调，幻灯片用来切下一张 */
  onAutoplayEnded: () => void = () => {};
  /** 同一支播放只通知一次，避免 completed/error 连跳两张 */
  private autoplayEndedNotified: boolean = false;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  /** 仅在用户点击播放（或幻灯片自动起播）后转圈 */
  @State private videoLoading: boolean = false;
  /** 播放中缓冲耗尽（BUFFERING_START）：转圈但不藏控件，避免被当成“播不下去” */
  @State private videoRebuffering: boolean = false;
  /** 已进入 playing：才揭开 Surface，避免封面与首帧跳变 */
  @State private videoSurfaceVisible: boolean = false;
  @State private hint: string = '';
  @State private isDarkTheme: boolean = false;
  /** 播放链路失败时可手动重试（与「清晰度超限」等提示区分） */
  @State private showPlaybackRetry: boolean = false;
  @State @Watch('onPlaybackChromeChanged') private isPlaying: boolean = false;
  @State private userStartedOnce: boolean = false;
  @State private playbackEnded: boolean = false;
  @State @Watch('onPlaybackChromeChanged') private muted: boolean = false;
  @State private landscape: boolean = false;
  @StorageProp(GALLERY_PREVIEW_VIDEO_TOGGLE_PLAY_SEQ_KEY) @Watch('onTogglePlayCmd')
    private togglePlaySeq: number = 0;
  @StorageProp(GALLERY_PREVIEW_VIDEO_TOGGLE_MUTE_SEQ_KEY) @Watch('onToggleMuteCmd')
    private toggleMuteSeq: number = 0;
  private lastTogglePlaySeq: number = 0;
  private lastToggleMuteSeq: number = 0;
  @State private currentMs: number = 0;
  @State private durationMs: number = 0;
  @State private dragRatio: number = 0;
  @State private draggingSeek: boolean = false;
  /** 初值读全局记忆，避免 LazyForEach 新实例首帧仍画 1.0x/原始 再闪一下 */
  @State private speedRate: number = LAST_VIDEO_SPEED_RATE;
  @State private qualityIndex: number = LAST_VIDEO_QUALITY_INDEX;
  @State private longPressSpeeding: boolean = false;
  @State private viewW: number = 360;
  @State private viewH: number = 780;
  @State private adjustHudVisible: boolean = false;
  @State private adjustIsBrightness: boolean = true;
  @State private screenBrightness: number = 0.5;
  @State private mediaVolume: number = 5;
  @State private mediaVolumeMax: number = GALLERY_VIDEO_VOLUME_MAX_FALLBACK;

  private xController: XComponentController = new XComponentController();
  private avPlayer: media.AVPlayer | null = null;
  private playGen: number = 0;
  private surfaceReady: boolean = false;
  private dragStartRatio: number = 0;
  private wasPlayingBeforeSeek: boolean = false;
  private seekResumePending: boolean = false;
  /** 合并短时间内的重复重建请求，避免 onLoad/onUrlChange 叠加触发两次拉流 */
  private restartTimerId: number = 0;
  /** 清晰度切换时记忆的目标进度（毫秒）；-1 表示无待恢复进度 */
  private pendingRestoreMs: number = -1;
  /** 是否存在进行中的清晰度切换（用于在 playing 时给出成功提示） */
  private pendingQualitySwitch: boolean = false;
  /**
   * 当前已通过 decode/play 建立的服务器转码会话对应的相册 photoId。
   * 切视频 / 切清晰度 / 离屏前须 POST decode/quit，避免会话残留导致下一次播放失败。
   */
  private decodeSessionPhotoId: string = '';
  /**
   * 转码流 + 非 1 倍速时，若在 prepared 阶段就 setSpeed，部分机型上易 prepare/play 失败或声画不同步；
   * 先以 1.0 起播，进入 playing 后再套用记忆倍速。
   */
  private deferPlaybackRateUntilPlaying: boolean = false;
  /** 转码播放异常自动自愈次数（每个视频最多一次） */
  private autoRecoverCount: number = 0;
  /** 最近一次 timeUpdate 墙钟时间；报错时若进度仍在刷新，多为 HLS+高倍速下的误信号 */
  private lastAvTimeUpdateWallMs: number = 0;
  /**
   * 在此时间之前，对「播放失败」类回调采取更宽松过滤（转码起播后套 1.75x 等组合易抖动）。
   * 每次新起播在 startPlay 入口清零，仅在 arm… 时写入。
   */
  private playbackFalsePositiveGuardUntilMs: number = 0;
  private adjustBrightnessBase: number = 0.5;
  private adjustVolumeBase: number = 5;
  private savedWindowBrightness: number = -1;
  private windowBrightnessDirty: boolean = false;
  private adjustHudHideTimer: number = 0;
  private chromeHideTimer: number = 0;
  /** 周期性拉取下载速率，用来对照“只播前几秒”是否因拉流停滞 */
  private playbackInfoTimerId: number = 0;
  /** prepare/play 卡住时给出重试，避免无限转圈 */
  private loadWatchdogId: number = 0;
  /** 最近一次 CACHED_DURATION（毫秒），供停滞诊断 */
  private lastCachedDurationMs: number = 0;
  private lastCachedDurationWarnMs: number = 0;

  /** 视频 Surface 跟随深浅色，避免浅色模式铺白、深色模式铺黑不一致 */
  private surfaceBackgroundColor(): ResourceColor {
    return this.isDarkTheme ? Color.Black : Color.White;
  }

  /** 未起播时保持透明，让下层/本层封面参与 sharedTransition 且不跳变 */
  private hostBackgroundColor(): ResourceColor {
    return this.videoSurfaceVisible ? this.surfaceBackgroundColor() : Color.Transparent;
  }

  private finishVideoLoading(): void {
    if (!this.videoLoading) {
      return;
    }
    this.videoLoading = false;
  }

  private static formatMediaErr(e: Error): string {
    const be = e as BusinessError;
    if (be.code !== undefined) {
      return `code=${be.code} msg=${be.message}`;
    }
    return String(e);
  }

  private static sanitizeUrlForLog(url: string): string {
    const s = url.trim();
    if (s.length === 0) {
      return '';
    }
    const q = s.indexOf('?');
    const noQuery = q >= 0 ? s.substring(0, q) : s;
    if (noQuery.length <= 160) {
      return noQuery;
    }
    return `${noQuery.substring(0, 80)}...${noQuery.substring(noQuery.length - 48)}`;
  }

  private static isHlsUrl(url: string): boolean {
    const lower = url.toLowerCase();
    return lower.indexOf('.m3u8') >= 0;
  }

  private buildPlaybackStrategy(directStream: boolean): media.PlaybackStrategy {
    const startSec = directStream
      ? GALLERY_VIDEO_START_BUFFER_DIRECT_SEC
      : GALLERY_VIDEO_START_BUFFER_TRANSCODE_SEC;
    const strategy: media.PlaybackStrategy = {
      showFirstFrameOnPrepare: true,
      preferredBufferDuration: GALLERY_VIDEO_PREFERRED_BUFFER_DURATION_SEC,
      preferredBufferDurationForPlaying: startSec
    };
    return strategy;
  }

  private stopPlaybackInfoWatch(): void {
    if (this.playbackInfoTimerId === 0) {
      return;
    }
    try {
      clearInterval(this.playbackInfoTimerId);
    } catch (_e) {
    }
    this.playbackInfoTimerId = 0;
  }

  private clearLoadWatchdog(): void {
    if (this.loadWatchdogId === 0) {
      return;
    }
    try {
      clearTimeout(this.loadWatchdogId);
    } catch (_e) {
    }
    this.loadWatchdogId = 0;
  }

  private armLoadWatchdog(gen: number): void {
    this.clearLoadWatchdog();
    this.loadWatchdogId = setTimeout((): void => {
      this.loadWatchdogId = 0;
      if (gen !== this.playGen || this.isPlaying) {
        return;
      }
      hilog.error(DOMAIN, TAG,
        'load watchdog timeout quality=%{public}s pos=%{public}s cachedMs=%{public}s',
        this.currentQualityLabel(), `${this.currentMs}`, `${this.lastCachedDurationMs}`);
      this.setPlaybackFailureHint('加载超时，请改用较低清晰度后重试');
    }, GALLERY_VIDEO_LOAD_WATCHDOG_MS);
  }

  /**
   * 4K/2.7K 原片 20MB 缓冲只够几秒，默认改走 1080p 转码。
   * 不写 LAST_VIDEO_QUALITY_INDEX：用户在菜单里选「原始」仍然生效。
   */
  private preferTranscodeForUhd(): void {
    if (this.maxResolutionP < GALLERY_VIDEO_UHD_MIN_P) {
      return;
    }
    if (this.qualityIndex !== 0) {
      return;
    }
    if (this.isQualityAllowed(1)) {
      hilog.info(DOMAIN, TAG, 'UHD %{public}sp 默认改用 1080p 转码', `${this.maxResolutionP}`);
      this.qualityIndex = 1;
    }
  }

  private startPlaybackInfoWatch(player: media.AVPlayer, gen: number): void {
    this.stopPlaybackInfoWatch();
    this.playbackInfoTimerId = setInterval((): void => {
      if (gen !== this.playGen || this.avPlayer !== player) {
        this.stopPlaybackInfoWatch();
        return;
      }
      player.getPlaybackInfo().then((info: media.PlaybackInfo): void => {
        if (gen !== this.playGen || this.avPlayer !== player) {
          return;
        }
        const rate = Number(info[media.PlaybackInfoKey.DOWNLOAD_RATE]);
        const avg = Number(info[media.PlaybackInfoKey.AVG_DOWNLOAD_RATE]);
        hilog.info(DOMAIN, TAG,
          'playbackInfo pos=%{public}s dur=%{public}s cachedMs=%{public}s down=%{public}s avgDown=%{public}s playing=%{public}s rebuffer=%{public}s',
          `${this.currentMs}`, `${this.durationMs}`, `${this.lastCachedDurationMs}`,
          `${rate}`, `${avg}`, `${this.isPlaying}`, `${this.videoRebuffering}`);
        if (this.isPlaying && this.lastCachedDurationMs >= 0 &&
          this.lastCachedDurationMs < GALLERY_VIDEO_CACHED_DURATION_WARN_MS &&
          Number.isFinite(rate) && rate <= 0) {
          hilog.warn(DOMAIN, TAG,
            '疑似拉流停滞：播放中 cachedMs=%{public}s downloadRate=%{public}s pos=%{public}s',
            `${this.lastCachedDurationMs}`, `${rate}`, `${this.currentMs}`);
        }
      }).catch((e: BusinessError): void => {
        if (gen !== this.playGen) {
          return;
        }
        hilog.warn(DOMAIN, TAG, 'getPlaybackInfo err: %{public}s', GalleryAuthVideo.formatMediaErr(e));
      });
    }, GALLERY_VIDEO_PLAYBACK_INFO_INTERVAL_MS);
  }

  /** 幻灯片：进页即视为用户已点播放 */
  private applyAutoStartIfNeeded(): void {
    if (!this.autoStart || !this.active || this.videoUrl.length === 0) {
      return;
    }
    this.userStartedOnce = true;
    this.videoLoading = true;
  }

  private notifyAutoplayEndedIfNeeded(): void {
    if (this.autoplayEndedNotified || !this.active || !this.autoStart) {
      return;
    }
    this.autoplayEndedNotified = true;
    this.onAutoplayEnded();
  }

  /** 尚无播放器时，点击播放才创建并拉流 */
  private beginPlaybackFromUser(): void {
    this.userStartedOnce = true;
    this.playbackEnded = false;
    this.videoLoading = true;
    this.showPlaybackRetry = false;
    this.hint = '';
    this.onPlaybackChromeChanged();
    this.scheduleStartPlay();
  }

  private loadingSpinnerColor(): ResourceColor {
    return this.isDarkTheme ? Color.White : '#5B6675';
  }

  private loadingHintColor(): ResourceColor {
    return this.isDarkTheme ? '#CCCCCC' : '#5B6675';
  }

  private controlPrimaryTextColor(): ResourceColor {
    return $r('app.color.button_secondary_fg');
  }

  private effectiveBottomPadding(): number {
    if (this.previewToolbarVisible) {
      return this.bottomPadding;
    }
    return Math.max(0, this.systemBottomInsetVp);
  }

  private hintTextColor(): ResourceColor {
    return this.isDarkTheme ? '#CCCCCC' : '#5B6675';
  }

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
  }

  /** 非原始档位必须 <= 原始清晰度；原始直链始终允许选择 */
  private isQualityAllowed(idx: number): boolean {
    if (idx < 0 || idx >= QUALITY_OPTIONS.length) {
      return false;
    }
    const q = QUALITY_OPTIONS[idx];
    if (q.directStream) {
      return true;
    }
    const maxP = Math.max(1, Math.floor(this.maxResolutionP));
    return Number(q.resolution) <= maxP;
  }

  /**
   * 当前条目分辨率下，把本页 qualityIndex 夹到合法档位。
   * 注意：切勿写 LAST_VIDEO_QUALITY_INDEX——那是用户「偏好」，仅应在菜单里手选时更新；
   * 若在此处因低分辨率视频回退到 0 也同步全局，滑回高分辨率视频后会永久变成「原始」。
   */
  private normalizeQualityIndex(): void {
    if (this.isQualityAllowed(this.qualityIndex)) {
      return;
    }
    if (this.isQualityAllowed(0)) {
      this.qualityIndex = 0;
      return;
    }
    for (let i = QUALITY_OPTIONS.length - 1; i >= 0; i--) {
      if (this.isQualityAllowed(i)) {
        this.qualityIndex = i;
        return;
      }
    }
    this.qualityIndex = 0;
  }

  onUrlChange(): void {
    this.playGen++;
    this.isPlaying = false;
    this.userStartedOnce = false;
    this.autoplayEndedNotified = false;
    this.playbackEnded = false;
    this.currentMs = 0;
    this.durationMs = 0;
    this.draggingSeek = false;
    this.dragRatio = 0;
    this.wasPlayingBeforeSeek = false;
    this.seekResumePending = false;
    // 切换到下一个视频时保留用户最近一次选择的倍速，不再重置为 1.0x。
    this.speedRate = LAST_VIDEO_SPEED_RATE;
    // 切换到下一个视频时保留上次选择的清晰度档位。
    this.qualityIndex = LAST_VIDEO_QUALITY_INDEX;
    this.normalizeQualityIndex();
    this.preferTranscodeForUhd();
    this.longPressSpeeding = false;
    this.hint = '';
    this.showPlaybackRetry = false;
    this.pendingQualitySwitch = false;
    this.autoRecoverCount = 0;
    this.lastAvTimeUpdateWallMs = 0;
    this.playbackFalsePositiveGuardUntilMs = 0;
    this.videoSurfaceVisible = false;
    this.videoLoading = false;
    this.videoRebuffering = false;
    this.stopPlaybackInfoWatch();
    this.clearLoadWatchdog();
    this.clearChromeAutoHideTimer();
    this.applyAutoStartIfNeeded();
    if (this.userStartedOnce) {
      this.scheduleStartPlay();
    }
  }

  /**
   * 组件首次创建时，@Watch('onUrlChange') 可能不会在首帧前触发，
   * 导致按钮文案短暂显示默认值（1.00x / 原始）。
   * 这里在首次出现时主动同步全局记忆，确保切到下一视频时“显示即记忆值”。
   */
  aboutToAppear(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.speedRate = LAST_VIDEO_SPEED_RATE;
    this.qualityIndex = LAST_VIDEO_QUALITY_INDEX;
    this.normalizeQualityIndex();
    this.preferTranscodeForUhd();
    this.autoRecoverCount = 0;
    this.showPlaybackRetry = false;
    this.lastTogglePlaySeq = this.togglePlaySeq;
    this.lastToggleMuteSeq = this.toggleMuteSeq;
    this.videoLoading = false;
    this.videoRebuffering = false;
    this.videoSurfaceVisible = false;
    this.autoplayEndedNotified = false;
    this.applyAutoStartIfNeeded();
    this.onPlaybackChromeChanged();
    void this.initWindowBrightness();
    void this.initMediaVolume();
  }

  onPlaybackChromeChanged(): void {
    if (!this.active) {
      return;
    }
    setGalleryPreviewVideoActive(true);
    setGalleryPreviewVideoPlaying(this.isPlaying);
    setGalleryPreviewVideoMuted(this.muted);
    setGalleryPreviewVideoDockExpanded(this.userStartedOnce && !this.playbackEnded);
    this.bumpChromeAutoHide();
  }

  onTogglePlayCmd(): void {
    if (this.togglePlaySeq === this.lastTogglePlaySeq) {
      return;
    }
    this.lastTogglePlaySeq = this.togglePlaySeq;
    if (this.active) {
      void this.togglePlayPause();
    }
  }

  onToggleMuteCmd(): void {
    if (this.toggleMuteSeq === this.lastToggleMuteSeq) {
      return;
    }
    this.lastToggleMuteSeq = this.toggleMuteSeq;
    if (this.active) {
      this.toggleMute();
    }
  }

  onActiveChanged(): void {
    const p = this.avPlayer;
    if (!this.active) {
      this.videoLoading = false;
      this.videoRebuffering = false;
      this.isPlaying = false;
      this.adjustHudVisible = false;
      this.autoplayEndedNotified = false;
      setGalleryPreviewVideoActive(false);
      setGalleryPreviewVideoPlaying(false);
      setGalleryPreviewVideoDockExpanded(false);
      this.clearChromeAutoHideTimer();
      void this.restoreWindowBrightness();
      if (this.landscape) {
        this.landscape = false;
        void restoreGalleryPreviewPortrait(this.getUIContext());
      }
      if (p !== null) {
        p.pause().catch((): void => {});
      }
      return;
    }
    // 滑到本页时再按 autoStart 起播，避免相邻页预创建时把 userStartedOnce 提前置位
    this.applyAutoStartIfNeeded();
    this.onPlaybackChromeChanged();
    // 恢复到可见页：优先续播已有实例；没有实例则按正常链路重建
    if (this.videoUrl.length === 0) {
      return;
    }
    if (p !== null) {
      if (this.userStartedOnce && !this.playbackEnded) {
        p.play().catch((): void => {});
      }
      return;
    }
    if (this.surfaceReady && this.userStartedOnce) {
      this.videoLoading = true;
      this.scheduleStartPlay();
    }
  }

  aboutToDisappear(): void {
    this.playGen++;
    this.stopPlaybackInfoWatch();
    this.clearLoadWatchdog();
    this.clearAdjustHudHideTimer();
    this.clearChromeAutoHideTimer();
    void this.restoreWindowBrightness();
    if (this.active) {
      setGalleryPreviewVideoActive(false);
      setGalleryPreviewVideoPlaying(false);
      if (this.landscape) {
        this.landscape = false;
        void restoreGalleryPreviewPortrait(this.getUIContext());
      }
    }
    if (this.restartTimerId !== 0) {
      try {
        clearTimeout(this.restartTimerId);
      } catch (_e) {
      }
      this.restartTimerId = 0;
    }
    const pid = this.decodeSessionPhotoId;
    this.decodeSessionPhotoId = '';
    if (pid.length > 0) {
      const c = AppSession.getClient();
      if (c !== null) {
        void c.requestVideoDecodeQuit(pid, 8000);
      }
    }
    const p = this.avPlayer;
    this.avPlayer = null;
    GalleryAuthVideo.safeRelease(p);
  }

  /**
   * 合并触发播放重建：
   * - 切清晰度时可能同时命中多个生命周期回调；
   * - 统一延后到一个 tick 执行，可避免重复 setMediaSource / release，
   *   从而减少服务端看到的重复 quit 与 stream/v 请求。
   */
  private scheduleStartPlay(): void {
    if (this.restartTimerId !== 0) {
      try {
        clearTimeout(this.restartTimerId);
      } catch (_e) {
      }
      this.restartTimerId = 0;
    }
    this.restartTimerId = setTimeout((): void => {
      this.restartTimerId = 0;
      void this.startPlay();
    }, 30);
  }

  private static unbindPlayerListeners(p: media.AVPlayer): void {
    try {
      p.off('error');
    } catch (_e) {
    }
    try {
      p.off('timeUpdate');
    } catch (_e) {
    }
    try {
      p.off('durationUpdate');
    } catch (_e) {
    }
    try {
      p.off('seekDone');
    } catch (_e) {
    }
    try {
      p.off('stateChange');
    } catch (_e) {
    }
    try {
      p.off('bufferingUpdate');
    } catch (_e) {
    }
  }

  private static safeRelease(p: media.AVPlayer | null): void {
    if (p === null) { return; }
    GalleryAuthVideo.unbindPlayerListeners(p);
    p.release().catch((): void => {});
  }

  private progressRatio(): number {
    if (this.draggingSeek) {
      return this.dragRatio;
    }
    if (this.durationMs <= 0) {
      return 0;
    }
    const r = this.currentMs / this.durationMs;
    return Math.max(0, Math.min(1, r));
  }

  private fmtTime(ms: number): string {
    const sec = Math.max(0, Math.floor(ms / 1000));
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    const mm = m < 10 ? `0${m}` : `${m}`;
    const ss = s < 10 ? `0${s}` : `${s}`;
    return `${mm}:${ss}`;
  }

  private speedBadgeText(): string {
    if (this.longPressSpeeding) {
      return '2.0X';
    }
    const r = this.speedRate;
    if (Math.abs(r - 0.25) < 0.01) {
      return '0.25X';
    }
    if (Math.abs(r - 0.5) < 0.01) {
      return '0.5X';
    }
    if (Math.abs(r - 1.5) < 0.01) {
      return '1.5X';
    }
    return `${r.toFixed(1)}X`;
  }

  /**
   * 与时间轴/失败过滤相关的「当前生效倍速」：
   * 长按快进时底层实际为 2.0x，若仍按记忆的 speedRate（如 1.75）算「多久该有一次 timeUpdate」会系统性偏差，
   * 进而把正常播放当成「进度停滞」或放大误报。
   */
  private effectivePlaybackRateForTiming(): number {
    return this.longPressSpeeding ? LONG_PRESS_RATE : this.speedRate;
  }

  /**
   * 自然播放到片尾（state=completed）：高倍速时最后几百毫秒往往不再派发 timeUpdate，
   * UI 会停在「差一点没满条」；此处用播放器时长把进度拉到终点。
   */
  private syncUiProgressToNaturalEnd(player: media.AVPlayer): void {
    try {
      const pd = player.duration;
      if (pd > 0) {
        this.durationMs = Math.max(this.durationMs, pd);
        this.currentMs = Math.max(this.currentMs, pd);
      } else if (this.durationMs > 0) {
        this.currentMs = this.durationMs;
      }
    } catch (_e) {
      if (this.durationMs > 0) {
        this.currentMs = this.durationMs;
      }
    }
  }

  /**
   * 与图片预览一致：完整显示（Contain）。
   * 横视频优先贴合屏幕宽度，超高竖视频优先贴合屏幕高度，不做裁切。
   */
  private applyContainMode(player: media.AVPlayer): void {
    player.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT;
  }

  private applySpeed(player: media.AVPlayer, rate: number): void {
    /**
     * 倍速稳定性优先：
     * - 优先使用系统枚举 setSpeed（播放器底层对 A/V 同步更稳定）；
     * - 仅在 setSpeed 不可用时回退 setPlaybackRate。
     */
    try {
      if (Math.abs(rate - 0.25) < 0.01) {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_0_25_X);
      } else if (Math.abs(rate - 0.5) < 0.01) {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_0_50_X);
      } else if (Math.abs(rate - 1.0) < 0.01) {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_00_X);
      } else if (Math.abs(rate - 1.5) < 0.01) {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_50_X);
      } else if (Math.abs(rate - 2.0) < 0.01) {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_2_00_X);
      } else if (rate <= 0.75) {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_0_75_X);
      } else if (rate <= 1.25) {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_25_X);
      } else if (rate <= 1.75) {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_75_X);
      } else {
        player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_2_00_X);
      }
    } catch (_e) {
      try {
        player.setPlaybackRate(rate);
      } catch (_e2) {
      }
    }
  }

  private applyPlayerMute(player: media.AVPlayer): void {
    try {
      player.setVolume(this.muted ? 0 : 1);
    } catch (_e) {
    }
  }

  private toggleMute(): void {
    this.muted = !this.muted;
    const p = this.avPlayer;
    if (p !== null) {
      this.applyPlayerMute(p);
    }
  }

  private async toggleLandscape(): Promise<void> {
    const win = await this.resolveHostWindow();
    if (win === undefined) {
      return;
    }
    const next = !this.landscape;
    try {
      await win.setPreferredOrientation(
        next ? window.Orientation.USER_ROTATION_LANDSCAPE : window.Orientation.PORTRAIT
      );
      this.landscape = next;
      setGalleryPreviewVideoLandscape(next);
    } catch (_e) {
    }
  }

  private showCenterPlay(): boolean {
    return !this.isPlaying && (!this.userStartedOnce || this.playbackEnded);
  }

  private shouldResumePlayback(): boolean {
    return this.active && this.userStartedOnce && !this.playbackEnded;
  }

  private async togglePlayPause(): Promise<void> {
    const p = this.avPlayer;
    if (p === null) {
      this.beginPlaybackFromUser();
      return;
    }
    try {
      if (this.isPlaying) {
        this.isPlaying = false;
        this.videoRebuffering = false;
        this.clearChromeAutoHideTimer();
        setGalleryPreviewToolbarVisible(true);
        await p.pause();
        return;
      }
      this.userStartedOnce = true;
      this.playbackEnded = false;
      this.onPlaybackChromeChanged();
      this.isPlaying = true;
      this.scheduleChromeAutoHide();
      if (this.durationMs > 0 && this.currentMs >= this.durationMs - 400) {
        try {
          p.seek(0, media.SeekMode.SEEK_CLOSEST);
          this.currentMs = 0;
        } catch (_e) {
        }
      }
      await p.play();
    } catch (_e) {
    }
  }

  private clampAdjust(value: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, value));
  }

  private clearAdjustHudHideTimer(): void {
    if (this.adjustHudHideTimer === 0) {
      return;
    }
    try {
      clearTimeout(this.adjustHudHideTimer);
    } catch (_e) {
    }
    this.adjustHudHideTimer = 0;
  }

  private scheduleHideAdjustHud(): void {
    this.clearAdjustHudHideTimer();
    this.adjustHudHideTimer = setTimeout((): void => {
      this.adjustHudHideTimer = 0;
      this.adjustHudVisible = false;
    }, GALLERY_VIDEO_ADJUST_HUD_HIDE_MS);
  }

  private clearChromeAutoHideTimer(): void {
    if (this.chromeHideTimer === 0) {
      return;
    }
    try {
      clearTimeout(this.chromeHideTimer);
    } catch (_e) {
    }
    this.chromeHideTimer = 0;
  }

  /** 播放中无操作则收起顶底栏与浮层；暂停/结束保持显示 */
  private scheduleChromeAutoHide(): void {
    this.clearChromeAutoHideTimer();
    if (!this.active || !this.isPlaying) {
      return;
    }
    this.chromeHideTimer = setTimeout((): void => {
      this.chromeHideTimer = 0;
      if (this.active && this.isPlaying) {
        setGalleryPreviewToolbarVisible(false);
      }
    }, GALLERY_VIDEO_CHROME_AUTOHIDE_MS);
  }

  private bumpChromeAutoHide(): void {
    if (this.active && this.isPlaying) {
      this.scheduleChromeAutoHide();
    }
  }

  private revealPlaybackChrome(): void {
    this.clearChromeAutoHideTimer();
    setGalleryPreviewToolbarVisible(true);
  }

  private async resolveHostWindow(): Promise<window.Window | undefined> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      return await window.getLastWindow(ctx);
    } catch (_e) {
      return undefined;
    }
  }

  private async initWindowBrightness(): Promise<void> {
    const win = await this.resolveHostWindow();
    if (win === undefined) {
      return;
    }
    try {
      const raw = win.getWindowProperties().brightness;
      if (Number.isFinite(raw) && raw >= 0 && raw <= 1) {
        this.savedWindowBrightness = raw;
        this.screenBrightness = raw;
      } else {
        this.savedWindowBrightness = -1;
        this.screenBrightness = 0.5;
      }
    } catch (_e) {
    }
  }

  private async applyWindowBrightness(value: number): Promise<void> {
    const win = await this.resolveHostWindow();
    if (win === undefined) {
      return;
    }
    try {
      await win.setWindowBrightness(this.clampAdjust(value, 0, 1));
      this.windowBrightnessDirty = true;
    } catch (_e) {
    }
  }

  private async restoreWindowBrightness(): Promise<void> {
    if (!this.windowBrightnessDirty) {
      return;
    }
    const win = await this.resolveHostWindow();
    if (win === undefined) {
      return;
    }
    try {
      await win.setWindowBrightness(this.savedWindowBrightness);
      this.windowBrightnessDirty = false;
    } catch (_e) {
    }
  }

  private async initMediaVolume(): Promise<void> {
    try {
      const volumeManager = audio.getAudioManager().getVolumeManager();
      const maxV = await volumeManager.getMaxVolumeByStream(audio.StreamUsage.STREAM_USAGE_MOVIE);
      if (Number.isFinite(maxV) && maxV > 0) {
        this.mediaVolumeMax = maxV;
      }
      const cur = await volumeManager.getVolumeByStream(audio.StreamUsage.STREAM_USAGE_MOVIE);
      if (Number.isFinite(cur)) {
        this.mediaVolume = this.clampAdjust(cur, 0, this.mediaVolumeMax);
      }
    } catch (_e) {
    }
  }

  private onVideoSingleTap(): void {
    if (this.detailsShowing) {
      this.onDetailsTapDismiss();
      return;
    }
    const showing = this.previewToolbarVisible;
    setGalleryPreviewToolbarVisible(!showing);
    if (!showing && this.isPlaying) {
      this.scheduleChromeAutoHide();
      return;
    }
    this.clearChromeAutoHideTimer();
  }

  private beginVerticalAdjust(event: GestureEvent): void {
    if (this.draggingSeek || this.longPressSpeeding) {
      return;
    }
    const fl = event.fingerList;
    if (fl === undefined || fl.length < 1) {
      return;
    }
    this.clearAdjustHudHideTimer();
    this.clearChromeAutoHideTimer();
    this.adjustBrightnessBase = this.screenBrightness;
    this.adjustVolumeBase = this.mediaVolume;
    this.adjustIsBrightness = fl[0].localX < this.viewW * 0.5;
    this.adjustHudVisible = true;
    if (!this.adjustIsBrightness && this.muted) {
      this.muted = false;
      const p = this.avPlayer;
      if (p !== null) {
        this.applyPlayerMute(p);
      }
    }
  }

  private updateVerticalAdjust(event: GestureEvent): void {
    if (!this.adjustHudVisible || this.draggingSeek) {
      return;
    }
    const travel = Math.max(1, this.viewH * GALLERY_VIDEO_ADJUST_TRAVEL_RATIO);
    const delta = event.offsetY / travel;
    if (this.adjustIsBrightness) {
      const next = this.clampAdjust(this.adjustBrightnessBase - delta, 0, 1);
      this.screenBrightness = next;
      void this.applyWindowBrightness(next);
      return;
    }
    const nextVol = this.clampAdjust(
      this.adjustVolumeBase - delta * this.mediaVolumeMax,
      0,
      this.mediaVolumeMax
    );
    this.mediaVolume = nextVol;
  }

  private endVerticalAdjust(): void {
    if (!this.adjustHudVisible) {
      return;
    }
    this.scheduleHideAdjustHud();
    this.bumpChromeAutoHide();
  }

  private seekByRatio(ratio: number): void {
    const p = this.avPlayer;
    if (p === null || this.durationMs <= 0) {
      return;
    }
    const clamped = Math.max(0, Math.min(1, ratio));
    const toMs = Math.floor(this.durationMs * clamped);
    try {
      p.seek(toMs, media.SeekMode.SEEK_CLOSEST);
      this.currentMs = toMs;
    } catch (_e) {
    }
  }

  private async beginSeekDrag(): Promise<void> {
    const p = this.avPlayer;
    this.draggingSeek = true;
    this.dragStartRatio = this.progressRatio();
    this.dragRatio = this.dragStartRatio;
    this.wasPlayingBeforeSeek = this.isPlaying;
    this.seekResumePending = false;
    this.clearChromeAutoHideTimer();
    if (p !== null && this.wasPlayingBeforeSeek) {
      try {
        await p.pause();
      } catch (_e) {
      }
    }
  }

  private endSeekDrag(): void {
    this.seekByRatio(this.dragRatio);
    this.draggingSeek = false;
    this.seekResumePending = this.wasPlayingBeforeSeek;
  }

  /** 转码流播放异常时做一次保活重连，降低偶发失败率 */
  private tryAutoRecoverFromPlayError(gen: number): boolean {
    if (gen !== this.playGen || !this.active) {
      return false;
    }
    // 仅对 decode 转码流启用一次自愈，避免循环重连。
    if (this.decodeSessionPhotoId.length === 0 || this.autoRecoverCount >= 1) {
      return false;
    }
    this.autoRecoverCount++;
    this.videoLoading = true;
    this.showPlaybackRetry = false;
    this.hint = '播放重连中…';
    this.isPlaying = false;
    this.scheduleStartPlay();
    return true;
  }

  /**
   * 标记可恢复错误：展示文案并显示「重试」按钮。
   */
  private setPlaybackFailureHint(msg: string): void {
    this.hint = msg;
    this.showPlaybackRetry = true;
    this.videoLoading = false;
    this.videoRebuffering = false;
    this.clearLoadWatchdog();
    this.isPlaying = false;
    // 幻灯片不能卡在失败页上一直等；失败视为本段结束
    this.notifyAutoplayEndedIfNeeded();
  }

  /** 用户点击重试：清空失败态，允许再次走自动自愈计数，并重建播放。 */
  private onUserRetryPlayback(): void {
    this.showPlaybackRetry = false;
    this.hint = '';
    this.autoRecoverCount = 0;
    this.autoplayEndedNotified = false;
    if (!this.active || !this.surfaceReady || this.videoUrl.length === 0) {
      return;
    }
    this.videoLoading = true;
    this.scheduleStartPlay();
  }

  /**
   * 转码流 + 非 1x 倍速（尤其 720p + 1.75x）：起播后 setSpeed 会触发底层短暂不稳定，
   * 拉长一段时间内的失败过滤窗口；档位越“吃力”窗口越长。
   * @param appliedRate 实际刚调用 setSpeed 的倍率；缺省用 this.speedRate（长按快进时需传 2.0）
   */
  private armPlaybackFalsePositiveGuardForTranscode(appliedRate: number = -1): void {
    if (this.decodeSessionPhotoId.length === 0) {
      return;
    }
    const r = appliedRate > 0 ? appliedRate : this.effectivePlaybackRateForTiming();
    if (Math.abs(r - 1.0) <= 0.01) {
      return;
    }
    let extraMs = 850;
    // 高倍速对转码 HLS 压力更大，误报更集中
    if (r > 1.55) {
      extraMs += 500;
    }
    const q = this.currentQualityOption();
    if (!q.directStream && q.resolution === '720') {
      extraMs += 450;
    }
    this.playbackFalsePositiveGuardUntilMs = Date.now() + extraMs;
  }

  /**
   * 避免「本地误报播放失败」：
   * - release/重建后旧实例的异步拒绝仍可能进到 catch，须用 playGen + 实例指针过滤；
   * - 部分机型上 play()/prepare() 的 Promise 会因状态竞态被拒，但 state 已是 playing/prepared，此时不应弹失败；
   * - 转码 + 高倍速：套速后短时间窗口内、或进度 timeUpdate 仍在频繁更新时，error/state=error 多为误报。
   */
  private shouldIgnorePlaybackFailureSignal(p: media.AVPlayer, gen: number): boolean {
    if (gen !== this.playGen || this.avPlayer !== p) {
      return true;
    }
    try {
      const st = p.state;
      if (st === 'playing' || st === 'prepared') {
        return true;
      }
    } catch (_e) {
    }
    const now = Date.now();
    if (now < this.playbackFalsePositiveGuardUntilMs) {
      hilog.warn(DOMAIN, TAG, '忽略转码高倍速容错窗口内的失败信号 until=%{public}s',
        `${this.playbackFalsePositiveGuardUntilMs}`);
      return true;
    }
    const effRate = this.effectivePlaybackRateForTiming();
    if (this.decodeSessionPhotoId.length > 0 && Math.abs(effRate - 1.0) > 0.01) {
      /**
       * 高倍速下 timeUpdate 往往按「媒体时间」推进，墙钟上两次回调间隔 ≈ Δ媒体ms / effRate，
       * 固定 1100ms 会把「仍在正常播」误判成「长时间无进度」从而不再抑制误报的 error。
       * 故按生效倍速放宽墙钟容差（1.75x → 约 1.9s，2x → 约 2.2s）。
       */
      const wallTolMs = Math.floor(1100 * Math.max(1, effRate));
      if (this.lastAvTimeUpdateWallMs > 0 && now - this.lastAvTimeUpdateWallMs <= wallTolMs) {
        return true;
      }
    }
    return false;
  }

  private applyPickedSpeed(picked: number): void {
    const p = this.avPlayer;
    if (p === null) {
      return;
    }
    this.speedRate = picked;
    LAST_VIDEO_SPEED_RATE = picked;
    if (!this.longPressSpeeding) {
      this.applySpeed(p, picked);
      this.armPlaybackFalsePositiveGuardForTranscode();
    }
  }

  private currentQualityLabel(): string {
    const idx = this.qualityIndex;
    if (idx >= 0 && idx < QUALITY_OPTIONS.length) {
      return QUALITY_OPTIONS[idx].label;
    }
    return QUALITY_OPTIONS[0].label;
  }

  private parseVideoIdFromUrl(url: string): string {
    const s = url.trim();
    if (s.length === 0) {
      return '';
    }
    // 兼容绝对/相对地址：.../stream/v/{id}[?x=...]
    const m = s.match(/\/stream\/v\/([^/?#]+)/);
    if (m !== null && m.length > 1) {
      return m[1].trim();
    }
    return '';
  }

  /** 选择清晰度后立即重建播放链路；失败会自动回退到原始直链。 */
  private applyQualityAt(idx: number): void {
    if (idx < 0 || idx >= QUALITY_OPTIONS.length) {
      return;
    }
    // 禁止选择超过原始清晰度的档位（只能降，不能升）
    if (!this.isQualityAllowed(idx)) {
      this.hint = `当前视频最高支持 ${Math.max(1, Math.floor(this.maxResolutionP))}p，仅可降清晰度`;
      this.showPlaybackRetry = false;
      return;
    }
    if (idx === this.qualityIndex) {
      return;
    }
    this.qualityIndex = idx;
    LAST_VIDEO_QUALITY_INDEX = idx;
    if (!this.userStartedOnce) {
      return;
    }
    this.pendingQualitySwitch = true;
    this.isPlaying = false;
    /**
     * 记忆当前进度用于清晰度切换后的无缝续播。
     * 真正 seek 推迟到新流 playing 之后，避免在 prepared 对未缓存位置 seek 导致整段卡死。
     */
    if (this.currentMs > 0 && this.durationMs > 0) {
      this.pendingRestoreMs = Math.min(this.currentMs, Math.max(0, this.durationMs - 800));
    } else {
      this.pendingRestoreMs = 0;
    }
    // 切清晰度时保留控件，只转圈；全屏 loading 会挡住菜单，看起来像“没重新拉流”。
    this.videoLoading = false;
    this.videoRebuffering = this.active && this.videoUrl.length > 0;
    this.hint = '正在切换清晰度…';
    this.showPlaybackRetry = false;
    hilog.info(DOMAIN, TAG, 'applyQuality idx=%{public}s label=%{public}s restoreMs=%{public}s',
      `${idx}`, QUALITY_OPTIONS[idx].label, `${this.pendingRestoreMs}`);
    this.scheduleStartPlay();
  }

  private qualityMenuLabels(): string[] {
    const labels: string[] = [];
    for (let i = 0; i < QUALITY_OPTIONS.length; i++) {
      labels.push(QUALITY_OPTIONS[i].label);
    }
    return labels;
  }

  private async startPlay(): Promise<void> {
    const gen = ++this.playGen;
    // 新一次拉流，避免沿用上一条视频的容错截止时间误伤本轮判断
    this.playbackFalsePositiveGuardUntilMs = 0;
    this.lastAvTimeUpdateWallMs = 0;
    this.lastCachedDurationMs = 0;
    this.lastCachedDurationWarnMs = 0;
    this.videoRebuffering = this.pendingQualitySwitch;
    this.stopPlaybackInfoWatch();
    this.clearLoadWatchdog();
    this.normalizeQualityIndex();

    if (!this.active || !this.surfaceReady || this.videoUrl.length === 0) {
      hilog.warn(DOMAIN, TAG, 'startPlay skip active=%{public}s surface=%{public}s urlLen=%{public}s',
        `${this.active}`, `${this.surfaceReady}`, `${this.videoUrl.length}`);
      this.finishVideoLoading();
      this.videoRebuffering = false;
      return;
    }
    const qForDefer = QUALITY_OPTIONS[
      (this.qualityIndex >= 0 && this.qualityIndex < QUALITY_OPTIONS.length) ? this.qualityIndex : 0
    ];
    this.deferPlaybackRateUntilPlaying =
      !qForDefer.directStream && Math.abs(this.speedRate - 1.0) > 0.01;

    const surfaceId: string = this.xController.getXComponentSurfaceId();
    if (surfaceId.length === 0) {
      hilog.warn(DOMAIN, TAG, 'surfaceId empty');
      this.setPlaybackFailureHint('画面未就绪，请重试');
      return;
    }

    const clientPre = AppSession.getClient();
    if (this.decodeSessionPhotoId.length > 0 && clientPre !== null) {
      const toQuit = this.decodeSessionPhotoId;
      this.decodeSessionPhotoId = '';
      await clientPre.requestVideoDecodeQuit(toQuit, 2500);
      if (gen !== this.playGen) { return; }
    }

    // 销毁旧播放器
    const old = this.avPlayer;
    this.avPlayer = null;
    if (old !== null) {
      GalleryAuthVideo.unbindPlayerListeners(old);
      try { await old.release(); } catch (_e) {}
    }
    if (gen !== this.playGen) { return; }

    const client = AppSession.getClient();
    if (client === null) {
      this.setPlaybackFailureHint('未登录');
      return;
    }

    // 解析当前源的 videoId，用于按需调用 decode/play 申请指定清晰度地址。
    const sourceVideoId = this.parseVideoIdFromUrl(this.videoUrl);
    let playableUrl = this.videoUrl;
    const q = qForDefer;
    if (!q.directStream && sourceVideoId.length > 0) {
      const decodeRes = await client.requestVideoDecodePlayUrl({
        id: sourceVideoId,
        resolution: q.resolution,
        bitrate: q.bitrate,
        audioIndex: 1,
        videoEncoder: 'h264',
        channels: 2
      }, 20000);
      if (gen !== this.playGen) { return; }
      if (decodeRes.success && decodeRes.data !== undefined && decodeRes.data.playUrl.trim().length > 0) {
        playableUrl = decodeRes.data.playUrl.trim();
        this.decodeSessionPhotoId = sourceVideoId;
      } else {
        /**
         * 转码失败时不再自动回退到原始：
         * - 用户场景依赖转码来实现清晰度下降；
         * - 自动回退会造成“档位被悄悄改回原始”的错误体验。
         * 处理策略：保留当前清晰度选择，提示失败并终止本次播放重建。
         */
        const decodeMsg = decodeRes.message !== undefined && decodeRes.message.length > 0
          ? `${decodeRes.message}，请稍后重试`
          : '清晰度切换失败，请稍后重试';
        this.setPlaybackFailureHint(decodeMsg);
        this.pendingQualitySwitch = false;
        return;
      }
    } else {
      this.decodeSessionPhotoId = '';
    }

    const playbackStrategy = this.buildPlaybackStrategy(q.directStream);
    hilog.info(DOMAIN, TAG,
      'startPlay quality=%{public}s direct=%{public}s hls=%{public}s buf=%{public}ss startWatermark=%{public}ss url=%{public}s',
      q.label, `${q.directStream}`, `${GalleryAuthVideo.isHlsUrl(playableUrl)}`,
      `${playbackStrategy.preferredBufferDuration}`,
      `${playbackStrategy.preferredBufferDurationForPlaying}`,
      GalleryAuthVideo.sanitizeUrlForLog(playableUrl));

    // 获取鉴权头
    let headers: Record<string, string>;
    try {
      headers = await client.getGalleryStreamHeaders(playableUrl);
    } catch (e) {
      if (gen !== this.playGen) { return; }
      hilog.error(DOMAIN, TAG, 'getHeaders err: %{public}s', GalleryAuthVideo.formatMediaErr(e as Error));
      this.setPlaybackFailureHint('获取鉴权头失败');
      return;
    }
    if (gen !== this.playGen) { return; }

    // 创建播放器实例
    let player: media.AVPlayer;
    try {
      player = await media.createAVPlayer();
    } catch (e) {
      if (gen !== this.playGen) { return; }
      hilog.error(DOMAIN, TAG, 'createAVPlayer err: %{public}s', GalleryAuthVideo.formatMediaErr(e as Error));
      this.setPlaybackFailureHint('播放器创建失败');
      return;
    }
    if (gen !== this.playGen) {
      GalleryAuthVideo.safeRelease(player);
      return;
    }
    this.avPlayer = player;
    this.armLoadWatchdog(gen);

    // 错误回调
    player.on('error', (err: Error): void => {
      hilog.error(DOMAIN, TAG, 'avplayer error: %{public}s pos=%{public}s cachedMs=%{public}s',
        GalleryAuthVideo.formatMediaErr(err), `${this.currentMs}`, `${this.lastCachedDurationMs}`);
      if (gen !== this.playGen || this.avPlayer !== player) {
        return;
      }
      if (this.shouldIgnorePlaybackFailureSignal(player, gen)) {
        // 同实例下 state 已为 playing/prepared、或转码高倍速容错窗口内、或进度仍在走 → 多为误报。
        hilog.warn(DOMAIN, TAG, '忽略与当前状态不符的 avplayer error');
        return;
      }
      if (this.tryAutoRecoverFromPlayError(gen)) {
        return;
      }
      this.setPlaybackFailureHint('播放失败');
    });
    player.on('timeUpdate', (time: number): void => {
      if (gen !== this.playGen || this.draggingSeek) { return; }
      // 倍速切换后少数机型会短暂上报超出 duration 的 position 或非有限值，与「原始片长时间轴」脱节，
      // 易让进度条、清晰度切换记忆与失败抑制逻辑连锁误判。
      if (!Number.isFinite(time)) {
        return;
      }
      let mediaMs = Math.max(0, time);
      const d = this.durationMs;
      if (d > 0 && mediaMs > d) {
        mediaMs = d;
      }
      this.currentMs = mediaMs;
      this.lastAvTimeUpdateWallMs = Date.now();
    });
    player.on('durationUpdate', (d: number): void => {
      if (gen !== this.playGen) { return; }
      if (d > 0 && d !== this.durationMs) {
        this.durationMs = d;
        hilog.info(DOMAIN, TAG, 'durationUpdate %{public}s', `${this.durationMs}`);
        return;
      }
      if (d > 0) {
        this.durationMs = d;
      }
    });
    player.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number): void => {
      if (gen !== this.playGen || this.avPlayer !== player) {
        return;
      }
      if (infoType === media.BufferingInfoType.BUFFERING_START) {
        this.videoRebuffering = true;
        hilog.warn(DOMAIN, TAG,
          'BUFFERING_START pos=%{public}s dur=%{public}s cachedMs=%{public}s value=%{public}s',
          `${this.currentMs}`, `${this.durationMs}`, `${this.lastCachedDurationMs}`, `${value}`);
        return;
      }
      if (infoType === media.BufferingInfoType.BUFFERING_END) {
        this.videoRebuffering = false;
        hilog.info(DOMAIN, TAG, 'BUFFERING_END pos=%{public}s cachedMs=%{public}s',
          `${this.currentMs}`, `${this.lastCachedDurationMs}`);
        return;
      }
      if (infoType === media.BufferingInfoType.CACHED_DURATION) {
        this.lastCachedDurationMs = value;
        const now = Date.now();
        if (value < GALLERY_VIDEO_CACHED_DURATION_WARN_MS &&
          now - this.lastCachedDurationWarnMs >= 1000) {
          this.lastCachedDurationWarnMs = now;
          hilog.warn(DOMAIN, TAG, 'CACHED_DURATION 偏低 %{public}s pos=%{public}s dur=%{public}s',
            `${value}`, `${this.currentMs}`, `${this.durationMs}`);
        }
      }
    });
    player.on('seekDone', (time: number): void => {
      if (gen !== this.playGen) { return; }
      this.currentMs = time;
      if (this.seekResumePending) {
        this.seekResumePending = false;
        player.play().catch((e: Error): void => {
          if (this.shouldIgnorePlaybackFailureSignal(player, gen)) {
            return;
          }
          hilog.warn(DOMAIN, TAG, 'seek 后 play Promise 拒绝: %{public}s',
            GalleryAuthVideo.formatMediaErr(e));
          this.setPlaybackFailureHint('视频播放失败');
        });
      }
    });

    // 状态机回调：setMediaSource 后 state 仍为 idle；
    // 必须等 stateChange='initialized' 后才能设置 surfaceId 并调用 prepare。
    player.on('stateChange', (state: media.AVPlayerState, _reason: media.StateChangeReason): void => {
      if (gen !== this.playGen) { return; }
      hilog.info(DOMAIN, TAG, 'stateChange → %{public}s', state as string);
      if (state === 'initialized') {
        player.surfaceId = surfaceId;
        const runPrepare = (): void => {
          player.prepare().catch((e: Error): void => {
            if (this.shouldIgnorePlaybackFailureSignal(player, gen)) {
              return;
            }
            hilog.error(DOMAIN, TAG, 'prepare err: %{public}s', GalleryAuthVideo.formatMediaErr(e));
            this.setPlaybackFailureHint('视频准备失败');
          });
        };
        try {
          player.setPlaybackStrategy(playbackStrategy).then((): void => {
            if (gen !== this.playGen) {
              return;
            }
            runPrepare();
          }).catch((e: BusinessError): void => {
            hilog.warn(DOMAIN, TAG, 'setPlaybackStrategy err: %{public}s',
              GalleryAuthVideo.formatMediaErr(e));
            runPrepare();
          });
        } catch (_e) {
          runPrepare();
        }
      } else if (state === 'prepared') {
        this.durationMs = player.duration > 0 ? player.duration : this.durationMs;
        hilog.info(DOMAIN, TAG, 'prepared durationMs=%{public}s w=%{public}s h=%{public}s',
          `${this.durationMs}`, `${player.width}`, `${player.height}`);
        this.startPlaybackInfoWatch(player, gen);
        this.applyContainMode(player);
        this.applyPlayerMute(player);
        if (this.deferPlaybackRateUntilPlaying) {
          this.applySpeed(player, 1.0);
        } else {
          this.applySpeed(player, this.speedRate);
        }
        /**
         * 官方：对尚未缓存的位置 seek 会停在止播水线，直到重新凑够起播水线。
         * 切清晰度时新流还是空的，prepared 里先 seek 会让人以为“没有重新拉流”。
         * 这里一律先 play，等 playing 后再按 pendingRestoreMs 跳进度。
         */
        if (this.shouldResumePlayback()) {
          player.play().catch((e: Error): void => {
            if (this.shouldIgnorePlaybackFailureSignal(player, gen)) {
              return;
            }
            hilog.error(DOMAIN, TAG, 'play err: %{public}s', GalleryAuthVideo.formatMediaErr(e));
            this.setPlaybackFailureHint('视频播放失败');
          });
        }
        // 封面仍盖在 Surface 上，等 playing 再揭开，避免进页看到首帧跳变
      } else if (state === 'playing') {
        this.videoSurfaceVisible = true;
        this.finishVideoLoading();
        this.clearLoadWatchdog();
        this.videoRebuffering = false;
        this.hint = '';
        this.showPlaybackRetry = false;
        this.isPlaying = true;
        this.userStartedOnce = true;
        this.playbackEnded = false;
        this.onPlaybackChromeChanged();
        this.scheduleChromeAutoHide();
        this.pendingQualitySwitch = false;
        this.autoRecoverCount = 0;
        if (this.pendingRestoreMs > GALLERY_VIDEO_DEFER_SEEK_MIN_MS && this.durationMs > 0) {
          const toMs = Math.min(this.pendingRestoreMs, Math.max(0, this.durationMs - 500));
          this.pendingRestoreMs = -1;
          hilog.info(DOMAIN, TAG, 'quality switch seek after playing toMs=%{public}s', `${toMs}`);
          try {
            player.seek(toMs, media.SeekMode.SEEK_CLOSEST);
            this.currentMs = toMs;
          } catch (_e) {
          }
        } else {
          this.pendingRestoreMs = -1;
        }
        if (this.deferPlaybackRateUntilPlaying) {
          this.deferPlaybackRateUntilPlaying = false;
          this.applySpeed(player, this.speedRate);
          // 720p + 1.75x 等组合在 playing 后首次 setSpeed 时误报最多，拉开专用容错窗口
          this.armPlaybackFalsePositiveGuardForTranscode();
        }
      } else if (state === 'completed') {
        this.isPlaying = false;
        this.videoRebuffering = false;
        this.stopPlaybackInfoWatch();
        this.playbackEnded = true;
        this.onPlaybackChromeChanged();
        this.revealPlaybackChrome();
        this.syncUiProgressToNaturalEnd(player);
        this.notifyAutoplayEndedIfNeeded();
      } else if (state === 'paused' || state === 'stopped') {
        this.isPlaying = false;
      } else if (state === 'error') {
        // 仅处理当前绑定实例；释放中的旧实例可能仍上报 error，与 playGen 一并过滤。
        if (this.avPlayer !== player) {
          return;
        }
        if (this.shouldIgnorePlaybackFailureSignal(player, gen)) {
          hilog.warn(DOMAIN, TAG, '忽略 state=error（转码高倍速下多为抖动）');
          return;
        }
        this.videoRebuffering = false;
        this.stopPlaybackInfoWatch();
        hilog.error(DOMAIN, TAG, 'state error pos=%{public}s cachedMs=%{public}s',
          `${this.currentMs}`, `${this.lastCachedDurationMs}`);
        if (this.tryAutoRecoverFromPlayError(gen)) {
          return;
        }
        this.setPlaybackFailureHint('播放失败');
      }
    });

    // 设置媒体源（触发 idle → initialized 异步过渡，通过 stateChange 回调继续）
    try {
      const source = media.createMediaSourceWithUrl(playableUrl, headers);
      if (GalleryAuthVideo.isHlsUrl(playableUrl)) {
        try {
          source.setMimeType(media.AVMimeTypes.APPLICATION_M3U8);
        } catch (mimeErr) {
          hilog.warn(DOMAIN, TAG, 'setMimeType m3u8 err: %{public}s',
            GalleryAuthVideo.formatMediaErr(mimeErr as Error));
        }
      }
      // 官方：setMediaSource 开始预下载，缓冲策略必须在这里传入，不能拖到 initialized 之后。
      await player.setMediaSource(source, playbackStrategy);
      if (gen !== this.playGen) { return; }
      // 此处 state 可能仍是 idle，等待 stateChange 回调触发后续 prepare/play
    } catch (e) {
      if (gen !== this.playGen) { return; }
      hilog.error(DOMAIN, TAG, 'setMediaSource err: %{public}s', GalleryAuthVideo.formatMediaErr(e as Error));
      this.setPlaybackFailureHint('无法加载视频');
    }
  }

  private currentQualityOption(): QualityOption {
    this.normalizeQualityIndex();
    const idx = this.qualityIndex;
    if (idx >= 0 && idx < QUALITY_OPTIONS.length) {
      return QUALITY_OPTIONS[idx];
    }
    return QUALITY_OPTIONS[0];
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: 'gallery_auth_video_surface',
        type: 'surface',
        controller: this.xController
      })
        .width(this.videoSurfaceVisible ? '100%' : 1)
        .height(this.videoSurfaceVisible ? '100%' : 1)
        .backgroundColor(this.hostBackgroundColor())
        .opacity(this.videoSurfaceVisible ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
        .onLoad((): void => {
          this.surfaceReady = true;
          if (this.userStartedOnce) {
            this.scheduleStartPlay();
          }
        })
        .onDestroy((): void => {
          this.surfaceReady = false;
        });

      if (this.videoLoading) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(this.loadingSpinnerColor())
          Text('加载中…')
            .fontSize(14)
            .fontColor(this.loadingHintColor())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.None)
      }

      if (this.videoRebuffering && !this.videoLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(this.loadingSpinnerColor())
          .hitTestBehavior(HitTestMode.None)
      }

      if (!this.videoLoading) {
        GalleryVideoGestureHud({
          visible: this.adjustHudVisible,
          isBrightness: this.adjustIsBrightness,
          brightnessValue: this.screenBrightness,
          volumeValue: this.mediaVolume,
          volumeMax: this.mediaVolumeMax
        })
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.None)
      }

      AVVolumePanel({
        volumeLevel: this.mediaVolume,
        volumeParameter: {
          position: {
            x: -1,
            y: -1
          }
        }
      })
        .width(1)
        .height(1)
        .hitTestBehavior(HitTestMode.None)

      if (!this.videoLoading) {
        GalleryVideoOverlayChrome({
        visible: this.previewToolbarVisible,
        showCenterPlay: this.showCenterPlay(),
        landscape: this.landscape,
        speedText: this.speedBadgeText(),
        speedRate: this.speedRate,
        qualityLabels: this.qualityMenuLabels(),
        qualityIndex: this.qualityIndex,
        currentText: this.fmtTime(this.currentMs),
        durationText: this.fmtTime(this.durationMs),
        progress: this.progressRatio(),
        bottomPadding: this.effectiveBottomPadding(),
        onPlay: (): void => {
          void this.togglePlayPause();
        },
        onSelectSpeed: (rate: number): void => {
          this.bumpChromeAutoHide();
          this.applyPickedSpeed(rate);
        },
        onSelectQuality: (index: number): void => {
          this.bumpChromeAutoHide();
          this.applyQualityAt(index);
        },
        onFullscreen: (): void => {
          this.bumpChromeAutoHide();
          void this.toggleLandscape();
        },
        onInteract: (): void => {
          this.bumpChromeAutoHide();
        },
        onSeekStart: (): void => {
          this.clearChromeAutoHideTimer();
          void this.beginSeekDrag();
        },
        onSeekRatio: (ratio: number): void => {
          this.dragRatio = ratio;
          if (this.durationMs > 0) {
            this.currentMs = Math.floor(this.durationMs * ratio);
          }
        },
        onSeekEnd: (): void => {
          this.endSeekDrag();
          this.bumpChromeAutoHide();
        },
        onSeekCancel: (): void => {
          this.draggingSeek = false;
          this.seekResumePending = false;
          this.bumpChromeAutoHide();
        },
        onSeekTapRatio: (ratio: number): void => {
          if (!this.draggingSeek) {
            this.bumpChromeAutoHide();
            this.seekByRatio(ratio);
          }
        },
        onSingleTap: (): void => {
          this.onVideoSingleTap();
        },
        onDoubleTap: (): void => {
          void this.togglePlayPause();
        },
        onHoldSpeedStart: (): void => {
          const p = this.avPlayer;
          if (p === null) {
            return;
          }
          this.longPressSpeeding = true;
          this.applySpeed(p, LONG_PRESS_RATE);
          this.armPlaybackFalsePositiveGuardForTranscode(LONG_PRESS_RATE);
        },
        onHoldSpeedEnd: (): void => {
          const p = this.avPlayer;
          this.longPressSpeeding = false;
          if (p !== null) {
            this.applySpeed(p, this.speedRate);
            this.armPlaybackFalsePositiveGuardForTranscode();
          }
        },
        onVerticalAdjustStart: (event: GestureEvent): void => {
          this.beginVerticalAdjust(event);
        },
        onVerticalAdjustUpdate: (event: GestureEvent): void => {
          this.updateVerticalAdjust(event);
        },
        onVerticalAdjustEnd: (): void => {
          this.endVerticalAdjust();
        }
      })
        .width('100%')
        .height('100%')
      }

      // 必须放在全屏控制层之后：否则底部 Column 的占位区会优先命中，重试按钮点击无响应。
      if (this.hint.length > 0) {
        Column({ space: 14 }) {
          Text(this.hint)
            .fontSize(14)
            .fontColor(this.hintTextColor())
            .textAlign(TextAlign.Center)
          if (this.showPlaybackRetry) {
            FnHdsPillButton({
              text: '\u91cd\u8bd5',
              widthValue: 96,
              heightValue: 40,
              radiusValue: 20,
              fontSizeValue: 15,
              fontColorValue: this.controlPrimaryTextColor(),
              action: this.onUserRetryPlayback
            })
          }
        }
        .width('80%')
        .padding(16)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.hostBackgroundColor())
    .onAreaChange((_old, area): void => {
      const w = area.width as number;
      const h = area.height as number;
      if (w > 1) {
        this.viewW = w;
      }
      if (h > 1) {
        this.viewH = h;
      }
    })
  }
}
