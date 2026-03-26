/**
 * 图库大图预览（独立页面）。
 *
 * 布局：顶栏（← | 计数 | 原图⊙ | ···）/ 全屏 Swiper / 底栏（分享 下载 收藏 删除）
 *
 * 注：分享功能使用 @kit.ShareKit（@hms.collaboration.systemShare）。
 * 该模块属 HarmonyOS HMS SDK，DevEco Studio + hvigor 编译时可正常解析；
 * Cursor/VS Code 静态分析器不包含 HMS SDK 路径，linter 会误报 MODULE_NOT_FOUND，
 * 这属 IDE 配置限制，不影响实际构建。
 */
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
// picker.PhotoViewPicker.save() 通过系统弹窗让用户选择保存位置，无需 WRITE_IMAGEVIDEO 等受限权限
import { fileIo, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { GalleryPreviewSlide } from '../album/GalleryPreviewSlide';
import { GalleryPreviewNavStore } from '../album/GalleryPreviewNavStore';
import { GalleryListItem } from '../model/FnApiTypes';
import { isVideoItem, nasUrl, pickOriginal, pickThumb } from '../album/GalleryAlbumCommon';
import { AppSession } from '../auth/AppSession';

/** 与 LazyForEach 配套的轻量数据源 */
interface PreviewDataChangeListener {
  onDataReloaded(): void;
}

class PreviewItemsDataSource {
  private items: GalleryListItem[] = [];
  private listeners: PreviewDataChangeListener[] = [];

  totalCount(): number { return this.items.length; }
  getData(index: number): GalleryListItem { return this.items[index]; }

  registerDataChangeListener(listener: PreviewDataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: PreviewDataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) { this.listeners.splice(i, 1); }
  }
  reloadAll(list: GalleryListItem[]): void {
    this.items = list;
    this.listeners.forEach((l): void => { l.onDataReloaded(); });
  }
}

@Entry
@Component
struct GalleryPreview {
  @State private baseUrl: string = '';
  @State private swiperIndex: number = 0;
  @State private swiperLocked: boolean = false;
  @State private totalCount: number = 0;
  @State private dismissDragProgress: number = 0;
  @State private toolbarVisible: boolean = true;
  @State private loadOriginalReq: boolean = false;
  @State private downloading: boolean = false;
  @State private sharing: boolean = false;
  /** 当前图片是否已切换到原图（用于隐藏"原图"按钮） */
  @State private originalShowing: boolean = false;
  /**
   * 系统深浅色模式（框架自动写入 AppStorage 'colorMode'）：
   * ColorMode.LIGHT = 0，ColorMode.DARK = 1
   */
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  /**
   * 用 @State 显式保存深色标志，确保模式切换时 build() 一定被重触发。
   * （@StorageProp 在多层方法链调用中依赖追踪可能丢失，@State 变更则必定重渲染）
   */
  @State private isDarkTheme: boolean = false;

  private itemSource: PreviewItemsDataSource = new PreviewItemsDataSource();

  // ── 生命周期 ──────────────────────────────────────────────────────────────

