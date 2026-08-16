/**
 * 进入全屏预览前的闸门：当前页转圈，首项就绪后再 push。
 */
import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { GalleryListItem } from '../model/FnApiTypes';
import {
  getThumbPixCached,
  isGifItem,
  isVideoItem,
  loadThumbPix,
  nasUrl,
  pickThumb
} from './GalleryAlbumCommon';
import { isLivePhotoItem } from './livephoto/LivePhotoDetect';
import {
  LivePhotoPairFiles,
  loadMovingPhotoFromPair,
  materializeLivePhotoPair,
  unlinkLivePhotoPair
} from './livephoto/LivePhotoSandbox';

export const GALLERY_PREVIEW_OPENING_KEY: string = 'galleryPreviewOpening';
export const GALLERY_PREVIEW_WARMUP_VIDEO_URL_KEY: string = 'galleryPreviewWarmupVideoUrl';

AppStorage.setOrCreate(GALLERY_PREVIEW_OPENING_KEY, false);
AppStorage.setOrCreate(GALLERY_PREVIEW_WARMUP_VIDEO_URL_KEY, '');

let videoWarmupGen: number = 0;
let videoWarmupResolve: ((ok: boolean) => void) | undefined = undefined;

export function setGalleryPreviewOpening(opening: boolean): void {
  AppStorage.setOrCreate(GALLERY_PREVIEW_OPENING_KEY, opening);
}

export function setWarmupVideoUrl(url: string): void {
  AppStorage.setOrCreate(GALLERY_PREVIEW_WARMUP_VIDEO_URL_KEY, url);
}

export function waitForVideoPrepared(url: string, timeoutMs: number = 25000): Promise<boolean> {
  const gen = ++videoWarmupGen;
  setWarmupVideoUrl(url);
  return new Promise<boolean>((resolve: (ok: boolean) => void) => {
    const timer: number = setTimeout((): void => {
      if (gen !== videoWarmupGen) {
        return;
      }
      videoWarmupResolve = undefined;
      setWarmupVideoUrl('');
      resolve(false);
    }, timeoutMs);
    videoWarmupResolve = (ok: boolean): void => {
      if (gen !== videoWarmupGen) {
        return;
      }
      clearTimeout(timer);
      videoWarmupResolve = undefined;
      setWarmupVideoUrl('');
      resolve(ok);
    };
  });
}

export function completeVideoWarmup(ok: boolean): void {
  const resolver = videoWarmupResolve;
  if (resolver !== undefined) {
    resolver(ok);
  }
}

export function cancelVideoWarmup(): void {
  videoWarmupGen++;
  videoWarmupResolve = undefined;
  setWarmupVideoUrl('');
}

export class GalleryPreviewWarmedLive {
  pair: LivePhotoPairFiles | undefined = undefined;
  moving: photoAccessHelper.MovingPhoto | undefined = undefined;
}

export class GalleryPreviewEntryCache {
  static itemId: string = '';
  static live: GalleryPreviewWarmedLive | undefined = undefined;

  static stashLive(itemId: string, live: GalleryPreviewWarmedLive): void {
    if (GalleryPreviewEntryCache.live !== undefined &&
      GalleryPreviewEntryCache.live.pair !== live.pair) {
      void unlinkLivePhotoPair(GalleryPreviewEntryCache.live.pair);
    }
    GalleryPreviewEntryCache.itemId = itemId;
    GalleryPreviewEntryCache.live = live;
  }

  static takeLive(itemId: string): GalleryPreviewWarmedLive | undefined {
    if (itemId.length === 0 || GalleryPreviewEntryCache.itemId !== itemId) {
      return undefined;
    }
    const live = GalleryPreviewEntryCache.live;
    GalleryPreviewEntryCache.itemId = '';
    GalleryPreviewEntryCache.live = undefined;
    return live;
  }

  static discard(): void {
    const live = GalleryPreviewEntryCache.live;
    GalleryPreviewEntryCache.itemId = '';
    GalleryPreviewEntryCache.live = undefined;
    if (live !== undefined) {
      void unlinkLivePhotoPair(live.pair);
    }
  }
}

function itemIdOf(item: GalleryListItem): string {
  if (item.id === undefined || item.id === null) {
    return '';
  }
  return String(item.id);
}

async function warmupThumb(baseUrl: string, item: GalleryListItem): Promise<void> {
  const url = nasUrl(baseUrl, pickThumb(item));
  if (url.length === 0 || getThumbPixCached(url) !== undefined) {
    return;
  }
  await loadThumbPix(url);
}

async function warmupLive(
  uiCtx: UIContext,
  baseUrl: string,
  item: GalleryListItem
): Promise<void> {
  const host = uiCtx.getHostContext() as common.UIAbilityContext | undefined;
  if (host === undefined) {
    return;
  }
  try {
    const pair = await materializeLivePhotoPair(host, baseUrl, item, false);
    if (pair === undefined) {
      return;
    }
    const moving = await loadMovingPhotoFromPair(host, pair);
    const warmed = new GalleryPreviewWarmedLive();
    warmed.pair = pair;
    warmed.moving = moving;
    GalleryPreviewEntryCache.stashLive(itemIdOf(item), warmed);
  } catch (_e) {
  }
}

export async function warmupPreviewStartItem(
  uiCtx: UIContext,
  baseUrl: string,
  item: GalleryListItem
): Promise<void> {
  if (isVideoItem(item)) {
    // 视频进页由预览页自己的 AVPlayer 在 prepared（已能播放）时揭层。
    // 官方 startRenderFrame 要等 play() 后才回调，不能在这里空等整段缓冲。
    return;
  }
  await warmupThumb(baseUrl, item);
  if (isLivePhotoItem(item)) {
    await warmupLive(uiCtx, baseUrl, item);
    return;
  }
  if (isGifItem(item)) {
    return;
  }
}
