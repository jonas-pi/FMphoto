import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryWaterFlowDataSource } from '../GalleryFlowDataSource';
import {
  GALLERY_SCROLL_DEBUG_LOG,
  GALLERY_SCROLL_INTERACTIVE_LOG_WINDOW_MS,
  GALLERY_SCROLL_LOG_THROTTLE_MS,
  GALLERY_TAB_DOMAIN as DOMAIN,
  GALLERY_TAB_TAG as TAG,
  GALLERY_TIMELINE_DRAG_WATCHDOG_MS,
  GALLERY_TIMELINE_EXPANDED_AUTO_HIDE_MS,
  GALLERY_TIMELINE_RAIL_AUTO_HIDE_MS
} from './GalleryAlbumTabConstants';
import { GalleryAlbumDaySectionState } from './GalleryAlbumState';
import {
  timelineScrubExpandedChrome as selectTimelineScrubExpandedChrome,
  timelineScrubScrollRailOnly as selectTimelineScrubScrollRailOnly
} from './GalleryAlbumState';
import { TimelineDayModel, TimelineYearMonthPair } from './GalleryAlbumTabTypes';

export interface TimelineGestureControllerHost {
  scrollerRef: Scroller;
  flowDataSource: GalleryWaterFlowDataSource;
  orderedDays: TimelineDayModel[];
  sections: GalleryAlbumDaySectionState[];
  visualPlaceholderMode: boolean;
  timelineSidebarDragging: boolean;
  isDraggingOrFling: boolean;
  timelineBarVisible: boolean;
  timelinePressing: boolean;
  timelineLongPressExpanded: boolean;
  timelineDragWatchdogTimer: number;
  timelineDragWatchdogGen: number;
  lastMainListInteractMs: number;
  lastTimelineBarTouchMs: number;
  lastTimelineHandleSyncMs: number;
  lastScrollDebugLogMs: number;
  lastScrollDebugState: string;
  listSettledTimer: number;
  listSettledGen: number;
  listKineticScrolling: boolean;
  dayIndex: number;
  exhausted: boolean;
  loadingMore: boolean;
  bootLoading: boolean;
  gallerySlideGestureActive: boolean;
  galleryMainListScrollEnabled: boolean;
  timelineSeekInProgress: boolean;
  timelineHideTimer: number;
  timelineSliderRatio: number;
  timelineScrubTrackHeightVp: number;
  timelineSidebarHighlightIndex: number;
  timelineIndicatorY: number;
  timelineSeekGen: number;
  listVisibleFirstNodeIdx: number;
  listVisibleLastNodeIdx: number;
  ignoreListFreezeUntilMs: number;
  pumpEpoch: number;
  refreshLastKnownGlobalSlotsFromListIndices(firstIdx: number, lastIdx: number): void;
  captureListScrollIndexAnchor(): void;
  resolveYearMonthByTimelineRatio(ratio: number): TimelineYearMonthPair | null;
  flowHasVisibleYearMonth(year: number, month: number): boolean;
  startTimelineSeekWatchdog(year: number, month: number): void;
  seekTimelineListToDisplayRatio(ratio: number): void;
  syncGalleryTimelineAtTopForPull(): void;
  clearGalleryThumbHitBounds(): void;
  flushPendingFlowRebuild(): void;
  loadVisibleItemsThrottled(forceImmediate?: boolean, aggressive?: boolean): void;
  loadVisibleItemsImmediate(): void;
  syncListVisibleRoughToTimelineSliderTarget(): void;
  pumpLoad(singleBatch?: boolean): void;
  runMainListScrollSettledWork(epochAtSchedule?: number): void;
}

function scrollStateText(state: ScrollState): string {
  if (state === ScrollState.Idle) {
    return 'Idle';
  }
  if (state === ScrollState.Scroll) {
    return 'Scroll';
  }
  if (state === ScrollState.Fling) {
    return 'Fling';
  }
  return 'Unknown';
}

export function timelineGestureLogScrollDebug(host: TimelineGestureControllerHost, msg: string): void {
  if (!GALLERY_SCROLL_DEBUG_LOG) {
    return;
  }
  hilog.info(DOMAIN, TAG, '[scroll-debug] %{public}s', msg);
}

export function timelineGestureIsInScrollInteractiveLogWindow(host: TimelineGestureControllerHost): boolean {
  const now = Date.now();
  return now - host.lastMainListInteractMs <= GALLERY_SCROLL_INTERACTIVE_LOG_WINDOW_MS;
}

export function timelineGestureRefreshVisualPlaceholderMode(host: TimelineGestureControllerHost): void {
  const next = host.timelineSidebarDragging || host.isDraggingOrFling;
  if (host.visualPlaceholderMode !== next) {
    host.visualPlaceholderMode = next;
  }
}

