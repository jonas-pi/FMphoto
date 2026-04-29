/**
 * 原生相册 Tab（对齐 fnos_gallery_mobile.py 第 2~4 段主流程）。
 *
 * 数据链路：
 *   timeline -> 按日降序 -> 每日 getList 顺序分页
 *   偏移量由 dayOffsets 等非响应式 Map 同步维护，避免 @State 延迟导致重复请求。
 *
 * 加载策略：
 *   使用自驱加载泵 pumpLoad，每批完成后自动调度下一批；
 *   不依赖滚动事件，规避 Drag gesture has been canceled 导致的加载停滞；
 *   onDidScroll 只作为兜底唤醒，不改变接口调用语义。
 *
 * 视图组织：
 *   主列表采用 List + LazyForEach；
 *   row 的 key 需要跟随 flat 槽位变化，保证 skeleton 与真实项切换时正确刷新；
 *   大图预览走独立页面 pages/GalleryPreview。
 */
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { isHttpUnauthorizedMessage, tryRecoverSessionAfterAuthFailure } from '../auth/SessionReauth';
import { SessionPreferences } from '../auth/SessionPreferences';
import {
  AiPersonItem,
  GalleryGetListData,
  GalleryListItem,
  MagicSearchItem,
  MediaCategoryItem,
  SmartCategoryItem
} from '../model/FnApiTypes';
import {
  GalleryNetworkThumb,
  GalleryStaticThumbPlaceholder,
  GalleryThumbSkeleton,
  isGifItem,
  isVideoItem,
  nasUrl,
  pickThumb,
  recommendedThumbCacheKeep,
  THUMB_CACHE_MAX,
  trimThumbPixCache,
  trimThumbPixCacheForList,
} from './GalleryAlbumCommon';
import { GalleryFlowNode, GalleryWaterFlowDataSource } from './GalleryFlowDataSource';
import {
  GALLERY_SLIDE_DOM_BUDGET_PER_FRAME,
  GALLERY_SLIDE_FLOW_ROW_RADIUS,
  GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE,
  GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE,
  GALLERY_SLIDE_TAIL_FLOW_ROWS,
  pickIndexedFlatForSlidePointer
} from './GallerySlidePick';
import { GalleryPreviewNavStore } from './GalleryPreviewNavStore';
import { CategoryGalleryNavStore } from './CategoryGalleryNavStore';
import { openPersonAlbumById } from './PersonAlbumOpenHelper';
import { openRecentAddedGallery } from './RecentAddedOpenHelper';
import { GalleryDeleteSyncStore } from './GalleryDeleteSyncStore';
import { GalleryTimelineRefreshStore } from './GalleryTimelineRefreshStore';
import {
  GalleryHomeDayPlain,
  GalleryHomeSectionPlain,
  GalleryHomeStringNumMapArrays,
  GalleryHomeTimelineCache,
  GalleryHomeTimelineSnapshot
} from './GalleryHomeTimelineCache';
import { gallerySetAlbumBackHandler } from './GalleryAlbumHardwareBack';
import {
  galleryItemsMatchingSelectedIds,
  runBatchDownloadGalleryItems
} from './GalleryBatchDownload';
import {
  playGalleryEnterSelectionHaptic,
  playGalleryPullRefreshThresholdHaptic
} from './GallerySelectionHaptic';
import {
  fnImmersiveBackgroundEffect,
  fnLiquidGlassGradient,
  FnFullLoadingMask
} from '../common/FnUiCommon';
import { FN_GLOBAL_TAB_SWITCH_CURVE, FN_GLOBAL_TAB_SWITCH_DURATION } from '../common/FnMotion';
import { GALLERY_TOP_BAR_PAD_RIGHT_VP } from '../common/GalleryTopBarLayout';
import {
  GalleryAlbumTopBar,
  GALLERY_TOP_BAR_FLOATING_TOTAL_HEIGHT_VP
} from './galleryAlbumTab/GalleryAlbumTopBar';
import { GalleryAlbumFloatingTopBarLayer } from './galleryAlbumTab/GalleryAlbumFloatingTopBarLayer';
import { GalleryAlbumAlbumsHomeView } from './galleryAlbumTab/GalleryAlbumAlbumsHomeView';
import { GalleryAlbumSearchModeView } from './galleryAlbumTab/GalleryAlbumSearchModeView';
import { GalleryAlbumCategoryModeView } from './galleryAlbumTab/GalleryAlbumCategoryModeView';
import { GalleryAlbumSmartCategoryModeView } from './galleryAlbumTab/GalleryAlbumSmartCategoryModeView';
import { GalleryAlbumPersonModeView } from './galleryAlbumTab/GalleryAlbumPersonModeView';
import { GalleryAlbumMainModeView } from './galleryAlbumTab/GalleryAlbumMainModeView';
import { GalleryViewGranularity, galleryViewGranularityColumns } from './galleryAlbumTab/GalleryAlbumGranularity';
import {
  categoryCount,
  categoryCover,
  categoryTitle,
  parseCategoryMedia,
  personFace,
  personId,
  personName,
  personStatText,
  smartCategoryCover,
  smartCategoryName,
} from './galleryAlbumTab/GalleryAlbumModeData';
import {
  galleryAlbumCountGalleryListedItems,
  galleryAlbumFlatItems,
  galleryAlbumGalleryFlowLazyKey,
  galleryAlbumItemIdOf,
  galleryAlbumRebuildFlow,
  galleryAlbumUpsertSection,
} from './galleryAlbumTab/GalleryAlbumFlowLogic';
import {
  loadCollectGalleryItems as requestCollectGalleryItems,
  loadMediaCategories as requestMediaCategories,
  loadPersons as requestPersons,
  loadRecentAddedItems as requestRecentAddedItems,
  loadSmartCategories as requestSmartCategories,
} from './galleryAlbumTab/GalleryAlbumModeLoaders';
import {
  galleryAlbumAskBatchDownloadImageQuality,
  galleryAlbumApplyDeleteSyncIfNeeded,
  galleryAlbumConfirmAndBatchDelete,
  galleryAlbumConfirmAndBatchDownload,
  GalleryAlbumBatchActionsHost,
} from './galleryAlbumTab/GalleryAlbumBatchActions';
import {
  galleryAlbumApplyMainTimelineCacheSnapshot,
  galleryAlbumBuildMainTimelineCacheSnapshot,
} from './galleryAlbumTab/GalleryAlbumCacheSnapshot';
import {
  buildTimelineScrubPillLabel,
  collectTimelineYearMarkers,
  collectTimelineYearMonths,
  findFlowRoughVisibleRangeForYearMonth,
  findFlowScrollIndexForYearMonth,
  findTimelineMonthRange,
  getTimelineHighlightDay,
  getTimelineHighlightMonth,
  getTimelineHighlightYear,
  hasFlowVisibleYearMonth,
  resolveTimelineSliderSyncResult,
  resolveTimelineYearMonthByRatio,
  timelineIndicatorYForRatio as calcTimelineIndicatorYForRatio,
} from './galleryAlbumTab/GalleryAlbumTimelineLogic';
import {
  galleryAlbumCalculateGlobalIndex,
  galleryAlbumFlowHasVisibleYearMonth,
  galleryAlbumGetCurrentHighlightDay,
  galleryAlbumGetCurrentHighlightMonth,
  galleryAlbumGetCurrentHighlightYear,
  galleryAlbumGetTimelineScrubPillLabel,
  galleryAlbumGetTimelineYearMonths,
  galleryAlbumGetYearMarkersForTrack,
  galleryAlbumResolveDayByGlobalIndex,
  galleryAlbumResolveYearMonthByTimelineRatio,
  galleryAlbumScrollListByRatioEstimate,
  galleryAlbumSeekTimelineListToDisplayRatio,
  galleryAlbumStartTimelineSeekWatchdog,
  galleryAlbumSyncListVisibleRoughToTimelineSliderTarget,
  galleryAlbumSyncTimelineSliderFromFirstIndex,
  galleryAlbumTimelineIndicatorYForRatio,
  galleryAlbumTryScrollListToYearMonthIfVisible,
} from './galleryAlbumTab/GalleryAlbumTimelineRuntime';
import {
  GalleryAlbumModeOrchestratorHost,
  galleryAlbumBackToMain,
  galleryAlbumClearCategory,
  galleryAlbumClearPerson,
  galleryAlbumClearSearch,
  galleryAlbumClearSmartCategory,
  galleryAlbumEnrichPersonStats,
  galleryAlbumLoadMediaCategories,
  galleryAlbumLoadPersons,
  galleryAlbumLoadSmartCategories,
  galleryAlbumOpenCategory,
  galleryAlbumOpenCollectGallery,
  galleryAlbumOpenPerson,
  galleryAlbumPlayModeSwitchMotion,
  galleryAlbumRunSearch,
  galleryAlbumStartUpload,
} from './galleryAlbumTab/GalleryAlbumModeOrchestrator';
import {
  GalleryAlbumLoadOrchestratorHost,
  galleryAlbumBootstrap,
  galleryAlbumLoadOneBatch,
  galleryAlbumMarkTimelineRefreshCaughtUp,
  galleryAlbumOnTabVisibleAgain,
  galleryAlbumOnTimelinePullRefresh,
  galleryAlbumPumpLoad,
  galleryAlbumRefreshMediaCategoriesInPlace,
  galleryAlbumRefreshPersonListInPlace,
  galleryAlbumRefreshSmartCategoriesInPlace,
  galleryAlbumSyncTimelineAtTopForPull,
} from './galleryAlbumTab/GalleryAlbumLoadOrchestrator';
import {
  GalleryAlbumVisibleLoadHost,
  galleryAlbumVisibleAlignPumpToTimelineSliderTarget,
  galleryAlbumVisibleApproxGalleryFlowListNodeHeightVp,
  galleryAlbumVisibleCaptureListScrollIndexAnchor,
  galleryAlbumVisibleComputeLoadVisibleBufferAfterSlots,
  galleryAlbumVisibleConsumeVerticalScrollDeltaAsNodeIndex,
  galleryAlbumVisibleConsumeVerticalScrollDeltaAsNodeIndexBackward,
  galleryAlbumVisibleCountPhotoSlotsBeforeNode,
  galleryAlbumVisibleCountSkeletonPhotoSlotsInFlowNodeRange,
  galleryAlbumVisibleEstimateFirstVisibleNodeIndexFromScrollY,
  galleryAlbumVisibleFlushPendingFlowRebuild,
  galleryAlbumVisibleForceRefreshVisibleRange,
  galleryAlbumVisibleRefreshVisibleRangeIfAvailable,
  galleryAlbumVisibleGlobalSlotIndexAtDayStart,
  galleryAlbumVisibleLoadVisibleItems,
  galleryAlbumVisibleLoadVisibleItemsImmediate,
  galleryAlbumVisibleLoadVisibleItemsThrottled,
  galleryAlbumVisibleNudgeListScrollForScrollIndexRefresh,
  galleryAlbumVisiblePumpVisibleDayBandAllChunks,
  galleryAlbumVisiblePumpVisibleDayBandSequential,
  galleryAlbumVisibleRefineVisibleNodeIndicesAgainstScrollLag,
  galleryAlbumVisibleRefreshLastKnownGlobalSlotsFromListIndices,
  galleryAlbumVisibleTryApplyScrollerVisibleRangeIfAvailable,
} from './galleryAlbumTab/GalleryAlbumVisibleLoadController';
import {
  SelectionGestureControllerHost,
  selectionApplyGallerySlideRowRangeSelection,
  selectionBeginGallerySlideSelectGesture,
  selectionBeginGallerySlideSelectGestureAtWindowPx,
  selectionEndGallerySlideSelectGesture,
  selectionHitGalleryThumbDomPx,
  selectionHitSearchThumbDomPx,
  selectionOnGallerySlidePanUpdate,
  selectionOnGallerySlideTouchMoveWindow,
  selectionOnGalleryThumbLongPress,
  selectionOnGalleryThumbTap,
  selectionOnSearchThumbTap,
  selectionPanOffsetVpToPx,
  selectionPickGalleryThumbFlatForRowOrCache,
  selectionPickGalleryThumbFlatUnderPoint,
  selectionPickGalleryThumbFlatUnderPointForSlide,
  selectionPickSearchThumbFlatForRow,
  selectionPickSearchThumbFlatUnderPoint,
  selectionReadGestureFingerWindow,
  selectionRecordSearchThumbRect,
  selectionResolveSlidePointerWindowPx,
  selectionSearchThumbDomId,
  selectionToggleGallerySelectedId,
} from './galleryAlbumTab/SelectionGestureController';
import {
  galleryAlbumCollectGalleryIdsInFlatRange,
  galleryAlbumCollectSearchIdsInFlatRange,
  galleryAlbumExitSelection,
  galleryAlbumGalleryThumbDomId,
  galleryAlbumOpenPreview,
  galleryAlbumRecordGalleryThumbRectFromDom,
  galleryAlbumResolveGalleryFlatIndexForOpenPreview,
  galleryAlbumSetGallerySelectedIdsState,
} from './galleryAlbumTab/GalleryAlbumSelectionSupport';
import {
  TimelineGestureControllerHost,
  timelineGestureArmTimelineDragWatchdog,
  timelineGestureCancelListSettledTimer,
  timelineGestureCancelTimelineDragWatchdog,
  timelineGestureEndTimelineDrag,
  timelineGestureIsInScrollInteractiveLogWindow,
  timelineGestureKickPostTimelineReleaseLoad,
  timelineGestureLogScrollDebug,
  timelineGestureMaybeLogMainScrollTick,
  timelineGestureRefreshVisualPlaceholderMode,
  timelineGestureRunMainListScrollSettledWork,
  timelineGestureScheduleMainListSettledWork,
  timelineGestureShowTimelineBar,
  timelineGestureSyncTimelineHandleFromListThrottled,
  timelineGestureTimelineScrubExpandedChrome,
  timelineGestureTimelineScrubScrollRailOnly,
  timelineGestureTouchTimelineBarOnScroll,
} from './galleryAlbumTab/TimelineGestureController';
import {
  GalleryAlbumRootSurfaceHost,
  galleryAlbumAlbumsHomeSmartItems,
  galleryAlbumBeginRootSurfaceSwitch,
  galleryAlbumClearRootSurfaceSwitchTimer,
  galleryAlbumCurrentBottomDockInsetVp,
  galleryAlbumEnsureAlbumsHomeSupplementaryData,
  galleryAlbumIsAlbumsHomeSurface,
  galleryAlbumIsPhotosHomeSurface,
  galleryAlbumIsRootAlbumsSurfaceLayerVisible,
  galleryAlbumIsRootAlbumsSurfaceVisible,
  galleryAlbumIsRootPhotosSurfaceLayerVisible,
  galleryAlbumIsRootPhotosSurfaceVisible,
  galleryAlbumIsRootSurfaceVisible,
  galleryAlbumMainGalleryContentInsetTopVp,
  galleryAlbumOnHomeSurfaceChanged,
  galleryAlbumOpenPersonPage,
  galleryAlbumOpenRecycleBinPage,
  galleryAlbumOpenSearchPanel,
  galleryAlbumOpenSmartCategoryPage,
  galleryAlbumResetRootSurfaceSwitchTransforms,
  galleryAlbumReturnToHomeSurfaceRoot,
  galleryAlbumRootAlbumsSurfaceZIndex,
  galleryAlbumRootPhotosSurfaceZIndex,
  galleryAlbumSecondaryModeContentInsetTopVp,
  galleryAlbumShouldKeepAlbumsHomeMounted,
  galleryAlbumShouldKeepRootPhotosMainMounted,
  galleryAlbumToggleMoreMenu,
  galleryAlbumSyncHomeSurface,
  galleryAlbumTryConsumeSurfaceBack
} from './galleryAlbumTab/GalleryAlbumRootSurfaceController';
import {
  GalleryAlbumRootTitleHost,
  galleryAlbumCurrentHomeSurfaceTitle,
  galleryAlbumMaybeRefreshRootPhotosScrollTitleForThreshold,
  galleryAlbumRebuildDayGlobalSlotStarts,
  galleryAlbumRefreshRootPhotosScrollTitle,
  galleryAlbumResolveDayByGlobalIndexFast,
  galleryAlbumSetOrderedDays
} from './galleryAlbumTab/GalleryAlbumRootTitleController';
import {
  GalleryAlbumLifecycleHost,
  galleryAlbumAboutToAppear,
  galleryAlbumAboutToDisappear,
  galleryAlbumClearBootstrapDebounceTimer,
  galleryAlbumEnterGallerySelectionModeFromToolbar,
  galleryAlbumOnEpochChange,
  galleryAlbumOnPageShow,
  galleryAlbumOnPageShowSignal,
  galleryAlbumRequestBootstrap
} from './galleryAlbumTab/GalleryAlbumLifecycleController';
import {
  DAY_MAX_ROUNDS,
  DATE_FEED_BATCH,
  EMPTY_PAGE_ADVANCE_THRESHOLD,
  GALLERY_BATCH_VERBOSE_LOG,
  GALLERY_BOOTSTRAP_DEBOUNCE_MS,
  GALLERY_LAST_KNOWN_DEGENERATE_NEW_SLOT_SPAN,
  GALLERY_LAST_KNOWN_MIN_PREV_SLOT_SPAN,
  GALLERY_LAST_KNOWN_SHRINK_IGNORE_RATIO,
  GALLERY_LIST_APPROX_DAY_NODE_VP,
  GALLERY_LIST_APPROX_MONTH_NODE_VP,
  GALLERY_LIST_APPROX_ROW_NODE_VP,
  GALLERY_LOAD_VISIBLE_BUFFER_AFTER_CAP,
  GALLERY_LOAD_VISIBLE_BUFFER_BASE_AGGRESSIVE,
  GALLERY_LOAD_VISIBLE_BUFFER_BASE_NON_AGGRESSIVE,
  GALLERY_LOAD_VISIBLE_BUFFER_SCAN_WIN_NODES,
  GALLERY_LOAD_VISIBLE_MULTI_DAY_CHAIN_MAX,
  GALLERY_LOAD_VISIBLE_SCROLLER_RANGE_PAD_NODES,
  GALLERY_LOAD_VISIBLE_SKELETON_SLOT_MULTIPLIER,
  GALLERY_RECENT_DAY_MAX_ROUNDS,
  GALLERY_RECENT_PAGE_LIMIT,
  GALLERY_REFINE_ANCHOR_RESYNC_NODE_DRIFT,
  GALLERY_REFINE_EST_ADV_MAX_DRIFT_NODES,
  GALLERY_REFINE_MIN_VISIBLE_NODE_SPAN,
  GALLERY_SCROLL_DEBUG_LOG,
  GALLERY_SCROLL_DELTA_CONSUME_MAX_IT,
  GALLERY_SCROLL_INTERACTIVE_LOG_WINDOW_MS,
  GALLERY_SCROLL_LOG_THROTTLE_MS,
  GALLERY_SCROLL_Y_ESTIMATE_MAX_NODES,
  GALLERY_TAB_DOMAIN as DOMAIN,
  GALLERY_TAB_TAG as TAG,
  GALLERY_TIMELINE_DRAG_WATCHDOG_MS,
  GALLERY_TIMELINE_EXPANDED_AUTO_HIDE_MS,
  GALLERY_TIMELINE_HIT_WIDTH_VP,
  GALLERY_TIMELINE_INDICATOR_PAD_VP,
  GALLERY_TIMELINE_INDICATOR_RESERVED_VP,
  GALLERY_TIMELINE_LONG_PRESS_EXPAND_MS,
  GALLERY_TIMELINE_RAIL_AUTO_HIDE_MS,
  GALLERY_TIMELINE_RAIL_DRAG_VP,
  GALLERY_TIMELINE_RAIL_EXPANDED_VP,
  GALLERY_TIMELINE_RAIL_MIN_VP,
  GALLERY_TIMELINE_REFRESH_OFFSET_VP,
  GALLERY_TIMELINE_SEEK_HANDOFF_MAX_DRIFT_NODES,
  GALLERY_TIMELINE_SEEK_HANDOFF_MAX_SPAN_NODES,
  GALLERY_TIMELINE_SEEK_HANDOFF_STABLE_HITS,
  GALLERY_TIMELINE_SCRUB_PILL_MIN_WIDTH_VP,
  GALLERY_TIMELINE_SCRUB_PILL_X_VP,
  GALLERY_TIMELINE_THUMB_VP,
  GALLERY_TIMELINE_TRACK_DOM_ID,
  GALLERY_TIMELINE_YEAR_BADGE_X_VP,
  GALLERY_UPLOAD_RECHECK_MS,
  PUMP_UI_GAP_MS,
} from './galleryAlbumTab/GalleryAlbumTabConstants';
import { GalleryAlbumDaySectionState } from './galleryAlbumTab/GalleryAlbumState';
import {
  DayGlobalResolveResult,
  dayKey,
  fmtDayEnd,
  fmtDayStart,
  GalleryFingerCoordCompat,
  GalleryFingerWindowPoint,
  GalleryScrollerMaybeVisibleRange,
  GalleryThumbHitRect,
  GalleryVisibleNodeRange,
  listFromData,
  parseTimelineDayCells,
  sortDaysDesc,
  TimelineDayModel,
  TimelineYearMonth,
  TimelineYearMonthPair,
  YearMarker,
  ymKey,
} from './galleryAlbumTab/GalleryAlbumTabTypes';

