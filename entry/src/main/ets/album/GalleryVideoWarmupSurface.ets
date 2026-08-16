/**
 * 进预览前在当前页用隐藏 Surface 把真实视频 prepare 到出首帧。
 * 封面不能作为就绪标志。
 */
import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { completeVideoWarmup } from './GalleryPreviewEntryGate';

const DOMAIN: number = 0xFF00;
const TAG: string = 'VideoWarmup';

@Component
export struct GalleryVideoWarmupSurface {
  @Prop @Watch('onUrlChange') videoUrl: string = '';
  private xController: XComponentController = new XComponentController();
  private player: media.AVPlayer | null = null;
  private gen: number = 0;
  private surfaceReady: boolean = false;
  private finished: boolean = false;

  aboutToAppear(): void {
    if (this.videoUrl.length > 0 && this.surfaceReady) {
      void this.startWarmup();
    }
  }

  aboutToDisappear(): void {
    this.gen++;
    this.releasePlayer();
  }

  onUrlChange(): void {
    if (this.videoUrl.length === 0) {
      this.gen++;
      this.releasePlayer();
      return;
    }
    this.finished = false;
    void this.startWarmup();
  }

  private finish(ok: boolean): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    this.gen++;
    this.releasePlayer();
    completeVideoWarmup(ok);
  }

  private releasePlayer(): void {
    const p = this.player;
    this.player = null;
    if (p !== null) {
      try {
        p.off('stateChange');
        p.off('error');
      } catch (_e) {
      }
      p.release().catch((): void => {});
    }
  }

  private async startWarmup(): Promise<void> {
    const gen = ++this.gen;
    this.releasePlayer();
    if (this.videoUrl.length === 0 || !this.surfaceReady) {
      return;
    }
    const surfaceId: string = this.xController.getXComponentSurfaceId();
    if (surfaceId.length === 0) {
      this.finish(false);
      return;
    }
    const client = AppSession.getClient();
    if (client === null) {
      this.finish(false);
      return;
    }
    let headers: Record<string, string>;
    try {
      headers = await client.getGalleryStreamHeaders(this.videoUrl);
    } catch (_e) {
      if (gen === this.gen) {
        this.finish(false);
      }
      return;
    }
    if (gen !== this.gen) {
      return;
    }
    let player: media.AVPlayer;
    try {
      player = await media.createAVPlayer();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'createAVPlayer %{public}s', String(e));
      if (gen === this.gen) {
        this.finish(false);
      }
      return;
    }
    if (gen !== this.gen) {
      player.release().catch((): void => {});
      return;
    }
    this.player = player;
    player.on('error', (): void => {
      if (gen !== this.gen) {
        return;
      }
      this.finish(false);
    });
    player.on('stateChange', (state: media.AVPlayerState): void => {
      if (gen !== this.gen) {
        return;
      }
      if (state === 'initialized') {
        player.surfaceId = surfaceId;
        const runPrepare = (): void => {
          player.prepare().catch((): void => {
            if (gen === this.gen) {
              this.finish(false);
            }
          });
        };
        try {
          const strategy: media.PlaybackStrategy = { showFirstFrameOnPrepare: true };
          player.setPlaybackStrategy(strategy).then((): void => {
            if (gen === this.gen) {
              runPrepare();
            }
          }).catch((): void => {
            runPrepare();
          });
        } catch (_e) {
          runPrepare();
        }
      } else if (state === 'prepared') {
        this.finish(true);
      }
    });
    try {
      const source = media.createMediaSourceWithUrl(this.videoUrl, headers);
      await player.setMediaSource(source);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'setMediaSource %{public}s', String(e));
      if (gen === this.gen) {
        this.finish(false);
      }
    }
  }

  build() {
    XComponent({
      id: 'gallery_video_warmup_surface',
      type: 'surface',
      controller: this.xController
    })
      .width(64)
      .height(64)
      .hitTestBehavior(HitTestMode.None)
      .onLoad((): void => {
        this.surfaceReady = true;
        void this.startWarmup();
      })
      .onDestroy((): void => {
        this.surfaceReady = false;
      });
  }
}
