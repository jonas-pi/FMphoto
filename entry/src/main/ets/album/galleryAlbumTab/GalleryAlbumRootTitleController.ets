import { GalleryWaterFlowDataSource } from '../GalleryFlowDataSource';
import { TimelineGestureControllerHost } from './TimelineGestureController';
import { DayGlobalResolveResult, TimelineDayModel } from './GalleryAlbumTabTypes';
import { galleryAlbumResolveDayByGlobalIndex } from './GalleryAlbumTimelineRuntime';
import { GalleryViewGranularity, galleryViewGranularityTitle } from './GalleryAlbumGranularity';

export interface GalleryAlbumRootTitleHost {
  homeSurface: string;
  inSearchMode: boolean;
  inCategoryMode: boolean;
  inSmartCategoryMode: boolean;
  inPersonMode: boolean;
  viewGranularity: GalleryViewGranularity;
  rootPhotosScrollTitle: string;
  rootPhotosScrolledUnderTopBar: boolean;
  rootPhotosTitlePreferListAnchorUntilMs: number;
  timelineSeekInProgress: boolean;
  timelineReleaseAwaitVisibleCallback: boolean;
  listVisibleFirstNodeIdx: number;
  lastKnownGlobalPhotoSlotStart: number;
  lastKnownGlobalPhotoSlotEndExclusive: number;
  orderedDays: TimelineDayModel[];
  dayGlobalSlotStarts: number[];
  flowDataSource: GalleryWaterFlowDataSource;
  scrollerRef: Scroller;
  setRootPhotosScrollTitle(title: string): void;
  estimateFirstVisibleNodeIndexFromScrollY(yVp: number, total: number): number;
  mainGalleryContentInsetTopVp(): number;
  asTimelineGestureHost(): TimelineGestureControllerHost;
}

function isPhotosHomeSurface(host: GalleryAlbumRootTitleHost): boolean {
  return host.homeSurface !== 'albums';
}

function isRootPhotosSurfaceVisible(host: GalleryAlbumRootTitleHost): boolean {
  return isPhotosHomeSurface(host) &&
    !host.inSearchMode &&
    !host.inCategoryMode &&
    !host.inSmartCategoryMode &&
    !host.inPersonMode;
}

export function galleryAlbumRebuildDayGlobalSlotStarts(host: GalleryAlbumRootTitleHost): void {
  const next: number[] = [];
  let acc = 0;
  for (let i = 0; i < host.orderedDays.length; i++) {
    next.push(acc);
    acc += Math.max(0, host.orderedDays[i].itemCount);
  }
  host.dayGlobalSlotStarts = next;
}

export function galleryAlbumSetOrderedDays(host: GalleryAlbumRootTitleHost, value: TimelineDayModel[]): void {
  host.orderedDays = value;
  galleryAlbumRebuildDayGlobalSlotStarts(host);
}

export function galleryAlbumResolveDayByGlobalIndexFast(
  host: GalleryAlbumRootTitleHost,
  globalIndex: number
): DayGlobalResolveResult | null {
  if (host.orderedDays.length <= 0) {
    return null;
  }
  const g = Math.max(0, globalIndex);
  if (host.dayGlobalSlotStarts.length === host.orderedDays.length && host.dayGlobalSlotStarts.length > 0) {
    let lo = 0;
    let hi = host.dayGlobalSlotStarts.length - 1;
    while (lo <= hi) {
      const mid = lo + Math.floor((hi - lo) / 2);
      const start = Math.max(0, host.dayGlobalSlotStarts[mid]);
      const nextStart = mid + 1 < host.dayGlobalSlotStarts.length
        ? Math.max(start, host.dayGlobalSlotStarts[mid + 1])
        : Number.MAX_SAFE_INTEGER;
      if (g < start) {
        hi = mid - 1;
        continue;
      }
      if (g >= nextStart) {
        lo = mid + 1;
        continue;
      }
      return { dayIdx: mid, dayOffset: Math.max(0, g - start) };
    }
  }
  return galleryAlbumResolveDayByGlobalIndex(host.asTimelineGestureHost(), g);
}

export function galleryAlbumReadMainGalleryScrollOffsetVp(host: GalleryAlbumRootTitleHost): number {
  try {
    const off = host.scrollerRef.currentOffset();
    const yRaw = off.yOffset;
    if (typeof yRaw === 'number' && Number.isFinite(yRaw)) {
      return Math.max(0, yRaw);
    }
  } catch (_e) {
  }
  return 0;
}

export function galleryAlbumIsRootPhotosContentScrolledUnderTopBar(host: GalleryAlbumRootTitleHost): boolean {
  if (host.listVisibleFirstNodeIdx > 0) {
    return true;
  }
  const y = galleryAlbumReadMainGalleryScrollOffsetVp(host);
  return y >= Math.max(1, host.mainGalleryContentInsetTopVp() - 0.5);
}

export function galleryAlbumFormatRootPhotosVisibleDayTitle(
  year: number,
  month: number,
  day: number,
  granularity: GalleryViewGranularity
): string {
  return galleryViewGranularityTitle(year, month, day, granularity);
}

export function galleryAlbumResolveRootPhotosVisibleDayTitleFromGlobalSlots(
  host: GalleryAlbumRootTitleHost
): string | null {
  if (host.orderedDays.length <= 0) {
    return null;
  }
  const haveVisibleSlots = host.lastKnownGlobalPhotoSlotEndExclusive > host.lastKnownGlobalPhotoSlotStart;
  if (!haveVisibleSlots) {
    return null;
  }
  const resolved = galleryAlbumResolveDayByGlobalIndexFast(host, Math.max(0, host.lastKnownGlobalPhotoSlotStart));
  if (resolved === null || resolved.dayIdx < 0 || resolved.dayIdx >= host.orderedDays.length) {
    return null;
  }
  const day = host.orderedDays[resolved.dayIdx];
  if (day.year <= 0 || day.month <= 0 || day.day <= 0) {
    return null;
  }
  return galleryAlbumFormatRootPhotosVisibleDayTitle(day.year, day.month, day.day, host.viewGranularity);
}

