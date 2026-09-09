import { GalleryListItem } from '../../model/FnApiTypes';
import { GallerySlideshowStreamStore } from '../../album/slideshow/GallerySlideshowStreamStore';
import { GallerySlideshowPlaylistEntry } from '../../album/slideshow/GallerySlideshowTypes';
import { gallerySlideshowStableItemKey } from '../../album/slideshow/GallerySlideshowMedia';
import { slideshowLogAppend, slideshowLogPage, slideshowLogPrefetch } from '../../album/slideshow/GallerySlideshowTrace';
import { PreviewItemsDataSource } from './GalleryPreviewDataSource';

export interface GalleryPreviewSlideshowHost {
  slideshowEnabled: boolean;
  slideshowIntervalMs: number;
  slideshowLibraryTotal: number;
  slideshowGlobalIndices: number[];
  slideshowTimerId: number;
  slideshowAdvancePending: boolean;
  slideshowPrefetchTimer: number;
  lastLoggedSlideshowGlobal: number;
  lastLoggedSlideshowKey: string;
  swiperIndex: number;
  totalCount: number;
  previewItems: GalleryListItem[];
  itemSource: PreviewItemsDataSource;
  swiperCtrl: SwiperController;
  pinchGestureActive: boolean;
  previewZoomLocked: boolean;
  detailsVisible: boolean;
  downloading: boolean;
  sharing: boolean;
  deleting: boolean;
  currentItem(): GalleryListItem | null;
  currentItemIsVideo(): boolean;
}

export function galleryPreviewClearSlideshowTimer(host: GalleryPreviewSlideshowHost): void {
  if (host.slideshowTimerId >= 0) {
    clearTimeout(host.slideshowTimerId);
    host.slideshowTimerId = -1;
  }
}

export function galleryPreviewClearSlideshowPrefetchTimer(host: GalleryPreviewSlideshowHost): void {
  if (host.slideshowPrefetchTimer >= 0) {
    clearTimeout(host.slideshowPrefetchTimer);
    host.slideshowPrefetchTimer = -1;
  }
}

export function galleryPreviewScheduleSlideshowPrefetch(host: GalleryPreviewSlideshowHost): void {
  galleryPreviewClearSlideshowPrefetchTimer(host);
  host.slideshowPrefetchTimer = setTimeout((): void => {
    host.slideshowPrefetchTimer = -1;
    galleryPreviewMaybePrefetchSlideshowItems(host);
  }, 0);
}

export function galleryPreviewShouldPauseSlideshow(host: GalleryPreviewSlideshowHost): boolean {
  return host.pinchGestureActive || host.previewZoomLocked || host.detailsVisible ||
    host.downloading || host.sharing || host.deleting;
}

export function galleryPreviewAdvanceSlideshow(host: GalleryPreviewSlideshowHost): void {
  if (!host.slideshowEnabled) {
    return;
  }
  if (host.swiperIndex + 1 < host.totalCount) {
    const next = host.swiperIndex + 1;
    host.swiperIndex = next;
    host.swiperCtrl.changeIndex(next, true);
    galleryPreviewMaybePrefetchSlideshowItems(host);
    return;
  }
  if (GallerySlideshowStreamStore.isActive()) {
    void GallerySlideshowStreamStore.prefetchAppend((entries: GallerySlideshowPlaylistEntry[]): void => {
      if (entries.length === 0) {
        galleryPreviewClearSlideshowTimer(host);
        return;
      }
      galleryPreviewAppendSlideshowEntries(host, entries);
      const next = host.swiperIndex + 1;
      if (next < host.totalCount) {
        host.swiperIndex = next;
        host.swiperCtrl.changeIndex(next, true);
        galleryPreviewMaybePrefetchSlideshowItems(host);
      } else {
        galleryPreviewClearSlideshowTimer(host);
      }
    });
    return;
  }
  galleryPreviewClearSlideshowTimer(host);
}

export function galleryPreviewMaybePrefetchSlideshowItems(host: GalleryPreviewSlideshowHost): void {
  if (!host.slideshowEnabled || !GallerySlideshowStreamStore.isActive()) {
    return;
  }
  const remaining = host.totalCount - host.swiperIndex - 1;
  if (!GallerySlideshowStreamStore.shouldPrefetch(remaining)) {
    return;
  }
  slideshowLogPrefetch(remaining, host.swiperIndex, host.totalCount, 0);
  void GallerySlideshowStreamStore.prefetchAppend((entries: GallerySlideshowPlaylistEntry[]): void => {
    galleryPreviewAppendSlideshowEntries(host, entries);
  });
}