const GALLERY_GRANULARITY_HOST_SWITCH_DURATION_MS: number = 300;
const GALLERY_GRANULARITY_HOST_SWITCH_EXIT_MS: number = 110;
const GALLERY_GRANULARITY_HOST_SWITCH_OFFSET_VP: number = 18;
const GALLERY_GRANULARITY_HOST_SWITCH_START_OPACITY: number = 0.7;

// ─── Tab 组件 ─────────────────────────────────────────────────────────────

@Component
export struct GalleryAlbumTab {
  @Prop baseUrl: string = '';
  @Prop @Watch('onEpochChange') albumReloadEpoch: number = 0;
  @Prop topSafeInsetVp: number = 0;
  @Prop bottomSafeInsetVp: number = 0;
  @Prop floatingDockInsetBottomVp: number = 0;
  @Prop @Watch('onHomeSurfaceChanged') homeSurface: string = 'photos';
  @Prop @Watch('onViewGranularityChanged') viewGranularity: GalleryViewGranularity = GalleryViewGranularity.DAY;
  onSearchModeVisibilityChange: (hiddenBottomNav: boolean) => void = (_: boolean): void => {};
  onSelectionDockStateChange: (active: boolean, onDownload: () => void, onDelete: () => void) => void =
    (_: boolean, __: () => void, ___: () => void): void => {};
  /** Home.onPageShow() 递增后触发删除同步，作为不依赖子组件 onPageShow 传播的兜底。 */
  @Prop @Watch('onPageShowSignal') pageShowSignal: number = 0;

  @State private bootLoading: boolean = false;
  @State private loadError: string = '';
  @State private footText: string = '';
  @State private sections: GalleryAlbumDaySectionState[] = [];
  @State private rootPhotosScrollTitle: string = '\u56fe\u5e93';
  private rootPhotosScrolledUnderTopBar: boolean = false;
  private rootPhotosTitlePreferListAnchorUntilMs: number = 0;
  private lastInteractiveVisibleRangeRefreshAtMs: number = 0;
  private albumsHomeSmartPrefetchGen: number = 0;
  private albumsHomePersonPrefetchGen: number = 0;
  private albumsHomeMediaPrefetchGen: number = 0;
  private lastHomeSurface: string = 'photos';
  @State private rootModeContentWidthVp: number = 360;
  @State private rootPhotosSurfaceTranslateX: number = 0;
  @State private rootAlbumsSurfaceTranslateX: number = 0;
  @State private rootSurfaceSwitchAnimating: boolean = false;
  private rootSurfaceSwitchStartTimer: number = -1;
  private rootSurfaceSwitchTimer: number = -1;
  private rootSurfaceSwitchFrom: string = 'photos';
  private rootSurfaceSwitchTo: string = 'photos';

  // ── 搜索状态 ──────────────────────────────────────────────────────────────
  @State private searchQuery: string = '';
  @State @Watch('onSearchModeChanged') private inSearchMode: boolean = false;
  @State private searchResults: GalleryListItem[] = [];
  @State private searchLoading: boolean = false;
  @State private searchError: string = '';
  @State private moreMenuExpanded: boolean = false;
  @State private inCategoryMode: boolean = false;
  @State private categoryLoading: boolean = false;
  @State private categoryOpening: boolean = false;
  @State private categoryOpeningText: string = '打开中…';
  @State private categoryError: string = '';
  @State private categoryItems: MediaCategoryItem[] = [];
  @State private inSmartCategoryMode: boolean = false;
  @State private smartCategoryLoading: boolean = false;
  @State private smartCategoryError: string = '';
  @State private smartSceneItems: SmartCategoryItem[] = [];
  @State private smartInfoItems: SmartCategoryItem[] = [];
  @State private inPersonMode: boolean = false;
  @State private personLoading: boolean = false;
  @State private personOpening: boolean = false;
  @State private recentOpening: boolean = false;
  /** 打开“收藏”聚合列表时的全屏遮罩，与“最近添加”保持一致。 */
  @State private collectOpening: boolean = false;
  @State private personError: string = '';
  @State private personItems: AiPersonItem[] = [];
  @State private personStatVersion: number = 0;
  /** 上传状态 */
  @State private uploading: boolean = false;
  @State private uploadText: string = '';
  /** 主图库长按多选，已通过 draggable(false) 与系统拖拽中转站解耦。 */
  @State private gallerySelectionMode: boolean = false;
  @State private gallerySelectedIds: string[] = [];
  @State private galleryBatchDeleting: boolean = false;
  @State private galleryBatchDownloading: boolean = false;
  /**
   * 主时间线 List 是否响应手指滚动。
   * 划选时会临时关闭，避免 List 抢走 Pan；LazyForEach 的 row key 也不能随多选切换，
   * 否则子树重建会打断当前指下手势。
   */
  @State private galleryMainListScrollEnabled: boolean = true;
  /**
   * 统一交互状态机：
   * - timelineSidebarDragging: 时间轴手势进行中
   * - isDraggingOrFling: 主列表正在拖动或惯性滚动（Scroll/Fling）
   * - visualPlaceholderMode: 图片加载门控；时间轴拖动或主列表拖动/惯性时为 true
   *
   * 约束：任何图片请求开关都只看 visualPlaceholderMode，避免多状态互相覆盖。
   */
  @State private timelineSidebarDragging: boolean = false;
  @State private listKineticScrolling: boolean = false;
  @State private isDraggingOrFling: boolean = false;
  @State private visualPlaceholderMode: boolean = false;
  /** 主列表进入 Idle 后的 settled 防抖定时器 id，再次滚动时取消。 */
  private listSettledTimer: number = -1;
  /** settled 防抖代次，避免旧定时器回写。 */
  private listSettledGen: number = 0;
  /** 滚动排障：上次滚动日志时间戳。 */
  private lastScrollDebugLogMs: number = 0;
  /** 滚动排障：上次滚动状态文本，仅在状态变化或节流到期时打印。 */
  private lastScrollDebugState: string = 'init';
  /** 最近一次主列表交互时间，用于限制泵日志只在交互窗口输出。 */
  private lastMainListInteractMs: number = 0;
  private lastMainListScrollOffsetVp: number = 0;
  private lastMainListScrollOffsetHave: boolean = false;
  private visibleLoadPreferBottomFirst: boolean = false;
  /** 时间轴拖动 watchdog 定时器。 */
  private timelineDragWatchdogTimer: number = -1;
  /** 时间轴拖动会话代次，用于取消旧 watchdog 回写。 */
  private timelineDragWatchdogGen: number = 0;
  /** 滚动时触达时间轴显隐的节流时间戳，避免每帧重置 show/hide 定时器。 */
  private lastTimelineBarTouchMs: number = 0;
  /** 主列表到时间轴手柄位置同步的节流时间戳，避免 onScrollIndex 高频驱动手柄重绘。 */
  private lastTimelineHandleSyncMs: number = 0;
  private navigationGuardEpoch: number = 0;
  /** 时间轴是否显示：滚动或交互中显式可见，静止后自动淡出。 */
  @State private timelineBarVisible: boolean = false;
  /** 时间轴按压态：手指在轨道上，用于显隐与触感，不等同于“展开 scrub”。 */
  @State private timelinePressing: boolean = false;
  /** 长按细轨后进入完整展开态（年月气泡、年份刻度等），纵向拖动也会进入展开。 */
  @State private timelineLongPressExpanded: boolean = false;
  /** 滑块比例 [0,1]；0 表示最新，1 表示最旧。 */
  @State private timelineSliderRatio: number = 0;
  /** 褰撳墠楂樹寒鏈堜唤鍦ㄦ椂闂磋酱骞存湀鍒楄〃涓殑涓嬫爣 */
  @State private timelineSidebarHighlightIndex: number = 0;
  /** 指示标签的 Y 位置（vp）。 */
  @State private timelineIndicatorY: number = 12;
  /** 时间轴可用轨道高度（vp），由 onAreaChange 实测写入。 */
  @State private timelineScrubTrackHeightVp: number = 500;
  /** 自动隐藏定时器。 */
  private timelineHideTimer: number = -1;
  /** seek 保护标记：松手后短窗内阻断反向同步。 */
  private timelineSeekInProgress: boolean = false;
  /** seek 鐩戣鍣ㄤ唬娆★細鏂版嫋鍔ㄥ彲鍙栨秷鏃т换鍔?*/
  private timelineSeekGen: number = 0;
  /** 鏃堕棿杞寸▼搴忓寲 seek 鐨勫垪琛ㄩ敋鐐癸紝release 鍚庢嫿涓嶅埌 visible callback 鏃剁敤浜庤繎浼煎彲瑙嗗尯 */
  private timelineSeekAnchorNodeIdx: number = -1;
  /** 当前 List 可见节点区间，由 onScrollIndex 回传。 */
  private listVisibleFirstNodeIdx: number = 0;
  private listVisibleLastNodeIdx: number = 0;
  /**
   * onScrollIndex 最近一次回调时的 Scroller 纵向偏移与首索引。
   * LazyForEach + 全量骨架下，first/last 往往会明显滞后；这里用 (yNow - anchorY)
   * 向前推进节点索引，使其更贴近真实视口。
   */
  private listScrollIndexAnchorYVp: number = 0;
  private listScrollIndexAnchorFirst: number = 0;
  private listScrollIndexAnchorHave: boolean = false;
  /**
   * 全时间线“照片槽位”下标缓存，与 countPhotoSlotsBeforeNode 保持一致。
   * 若可见区只有标题行，onScrollIndex 可能返回 visEnd <= visStart，导致 loadVisible 不触发；
   * 这里使用最近一次有效可视槽位，作为松手静止后的加载锚点。
   */
  private lastKnownGlobalPhotoSlotStart: number = 0;
  private lastKnownGlobalPhotoSlotEndExclusive: number = 0;
  /** 可视区预加载缓冲，以“照片槽位”为单位。 */
  private readonly visiblePhotoBufferSlots: number = 12;
  /** 可视区驱动加载节流，避免 Idle 抖动时高频触发 loadVisibleItems。 */
  private lastLoadVisibleAtMs: number = 0;
  private loadVisibleRetryTimer: number = -1;
  private loadVisibleRetryGen: number = 0;
  private visibleBandPumpRunIdSeq: number = 0;
  private visibleBandPumpActiveRunId: number = -1;
  private visibleBandPumpActiveEpoch: number = -1;
  /** pump 代次：新滚动开始时递增，旧 pump/回调立即失效，用于打断并发链路。 */
  private pumpEpoch: number = 0;
  /** 时间轴松手后短窗内忽略程序化滚动对冻结态的回写，防止“必须再滑一下才加载”。 */
  private ignoreListFreezeUntilMs: number = 0;
  /** seek 后若拿不到 scroller visible range，在短时间内继续保持 anchor 优先。 */
  private timelineSeekNoScrollerGuardUntilMs: number = 0;
  private timelineReleaseAwaitVisibleCallback: boolean = false;
  private timelineSeekStableVisibleFirstNodeIdx: number = -1;
  private timelineSeekStableVisibleLastNodeIdx: number = -1;
  private timelineSeekStableVisibleHits: number = 0;
  /** 视觉冻结期收到的数据变更延迟到解冻后再一次性刷新，避免滚动条不跟手。 */
  private pendingFlowRebuild: boolean = false;
  /** 避免滚动停止后重复触发同一目标日的抢占加载。 */
  private lastVisibleLoadDayIdx: number = -1;
  /** 模式切换时内容层动效：淡入加轻微位移。 */
  @State private modeSwitchOpacity: number = 1;
  @State private modeSwitchOffsetY: number = 0;
  @State private renderedViewGranularity: GalleryViewGranularity = GalleryViewGranularity.DAY;
  private lastGranularityMotionMode: GalleryViewGranularity = GalleryViewGranularity.DAY;
  private granularitySwitchTimer: number = -1;
  /** WaterFlow + LazyForEach 数据源，与 sections 保持同步。 */
  private flowDataSource: GalleryWaterFlowDataSource = new GalleryWaterFlowDataSource();

  private loadGen: number = 0;
  private personStatGen: number = 0;
  private personStatOverrides: Map<string, string> = new Map<string, string>();
  private orderedDays: TimelineDayModel[] = [];
  private dayGlobalSlotStarts: number[] = [];
  private dayIndex: number = 0;
  private loadingMore: boolean = false;
  private exhausted: boolean = false;
  private dayOffsets: Map<string, number> = new Map<string, number>();
  /** 每天已请求的批次数，作为安全上限，防止 itemCount 不准时无限循环。 */
  private dayRounds: Map<string, number> = new Map<string, number>();
  /** 每天连续空页计数，防止单次空页误切日。 */
  private dayEmptyRounds: Map<string, number> = new Map<string, number>();
  private scrollerRef: Scroller = new Scroller();
  /** 上次已处理的删除同步版本号。 */
  private handledDeleteSyncVersion: number = 0;
  /** 长按后在此时间戳之前忽略单击，避免误进预览。 */
  private galleryLongPressIgnoreClickUntil: number = 0;
  /**
   * “划选段”进行中时为 true。该状态下 onDidScroll 不清空命中缓存，
   * 同时会把 Row 的 Pan 切为全向，以支持跨行划选。
   */
  @State private gallerySlideGestureActive: boolean = false;
  /** 各缩略图最近一次布局在窗口中的矩形；仅当前可见且已布局项有值，滚动时会清空以防脏矩形。 */
  private galleryThumbHitBounds: Map<string, GalleryThumbHitRect> = new Map<string, GalleryThumbHitRect>();
  /** AI 搜索结果列表的划选命中矩形，键为扁平下标字符串，与 `sg_${flat}` 对应。 */
  private searchThumbHitBounds: Map<string, GalleryThumbHitRect> = new Map<string, GalleryThumbHitRect>();
  /** 滑动连选时，fingerList 不可用则使用长按参考点加 Pan offset 估算指尖位置。 */
  private gallerySlideRefX: number = 0;
  private gallerySlideRefY: number = 0;
  private gallerySlideHasRef: boolean = false;
  /**
   * 划选锚点：长按起始缩略图在扁平列表中的下标，与 rowSlotFlatIndices 保持对齐。
   */
  private gallerySlideAnchorFlat: number = -1;
  /**
   * 进入本次划选前已选中的 id 快照。
   * begin 时拍下快照，保证缩回手指时只移除当前 flat 区间内、且不在原集合中的项目。
   */
  private gallerySlideUnionBase: string[] = [];
  /**
   * 当前划选区间终点 flat。指尖短暂离开缩略图时沿用上一次命中，避免选中状态闪烁。
   */
  private gallerySlideLastEndFlat: number = -1;
  /** 划选时仅在终点 flat 变化时提交 @State，减少整表刷新卡顿。 */
  private gallerySlideLastAppliedEndFlat: number = -99999;
  private gallerySlideLastApplyMs: number = 0;
  private gallerySlidePendingEndFlat: number = -1;
  /** 防抖定时器 id，小于 0 表示未挂起。 */
  private bootstrapDebounceTimer: number = -1;
  /** 与 GalleryTimelineRefreshStore.version 对齐；bootstrap 成功后更新，避免重复全量刷新。 */
  private lastBootstrapSatisfiedRefreshVersion: number = 0;
  /** 时间线 List 下拉刷新，绑定系统 Refresh 动效。 */
  @State private galleryTimelineRefreshing: boolean = false;
  /**
   * 时间线是否在列表顶端（Scroller 垂直偏移 <= 0）。
   * 这里不做成 @State，避免滚动时整页重绘；在 onDidScroll / 下拉回调前同步，
   * 仅用于判断是否允许触发刷新。
   */
  private galleryTimelineAtTopForPull: boolean = true;
  /** 下拉未回到顶部附近前，不重复触发“已达阈值”震动，避免来回拖动连续触发。 */
  private galleryPullRefreshThresholdHapticDone: boolean = false;

  private isMainGalleryModeActive(): boolean {
    return !this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode;
  }

  private notifyMainGallerySelectionVisualRefresh(): void {
    if (!this.isMainGalleryModeActive()) {
      return;
    }
    try {
      this.flowDataSource.notifyDataReload();
    } catch (_e) {
    }
  }

  private shouldUseHomeSelectionDock(): boolean {
    return this.isRootPhotosSurfaceVisible() && this.gallerySelectionMode;
  }

  private notifySelectionDockStateChange(): void {
    this.onSelectionDockStateChange(
      this.shouldUseHomeSelectionDock(),
      (): void => {
        void galleryAlbumConfirmAndBatchDownload(this.asBatchActionHost());
      },
      (): void => {
        void galleryAlbumConfirmAndBatchDelete(this.asBatchActionHost());
      }
    );
  }

  private dismissMoreMenu(): void {
    if (!this.moreMenuExpanded) {
      return;
    }
    this.moreMenuExpanded = false;
  }

  private setGallerySelectionModeState(value: boolean): void {
    if (this.gallerySelectionMode === value) {
      return;
    }
    this.gallerySelectionMode = value;
    if (value) {
      this.dismissMoreMenu();
    }
    this.notifyMainGallerySelectionVisualRefresh();
    this.notifySelectionDockStateChange();
  }

  private setGallerySelectedIdsStateLocal(value: string[]): void {
    this.gallerySelectedIds = value;
    this.notifyMainGallerySelectionVisualRefresh();
    this.notifySelectionDockStateChange();
  }

