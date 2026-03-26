/**
 * 主页：底层 Web 固定首页（/）；相册 Tab 为原生 GalleryAlbumTab；「我的」叠在最上。
 */
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryAlbumTab } from '../album/GalleryAlbumTab';
import { AppSession } from '../auth/AppSession';
import { SessionPreferences } from '../auth/SessionPreferences';
import { CertPolicy } from '../network/CertPolicy';
import { fnWebViewBaseUrl } from '../network/ServerUrl';
import {
  fnWebDefaultUserAgent,
  fnWebLocalStorageSecretInjectScript,
  injectFnWebCookies
} from '../network/FnWebCookies';

const DOMAIN = 0xFF00;
const TAG = 'Home';

/**
 * 加载 NAS H5：仅首页 `base/`，相册已改为原生 API + 网格，不再用 Web 打开 /p/album。
 */
@Component
struct NasWebPanel {
  /** 以 `/` 开头；主页场景固定为 `/` */
  @Prop webPath: string = '/';
  @Prop baseUrl: string = '';
  @Prop token: string = '';
  /** 与 loadUrl 一致：内置管理端固定 https，Cookie 须带 Secure */
  @Prop useHttps: boolean = true;
  /** 异步补全 fnos-long-token 后须重新 loadUrl，否则 H5 仍缺会话 Cookie */
  @Prop @Watch('onLongTokenChange') longToken: string = '';
  /** 与 sample 一致：localStorage「fnos-Secret」= Base64(K)，同 wsSignKeyB64 */
  @Prop wsSignKeyB64: string = '';

  private controller: webview.WebviewController = new webview.WebviewController();
  /** 未 attach 前忽略 longToken 的 @Watch，避免无 controller 时误调 loadUrl */
  private webControllerReady: boolean = false;
  /** 与当前已用于 loadUrl 的长 Token 一致则不再刷页 */
  private lastWebLongTokenApplied: string = '';

  private onLongTokenChange(): void {
    if (!this.webControllerReady || this.baseUrl.length === 0 || this.token.length === 0) {
      return;
    }
    if (this.longToken === this.lastWebLongTokenApplied) {
      return;
    }
    this.lastWebLongTokenApplied = this.longToken;
    setTimeout((): void => {
      this.applyWebLoad();
    }, 0);
  }