export function timelineGestureTouchTimelineBarOnScroll(host: TimelineGestureControllerHost): void {
  const now = Date.now();
  if (!host.timelineBarVisible || now - host.lastTimelineBarTouchMs >= 100) {
    host.lastTimelineBarTouchMs = now;
    timelineGestureShowTimelineBar(host);
  }
}

export function timelineGestureSyncTimelineHandleFromListThrottled(
  host: TimelineGestureControllerHost,
  firstIdx: number,
  syncTimelineSliderFromFirstIndex: (idx: number) => void
): void {
  const now = Date.now();
  if (now - host.lastTimelineHandleSyncMs < 80) {
    return;
  }
  host.lastTimelineHandleSyncMs = now;
  syncTimelineSliderFromFirstIndex(firstIdx);
}

export function timelineGestureCancelTimelineDragWatchdog(host: TimelineGestureControllerHost): void {
  if (host.timelineDragWatchdogTimer >= 0) {
    clearTimeout(host.timelineDragWatchdogTimer);
    host.timelineDragWatchdogTimer = -1;
  }
}

export function timelineGestureArmTimelineDragWatchdog(host: TimelineGestureControllerHost): void {
  timelineGestureCancelTimelineDragWatchdog(host);
  const gen = ++host.timelineDragWatchdogGen;
  host.timelineDragWatchdogTimer = setTimeout((): void => {
    if (gen !== host.timelineDragWatchdogGen) {
      return;
    }
    host.timelineDragWatchdogTimer = -1;
    if (!host.timelineSidebarDragging) {
      return;
    }
    host.timelineSidebarDragging = false;
    host.timelinePressing = false;
    host.timelineLongPressExpanded = false;
    host.timelineSeekInProgress = false;
    timelineGestureRefreshVisualPlaceholderMode(host);
    timelineGestureShowTimelineBar(host);
    timelineGestureLogScrollDebug(host, 'timeline drag watchdog release');
    host.runMainListScrollSettledWork();
  }, GALLERY_TIMELINE_DRAG_WATCHDOG_MS);
}

export function timelineGestureMaybeLogMainScrollTick(
  host: TimelineGestureControllerHost,
  offset: number,
  state: ScrollState
): void {
  if (!GALLERY_SCROLL_DEBUG_LOG) {
    return;
  }
  host.lastMainListInteractMs = Date.now();
  const now = Date.now();
  const st = scrollStateText(state);
  const changed = st !== host.lastScrollDebugState;
  if (!changed && now - host.lastScrollDebugLogMs < GALLERY_SCROLL_LOG_THROTTLE_MS) {
    return;
  }
  host.lastScrollDebugState = st;
  host.lastScrollDebugLogMs = now;
  timelineGestureLogScrollDebug(
    host,
    `state=${st}, offset=${offset.toFixed(1)}, placeholder=${host.visualPlaceholderMode ? 1 : 0}, `
    + `kinetic=${host.listKineticScrolling ? 1 : 0}, dragFling=${host.isDraggingOrFling ? 1 : 0}, `
    + `dayIndex=${host.dayIndex}, exhausted=${host.exhausted ? 1 : 0}, loadingMore=${host.loadingMore ? 1 : 0}`
  );
}

export function timelineGestureCancelListSettledTimer(
  host: TimelineGestureControllerHost,
  invalidateGen: boolean = true
): void {
  if (host.listSettledTimer >= 0) {
    clearTimeout(host.listSettledTimer);
    host.listSettledTimer = -1;
  }
  if (invalidateGen) {
    host.listSettledGen++;
  }
}

export function timelineGestureScheduleMainListSettledWork(host: TimelineGestureControllerHost): void {
  timelineGestureCancelListSettledTimer(host, false);
  const gen = ++host.listSettledGen;
  const epoch = host.pumpEpoch;
  if (!host.isDraggingOrFling && !host.visualPlaceholderMode && !host.timelineSidebarDragging) {
    host.loadVisibleItemsThrottled(true, false);
  }
  host.listSettledTimer = setTimeout((): void => {
    if (gen !== host.listSettledGen) {
      return;
    }
    if (epoch !== host.pumpEpoch) {
      return;
    }
    if (host.listSettledTimer < 0) {
      return;
    }
    host.listSettledTimer = -1;
    if (host.isDraggingOrFling || host.visualPlaceholderMode) {
      return;
    }
    timelineGestureLogScrollDebug(host, 'settled release: loadVisible + settledWork');
    host.loadVisibleItemsThrottled();
    host.runMainListScrollSettledWork(epoch);
  }, 220);
}

