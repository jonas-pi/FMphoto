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

@Component
export struct GalleryAuthVideo {
  @Prop @Watch('onUrlChange') videoUrl: string = '';
  @State private hint: string = '加载中…';

  private xController: XComponentController = new XComponentController();
  private avPlayer: media.AVPlayer | null = null;
  private playGen: number = 0;
  private surfaceReady: boolean = false;

  onUrlChange(): void {
    this.playGen++;
    if (this.videoUrl.length > 0) {
      this.hint = '加载中…';
    }
    void this.startPlay();
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

  private async startPlay(): Promise<void> {
    const gen = ++this.playGen;

    if (!this.surfaceReady || this.videoUrl.length === 0) {
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
    if (client === null) { this.hint = '未登录'; return; }

    // 获取鉴权头
    let headers: Record<string, string>;
    try {
      headers = await client.getGalleryStreamHeaders(this.videoUrl);
    } catch (e) {
      if (gen !== this.playGen) { return; }
      hilog.error(DOMAIN, TAG, 'getHeaders err: %{public}s', String(e));
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
        this.hint = '播放失败';
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
          this.hint = '视频准备失败';
        });
      } else if (state === 'prepared') {
        player.play().catch((e: Error): void => {
          if (gen !== this.playGen) { return; }
          hilog.error(DOMAIN, TAG, 'play err: %{public}s', String(e));
          this.hint = '视频播放失败';
        });
      } else if (state === 'playing') {
        this.hint = '';
      } else if (state === 'error') {
        hilog.error(DOMAIN, TAG, 'state error');
        this.hint = '播放失败';
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
        .onLoad((): void => {
          this.surfaceReady = true;
          void this.startPlay();
        })
        .onDestroy((): void => {
          this.surfaceReady = false;
        });

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(14)
          .fontColor('#CCCCCC')
          .padding(16)
      }
    }
    .width('100%')
    .height('100%')
  }
}