  /** 在业务脚本前写入 fnos-Secret（与 sample PySide DocumentCreation 等效，尽量早执行） */
  private injectFnosSecretIfNeeded(pageUrl: string): void {
    if (this.wsSignKeyB64.length === 0) {
      return;
    }
    if (pageUrl.length === 0 || pageUrl.startsWith('about:') || !pageUrl.startsWith('http')) {
      return;
    }
    try {
      void this.controller.runJavaScript(fnWebLocalStorageSecretInjectScript(this.wsSignKeyB64));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'fnos-Secret inject: %{public}s', String(e));
    }
  }

  private applyWebLoad(): void {
    if (this.baseUrl.length === 0 || this.token.length === 0) {
      hilog.warn(DOMAIN, TAG, 'Web skip load: empty baseUrl or token');
      return;
    }
    let base = this.baseUrl;
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    let path = this.webPath.trim();
    let target: string;
    if (path.length === 0 || path === '/') {
      target = `${base}/`;
    } else {
      if (!path.startsWith('/')) {
        path = `/${path}`;
      }
      target = `${base}${path}`;
    }
    const longTok = this.longToken.length > 0 ? this.longToken : undefined;
    try {
      injectFnWebCookies(base, this.token, this.useHttps, longTok);
      /** 勿向 loadUrl 塞 Cookie/UA 附加头：部分 ArkWeb 会白屏；会话依赖已注入的 Cookie + 默认请求 */
      this.controller.loadUrl(target);
      /** sample：须在业务脚本前写入 fnos-Secret；部分机型 onPageBegin 无 url，故在导航后短延迟再注入一次 */
      setTimeout((): void => {
        this.injectFnosSecretIfNeeded(target);
      }, 80);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'inject/loadUrl err: %{public}s', String(e));
      try {
        this.controller.loadUrl(target);
        setTimeout((): void => {
          this.injectFnosSecretIfNeeded(target);
        }, 80);
      } catch (e2) {
        hilog.error(DOMAIN, TAG, 'loadUrl retry err: %{public}s', String(e2));
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Web({ src: 'about:blank', controller: this.controller })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .zoomAccess(true)
        .onControllerAttached((): void => {
          this.webControllerReady = true;
          this.lastWebLongTokenApplied = this.longToken;
          try {
            this.controller.setCustomUserAgent(fnWebDefaultUserAgent());
          } catch (_e) {
          }
          setTimeout((): void => {
            this.applyWebLoad();
          }, 100);
        })
        .onPageBegin((event) => {
          const u = event !== undefined && event.url !== undefined ? event.url : '';
          this.injectFnosSecretIfNeeded(u);
        })
        .onPageEnd((event) => {
          const u = event !== undefined && event.url !== undefined ? event.url : '';
          this.injectFnosSecretIfNeeded(u);
        })
        .onSslErrorEvent((event) => {
          if (event === null || event.handler === undefined) {
            return;
          }
          let base = this.baseUrl;
          if (base.endsWith('/')) {
            base = base.substring(0, base.length - 1);
          }
          if (base.length > 0 && CertPolicy.isTrusted(base)) {
            event.handler.handleConfirm();
          }
        })
      Button($r('app.string.web_reload'))
        .fontSize(13)
        .height(40)
        .margin({ right: 10, bottom: 56 })
        .onClick((): void => {
          this.applyWebLoad();
        })
    }
    .width('100%')
    .height('100%')
  }
}