  private asSelectionGestureHost(): SelectionGestureControllerHost {
    const self = this;
    class SelectionGestureHostBridge implements SelectionGestureControllerHost {
      getUIContext() { return self.getUIContext(); }
      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(value: string) { self.baseUrl = value; }
      get inSearchMode(): boolean { return self.inSearchMode; }
      set inSearchMode(value: boolean) { self.inSearchMode = value; }
      get gallerySelectionMode(): boolean { return self.gallerySelectionMode; }
      set gallerySelectionMode(value: boolean) { self.setGallerySelectionModeState(value); }
      get galleryTimelineRefreshing(): boolean { return self.galleryTimelineRefreshing; }
      set galleryTimelineRefreshing(value: boolean) { self.galleryTimelineRefreshing = value; }
      get gallerySlideGestureActive(): boolean { return self.gallerySlideGestureActive; }
      set gallerySlideGestureActive(value: boolean) { self.gallerySlideGestureActive = value; }
      get galleryMainListScrollEnabled(): boolean { return self.galleryMainListScrollEnabled; }
      set galleryMainListScrollEnabled(value: boolean) { self.galleryMainListScrollEnabled = value; }
      get gallerySlideAnchorFlat(): number { return self.gallerySlideAnchorFlat; }
      set gallerySlideAnchorFlat(value: number) { self.gallerySlideAnchorFlat = value; }
      get gallerySlideUnionBase(): string[] { return self.gallerySlideUnionBase; }
      set gallerySlideUnionBase(value: string[]) { self.gallerySlideUnionBase = value; }
      get gallerySlideLastEndFlat(): number { return self.gallerySlideLastEndFlat; }
      set gallerySlideLastEndFlat(value: number) { self.gallerySlideLastEndFlat = value; }
      get gallerySlideLastAppliedEndFlat(): number { return self.gallerySlideLastAppliedEndFlat; }
      set gallerySlideLastAppliedEndFlat(value: number) { self.gallerySlideLastAppliedEndFlat = value; }
      get gallerySlideLastApplyMs(): number { return self.gallerySlideLastApplyMs; }
      set gallerySlideLastApplyMs(value: number) { self.gallerySlideLastApplyMs = value; }
      get gallerySlidePendingEndFlat(): number { return self.gallerySlidePendingEndFlat; }
      set gallerySlidePendingEndFlat(value: number) { self.gallerySlidePendingEndFlat = value; }
      get galleryLongPressIgnoreClickUntil(): number { return self.galleryLongPressIgnoreClickUntil; }
      set galleryLongPressIgnoreClickUntil(value: number) { self.galleryLongPressIgnoreClickUntil = value; }
      get gallerySlideRefX(): number { return self.gallerySlideRefX; }
      set gallerySlideRefX(value: number) { self.gallerySlideRefX = value; }
      get gallerySlideRefY(): number { return self.gallerySlideRefY; }
      set gallerySlideRefY(value: number) { self.gallerySlideRefY = value; }
      get gallerySlideHasRef(): boolean { return self.gallerySlideHasRef; }
      set gallerySlideHasRef(value: boolean) { self.gallerySlideHasRef = value; }
      get searchResults(): GalleryListItem[] { return self.searchResults; }
      set searchResults(value: GalleryListItem[]) { self.searchResults = value; }
      get flowDataSource(): GalleryWaterFlowDataSource { return self.flowDataSource; }
      set flowDataSource(value: GalleryWaterFlowDataSource) { self.flowDataSource = value; }
      get galleryThumbHitBounds(): Map<string, GalleryThumbHitRect> { return self.galleryThumbHitBounds; }
      set galleryThumbHitBounds(value: Map<string, GalleryThumbHitRect>) { self.galleryThumbHitBounds = value; }
      get searchThumbHitBounds(): Map<string, GalleryThumbHitRect> { return self.searchThumbHitBounds; }
      set searchThumbHitBounds(value: Map<string, GalleryThumbHitRect>) { self.searchThumbHitBounds = value; }
      get gallerySelectedIds(): string[] { return self.gallerySelectedIds; }
      set gallerySelectedIds(value: string[]) { self.setGallerySelectedIdsStateLocal(value); }
      itemIdOf(item: GalleryListItem): string { return galleryAlbumItemIdOf(item); }
      flatItems(): GalleryListItem[] { return galleryAlbumFlatItems(self.asVisibleLoadHost()); }
      galleryThumbDomId(photoId: string): string { return galleryAlbumGalleryThumbDomId(photoId); }
      recordGalleryThumbRectFromDom(photoId: string, domId: string): void {
        galleryAlbumRecordGalleryThumbRectFromDom(this, photoId, domId);
      }
      setGallerySelectedIdsState(ids: string[]): void { galleryAlbumSetGallerySelectedIdsState(this, ids); }
      toast(msg: string): void { self.toast(msg); }
      openPreview(flatIndex: number): void { galleryAlbumOpenPreview(this, flatIndex); }
      resolveGalleryFlatIndexForOpenPreview(item: GalleryListItem, hintFlat: number): number {
        return galleryAlbumResolveGalleryFlatIndexForOpenPreview(this, item, hintFlat);
      }
    }
    return new SelectionGestureHostBridge();
  }

  private asBatchActionHost(): GalleryAlbumBatchActionsHost {
    const self = this;
    class BatchActionHostBridge implements GalleryAlbumBatchActionsHost {
      getUIContext() { return self.getUIContext(); }
      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(value: string) { self.baseUrl = value; }
      get inSearchMode(): boolean { return self.inSearchMode; }
      set inSearchMode(value: boolean) { self.inSearchMode = value; }
      get gallerySelectedIds(): string[] { return self.gallerySelectedIds; }
      set gallerySelectedIds(value: string[]) { self.setGallerySelectedIdsStateLocal(value); }
      get galleryBatchDeleting(): boolean { return self.galleryBatchDeleting; }
      set galleryBatchDeleting(value: boolean) { self.galleryBatchDeleting = value; }
      get galleryBatchDownloading(): boolean { return self.galleryBatchDownloading; }
      set galleryBatchDownloading(value: boolean) { self.galleryBatchDownloading = value; }
      get searchResults(): GalleryListItem[] { return self.searchResults; }
      set searchResults(value: GalleryListItem[]) { self.searchResults = value; }
      get sections(): GalleryAlbumDaySectionState[] { return self.sections; }
      set sections(value: GalleryAlbumDaySectionState[]) { self.sections = value; }
      get handledDeleteSyncVersion(): number { return self.handledDeleteSyncVersion; }
      set handledDeleteSyncVersion(value: number) { self.handledDeleteSyncVersion = value; }
      toast(msg: string): void { self.toast(msg); }
      requestBootstrap(debounced: boolean): void { self.requestBootstrap(debounced); }
      exitGallerySelection(): void { galleryAlbumExitSelection(self.asSelectionGestureHost()); }
      itemIdOf(item: GalleryListItem): string { return galleryAlbumItemIdOf(item); }
      flatItems(): GalleryListItem[] { return galleryAlbumFlatItems(self.asVisibleLoadHost()); }
      rebuildFlow(): void { galleryAlbumRebuildFlow(self.asVisibleLoadHost()); }
    }
    return new BatchActionHostBridge();
  }

  private asTimelineGestureHost(): TimelineGestureControllerHost {
    const self = this;
    class TimelineGestureHostBridge implements TimelineGestureControllerHost {
      get scrollerRef(): Scroller { return self.scrollerRef; }
      set scrollerRef(value: Scroller) { self.scrollerRef = value; }
      get flowDataSource(): GalleryWaterFlowDataSource { return self.flowDataSource; }
      set flowDataSource(value: GalleryWaterFlowDataSource) { self.flowDataSource = value; }
      get orderedDays(): TimelineDayModel[] { return self.orderedDays; }
      set orderedDays(value: TimelineDayModel[]) { self.setOrderedDays(value); }
      get dayGlobalSlotStarts(): number[] { return self.dayGlobalSlotStarts; }
      set dayGlobalSlotStarts(value: number[]) { self.dayGlobalSlotStarts = value; }
      get sections(): GalleryAlbumDaySectionState[] { return self.sections; }
      set sections(value: GalleryAlbumDaySectionState[]) { self.sections = value; }
      get visualPlaceholderMode(): boolean { return self.visualPlaceholderMode; }
      set visualPlaceholderMode(value: boolean) { self.visualPlaceholderMode = value; }
      get timelineSidebarDragging(): boolean { return self.timelineSidebarDragging; }
      set timelineSidebarDragging(value: boolean) { self.timelineSidebarDragging = value; }
      get isDraggingOrFling(): boolean { return self.isDraggingOrFling; }
      set isDraggingOrFling(value: boolean) { self.isDraggingOrFling = value; }
      get timelineBarVisible(): boolean { return self.timelineBarVisible; }
      set timelineBarVisible(value: boolean) { self.timelineBarVisible = value; }
      get timelinePressing(): boolean { return self.timelinePressing; }
      set timelinePressing(value: boolean) { self.timelinePressing = value; }
      get timelineLongPressExpanded(): boolean { return self.timelineLongPressExpanded; }
      set timelineLongPressExpanded(value: boolean) { self.timelineLongPressExpanded = value; }
      get timelineDragWatchdogTimer(): number { return self.timelineDragWatchdogTimer; }
      set timelineDragWatchdogTimer(value: number) { self.timelineDragWatchdogTimer = value; }
      get timelineDragWatchdogGen(): number { return self.timelineDragWatchdogGen; }
      set timelineDragWatchdogGen(value: number) { self.timelineDragWatchdogGen = value; }
      get lastMainListInteractMs(): number { return self.lastMainListInteractMs; }
      set lastMainListInteractMs(value: number) { self.lastMainListInteractMs = value; }
      get lastTimelineBarTouchMs(): number { return self.lastTimelineBarTouchMs; }
      set lastTimelineBarTouchMs(value: number) { self.lastTimelineBarTouchMs = value; }
      get lastTimelineHandleSyncMs(): number { return self.lastTimelineHandleSyncMs; }
      set lastTimelineHandleSyncMs(value: number) { self.lastTimelineHandleSyncMs = value; }
      get lastScrollDebugLogMs(): number { return self.lastScrollDebugLogMs; }
      set lastScrollDebugLogMs(value: number) { self.lastScrollDebugLogMs = value; }
      get lastScrollDebugState(): string { return self.lastScrollDebugState; }
      set lastScrollDebugState(value: string) { self.lastScrollDebugState = value; }
      get listSettledTimer(): number { return self.listSettledTimer; }
      set listSettledTimer(value: number) { self.listSettledTimer = value; }
      get listSettledGen(): number { return self.listSettledGen; }
      set listSettledGen(value: number) { self.listSettledGen = value; }
      get listKineticScrolling(): boolean { return self.listKineticScrolling; }
      set listKineticScrolling(value: boolean) { self.listKineticScrolling = value; }
      get dayIndex(): number { return self.dayIndex; }
      set dayIndex(value: number) { self.dayIndex = value; }
      get exhausted(): boolean { return self.exhausted; }
      set exhausted(value: boolean) { self.exhausted = value; }
      get loadingMore(): boolean { return self.loadingMore; }
      set loadingMore(value: boolean) { self.loadingMore = value; }
      get bootLoading(): boolean { return self.bootLoading; }
      set bootLoading(value: boolean) { self.bootLoading = value; }
      get gallerySlideGestureActive(): boolean { return self.gallerySlideGestureActive; }
      set gallerySlideGestureActive(value: boolean) { self.gallerySlideGestureActive = value; }
      get galleryMainListScrollEnabled(): boolean { return self.galleryMainListScrollEnabled; }
      set galleryMainListScrollEnabled(value: boolean) { self.galleryMainListScrollEnabled = value; }
      get timelineSeekInProgress(): boolean { return self.timelineSeekInProgress; }
      set timelineSeekInProgress(value: boolean) { self.timelineSeekInProgress = value; }
      get timelineHideTimer(): number { return self.timelineHideTimer; }
      set timelineHideTimer(value: number) { self.timelineHideTimer = value; }
      get timelineSliderRatio(): number { return self.timelineSliderRatio; }
      set timelineSliderRatio(value: number) { self.timelineSliderRatio = value; }
      get timelineScrubTrackHeightVp(): number { return self.timelineScrubTrackHeightVp; }
      set timelineScrubTrackHeightVp(value: number) { self.timelineScrubTrackHeightVp = value; }
      get timelineSidebarHighlightIndex(): number { return self.timelineSidebarHighlightIndex; }
      set timelineSidebarHighlightIndex(value: number) { self.timelineSidebarHighlightIndex = value; }
      get timelineIndicatorY(): number { return self.timelineIndicatorY; }
      set timelineIndicatorY(value: number) { self.timelineIndicatorY = value; }
      get timelineSeekGen(): number { return self.timelineSeekGen; }
      set timelineSeekGen(value: number) { self.timelineSeekGen = value; }
      get timelineSeekAnchorNodeIdx(): number { return self.timelineSeekAnchorNodeIdx; }
      set timelineSeekAnchorNodeIdx(value: number) { self.timelineSeekAnchorNodeIdx = value; }
      get visibleLoadPreferBottomFirst(): boolean { return self.visibleLoadPreferBottomFirst; }
      set visibleLoadPreferBottomFirst(value: boolean) { self.visibleLoadPreferBottomFirst = value; }
      get listVisibleFirstNodeIdx(): number { return self.listVisibleFirstNodeIdx; }
      set listVisibleFirstNodeIdx(value: number) { self.listVisibleFirstNodeIdx = value; }
      get listVisibleLastNodeIdx(): number { return self.listVisibleLastNodeIdx; }
      set listVisibleLastNodeIdx(value: number) { self.listVisibleLastNodeIdx = value; }
      get ignoreListFreezeUntilMs(): number { return self.ignoreListFreezeUntilMs; }
      set ignoreListFreezeUntilMs(value: number) { self.ignoreListFreezeUntilMs = value; }
      get timelineSeekNoScrollerGuardUntilMs(): number { return self.timelineSeekNoScrollerGuardUntilMs; }
      set timelineSeekNoScrollerGuardUntilMs(value: number) { self.timelineSeekNoScrollerGuardUntilMs = value; }
      get pumpEpoch(): number { return self.pumpEpoch; }
      set pumpEpoch(value: number) { self.pumpEpoch = value; }
      flowNodeIndexFromListIndex(index: number): number { return self.flowNodeIndexFromMainListIndex(index); }
      listIndexFromFlowNodeIndex(index: number): number { return self.mainListIndexFromFlowNodeIndex(index); }
      refreshLastKnownGlobalSlotsFromListIndices(firstIdx: number, lastIdx: number): void {
        galleryAlbumVisibleRefreshLastKnownGlobalSlotsFromListIndices(self.asVisibleLoadHost(), firstIdx, lastIdx);
      }
      captureListScrollIndexAnchor(): void {
        galleryAlbumVisibleCaptureListScrollIndexAnchor(self.asVisibleLoadHost());
      }
      refreshVisibleRangeIfAvailable(): boolean {
        return galleryAlbumVisibleRefreshVisibleRangeIfAvailable(self.asVisibleLoadHost());
      }
      forceRefreshVisibleRange(): boolean {
        return galleryAlbumVisibleForceRefreshVisibleRange(self.asVisibleLoadHost());
      }
      tryHandOffTimelineSeekToListDriven(reason: string): boolean {
        return self.tryHandOffTimelineSeekToListDrivenFromScroller(reason);
      }
      resolveYearMonthByTimelineRatio(ratio: number): TimelineYearMonthPair | null {
        return galleryAlbumResolveYearMonthByTimelineRatio(this, ratio);
      }
      flowHasVisibleYearMonth(year: number, month: number): boolean {
        return galleryAlbumFlowHasVisibleYearMonth(this, year, month);
      }
      startTimelineSeekWatchdog(year: number, month: number): void {
        galleryAlbumStartTimelineSeekWatchdog(this, year, month);
      }
      seekTimelineListToDisplayRatio(ratio: number): void { galleryAlbumSeekTimelineListToDisplayRatio(this, ratio); }
      syncGalleryTimelineAtTopForPull(): void { galleryAlbumSyncTimelineAtTopForPull(self.asLoadOrchestratorHost()); }
      clearGalleryThumbHitBounds(): void { self.galleryThumbHitBounds.clear(); }
      flushPendingFlowRebuild(): void { galleryAlbumVisibleFlushPendingFlowRebuild(self.asVisibleLoadHost()); }
      loadVisibleItemsThrottled(forceImmediate?: boolean, aggressive?: boolean): void {
        galleryAlbumVisibleLoadVisibleItemsThrottled(self.asVisibleLoadHost(), forceImmediate, aggressive);
      }
      loadVisibleItemsImmediate(): void { galleryAlbumVisibleLoadVisibleItemsImmediate(self.asVisibleLoadHost()); }
      loadVisibleItemsInteractiveVisiblePriority(): void {
        galleryAlbumVisibleLoadVisibleItemsThrottled(self.asVisibleLoadHost(), true, true, true);
      }
      syncListVisibleRoughToTimelineSliderTarget(): void { galleryAlbumSyncListVisibleRoughToTimelineSliderTarget(this); }
      refreshRootPhotosScrollTitle(): void { self.refreshRootPhotosScrollTitle(); }
      pumpLoad(singleBatch?: boolean): void { galleryAlbumPumpLoad(self.asLoadOrchestratorHost(), singleBatch); }
      runMainListScrollSettledWork(epochAtSchedule?: number): void {
        timelineGestureRunMainListScrollSettledWork(this, epochAtSchedule);
      }
    }
    return new TimelineGestureHostBridge();
  }

  private asModeOrchestratorHost(): GalleryAlbumModeOrchestratorHost {
    const self = this;
    class ModeOrchestratorHostBridge implements GalleryAlbumModeOrchestratorHost {
      getUIContext() { return self.getUIContext(); }
      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(value: string) { self.baseUrl = value; }
      get modeSwitchOpacity(): number { return self.modeSwitchOpacity; }
      set modeSwitchOpacity(value: number) { self.modeSwitchOpacity = value; }
      get modeSwitchOffsetY(): number { return self.modeSwitchOffsetY; }
      set modeSwitchOffsetY(value: number) { self.modeSwitchOffsetY = value; }
      get inSearchMode(): boolean { return self.inSearchMode; }
      set inSearchMode(value: boolean) { self.inSearchMode = value; }
      get inCategoryMode(): boolean { return self.inCategoryMode; }
      set inCategoryMode(value: boolean) { self.inCategoryMode = value; }
      get inSmartCategoryMode(): boolean { return self.inSmartCategoryMode; }
      set inSmartCategoryMode(value: boolean) { self.inSmartCategoryMode = value; }
      get inPersonMode(): boolean { return self.inPersonMode; }
      set inPersonMode(value: boolean) { self.inPersonMode = value; }
      get searchQuery(): string { return self.searchQuery; }
      set searchQuery(value: string) { self.searchQuery = value; }
      get searchLoading(): boolean { return self.searchLoading; }
      set searchLoading(value: boolean) { self.searchLoading = value; }
      get searchError(): string { return self.searchError; }
      set searchError(value: string) { self.searchError = value; }
      get searchResults(): GalleryListItem[] { return self.searchResults; }
      set searchResults(value: GalleryListItem[]) { self.searchResults = value; }
      get categoryLoading(): boolean { return self.categoryLoading; }
      set categoryLoading(value: boolean) { self.categoryLoading = value; }
      get categoryOpening(): boolean { return self.categoryOpening; }
      set categoryOpening(value: boolean) { self.categoryOpening = value; }
      get categoryOpeningText(): string { return self.categoryOpeningText; }
      set categoryOpeningText(value: string) { self.categoryOpeningText = value; }
      get categoryError(): string { return self.categoryError; }
      set categoryError(value: string) { self.categoryError = value; }
      get categoryItems(): MediaCategoryItem[] { return self.categoryItems; }
      set categoryItems(value: MediaCategoryItem[]) { self.categoryItems = value; }
      get smartCategoryLoading(): boolean { return self.smartCategoryLoading; }
      set smartCategoryLoading(value: boolean) { self.smartCategoryLoading = value; }
      get smartCategoryError(): string { return self.smartCategoryError; }
      set smartCategoryError(value: string) { self.smartCategoryError = value; }
      get smartSceneItems(): SmartCategoryItem[] { return self.smartSceneItems; }
      set smartSceneItems(value: SmartCategoryItem[]) { self.smartSceneItems = value; }
      get smartInfoItems(): SmartCategoryItem[] { return self.smartInfoItems; }
      set smartInfoItems(value: SmartCategoryItem[]) { self.smartInfoItems = value; }
      get personLoading(): boolean { return self.personLoading; }
      set personLoading(value: boolean) { self.personLoading = value; }
      get personOpening(): boolean { return self.personOpening; }
      set personOpening(value: boolean) { self.personOpening = value; }
      get personError(): string { return self.personError; }
      set personError(value: string) { self.personError = value; }
      get personItems(): AiPersonItem[] { return self.personItems; }
      set personItems(value: AiPersonItem[]) { self.personItems = value; }
      get personStatOverrides(): Map<string, string> { return self.personStatOverrides; }
      set personStatOverrides(value: Map<string, string>) { self.personStatOverrides = value; }
      get personStatVersion(): number { return self.personStatVersion; }
      set personStatVersion(value: number) { self.personStatVersion = value; }
      get personStatGen(): number { return self.personStatGen; }
      set personStatGen(value: number) { self.personStatGen = value; }
      get recentOpening(): boolean { return self.recentOpening; }
      set recentOpening(value: boolean) { self.recentOpening = value; }
      get collectOpening(): boolean { return self.collectOpening; }
      set collectOpening(value: boolean) { self.collectOpening = value; }
      get uploading(): boolean { return self.uploading; }
      set uploading(value: boolean) { self.uploading = value; }
      get uploadText(): string { return self.uploadText; }
      set uploadText(value: string) { self.uploadText = value; }
      get lastBootstrapSatisfiedRefreshVersion(): number { return self.lastBootstrapSatisfiedRefreshVersion; }
      set lastBootstrapSatisfiedRefreshVersion(value: number) { self.lastBootstrapSatisfiedRefreshVersion = value; }
      exitGallerySelection(): void { galleryAlbumExitSelection(self.asSelectionGestureHost()); }
      requestBootstrap(forceImmediate: boolean): void { self.requestBootstrap(forceImmediate); }
      bootstrap(showFullBleedSkeleton?: boolean): Promise<void> {
        return galleryAlbumBootstrap(self.asLoadOrchestratorHost(), showFullBleedSkeleton);
      }
      itemIdOf(item: GalleryListItem): string { return galleryAlbumItemIdOf(item); }
      createNavigationGuard(): () => boolean { return self.createNavigationGuard(); }
      toast(msg: string): void { self.toast(msg); }
    }
    return new ModeOrchestratorHostBridge();
  }