export function galleryPreviewAppendSlideshowEntries(
  host: GalleryPreviewSlideshowHost,
  entries: GallerySlideshowPlaylistEntry[]
): void {
  if (entries.length === 0) {
    return;
  }
  const seenKeys: Set<string> = new Set();
  const seenGlobals: Set<number> = new Set();
  for (let i = 0; i < host.previewItems.length; i++) {
    const key = gallerySlideshowStableItemKey(host.previewItems[i]);
    if (key.length > 0) {
      seenKeys.add(key);
    }
  }
  for (let i = 0; i < host.slideshowGlobalIndices.length; i++) {
    seenGlobals.add(host.slideshowGlobalIndices[i]);
  }
  const unique: GallerySlideshowPlaylistEntry[] = [];
  let dropGlobal = 0;
  let dropKey = 0;
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    if (seenGlobals.has(entry.globalIndex)) {
      dropGlobal++;
      continue;
    }
    const key = gallerySlideshowStableItemKey(entry.item);
    if (key.length > 0 && seenKeys.has(key)) {
      dropKey++;
      continue;
    }
    unique.push(entry);
    seenGlobals.add(entry.globalIndex);
    if (key.length > 0) {
      seenKeys.add(key);
    }
  }
  if (unique.length === 0) {
    slideshowLogAppend(entries.length, 0, dropGlobal, dropKey, host.previewItems.length,
      host.slideshowGlobalIndices.length);
    return;
  }
  const items: GalleryListItem[] = [];
  for (let i = 0; i < unique.length; i++) {
    items.push(unique[i].item);
    host.slideshowGlobalIndices.push(unique[i].globalIndex);
  }
  const before = host.previewItems.length;
  host.itemSource.appendItems(items);
  if (host.previewItems.length === before) {
    for (let i = 0; i < items.length; i++) {
      host.previewItems.push(items[i]);
    }
  }
  host.totalCount = host.previewItems.length;
  GallerySlideshowStreamStore.rememberEntries(unique);
  slideshowLogAppend(entries.length, unique.length, dropGlobal, dropKey, host.previewItems.length,
    host.slideshowGlobalIndices.length);
}

export function galleryPreviewLogSlideshowPage(host: GalleryPreviewSlideshowHost): void {
  if (!host.slideshowEnabled) {
    return;
  }
  const item = host.currentItem();
  const key = item !== null ? gallerySlideshowStableItemKey(item) : '';
  const globalIdx = galleryPreviewSlideshowGlobalIndexAt(host, host.swiperIndex);
  const fallback = globalIdx < 0;
  const sequential = globalIdx >= 0 && host.lastLoggedSlideshowGlobal >= 0 &&
    globalIdx === host.lastLoggedSlideshowGlobal + 1;
  const duplicateKey = key.length > 0 && key === host.lastLoggedSlideshowKey;
  slideshowLogPage(
    host.swiperIndex,
    globalIdx,
    key,
    host.previewItems.length,
    host.slideshowGlobalIndices.length,
    fallback,
    sequential,
    duplicateKey
  );
  host.lastLoggedSlideshowGlobal = globalIdx;
  host.lastLoggedSlideshowKey = key;
}

export function galleryPreviewSlideshowGlobalIndexAt(
  host: GalleryPreviewSlideshowHost,
  playlistIdx: number
): number {
  if (playlistIdx < 0 || playlistIdx >= host.slideshowGlobalIndices.length) {
    return -1;
  }
  return host.slideshowGlobalIndices[playlistIdx];
}

export function galleryPreviewArmSlideshowTimer(host: GalleryPreviewSlideshowHost): void {
  galleryPreviewClearSlideshowTimer(host);
  if (!host.slideshowEnabled || host.slideshowIntervalMs <= 0) {
    return;
  }
  if (host.totalCount <= 1 && !GallerySlideshowStreamStore.isActive()) {
    return;
  }
  if (host.detailsVisible) {
    return;
  }
  if (host.currentItemIsVideo()) {
    return;
  }
  host.slideshowTimerId = setTimeout((): void => {
    host.slideshowTimerId = -1;
    if (galleryPreviewShouldPauseSlideshow(host)) {
      galleryPreviewArmSlideshowTimer(host);
      return;
    }
    if (host.currentItemIsVideo()) {
      return;
    }
    galleryPreviewAdvanceSlideshow(host);
    galleryPreviewArmSlideshowTimer(host);
  }, host.slideshowIntervalMs);
}

export function galleryPreviewPauseSlideshowForDetails(host: GalleryPreviewSlideshowHost): void {
  galleryPreviewClearSlideshowTimer(host);
}

export function galleryPreviewResumeSlideshowAfterDetails(host: GalleryPreviewSlideshowHost): void {
  if (!host.slideshowEnabled) {
    return;
  }
  if (host.slideshowAdvancePending) {
    host.slideshowAdvancePending = false;
    galleryPreviewAdvanceSlideshow(host);
  }
  galleryPreviewArmSlideshowTimer(host);
}

export function galleryPreviewOnSlideshowVideoEnded(host: GalleryPreviewSlideshowHost): void {
  if (!host.slideshowEnabled) {
    return;
  }
  if (galleryPreviewShouldPauseSlideshow(host)) {
    host.slideshowAdvancePending = true;
    return;
  }
  galleryPreviewAdvanceSlideshow(host);
  galleryPreviewArmSlideshowTimer(host);
}