@Component
struct MePanel {
  build() {
    Column({ space: 16 }) {
      Text($r('app.string.tab_me'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ top: 24 })

      Button($r('app.string.settings'))
        .width('100%')
        .onClick((): void => {
          router.pushUrl({ url: 'pages/Settings' }).catch(() => {
          });
        })

      Button($r('app.string.logout'))
        .width('100%')
        .backgroundColor('#E11D48')
        .onClick((): void => {
          const ctx = getContext(this) as common.UIAbilityContext;
          void SessionPreferences.clearSession(ctx).then(() => {
            AppSession.clear();
            router.replaceUrl({ url: 'pages/Login' }).catch(() => {
            });
          });
        })
    }
    .padding(24)
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Entry
@Component
struct Home {
  /**
   * 内置 Web 加载地址：同登录主机，端口固定 HTTP:5666 / HTTPS:5667（与飞牛 Web 服务一致）
   */
  @State private snapWebBase: string = '';
  @State private snapToken: string = '';
  @State private snapLongToken: string = '';
  /** 与 sample：localStorage「fnos-Secret」 */
  @State private snapWsSignKeyB64: string = '';
  @State private sessionOk: boolean = false;
  /** 0 首页 Web / 1 原生相册 / 2 我的 */
  @State private bottomNavIndex: number = 0;
  /** 递增以触发 GalleryAlbumTab 重新拉 timeline（切 Tab、longToken 补全时） */
  @State private albumReloadEpoch: number = 0;

  /** 供 GalleryAlbumTab @Consume：当前是否有全屏预览打开 */
  @Provide galleryHasPreview: boolean = false;
  /** 递增触发 GalleryAlbumTab 关闭预览（onBackPress 协调） */
  @Provide closeGalleryPreview: number = 0;

  /**
   * 系统返回手势/按键拦截：
   * - 相册全屏预览打开时消费返回事件，关闭预览而非退出页面
   * - 返回 true = 消费事件（不退出），false = 默认行为
   */
  onBackPress(): boolean {
    if (this.galleryHasPreview) {
      this.closeGalleryPreview++;
      return true;
    }
    return false;
  }

  aboutToAppear(): void {
    const s = AppSession.getStored();
    if (s !== null && s.token.length > 0 && s.baseUrl.length > 0) {
      let b = s.baseUrl;
      if (b.endsWith('/')) {
        b = b.substring(0, b.length - 1);
      }
      this.snapWebBase = fnWebViewBaseUrl(b);
      this.snapWsSignKeyB64 = s.wsSignKeyB64.length > 0 ? s.wsSignKeyB64 : '';
      hilog.info(DOMAIN, TAG, 'WebView base %{public}s (session %{public}s)', this.snapWebBase, b);
      this.snapToken = s.token;
      this.snapLongToken = s.fnosLongToken.length > 0 ? s.fnosLongToken : '';
      this.sessionOk = true;
      if (this.snapLongToken.length === 0) {
        const ctx = getContext(this) as common.UIAbilityContext;
        const c = AppSession.getClient();
        if (c !== null) {
          void c.fetchFnosLongTokenProbe(12000).then((tok: string) => {
            if (tok.length === 0) {
              return;
            }
            setTimeout((): void => {
              const cur = AppSession.getStored();
              if (cur === null) {
                return;
              }
              cur.fnosLongToken = tok;
              AppSession.apply(cur);
              void SessionPreferences.save(ctx, cur);
              this.snapLongToken = tok;
              this.albumReloadEpoch++;
            }, 0);
          });
        }
      }
    }
  }

  build() {
    Column() {
      if (!this.sessionOk) {
        Column({ space: 16 }) {
          Text($r('app.string.home_session_missing'))
            .fontSize(16)
            .width('100%')
          Text($r('app.string.home_session_hint'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Button($r('app.string.back_to_login'))
            .width('100%')
            .onClick((): void => {
              router.replaceUrl({ url: 'pages/Login' }).catch(() => {
              });
            })
        }
        .padding(24)
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Stack() {
            NasWebPanel({
              webPath: '/',
              baseUrl: this.snapWebBase,
              token: this.snapToken,
              useHttps: true,
              longToken: this.snapLongToken,
              wsSignKeyB64: this.snapWsSignKeyB64
            })
              .width('100%')
              .height('100%')
            if (this.bottomNavIndex === 1) {
              GalleryAlbumTab({
                baseUrl: this.snapWebBase,
                albumReloadEpoch: this.albumReloadEpoch
              })
                .width('100%')
                .height('100%')
            }
            if (this.bottomNavIndex === 2) {
              MePanel()
                .width('100%')
                .height('100%')
                .backgroundColor($r('app.color.page_background'))
            }
          }
          .width('100%')
          .layoutWeight(1)

          Row() {
            Column() {
              Text($r('app.string.tab_home'))
                .fontSize(12)
                .fontColor(
                  this.bottomNavIndex === 0 ? $r('app.color.brand_primary') : $r('app.color.text_secondary')
                )
            }
            .layoutWeight(1)
            .height(52)
            .justifyContent(FlexAlign.Center)
            .onClick((): void => {
              this.bottomNavIndex = 0;
            })

            Column() {
              Text($r('app.string.tab_album'))
                .fontSize(12)
                .fontColor(
                  this.bottomNavIndex === 1 ? $r('app.color.brand_primary') : $r('app.color.text_secondary')
                )
            }
            .layoutWeight(1)
            .height(52)
            .justifyContent(FlexAlign.Center)
            .onClick((): void => {
              this.bottomNavIndex = 1;
            })

            Column() {
              Text($r('app.string.tab_me'))
                .fontSize(12)
                .fontColor(
                  this.bottomNavIndex === 2 ? $r('app.color.brand_primary') : $r('app.color.text_secondary')
                )
            }
            .layoutWeight(1)
            .height(52)
            .justifyContent(FlexAlign.Center)
            .onClick((): void => {
              this.bottomNavIndex = 2;
            })
          }
          .width('100%')
          .padding({ bottom: 4 })
          .backgroundColor($r('app.color.page_background'))
          .borderWidth({ top: 1 })
          .borderColor('#22000000')
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