export function galleryAlbumResolveRootPhotosVisibleDayTitleNearAnchor(
  host: GalleryAlbumRootTitleHost,
  anchor: number,
  total: number
): string | null {
  const searchRadius = 18;
  const safeAnchor = Math.max(0, Math.min(anchor, total - 1));
  const forwardEnd = Math.min(total - 1, safeAnchor + searchRadius);
  for (let i = safeAnchor; i <= forwardEnd; i++) {
    const node = host.flowDataSource.getData(i);
    if ((node.kind === 'day' || node.kind === 'row') && node.year > 0 && node.month > 0 && node.day > 0) {
      return galleryAlbumFormatRootPhotosVisibleDayTitle(node.year, node.month, node.day, host.viewGranularity);
    }
  }
  const backwardStart = Math.max(0, safeAnchor - searchRadius);
  for (let i = safeAnchor; i >= backwardStart; i--) {
    const node = host.flowDataSource.getData(i);
    if ((node.kind === 'day' || node.kind === 'row') && node.year > 0 && node.month > 0 && node.day > 0) {
      return galleryAlbumFormatRootPhotosVisibleDayTitle(node.year, node.month, node.day, host.viewGranularity);
    }
  }
  return null;
}

export function galleryAlbumResolveRootPhotosVisibleDayTitle(host: GalleryAlbumRootTitleHost): string | null {
  const total = host.flowDataSource.totalCount();
  if (total <= 0) {
    return null;
  }
  const scrollY = galleryAlbumReadMainGalleryScrollOffsetVp(host);
  const estimatedAnchor = Math.max(
    0,
    Math.min(host.estimateFirstVisibleNodeIndexFromScrollY(scrollY, total), total - 1)
  );
  const preferListAnchor =
    host.timelineSeekInProgress ||
    host.timelineReleaseAwaitVisibleCallback ||
    Date.now() <= host.rootPhotosTitlePreferListAnchorUntilMs;
  const visibleAnchor = Math.max(0, Math.min(host.listVisibleFirstNodeIdx, total - 1));
  if (preferListAnchor) {
    const visibleTitle = galleryAlbumResolveRootPhotosVisibleDayTitleNearAnchor(host, visibleAnchor, total);
    if (visibleTitle !== null) {
      return visibleTitle;
    }
    const estimatedTitle = galleryAlbumResolveRootPhotosVisibleDayTitleNearAnchor(host, estimatedAnchor, total);
    if (estimatedTitle !== null) {
      return estimatedTitle;
    }
    if (host.timelineReleaseAwaitVisibleCallback) {
      return null;
    }
  }
  const visibleTitle = galleryAlbumResolveRootPhotosVisibleDayTitleNearAnchor(host, visibleAnchor, total);
  if (visibleTitle !== null) {
    return visibleTitle;
  }
  const estimatedTitle = galleryAlbumResolveRootPhotosVisibleDayTitleNearAnchor(host, estimatedAnchor, total);
  if (estimatedTitle !== null) {
    return estimatedTitle;
  }
  return galleryAlbumResolveRootPhotosVisibleDayTitleFromGlobalSlots(host);
}

export function galleryAlbumRefreshRootPhotosScrollTitle(host: GalleryAlbumRootTitleHost): void {
  if (!isPhotosHomeSurface(host)) {
    host.rootPhotosScrolledUnderTopBar = false;
    host.setRootPhotosScrollTitle('\u56fe\u5e93');
    return;
  }
  if (!isRootPhotosSurfaceVisible(host)) {
    return;
  }
  const scrolledUnderTopBar = galleryAlbumIsRootPhotosContentScrolledUnderTopBar(host);
  host.rootPhotosScrolledUnderTopBar = scrolledUnderTopBar;
  if (!scrolledUnderTopBar) {
    host.setRootPhotosScrollTitle('\u56fe\u5e93');
    return;
  }
  const title = galleryAlbumResolveRootPhotosVisibleDayTitle(host);
  if (title !== null && title.length > 0) {
    host.setRootPhotosScrollTitle(title);
    return;
  }
  if (host.rootPhotosScrollTitle.length <= 0) {
    host.setRootPhotosScrollTitle('\u56fe\u5e93');
  }
}

export function galleryAlbumMaybeRefreshRootPhotosScrollTitleForThreshold(host: GalleryAlbumRootTitleHost): void {
  if (!isPhotosHomeSurface(host) || !isRootPhotosSurfaceVisible(host)) {
    return;
  }
  if (host.timelineReleaseAwaitVisibleCallback) {
    return;
  }
  const nextScrolledUnderTopBar = galleryAlbumIsRootPhotosContentScrolledUnderTopBar(host);
  if (nextScrolledUnderTopBar === host.rootPhotosScrolledUnderTopBar) {
    return;
  }
  host.rootPhotosScrolledUnderTopBar = nextScrolledUnderTopBar;
  galleryAlbumRefreshRootPhotosScrollTitle(host);
}

export function galleryAlbumCurrentHomeSurfaceTitle(host: GalleryAlbumRootTitleHost): string {
  return host.homeSurface === 'albums' ? '\u76f8\u518c' : host.rootPhotosScrollTitle;
}
