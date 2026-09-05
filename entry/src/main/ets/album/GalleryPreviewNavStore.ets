/**
 * 进入独立预览页前写入会话数据（路由 params 不宜携带大列表）。
 * 退出预览页后应 clear，释放引用。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UIContext } from '@kit.ArkUI';
import { GalleryListItem } from '../model/FnApiTypes';
import {
  GalleryPreviewEntryCache,
  cancelVideoWarmup,
  setGalleryPreviewOpening,
  warmupPreviewStartItem
} from './GalleryPreviewEntryGate';
import {
  GALLERY_PREVIEW_SOURCE_HOME_ID,
  gallerySharedSourceDomId,
  setGalleryPreviewHeroActive
} from './GallerySharedTransition';
import { GallerySlideshowStreamStore } from './slideshow/GallerySlideshowStreamStore';

const DOMAIN = 0xFF00;
const TAG = 'GalleryNav';

/** 幻灯片模式会话：进入预览页时读取，退出后清零 */
export class GalleryPreviewSlideshowSession {
  enabled: boolean = false;
  intervalMs: number = 5000;
  /** 时间轴统计的全库媒体总数（用于顶栏计数，非当前已加载队列长度） */
  libraryTotalCount: number = 0;
}

export class GalleryPreviewNavStore {
  static baseUrl: string = '';
  static items: GalleryListItem[] = [];
  static startIndex: number = 0;
  static slideshow: GalleryPreviewSlideshowSession = new GalleryPreviewSlideshowSession();
  /** 与 items 对齐：每条在图库时间轴全局序列中的下标（0-based） */
  static slideshowGlobalIndices: number[] = [];
  /** 打开预览的页面根节点，用于判断关闭预览后是否已有可复用的同层页面。 */
  static sourceRootId: string = GALLERY_PREVIEW_SOURCE_HOME_ID;
  /** 预览下滑时显示的上一级页面快照；预览实例取得引用后由 clear 释放 Store 引用。 */
  static sourcePageSnapshot: PixelMap | undefined = undefined;
  /** 被点击缩略图相对快照根节点的像素矩形；预览页据此覆盖空白占位。 */
  static sourcePlaceholderX: number = 0;
  static sourcePlaceholderY: number = 0;
  static sourcePlaceholderW: number = 0;
  static sourcePlaceholderH: number = 0;
  private static opening: boolean = false;
  private static openGen: number = 0;
  private static lastEnterTs: number = 0;
  /** 独立于 opening：pushUrl resolve 后 opening 立即复位，连点仍可能双压栈 */
  private static readonly ENTER_DEBOUNCE_MS: number = 400;

  static openPreview(
    uiCtx: UIContext,
    baseUrl: string,
    items: GalleryListItem[],
    startIndex: number,
    sourceRootId: string = GALLERY_PREVIEW_SOURCE_HOME_ID
  ): void {
    const now = Date.now();
    if (now - GalleryPreviewNavStore.lastEnterTs < GalleryPreviewNavStore.ENTER_DEBOUNCE_MS) {
      return;
    }
    GalleryPreviewNavStore.lastEnterTs = now;
    void GalleryPreviewNavStore.openPreviewWhenReady(uiCtx, baseUrl, items, startIndex, sourceRootId);
  }