export function timelineGestureRunMainListScrollSettledWork(
  host: TimelineGestureControllerHost,
  epochAtSchedule: number = -1
): void {
  if (epochAtSchedule >= 0 && epochAtSchedule !== host.pumpEpoch) {
    return;
  }
  if (host.isDraggingOrFling || host.visualPlaceholderMode) {
    return;
  }
  if (host.timelineSidebarDragging || host.timelineSeekInProgress) {
    return;
  }
  host.syncGalleryTimelineAtTopForPull();
  if (!host.gallerySlideGestureActive && !host.galleryMainListScrollEnabled) {
    host.galleryMainListScrollEnabled = true;
  }
  if (!host.gallerySlideGestureActive) {
    host.clearGalleryThumbHitBounds();
  }
  if (!host.exhausted && !host.loadingMore && !host.bootLoading) {
    host.pumpLoad(true);
  }
  host.flushPendingFlowRebuild();
}

export function timelineGestureTimelineScrubExpandedChrome(host: TimelineGestureControllerHost): boolean {
  return selectTimelineScrubExpandedChrome({
    timelineSidebarDragging: host.timelineSidebarDragging,
    timelineLongPressExpanded: host.timelineLongPressExpanded,
    timelineBarVisible: host.timelineBarVisible
  });
}

export function timelineGestureTimelineScrubScrollRailOnly(host: TimelineGestureControllerHost): boolean {
  return selectTimelineScrubScrollRailOnly({
    timelineSidebarDragging: host.timelineSidebarDragging,
    timelineLongPressExpanded: host.timelineLongPressExpanded,
    timelineBarVisible: host.timelineBarVisible
  });
}

export function timelineGestureShowTimelineBar(host: TimelineGestureControllerHost): void {
  host.timelineBarVisible = true;
  if (host.timelineHideTimer >= 0) {
    clearTimeout(host.timelineHideTimer);
    host.timelineHideTimer = -1;
  }
  if (host.timelineSidebarDragging || host.timelinePressing) {
    return;
  }
  const hideMs = timelineGestureTimelineScrubExpandedChrome(host)
    ? GALLERY_TIMELINE_EXPANDED_AUTO_HIDE_MS
    : GALLERY_TIMELINE_RAIL_AUTO_HIDE_MS;
  host.timelineHideTimer = setTimeout((): void => {
    host.timelineHideTimer = -1;
    host.timelineBarVisible = false;
    host.timelineLongPressExpanded = false;
  }, hideMs);
}

export function timelineGestureKickPostTimelineReleaseLoad(host: TimelineGestureControllerHost): void {
  host.flushPendingFlowRebuild();
  host.syncListVisibleRoughToTimelineSliderTarget();
  host.loadVisibleItemsImmediate();
  if (!host.loadingMore && !host.exhausted && !host.bootLoading) {
    host.pumpLoad(true);
  }
  const epoch = host.pumpEpoch;
  setTimeout((): void => {
    if (epoch !== host.pumpEpoch || host.timelineSidebarDragging || host.isDraggingOrFling) {
      return;
    }
    host.flushPendingFlowRebuild();
    host.syncListVisibleRoughToTimelineSliderTarget();
    host.loadVisibleItemsImmediate();
    if (!host.loadingMore && !host.exhausted && !host.bootLoading) {
      host.pumpLoad(true);
    }
  }, 120);
}

export function timelineGestureEndTimelineDrag(host: TimelineGestureControllerHost): void {
  timelineGestureCancelTimelineDragWatchdog(host);
  host.timelineDragWatchdogGen++;
  host.ignoreListFreezeUntilMs = Date.now() + 900;
  host.timelineSidebarDragging = false;
  host.timelinePressing = false;
  host.timelineLongPressExpanded = false;
  timelineGestureRefreshVisualPlaceholderMode(host);
  host.timelineSeekInProgress = true;
  host.seekTimelineListToDisplayRatio(host.timelineSliderRatio);
  const ym = host.resolveYearMonthByTimelineRatio(host.timelineSliderRatio);
  if (ym !== null && !host.flowHasVisibleYearMonth(ym.year, ym.month)) {
    host.startTimelineSeekWatchdog(ym.year, ym.month);
  }
  setTimeout((): void => {
    host.timelineSeekInProgress = false;
    host.isDraggingOrFling = false;
    host.listKineticScrolling = false;
    host.visualPlaceholderMode = false;
    host.ignoreListFreezeUntilMs = Date.now() + 600;
    timelineGestureRefreshVisualPlaceholderMode(host);
    timelineGestureKickPostTimelineReleaseLoad(host);
    host.runMainListScrollSettledWork();
    timelineGestureShowTimelineBar(host);
  }, 120);
}