  private asLoadOrchestratorHost(): GalleryAlbumLoadOrchestratorHost {
    const self = this;
    class LoadOrchestratorHostBridge implements GalleryAlbumLoadOrchestratorHost {
      getUIContext() { return self.getUIContext(); }
      get inSearchMode(): boolean { return self.inSearchMode; }
      set inSearchMode(value: boolean) { self.inSearchMode = value; }
      get inCategoryMode(): boolean { return self.inCategoryMode; }
      set inCategoryMode(value: boolean) { self.inCategoryMode = value; }
      get inSmartCategoryMode(): boolean { return self.inSmartCategoryMode; }
      set inSmartCategoryMode(value: boolean) { self.inSmartCategoryMode = value; }
      get inPersonMode(): boolean { return self.inPersonMode; }
      set inPersonMode(value: boolean) { self.inPersonMode = value; }
      get categoryLoading(): boolean { return self.categoryLoading; }
      set categoryLoading(value: boolean) { self.categoryLoading = value; }
      get categoryError(): string { return self.categoryError; }
      set categoryError(value: string) { self.categoryError = value; }
      get categoryItems(): MediaCategoryItem[] { return self.categoryItems; }
      set categoryItems(value: MediaCategoryItem[]) { self.categoryItems = value; }
      get smartCategoryLoading(): boolean { return self.smartCategoryLoading; }
      set smartCategoryLoading(value: boolean) { self.smartCategoryLoading = value; }
      get smartCategoryError(): string { return self.smartCategoryError; }
      set smartCategoryError(value: string) { self.smartCategoryError = value; }
      get smartSceneItems(): SmartCategoryItem[] { return self.smartSceneItems; }
      set smartSceneItems(value: SmartCategoryItem[]) { self.smartSceneItems = value; }
      get smartInfoItems(): SmartCategoryItem[] { return self.smartInfoItems; }
      set smartInfoItems(value: SmartCategoryItem[]) { self.smartInfoItems = value; }
      get personLoading(): boolean { return self.personLoading; }
      set personLoading(value: boolean) { self.personLoading = value; }
      get personError(): string { return self.personError; }
      set personError(value: string) { self.personError = value; }
      get personItems(): AiPersonItem[] { return self.personItems; }
      set personItems(value: AiPersonItem[]) { self.personItems = value; }
      get personStatOverrides(): Map<string, string> { return self.personStatOverrides; }
      set personStatOverrides(value: Map<string, string>) { self.personStatOverrides = value; }
      get personStatVersion(): number { return self.personStatVersion; }
      set personStatVersion(value: number) { self.personStatVersion = value; }
      get personStatGen(): number { return self.personStatGen; }
      set personStatGen(value: number) { self.personStatGen = value; }
      get lastBootstrapSatisfiedRefreshVersion(): number { return self.lastBootstrapSatisfiedRefreshVersion; }
      set lastBootstrapSatisfiedRefreshVersion(value: number) { self.lastBootstrapSatisfiedRefreshVersion = value; }
      get galleryTimelineAtTopForPull(): boolean { return self.galleryTimelineAtTopForPull; }
      set galleryTimelineAtTopForPull(value: boolean) { self.galleryTimelineAtTopForPull = value; }
      get gallerySelectionMode(): boolean { return self.gallerySelectionMode; }
      set gallerySelectionMode(value: boolean) { self.setGallerySelectionModeState(value); }
      get galleryTimelineRefreshing(): boolean { return self.galleryTimelineRefreshing; }
      set galleryTimelineRefreshing(value: boolean) { self.galleryTimelineRefreshing = value; }
      get galleryPullRefreshThresholdHapticDone(): boolean { return self.galleryPullRefreshThresholdHapticDone; }
      set galleryPullRefreshThresholdHapticDone(value: boolean) { self.galleryPullRefreshThresholdHapticDone = value; }
      get loadGen(): number { return self.loadGen; }
      set loadGen(value: number) { self.loadGen = value; }
      get exhausted(): boolean { return self.exhausted; }
      set exhausted(value: boolean) { self.exhausted = value; }
      get dayIndex(): number { return self.dayIndex; }
      set dayIndex(value: number) { self.dayIndex = value; }
      get orderedDays(): TimelineDayModel[] { return self.orderedDays; }
      set orderedDays(value: TimelineDayModel[]) { self.setOrderedDays(value); }
      get dayOffsets(): Map<string, number> { return self.dayOffsets; }
      set dayOffsets(value: Map<string, number>) { self.dayOffsets = value; }
      get dayRounds(): Map<string, number> { return self.dayRounds; }
      set dayRounds(value: Map<string, number>) { self.dayRounds = value; }
      get dayEmptyRounds(): Map<string, number> { return self.dayEmptyRounds; }
      set dayEmptyRounds(value: Map<string, number>) { self.dayEmptyRounds = value; }
      get bootLoading(): boolean { return self.bootLoading; }
      set bootLoading(value: boolean) { self.bootLoading = value; }
      get loadError(): string { return self.loadError; }
      set loadError(value: string) { self.loadError = value; }
      get sections(): GalleryAlbumDaySectionState[] { return self.sections; }
      set sections(value: GalleryAlbumDaySectionState[]) { self.sections = value; }
      get footText(): string { return self.footText; }
      set footText(value: string) { self.footText = value; }
      get loadingMore(): boolean { return self.loadingMore; }
      set loadingMore(value: boolean) { self.loadingMore = value; }
      get pumpEpoch(): number { return self.pumpEpoch; }
      set pumpEpoch(value: number) { self.pumpEpoch = value; }
      get lastVisibleLoadDayIdx(): number { return self.lastVisibleLoadDayIdx; }
      set lastVisibleLoadDayIdx(value: number) { self.lastVisibleLoadDayIdx = value; }
      get bootstrapDebounceTimer(): number { return self.bootstrapDebounceTimer; }
      set bootstrapDebounceTimer(value: number) { self.bootstrapDebounceTimer = value; }
      get scrollerRef(): Scroller { return self.scrollerRef; }
      set scrollerRef(value: Scroller) { self.scrollerRef = value; }
      applyDeleteSyncIfNeeded(): void { galleryAlbumApplyDeleteSyncIfNeeded(self.asBatchActionHost()); }
      enrichPersonStats(items: AiPersonItem[], gen: number): Promise<void> {
        return galleryAlbumEnrichPersonStats(self.asModeOrchestratorHost(), items, gen);
      }
      rebuildFlow(): void { galleryAlbumRebuildFlow(self.asVisibleLoadHost()); }
      countGalleryListedItems(): number { return galleryAlbumCountGalleryListedItems(self.sections); }
      upsertSection(day: TimelineDayModel, list: GalleryListItem[], newOffset: number): void {
        galleryAlbumUpsertSection(self.asVisibleLoadHost(), day, list, newOffset);
      }
      clearBootstrapDebounceTimer(): void { self.clearBootstrapDebounceTimer(); }
      loadVisibleItemsImmediate(): void {
        galleryAlbumVisibleLoadVisibleItemsImmediate(self.asVisibleLoadHost());
      }
    }
    return new LoadOrchestratorHostBridge();
  }

  private asVisibleLoadHost(): GalleryAlbumVisibleLoadHost {
    const self = this;
    class VisibleLoadHostBridge implements GalleryAlbumVisibleLoadHost {
      get scrollerRef(): Scroller { return self.scrollerRef; }
      set scrollerRef(value: Scroller) { self.scrollerRef = value; }
      get flowDataSource(): GalleryWaterFlowDataSource { return self.flowDataSource; }
      set flowDataSource(value: GalleryWaterFlowDataSource) { self.flowDataSource = value; }
      get bootLoading(): boolean { return self.bootLoading; }
      set bootLoading(value: boolean) { self.bootLoading = value; }
      get orderedDays(): TimelineDayModel[] { return self.orderedDays; }
      set orderedDays(value: TimelineDayModel[]) { self.setOrderedDays(value); }
      get dayGlobalSlotStarts(): number[] { return self.dayGlobalSlotStarts; }
      set dayGlobalSlotStarts(value: number[]) { self.dayGlobalSlotStarts = value; }
      get sections(): GalleryAlbumDaySectionState[] { return self.sections; }
      set sections(value: GalleryAlbumDaySectionState[]) { self.sections = value; }
      get visualPlaceholderMode(): boolean { return self.visualPlaceholderMode; }
      set visualPlaceholderMode(value: boolean) { self.visualPlaceholderMode = value; }
      get isDraggingOrFling(): boolean { return self.isDraggingOrFling; }
      set isDraggingOrFling(value: boolean) { self.isDraggingOrFling = value; }
      get timelineSidebarDragging(): boolean { return self.timelineSidebarDragging; }
      set timelineSidebarDragging(value: boolean) { self.timelineSidebarDragging = value; }
      get timelineSeekInProgress(): boolean { return self.timelineSeekInProgress; }
      set timelineSeekInProgress(value: boolean) { self.timelineSeekInProgress = value; }
      get ignoreListFreezeUntilMs(): number { return self.ignoreListFreezeUntilMs; }
      set ignoreListFreezeUntilMs(value: number) { self.ignoreListFreezeUntilMs = value; }
      get timelineSeekNoScrollerGuardUntilMs(): number { return self.timelineSeekNoScrollerGuardUntilMs; }
      set timelineSeekNoScrollerGuardUntilMs(value: number) { self.timelineSeekNoScrollerGuardUntilMs = value; }
      get pendingFlowRebuild(): boolean { return self.pendingFlowRebuild; }
      set pendingFlowRebuild(value: boolean) { self.pendingFlowRebuild = value; }
      get lastLoadVisibleAtMs(): number { return self.lastLoadVisibleAtMs; }
      set lastLoadVisibleAtMs(value: number) { self.lastLoadVisibleAtMs = value; }
      get loadingMore(): boolean { return self.loadingMore; }
      set loadingMore(value: boolean) { self.loadingMore = value; }
      get exhausted(): boolean { return self.exhausted; }
      set exhausted(value: boolean) { self.exhausted = value; }
      get listVisibleFirstNodeIdx(): number { return self.listVisibleFirstNodeIdx; }
      set listVisibleFirstNodeIdx(value: number) { self.listVisibleFirstNodeIdx = value; }
      get listVisibleLastNodeIdx(): number { return self.listVisibleLastNodeIdx; }
      set listVisibleLastNodeIdx(value: number) { self.listVisibleLastNodeIdx = value; }
      get listScrollIndexAnchorHave(): boolean { return self.listScrollIndexAnchorHave; }
      set listScrollIndexAnchorHave(value: boolean) { self.listScrollIndexAnchorHave = value; }
      get listScrollIndexAnchorYVp(): number { return self.listScrollIndexAnchorYVp; }
      set listScrollIndexAnchorYVp(value: number) { self.listScrollIndexAnchorYVp = value; }
      get listScrollIndexAnchorFirst(): number { return self.listScrollIndexAnchorFirst; }
      set listScrollIndexAnchorFirst(value: number) { self.listScrollIndexAnchorFirst = value; }
      get lastKnownGlobalPhotoSlotStart(): number { return self.lastKnownGlobalPhotoSlotStart; }
      set lastKnownGlobalPhotoSlotStart(value: number) { self.lastKnownGlobalPhotoSlotStart = value; }
      get lastKnownGlobalPhotoSlotEndExclusive(): number { return self.lastKnownGlobalPhotoSlotEndExclusive; }
      set lastKnownGlobalPhotoSlotEndExclusive(value: number) { self.lastKnownGlobalPhotoSlotEndExclusive = value; }
      get dayIndex(): number { return self.dayIndex; }
      set dayIndex(value: number) { self.dayIndex = value; }
      get lastVisibleLoadDayIdx(): number { return self.lastVisibleLoadDayIdx; }
      set lastVisibleLoadDayIdx(value: number) { self.lastVisibleLoadDayIdx = value; }
      get dayOffsets(): Map<string, number> { return self.dayOffsets; }
      set dayOffsets(value: Map<string, number>) { self.dayOffsets = value; }
      get pumpEpoch(): number { return self.pumpEpoch; }
      set pumpEpoch(value: number) { self.pumpEpoch = value; }
      get loadGen(): number { return self.loadGen; }
      set loadGen(value: number) { self.loadGen = value; }
      get loadVisibleRetryTimer(): number { return self.loadVisibleRetryTimer; }
      set loadVisibleRetryTimer(value: number) { self.loadVisibleRetryTimer = value; }
      get loadVisibleRetryGen(): number { return self.loadVisibleRetryGen; }
      set loadVisibleRetryGen(value: number) { self.loadVisibleRetryGen = value; }
      get visibleBandPumpRunIdSeq(): number { return self.visibleBandPumpRunIdSeq; }
      set visibleBandPumpRunIdSeq(value: number) { self.visibleBandPumpRunIdSeq = value; }
      get visibleBandPumpActiveRunId(): number { return self.visibleBandPumpActiveRunId; }
      set visibleBandPumpActiveRunId(value: number) { self.visibleBandPumpActiveRunId = value; }
      get visibleBandPumpActiveEpoch(): number { return self.visibleBandPumpActiveEpoch; }
      set visibleBandPumpActiveEpoch(value: number) { self.visibleBandPumpActiveEpoch = value; }
      get timelineSliderRatio(): number { return self.timelineSliderRatio; }
      set timelineSliderRatio(value: number) { self.timelineSliderRatio = value; }
      get timelineSeekAnchorNodeIdx(): number { return self.timelineSeekAnchorNodeIdx; }
      set timelineSeekAnchorNodeIdx(value: number) { self.timelineSeekAnchorNodeIdx = value; }
      get visibleLoadPreferBottomFirst(): boolean { return self.visibleLoadPreferBottomFirst; }
      set visibleLoadPreferBottomFirst(value: boolean) { self.visibleLoadPreferBottomFirst = value; }
      get galleryGridColumns(): number { return self.currentGalleryGridColumns(); }
      set galleryGridColumns(_value: number) {}
      get rootModeContentWidthVp(): number { return self.rootModeContentWidthVp; }
      set rootModeContentWidthVp(value: number) { self.rootModeContentWidthVp = value; }
      get viewGranularity(): GalleryViewGranularity { return self.renderedViewGranularity; }
      set viewGranularity(value: GalleryViewGranularity) { self.viewGranularity = value; }
      flowNodeIndexFromListIndex(index: number): number { return self.flowNodeIndexFromMainListIndex(index); }
      listIndexFromFlowNodeIndex(index: number): number { return self.mainListIndexFromFlowNodeIndex(index); }
      resolveDayByGlobalIndex(globalIndex: number): DayGlobalResolveResult | null {
        return self.resolveDayByGlobalIndexFast(globalIndex);
      }
      resolveYearMonthByTimelineRatio(ratio: number): TimelineYearMonthPair | null {
        return galleryAlbumResolveYearMonthByTimelineRatio(self.asTimelineGestureHost(), ratio);
      }
      isInScrollInteractiveLogWindow(): boolean { return timelineGestureIsInScrollInteractiveLogWindow(self.asTimelineGestureHost()); }
      logScrollDebug(msg: string): void { timelineGestureLogScrollDebug(self.asTimelineGestureHost(), msg); }
      refreshRootPhotosScrollTitle(): void { self.refreshRootPhotosScrollTitle(); }
      rebuildFlow(): void { galleryAlbumRebuildFlow(self.asVisibleLoadHost()); }
      pumpLoad(singleBatch?: boolean): void { galleryAlbumPumpLoad(self.asLoadOrchestratorHost(), singleBatch); }
      loadOneBatch(): Promise<number> { return galleryAlbumLoadOneBatch(self.asLoadOrchestratorHost()); }
    }
    return new VisibleLoadHostBridge();
  }

