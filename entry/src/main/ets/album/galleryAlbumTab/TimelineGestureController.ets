import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../../auth/AppSession';
import { GalleryWaterFlowDataSource } from '../GalleryFlowDataSource';
import {
  GALLERY_SCROLL_DEBUG_LOG,
  GALLERY_SCROLL_INTERACTIVE_LOG_WINDOW_MS,
  GALLERY_SCROLL_LOG_THROTTLE_MS,
  GALLERY_TAB_DOMAIN as DOMAIN,
  GALLERY_TAB_TAG as TAG,
  GALLERY_TIMELINE_DRAG_WATCHDOG_MS,
  GALLERY_TIMELINE_EXPANDED_AUTO_HIDE_MS,
  GALLERY_TIMELINE_RAIL_AUTO_HIDE_MS,
  GALLERY_TIMELINE_SEEK_NO_SCROLLER_GUARD_MS,
  GALLERY_TIMELINE_SEEK_RELEASE_FREEZE_MS
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
  dayGlobalSlotStarts: number[];
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
  timelineSeekAnchorNodeIdx: number;
  visibleLoadPreferBottomFirst: boolean;
  listVisibleFirstNodeIdx: number;
  listVisibleLastNodeIdx: number;
  ignoreListFreezeUntilMs: number;
  timelineSeekNoScrollerGuardUntilMs: number;
  pumpEpoch: number;
  flowNodeIndexFromListIndex(index: number): number;
  listIndexFromFlowNodeIndex(index: number): number;
  refreshLastKnownGlobalSlotsFromListIndices(firstIdx: number, lastIdx: number): void;
  captureListScrollIndexAnchor(): void;
  refreshVisibleRangeIfAvailable(): boolean;
  forceRefreshVisibleRange(): boolean;
  tryHandOffTimelineSeekToListDriven(reason: string): boolean;
  resolveYearMonthByTimelineRatio(ratio: number): TimelineYearMonthPair | null;
  flowHasVisibleYearMonth(year: number, month: number): boolean;
  startTimelineSeekWatchdog(year: number, month: number): void;
  seekTimelineListToDisplayRatio(ratio: number): void;
  syncGalleryTimelineAtTopForPull(): void;
  clearGalleryThumbHitBounds(): void;
  flushPendingFlowRebuild(): void;
  loadVisibleItemsThrottled(forceImmediate?: boolean, aggressive?: boolean): void;
  loadVisibleItemsImmediate(): void;
  loadVisibleItemsInteractiveVisiblePriority(): void;
  syncListVisibleRoughToTimelineSliderTarget(): void;
  refreshRootPhotosScrollTitle(): void;
  pumpLoad(singleBatch?: boolean): void;
  runMainListScrollSettledWork(epochAtSchedule?: number): void;
}

class TimelineReleaseVisiblePassPlan {
  delayMs: number = 0;
  refreshVisibleRange: boolean = false;
  allowRoughFallback: boolean = false;
  label: string = '';
}

const GALLERY_SCROLL_RELEASE_TRACE_TAG = '[scroll-release-visible]';

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