  onPageShow(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar();
  }

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar();
  }

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  aboutToAppear(): void {
    this.baseUrl = GalleryPreviewNavStore.baseUrl;
    this.itemSource.reloadAll(GalleryPreviewNavStore.items);
    this.totalCount = GalleryPreviewNavStore.items.length;
    this.swiperIndex = GalleryPreviewNavStore.startIndex;
    this.isDarkTheme = this.colorMode === 1;
    const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
    if (rp !== undefined && rp['idx'] !== undefined) {
      const n = Number(rp['idx']);
      if (Number.isFinite(n) && n >= 0 && n < this.totalCount) {
        this.swiperIndex = Math.floor(n);
      }
    }
  }

  aboutToDisappear(): void {
    GalleryPreviewNavStore.clear();
  }

  // ── 系统栏颜色 ────────────────────────────────────────────────────────────

  private applySystemBar(): void {
    try {
      const dark = this.colorMode === 1;
      const bg = dark ? '#FF000000' : '#FFF5F5F5';
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

  // ── 颜色辅助（基于 @State isDarkTheme，保证重渲染时颜色同步） ─────────────

  private isDark(): boolean { return this.isDarkTheme; }

  /**
   * 页面背景色：与工具栏颜色保持一致，确保小白条区域（底部安全区域）颜色统一。
   * 浅色模式使用 #F5F5F5（与工具栏相同），深色使用纯黑。
   */
  private pageBg(): string { return this.isDark() ? '#FF000000' : '#FFF5F5F5'; }

  /** 工具栏底色（完全不透明） */
  private toolbarBg(): string { return this.isDark() ? '#FF000000' : '#FFF5F5F5'; }

  /** 工具栏前景色（文字/图标） */
  private fgColor(): ResourceColor { return this.isDark() ? Color.White : Color.Black; }

  /** 圆形按钮背景色 */
  private btnBg(): string { return this.isDark() ? '#33FFFFFF' : '#22000000'; }

  // ── 工具 ─────────────────────────────────────────────────────────────────

  /** PromptAction.showToast 标注了 @throws，统一包裹消除 ArkTS 警告 */
  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {}
  }

  private currentItem(): GalleryListItem | null {
    if (this.totalCount === 0 || this.swiperIndex >= this.totalCount) { return null; }
    return this.itemSource.getData(this.swiperIndex);
  }

  private currentHasOriginal(): boolean {
    const item = this.currentItem();
    if (item === null) { return false; }
    return pickOriginal(item).length > 0 && !isVideoItem(item);
  }

  private titleCounter(): string {
    return this.totalCount > 0 ? `${this.swiperIndex + 1} / ${this.totalCount}` : '';
  }

  private toolbarAlpha(): number {
    return Math.max(0, 1 - this.dismissDragProgress * 1.5);
  }

  private toggleToolbar(): void {
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, (): void => {
      this.toolbarVisible = !this.toolbarVisible;
    });
  }

  /** 获取当前图片 buffer，useOriginal=true 优先原图，false 只取缩略图 */
  private async fetchCurrentImageBuffer(useOriginal: boolean = true): Promise<ArrayBuffer | undefined> {
    const item = this.currentItem();
    if (item === null) { return undefined; }
    const origUrl = nasUrl(this.baseUrl, pickOriginal(item));
    const thumbUrl = nasUrl(this.baseUrl, pickThumb(item));
    let imgUrl = '';
    if (useOriginal && origUrl.length > 0) {
      imgUrl = origUrl;
    } else if (thumbUrl.length > 0) {
      imgUrl = thumbUrl;
    }
    if (imgUrl.length === 0) { return undefined; }
    const client = AppSession.getClient();
    if (client === null) { return undefined; }
    // 原图给更长超时（60s），缩略图 15s 足够
    return client.fetchGalleryImageBuffer(imgUrl, useOriginal ? 60000 : 15000);
  }

  // ── 下载 ─────────────────────────────────────────────────────────────────

  private downloadCurrentImage(): void {
    if (this.downloading) { return; }
    this.downloading = true;
    void this.doDownload().finally((): void => {
      this.downloading = false;
    });
  }

  private async doDownload(): Promise<void> {
    // ① 若有原图可选，弹出质量选择菜单（本地 UI，立即响应）
    let useOriginal = false;
    if (this.currentHasOriginal()) {
      try {
        const choice = await this.getUIContext().getPromptAction().showActionMenu({
          title: '选择下载质量',
          buttons: [
            { text: '原图（高清）', color: '#007AFF' },
            { text: '缩略图（较小）', color: '#007AFF' }
          ]
        });
        useOriginal = choice.index === 0;
      } catch (_e) {
        // 用户按返回键取消
        return;
      }
    }

    // ② 立即弹出系统保存面板，用户选择保存位置
    let saveUri = '';
    try {
      const saveOptions = new picker.PhotoSaveOptions();
      saveOptions.newFileNames = [`photo_${Date.now()}.jpg`];
      const uris = await new picker.PhotoViewPicker().save(saveOptions);
      if (uris.length === 0) {
        this.toast('已取消保存');
        return;
      }
      saveUri = uris[0];
    } catch (_e) {
      this.toast('保存取消');
      return;
    }

    // ③ 用户已选择目标位置，按所选质量下载并写入
    const buf = await this.fetchCurrentImageBuffer(useOriginal);
    if (buf === undefined || buf.byteLength === 0) {
      this.toast('图片加载失败，请重试');
      return;
    }

    try {
      const saveFile = await fileIo.open(saveUri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
      await fileIo.write(saveFile.fd, buf);
      await fileIo.close(saveFile.fd);
      this.toast(useOriginal ? '原图已保存到相册' : '缩略图已保存到相册');
    } catch (_e) {
      this.toast('写入失败，请重试');
    }
  }

  // ── 分享（HarmonyOS systemShare） ─────────────────────────────────────────

  private shareCurrentImage(): void {
    if (this.sharing) { return; }
    this.sharing = true;
    void this.doShare().finally((): void => {
      this.sharing = false;
    });
  }

  private async doShare(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;

    const buf = await this.fetchCurrentImageBuffer();
    if (buf === undefined || buf.byteLength === 0) {
      this.toast('图片加载失败，请重试');
      return;
    }

    // 写入临时缓存文件，供系统分享面板读取
    const tempPath = `${ctx.cacheDir}/share_preview.jpg`;
    try {
      const tmpFile = fileIo.openSync(tempPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(tmpFile.fd, buf);
      fileIo.closeSync(tmpFile.fd);
    } catch (_e) {
      this.toast('临时文件写入失败');
      return;
    }

    try {
      // 调起鸿蒙官方系统分享面板（@kit.ShareKit / @hms.collaboration.systemShare）
      const record: systemShare.SharedRecord = {
        utd: 'general.image',
        uri: `file://${tempPath}`,
        title: '分享图片'
      };
      const shareData = new systemShare.SharedData(record);
      const ctrl = new systemShare.ShareController(shareData);
      await ctrl.show(ctx, {
        selectionMode: 0,
        previewMode: systemShare.SharePreviewMode.DETAIL
      });
    } catch (_e) {
      this.toast('分享失败，请重试');
    }
  }

  // ── Builder ───────────────────────────────────────────────────────────────

  @Builder
  bottomAction(icon: Resource, label: string, loading: boolean, action: () => void, dimmed: boolean = false) {
    Column({ space: 4 }) {
      if (loading) {
        LoadingProgress().width(26).height(26).color(this.fgColor())
      } else {
        SymbolGlyph(icon).fontSize(26).fontColor([dimmed ? '#888888' : this.fgColor()])
      }
      Text(label).fontSize(11).fontColor(dimmed ? '#888888' : this.fgColor())
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14 })
    .alignItems(HorizontalAlign.Center)
    .onClick(dimmed ? (): void => {} : action)
  }

  // ── build ─────────────────────────────────────────────────────────────────

  build() {
    Stack() {

      // ── 内容区（Swiper 铺满整个屏幕，包括工具栏背后区域） ──────────────────
      if (this.totalCount > 0) {
        Swiper() {
          LazyForEach(this.itemSource, (item: GalleryListItem, idx: number) => {
            GalleryPreviewSlide({
              baseUrl: this.baseUrl,
              item: item,
              loadOriginalReq: this.loadOriginalReq,
              onZoomLockChange: (locked: boolean): void => { this.swiperLocked = locked; },
              onVerticalDragProgress: (p: number): void => {
                this.dismissDragProgress = Math.max(0, Math.min(1, p));
              },
              onVerticalDismiss: (): void => { this.getUIContext().getRouter().back(); },
              onOriginalLoaded: (): void => { this.originalShowing = true; }
            })
          }, (_item: GalleryListItem, i: number) => `gp_slide_${i}`)
        }
        .width('100%').height('100%')
        .index(this.swiperIndex).indicator(false).loop(false)
        .duration(300).curve(Curve.EaseInOut).cachedCount(2)
        .disableSwipe(this.swiperLocked)
        .onClick((): void => { this.toggleToolbar(); })
        .onChange((idx: number): void => {
          this.swiperIndex = idx;
          this.dismissDragProgress = 0;
          this.loadOriginalReq = false;
          this.originalShowing = false;
          if (!this.toolbarVisible) {
            this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, (): void => {
              this.toolbarVisible = true;
            });
          }
        })
      } else {
        Column() {
          Text('暂无预览').fontSize(16).fontColor('#CCCCCC')
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      }

      // ── 工具栏叠层（覆盖在 Swiper 上方）──────────────────────────────────
      // hitTestBehavior.Transparent：点击穿透到下层 Swiper；
      // 顶/底栏 Row 本身会吸收对其区域的点击，中间透明 Blank 则传递到 Swiper。
      Column() {

        // 顶部工具栏
        Row() {
          // 左侧区域（固定 88px，与右侧等宽，确保标题真正居中）
          Row() {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.chevron_backward')).fontSize(22).fontColor([this.fgColor()])
            }
            .width(40).height(40).backgroundColor(this.btnBg())
            .onClick((): void => { this.getUIContext().getRouter().back(); })
          }
          .width(88).justifyContent(FlexAlign.Start)

          // 居中标题
          Text(this.titleCounter())
            .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.fgColor())
            .layoutWeight(1).textAlign(TextAlign.Center)

          // 右侧区域（固定 88px）：原图（已加载后消失）+ 更多
          Row({ space: 8 }) {
            if (this.currentHasOriginal() && !this.originalShowing) {
              Button({ type: ButtonType.Circle, stateEffect: true }) {
                SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(20).fontColor([this.fgColor()])
              }
              .width(40).height(40).backgroundColor(this.btnBg())
              .onClick((): void => { this.loadOriginalReq = true; })
            }
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.more')).fontSize(20).fontColor([this.fgColor()])
            }
            .width(40).height(40).backgroundColor(this.btnBg())
          }
          .width(88).justifyContent(FlexAlign.End)
        }
        .width('100%').height(56)
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.toolbarBg())

        // 中间透明区域：点击穿透到 Swiper
        Blank().layoutWeight(1)

        // 底部工具栏
        Row() {
          this.bottomAction($r('sys.symbol.share'), '分享', this.sharing,
            (): void => { this.shareCurrentImage(); })
          this.bottomAction($r('sys.symbol.download'), '下载', this.downloading,
            (): void => { this.downloadCurrentImage(); })
          this.bottomAction($r('sys.symbol.star'), '收藏', false, (): void => {}, true)
          this.bottomAction($r('sys.symbol.trash'), '删除', false, (): void => {}, true)
        }
        .width('100%')
        .backgroundColor(this.toolbarBg())

      }
      .width('100%').height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .opacity(this.toolbarVisible ? this.toolbarAlpha() : 0)
      .animation({ duration: 220, curve: Curve.EaseInOut })

    }
    .width('100%').height('100%')
    .backgroundColor(this.pageBg())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: 240, curve: Curve.EaseOut })
      .opacity(0).scale({ x: 0.95, y: 0.95 })
    PageTransitionExit({ duration: 200, curve: Curve.EaseIn })
      .opacity(0).scale({ x: 0.95, y: 0.95 })
  }
}