  private asRootSurfaceHost(): GalleryAlbumRootSurfaceHost {
    const self = this;
    class RootSurfaceHostBridge implements GalleryAlbumRootSurfaceHost {
      getUIContext() { return self.getUIContext(); }
      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(value: string) { self.baseUrl = value; }
      get topSafeInsetVp(): number { return self.topSafeInsetVp; }
      set topSafeInsetVp(value: number) { self.topSafeInsetVp = value; }
      get floatingDockInsetBottomVp(): number { return self.floatingDockInsetBottomVp; }
      set floatingDockInsetBottomVp(value: number) { self.floatingDockInsetBottomVp = value; }
      get homeSurface(): string { return self.homeSurface; }
      set homeSurface(value: string) { self.homeSurface = value; }
      get inSearchMode(): boolean { return self.inSearchMode; }
      set inSearchMode(value: boolean) { self.inSearchMode = value; }
      get inCategoryMode(): boolean { return self.inCategoryMode; }
      set inCategoryMode(value: boolean) { self.inCategoryMode = value; }
      get inSmartCategoryMode(): boolean { return self.inSmartCategoryMode; }
      set inSmartCategoryMode(value: boolean) { self.inSmartCategoryMode = value; }
      get inPersonMode(): boolean { return self.inPersonMode; }
      set inPersonMode(value: boolean) { self.inPersonMode = value; }
      get moreMenuExpanded(): boolean { return self.moreMenuExpanded; }
      set moreMenuExpanded(value: boolean) { self.moreMenuExpanded = value; }
      get categoryLoading(): boolean { return self.categoryLoading; }
      set categoryLoading(value: boolean) { self.categoryLoading = value; }
      get categoryError(): string { return self.categoryError; }
      set categoryError(value: string) { self.categoryError = value; }
      get categoryItems(): MediaCategoryItem[] { return self.categoryItems; }
      set categoryItems(value: MediaCategoryItem[]) { self.categoryItems = value; }
      get smartCategoryLoading(): boolean { return self.smartCategoryLoading; }
      set smartCategoryLoading(value: boolean) { self.smartCategoryLoading = value; }
      get smartCategoryError(): string { return self.smartCategoryError; }
      set smartCategoryError(value: string) { self.smartCategoryError = value; }
      get smartSceneItems(): SmartCategoryItem[] { return self.smartSceneItems; }
      set smartSceneItems(value: SmartCategoryItem[]) { self.smartSceneItems = value; }
      get smartInfoItems(): SmartCategoryItem[] { return self.smartInfoItems; }
      set smartInfoItems(value: SmartCategoryItem[]) { self.smartInfoItems = value; }
      get personLoading(): boolean { return self.personLoading; }
      set personLoading(value: boolean) { self.personLoading = value; }
      get personError(): string { return self.personError; }
      set personError(value: string) { self.personError = value; }
      get personItems(): AiPersonItem[] { return self.personItems; }
      set personItems(value: AiPersonItem[]) { self.personItems = value; }
      get searchLoading(): boolean { return self.searchLoading; }
      set searchLoading(value: boolean) { self.searchLoading = value; }
      get searchError(): string { return self.searchError; }
      set searchError(value: string) { self.searchError = value; }
      get searchResults(): GalleryListItem[] { return self.searchResults; }
      set searchResults(value: GalleryListItem[]) { self.searchResults = value; }
      get categoryOpening(): boolean { return self.categoryOpening; }
      set categoryOpening(value: boolean) { self.categoryOpening = value; }
      get rootModeContentWidthVp(): number { return self.rootModeContentWidthVp; }
      set rootModeContentWidthVp(value: number) { self.rootModeContentWidthVp = value; }
      get rootPhotosSurfaceTranslateX(): number { return self.rootPhotosSurfaceTranslateX; }
      set rootPhotosSurfaceTranslateX(value: number) { self.rootPhotosSurfaceTranslateX = value; }
      get rootAlbumsSurfaceTranslateX(): number { return self.rootAlbumsSurfaceTranslateX; }
      set rootAlbumsSurfaceTranslateX(value: number) { self.rootAlbumsSurfaceTranslateX = value; }
      get rootSurfaceSwitchAnimating(): boolean { return self.rootSurfaceSwitchAnimating; }
      set rootSurfaceSwitchAnimating(value: boolean) { self.rootSurfaceSwitchAnimating = value; }
      get rootSurfaceSwitchStartTimer(): number { return self.rootSurfaceSwitchStartTimer; }
      set rootSurfaceSwitchStartTimer(value: number) { self.rootSurfaceSwitchStartTimer = value; }
      get rootSurfaceSwitchTimer(): number { return self.rootSurfaceSwitchTimer; }
      set rootSurfaceSwitchTimer(value: number) { self.rootSurfaceSwitchTimer = value; }
      get rootSurfaceSwitchFrom(): string { return self.rootSurfaceSwitchFrom; }
      set rootSurfaceSwitchFrom(value: string) { self.rootSurfaceSwitchFrom = value; }
      get rootSurfaceSwitchTo(): string { return self.rootSurfaceSwitchTo; }
      set rootSurfaceSwitchTo(value: string) { self.rootSurfaceSwitchTo = value; }
      get albumsHomeSmartPrefetchGen(): number { return self.albumsHomeSmartPrefetchGen; }
      set albumsHomeSmartPrefetchGen(value: number) { self.albumsHomeSmartPrefetchGen = value; }
      get albumsHomePersonPrefetchGen(): number { return self.albumsHomePersonPrefetchGen; }
      set albumsHomePersonPrefetchGen(value: number) { self.albumsHomePersonPrefetchGen = value; }
      get albumsHomeMediaPrefetchGen(): number { return self.albumsHomeMediaPrefetchGen; }
      set albumsHomeMediaPrefetchGen(value: number) { self.albumsHomeMediaPrefetchGen = value; }
      get lastHomeSurface(): string { return self.lastHomeSurface; }
      set lastHomeSurface(value: string) { self.lastHomeSurface = value; }
      dismissMoreMenu(): void { self.dismissMoreMenu(); }
      refreshRootPhotosScrollTitle(): void { self.refreshRootPhotosScrollTitle(); }
      notifySelectionDockStateChange(): void { self.notifySelectionDockStateChange(); }
      exitGallerySelection(): void { galleryAlbumExitSelection(self.asSelectionGestureHost()); }
      playModeSwitchMotion(direction?: number): void {
        galleryAlbumPlayModeSwitchMotion(self.asModeOrchestratorHost(), direction);
      }
      backToMain(animate: boolean): void {
        if (animate) {
          galleryAlbumBackToMain(self.asModeOrchestratorHost());
          return;
        }
        galleryAlbumExitSelection(self.asSelectionGestureHost());
        self.inSearchMode = false;
        self.inCategoryMode = false;
        self.inSmartCategoryMode = false;
        self.inPersonMode = false;
      }
      loadMediaCategories(): Promise<void> { return galleryAlbumLoadMediaCategories(self.asModeOrchestratorHost()); }
      toast(msg: string): void { self.toast(msg); }
    }
    return new RootSurfaceHostBridge();
  }

  private asRootTitleHost(): GalleryAlbumRootTitleHost {
    const self = this;
    class RootTitleHostBridge implements GalleryAlbumRootTitleHost {
      get homeSurface(): string { return self.homeSurface; }
      set homeSurface(value: string) { self.homeSurface = value; }
      get inSearchMode(): boolean { return self.inSearchMode; }
      set inSearchMode(value: boolean) { self.inSearchMode = value; }
      get inCategoryMode(): boolean { return self.inCategoryMode; }
      set inCategoryMode(value: boolean) { self.inCategoryMode = value; }
      get inSmartCategoryMode(): boolean { return self.inSmartCategoryMode; }
      set inSmartCategoryMode(value: boolean) { self.inSmartCategoryMode = value; }
      get inPersonMode(): boolean { return self.inPersonMode; }
      set inPersonMode(value: boolean) { self.inPersonMode = value; }
      get viewGranularity(): GalleryViewGranularity { return self.renderedViewGranularity; }
      set viewGranularity(value: GalleryViewGranularity) { self.viewGranularity = value; }
      get rootPhotosScrollTitle(): string { return self.rootPhotosScrollTitle; }
      set rootPhotosScrollTitle(value: string) { self.rootPhotosScrollTitle = value; }
      get rootPhotosScrolledUnderTopBar(): boolean { return self.rootPhotosScrolledUnderTopBar; }
      set rootPhotosScrolledUnderTopBar(value: boolean) { self.rootPhotosScrolledUnderTopBar = value; }
      get rootPhotosTitlePreferListAnchorUntilMs(): number { return self.rootPhotosTitlePreferListAnchorUntilMs; }
      set rootPhotosTitlePreferListAnchorUntilMs(value: number) { self.rootPhotosTitlePreferListAnchorUntilMs = value; }
      get timelineSeekInProgress(): boolean { return self.timelineSeekInProgress; }
      set timelineSeekInProgress(value: boolean) { self.timelineSeekInProgress = value; }
      get timelineReleaseAwaitVisibleCallback(): boolean { return self.timelineReleaseAwaitVisibleCallback; }
      set timelineReleaseAwaitVisibleCallback(value: boolean) { self.timelineReleaseAwaitVisibleCallback = value; }
      get listVisibleFirstNodeIdx(): number { return self.listVisibleFirstNodeIdx; }
      set listVisibleFirstNodeIdx(value: number) { self.listVisibleFirstNodeIdx = value; }
      get lastKnownGlobalPhotoSlotStart(): number { return self.lastKnownGlobalPhotoSlotStart; }
      set lastKnownGlobalPhotoSlotStart(value: number) { self.lastKnownGlobalPhotoSlotStart = value; }
      get lastKnownGlobalPhotoSlotEndExclusive(): number { return self.lastKnownGlobalPhotoSlotEndExclusive; }
      set lastKnownGlobalPhotoSlotEndExclusive(value: number) { self.lastKnownGlobalPhotoSlotEndExclusive = value; }
      get orderedDays(): TimelineDayModel[] { return self.orderedDays; }
      set orderedDays(value: TimelineDayModel[]) { self.orderedDays = value; }
      get dayGlobalSlotStarts(): number[] { return self.dayGlobalSlotStarts; }
      set dayGlobalSlotStarts(value: number[]) { self.dayGlobalSlotStarts = value; }
      get flowDataSource(): GalleryWaterFlowDataSource { return self.flowDataSource; }
      set flowDataSource(value: GalleryWaterFlowDataSource) { self.flowDataSource = value; }
      get scrollerRef(): Scroller { return self.scrollerRef; }
      set scrollerRef(value: Scroller) { self.scrollerRef = value; }
      setRootPhotosScrollTitle(title: string): void { self.setRootPhotosScrollTitle(title); }
      estimateFirstVisibleNodeIndexFromScrollY(yVp: number, total: number): number {
        return self.estimateFirstVisibleNodeIndexFromScrollY(yVp, total);
      }
      mainGalleryContentInsetTopVp(): number { return self.mainGalleryContentInsetTopVp(); }
      asTimelineGestureHost(): TimelineGestureControllerHost { return self.asTimelineGestureHost(); }
    }
    return new RootTitleHostBridge();
  }

  private asLifecycleHost(): GalleryAlbumLifecycleHost {
    const self = this;
    class LifecycleHostBridge implements GalleryAlbumLifecycleHost {
      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(value: string) { self.baseUrl = value; }
      get homeSurface(): string { return self.homeSurface; }
      set homeSurface(value: string) { self.homeSurface = value; }
      get inSearchMode(): boolean { return self.inSearchMode; }
      set inSearchMode(value: boolean) { self.inSearchMode = value; }
      get inCategoryMode(): boolean { return self.inCategoryMode; }
      set inCategoryMode(value: boolean) { self.inCategoryMode = value; }
      get inSmartCategoryMode(): boolean { return self.inSmartCategoryMode; }
      set inSmartCategoryMode(value: boolean) { self.inSmartCategoryMode = value; }
      get inPersonMode(): boolean { return self.inPersonMode; }
      set inPersonMode(value: boolean) { self.inPersonMode = value; }
      get rootSurfaceSwitchAnimating(): boolean { return self.rootSurfaceSwitchAnimating; }
      set rootSurfaceSwitchAnimating(value: boolean) { self.rootSurfaceSwitchAnimating = value; }
      get timelineReleaseAwaitVisibleCallback(): boolean { return self.timelineReleaseAwaitVisibleCallback; }
      set timelineReleaseAwaitVisibleCallback(value: boolean) { self.timelineReleaseAwaitVisibleCallback = value; }
      get lastHomeSurface(): string { return self.lastHomeSurface; }
      set lastHomeSurface(value: string) { self.lastHomeSurface = value; }
      get personOpening(): boolean { return self.personOpening; }
      set personOpening(value: boolean) { self.personOpening = value; }
      get categoryOpening(): boolean { return self.categoryOpening; }
      set categoryOpening(value: boolean) { self.categoryOpening = value; }
      get recentOpening(): boolean { return self.recentOpening; }
      set recentOpening(value: boolean) { self.recentOpening = value; }
      get collectOpening(): boolean { return self.collectOpening; }
      set collectOpening(value: boolean) { self.collectOpening = value; }
      get isDraggingOrFling(): boolean { return self.isDraggingOrFling; }
      set isDraggingOrFling(value: boolean) { self.isDraggingOrFling = value; }
      get pumpEpoch(): number { return self.pumpEpoch; }
      set pumpEpoch(value: number) { self.pumpEpoch = value; }
      get bootstrapDebounceTimer(): number { return self.bootstrapDebounceTimer; }
      set bootstrapDebounceTimer(value: number) { self.bootstrapDebounceTimer = value; }
      get galleryTimelineRefreshing(): boolean { return self.galleryTimelineRefreshing; }
      set galleryTimelineRefreshing(value: boolean) { self.galleryTimelineRefreshing = value; }
      get gallerySelectionMode(): boolean { return self.gallerySelectionMode; }
      set gallerySelectionMode(value: boolean) { self.gallerySelectionMode = value; }
      get loadGen(): number { return self.loadGen; }
      set loadGen(value: number) { self.loadGen = value; }
      currentThumbHeavyItemCount(): number { return self.currentThumbHeavyItemCount(); }
      onSearchModeVisibilityChange(hiddenBottomNav: boolean): void {
        self.onSearchModeVisibilityChange(hiddenBottomNav);
      }
      notifySelectionDockStateChange(): void { self.notifySelectionDockStateChange(); }
      syncHomeSurface(animate: boolean): void { self.syncHomeSurface(animate); }
      refreshRootPhotosScrollTitle(): void { self.refreshRootPhotosScrollTitle(); }
      ensureAlbumsHomeSupplementaryData(): void { self.ensureAlbumsHomeSupplementaryData(); }
      clearRootSurfaceSwitchTimer(): void { self.clearRootSurfaceSwitchTimer(); }
      resetRootSurfaceSwitchTransforms(): void { self.resetRootSurfaceSwitchTransforms(); }
      dismissMoreMenu(): void { self.dismissMoreMenu(); }
      invalidateNavigationGuard(): void { self.invalidateNavigationGuard(); }
      tryConsumeSurfaceBack(): boolean { return self.tryConsumeSurfaceBack(); }
      setGallerySelectionModeState(value: boolean): void { self.setGallerySelectionModeState(value); }
      asSelectionGestureHost(): SelectionGestureControllerHost { return self.asSelectionGestureHost(); }
      asTimelineGestureHost(): TimelineGestureControllerHost { return self.asTimelineGestureHost(); }
      asLoadOrchestratorHost(): GalleryAlbumLoadOrchestratorHost { return self.asLoadOrchestratorHost(); }
      asVisibleLoadHost(): GalleryAlbumVisibleLoadHost { return self.asVisibleLoadHost(); }
    }
    return new LifecycleHostBridge();
  }

  // ── 扁平列表（供跳转独立预览页） ────────────────────────────────────────

  private countPhotoSlotsBeforeNode(nodeIdx: number): number {
    return galleryAlbumVisibleCountPhotoSlotsBeforeNode(this.asVisibleLoadHost(), nodeIdx);
  }

  /** orderedDays[0..dayIdx) 的全局槽位前缀和。 */
  private globalSlotIndexAtDayStart(dayIdx: number): number {
    return galleryAlbumVisibleGlobalSlotIndexAtDayStart(this.asVisibleLoadHost(), dayIdx);
  }

  /**
   * 根据 List 可见节点区间刷新“全局照片槽位”缓存；只要存在 row 就写入，
   * 供 loadVisible 在 vis 退化时兜底使用。
   */
  private refreshLastKnownGlobalSlotsFromListIndices(firstIdx: number, lastIdx: number): void {
    galleryAlbumVisibleRefreshLastKnownGlobalSlotsFromListIndices(this.asVisibleLoadHost(), firstIdx, lastIdx);
  }

  private captureListScrollIndexAnchor(): void {
    galleryAlbumVisibleCaptureListScrollIndexAnchor(this.asVisibleLoadHost());
  }

  private shouldPreserveVisibleLoadPriorityDuringTimelineRelease(): boolean {
    return this.timelineSeekInProgress ||
      (!this.timelineSidebarDragging && Date.now() < this.ignoreListFreezeUntilMs);
  }

  private updateVisibleLoadPriorityFromScrollOffset(offsetVp: number): void {
    if (!Number.isFinite(offsetVp)) {
      return;
    }
    if (this.shouldPreserveVisibleLoadPriorityDuringTimelineRelease()) {
      return;
    }
    const next = Math.max(0, offsetVp);
    if (this.lastMainListScrollOffsetHave) {
      const delta = next - this.lastMainListScrollOffsetVp;
      if (Math.abs(delta) >= 0.5) {
        this.visibleLoadPreferBottomFirst = delta > 0;
      }
    }
    this.lastMainListScrollOffsetVp = next;
    this.lastMainListScrollOffsetHave = true;
  }

  private updateVisibleLoadPriorityFromVisibleRange(firstIdx: number, lastIdx: number): void {
    const first = Math.floor(firstIdx);
    const last = Math.floor(lastIdx);
    const prevFirst = this.listVisibleFirstNodeIdx;
    const prevLast = this.listVisibleLastNodeIdx;
    if (this.shouldPreserveVisibleLoadPriorityDuringTimelineRelease()) {
      return;
    }
    if (first === prevFirst && last === prevLast) {
      return;
    }
    const deltaFirst = first - prevFirst;
    const deltaLast = last - prevLast;
    const primary = Math.abs(deltaFirst) >= Math.abs(deltaLast) ? deltaFirst : deltaLast;
    if (Math.abs(primary) >= 1) {
      this.visibleLoadPreferBottomFirst = primary > 0;
    }
  }

  private resetTimelineSeekStableVisibleState(): void {
    this.timelineSeekStableVisibleFirstNodeIdx = -1;
    this.timelineSeekStableVisibleLastNodeIdx = -1;
    this.timelineSeekStableVisibleHits = 0;
  }

  private resolveTimelineSeekTargetNodeRange(): GalleryVisibleNodeRange | null {
    const ym = galleryAlbumResolveYearMonthByTimelineRatio(this.asTimelineGestureHost(), this.timelineSliderRatio);
    if (ym === null) {
      return null;
    }
    return findFlowRoughVisibleRangeForYearMonth(this.flowDataSource, ym.year, ym.month);
  }

  private tryHandOffTimelineSeekToListDrivenFromCandidate(
    firstIdx: number,
    lastIdx: number,
    source: string
  ): boolean {
    if (!this.timelineSeekInProgress) {
      return false;
    }
    const total = this.flowDataSource.totalCount();
    if (total <= 0) {
      return false;
    }
    const targetRange = this.resolveTimelineSeekTargetNodeRange();
    if (targetRange === null) {
      this.resetTimelineSeekStableVisibleState();
      return false;
    }
    const first = Math.max(0, Math.min(Math.floor(firstIdx), total - 1));
    const last = Math.max(first, Math.min(Math.floor(lastIdx), total - 1));
    const span = last - first + 1;
    const overlapsTarget = last >= targetRange.first && first <= targetRange.last;
    if (!overlapsTarget || span > GALLERY_TIMELINE_SEEK_HANDOFF_MAX_SPAN_NODES) {
      this.resetTimelineSeekStableVisibleState();
      timelineGestureLogScrollDebug(
        this.asTimelineGestureHost(),
        `[timeline-seek] ignore unstable visible source: source=${source}, range=${first}~${last}, `
        + `target=${targetRange.first}~${targetRange.last}, span=${span}`
      );
      return false;
    }
    const driftCap = Math.max(
      GALLERY_TIMELINE_SEEK_HANDOFF_MAX_DRIFT_NODES,
      Math.min(24, Math.ceil(span * 0.25))
    );
    let stableHits = 1;
    if (this.timelineSeekStableVisibleHits > 0 &&
      this.timelineSeekStableVisibleFirstNodeIdx >= 0 &&
      this.timelineSeekStableVisibleLastNodeIdx >= 0 &&
      Math.abs(first - this.timelineSeekStableVisibleFirstNodeIdx) <= driftCap &&
      Math.abs(last - this.timelineSeekStableVisibleLastNodeIdx) <= driftCap) {
      stableHits = this.timelineSeekStableVisibleHits + 1;
    }
    this.timelineSeekStableVisibleFirstNodeIdx = first;
    this.timelineSeekStableVisibleLastNodeIdx = last;
    this.timelineSeekStableVisibleHits = stableHits;
    timelineGestureLogScrollDebug(
      this.asTimelineGestureHost(),
      `[timeline-seek] observe visible source: source=${source}, range=${first}~${last}, `
      + `target=${targetRange.first}~${targetRange.last}, hits=${stableHits}/${GALLERY_TIMELINE_SEEK_HANDOFF_STABLE_HITS}`
    );
    if (stableHits < GALLERY_TIMELINE_SEEK_HANDOFF_STABLE_HITS) {
      return false;
    }
    this.timelineSeekInProgress = false;
    this.timelineReleaseAwaitVisibleCallback = false;
    this.applyListVisibleNodeRange(first, last);
    this.refreshRootPhotosScrollTitle();
    this.resetTimelineSeekStableVisibleState();
    timelineGestureLogScrollDebug(
      this.asTimelineGestureHost(),
      `[timeline-seek] handoff to list-driven: source=${source}, range=${first}~${last}`
    );
    return true;
  }

