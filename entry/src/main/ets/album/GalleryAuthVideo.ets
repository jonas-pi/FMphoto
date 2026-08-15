/**
 * 带图库鉴权的视频播放：Cookie、authx、AccessToken、Referer 与缩略图一致。
 *
 * 关键设计：
 *   1. setMediaSource() 的 Promise resolve 时 state 仍为 idle，
 *      必须等 stateChange 回调触发 'initialized' 才能设置 surfaceId 并调用 prepare。
 *   2. 使用 generation token (playGen) 保证并发安全：
 *      每次 startPlay() 入口同步递增 gen，后续所有异步检查点均比较 gen，
 *      不匹配则说明已被更新的调用取代，直接退出。
 */
import { media } from '@kit.MediaKit';
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

interface QualityOption {
  label: string;
  resolution: string;
  bitrate: number;
  /** true 表示走原始直链（/stream/v/{id}），不走 decode/play */
  directStream: boolean;
}

const QUALITY_OPTIONS: QualityOption[] = [
  // 默认使用原始直链，性能和带宽通常最好；用户可手动切到转码档位。
  { label: '原始', resolution: '1080', bitrate: 30000000, directStream: true },
  // 转码档位参数按你提供的抓包结构构造。
  { label: '高清 1080p', resolution: '1080', bitrate: 30000000, directStream: false },
  { label: '均衡 720p', resolution: '720', bitrate: 12000000, directStream: false },
  { label: '流畅 480p', resolution: '480', bitrate: 6000000, directStream: false }
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
  /** 当前视频允许的最大清晰度（p），由上游按原始分辨率估算传入 */
  @Prop maxResolutionP: number = 1080;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @State private videoLoading: boolean = false;
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

  private surfaceBackgroundColor(): ResourceColor {
    return this.isDarkTheme ? Color.Black : Color.White;
  }

  private controlPrimaryTextColor(): ResourceColor {
    return $r('app.color.button_secondary_fg');
  }

  private effectiveBottomPadding(): number {
    return this.previewToolbarVisible ? this.bottomPadding : 0;
  }

  private loadingIndicatorColor(): ResourceColor {
    return this.isDarkTheme ? Color.White : $r('app.color.brand_primary');
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
    this.longPressSpeeding = false;
    this.hint = '';
    this.showPlaybackRetry = false;
    this.pendingQualitySwitch = false;
    this.autoRecoverCount = 0;
    this.lastAvTimeUpdateWallMs = 0;
    this.playbackFalsePositiveGuardUntilMs = 0;
    this.videoLoading = this.active && this.videoUrl.length > 0;
    this.clearChromeAutoHideTimer();
    this.scheduleStartPlay();
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
    this.autoRecoverCount = 0;
    this.showPlaybackRetry = false;
    this.lastTogglePlaySeq = this.togglePlaySeq;
    this.lastToggleMuteSeq = this.toggleMuteSeq;
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
      this.isPlaying = false;
      this.adjustHudVisible = false;
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
    if (this.surfaceReady) {
      this.videoLoading = true;
      this.scheduleStartPlay();
    }
  }

  aboutToDisappear(): void {
    this.playGen++;
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

  private static safeRelease(p: media.AVPlayer | null): void {
    if (p === null) { return; }
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
    if (p === null) { return; }
    try {
      if (this.isPlaying) {
        this.isPlaying = false;
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
    this.isPlaying = false;
  }

  /** 用户点击重试：清空失败态，允许再次走自动自愈计数，并重建播放。 */
  private onUserRetryPlayback(): void {
    this.showPlaybackRetry = false;
    this.hint = '';
    this.autoRecoverCount = 0;
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
  private async chooseQuality(): Promise<void> {
    try {
      const choice = await this.getUIContext().getPromptAction().showActionMenu({
        title: '播放清晰度',
        buttons: [
          { text: '原始', color: '#007AFF' },
          { text: '高清 1080p', color: '#007AFF' },
          { text: '均衡 720p', color: '#007AFF' },
          { text: '流畅 480p', color: '#007AFF' }
        ]
      });
      const idx = choice.index;
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
      this.pendingQualitySwitch = true;
      /**
       * 记忆当前进度用于清晰度切换后的无缝续播：
       * - 仅记录有效区间 [0, duration)；
       * - 若当前尚未拿到 duration，则按 0 处理（从头播）。
       */
      if (this.currentMs > 0 && this.durationMs > 0) {
        this.pendingRestoreMs = Math.min(this.currentMs, Math.max(0, this.durationMs - 800));
      } else {
        this.pendingRestoreMs = 0;
      }
      this.videoLoading = this.active && this.videoUrl.length > 0;
      this.hint = '';
      this.showPlaybackRetry = false;
      this.scheduleStartPlay();
    } catch (_e) {
    }
  }

  private async startPlay(): Promise<void> {
    const gen = ++this.playGen;
    // 新一次拉流，避免沿用上一条视频的容错截止时间误伤本轮判断
    this.playbackFalsePositiveGuardUntilMs = 0;
    this.lastAvTimeUpdateWallMs = 0;
    this.normalizeQualityIndex();

    if (!this.active || !this.surfaceReady || this.videoUrl.length === 0) {
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
      return;
    }

    const clientPre = AppSession.getClient();
    if (this.decodeSessionPhotoId.length > 0 && clientPre !== null) {
      const toQuit = this.decodeSessionPhotoId;
      this.decodeSessionPhotoId = '';
      await clientPre.requestVideoDecodeQuit(toQuit, 8000);
      if (gen !== this.playGen) { return; }
    }

    // 销毁旧播放器
    const old = this.avPlayer;
    this.avPlayer = null;
    if (old !== null) {
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

    // 获取鉴权头
    let headers: Record<string, string>;
    try {
      headers = await client.getGalleryStreamHeaders(playableUrl);
    } catch (e) {
      if (gen !== this.playGen) { return; }
      hilog.error(DOMAIN, TAG, 'getHeaders err: %{public}s', String(e));
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
      hilog.error(DOMAIN, TAG, 'createAVPlayer err: %{public}s', String(e));
      this.setPlaybackFailureHint('播放器创建失败');
      return;
    }
    if (gen !== this.playGen) {
      GalleryAuthVideo.safeRelease(player);
      return;
    }
    this.avPlayer = player;

    // 错误回调
    player.on('error', (err: Error): void => {
      hilog.error(DOMAIN, TAG, 'avplayer error: %{public}s', String(err));
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
      this.durationMs = d > 0 ? d : this.durationMs;
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
          hilog.warn(DOMAIN, TAG, 'seek 后 play Promise 拒绝: %{public}s', String(e));
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
            hilog.error(DOMAIN, TAG, 'prepare err: %{public}s', String(e));
            this.setPlaybackFailureHint('视频准备失败');
          });
        };
        try {
          const strategy: media.PlaybackStrategy = { showFirstFrameOnPrepare: true };
          player.setPlaybackStrategy(strategy).then((): void => {
            if (gen !== this.playGen) {
              return;
            }
            runPrepare();
          }).catch((): void => {
            runPrepare();
          });
        } catch (_e) {
          runPrepare();
        }
      } else if (state === 'prepared') {
        this.videoLoading = false;
        this.durationMs = player.duration > 0 ? player.duration : this.durationMs;
        this.applyContainMode(player);
        this.applyPlayerMute(player);
        if (this.deferPlaybackRateUntilPlaying) {
          this.applySpeed(player, 1.0);
        } else {
          this.applySpeed(player, this.speedRate);
        }
        /**
         * 清晰度切换后先 seek，再在 seekDone 里恢复播放：
         * - 避免「seek 与 play 同时发生」带来的偶发声画不同步与卡顿。
         */
        if (this.pendingRestoreMs >= 0 && this.durationMs > 0) {
          const toMs = Math.min(this.pendingRestoreMs, Math.max(0, this.durationMs - 500));
          this.pendingRestoreMs = -1;
          this.seekResumePending = this.shouldResumePlayback();
          try {
            player.seek(toMs, media.SeekMode.SEEK_CLOSEST);
            this.currentMs = toMs;
          } catch (_e) {
            this.seekResumePending = false;
            if (this.shouldResumePlayback()) {
              player.play().catch((e: Error): void => {
                if (this.shouldIgnorePlaybackFailureSignal(player, gen)) {
                  return;
                }
                hilog.error(DOMAIN, TAG, 'play after seek-fail err: %{public}s', String(e));
                this.setPlaybackFailureHint('视频播放失败');
              });
            }
          }
        } else if (this.shouldResumePlayback()) {
          player.play().catch((e: Error): void => {
            if (this.shouldIgnorePlaybackFailureSignal(player, gen)) {
              return;
            }
            hilog.error(DOMAIN, TAG, 'play err: %{public}s', String(e));
            this.setPlaybackFailureHint('视频播放失败');
          });
        } else {
          this.videoLoading = false;
        }
      } else if (state === 'playing') {
        this.videoLoading = false;
        this.hint = '';
        this.showPlaybackRetry = false;
        this.isPlaying = true;
        this.userStartedOnce = true;
        this.playbackEnded = false;
        this.onPlaybackChromeChanged();
        this.scheduleChromeAutoHide();
        this.pendingQualitySwitch = false;
        this.autoRecoverCount = 0;
        if (this.deferPlaybackRateUntilPlaying) {
          this.deferPlaybackRateUntilPlaying = false;
          this.applySpeed(player, this.speedRate);
          // 720p + 1.75x 等组合在 playing 后首次 setSpeed 时误报最多，拉开专用容错窗口
          this.armPlaybackFalsePositiveGuardForTranscode();
        }
      } else if (state === 'completed') {
        this.isPlaying = false;
        this.playbackEnded = true;
        this.onPlaybackChromeChanged();
        this.revealPlaybackChrome();
        this.syncUiProgressToNaturalEnd(player);
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
        hilog.error(DOMAIN, TAG, 'state error');
        if (this.tryAutoRecoverFromPlayError(gen)) {
          return;
        }
        this.setPlaybackFailureHint('播放失败');
      }
    });

    // 设置媒体源（触发 idle → initialized 异步过渡，通过 stateChange 回调继续）
    try {
      const source = media.createMediaSourceWithUrl(playableUrl, headers);
      await player.setMediaSource(source);
      if (gen !== this.playGen) { return; }
      // 此处 state 可能仍是 idle，等待 stateChange 回调触发后续 prepare/play
    } catch (e) {
      if (gen !== this.playGen) { return; }
      hilog.error(DOMAIN, TAG, 'setMediaSource err: %{public}s', String(e));
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
        .width('100%')
        .height('100%')
        .backgroundColor(this.surfaceBackgroundColor())
        .hitTestBehavior(HitTestMode.None)
        .onLoad((): void => {
          this.surfaceReady = true;
          this.scheduleStartPlay();
        })
        .onDestroy((): void => {
          this.surfaceReady = false;
        });

      if (this.videoLoading) {
        Column({ space: 12 }) {
          LoadingProgress().width(48).height(48).color(this.loadingIndicatorColor())
        }
        .hitTestBehavior(HitTestMode.None)
      }

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

      GalleryVideoOverlayChrome({
        visible: this.previewToolbarVisible,
        showCenterPlay: this.showCenterPlay(),
        landscape: this.landscape,
        speedText: this.speedBadgeText(),
        speedRate: this.speedRate,
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
        onQuality: (): void => {
          this.bumpChromeAutoHide();
          void this.chooseQuality();
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
    // 透明背景：XComponent 表面始终为黑（视频渲染区域），四周留白区域由父组件
    // GalleryPreviewSlide 的主题背景透出（深色模式=黑，浅色模式=白），跟随系统主题
    .backgroundColor(this.surfaceBackgroundColor())
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
