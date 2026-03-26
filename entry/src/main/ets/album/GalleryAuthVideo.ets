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
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';

const DOMAIN = 0xFF00;
const TAG = 'GalleryAuthVideo';
const LONG_PRESS_RATE = 2.0;

interface SpeedOption {
  label: string;
  rate: number;
}

const SPEED_OPTIONS: SpeedOption[] = [
  { label: '0.75x', rate: 0.75 },
  { label: '1.0x', rate: 1.0 },
  { label: '1.25x', rate: 1.25 },
  { label: '1.75x', rate: 1.75 },
  { label: '2.0x', rate: 2.0 }
];

@Component
export struct GalleryAuthVideo {
  @Prop @Watch('onUrlChange') videoUrl: string = '';
  /** 当前是否为 Swiper 可见页；不可见时暂停以避免后台串音 */
  @Prop @Watch('onActiveChanged') active: boolean = true;
  /** 底部额外安全间距，由父页面传入以避开底部工具栏 */
  @Prop bottomPadding: number = 0;
  @State private videoLoading: boolean = false;
  @State private hint: string = '';
  @State private controlsVisible: boolean = true;
  @State private isPlaying: boolean = false;
  @State private currentMs: number = 0;
  @State private durationMs: number = 0;
  @State private dragRatio: number = 0;
  @State private draggingSeek: boolean = false;
  @State private speedRate: number = 1.0;
  @State private longPressSpeeding: boolean = false;
  @State private progressW: number = 1;

  private xController: XComponentController = new XComponentController();
  private avPlayer: media.AVPlayer | null = null;
  private playGen: number = 0;
  private surfaceReady: boolean = false;
  private dragStartRatio: number = 0;
  private wasPlayingBeforeSeek: boolean = false;
  private seekResumePending: boolean = false;

  onUrlChange(): void {
    this.playGen++;
    this.isPlaying = false;
    this.currentMs = 0;
    this.durationMs = 0;
    this.draggingSeek = false;
    this.dragRatio = 0;
    this.wasPlayingBeforeSeek = false;
    this.seekResumePending = false;
    this.speedRate = 1.0;
    this.longPressSpeeding = false;
    this.hint = '';
    this.videoLoading = this.active && this.videoUrl.length > 0;
    void this.startPlay();
  }

  onActiveChanged(): void {
    const p = this.avPlayer;
    if (!this.active) {
      this.videoLoading = false;
      this.isPlaying = false;
      if (p !== null) {
        p.pause().catch((): void => {});
      }
      return;
    }
    // 恢复到可见页：优先续播已有实例；没有实例则按正常链路重建
    if (this.videoUrl.length === 0) {
      return;
    }
    if (p !== null) {
      p.play().catch((): void => {});
      return;
    }
    if (this.surfaceReady) {
      this.videoLoading = true;
      void this.startPlay();
    }
  }

  aboutToDisappear(): void {
    this.playGen++;
    const p = this.avPlayer;
    this.avPlayer = null;
    GalleryAuthVideo.safeRelease(p);
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
    const ss = s < 10 ? `0${s}` : `${s}`;
    return `${m}:${ss}`;
  }

  /**
   * 与图片预览一致：完整显示（Contain）。
   * 横视频优先贴合屏幕宽度，超高竖视频优先贴合屏幕高度，不做裁切。
   */
  private applyContainMode(player: media.AVPlayer): void {
    player.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT;
  }

