import { GalleryWaterFlowDataSource } from '../GalleryFlowDataSource';
import { GalleryViewGranularity } from './GalleryAlbumGranularity';
import { GalleryThumbHitRect, TimelineDayModel } from './GalleryAlbumTabTypes';

export class GalleryAlbumModeRuntime {
  searchQuery: string = '';
  personStatGen: number = 0;
  personStatOverrides: Map<string, string> = new Map<string, string>();
  navigationGuardEpoch: number = 0;
}

export class GalleryAlbumSelectionRuntime {
  gallerySelectedIds: string[] = [];
  galleryThumbHitBounds: Map<string, GalleryThumbHitRect> = new Map<string, GalleryThumbHitRect>();
  searchThumbHitBounds: Map<string, GalleryThumbHitRect> = new Map<string, GalleryThumbHitRect>();
  gallerySlideRefX: number = 0;
  gallerySlideRefY: number = 0;
  gallerySlideHasRef: boolean = false;
  gallerySlideAnchorFlat: number = -1;
  gallerySlideUnionBase: string[] = [];
  gallerySlideLastEndFlat: number = -1;
  gallerySlideLastAppliedEndFlat: number = -99999;
  gallerySlideLastApplyMs: number = 0;
  gallerySlidePendingEndFlat: number = -1;
  galleryMainListDomId: string = 'gallery_album_main_list';
  gallerySlideAutoScrollTimer: number = -1;
  gallerySlideAutoScrollVelocityVp: number = 0;
  gallerySlideAutoScrollPointerX: number = 0;
  gallerySlideAutoScrollPointerY: number = 0;
  galleryLongPressIgnoreClickUntil: number = 0;
}

export class GalleryAlbumVisibleRuntime {
  listKineticScrolling: boolean = false;
  isDraggingOrFling: boolean = false;
  visualPlaceholderMode: boolean = false;
  listSettledTimer: number = -1;
  listSettledGen: number = 0;
  lastScrollDebugLogMs: number = 0;
  lastScrollDebugState: string = 'init';
  lastMainListInteractMs: number = 0;
  lastMainListScrollOffsetVp: number = 0;
  lastMainListScrollOffsetHave: boolean = false;
  visibleLoadPreferBottomFirst: boolean = false;
  listVisibleFirstNodeIdx: number = 0;
  listVisibleLastNodeIdx: number = 0;
  listScrollIndexAnchorYVp: number = 0;
  listScrollIndexAnchorFirst: number = 0;
  listScrollIndexAnchorHave: boolean = false;
  lastKnownGlobalPhotoSlotStart: number = 0;
  lastKnownGlobalPhotoSlotEndExclusive: number = 0;
  readonly visiblePhotoBufferSlots: number = 12;
  lastLoadVisibleAtMs: number = 0;
  loadVisibleRetryTimer: number = -1;
  loadVisibleRetryGen: number = 0;
  visibleBandPumpRunIdSeq: number = 0;
  visibleBandPumpActiveRunId: number = -1;
  visibleBandPumpActiveEpoch: number = -1;
  ignoreListFreezeUntilMs: number = 0;
  pendingFlowRebuild: boolean = false;
  lastVisibleLoadDayIdx: number = -1;
  lastInteractiveVisibleRangeRefreshAtMs: number = 0;
}

export class GalleryAlbumTimelineGestureRuntime {
  timelineDragWatchdogTimer: number = -1;
  timelineDragWatchdogGen: number = 0;
  lastTimelineBarTouchMs: number = 0;
  lastTimelineHandleSyncMs: number = 0;
  timelineHideTimer: number = -1;
  timelineSeekInProgress: boolean = false;
  timelineSeekGen: number = 0;
  timelineSeekAnchorNodeIdx: number = -1;
  timelineSeekNoScrollerGuardUntilMs: number = 0;
  timelineReleaseAwaitVisibleCallback: boolean = false;
  timelineSeekStableVisibleFirstNodeIdx: number = -1;
  timelineSeekStableVisibleLastNodeIdx: number = -1;
  timelineSeekStableVisibleHits: number = 0;
}

export class GalleryAlbumLoadRuntime {
  flowDataSource: GalleryWaterFlowDataSource = new GalleryWaterFlowDataSource();
  loadGen: number = 0;
  orderedDays: TimelineDayModel[] = [];
  dayGlobalSlotStarts: number[] = [];
  dayIndex: number = 0;
  loadingMore: boolean = false;
  exhausted: boolean = false;
  dayOffsets: Map<string, number> = new Map<string, number>();
  dayRounds: Map<string, number> = new Map<string, number>();
  dayEmptyRounds: Map<string, number> = new Map<string, number>();
  pumpEpoch: number = 0;
  bootstrapDebounceTimer: number = -1;
  lastBootstrapSatisfiedRefreshVersion: number = 0;
  handledDeleteSyncVersion: number = 0;
  galleryTimelineRefreshEpoch: number = 0;
  galleryTimelineAtTopForPull: boolean = true;
  galleryPullRefreshThresholdHapticDone: boolean = false;
}

export class GalleryAlbumRootSurfaceRuntime {
  rootPhotosScrolledUnderTopBar: boolean = false;
  rootPhotosTitlePreferListAnchorUntilMs: number = 0;
  albumsHomeSmartPrefetchGen: number = 0;
  albumsHomePersonPrefetchGen: number = 0;
  albumsHomeUserAlbumPrefetchGen: number = 0;
  albumsHomeMediaPrefetchGen: number = 0;
  lastHomeSurface: string = 'photos';
  lastAlbumsHomeRefreshVersion: number = 0;
  rootSurfaceSwitchStartTimer: number = -1;
  rootSurfaceSwitchTimer: number = -1;
  rootSurfaceSwitchFrom: string = 'photos';
  rootSurfaceSwitchTo: string = 'photos';
  lastGranularityMotionMode: GalleryViewGranularity = GalleryViewGranularity.DAY;
  skipNextGranularityHostMotion: boolean = false;
  granularityPinchActive: boolean = false;
}

/**
 * 非响应式运行态容器。@State/@Prop/@Watch 仍留在 GalleryAlbumTab shell。
 * 每个字段只有一份存储，页面通过 this.session.<domain>.<field> 访问。
 */
export class GalleryAlbumSession {
  mode: GalleryAlbumModeRuntime = new GalleryAlbumModeRuntime();
  selection: GalleryAlbumSelectionRuntime = new GalleryAlbumSelectionRuntime();
  visible: GalleryAlbumVisibleRuntime = new GalleryAlbumVisibleRuntime();
  timeline: GalleryAlbumTimelineGestureRuntime = new GalleryAlbumTimelineGestureRuntime();
  load: GalleryAlbumLoadRuntime = new GalleryAlbumLoadRuntime();
  root: GalleryAlbumRootSurfaceRuntime = new GalleryAlbumRootSurfaceRuntime();
  scrollerRef: Scroller = new Scroller();
  albumsScroller: Scroller = new Scroller();
  searchScroller: Scroller = new Scroller();
  titleBarScrollerBindList: Scroller[] = [];
}
