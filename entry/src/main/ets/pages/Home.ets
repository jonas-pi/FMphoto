/**
 * 主页：底层 Web 固定首页（/）；相册 Tab 为原生 GalleryAlbumTab；「我的」叠在最上。
 * 底部导航使用鸿蒙标准 Tabs 风格（SymbolGlyph + 文字 + 选中态动画）。
 */
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryAlbumTab } from '../album/GalleryAlbumTab';
import { galleryTryConsumeAlbumBack } from '../album/GalleryAlbumHardwareBack';
import { AppSession } from '../auth/AppSession';
import { proactiveRefreshLongTokenOnForeground } from '../auth/SessionReauth';
import { SessionPreferences } from '../auth/SessionPreferences';
import { CertPolicy } from '../network/CertPolicy';
import { fnWebViewBaseUrl } from '../network/ServerUrl';
import {
  fnWebDefaultUserAgent,
  fnWebLocalStorageSecretInjectScript,
  injectFnWebCookies
} from '../network/FnWebCookies';
import { FnPrimaryButton, FnSecondaryButton } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION,
  FN_TAB_ALBUM_ME_CURVE,
  FN_TAB_ALBUM_ME_IN_MS,
  FN_TAB_ALBUM_ME_OUT_MS,
  FN_TAB_HOME_CONTENT_CURVE,
  FN_TAB_HOME_CONTENT_IN_MS,
  FN_TAB_HOME_CONTENT_OUT_MS,
  FN_TAB_SWITCH_CURVE,
  FN_TAB_SWITCH_IN_DURATION
} from '../common/FnMotion';
import {
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_ROW_HEIGHT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from '../common/GalleryTopBarLayout';

const DOMAIN = 0xFF00;
const TAG = 'Home';
const HOME_BOTTOM_NAV_ITEM_HEIGHT_VP: number = 64;
const HOME_BOTTOM_NAV_PAD_TOP_VP: number = 6;
const HOME_BOTTOM_NAV_PAD_SIDE_VP: number = 6;
const HOME_BOTTOM_NAV_PAD_EXTRA_BOTTOM_VP: number = 8;

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
      FnSecondaryButton({ text: $r('app.string.web_reload') })
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
  @Prop topSafeInsetVp: number = 0;

  build() {
    Column() {
      Row() {
        Row()
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        Text($r('app.string.tab_me'))
          .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(2)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row()
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: GALLERY_TOP_BAR_PAD_LEFT_VP,
        right: GALLERY_TOP_BAR_PAD_RIGHT_VP,
        top: GALLERY_TOP_BAR_PAD_TOP_VP + this.topSafeInsetVp,
        bottom: GALLERY_TOP_BAR_PAD_BOTTOM_VP
      })

      Column({ space: 16 }) {
        Button($r('app.string.logout'))
          .width('100%')
          .height($r('app.float.button_height'))
          .backgroundColor('#E11D48')
          .fontColor(Color.White)
          .borderRadius($r('app.float.radius_medium'))
          .onClick((): void => {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
            void SessionPreferences.clearSession(ctx).then(() => {
              AppSession.clear();
              this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
              });
            });
          })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 24, right: 24, top: 8, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
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
  /** 页面可见时递增 → 通知 GalleryAlbumTab 做删除同步 */
  @State private pageShowSignal: number = 0;
  /** Tab 切换时内容区水平位移（保持不透明，避免底层 Web 透出） */
  @State private contentTranslateX: number = 0;
  /**
   * 系统深浅色模式（框架自动写入 AppStorage 'colorMode'）：
   * ColorMode.LIGHT = 0，ColorMode.DARK = 1
   */
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  /**
   * 用 @State 镜像深色标志：@StorageProp 在嵌套方法链中依赖追踪可能丢失，
   * @State 变更则必定触发 build() 重渲染，保证背景色实时同步。
   */
  @State private isDarkTheme: boolean = false;
  @State private systemTopInsetVp: number = 0;
  @State private systemBottomInsetVp: number = 0;

  // ── 系统栏颜色 ────────────────────────────────────────────────────────────

  onBackPress(): boolean {
    if (this.bottomNavIndex === 1 && galleryTryConsumeAlbumBack()) {
      return true;
    }
    return false;
  }

  onPageShow(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBarTheme();
    this.pageShowSignal++;
    // 节流探测 long-token，降低长时间挂起后进相册 HTTP 401 的概率（非永久保活，仅前台轻量刷新）
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void proactiveRefreshLongTokenOnForeground(ctx).then((changed: boolean): void => {
      if (changed) {
        const s = AppSession.getStored();
        if (s !== null) {
          this.snapLongToken = s.fnosLongToken.length > 0 ? s.fnosLongToken : '';
        }
      }
    });
  }

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBarTheme();
  }

  /** 根据深浅色模式同步状态栏/导航栏背景与文字颜色 */
  private applySystemBarTheme(): void {
    try {
      const dark = this.colorMode === 1; // ColorMode.DARK = 1
      // light: page_background = #F5F5F5；dark: page_background = #1C1C1E
      const content = dark ? '#FFFFFFFF' : '#FF000000';
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win): void => {
        win.setWindowLayoutFullScreen(true).catch((_e: Error): void => {});
        this.syncSystemAvoidArea(win);
        win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: content,
          navigationBarContentColor: content
        }).catch((_e: Error): void => {});
      }).catch((_e: Error): void => {});
    } catch (_e) {}
  }

  // ─────────────────────────────────────────────────────────────────────────

  /**
   * 相册 Tab 内可能已静默刷新 token；切回首页 Web 前同步快照，避免 Web 仍带过期 Cookie。
   */
  private pxToVp(value: number): number {
    try {
      return this.getUIContext().px2vp(value);
    } catch (_e) {
      return value;
    }
  }

  private syncSystemAvoidArea(win: window.Window): void {
    try {
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.systemTopInsetVp = Math.max(0, this.pxToVp(area.topRect.height));
      this.systemBottomInsetVp = Math.max(0, this.pxToVp(area.bottomRect.height));
    } catch (_e) {
      this.systemTopInsetVp = 0;
      this.systemBottomInsetVp = 0;
    }
  }

  private bottomNavPadBottom(): number {
    return Math.max(HOME_BOTTOM_NAV_PAD_EXTRA_BOTTOM_VP, this.systemBottomInsetVp + HOME_BOTTOM_NAV_PAD_EXTRA_BOTTOM_VP);
  }

  private syncWebSessionSnapshotFromAppSession(): void {
    const s = AppSession.getStored();
    if (s === null || !this.sessionOk) {
      return;
    }
    this.snapToken = s.token;
    this.snapLongToken = s.fnosLongToken.length > 0 ? s.fnosLongToken : '';
    this.snapWsSignKeyB64 = s.wsSignKeyB64.length > 0 ? s.wsSignKeyB64 : '';
  }

  private switchTab(target: number): void {
    if (target === this.bottomNavIndex) {
      return;
    }
    const involvesHome = target === 0 || this.bottomNavIndex === 0;
    const albumMeSwitch =
      (target === 1 && this.bottomNavIndex === 2) || (target === 2 && this.bottomNavIndex === 1);

    if (albumMeSwitch) {
      const towardMe = target === 2;
      const outPx = towardMe ? -22 : 22;
      this.getUIContext().animateTo(
        { duration: FN_TAB_ALBUM_ME_OUT_MS, curve: FN_TAB_ALBUM_ME_CURVE },
        (): void => {
          this.contentTranslateX = outPx;
        }
      );
      setTimeout((): void => {
        this.bottomNavIndex = target;
        this.getUIContext().animateTo(
          { duration: FN_TAB_ALBUM_ME_IN_MS, curve: FN_TAB_ALBUM_ME_CURVE },
          (): void => {
            this.contentTranslateX = 0;
          }
        );
      }, Math.floor(FN_TAB_ALBUM_ME_OUT_MS * 0.55));
      return;
    }

    if (involvesHome) {
      const towardHome = target === 0;
      const outPx = towardHome ? 14 : -12;
      this.getUIContext().animateTo(
        { duration: FN_TAB_HOME_CONTENT_OUT_MS, curve: FN_TAB_HOME_CONTENT_CURVE },
        (): void => {
          this.contentTranslateX = outPx;
        }
      );
      setTimeout((): void => {
        this.bottomNavIndex = target;
        if (target === 0) {
          this.syncWebSessionSnapshotFromAppSession();
        }
        this.getUIContext().animateTo(
          { duration: FN_TAB_HOME_CONTENT_IN_MS, curve: FN_TAB_HOME_CONTENT_CURVE },
          (): void => {
            this.contentTranslateX = 0;
          }
        );
      }, Math.floor(FN_TAB_HOME_CONTENT_OUT_MS * 0.65));
      return;
    }

    this.bottomNavIndex = target;
  }

  aboutToAppear(): void {
    this.isDarkTheme = this.colorMode === 1;
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
        .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })

      SymbolGlyph(symbol)
        .fontSize(this.bottomNavIndex === idx ? 25 : 23)
        .fontColor([this.bottomNavIndex === idx
          ? $r('app.color.brand_primary')
          : $r('app.color.text_secondary')])
        .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })

      Text(label)
        .fontSize(11)
        .fontWeight(this.bottomNavIndex === idx ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.bottomNavIndex === idx
          ? $r('app.color.brand_primary')
          : $r('app.color.text_secondary'))
        .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
    }
    .layoutWeight(1)
    .height(HOME_BOTTOM_NAV_ITEM_HEIGHT_VP)
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
          FnPrimaryButton({ text: $r('app.string.back_to_login') })
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
              .visibility(this.bottomNavIndex === 0 ? Visibility.Visible : Visibility.Hidden)
              .hitTestBehavior(this.bottomNavIndex === 0 ? HitTestMode.Default : HitTestMode.None)
            if (this.bottomNavIndex === 1) {
              GalleryAlbumTab({
                baseUrl: this.snapWebBase,
                albumReloadEpoch: this.albumReloadEpoch,
                pageShowSignal: this.pageShowSignal,
                topSafeInsetVp: this.systemTopInsetVp,
                bottomSafeInsetVp: this.systemBottomInsetVp
              })
                .width('100%')
                .height('100%')
            }
            if (this.bottomNavIndex === 2) {
              MePanel({ topSafeInsetVp: this.systemTopInsetVp })
                .width('100%')
                .height('100%')
                .backgroundColor(this.isDarkTheme ? '#FF1C1C1E' : '#FFF5F5F5')
            }
          }
          .width('100%')
          .layoutWeight(1)
          .translate({ x: this.contentTranslateX, y: 0 })

          // ── 标准鸿蒙底部 Tabs 栏 ────────────────────────────────────
          Row() {
            this.tabItem(0, $r('sys.symbol.house'), $r('app.string.tab_home'))
            this.tabItem(1, $r('sys.symbol.picture'), $r('app.string.tab_album'))
            this.tabItem(2, $r('sys.symbol.person'), $r('app.string.tab_me'))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.isDarkTheme ? '#FF1C1C1E' : '#FFF5F5F5')
          .borderWidth({ top: 0.5 })
          .borderColor(this.isDarkTheme ? '#1AFFFFFF' : '#1A000000')
          .padding({
            left: HOME_BOTTOM_NAV_PAD_SIDE_VP,
            right: HOME_BOTTOM_NAV_PAD_SIDE_VP,
            top: HOME_BOTTOM_NAV_PAD_TOP_VP,
            bottom: this.bottomNavPadBottom()
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkTheme ? '#FF1C1C1E' : '#FFF5F5F5')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 12, y: 0 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: -8, y: 0 });
  }
}
