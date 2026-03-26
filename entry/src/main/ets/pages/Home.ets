/**
 * 主页：底层 Web 固定首页（/）；相册 Tab 为原生 GalleryAlbumTab；「我的」叠在最上。
 * 底部导航使用鸿蒙标准 Tabs 风格（SymbolGlyph + 文字 + 选中态动画）。
 */
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
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
  @Prop webPath: string = '/';
  @Prop baseUrl: string = '';
  @Prop token: string = '';
  @Prop useHttps: boolean = true;
  @Prop @Watch('onLongTokenChange') longToken: string = '';
  @Prop wsSignKeyB64: string = '';

  private controller: webview.WebviewController = new webview.WebviewController();
  private webControllerReady: boolean = false;
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
      this.controller.loadUrl(target);
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
          this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' }).catch(() => {
          });
        })

      Button($r('app.string.logout'))
        .width('100%')
        .backgroundColor('#E11D48')
        .onClick((): void => {
          const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
          void SessionPreferences.clearSession(ctx).then(() => {
            AppSession.clear();
            this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
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
  @State private snapWebBase: string = '';
  @State private snapToken: string = '';
  @State private snapLongToken: string = '';
  @State private snapWsSignKeyB64: string = '';
  @State private sessionOk: boolean = false;
  /** 0 首页 Web / 1 原生相册 / 2 我的 */
  @State private bottomNavIndex: number = 0;
  /** 递增以触发 GalleryAlbumTab 重新拉 timeline */
  @State private albumReloadEpoch: number = 0;
  /** 内容区淡入缩放过渡 */
  @State private contentOpacity: number = 1;
  @State private contentScale: number = 1;
  /**
   * 系统深浅色模式（框架自动写入 AppStorage 'colorMode'）：
   * ColorMode.LIGHT = 0，ColorMode.DARK = 1
   */
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;

  // ── 系统栏颜色 ────────────────────────────────────────────────────────────

  onPageShow(): void {
    this.applySystemBarTheme();
  }

  onColorModeChanged(): void {
    this.applySystemBarTheme();
  }

  /** 根据深浅色模式同步状态栏/导航栏背景与文字颜色 */
  private applySystemBarTheme(): void {
    try {
      const dark = this.colorMode === 1; // ColorMode.DARK = 1
      // light: page_background = #F5F5F5；dark: page_background = #1C1C1E
      const bg = dark ? '#FF1C1C1E' : '#FFF5F5F5';
      const content = dark ? '#FFFFFFFF' : '#FF000000';
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win): void => {
        win.setWindowSystemBarProperties({
          statusBarColor: bg,
          navigationBarColor: bg,
          statusBarContentColor: content,
          navigationBarContentColor: content
        }).catch((_e: Error): void => {});
      }).catch((_e: Error): void => {});
    } catch (_e) {}
  }

  // ─────────────────────────────────────────────────────────────────────────

  private switchTab(target: number): void {
    if (target === this.bottomNavIndex) {
      return;
    }
    this.getUIContext().animateTo({ duration: 120, curve: Curve.EaseOut }, (): void => {
      this.contentOpacity = 0.92;
      this.contentScale = 0.996;
    });
    setTimeout((): void => {
      this.bottomNavIndex = target;
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
        this.contentOpacity = 1;
        this.contentScale = 1;
      });
    }, 100);
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
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
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

  /** 标准 Tabs 风格单项（SymbolGlyph + 文字 + 选中动画） */
  @Builder
  private tabItem(idx: number, symbol: Resource, label: Resource) {
    Column({ space: 4 }) {
      // 选中指示条
      Column()
        .width(this.bottomNavIndex === idx ? 24 : 0)
        .height(3)
        .borderRadius(1.5)
        .backgroundColor($r('app.color.brand_primary'))
        .animation({ duration: 220, curve: Curve.EaseOut })

      SymbolGlyph(symbol)
        .fontSize(this.bottomNavIndex === idx ? 25 : 23)
        .fontColor([this.bottomNavIndex === idx
          ? $r('app.color.brand_primary')
          : $r('app.color.text_secondary')])
        .animation({ duration: 220, curve: Curve.EaseOut })

      Text(label)
        .fontSize(11)
        .fontWeight(this.bottomNavIndex === idx ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.bottomNavIndex === idx
          ? $r('app.color.brand_primary')
          : $r('app.color.text_secondary'))
        .animation({ duration: 220, curve: Curve.EaseOut })
    }
    .layoutWeight(1)
    .height(60)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      this.switchTab(idx);
    })
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
              this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
              });
            })
        }
        .padding(24)
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          // ── 内容区 ───────────────────────────────────────────────────
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
          .opacity(this.contentOpacity)
          .scale({ x: this.contentScale, y: this.contentScale })

          // ── 标准鸿蒙底部 Tabs 栏 ────────────────────────────────────
          Row() {
            this.tabItem(0, $r('sys.symbol.house'), $r('app.string.tab_home'))
            this.tabItem(1, $r('sys.symbol.picture'), $r('app.string.tab_album'))
            this.tabItem(2, $r('sys.symbol.person'), $r('app.string.tab_me'))
          }
          .width('100%')
          .backgroundColor($r('app.color.page_background'))
          .borderWidth({ top: 0.5 })
          .borderColor('#1A000000')
          .padding({ bottom: 4 })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