function timelineGestureLogReleaseTrace(host: TimelineGestureControllerHost, msg: string): void {
  timelineGestureLogScrollDebug(host, `${GALLERY_SCROLL_RELEASE_TRACE_TAG} ${msg}`);
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
  if (now - host.lastTimelineHandleSyncMs < 96) {
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

function timelineGestureRunReleaseVisiblePass(
  host: TimelineGestureControllerHost,
  refreshVisibleRange: boolean,
  allowRoughFallback: boolean,
  passLabel: string
): void {
  if (!host.timelineSeekInProgress) {
    timelineGestureLogReleaseTrace(host, `${passLabel}: skip after list-driven handoff`);
    return;
  }
  host.flushPendingFlowRebuild();
  let refreshedByScroller = false;
  if (refreshVisibleRange) {
    // Timeline release must not physically nudge the list, or the page will visibly bounce.
    refreshedByScroller = host.refreshVisibleRangeIfAvailable();
    if (refreshedByScroller) {
      host.tryHandOffTimelineSeekToListDriven(passLabel);
    }
  }
  timelineGestureLogReleaseTrace(
    host,
    `${passLabel}: refresh=${refreshVisibleRange ? 1 : 0}, scrollerRange=${refreshedByScroller ? 1 : 0}, `
    + `roughFallback=${allowRoughFallback ? 1 : 0}, dayIndex=${host.dayIndex}, loadingMore=${host.loadingMore ? 1 : 0}, `
    + `dragging=${host.timelineSidebarDragging ? 1 : 0}, seek=${host.timelineSeekInProgress ? 1 : 0}`
  );
  if (!refreshedByScroller && allowRoughFallback && Date.now() < host.ignoreListFreezeUntilMs) {
    timelineGestureLogReleaseTrace(host, `${passLabel}: defer rough visible-range fallback during release freeze`);
    return;
  }
  if (!refreshedByScroller && allowRoughFallback) {
    host.syncListVisibleRoughToTimelineSliderTarget();
    timelineGestureLogReleaseTrace(host, `${passLabel}: apply rough visible-range fallback`);
  }
  if (!refreshedByScroller && !allowRoughFallback) {
    timelineGestureLogReleaseTrace(host, `${passLabel}: wait visible range callback`);
    return;
  }
  if (host.timelineSeekInProgress) {
    host.loadVisibleItemsInteractiveVisiblePriority();
  } else {
    host.loadVisibleItemsThrottled(true, false);
  }
  if (refreshedByScroller && !host.timelineSeekInProgress) {
    host.refreshRootPhotosScrollTitle();
  }
  timelineGestureLogReleaseTrace(
    host,
    `${passLabel}: kick ${host.timelineSeekInProgress ? 'timeline-seek' : 'list-driven'} visible load, `
    + `scrollerRange=${refreshedByScroller ? 1 : 0}, roughFallback=${allowRoughFallback ? 1 : 0}`
  );
}

export function timelineGestureKickPostTimelineReleaseLoad(host: TimelineGestureControllerHost): void {
  const releaseGen = host.timelineDragWatchdogGen;
  const passes: TimelineReleaseVisiblePassPlan[] = [];
  const pass0 = new TimelineReleaseVisiblePassPlan();
  pass0.delayMs = 0;
  pass0.refreshVisibleRange = true;
  pass0.allowRoughFallback = false;
  pass0.label = 'pass0';
  passes.push(pass0);

  const pass1 = new TimelineReleaseVisiblePassPlan();
  pass1.delayMs = 120;
  pass1.refreshVisibleRange = true;
  pass1.allowRoughFallback = false;
  pass1.label = 'pass1';
  passes.push(pass1);

  const pass2 = new TimelineReleaseVisiblePassPlan();
  pass2.delayMs = 280;
  pass2.refreshVisibleRange = true;
  pass2.allowRoughFallback = true;
  pass2.label = 'pass2';
  passes.push(pass2);

  const pass3 = new TimelineReleaseVisiblePassPlan();
  pass3.delayMs = 520;
  pass3.refreshVisibleRange = true;
  pass3.allowRoughFallback = true;
  pass3.label = 'pass3';
  passes.push(pass3);
  for (let i = 0; i < passes.length; i++) {
    const pass = passes[i];
    setTimeout((): void => {
      if (releaseGen !== host.timelineDragWatchdogGen) {
        return;
      }
      if (host.timelineSidebarDragging) {
        return;
      }
      timelineGestureRunReleaseVisiblePass(
        host,
        pass.refreshVisibleRange,
        pass.allowRoughFallback,
        pass.label
      );
    }, pass.delayMs);
  }
}

function timelineGesturePreemptStaleRequestsForVisiblePriority(host: TimelineGestureControllerHost): void {
  timelineGestureCancelListSettledTimer(host);
  host.pumpEpoch++;
  host.isDraggingOrFling = false;
  host.listKineticScrolling = false;
  host.visualPlaceholderMode = false;
  const client = AppSession.getClient();
  if (client !== null) {
    client.cancelPendingRequests();
  }
  timelineGestureLogScrollDebug(
    host,
    `timeline release: preempt stale requests for visible priority (preserve inflight=${host.loadingMore ? 1 : 0})`
  );
}

function timelineGestureScheduleReleaseVisiblePriority(host: TimelineGestureControllerHost): void {
  const releaseGen = host.timelineDragWatchdogGen;
  setTimeout((): void => {
    if (releaseGen !== host.timelineDragWatchdogGen) {
      return;
    }
    if (host.timelineSidebarDragging) {
      return;
    }
    timelineGesturePreemptStaleRequestsForVisiblePriority(host);
    timelineGestureRefreshVisualPlaceholderMode(host);
    host.flushPendingFlowRebuild();
    const refreshedVisibleRange = host.refreshVisibleRangeIfAvailable();
    if (refreshedVisibleRange) {
      host.tryHandOffTimelineSeekToListDriven('releasePriority');
    }
    timelineGestureLogReleaseTrace(
      host,
      `releasePriority: scrollerRange=${refreshedVisibleRange ? 1 : 0}, dayIndex=${host.dayIndex}, `
      + `loadingMore=${host.loadingMore ? 1 : 0}, exhausted=${host.exhausted ? 1 : 0}`
    );
    if (host.timelineSeekInProgress && !refreshedVisibleRange) {
      host.syncListVisibleRoughToTimelineSliderTarget();
      timelineGestureLogReleaseTrace(host, 'releasePriority: apply rough visible-range fallback');
    }
    if (refreshedVisibleRange && !host.timelineSeekInProgress) {
      host.refreshRootPhotosScrollTitle();
    }
    if (host.timelineSeekInProgress) {
      host.loadVisibleItemsInteractiveVisiblePriority();
      timelineGestureLogReleaseTrace(host, 'releasePriority: keep timeline-seek visible-priority load');
      timelineGestureKickPostTimelineReleaseLoad(host);
    } else {
      host.loadVisibleItemsThrottled(true, false);
      timelineGestureLogReleaseTrace(host, 'releasePriority: handoff complete, resume list-driven load');
    }
    timelineGestureShowTimelineBar(host);
    const settledEpoch = host.pumpEpoch;
    setTimeout((): void => {
      if (settledEpoch !== host.pumpEpoch || host.timelineSidebarDragging || host.isDraggingOrFling) {
        return;
      }
      host.runMainListScrollSettledWork();
    }, 220);
  }, 24);
}

export function timelineGestureEndTimelineDrag(host: TimelineGestureControllerHost): void {
  timelineGestureCancelTimelineDragWatchdog(host);
  host.timelineDragWatchdogGen++;
  host.ignoreListFreezeUntilMs = Date.now() + GALLERY_TIMELINE_SEEK_RELEASE_FREEZE_MS;
  host.timelineSeekNoScrollerGuardUntilMs = Date.now() + GALLERY_TIMELINE_SEEK_NO_SCROLLER_GUARD_MS;
  host.timelineSidebarDragging = false;
  host.timelinePressing = false;
  host.timelineLongPressExpanded = false;
  timelineGestureRefreshVisualPlaceholderMode(host);
  host.timelineSeekInProgress = true;
  const total = host.flowDataSource.totalCount();
  const prevFirst = Math.max(0, Math.min(total - 1, host.listVisibleFirstNodeIdx));
  const prevLast = Math.max(prevFirst, Math.min(total - 1, host.listVisibleLastNodeIdx));
  const prevAnchor = total > 0 ? Math.max(0, Math.min(total - 1, Math.floor((prevFirst + prevLast) / 2))) : -1;
  host.seekTimelineListToDisplayRatio(host.timelineSliderRatio);
  if (total > 0 && prevAnchor >= 0 &&
    Number.isFinite(host.timelineSeekAnchorNodeIdx) && host.timelineSeekAnchorNodeIdx >= 0) {
    const targetAnchor = Math.max(0, Math.min(total - 1, Math.floor(host.timelineSeekAnchorNodeIdx)));
    if (Math.abs(targetAnchor - prevAnchor) >= 1) {
      host.visibleLoadPreferBottomFirst = targetAnchor > prevAnchor;
      timelineGestureLogReleaseTrace(
        host,
        `endDrag: seed visible priority -> ${host.visibleLoadPreferBottomFirst ? 'bottom-first' : 'top-first'}, `
        + `prevAnchor=${prevAnchor}, targetAnchor=${targetAnchor}`
      );
    }
  }
  const ym = host.resolveYearMonthByTimelineRatio(host.timelineSliderRatio);
  if (ym !== null) {
    host.startTimelineSeekWatchdog(ym.year, ym.month);
  }
  timelineGestureLogReleaseTrace(
    host,
    `endDrag: ratio=${host.timelineSliderRatio.toFixed(4)}, target=${ym === null ? 'none' : `${ym.year}-${ym.month}`}, `
    + `visibleInFlow=${ym !== null && host.flowHasVisibleYearMonth(ym.year, ym.month) ? 1 : 0}`
  );
  timelineGestureScheduleReleaseVisiblePriority(host);
}