  private static async openPreviewWhenReady(
    uiCtx: UIContext,
    baseUrl: string,
    items: GalleryListItem[],
    startIndex: number,
    sourceRootId: string
  ): Promise<void> {
    if (GalleryPreviewNavStore.opening) {
      return;
    }
    GalleryPreviewNavStore.resetSlideshow();
    GalleryPreviewNavStore.baseUrl = baseUrl;
    GalleryPreviewNavStore.items = items.slice();
    GalleryPreviewNavStore.sourceRootId = sourceRootId;
    const n = GalleryPreviewNavStore.items.length;
    GalleryPreviewNavStore.startIndex = n <= 0 ? 0 : Math.max(0, Math.min(startIndex, n - 1));
    if (n === 0) {
      hilog.warn(DOMAIN, TAG, 'openPreview skipped: empty list');
      return;
    }
    const gen = ++GalleryPreviewNavStore.openGen;
    GalleryPreviewNavStore.opening = true;
    const startItem = GalleryPreviewNavStore.items[GalleryPreviewNavStore.startIndex];
    const startItemId = startItem !== undefined && startItem.id !== undefined &&
      startItem.id !== null ? String(startItem.id) : '';
    GalleryPreviewNavStore.sourcePlaceholderX = 0;
    GalleryPreviewNavStore.sourcePlaceholderY = 0;
    GalleryPreviewNavStore.sourcePlaceholderW = 0;
    GalleryPreviewNavStore.sourcePlaceholderH = 0;
    try {
      const rootRect = uiCtx.getComponentUtils().getRectangleById(sourceRootId);
      const thumbRect = uiCtx.getComponentUtils().getRectangleById(gallerySharedSourceDomId(startItemId));
      GalleryPreviewNavStore.sourcePlaceholderX =
        (thumbRect.windowOffset.x as number) - (rootRect.windowOffset.x as number);
      GalleryPreviewNavStore.sourcePlaceholderY =
        (thumbRect.windowOffset.y as number) - (rootRect.windowOffset.y as number);
      GalleryPreviewNavStore.sourcePlaceholderW = thumbRect.size.width as number;
      GalleryPreviewNavStore.sourcePlaceholderH = thumbRect.size.height as number;
    } catch (_e) {
      // 找不到矩形时只是不覆盖占位，不影响正常预览和返回。
    }
    try {
      // 不隐藏真实缩略图直接抓图，避免点击后出现一帧闪烁。
      GalleryPreviewNavStore.sourcePageSnapshot =
        uiCtx.getComponentSnapshot().getSync(sourceRootId);
    } catch (_e) {
      GalleryPreviewNavStore.sourcePageSnapshot = undefined;
    }
    setGalleryPreviewHeroActive(true);
    // 网格可见项缩略图已在缓存，先 push 开启动画；实况预热并行，不挡跟手。
    if (startItem !== undefined) {
      void warmupPreviewStartItem(uiCtx, baseUrl, startItem);
    }
    try {
      await uiCtx.getRouter().pushUrl({
        url: 'pages/GalleryPreview',
        params: { idx: `${GalleryPreviewNavStore.startIndex}` }
      });
    } catch (e) {
      GalleryPreviewEntryCache.discard();
      GalleryPreviewNavStore.sourcePageSnapshot = undefined;
      setGalleryPreviewHeroActive(false);
      setGalleryPreviewOpening(false);
      hilog.error(DOMAIN, TAG, 'pushUrl GalleryPreview: %{public}s', String(e));
    } finally {
      if (gen === GalleryPreviewNavStore.openGen) {
        GalleryPreviewNavStore.opening = false;
      }
    }
  }

  static openSlideshowPreview(
    uiCtx: UIContext,
    baseUrl: string,
    items: GalleryListItem[],
    intervalMs: number,
    libraryTotalCount: number = 0,
    globalIndices: number[] = []
  ): void {
    GalleryPreviewNavStore.baseUrl = baseUrl;
    GalleryPreviewNavStore.items = items.slice();
    GalleryPreviewNavStore.sourceRootId = GALLERY_PREVIEW_SOURCE_HOME_ID;
    GalleryPreviewNavStore.slideshowGlobalIndices = globalIndices.slice();
    const n = GalleryPreviewNavStore.items.length;
    GalleryPreviewNavStore.startIndex = 0;
    GalleryPreviewNavStore.sourceRootId = GALLERY_PREVIEW_SOURCE_HOME_ID;
    GalleryPreviewNavStore.sourcePageSnapshot = undefined;
    GalleryPreviewNavStore.sourcePlaceholderX = 0;
    GalleryPreviewNavStore.sourcePlaceholderY = 0;
    GalleryPreviewNavStore.sourcePlaceholderW = 0;
    GalleryPreviewNavStore.sourcePlaceholderH = 0;
    GalleryPreviewNavStore.slideshow.enabled = true;
    GalleryPreviewNavStore.slideshow.intervalMs = Math.max(2000, Math.floor(intervalMs));
    GalleryPreviewNavStore.slideshow.libraryTotalCount = Math.max(0, Math.floor(libraryTotalCount));
    if (n === 0) {
      hilog.warn(DOMAIN, TAG, 'openSlideshowPreview skipped: empty list');
      GalleryPreviewNavStore.resetSlideshow();
      return;
    }
    setGalleryPreviewHeroActive(false);
    uiCtx.getRouter().pushUrl({
      url: 'pages/GalleryPreview',
      params: { idx: '0', slideshow: '1' }
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'pushUrl GalleryPreview slideshow: %{public}s', String(e));
    });
  }

  static resetSlideshow(): void {
    GalleryPreviewNavStore.slideshow.enabled = false;
    GalleryPreviewNavStore.slideshow.intervalMs = 5000;
    GalleryPreviewNavStore.slideshow.libraryTotalCount = 0;
    GalleryPreviewNavStore.slideshowGlobalIndices = [];
  }

  static clear(): void {
    GalleryPreviewNavStore.items = [];
    GalleryPreviewNavStore.baseUrl = '';
    GalleryPreviewNavStore.startIndex = 0;
    GalleryPreviewNavStore.sourcePageSnapshot = undefined;
    GalleryPreviewNavStore.sourcePlaceholderX = 0;
    GalleryPreviewNavStore.sourcePlaceholderY = 0;
    GalleryPreviewNavStore.sourcePlaceholderW = 0;
    GalleryPreviewNavStore.sourcePlaceholderH = 0;
    GalleryPreviewNavStore.slideshowGlobalIndices = [];
    GalleryPreviewNavStore.resetSlideshow();
    GalleryPreviewEntryCache.discard();
    cancelVideoWarmup();
    setGalleryPreviewOpening(false);
    GallerySlideshowStreamStore.clear();
  }
}