  private applySpeed(player: media.AVPlayer, rate: number): void {
    try {
      player.setPlaybackRate(rate);
    } catch (_e) {
      try {
        if (rate <= 0.75) {
          player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_0_75_X);
        } else if (rate <= 1.0) {
          player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_00_X);
        } else if (rate <= 1.25) {
          player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_25_X);
        } else if (rate <= 1.75) {
          player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_1_75_X);
        } else {
          player.setSpeed(media.PlaybackSpeed.SPEED_FORWARD_2_00_X);
        }
      } catch (_e2) {
      }
    }
  }

  private async togglePlayPause(): Promise<void> {
    const p = this.avPlayer;
    if (p === null) { return; }
    try {
      if (this.isPlaying) {
        await p.pause();
      } else {
        await p.play();
      }
    } catch (_e) {
    }
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

  private async chooseSpeed(): Promise<void> {
    try {
      const choice = await this.getUIContext().getPromptAction().showActionMenu({
        title: '播放倍速',
        buttons: [
          { text: '0.75x', color: '#007AFF' },
          { text: '1.0x', color: '#007AFF' },
          { text: '1.25x', color: '#007AFF' },
          { text: '1.75x', color: '#007AFF' },
          { text: '2.0x', color: '#007AFF' }
        ]
      });
      const idx = choice.index;
      if (idx < 0 || idx >= SPEED_OPTIONS.length) {
        return;
      }
      const p = this.avPlayer;
      if (p === null) {
        return;
      }
      const picked = SPEED_OPTIONS[idx].rate;
      this.speedRate = picked;
      if (!this.longPressSpeeding) {
        this.applySpeed(p, picked);
      }
    } catch (_e) {
    }
  }

  private async startPlay(): Promise<void> {
    const gen = ++this.playGen;

    if (!this.active || !this.surfaceReady || this.videoUrl.length === 0) {
      return;
    }
    const surfaceId: string = this.xController.getXComponentSurfaceId();
    if (surfaceId.length === 0) {
      hilog.warn(DOMAIN, TAG, 'surfaceId empty');
      return;
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
      this.videoLoading = false;
      this.hint = '未登录';
      return;
    }

    // 获取鉴权头
    let headers: Record<string, string>;
    try {
      headers = await client.getGalleryStreamHeaders(this.videoUrl);
    } catch (e) {
      if (gen !== this.playGen) { return; }
      hilog.error(DOMAIN, TAG, 'getHeaders err: %{public}s', String(e));
      this.videoLoading = false;
      this.hint = '获取鉴权头失败';
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
      this.videoLoading = false;
      this.hint = '播放器创建失败';
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
      if (gen === this.playGen) {
        this.videoLoading = false;
        this.hint = '播放失败';
        this.isPlaying = false;
      }
    });
    player.on('timeUpdate', (time: number): void => {
      if (gen !== this.playGen || this.draggingSeek) { return; }
      this.currentMs = time;
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
        player.play().catch((_e: Error): void => {});
      }
    });

    // 状态机回调：setMediaSource 后 state 仍为 idle；
    // 必须等 stateChange='initialized' 后才能设置 surfaceId 并调用 prepare。
    player.on('stateChange', (state: media.AVPlayerState, _reason: media.StateChangeReason): void => {
      if (gen !== this.playGen) { return; }
      hilog.info(DOMAIN, TAG, 'stateChange → %{public}s', state as string);
      if (state === 'initialized') {
        player.surfaceId = surfaceId;
        player.prepare().catch((e: Error): void => {
          if (gen !== this.playGen) { return; }
          hilog.error(DOMAIN, TAG, 'prepare err: %{public}s', String(e));
          this.videoLoading = false;
          this.hint = '视频准备失败';
        });
      } else if (state === 'prepared') {
        this.durationMs = player.duration > 0 ? player.duration : this.durationMs;
        this.applyContainMode(player);
        this.applySpeed(player, this.speedRate);
        if (this.active) {
          player.play().catch((e: Error): void => {
            if (gen !== this.playGen) { return; }
            hilog.error(DOMAIN, TAG, 'play err: %{public}s', String(e));
            this.videoLoading = false;
            this.hint = '视频播放失败';
          });
        }
      } else if (state === 'playing') {
        this.videoLoading = false;
        this.hint = '';
        this.isPlaying = true;
      } else if (state === 'paused' || state === 'completed' || state === 'stopped') {
        this.isPlaying = false;
      } else if (state === 'error') {
        hilog.error(DOMAIN, TAG, 'state error');
        this.videoLoading = false;
        this.hint = '播放失败';
        this.isPlaying = false;
      }
    });

    // 设置媒体源（触发 idle → initialized 异步过渡，通过 stateChange 回调继续）
    try {
      const source = media.createMediaSourceWithUrl(this.videoUrl, headers);
      await player.setMediaSource(source);
      if (gen !== this.playGen) { return; }
      // 此处 state 可能仍是 idle，等待 stateChange 回调触发后续 prepare/play
    } catch (e) {
      if (gen !== this.playGen) { return; }
      hilog.error(DOMAIN, TAG, 'setMediaSource err: %{public}s', String(e));
      this.videoLoading = false;
      this.hint = '无法加载视频';
    }
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
        .onClick((): void => {
          this.controlsVisible = !this.controlsVisible;
        })
        .gesture(
          LongPressGesture({ repeat: false })
            .onAction((): void => {
              const p = this.avPlayer;
              if (p === null) { return; }
              this.longPressSpeeding = true;
              this.applySpeed(p, LONG_PRESS_RATE);
            })
            .onActionEnd((): void => {
              const p = this.avPlayer;
              this.longPressSpeeding = false;
              if (p !== null) {
                this.applySpeed(p, this.speedRate);
              }
            })
            .onActionCancel((): void => {
              const p = this.avPlayer;
              this.longPressSpeeding = false;
              if (p !== null) {
                this.applySpeed(p, this.speedRate);
              }
            })
        )
        .onLoad((): void => {
          this.surfaceReady = true;
          void this.startPlay();
        })
        .onDestroy((): void => {
          this.surfaceReady = false;
        });

      if (this.videoLoading) {
        Column({ space: 12 }) {
          LoadingProgress().width(48).height(48).color(Color.White)
        }
        .hitTestBehavior(HitTestMode.None)
      } else if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(14)
          .fontColor('#CCCCCC')
          .padding(16)
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.controlsVisible) {
        Column() {
          Blank().layoutWeight(1)
          Column({ space: 8 }) {
            Row({ space: 10 }) {
              Button({ type: ButtonType.Circle, stateEffect: true }) {
                SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
                  .fontSize(20)
                  .fontColor([Color.White])
              }
              .width(40).height(40).backgroundColor('#55000000')
              .onClick((): void => { void this.togglePlayPause(); })

              Button({ type: ButtonType.Capsule, stateEffect: true }) {
                Text(this.longPressSpeeding ? '2.0x' : `${this.speedRate.toFixed(2)}x`)
                  .fontSize(13)
                  .fontColor(Color.White)
              }
              .height(36).backgroundColor('#55000000')
              .onClick((): void => { void this.chooseSpeed(); })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            Row({ space: 8 }) {
              Text(this.fmtTime(this.currentMs))
                .fontSize(11)
                .fontColor('#DDFFFFFF')
                .width(44)
              Stack({ alignContent: Alignment.Start }) {
                Row()
                  .width('100%')
                  .height(3)
                  .backgroundColor('#44FFFFFF')
                  .borderRadius(2)
                Row()
                  .width(`${Math.round(this.progressRatio() * 100)}%`)
                  .height(3)
                  .backgroundColor('#FFFFFFFF')
                  .borderRadius(2)
              }
              .layoutWeight(1)
              .height(24)
              .onAreaChange((_old, area): void => {
                const w = area.width as number;
                this.progressW = w > 1 ? w : 1;
              })
              .gesture(
                PanGesture({ direction: PanDirection.Horizontal })
                  .onActionStart((): void => {
                    void this.beginSeekDrag();
                  })
                  .onActionUpdate((ev: GestureEvent): void => {
                    const delta = this.progressW > 0 ? ev.offsetX / this.progressW : 0;
                    const r = this.dragStartRatio + delta;
                    this.dragRatio = Math.max(0, Math.min(1, r));
                    if (this.durationMs > 0) {
                      this.currentMs = Math.floor(this.durationMs * this.dragRatio);
                    }
                  })
                  .onActionEnd((): void => {
                    this.endSeekDrag();
                  })
                  .onActionCancel((): void => {
                    this.draggingSeek = false;
                    this.seekResumePending = false;
                  })
              )

              Text(this.fmtTime(this.durationMs))
                .fontSize(11)
                .fontColor('#DDFFFFFF')
                .width(44)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .padding({ left: 12, right: 12, bottom: 18 + this.bottomPadding, top: 10 })
          .backgroundColor('#33000000')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
      }
    }
    .width('100%')
    .height('100%')
    // 透明背景：XComponent 表面始终为黑（视频渲染区域），四周留白区域由父组件
    // GalleryPreviewSlide 的主题背景透出（深色模式=黑，浅色模式=白），跟随系统主题
    .backgroundColor(Color.Transparent)
  }
}
