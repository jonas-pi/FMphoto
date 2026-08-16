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
  private static opening: boolean = false;
  private static openGen: number = 0;

  static openPreview(
    uiCtx: UIContext,
    baseUrl: string,
    items: GalleryListItem[],
    startIndex: number
  ): void {
    void GalleryPreviewNavStore.openPreviewWhenReady(uiCtx, baseUrl, items, startIndex);
  }

  private static async openPreviewWhenReady(
    uiCtx: UIContext,
    baseUrl: string,
    items: GalleryListItem[],
    startIndex: number
  ): Promise<void> {
    if (GalleryPreviewNavStore.opening) {
      return;
    }
    GalleryPreviewNavStore.resetSlideshow();
    GalleryPreviewNavStore.baseUrl = baseUrl;
    GalleryPreviewNavStore.items = items.slice();
    const n = GalleryPreviewNavStore.items.length;
    GalleryPreviewNavStore.startIndex = n <= 0 ? 0 : Math.max(0, Math.min(startIndex, n - 1));
    if (n === 0) {
      hilog.warn(DOMAIN, TAG, 'openPreview skipped: empty list');
      return;
    }
    const gen = ++GalleryPreviewNavStore.openGen;
    GalleryPreviewNavStore.opening = true;
    setGalleryPreviewOpening(true);
    const startItem = GalleryPreviewNavStore.items[GalleryPreviewNavStore.startIndex];
    try {
      if (startItem !== undefined) {
        await warmupPreviewStartItem(uiCtx, baseUrl, startItem);
      }
    } catch (_e) {
    }
    if (gen !== GalleryPreviewNavStore.openGen) {
      GalleryPreviewNavStore.opening = false;
      return;
    }
    try {
      await uiCtx.getRouter().pushUrl({
        url: 'pages/GalleryPreview',
        params: { idx: `${GalleryPreviewNavStore.startIndex}` }
      });
    } catch (e) {
      GalleryPreviewEntryCache.discard();
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
    GalleryPreviewNavStore.slideshowGlobalIndices = globalIndices.slice();
    const n = GalleryPreviewNavStore.items.length;
    GalleryPreviewNavStore.startIndex = 0;
    GalleryPreviewNavStore.slideshow.enabled = true;
    GalleryPreviewNavStore.slideshow.intervalMs = Math.max(2000, Math.floor(intervalMs));
    GalleryPreviewNavStore.slideshow.libraryTotalCount = Math.max(0, Math.floor(libraryTotalCount));
    if (n === 0) {
      hilog.warn(DOMAIN, TAG, 'openSlideshowPreview skipped: empty list');
      GalleryPreviewNavStore.resetSlideshow();
      return;
    }
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
    GalleryPreviewNavStore.slideshowGlobalIndices = [];
    GalleryPreviewNavStore.resetSlideshow();
    GalleryPreviewEntryCache.discard();
    cancelVideoWarmup();
    setGalleryPreviewOpening(false);
    GallerySlideshowStreamStore.clear();
  }
}
