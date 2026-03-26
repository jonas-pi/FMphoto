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
import { fileIo, picker, fileUri as fileUriUtil } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { GalleryPreviewSlide } from '../album/GalleryPreviewSlide';
import { GalleryPreviewNavStore } from '../album/GalleryPreviewNavStore';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import { GalleryListItem, GalleryPhotoDetailData } from '../model/FnApiTypes';
import { isVideoItem, itemFileExt, nasUrl, pickOriginal, pickThumb, pickVideo } from '../album/GalleryAlbumCommon';
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
  /** 右上角详情面板开关 */
  @State private detailsVisible: boolean = false;
  /** 详情请求加载态 */
  @State private detailsLoading: boolean = false;
  /** 详情错误文案 */
  @State private detailsError: string = '';
  /** 当前已加载详情数据 */
  @State private detailsData: GalleryPhotoDetailData | undefined = undefined;
  /** 详情数据对应的 photoId，用于避免重复请求 */
  @State private detailsPhotoId: string = '';
  /** 详情里点击路径后，正在加载同目录媒体 */
  @State private folderOpening: boolean = false;
  /** 底部工具栏实测高度（初始值 80vp 防止第一帧进度条与按钮重叠，onAreaChange 后更新为实测值） */
  @State private bottomBarHeight: number = 80;
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
    const client = AppSession.getClient();
    if (client !== null) {
      client.cancelPendingRequests();
    }
    GalleryPreviewNavStore.clear();
  }

  // ── 系统栏颜色 ────────────────────────────────────────────────────────────

  private applySystemBar(): void {
    try {
      // 状态栏/导航栏始终跟随系统深浅色，不再按视频页强制纯黑
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

  /** 工具栏底色：视频页始终深色半透明（与黑色视频背景保持一致），图片页跟随系统主题 */
  private toolbarBg(): string {
    if (this.currentItemIsVideo()) { return '#CC000000'; }
    return this.isDark() ? '#FF000000' : '#FFF5F5F5';
  }

  /** 工具栏前景色（文字/图标）：视频页工具栏始终深色背景，前景色强制白色 */
  private fgColor(): ResourceColor {
    if (this.currentItemIsVideo()) { return Color.White; }
    return this.isDark() ? Color.White : Color.Black;
  }

  /** 圆形按钮背景色：视频页工具栏始终深色，按钮用亮色遮罩 */
  private btnBg(): string {
    if (this.currentItemIsVideo()) { return '#33FFFFFF'; }
    return this.isDark() ? '#33FFFFFF' : '#22000000';
  }

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

  private currentItemIsVideo(): boolean {
    const item = this.currentItem();
    return item !== null && isVideoItem(item);
  }

  /** 当前条目的 photoId（用于请求 getOne 详情） */
  private currentItemId(): string {
    const item = this.currentItem();
    if (item === null || item.id === undefined || item.id === null) {
      return '';
    }
    const id = String(item.id).trim();
    return id.length > 0 ? id : '';
  }

  private currentHasOriginal(): boolean {
    const item = this.currentItem();
    if (item === null) { return false; }
    return pickOriginal(item).length > 0 && !isVideoItem(item);
  }

  private currentImageExt(): string {
    const item = this.currentItem();
    if (item === null) { return 'jpg'; }
    const ext = itemFileExt(item);
    if (ext === 'gif') { return 'gif'; }
    if (ext === 'png') { return 'png'; }
    if (ext === 'webp') { return 'webp'; }
    return 'jpg';
  }

  /** 当前视频扩展名（用于下载文件名）；未知时回退 mp4 */
  private currentVideoExt(): string {
    const item = this.currentItem();
    if (item === null) { return 'mp4'; }
    const ext = itemFileExt(item);
    if (ext === 'mp4' || ext === 'mov' || ext === 'm4v' || ext === 'mkv' || ext === 'avi' || ext === 'webm') {
      return ext;
    }
    return 'mp4';
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

  /** 打开右上角详情面板（按当前媒体请求 /gallery/getOne） */
  private openDetailsPanel(): void {
    const id = this.currentItemId();
    if (id.length === 0) {
      this.toast('当前媒体无详情 ID');
      return;
    }
    this.detailsVisible = true;
    this.detailsError = '';
    if (this.detailsData !== undefined && this.detailsPhotoId === id) {
      return;
    }
    this.detailsLoading = true;
    this.detailsData = undefined;
    void this.loadPhotoDetails(id).finally((): void => {
      this.detailsLoading = false;
    });
  }

  private async loadPhotoDetails(photoId: string): Promise<void> {
    const client = AppSession.getClient();
    if (client === null) {
      this.detailsError = '未登录';
      return;
    }
    const res = await client.getGalleryPhotoDetail(photoId, 15000);
    if (!res.success || res.data === undefined) {
      this.detailsError = res.message ?? '详情加载失败';
      return;
    }
    this.detailsData = res.data;
    this.detailsPhotoId = photoId;
  }

  private closeDetailsPanel(): void {
    this.detailsVisible = false;
  }

  private detailText(v: string | number | undefined): string {
    if (v === undefined || v === null) {
      return '';
    }
    const s = String(v).trim();
    return s.length > 0 ? s : '';
  }

  /** 文件体积格式化（B/KB/MB） */
  private formatBytes(v: string | number | undefined): string {
    const raw = this.detailText(v);
    if (raw.length === 0) {
      return '';
    }
    const n = Number(raw);
    if (!Number.isFinite(n) || n < 0) {
      return raw;
    }
    if (n < 1024) {
      return `${Math.floor(n)} B`;
    }
    if (n < 1024 * 1024) {
      return `${(n / 1024).toFixed(1)} KB`;
    }
    if (n < 1024 * 1024 * 1024) {
      return `${(n / (1024 * 1024)).toFixed(2)} MB`;
    }
    return `${(n / (1024 * 1024 * 1024)).toFixed(2)} GB`;
  }

  /** 将输入值解析为字节数；无法解析时返回 undefined */
  private parseBytes(v: string | number | undefined): number | undefined {
    const raw = this.detailText(v);
    if (raw.length === 0) {
      return undefined;
    }
    const n = Number(raw);
    if (!Number.isFinite(n) || n < 0) {
      return undefined;
    }
    return Math.floor(n);
  }

  /** 当前条目原文件大小（优先 originalSize，再退回 fileSize） */
  private currentOriginalSizeBytes(): number | undefined {
    const item = this.currentItem();
    if (item === null) {
      return undefined;
    }
    const orig = this.parseBytes(item.originalSize);
    if (orig !== undefined) {
      return orig;
    }
    return this.parseBytes(item.fileSize);
  }

  /** 菜单展示用大小标签 */
  private qualitySizeLabel(bytes: number | undefined): string {
    if (bytes === undefined) {
      return '大小未知';
    }
    return this.formatBytes(bytes);
  }

  /** 组装双值文本；任一为空时返回另一个，均为空返回空串 */
  private joinPair(left: string, right: string, sep: string): string {
    if (left.length > 0 && right.length > 0) {
      return `${left}${sep}${right}`;
    }
    if (left.length > 0) {
      return left;
    }
    if (right.length > 0) {
      return right;
    }
    return '';
  }

  /** 从文件完整路径中提取目录路径（去掉最后一级文件名） */
  private parentFolderPath(fullPath: string): string {
    const p = fullPath.trim();
    if (p.length === 0) {
      return '';
    }
    const idx = p.lastIndexOf('/');
    if (idx <= 0) {
      return '';
    }
    return p.substring(0, idx);
  }

  /**
   * 标题路径压缩：
   * - 层级 <= 3：完整显示
   * - 层级 > 3：显示「最父一层 / ... / 最末两层」
   * 例：/a/b/c/d/e -> /a/.../d/e
   */
  private compactFolderTitle(folderPath: string): string {
    const p = folderPath.trim();
    if (p.length === 0) {
      return '文件夹';
    }
    const partsRaw = p.split('/');
    const parts: string[] = [];
    for (let i = 0; i < partsRaw.length; i++) {
      const seg = partsRaw[i].trim();
      if (seg.length > 0) {
        parts.push(seg);
      }
    }
    if (parts.length === 0) {
      return p;
    }
    if (parts.length <= 3) {
      return `/${parts.join('/')}`;
    }
    const first = parts[0];
    const last1 = parts[parts.length - 2];
    const last2 = parts[parts.length - 1];
    return `/${first}/.../${last1}/${last2}`;
  }

  /** 点击详情里的文件路径，打开该目录下所有媒体 */
  private openFolderFromDetailPath(): void {
    if (this.folderOpening) {
      return;
    }
    const rawPath = this.detailText(this.detailsData?.filePath ?? this.detailsData?.showFilePath);
    const folderPath = this.parentFolderPath(rawPath);
    if (folderPath.length === 0) {
      this.toast('文件路径不可用');
      return;
    }
    this.folderOpening = true;
    void this.fetchAndOpenFolderMedia(folderPath).finally((): void => {
      this.folderOpening = false;
    });
  }

  private async fetchAndOpenFolderMedia(folderPath: string): Promise<void> {
    const client = AppSession.getClient();
    if (client === null) {
      this.toast('未登录');
      return;
    }
    // 直接分页拉取：避免 limit=-1 在部分 NAS 上等待过久导致“看起来加载不出来”
    const all: GalleryListItem[] = [];
    const pageSize = 100;
    let offset = 0;
    let rounds = 0;
    while (rounds < 200) {
      const res = await client.getFolderViewFileList(folderPath, pageSize, offset, false, 2, 20000);
      if (!res.success || res.data === undefined) {
        this.toast(res.message ?? '文件夹媒体加载失败');
        return;
      }
      const list = res.data;
      if (list.length === 0) {
        break;
      }
      for (let i = 0; i < list.length; i++) {
        all.push(list[i]);
      }
      offset += list.length;
      rounds++;
      if (list.length < pageSize) {
        break;
      }
    }
    if (all.length === 0) {
      this.toast('该文件夹暂无可预览媒体');
      return;
    }

    this.detailsVisible = false;
    CategoryGalleryNavStore.open(
      this.baseUrl,
      this.compactFolderTitle(folderPath),
      all,
      this.getUIContext()
    );
  }

  @Builder
  private detailRow(label: string, value: string) {
    if (value.length > 0) {
      Row({ space: 10 }) {
        Text(label)
          .fontSize(13)
          .fontColor(this.isDark() ? '#FF8E8E93' : '#FF6E6E73')
          .width(92)
        Text(value)
          .fontSize(13)
          .fontColor(this.isDark() ? '#FFF2F2F7' : '#FF1C1C1E')
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 6, bottom: 6 })
    }
  }

  @Builder
  private detailPathRow(label: string, fullPath: string) {
    if (fullPath.length > 0) {
      Row({ space: 10 }) {
        Text(label)
          .fontSize(13)
          .fontColor(this.isDark() ? '#FF8E8E93' : '#FF6E6E73')
          .width(92)
        Column({ space: 4 }) {
          Text(fullPath)
            .fontSize(13)
            .fontColor(this.isDark() ? '#FF78A6FF' : '#FF0A63D8')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.folderOpening ? '正在打开同目录媒体...' : '点击打开同目录媒体')
            .fontSize(11)
            .fontColor(this.isDark() ? '#FF8E8E93' : '#FF6E6E73')
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 6, bottom: 6 })
      .onClick((): void => {
        this.openFolderFromDetailPath();
      })
    }
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

  /** 获取当前视频 buffer（直链视频流，不再走图片缩略图/原图链路） */
  private async fetchCurrentVideoBuffer(): Promise<ArrayBuffer | undefined> {
    const item = this.currentItem();
    if (item === null) { return undefined; }
    const videoUrl = nasUrl(this.baseUrl, pickVideo(item));
    if (videoUrl.length === 0) { return undefined; }
    const client = AppSession.getClient();
    if (client === null) { return undefined; }
    // 视频下载通常更大，给更长超时
    return client.fetchGalleryImageBuffer(videoUrl, 120000);
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
    const isVideo = this.currentItemIsVideo();

    // ① 图片：若有原图可选，弹出质量选择菜单（本地 UI，立即响应）
    //    视频：不弹质量选择，直接下载原视频文件。
    let useOriginal = false;
    // 为了在菜单中展示更准确大小，预取缩略图大小；并复用已取的 buffer，避免重复网络请求。
    let prefetchedOriginal: ArrayBuffer | undefined = undefined;
    let prefetchedThumb: ArrayBuffer | undefined = undefined;
    if (!isVideo && this.currentHasOriginal()) {
      let originalBytes = this.currentOriginalSizeBytes();
      let thumbBytes: number | undefined = undefined;
      // 缩略图体积通常较小，先取一次用于菜单文案与后续下载复用
      prefetchedThumb = await this.fetchCurrentImageBuffer(false);
      if (prefetchedThumb !== undefined && prefetchedThumb.byteLength > 0) {
        thumbBytes = prefetchedThumb.byteLength;
      } else {
        prefetchedThumb = undefined;
      }
      // 若列表未下发原图体积，则补一次原图大小估算
      if (originalBytes === undefined) {
        prefetchedOriginal = await this.fetchCurrentImageBuffer(true);
        if (prefetchedOriginal !== undefined && prefetchedOriginal.byteLength > 0) {
          originalBytes = prefetchedOriginal.byteLength;
        } else {
          prefetchedOriginal = undefined;
        }
      }
      try {
        const choice = await this.getUIContext().getPromptAction().showActionMenu({
          title: '选择下载质量',
          buttons: [
            { text: `原图（${this.qualitySizeLabel(originalBytes)}）`, color: '#007AFF' },
            { text: `缩略图（${this.qualitySizeLabel(thumbBytes)}）`, color: '#007AFF' }
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
      const ext = isVideo ? this.currentVideoExt() : this.currentImageExt();
      saveOptions.newFileNames = [`${isVideo ? 'video' : 'photo'}_${Date.now()}.${ext}`];
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

    // ③ 用户已选择目标位置，按媒体类型下载并写入
    let buf: ArrayBuffer | undefined;
    if (isVideo) {
      buf = await this.fetchCurrentVideoBuffer();
    } else if (useOriginal) {
      buf = prefetchedOriginal !== undefined ? prefetchedOriginal : await this.fetchCurrentImageBuffer(true);
    } else {
      buf = prefetchedThumb !== undefined ? prefetchedThumb : await this.fetchCurrentImageBuffer(false);
    }
    if (buf === undefined || buf.byteLength === 0) {
      this.toast(isVideo ? '视频加载失败，请重试' : '图片加载失败，请重试');
      return;
    }

    try {
      const saveFile = await fileIo.open(saveUri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
      await fileIo.write(saveFile.fd, buf);
      await fileIo.close(saveFile.fd);
      if (isVideo) {
        this.toast('视频已保存到相册');
      } else {
        this.toast(useOriginal ? '原图已保存到相册' : '缩略图已保存到相册');
      }
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
    const isVideo = this.currentItemIsVideo();

    const buf = isVideo
      ? await this.fetchCurrentVideoBuffer()
      : await this.fetchCurrentImageBuffer();
    if (buf === undefined || buf.byteLength === 0) {
      this.toast(isVideo ? '视频加载失败，请重试' : '图片加载失败，请重试');
      return;
    }

    // 写入临时缓存文件，供系统分享面板读取（按媒体类型区分后缀）
    const ext = isVideo ? this.currentVideoExt() : this.currentImageExt();
    const tempPath = `${ctx.cacheDir}/share_preview.${ext}`;
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
      // 调起鸿蒙官方系统分享面板（@kit.ShareKit）
      // 使用 fileUri.getUriFromPath 生成系统可访问的正确 URI 格式
      const shareUri = fileUriUtil.getUriFromPath(tempPath);
      const record: systemShare.SharedRecord = {
        utd: isVideo ? 'general.video' : 'general.image',
        uri: shareUri,
        title: isVideo ? '分享视频' : '分享图片'
      };
      const shareData = new systemShare.SharedData(record);
      const ctrl = new systemShare.ShareController(shareData);
      await ctrl.show(ctx, {
        selectionMode: systemShare.SelectionMode.SINGLE,
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
    // 双重守卫：dimmed 置灰 + 工具栏不可见时均不响应，防止进度条操作误触下载
    .onClick((dimmed || !this.toolbarVisible) ? (): void => {} : action)
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
              active: idx === this.swiperIndex,
              videoBottomPadding: this.toolbarVisible ? this.bottomBarHeight : 0,
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
          // 切换媒体类型时（图片↔视频）重新同步系统栏颜色
          this.applySystemBar();
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
                // “查看原图”使用图片语义图标，避免与“下载”动作混淆
                SymbolGlyph($r('sys.symbol.picture')).fontSize(20).fontColor([this.fgColor()])
              }
              .width(40).height(40).backgroundColor(this.btnBg())
              .onClick((): void => { this.loadOriginalReq = true; })
            }
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.more')).fontSize(20).fontColor([this.fgColor()])
            }
            .width(40).height(40).backgroundColor(this.btnBg())
            .onClick((): void => { this.openDetailsPanel(); })
          }
          .width(88).justifyContent(FlexAlign.End)
        }
        .width('100%').height(56)
        .padding({ left: 8, right: 8 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.toolbarBg())
        .hitTestBehavior(this.toolbarVisible ? HitTestMode.Default : HitTestMode.None)

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
        .hitTestBehavior(this.toolbarVisible ? HitTestMode.Default : HitTestMode.None)
        .onAreaChange((_old, area): void => {
          const h = area.height as number;
          if (h > 0) { this.bottomBarHeight = h; }
        })

      }
      .width('100%').height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .opacity(this.toolbarVisible ? this.toolbarAlpha() : 0)
      .animation({ duration: 220, curve: Curve.EaseInOut })

      // 详情底部弹层：由右上角「更多」按钮触发
      if (this.detailsVisible) {
        Column() {
          Blank()
            .layoutWeight(1)
            .onClick((): void => { this.closeDetailsPanel(); })

          Column() {
            Row() {
              Text('照片详情')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isDark() ? '#FFF2F2F7' : '#FF1C1C1E')
              Blank()
              Button('关闭', { type: ButtonType.Normal, stateEffect: true })
                .fontSize(13)
                .height(30)
                .padding({ left: 10, right: 10 })
                .backgroundColor(this.isDark() ? '#33FFFFFF' : '#12000000')
                .fontColor(this.isDark() ? '#FFF2F2F7' : '#FF1C1C1E')
                .onClick((): void => { this.closeDetailsPanel(); })
            }
            .width('100%')
            .margin({ bottom: 8 })

            if (this.detailsLoading) {
              Row({ space: 10 }) {
                LoadingProgress().width(22).height(22).color(this.fgColor())
                Text('详情加载中…')
                  .fontSize(13)
                  .fontColor(this.isDark() ? '#FF8E8E93' : '#FF6E6E73')
              }
              .width('100%')
              .padding({ top: 18, bottom: 20 })
            } else if (this.detailsError.length > 0) {
              Text(this.detailsError)
                .fontSize(13)
                .fontColor('#FFE0483E')
                .width('100%')
                .padding({ top: 12, bottom: 16 })
            } else {
              Scroll() {
                Column() {
                  this.detailRow('文件名', this.detailText(this.detailsData?.fileName))
                  this.detailRow('拍摄时间', this.detailText(this.detailsData?.photoDateTime ?? this.detailsData?.dateTime))
                  this.detailRow('文件类型', this.detailText(this.detailsData?.fileType))
                  this.detailRow('文件大小', this.formatBytes(this.detailsData?.fileSize))
                  this.detailRow(
                    '分辨率',
                    this.joinPair(
                      this.detailText(this.detailsData?.width),
                      this.detailText(this.detailsData?.height),
                      ' x '
                    )
                  )
                  this.detailRow('设备厂商', this.detailText(this.detailsData?.make))
                  this.detailRow('设备型号', this.detailText(this.detailsData?.model))
                  this.detailRow('光圈', this.detailText(this.detailsData?.fumber))
                  this.detailRow('快门', this.detailText(this.detailsData?.exposureTime))
                  this.detailRow('ISO', this.detailText(this.detailsData?.isoSpeedRatings))
                  this.detailRow('焦距', this.detailText(this.detailsData?.focalLength))
                  this.detailRow('像素', this.detailText(this.detailsData?.mp))
                  this.detailRow('曝光程序', this.detailText(this.detailsData?.exposureProgram))
                  this.detailRow('测光模式', this.detailText(this.detailsData?.meteringMode))
                  this.detailRow('地理位置', this.detailText(this.detailsData?.geo))
                  this.detailRow(
                    '经纬度',
                    this.joinPair(
                      this.detailText(this.detailsData?.latitude),
                      this.detailText(this.detailsData?.longitude),
                      ', '
                    )
                  )
                  this.detailPathRow('文件路径', this.detailText(this.detailsData?.filePath ?? this.detailsData?.showFilePath))
                }
                .width('100%')
                .padding({ bottom: 10 })
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .scrollBar(BarState.Auto)
            }
          }
          .width('100%')
          .constraintSize({ maxHeight: '70%' })
          .padding({ left: 14, right: 14, top: 14, bottom: 18 })
          .backgroundColor(this.isDark() ? '#FF1C1C1E' : '#FFFFFFFF')
          .borderRadius({ topLeft: 16, topRight: 16 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
      }

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