  private tryHandOffTimelineSeekToListDrivenFromScroller(reason: string): boolean {
    if (!this.timelineSeekInProgress) {
      return false;
    }
    const total = this.flowDataSource.totalCount();
    if (total <= 0) {
      return false;
    }
    if (!galleryAlbumVisibleTryApplyScrollerVisibleRangeIfAvailable(this.asVisibleLoadHost(), total)) {
      return false;
    }
    return this.tryHandOffTimelineSeekToListDrivenFromCandidate(
      this.listVisibleFirstNodeIdx,
      this.listVisibleLastNodeIdx,
      `${reason}/scroller`
    );
  }

  private applyListVisibleNodeRange(firstIdx: number, lastIdx: number): void {
    const total = this.flowDataSource.totalCount();
    if (total <= 0) {
      return;
    }
    const rawFirst = Math.max(0, Math.min(Math.floor(firstIdx), total - 1));
    const rawLast = Math.max(rawFirst, Math.min(Math.floor(lastIdx), total - 1));
    let first = rawFirst;
    let last = rawLast;
    let preserveSeekAnchor = false;
    const releaseFreezeActive =
      !this.timelineSidebarDragging &&
      !this.timelineSeekInProgress &&
      Date.now() < this.ignoreListFreezeUntilMs;
    if (releaseFreezeActive &&
      Number.isFinite(this.timelineSeekAnchorNodeIdx) &&
      this.timelineSeekAnchorNodeIdx >= 0) {
      const anchor = Math.max(0, Math.min(Math.floor(this.timelineSeekAnchorNodeIdx), total - 1));
      const guardBacktrack = Math.max(2, Math.floor(GALLERY_LOAD_VISIBLE_BUFFER_SCAN_WIN_NODES / 8));
      first = Math.max(0, anchor - guardBacktrack);
      last = Math.max(first, Math.min(total - 1, anchor + GALLERY_LOAD_VISIBLE_BUFFER_SCAN_WIN_NODES));
      preserveSeekAnchor = true;
      if (first !== rawFirst || last !== rawLast) {
        timelineGestureLogScrollDebug(
          this.asTimelineGestureHost(),
          `[scroll-release-visible] guard callback range: raw=${rawFirst}~${rawLast}, anchor=${anchor}, `
          + `apply=${first}~${last}`
        );
      }
    } else {
      const rawSpan = rawLast - rawFirst + 1;
      const maxReasonableSpan = Math.max(
        GALLERY_TIMELINE_SEEK_HANDOFF_MAX_SPAN_NODES,
        GALLERY_LOAD_VISIBLE_BUFFER_SCAN_WIN_NODES * 5
      );
      if (rawSpan > maxReasonableSpan) {
        if (this.visibleLoadPreferBottomFirst) {
          first = Math.max(0, rawLast - maxReasonableSpan + 1);
          last = rawLast;
        } else {
          first = rawFirst;
          last = Math.min(total - 1, rawFirst + maxReasonableSpan - 1);
        }
        timelineGestureLogScrollDebug(
          this.asTimelineGestureHost(),
          `[scroll-release-visible] clamp implausible visible range: raw=${rawFirst}~${rawLast}, `
          + `apply=${first}~${last}, priority=${this.visibleLoadPreferBottomFirst ? 'bottom-first' : 'top-first'}`
        );
      }
    }
    if (!preserveSeekAnchor) {
      this.timelineSeekAnchorNodeIdx = first;
    }
    this.listVisibleFirstNodeIdx = first;
    this.listVisibleLastNodeIdx = last;
    this.refreshLastKnownGlobalSlotsFromListIndices(first, last);
    this.captureListScrollIndexAnchor();
  }

  private approxGalleryFlowListNodeHeightVp(node: GalleryFlowNode): number {
    return galleryAlbumVisibleApproxGalleryFlowListNodeHeightVp(node);
  }

  /** 自 anchorFirst 起向下“吃掉” deltaVp 内容位移后，估算首可见节点下标。 */
  /**
   * 根据 List 顶部累计近似高度，估算 yVp 对应的首个节点下标（与 Scroller.yOffset 同向）。
   * 仅作 refine 下界，步数设上限，避免超长列表单次 O(n)。
   */
  private estimateFirstVisibleNodeIndexFromScrollY(yVp: number, total: number): number {
    return galleryAlbumVisibleEstimateFirstVisibleNodeIndexFromScrollY(this.asVisibleLoadHost(), yVp, total);
  }

  private consumeVerticalScrollDeltaAsNodeIndex(startIdx: number, deltaVp: number): number {
    return galleryAlbumVisibleConsumeVerticalScrollDeltaAsNodeIndex(this.asVisibleLoadHost(), startIdx, deltaVp);
  }

  /**
   * 与 consumeVerticalScrollDeltaAsNodeIndex 对称：当 y 减小（列表内容向上滚、看到较新的内容）时，
   * 从锚点节点向上消耗 deltaVp 的近似高度，得到更小的首可见节点下标。
   */
  private consumeVerticalScrollDeltaAsNodeIndexBackward(startIdx: number, deltaVp: number): number {
    return galleryAlbumVisibleConsumeVerticalScrollDeltaAsNodeIndexBackward(this.asVisibleLoadHost(), startIdx, deltaVp);
  }

  /**
   * 根据 Scroller 纵向偏移相对“上次 onScrollIndex 锚点”的增量，向前修正声称的 first/last，
   * 缓解 ArkUI List + LazyForEach 下索引回调滞后于真实视口的问题。
   */
  private refineVisibleNodeIndicesAgainstScrollLag(claimedFirst: number, claimedLast: number): GalleryVisibleNodeRange {
    return galleryAlbumVisibleRefineVisibleNodeIndicesAgainstScrollLag(this.asVisibleLoadHost(), claimedFirst, claimedLast);
  }

  /** 统计 [first,last] 节点区间内 row 中仍为骨架（null）的照片槽位数，用于按屏内占位扩展拉取范围。 */
  private countSkeletonPhotoSlotsInFlowNodeRange(first: number, last: number): number {
    return galleryAlbumVisibleCountSkeletonPhotoSlotsInFlowNodeRange(this.asVisibleLoadHost(), first, last);
  }

  /** 下方全局槽位缓冲：保底后再按当前窗口内骨架槽位数放大，上限受 cap 约束。 */
  private computeLoadVisibleBufferAfterSlots(aggressive: boolean, scanFirst: number, scanLast: number): number {
    return galleryAlbumVisibleComputeLoadVisibleBufferAfterSlots(this.asVisibleLoadHost(), aggressive, scanFirst, scanLast);
  }

  /**
   * 滚动静止后按可视区触发“日级优先加载”：
   * - 若 Scroller.getVisibleRange 可用，以返回区间作为唯一可见节点窗，跳过 refine；
   *   再映射到全局槽位并扩展 buffer，与 RecyclerView 的首末可见项驱动加载一致。
   * - 否则继续走 refine + y 反推兜底。
   * - 反查目标日时，若当前 dayIndex 落后，则前移到目标日并启动 pumpLoad。
   *
   * 注意：现有 sections 结构是“前缀连续真实数据”，不能安全跳 offset，否则会打乱映射；
   * 因此这里只做“按天抢占”，不直接改 dayOffsets 到中间页。
   */
  private loadVisibleItemsThrottled(forceImmediate: boolean = false, aggressive: boolean = false): void {
    galleryAlbumVisibleLoadVisibleItemsThrottled(this.asVisibleLoadHost(), forceImmediate, aggressive);
  }

  /**
   * 跨日窗口可能远大于 GALLERY_LOAD_VISIBLE_MULTI_DAY_CHAIN_MAX；
   * 若单段只泵前 N 天，屏幕上会形成“载一段、空一段”的条纹，因此这里按固定块顺序泵完整个 [loD, hiD]，
   * 块间仍受 epoch 和交互态 gate 约束。
   */
  private async pumpVisibleDayBandAllChunks(
    loD: number,
    hiD: number,
    startG: number,
    endG: number,
    epoch: number
  ): Promise<void> {
    await galleryAlbumVisiblePumpVisibleDayBandAllChunks(this.asVisibleLoadHost(), loD, hiD, startG, endG, epoch);
  }

  /**
   * 可见槽位区间跨多个日历日时，对窗口内涉及的每个日顺序各请求一批，
   * 并在进入该日前把 offset 对齐到与 [startG, endG] 重叠的起点。
   */
  private async pumpVisibleDayBandSequential(
    loDayIdx: number,
    hiDayIdx: number,
    startG: number,
    endG: number,
    epoch: number
  ): Promise<void> {
    await galleryAlbumVisiblePumpVisibleDayBandSequential(this.asVisibleLoadHost(), loDayIdx, hiDayIdx, startG, endG, epoch);
  }

  private loadVisibleItems(): void {
    galleryAlbumVisibleLoadVisibleItems(this.asVisibleLoadHost());
  }

  private loadVisibleItemsImmediate(): void {
    galleryAlbumVisibleLoadVisibleItemsImmediate(this.asVisibleLoadHost());
  }

  /**
   * 时间轴松手后的主动恢复：不依赖用户再滑动，直接拉起可视区加载。
   * 双阶段触发用于覆盖“程序化 seek 尚未完成可见区回传”的窗口。
   */
  private kickPostTimelineReleaseLoad(): void {
    timelineGestureKickPostTimelineReleaseLoad(this.asTimelineGestureHost());
  }

  private pxToVp(value: number): number {
    try {
      return this.getUIContext().px2vp(value);
    } catch (_e) {
      return value;
    }
  }

  private readTimelineFingerWindow(ev: GestureEvent): GalleryFingerWindowPoint | null {
    const fingerList = ev.fingerList;
    if (fingerList === undefined || fingerList.length < 1) {
      return null;
    }
    const finger = fingerList[0] as GalleryFingerCoordCompat;
    const x = finger.windowX ?? finger.globalX ?? finger.screenX ?? finger.displayX ?? finger.x;
    const y = finger.windowY ?? finger.globalY ?? finger.screenY ?? finger.displayY ?? finger.y;
    if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
      return null;
    }
    return { x, y };
  }

  private resolveTimelineSliderRatioFromFinger(ev: GestureEvent): number | null {
    const finger = this.readTimelineFingerWindow(ev);
    if (finger === null) {
      return null;
    }
    try {
      const rect = this.getUIContext().getComponentUtils().getRectangleById(GALLERY_TIMELINE_TRACK_DOM_ID);
      const trackTopVp = this.pxToVp(rect.windowOffset.y as number);
      const trackHeightVp = Math.max(64, this.pxToVp(rect.size.height as number));
      this.timelineScrubTrackHeightVp = trackHeightVp;
      const dragSpanVp = Math.max(trackHeightVp - GALLERY_TIMELINE_INDICATOR_RESERVED_VP, 40);
      const localYVp = finger.y - trackTopVp;
      return Math.max(0, Math.min(1, (localYVp - GALLERY_TIMELINE_INDICATOR_PAD_VP) / dragSpanVp));
    } catch (_e) {
      return null;
    }
  }

  private applyTimelineSliderRatioFromFinger(ev: GestureEvent, ymListLength: number): void {
    const ratio = this.resolveTimelineSliderRatioFromFinger(ev);
    if (ratio === null) {
      return;
    }
    if (Math.abs(ratio - this.timelineSliderRatio) < 0.001) {
      return;
    }
    this.timelineSliderRatio = ratio;
    this.timelineSidebarHighlightIndex =
      Math.max(0, Math.min(ymListLength - 1, Math.round(ratio * (ymListLength - 1))));
    this.timelineIndicatorY = galleryAlbumTimelineIndicatorYForRatio(this.timelineScrubTrackHeightVp, ratio);
  }

  private endTimelineDrag(): void {
    this.rootPhotosTitlePreferListAnchorUntilMs = Date.now() + 1400;
    this.ignoreListFreezeUntilMs = 0;
    this.resetTimelineSeekStableVisibleState();
    this.timelineReleaseAwaitVisibleCallback = true;
    timelineGestureLogScrollDebug(
      this.asTimelineGestureHost(),
      '[scroll-release-visible] endTimelineDrag: await visible callback = 1'
    );
    timelineGestureEndTimelineDrag(this.asTimelineGestureHost());
  }


  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {
    }
  }

  private createNavigationGuard(): () => boolean {
    const token = ++this.navigationGuardEpoch;
    return (): boolean => token === this.navigationGuardEpoch;
  }

  private currentThumbHeavyItemCount(): number {
    if (this.inSearchMode) {
      return this.searchResults.length;
    }
    if (this.inCategoryMode) {
      return this.categoryItems.length;
    }
    if (this.inSmartCategoryMode) {
      return this.smartSceneItems.length + this.smartInfoItems.length;
    }
    if (this.inPersonMode) {
      return this.personItems.length;
    }
    return galleryAlbumCountGalleryListedItems(this.sections);
  }

  private currentThumbCacheKeepDuringScroll(): number {
    const baseKeep = recommendedThumbCacheKeep(this.currentThumbHeavyItemCount(), false);
    if (this.homeSurface !== 'photos' || this.inSearchMode || this.inCategoryMode ||
      this.inSmartCategoryMode || this.inPersonMode) {
      return Math.min(THUMB_CACHE_MAX, baseKeep);
    }
    const columns = this.currentGalleryGridColumns();
    let floor = 36;
    if (columns >= 17) {
      floor = 160;
    } else if (columns >= 8) {
      floor = 96;
    }
    return Math.min(THUMB_CACHE_MAX, Math.max(baseKeep, floor));
  }

  private invalidateNavigationGuard(): void {
    this.navigationGuardEpoch++;
  }

  private async openCategory(cat: MediaCategoryItem): Promise<void> {
    await galleryAlbumOpenCategory(this.asModeOrchestratorHost(), cat);
  }

  /**
   * 最近添加：先按 explore/recent_timeline 分桶，再按日分页拉 recent_photos；
   * 最终聚合为平铺列表，并复用 CategoryGallery 预览页打开。
   */
  private async openRecentAdded(): Promise<void> {
    if (this.recentOpening) {
      return;
    }
    const isActive = this.createNavigationGuard();
    this.recentOpening = true;
    try {
      const result = await openRecentAddedGallery(
        this.baseUrl,
        this.getUIContext(),
        (item: GalleryListItem): string => galleryAlbumItemIdOf(item),
        isActive
      );
      if (!isActive()) {
        return;
      }
      if (!result.ok && result.errorMessage.length > 0) {
        this.toast(result.errorMessage);
      }
    } finally {
      this.recentOpening = false;
    }
  }

  /**
   * 收藏夹：先 GET gallery/timeline?is_collect=1 分日，
   * 再按日 GET getList(mode=collect & is_collect=1)，与 Web /p/collect 抓包保持一致。
   */
  private async openCollectGallery(): Promise<void> {
    await galleryAlbumOpenCollectGallery(this.asModeOrchestratorHost());
  }

  private onSearchModeChanged(): void {
    this.onSearchModeVisibilityChange(this.inSearchMode);
    this.notifySelectionDockStateChange();
  }

  private isPhotosHomeSurface(): boolean {
    return galleryAlbumIsPhotosHomeSurface(this.asRootSurfaceHost());
  }

  private isAlbumsHomeSurface(): boolean {
    return galleryAlbumIsAlbumsHomeSurface(this.asRootSurfaceHost());
  }

  private setRootPhotosScrollTitle(title: string): void {
    if (this.rootPhotosScrollTitle === title) {
      return;
    }
    this.rootPhotosScrollTitle = title;
  }

  private rebuildDayGlobalSlotStarts(): void {
    galleryAlbumRebuildDayGlobalSlotStarts(this.asRootTitleHost());
  }

  private setOrderedDays(value: TimelineDayModel[]): void {
    galleryAlbumSetOrderedDays(this.asRootTitleHost(), value);
  }

  private resolveDayByGlobalIndexFast(globalIndex: number): DayGlobalResolveResult | null {
    return galleryAlbumResolveDayByGlobalIndexFast(this.asRootTitleHost(), globalIndex);
  }

  private refreshRootPhotosScrollTitle(): void {
    galleryAlbumRefreshRootPhotosScrollTitle(this.asRootTitleHost());
  }

  private maybeRefreshRootPhotosScrollTitleForThreshold(): void {
    galleryAlbumMaybeRefreshRootPhotosScrollTitleForThreshold(this.asRootTitleHost());
  }

  private currentHomeSurfaceTitle(): string {
    return galleryAlbumCurrentHomeSurfaceTitle(this.asRootTitleHost());
  }

  private albumsHomeSmartItems(): SmartCategoryItem[] {
    return galleryAlbumAlbumsHomeSmartItems(this.asRootSurfaceHost());
  }

  private ensureAlbumsHomeSupplementaryData(): void {
    galleryAlbumEnsureAlbumsHomeSupplementaryData(this.asRootSurfaceHost());
  }

  private openRecycleBinPage(): void {
    galleryAlbumOpenRecycleBinPage(this.asRootSurfaceHost());
  }

  private openPersonPage(): void {
    galleryAlbumOpenPersonPage(this.asRootSurfaceHost());
  }

  private openSmartCategoryPage(): void {
    galleryAlbumOpenSmartCategoryPage(this.asRootSurfaceHost());
  }

  private isRootPhotosSurfaceVisible(): boolean {
    return galleryAlbumIsRootPhotosSurfaceVisible(this.asRootSurfaceHost());
  }

  private isRootAlbumsSurfaceVisible(): boolean {
    return galleryAlbumIsRootAlbumsSurfaceVisible(this.asRootSurfaceHost());
  }

  private shouldKeepAlbumsHomeMounted(): boolean {
    return galleryAlbumShouldKeepAlbumsHomeMounted(this.asRootSurfaceHost());
  }

  private isRootSurfaceVisible(): boolean {
    return galleryAlbumIsRootSurfaceVisible(this.asRootSurfaceHost());
  }

  private clearRootSurfaceSwitchTimer(): void {
    galleryAlbumClearRootSurfaceSwitchTimer(this.asRootSurfaceHost());
  }

  private isRootPhotosSurfaceLayerVisible(): boolean {
    return galleryAlbumIsRootPhotosSurfaceLayerVisible(this.asRootSurfaceHost());
  }

  private isRootAlbumsSurfaceLayerVisible(): boolean {
    return galleryAlbumIsRootAlbumsSurfaceLayerVisible(this.asRootSurfaceHost());
  }

  private rootPhotosSurfaceZIndex(): number {
    return galleryAlbumRootPhotosSurfaceZIndex(this.asRootSurfaceHost());
  }

  private rootAlbumsSurfaceZIndex(): number {
    return galleryAlbumRootAlbumsSurfaceZIndex(this.asRootSurfaceHost());
  }

  private resetRootSurfaceSwitchTransforms(): void {
    galleryAlbumResetRootSurfaceSwitchTransforms(this.asRootSurfaceHost());
  }

  private beginRootSurfaceSwitch(prevSurface: string, nextSurface: string): void {
    galleryAlbumBeginRootSurfaceSwitch(this.asRootSurfaceHost(), prevSurface, nextSurface);
  }

  private returnToHomeSurfaceRoot(animate: boolean): void {
    galleryAlbumReturnToHomeSurfaceRoot(this.asRootSurfaceHost(), animate);
  }

  private syncHomeSurface(animate: boolean): void {
    galleryAlbumSyncHomeSurface(this.asRootSurfaceHost(), animate);
  }

  private shouldKeepRootPhotosMainMounted(): boolean {
    return galleryAlbumShouldKeepRootPhotosMainMounted(this.asRootSurfaceHost());
  }

  private tryConsumeSurfaceBack(): boolean {
    return galleryAlbumTryConsumeSurfaceBack(this.asRootSurfaceHost());
  }

  private onHomeSurfaceChanged(): void {
    galleryAlbumOnHomeSurfaceChanged(this.asRootSurfaceHost());
  }

  private currentGalleryGridColumns(): number {
    return galleryViewGranularityColumns(this.renderedViewGranularity);
  }

  private granularitySwitchDirection(nextMode: GalleryViewGranularity): number {
    if (nextMode === this.lastGranularityMotionMode) {
      return 0;
    }
    return nextMode > this.lastGranularityMotionMode ? 1 : -1;
  }

  private clearGranularitySwitchTimer(): void {
    if (this.granularitySwitchTimer >= 0) {
      clearTimeout(this.granularitySwitchTimer);
      this.granularitySwitchTimer = -1;
    }
  }

  private playGranularityHostExitMotion(direction: number): void {
    if (direction === 0) {
      this.modeSwitchOpacity = 1;
      this.modeSwitchOffsetY = 0;
      return;
    }
    try {
      this.getUIContext().animateTo(
        { duration: GALLERY_GRANULARITY_HOST_SWITCH_EXIT_MS, curve: Curve.EaseIn },
        (): void => {
          this.modeSwitchOpacity = GALLERY_GRANULARITY_HOST_SWITCH_START_OPACITY;
          this.modeSwitchOffsetY = direction > 0 ? GALLERY_GRANULARITY_HOST_SWITCH_OFFSET_VP : -GALLERY_GRANULARITY_HOST_SWITCH_OFFSET_VP;
        }
      );
    } catch (_e) {
      this.modeSwitchOpacity = GALLERY_GRANULARITY_HOST_SWITCH_START_OPACITY;
      this.modeSwitchOffsetY = direction > 0 ? GALLERY_GRANULARITY_HOST_SWITCH_OFFSET_VP : -GALLERY_GRANULARITY_HOST_SWITCH_OFFSET_VP;
    }
  }

  private commitGranularitySwitch(direction: number): void {
    this.granularitySwitchTimer = -1;
    this.renderedViewGranularity = this.viewGranularity;
    this.lastGranularityMotionMode = this.renderedViewGranularity;
    galleryAlbumRebuildFlow(this.asVisibleLoadHost());
    this.refreshRootPhotosScrollTitle();
    if (direction === 0) {
      this.modeSwitchOpacity = 1;
      this.modeSwitchOffsetY = 0;
      setTimeout((): void => {
        void galleryAlbumVisibleRefreshVisibleRangeIfAvailable(this.asVisibleLoadHost());
        galleryAlbumVisibleLoadVisibleItemsImmediate(this.asVisibleLoadHost());
        this.refreshRootPhotosScrollTitle();
      }, 16);
      return;
    }
    this.modeSwitchOpacity = GALLERY_GRANULARITY_HOST_SWITCH_START_OPACITY;
    this.modeSwitchOffsetY = direction > 0 ? -GALLERY_GRANULARITY_HOST_SWITCH_OFFSET_VP : GALLERY_GRANULARITY_HOST_SWITCH_OFFSET_VP;
    try {
      this.getUIContext().animateTo(
        { duration: GALLERY_GRANULARITY_HOST_SWITCH_DURATION_MS, curve: Curve.EaseOut },
        (): void => {
          this.modeSwitchOpacity = 1;
          this.modeSwitchOffsetY = 0;
        }
      );
    } catch (_e) {
      this.modeSwitchOpacity = 1;
      this.modeSwitchOffsetY = 0;
    }
    setTimeout((): void => {
      void galleryAlbumVisibleRefreshVisibleRangeIfAvailable(this.asVisibleLoadHost());
      galleryAlbumVisibleLoadVisibleItemsImmediate(this.asVisibleLoadHost());
      this.refreshRootPhotosScrollTitle();
    }, 16);
  }

  private onViewGranularityChanged(): void {
    this.clearGranularitySwitchTimer();
    this.commitGranularitySwitch(0);
  }

  private openSearchPanel(): void {
    galleryAlbumOpenSearchPanel(this.asRootSurfaceHost());
  }

  private showMoreMenu(): void {
    galleryAlbumToggleMoreMenu(this.asRootSurfaceHost());
  }

  private secondaryModeContentInsetTopVp(): number {
    return galleryAlbumSecondaryModeContentInsetTopVp(this.asRootSurfaceHost());
  }

  private mainGalleryContentInsetTopVp(): number {
    return galleryAlbumMainGalleryContentInsetTopVp(this.asRootSurfaceHost());
  }

  private mainListLeadingInsetItemCount(): number {
    return this.mainGalleryContentInsetTopVp() > 0 ? 1 : 0;
  }

  private flowNodeIndexFromMainListIndex(index: number): number {
    return Math.floor(index) - this.mainListLeadingInsetItemCount();
  }

  private mainListIndexFromFlowNodeIndex(index: number): number {
    return Math.max(0, Math.floor(index) + this.mainListLeadingInsetItemCount());
  }

  private currentBottomDockInsetVp(): number {
    return galleryAlbumCurrentBottomDockInsetVp(this.asRootSurfaceHost());
  }

  private onEpochChange(): void {
    galleryAlbumOnEpochChange(this.asLifecycleHost());
  }

  private onPageShowSignal(): void {
    galleryAlbumOnPageShowSignal(this.asLifecycleHost());
  }

  aboutToAppear(): void {
    this.clearGranularitySwitchTimer();
    this.renderedViewGranularity = this.viewGranularity;
    this.lastGranularityMotionMode = this.viewGranularity;
    this.modeSwitchOpacity = 1;
    this.modeSwitchOffsetY = 0;
    galleryAlbumAboutToAppear(this.asLifecycleHost());
  }

  aboutToDisappear(): void {
    this.clearGranularitySwitchTimer();
    galleryAlbumAboutToDisappear(this.asLifecycleHost());
  }

  onPageShow(): void {
    galleryAlbumOnPageShow(this.asLifecycleHost());
  }

  private clearBootstrapDebounceTimer(): void {
    galleryAlbumClearBootstrapDebounceTimer(this.asLifecycleHost());
  }

  private requestBootstrap(debounced: boolean): void {
    galleryAlbumRequestBootstrap(this.asLifecycleHost(), debounced);
  }

  private enterGallerySelectionModeFromToolbar(): void {
    galleryAlbumEnterGallerySelectionModeFromToolbar(this.asLifecycleHost());
  }

  /**
   * 时间线区域下拉刷新：使用系统 Refresh 动效；非列表顶部、多选或子模式时不发起网络请求。
   */
  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.isRootPhotosSurfaceLayerVisible()) {
          Stack() {
            GalleryAlbumFloatingTopBarLayer({
              homeSurface: 'photos',
              inSearchMode: false,
              inCategoryMode: false,
              inSmartCategoryMode: false,
              inPersonMode: false,
              rootSurfaceTitle: this.rootPhotosScrollTitle,
              gallerySelectionMode: this.gallerySelectionMode,
              gallerySelectedCount: this.gallerySelectedIds.length,
              moreMenuExpanded: this.moreMenuExpanded,
              searchQuery: this.searchQuery,
              topSafeInsetVp: this.topSafeInsetVp,
              pageShowSignal: this.pageShowSignal,
              onSearchQueryChange: (value: string): void => {
                this.searchQuery = value;
              },
              onSearchSubmit: (): void => {
                void galleryAlbumRunSearch(this.asModeOrchestratorHost(), this.searchQuery);
              },
              onOpenSearch: (): void => {
                this.openSearchPanel();
              },
              onStartUpload: (): void => {
                galleryAlbumStartUpload(this.asModeOrchestratorHost());
              },
              onExitSelection: (): void => {
                galleryAlbumExitSelection(this.asSelectionGestureHost());
              },
              onEnterSelection: (): void => {
                this.enterGallerySelectionModeFromToolbar();
              },
              onBackToGallery: (): void => {
                this.returnToHomeSurfaceRoot(true);
              },
              onShowMoreMenu: (): void => {
                this.showMoreMenu();
              }
            })
          }
          .width('100%')
          .height('100%')
          .translate({ x: this.rootPhotosSurfaceTranslateX, y: 0 })
          .enabled(this.isRootPhotosSurfaceVisible())
          .hitTestBehavior(this.isRootPhotosSurfaceVisible() ? HitTestMode.Transparent : HitTestMode.None)
          .zIndex(this.rootPhotosSurfaceZIndex() + 10)
        }

        if (this.isRootAlbumsSurfaceLayerVisible()) {
          Stack() {
            GalleryAlbumFloatingTopBarLayer({
              homeSurface: 'albums',
              inSearchMode: false,
              inCategoryMode: true,
              inSmartCategoryMode: false,
              inPersonMode: false,
              rootSurfaceTitle: '相册',
              gallerySelectionMode: this.gallerySelectionMode,
              gallerySelectedCount: this.gallerySelectedIds.length,
              moreMenuExpanded: this.moreMenuExpanded,
              searchQuery: this.searchQuery,
              topSafeInsetVp: this.topSafeInsetVp,
              pageShowSignal: this.pageShowSignal,
              onSearchQueryChange: (value: string): void => {
                this.searchQuery = value;
              },
              onSearchSubmit: (): void => {
                void galleryAlbumRunSearch(this.asModeOrchestratorHost(), this.searchQuery);
              },
              onOpenSearch: (): void => {
                this.openSearchPanel();
              },
              onStartUpload: (): void => {
                galleryAlbumStartUpload(this.asModeOrchestratorHost());
              },
              onExitSelection: (): void => {
                galleryAlbumExitSelection(this.asSelectionGestureHost());
              },
              onEnterSelection: (): void => {
                this.enterGallerySelectionModeFromToolbar();
              },
              onBackToGallery: (): void => {
                this.returnToHomeSurfaceRoot(true);
              },
              onShowMoreMenu: (): void => {
                this.showMoreMenu();
              }
            })
          }
          .width('100%')
          .height('100%')
          .translate({ x: this.rootAlbumsSurfaceTranslateX, y: 0 })
          .enabled(this.isRootAlbumsSurfaceVisible())
          .hitTestBehavior(this.isRootAlbumsSurfaceVisible() ? HitTestMode.Transparent : HitTestMode.None)
          .zIndex(this.rootAlbumsSurfaceZIndex() + 10)
        }

        if (!this.isRootPhotosSurfaceLayerVisible() && !this.isRootAlbumsSurfaceLayerVisible()) {
          Stack() {
            GalleryAlbumFloatingTopBarLayer({
              homeSurface: this.isAlbumsHomeSurface() ? 'albums' : 'photos',
              inSearchMode: this.inSearchMode,
              inCategoryMode: this.inCategoryMode,
              inSmartCategoryMode: this.inSmartCategoryMode,
              inPersonMode: this.inPersonMode,
              rootSurfaceTitle: this.currentHomeSurfaceTitle(),
              gallerySelectionMode: this.gallerySelectionMode,
              gallerySelectedCount: this.gallerySelectedIds.length,
              moreMenuExpanded: this.moreMenuExpanded,
              searchQuery: this.searchQuery,
              topSafeInsetVp: this.topSafeInsetVp,
              pageShowSignal: this.pageShowSignal,
              onSearchQueryChange: (value: string): void => {
                this.searchQuery = value;
              },
              onSearchSubmit: (): void => {
                void galleryAlbumRunSearch(this.asModeOrchestratorHost(), this.searchQuery);
              },
              onOpenSearch: (): void => {
                this.openSearchPanel();
              },
              onStartUpload: (): void => {
                galleryAlbumStartUpload(this.asModeOrchestratorHost());
              },
              onExitSelection: (): void => {
                galleryAlbumExitSelection(this.asSelectionGestureHost());
              },
              onEnterSelection: (): void => {
                this.enterGallerySelectionModeFromToolbar();
              },
              onBackToGallery: (): void => {
                this.returnToHomeSurfaceRoot(true);
              },
              onShowMoreMenu: (): void => {
                this.showMoreMenu();
              }
            })
          }
          .width('100%')
          .height('100%')
          .zIndex(11)
        }

        if (this.moreMenuExpanded) {
          Stack({ alignContent: Alignment.TopEnd }) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(Color.Transparent)
              .onClick((): void => {
                this.dismissMoreMenu();
              })

            Column({ space: 10 }) {
              Text(this.isAlbumsHomeSurface() ? '\u76f8\u518c\u83dc\u5355' : '\u56fe\u5e93\u83dc\u5355')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))

              Text('菜单内容暂时清空')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .backgroundColor($r('app.color.gallery_material_surface_bg'))
            .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
            .backgroundEffect(fnImmersiveBackgroundEffect())
            .linearGradient(fnLiquidGlassGradient())
            .borderRadius(22)
            .border({ width: 1, color: $r('app.color.immersive_panel_border') })
            .shadow({ radius: 18, color: '#14001A33', offsetX: 0, offsetY: 8 })
            .clip(true)
            .margin({
              top: this.topSafeInsetVp + GALLERY_TOP_BAR_FLOATING_TOTAL_HEIGHT_VP + 8,
              right: GALLERY_TOP_BAR_PAD_RIGHT_VP
            })
          }
          .width('100%')
          .height('100%')
          .zIndex(2)
        }

        Stack({ alignContent: Alignment.TopStart }) {
      // ── 搜索结果视图 ──────────────────────────────────────────────────────
      if (this.inSearchMode) {
        GalleryAlbumSearchModeView({
          baseUrl: this.baseUrl,
          contentInsetTopVp: this.secondaryModeContentInsetTopVp(),
          contentInsetBottomVp: this.currentBottomDockInsetVp(),
          loading: this.searchLoading,
          error: this.searchError,
          searchResults: this.searchResults,
          gallerySelectionMode: this.gallerySelectionMode,
          gallerySelectedCount: this.gallerySelectedIds.length,
          gallerySelectedIds: this.gallerySelectedIds,
          galleryBatchDownloading: this.galleryBatchDownloading,
          galleryBatchDeleting: this.galleryBatchDeleting,
          galleryMainListScrollEnabled: this.galleryMainListScrollEnabled,
          gallerySlideGestureActive: this.gallerySlideGestureActive,
          galleryLongPressIgnoreClickUntil: this.galleryLongPressIgnoreClickUntil,
          modeSwitchOpacity: this.modeSwitchOpacity,
          modeSwitchOffsetY: this.modeSwitchOffsetY,
          itemIdOf: (item: GalleryListItem): string => galleryAlbumItemIdOf(item),
          searchThumbDomId: (flatIndex: number): string => selectionSearchThumbDomId(this.asSelectionGestureHost(), flatIndex),
          recordSearchThumbRect: (flatIndex: number): void => selectionRecordSearchThumbRect(this.asSelectionGestureHost(), flatIndex),
          onSearchThumbTap: (item: GalleryListItem, flatIndex: number): void =>
            selectionOnSearchThumbTap(this.asSelectionGestureHost(), item, flatIndex),
          readGestureFingerWindow: (ev: GestureEvent): GalleryFingerWindowPoint | null =>
            selectionReadGestureFingerWindow(this.asSelectionGestureHost(), ev),
          pickSearchThumbFlatForRow: (rowStart: number, xPx: number, yPx: number): number =>
            selectionPickSearchThumbFlatForRow(this.asSelectionGestureHost(), rowStart, xPx, yPx),
          onGalleryThumbLongPress: (item: GalleryListItem): void =>
            selectionOnGalleryThumbLongPress(this.asSelectionGestureHost(), item),
          beginGallerySlideSelectGesture: (ev: GestureEvent, item: GalleryListItem, anchorFlat: number): void =>
            selectionBeginGallerySlideSelectGesture(this.asSelectionGestureHost(), ev, item, anchorFlat),
          endGallerySlideSelectGesture: (): void => selectionEndGallerySlideSelectGesture(this.asSelectionGestureHost()),
          onGallerySlidePanUpdate: (ev: GestureEvent): void =>
            selectionOnGallerySlidePanUpdate(this.asSelectionGestureHost(), ev),
          onGallerySlideTouchMoveWindow: (xPx: number, yPx: number): void =>
            selectionOnGallerySlideTouchMoveWindow(this.asSelectionGestureHost(), xPx, yPx),
          ensureMainListScrollEnabled: (): void => {
            this.galleryMainListScrollEnabled = true;
          },
          clearSearchThumbHitBounds: (): void => {
            this.searchThumbHitBounds.clear();
          },
          onBatchDownload: (): void => {
            void galleryAlbumConfirmAndBatchDownload(this.asBatchActionHost());
          },
          onBatchDelete: (): void => {
            void galleryAlbumConfirmAndBatchDelete(this.asBatchActionHost());
          }
        })
      }

      if (this.shouldKeepAlbumsHomeMounted()) {
        GalleryAlbumAlbumsHomeView({
          baseUrl: this.baseUrl,
          pageVisible: this.isRootAlbumsSurfaceLayerVisible(),
          contentInsetTopVp: this.secondaryModeContentInsetTopVp(),
          contentInsetBottomVp: this.currentBottomDockInsetVp(),
          mediaLoading: this.categoryLoading,
          mediaError: this.categoryError,
          mediaOpening: this.categoryOpening,
          mediaItems: this.categoryItems,
          personLoading: this.personLoading,
          personError: this.personError,
          personItems: this.personItems,
          smartLoading: this.smartCategoryLoading,
          smartError: this.smartCategoryError,
          smartSceneItems: this.smartSceneItems,
          smartInfoItems: this.smartInfoItems,
          modeSwitchOpacity: this.modeSwitchOpacity,
          modeSwitchOffsetY: this.modeSwitchOffsetY,
          getMediaCategoryTitle: (item: MediaCategoryItem): string => categoryTitle(item),
          getMediaCategoryCount: (item: MediaCategoryItem): number => categoryCount(item),
          getMediaCategoryCover: (item: MediaCategoryItem): string => categoryCover(item),
          getPersonName: (item: AiPersonItem): string => personName(item),
          getPersonFace: (item: AiPersonItem): string => personFace(item),
          getSmartCategoryCover: (item: SmartCategoryItem): string => smartCategoryCover(item),
          onOpenMediaCategory: (item: MediaCategoryItem): void => {
            void galleryAlbumOpenCategory(this.asModeOrchestratorHost(), item);
          },
          onOpenPersonPage: (): void => {
            this.openPersonPage();
          },
          onOpenSmartCategoryPage: (): void => {
            this.openSmartCategoryPage();
          },
          onOpenPlacePlaceholder: (): void => {
            this.toast('地点功能预留中');
          },
          onOpenRecentAdded: (): void => {
            void this.openRecentAdded();
          },
          onOpenCollect: (): void => {
            void this.openCollectGallery();
          },
          onOpenRecycleBin: (): void => {
            this.openRecycleBinPage();
          }
        })
          .visibility(this.isRootAlbumsSurfaceLayerVisible() ? Visibility.Visible : Visibility.None)
          .translate({ x: this.rootAlbumsSurfaceTranslateX, y: 0 })
          .enabled(this.isRootAlbumsSurfaceVisible())
          .hitTestBehavior(this.isRootAlbumsSurfaceVisible() ? HitTestMode.Default : HitTestMode.None)
          .zIndex(this.rootAlbumsSurfaceZIndex())
      }

      if (this.inCategoryMode && !this.isAlbumsHomeSurface()) {
        GalleryAlbumCategoryModeView({
          baseUrl: this.baseUrl,
          contentInsetTopVp: this.secondaryModeContentInsetTopVp(),
          contentInsetBottomVp: this.currentBottomDockInsetVp(),
          loading: this.categoryLoading,
          error: this.categoryError,
          opening: this.categoryOpening,
          items: this.categoryItems,
          modeSwitchOpacity: this.modeSwitchOpacity,
          modeSwitchOffsetY: this.modeSwitchOffsetY,
          getCategoryTitle: (item: MediaCategoryItem): string => categoryTitle(item),
          getCategoryCount: (item: MediaCategoryItem): number => categoryCount(item),
          getCategoryCover: (item: MediaCategoryItem): string => categoryCover(item),
          onOpenCategory: (item: MediaCategoryItem): void => {
            void galleryAlbumOpenCategory(this.asModeOrchestratorHost(), item);
          }
        })
      }

      if (this.inSmartCategoryMode) {
        GalleryAlbumSmartCategoryModeView({
          baseUrl: this.baseUrl,
          contentInsetTopVp: this.secondaryModeContentInsetTopVp(),
          contentInsetBottomVp: this.currentBottomDockInsetVp(),
          loading: this.smartCategoryLoading,
          error: this.smartCategoryError,
          sceneItems: this.smartSceneItems,
          infoItems: this.smartInfoItems,
          modeSwitchOpacity: this.modeSwitchOpacity,
          modeSwitchOffsetY: this.modeSwitchOffsetY,
          getCategoryName: (item: SmartCategoryItem): string => smartCategoryName(item),
          getCategoryCover: (item: SmartCategoryItem): string => smartCategoryCover(item),
          onRunSearch: (keyword: string): void => {
            this.searchQuery = keyword;
            void galleryAlbumRunSearch(this.asModeOrchestratorHost(), keyword);
          }
        })
      }

      if (this.inPersonMode) {
        GalleryAlbumPersonModeView({
          baseUrl: this.baseUrl,
          contentInsetTopVp: this.secondaryModeContentInsetTopVp(),
          contentInsetBottomVp: this.currentBottomDockInsetVp(),
          loading: this.personLoading,
          error: this.personError,
          opening: this.personOpening,
          items: this.personItems,
          modeSwitchOpacity: this.modeSwitchOpacity,
          modeSwitchOffsetY: this.modeSwitchOffsetY,
          getPersonName: (item: AiPersonItem): string => personName(item),
          getPersonFace: (item: AiPersonItem): string => personFace(item),
          getPersonStatText: (item: AiPersonItem): string => personStatText(item, this.personStatOverrides),
          onOpenPerson: (item: AiPersonItem): void => {
            void galleryAlbumOpenPerson(this.asModeOrchestratorHost(), item);
          }
        })
      }

      // ── 图库视图 ─────────────────────────────────────────────────────────
      if (this.shouldKeepRootPhotosMainMounted()) {
        GalleryAlbumMainModeView({
          baseUrl: this.baseUrl,
          viewGranularity: this.renderedViewGranularity,
          gridColumns: this.currentGalleryGridColumns(),
          contentInsetTopVp: this.mainGalleryContentInsetTopVp(),
          contentInsetBottomVp: this.currentBottomDockInsetVp(),
          modeSwitchOpacity: this.modeSwitchOpacity,
          modeSwitchOffsetY: this.modeSwitchOffsetY,
          bootLoading: this.bootLoading,
          loadError: this.loadError,
          footText: this.footText,
          galleryTimelineRefreshing: this.galleryTimelineRefreshing,
          gallerySelectionMode: this.gallerySelectionMode,
          gallerySelectedCount: this.gallerySelectedIds.length,
          gallerySelectedIds: this.gallerySelectedIds,
          showBatchActionBar: !this.shouldUseHomeSelectionDock(),
          galleryBatchDownloading: this.galleryBatchDownloading,
          galleryBatchDeleting: this.galleryBatchDeleting,
          galleryMainListScrollEnabled: this.galleryMainListScrollEnabled,
          gallerySlideGestureActive: this.gallerySlideGestureActive,
          galleryLongPressIgnoreClickUntil: this.galleryLongPressIgnoreClickUntil,
          timelineSidebarDragging: this.timelineSidebarDragging,
          isDraggingOrFling: this.isDraggingOrFling,
          sectionsLength: this.sections.length,
          orderedDaysLength: this.orderedDays.length,
          timelineExpandedChrome: timelineGestureTimelineScrubExpandedChrome(this.asTimelineGestureHost()),
          timelineScrollRailOnly: timelineGestureTimelineScrubScrollRailOnly(this.asTimelineGestureHost()),
          timelineYearMarkers: galleryAlbumGetYearMarkersForTrack(this.asTimelineGestureHost()),
          timelineScrubPillLabel: galleryAlbumGetTimelineScrubPillLabel(this.asTimelineGestureHost()),
          timelineBarVisible: this.timelineBarVisible,
          timelinePressing: this.timelinePressing,
          timelineLongPressExpanded: this.timelineLongPressExpanded,
          timelineIndicatorY: this.timelineIndicatorY,
          timelineSliderRatio: this.timelineSliderRatio,
          scrollerRef: this.scrollerRef,
          flowDataSource: this.flowDataSource,
          itemIdOf: (item: GalleryListItem): string => galleryAlbumItemIdOf(item),
          galleryThumbDomId: (photoId: string): string => galleryAlbumGalleryThumbDomId(photoId),
          recordGalleryThumbRectFromDom: (photoId: string, domId: string): void =>
            galleryAlbumRecordGalleryThumbRectFromDom(this.asSelectionGestureHost(), photoId, domId),
          onGalleryThumbTap: (item: GalleryListItem, flatIndex: number): void =>
            selectionOnGalleryThumbTap(this.asSelectionGestureHost(), item, flatIndex),
          galleryFlowLazyKey: (node: GalleryFlowNode): string => galleryAlbumGalleryFlowLazyKey(node),
          getFlatItems: (): GalleryListItem[] => galleryAlbumFlatItems(this.asVisibleLoadHost()),
          endGallerySlideSelectGesture: (): void => selectionEndGallerySlideSelectGesture(this.asSelectionGestureHost()),
          readGestureFingerWindow: (ev: GestureEvent): GalleryFingerWindowPoint | null =>
            selectionReadGestureFingerWindow(this.asSelectionGestureHost(), ev),
          pickGalleryThumbFlatUnderPoint: (xPx: number, yPx: number): number =>
            selectionPickGalleryThumbFlatUnderPoint(this.asSelectionGestureHost(), xPx, yPx),
          pickGalleryThumbFlatForRowOrCache: (node: GalleryFlowNode, xPx: number, yPx: number): number =>
            selectionPickGalleryThumbFlatForRowOrCache(this.asSelectionGestureHost(), node, xPx, yPx),
          onGalleryThumbLongPress: (item: GalleryListItem): void =>
            selectionOnGalleryThumbLongPress(this.asSelectionGestureHost(), item),
          beginGallerySlideSelectGesture: (ev: GestureEvent, item: GalleryListItem, anchorFlat: number): void =>
            selectionBeginGallerySlideSelectGesture(this.asSelectionGestureHost(), ev, item, anchorFlat),
          beginGallerySlideSelectGestureAtWindowPx:
            (item: GalleryListItem, anchorFlat: number, xPx: number, yPx: number): void =>
              selectionBeginGallerySlideSelectGestureAtWindowPx(
                this.asSelectionGestureHost(),
                item,
                anchorFlat,
                xPx,
                yPx
              ),
          onGallerySlidePanUpdate: (ev: GestureEvent): void =>
            selectionOnGallerySlidePanUpdate(this.asSelectionGestureHost(), ev),
          onGallerySlideTouchMoveWindow: (xPx: number, yPx: number): void =>
            selectionOnGallerySlideTouchMoveWindow(this.asSelectionGestureHost(), xPx, yPx),
          onListScrollIndex: (firstIdx: number, lastIdx: number, _centerIdx: number): void => {
            const flowFirstIdx = this.flowNodeIndexFromMainListIndex(firstIdx);
            const flowLastIdx = this.flowNodeIndexFromMainListIndex(lastIdx);
            this.applyListVisibleNodeRange(flowFirstIdx, flowLastIdx);
            this.refreshRootPhotosScrollTitle();
            if (this.timelineReleaseAwaitVisibleCallback && !this.timelineSidebarDragging) {
              timelineGestureLogScrollDebug(
                this.asTimelineGestureHost(),
                `[scroll-release-visible] onScrollIndex: raw=${firstIdx}~${lastIdx}, flow=${flowFirstIdx}~${flowLastIdx}`
              );
              this.timelineReleaseAwaitVisibleCallback = false;
              galleryAlbumVisibleLoadVisibleItemsImmediate(this.asVisibleLoadHost());
            }
            if (this.timelineSidebarDragging || this.timelineSeekInProgress) {
              return;
            }
            timelineGestureSyncTimelineHandleFromListThrottled(
              this.asTimelineGestureHost(),
              Math.max(0, flowFirstIdx),
              (idx: number): void => {
                galleryAlbumSyncTimelineSliderFromFirstIndex(this.asTimelineGestureHost(), idx);
              }
            );
            timelineGestureTouchTimelineBarOnScroll(this.asTimelineGestureHost());
          },
          onListDidScroll: (_offset: number, _scrollState: ScrollState): void => {
            this.maybeRefreshRootPhotosScrollTitleForThreshold();
            timelineGestureMaybeLogMainScrollTick(this.asTimelineGestureHost(), _offset, _scrollState);
            this.updateVisibleLoadPriorityFromScrollOffset(_offset);
            const draggingOrFling = _scrollState === ScrollState.Scroll || _scrollState === ScrollState.Fling;
            const shouldFreezeByListScroll =
              draggingOrFling && !this.timelineSeekInProgress && Date.now() >= this.ignoreListFreezeUntilMs;
            const wasDraggingOrFling = this.isDraggingOrFling;
            let refreshedVisibleRangeWhileInteracting = false;
            let stateChanged = false;
            if (shouldFreezeByListScroll) {
              if (!this.isDraggingOrFling) {
                this.pumpEpoch++;
                timelineGestureCancelListSettledTimer(this.asTimelineGestureHost());
                this.isDraggingOrFling = true;
                this.lastInteractiveVisibleRangeRefreshAtMs = 0;
                trimThumbPixCache(this.currentThumbCacheKeepDuringScroll());
                stateChanged = true;
              }
              if (!this.listKineticScrolling) {
                this.listKineticScrolling = true;
                stateChanged = true;
              }
              if (!this.timelineSidebarDragging) {
                const now = Date.now();
                const shouldRefreshVisibleRange = this.lastInteractiveVisibleRangeRefreshAtMs <= 0 ||
                  now - this.lastInteractiveVisibleRangeRefreshAtMs >= 96;
                if (shouldRefreshVisibleRange) {
                  refreshedVisibleRangeWhileInteracting =
                    galleryAlbumVisibleRefreshVisibleRangeIfAvailable(this.asVisibleLoadHost());
                  if (refreshedVisibleRangeWhileInteracting) {
                    this.lastInteractiveVisibleRangeRefreshAtMs = now;
                  }
                }
              }
            } else if (_scrollState === ScrollState.Idle) {
              if (this.isDraggingOrFling) {
                this.isDraggingOrFling = false;
                stateChanged = true;
              }
              if (this.listKineticScrolling) {
                this.listKineticScrolling = false;
                stateChanged = true;
              }
              this.lastInteractiveVisibleRangeRefreshAtMs = 0;
              if (this.visualPlaceholderMode) {
                this.visualPlaceholderMode = false;
                stateChanged = true;
              }
              if (this.timelineReleaseAwaitVisibleCallback) {
                if (!this.tryHandOffTimelineSeekToListDrivenFromScroller('onDidScrollIdle')) {
                  timelineGestureLogScrollDebug(
                    this.asTimelineGestureHost(),
                    '[scroll-release-visible] onDidScroll Idle: release still awaiting callback, force immediate visible load'
                  );
                  this.timelineReleaseAwaitVisibleCallback = false;
                  galleryAlbumVisibleLoadVisibleItemsImmediate(this.asVisibleLoadHost());
                }
              }
              if (wasDraggingOrFling) {
                timelineGestureScheduleMainListSettledWork(this.asTimelineGestureHost());
              }
            }
            if (stateChanged) {
              timelineGestureRefreshVisualPlaceholderMode(this.asTimelineGestureHost());
            }
            if (refreshedVisibleRangeWhileInteracting) {
              this.refreshRootPhotosScrollTitle();
              if (this.timelineReleaseAwaitVisibleCallback) {
                this.timelineReleaseAwaitVisibleCallback = false;
                galleryAlbumVisibleLoadVisibleItemsThrottled(this.asVisibleLoadHost(), true, true, true);
              } else {
                galleryAlbumVisibleLoadVisibleItemsThrottled(this.asVisibleLoadHost(), false, true, true);
              }
            }
            if (draggingOrFling || this.timelineSidebarDragging) {
              timelineGestureTouchTimelineBarOnScroll(this.asTimelineGestureHost());
            }
          },
          onListVisibleContentChange: (start: VisibleListContentInfo, end: VisibleListContentInfo): void => {
            if (start.index < 0 || end.index < 0) {
              return;
            }
            const flowStartIdx = this.flowNodeIndexFromMainListIndex(start.index);
            const flowEndIdx = this.flowNodeIndexFromMainListIndex(end.index);
            this.updateVisibleLoadPriorityFromVisibleRange(flowStartIdx, flowEndIdx);
            if (this.timelineSeekInProgress) {
              const handedOff = this.tryHandOffTimelineSeekToListDrivenFromCandidate(
                flowStartIdx,
                flowEndIdx,
                'onListVisibleContentChange'
              );
              if (this.timelineReleaseAwaitVisibleCallback) {
                timelineGestureLogScrollDebug(
                  this.asTimelineGestureHost(),
                  `[scroll-release-visible] onVisibleContentChange: raw=${start.index}~${end.index}, `
                  + `flow=${flowStartIdx}~${flowEndIdx}`
                );
                this.timelineReleaseAwaitVisibleCallback = false;
              }
              if (!handedOff) {
                galleryAlbumVisibleLoadVisibleItemsThrottled(this.asVisibleLoadHost(), true, true, true);
                return;
              }
              timelineGestureLogScrollDebug(
                this.asTimelineGestureHost(),
                `[scroll-release-visible] onVisibleContentChange: handoff complete, force immediate list-driven load, `
                + `raw=${start.index}~${end.index}, flow=${flowStartIdx}~${flowEndIdx}`
              );
              galleryAlbumVisibleLoadVisibleItemsThrottled(this.asVisibleLoadHost(), true, true, true);
              return;
            } else {
              this.applyListVisibleNodeRange(flowStartIdx, flowEndIdx);
              this.refreshRootPhotosScrollTitle();
            }
            const releaseFreezeActive =
              !this.timelineSidebarDragging &&
              !this.timelineSeekInProgress &&
              Date.now() < this.ignoreListFreezeUntilMs;
            if (this.timelineReleaseAwaitVisibleCallback) {
              timelineGestureLogScrollDebug(
                this.asTimelineGestureHost(),
                `[scroll-release-visible] onVisibleContentChange: raw=${start.index}~${end.index}, `
                + `flow=${flowStartIdx}~${flowEndIdx}`
              );
              this.timelineReleaseAwaitVisibleCallback = false;
              galleryAlbumVisibleLoadVisibleItemsThrottled(this.asVisibleLoadHost(), true, true, true);
            } else {
              if (this.isDraggingOrFling || releaseFreezeActive) {
                if (releaseFreezeActive) {
                  timelineGestureLogScrollDebug(
                    this.asTimelineGestureHost(),
                    `[scroll-release-visible] onVisibleContentChange: release-freeze interactive priority, `
                    + `raw=${start.index}~${end.index}, flow=${flowStartIdx}~${flowEndIdx}`
                  );
                }
                galleryAlbumVisibleLoadVisibleItemsThrottled(this.asVisibleLoadHost(), false, true, true);
              } else {
                galleryAlbumVisibleLoadVisibleItemsThrottled(this.asVisibleLoadHost(), false, false);
              }
            }
          },
          onRefreshOffsetChange: (offset: number): void => {
            if (this.gallerySelectionMode) {
              return;
            }
            const th = GALLERY_TIMELINE_REFRESH_OFFSET_VP;
            if (offset >= th) {
              if (!this.galleryPullRefreshThresholdHapticDone) {
                this.galleryPullRefreshThresholdHapticDone = true;
                playGalleryPullRefreshThresholdHaptic();
              }
            } else if (offset < th * 0.2) {
              this.galleryPullRefreshThresholdHapticDone = false;
            }
          },
          onRefreshing: (): void => {
            void galleryAlbumOnTimelinePullRefresh(this.asLoadOrchestratorHost());
          },
          onBatchDownload: (): void => {
            void galleryAlbumConfirmAndBatchDownload(this.asBatchActionHost());
          },
          onBatchDelete: (): void => {
            void galleryAlbumConfirmAndBatchDelete(this.asBatchActionHost());
          },
          onTimelineSeekToCurrentRatio: (): void => {
            galleryAlbumSeekTimelineListToDisplayRatio(this.asTimelineGestureHost(), this.timelineSliderRatio);
          },
          onTimelineTrackHeightChange: (height: number): void => {
            this.timelineScrubTrackHeightVp = height;
          },
          onTimelineTouchStateChange: (event: TouchEvent): void => {
            if (event.type === TouchType.Down) {
              this.timelinePressing = true;
              timelineGestureRefreshVisualPlaceholderMode(this.asTimelineGestureHost());
              timelineGestureShowTimelineBar(this.asTimelineGestureHost());
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.timelinePressing = false;
              this.timelineLongPressExpanded = false;
              timelineGestureRefreshVisualPlaceholderMode(this.asTimelineGestureHost());
              if (!this.timelineSidebarDragging) {
                timelineGestureShowTimelineBar(this.asTimelineGestureHost());
              }
            }
          },
          onTimelineLongPressExpand: (): void => {
            if (!this.timelineSidebarDragging) {
              this.timelineLongPressExpanded = true;
              timelineGestureShowTimelineBar(this.asTimelineGestureHost());
            }
          },
          onTimelinePanStart: (_event: GestureEvent): void => {
            this.timelineSidebarDragging = true;
            this.timelineLongPressExpanded = false;
            const ymList = galleryAlbumGetTimelineYearMonths(this.asTimelineGestureHost());
            if (ymList.length > 0) {
              this.applyTimelineSliderRatioFromFinger(_event, ymList.length);
              galleryAlbumSyncListVisibleRoughToTimelineSliderTarget(this.asTimelineGestureHost());
              this.refreshRootPhotosScrollTitle();
            }
            timelineGestureRefreshVisualPlaceholderMode(this.asTimelineGestureHost());
            timelineGestureArmTimelineDragWatchdog(this.asTimelineGestureHost());
            if (this.timelineHideTimer >= 0) {
              clearTimeout(this.timelineHideTimer);
              this.timelineHideTimer = -1;
            }
          },
          onTimelinePanUpdate: (event: GestureEvent): void => {
            const ymList = galleryAlbumGetTimelineYearMonths(this.asTimelineGestureHost());
            if (ymList.length === 0) {
              return;
            }
            this.applyTimelineSliderRatioFromFinger(event, ymList.length);
            galleryAlbumSyncListVisibleRoughToTimelineSliderTarget(this.asTimelineGestureHost());
            this.refreshRootPhotosScrollTitle();
            timelineGestureArmTimelineDragWatchdog(this.asTimelineGestureHost());
          },
          onTimelinePanEnd: (_event: GestureEvent): void => {
            this.endTimelineDrag();
          },
          onTimelinePanCancel: (_event: GestureEvent): void => {
            this.endTimelineDrag();
          }
        })
          .visibility(this.isRootPhotosSurfaceLayerVisible() ? Visibility.Visible : Visibility.None)
          .translate({ x: this.rootPhotosSurfaceTranslateX, y: 0 })
          .enabled(this.isRootPhotosSurfaceVisible())
          .hitTestBehavior(this.isRootPhotosSurfaceVisible() ? HitTestMode.Default : HitTestMode.None)
          .zIndex(this.rootPhotosSurfaceZIndex())
      }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))
        .onAreaChange((_old, area): void => {
          const width = area.width as number;
          if (width > 0 && Math.abs(width - this.rootModeContentWidthVp) > 0.5) {
            this.rootModeContentWidthVp = width;
          }
        })
      }
      .width('100%')
      .height('100%')

      if (this.galleryBatchDeleting) {
        FnFullLoadingMask({ text: '移入回收站中...' })
      }
      if (this.galleryBatchDownloading) {
        FnFullLoadingMask({ text: '下载中...' })
      }
      if (this.recentOpening) {
        FnFullLoadingMask({ text: '加载最近添加中...' })
      }
      if (this.collectOpening) {
        FnFullLoadingMask({ text: '加载收藏中...' })
      }
      if (this.categoryOpening) {
        FnFullLoadingMask({ text: this.categoryOpeningText })
      }

      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
        if (this.uploading) {
          FnFullLoadingMask({ text: this.uploadText.length > 0 ? this.uploadText : '上传中...' })
        }
      }
    }
    .width('100%')
    .height('100%')
  }
}

