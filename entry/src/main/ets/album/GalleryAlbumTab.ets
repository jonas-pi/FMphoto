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
  pickThumb
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
import { FnFullLoadingMask } from '../common/FnUiCommon';
import {
  FN_TAB_SWITCH_CURVE,
  FN_TAB_SWITCH_IN_DURATION,
  FN_TAB_SWITCH_OUT_DURATION
} from '../common/FnMotion';
import {
  GALLERY_TOP_BAR_BUTTON_FONT_VP,
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_ROW_HEIGHT_VP,
  GALLERY_TOP_BAR_SUBTITLE_FONT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from '../common/GalleryTopBarLayout';
import {
  GALLERY_BATCH_ACTION_HEIGHT_VP,
  GALLERY_BATCH_BAR_PAD_BOTTOM_VP,
  GALLERY_BATCH_BAR_PAD_LEFT_VP,
  GALLERY_BATCH_BAR_PAD_RIGHT_VP,
  GALLERY_BATCH_BAR_PAD_TOP_VP,
  GALLERY_BATCH_BAR_SPACE_VP,
  GALLERY_BATCH_DESTRUCTIVE_BG,
  GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_BOTTOM_VP,
  GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_LEFT_VP,
  GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_RIGHT_VP,
  GALLERY_HOME_NAV_CHIP_FONT_VP,
  GALLERY_HOME_NAV_CHIP_HEIGHT_VP,
  GALLERY_HOME_NAV_CHIP_PAD_H_VP,
  GALLERY_HOME_NAV_CHIP_RADIUS_VP,
  GALLERY_HOME_UPLOAD_FAB_MARGIN_BOTTOM_VP,
  GALLERY_HOME_UPLOAD_FAB_MARGIN_RIGHT_VP,
  GALLERY_HOME_UPLOAD_FAB_SIZE_VP
} from '../common/GalleryButtonStyles';
import { GalleryAlbumTopBar } from './galleryAlbumTab/GalleryAlbumTopBar';
import { GalleryAlbumEntryChips } from './galleryAlbumTab/GalleryAlbumEntryChips';
import { GalleryAlbumSearchModeView } from './galleryAlbumTab/GalleryAlbumSearchModeView';
import { GalleryAlbumCategoryModeView } from './galleryAlbumTab/GalleryAlbumCategoryModeView';
import { GalleryAlbumSmartCategoryModeView } from './galleryAlbumTab/GalleryAlbumSmartCategoryModeView';
import { GalleryAlbumPersonModeView } from './galleryAlbumTab/GalleryAlbumPersonModeView';
import { GalleryAlbumMainModeView } from './galleryAlbumTab/GalleryAlbumMainModeView';
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
  galleryAlbumPickAndUpload,
  galleryAlbumPlayModeSwitchMotion,
  galleryAlbumRunSearch,
  galleryAlbumStartUpload,
  galleryAlbumTryConsumeHardwareBack,
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
  selectionEndGallerySlideSelectGesture,
  selectionHitGalleryThumbDomPx,
  selectionHitSearchThumbDomPx,
  selectionOnGallerySlidePanUpdate,
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
  GALLERY_TIMELINE_LONG_PRESS_EXPAND_MS,
  GALLERY_TIMELINE_RAIL_AUTO_HIDE_MS,
  GALLERY_TIMELINE_RAIL_DRAG_VP,
  GALLERY_TIMELINE_RAIL_EXPANDED_VP,
  GALLERY_TIMELINE_RAIL_MIN_VP,
  GALLERY_TIMELINE_REFRESH_OFFSET_VP,
  GALLERY_TIMELINE_SCRUB_PILL_MIN_WIDTH_VP,
  GALLERY_TIMELINE_SCRUB_PILL_X_VP,
  GALLERY_TIMELINE_THUMB_VP,
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

// 鈹€鈹€鈹€ 涓?Tab 缁勪欢 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

@Component
export struct GalleryAlbumTab {
  @Prop baseUrl: string = '';
  @Prop @Watch('onEpochChange') albumReloadEpoch: number = 0;
  @Prop topSafeInsetVp: number = 0;
  @Prop bottomSafeInsetVp: number = 0;
  /** Home.onPageShow() 閫掑 鈫?瑙﹀彂鍒犻櫎鍚屾锛堝畨鍏ㄤ繚闅滐紝涓嶄緷璧栧瓙缁勪欢 onPageShow 浼犳挱锛?*/
  @Prop @Watch('onPageShowSignal') pageShowSignal: number = 0;

  @State private bootLoading: boolean = false;
  @State private loadError: string = '';
  @State private footText: string = '';
  @State private sections: GalleryAlbumDaySectionState[] = [];

  // 鈹€鈹€ 鎼滅储鐘舵€?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  @State private searchQuery: string = '';
  @State private inSearchMode: boolean = false;
  @State private searchResults: GalleryListItem[] = [];
  @State private searchLoading: boolean = false;
  @State private searchError: string = '';
  @State private inCategoryMode: boolean = false;
  @State private categoryLoading: boolean = false;
  @State private categoryOpening: boolean = false;
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
  /** 鎵撳紑銆屾敹钘忋€嶈仛鍚堝垪琛ㄦ椂鐨勫叏灞忛伄缃╋紙涓庢渶杩戞坊鍔犱竴鑷达級 */
  @State private collectOpening: boolean = false;
  @State private personError: string = '';
  @State private personItems: AiPersonItem[] = [];
  @State private personStatVersion: number = 0;
  /** 涓婁紶鐘舵€?*/
  @State private uploading: boolean = false;
  @State private uploadText: string = '';
  /** 涓诲浘搴撻暱鎸夊閫夛紙涓庣郴缁熸嫋鎷?涓浆绔欒В鑰︼細缂╃暐鍥惧凡 draggable(false)锛?*/
  @State private gallerySelectionMode: boolean = false;
  @State private gallerySelectedIds: string[] = [];
  @State private galleryBatchDeleting: boolean = false;
  @State private galleryBatchDownloading: boolean = false;
  /**
   * 涓绘椂闂寸嚎 List 鏄惁鍝嶅簲鎵嬫寚婊氬姩銆?
   * 鍒掗€夋椂涓存椂鍏抽棴锛岄伩鍏?List 鎶㈣蛋 Pan锛汱azyForEach 琛?key 鍕块殢澶氶€夊垏鎹紝鍚﹀垯瀛愭爲閲嶅缓浼氫腑鏂綋鍓嶆寚涓嬫墜鍔裤€?
   */
  @State private galleryMainListScrollEnabled: boolean = true;
  /**
   * 缁熶竴浜や簰鐘舵€佹満锛?
   * - timelineSidebarDragging: 鏃堕棿杞存墜鍔胯繘琛屼腑
   * - isDraggingOrFling: 涓诲垪琛ㄦ鍦ㄦ嫋鍔?鎯€э紙Scroll/Fling锛?
   * - visualPlaceholderMode: 鍥剧墖鍔犺浇闂ㄦ帶锛堟椂闂磋酱鎷栧姩鎴栦富鍒楄〃鎷栧姩/鎯€ф椂涓?true锛?
   *
   * 绾︽潫锛氫换浣曞浘鐗囪姹傚紑鍏抽兘鍙湅 visualPlaceholderMode锛岄伩鍏嶅鐘舵€佷簰鐩歌鐩栥€?
   */
  @State private timelineSidebarDragging: boolean = false;
  @State private listKineticScrolling: boolean = false;
  @State private isDraggingOrFling: boolean = false;
  @State private visualPlaceholderMode: boolean = false;
  /** 涓诲垪琛?Idle 鍚?settled 闃叉姈瀹氭椂鍣?id锛涘啀娆℃粴鍔ㄦ椂鍙栨秷 */
  private listSettledTimer: number = -1;
  /** settled 闃叉姈浠ｆ锛岄伩鍏嶆棫瀹氭椂鍣ㄥ洖鍐?*/
  private listSettledGen: number = 0;
  /** 婊氬姩鎺掗殰锛氫笂娆℃粴鍔ㄦ棩蹇楁椂闂存埑 */
  private lastScrollDebugLogMs: number = 0;
  /** 婊氬姩鎺掗殰锛氫笂娆℃粴鍔ㄧ姸鎬佹枃鏈紙浠呯姸鎬佸彉鍖栨垨鑺傛祦鍒版湡鎵嶆墦鍗帮級 */
  private lastScrollDebugState: string = 'init';
  /** 鏈€杩戜竴娆′富鍒楄〃浜や簰鏃堕棿锛堢敤浜庨檺鍒舵车鏃ュ織浠呭湪浜や簰绐楀彛杈撳嚭锛?*/
  private lastMainListInteractMs: number = 0;
  /** 鏃堕棿杞存嫋鍔ㄦ€?watchdog 瀹氭椂鍣?*/
  private timelineDragWatchdogTimer: number = -1;
  /** 鏃堕棿杞存嫋鍔ㄤ細璇濅唬娆★紙鐢ㄤ簬鍙栨秷鏃?watchdog 鍥炲啓锛?*/
  private timelineDragWatchdogGen: number = 0;
  /** 婊氬姩鏃惰Е杈炬椂闂磋酱鏄鹃殣鐨勮妭娴佹椂闂存埑锛岄伩鍏嶆瘡甯ч噸缃?show/hide 瀹氭椂鍣?*/
  private lastTimelineBarTouchMs: number = 0;
  /** 涓诲垪琛?-> 鏃堕棿杞存墜鏌勪綅缃悓姝ヨ妭娴佹椂闂存埑锛堥伩鍏?onScrollIndex 楂橀椹卞姩鎵嬫焺閲嶇粯锛?*/
  private lastTimelineHandleSyncMs: number = 0;
  private navigationGuardEpoch: number = 0;
  /** 鏃堕棿杞存槸鍚︽樉绀猴紙婊氬姩涓?浜や簰涓樉寮忓彲瑙侊紝闈欐鍚庤嚜鍔ㄦ贰鍑猴級 */
  @State private timelineBarVisible: boolean = false;
  /** 鏃堕棿杞存寜鍘嬫€侊細鎵嬫寚鍦ㄨ建閬撲笂锛堢敤浜庢樉闅愪笌瑙︽劅锛屼笉绛夊悓浜庛€屽睍寮€ scrub銆嶏級 */
  @State private timelinePressing: boolean = false;
  /** 闀挎寜缁嗚建鍚庤繘鍏ュ畬鏁村睍寮€鎬侊紙骞存湀姘旀场銆佸勾浠藉埢搴︾瓑锛夛紱绾靛悜鎷栧姩涔熶細杩涘叆灞曞紑 */
  @State private timelineLongPressExpanded: boolean = false;
  /** 婊戝潡姣斾緥 [0,1]锛?=鏈€鏂帮紝1=鏈€鏃?*/
  @State private timelineSliderRatio: number = 0;
  /** 褰撳墠楂樹寒鏈堜唤鍦ㄦ椂闂磋酱骞存湀鍒楄〃涓殑涓嬫爣 */
  @State private timelineSidebarHighlightIndex: number = 0;
  /** 鎸囩ず鏍囩鐨?Y 浣嶇疆锛坴p锛?*/
  @State private timelineIndicatorY: number = 12;
  /** 鏃堕棿杞村彲鐢ㄨ建閬撻珮搴︼紙vp锛夛紝鐢?onAreaChange 瀹炴祴鍐欏叆 */
  @State private timelineScrubTrackHeightVp: number = 500;
  /** 鎷栧姩寮€濮嬫椂姣斾緥 */
  private timelineDragStartRatio: number = 0;
  /** 鎷栧姩鑺傛祦锛坢s锛?*/
  private lastTimelineDragScrollMs: number = 0;
  /** 鑷姩闅愯棌瀹氭椂鍣?*/
  private timelineHideTimer: number = -1;
  /** seek 淇濇姢鏍囪锛氭澗鎵嬪悗鐭獥鍐呴樆鏂弽鍚戝悓姝?*/
  private timelineSeekInProgress: boolean = false;
  /** seek 鐩戣鍣ㄤ唬娆★細鏂版嫋鍔ㄥ彲鍙栨秷鏃т换鍔?*/
  private timelineSeekGen: number = 0;
  /** 褰撳墠 List 鍙鑺傜偣鍖洪棿锛堢敱 onScrollIndex 鍥炰紶锛?*/
  private listVisibleFirstNodeIdx: number = 0;
  private listVisibleLastNodeIdx: number = 0;
  /**
   * onScrollIndex 鏈€杩戜竴娆″洖璋冩椂鐨?Scroller 绾靛悜鍋忕Щ涓庨绱㈠紩銆?
   * LazyForEach + 鍏ㄩ噺楠ㄦ灦涓嬪垪琛ㄥ父銆屾粴鍔ㄤ簡寰堜箙鎵嶆洿鏂?first/last銆嶏紝鐢?(yNow - anchorY) 鍚戝墠鎺ㄨ繘鑺傜偣浠ヨ创鍚堢湡瀹炶鍙ｃ€?
   */
  private listScrollIndexAnchorYVp: number = 0;
  private listScrollIndexAnchorFirst: number = 0;
  private listScrollIndexAnchorHave: boolean = false;
  /**
   * 鍏ㄦ椂闂寸嚎銆岀収鐗囨Ы浣嶃€嶄笅鏍囩紦瀛橈紙涓?countPhotoSlotsBeforeNode 涓€鑷达級锛?
   * 鍙鍖哄彧鏈夋爣棰樿鏃?onScrollIndex 浼氬緱鍒?visEnd<=visStart锛屽鑷?loadVisible 姘歌繙涓嶈Е鍙戯紱
   * 鐢ㄦ渶杩戜竴娆℃湁鏁堝彲瑙嗘Ы浣嶄綔涓烘澗鎵?闈欐鍚庣殑鍔犺浇閿氱偣銆?
   */
  private lastKnownGlobalPhotoSlotStart: number = 0;
  private lastKnownGlobalPhotoSlotEndExclusive: number = 0;
  /** 鍙鍖洪鍔犺浇缂撳啿锛堜互鈥滅収鐗囨Ы浣嶁€濊锛?*/
  private readonly visiblePhotoBufferSlots: number = 12;
  /** 鍙鍖洪┍鍔ㄥ姞杞借妭娴侊細閬垮厤 Idle 鎶栧姩鏃堕珮棰戣Е鍙?loadVisibleItems */
  private lastLoadVisibleAtMs: number = 0;
  private loadVisibleRetryTimer: number = -1;
  private loadVisibleRetryGen: number = 0;
  /** pump 浠ｆ锛氭柊婊氬姩寮€濮嬫椂閫掑锛屾棫 pump/鍥炶皟绔嬪嵆澶辨晥锛堟墦鏂苟鍙戦摼璺級 */
  private pumpEpoch: number = 0;
  /** 鏃堕棿杞存澗鎵嬪悗鐭獥鍐呭拷鐣ョ▼搴忓寲婊氬姩瀵瑰喕缁撴€佺殑鍥炲啓锛岄槻姝⑩€滃繀椤诲啀婊戜竴涓嬫墠鍔犺浇鈥?*/
  private ignoreListFreezeUntilMs: number = 0;
  private timelineReleaseAwaitVisibleCallback: boolean = false;
  /** 瑙嗚鍐荤粨鏈燂紙鎷栧姩/Fling锛夋敹鍒扮殑鏁版嵁鍙樻洿寤惰繜鍒拌В鍐诲悗鍐嶄竴娆℃€у埛鏂帮紝閬垮厤婊氬姩鏉′笉璺熸墜 */
  private pendingFlowRebuild: boolean = false;
  /** 閬垮厤婊氬姩鍋滄鍚庨噸澶嶈Е鍙戝悓涓€鐩爣鏃ョ殑鎶㈠崰鍔犺浇 */
  private lastVisibleLoadDayIdx: number = -1;
  /** 妯″紡鍒囨崲鏃跺唴瀹瑰眰鍔ㄦ晥锛堟贰鍏?+ 杞诲井浣嶇Щ锛?*/
  @State private modeSwitchOpacity: number = 1;
  @State private modeSwitchOffsetY: number = 0;
  /** WaterFlow + LazyForEach 鏁版嵁婧愶紙涓?sections 鍚屾锛?*/
  private flowDataSource: GalleryWaterFlowDataSource = new GalleryWaterFlowDataSource();

  private loadGen: number = 0;
  private personStatGen: number = 0;
  private personStatOverrides: Map<string, string> = new Map<string, string>();
  private orderedDays: TimelineDayModel[] = [];
  private dayIndex: number = 0;
  private loadingMore: boolean = false;
  private exhausted: boolean = false;
  private dayOffsets: Map<string, number> = new Map<string, number>();
  /** 姣忓ぉ宸茶姹傜殑鎵规鏁帮紙瀹夊叏涓婇檺锛岄槻姝?itemCount 涓嶅噯鏃舵棤闄愬惊鐜級 */
  private dayRounds: Map<string, number> = new Map<string, number>();
  /** 姣忓ぉ杩炵画绌洪〉璁℃暟锛堥槻姝㈠崟娆＄┖椤佃鍒囨棩锛?*/
  private dayEmptyRounds: Map<string, number> = new Map<string, number>();
  private scrollerRef: Scroller = new Scroller();
  /** 涓婃宸插鐞嗙殑鍒犻櫎鍚屾鐗堟湰鍙?*/
  private handledDeleteSyncVersion: number = 0;
  /** 闀挎寜鍚庡湪姝ゆ椂闂存埑涔嬪墠蹇界暐鍗曞嚮锛岄伩鍏嶈杩涢瑙?*/
  private galleryLongPressIgnoreClickUntil: number = 0;
  /**
   * 銆屽垝閫夋銆嶈繘琛屼腑锛氫负 true 鏃?onDidScroll 涓嶆竻绌哄懡涓紦瀛橈紱涓?Row 涓?Pan 鍒囦负鍏ㄥ悜浠ヨ法琛屽垝閫夈€?
   * 涓?@State 浠ヤ究澶氶€夋€佷笅鍦ㄣ€屼粎妯悜 Pan / 鍏ㄥ悜 Pan銆嶉棿鍒囨崲锛堝榻愮郴缁熺浉鍐岋細绾垫粦鍒楄〃銆佹í婊戝垝閫夛級銆?
   */
  @State private gallerySlideGestureActive: boolean = false;
  /** 鍚勭缉鐣ュ浘鏈€杩戜竴娆″竷灞€鍦ㄧ獥鍙ｄ腑鐨勭煩褰紙浠呭綋鍓嶅彲瑙?鏇惧竷灞€椤规湁鍊硷紱鍒楄〃婊氬姩鏃朵細娓呯┖浠ラ槻鑴忕煩褰級 */
  private galleryThumbHitBounds: Map<string, GalleryThumbHitRect> = new Map<string, GalleryThumbHitRect>();
  /** AI 鎼滅储缁撴灉鍒楄〃鍒掗€夊懡涓煩褰紙閿负鎵佸钩涓嬫爣瀛楃涓诧紝涓?`sg_${flat}` 瀵瑰簲锛?*/
  private searchThumbHitBounds: Map<string, GalleryThumbHitRect> = new Map<string, GalleryThumbHitRect>();
  /** 婊戝姩杩為€夛細fingerList 涓嶅彲鐢ㄦ椂锛岀敤闀挎寜鍙傝€冪偣 + Pan offset 浼扮畻鎸囧皷浣嶇疆 */
  private gallerySlideRefX: number = 0;
  private gallerySlideRefY: number = 0;
  private gallerySlideHasRef: boolean = false;
  /**
   * 鍒掗€夐敋鐐癸細闀挎寜璧峰缂╃暐鍥惧湪鎵佸钩鍒楄〃涓殑涓嬫爣锛堜笌 flow row 鐨?rowSlotFlatIndices 涓€鑷达紝琛屼紭鍏?3 鍒椾竴琛岋級銆?
   */
  private gallerySlideAnchorFlat: number = -1;
  /**
   * 杩涘叆鏈鍒掗€夊墠宸查€変腑鐨?id锛堜笉鍚悗缁粦鍔ㄤ复鏃舵墿閫夋椂鍙啀鏀剁缉鐨勯儴鍒嗛€氳繃銆屽尯闂村苟闆嗐€嶈绠楋級銆?
   * 鍦?begin 鏃跺彇 snapshot锛屼繚璇佺缉鍥炴墜鎸囨椂鍙幓鎺夈€屽綋鍓?flat 鍖洪棿銆嶅唴銆佷笖涓嶅湪姝ら泦鍚堜腑鐨勯」銆?
   */
  private gallerySlideUnionBase: string[] = [];
  /**
   * 褰撳墠鍒掗€夊尯闂寸粓鐐?flat锛涙寚灏栫煭鏆傜寮€缂╃暐鍥炬椂娌跨敤涓婁竴娆″懡涓紝閬垮厤閫変腑闂儊銆?
   */
  private gallerySlideLastEndFlat: number = -1;
  /** 鍒掗€夋椂浠呭綋缁堢偣 flat 鍙樺寲鏃舵墠鎻愪氦 @State锛屽噺杞诲垪琛ㄦ暣琛ㄥ埛鏂板崱椤?*/
  private gallerySlideLastAppliedEndFlat: number = -99999;
  private gallerySlideLastApplyMs: number = 0;
  private gallerySlidePendingEndFlat: number = -1;
  /** 闃叉姈瀹氭椂鍣?id锛?0 琛ㄧず鏈寕璧凤級 */
  private bootstrapDebounceTimer: number = -1;
  /** 涓?GalleryTimelineRefreshStore.version 瀵归綈锛氭垚鍔?bootstrap 鏃堕棿杞村悗鏇存柊锛岄伩鍏嶉噸澶嶅叏閲忓埛 */
  private lastBootstrapSatisfiedRefreshVersion: number = 0;
  /** 鏃堕棿绾?List 涓嬫媺鍒锋柊锛氱郴缁?Refresh 鍔ㄦ晥缁戝畾 */
  @State private galleryTimelineRefreshing: boolean = false;
  /**
   * 鏃堕棿绾挎槸鍚﹀湪鍒楄〃椤剁锛圫croller 鍨傜洿鍋忕Щ鈮?锛夈€傞潪 @State锛岄伩鍏嶆粴鍔ㄦ椂鏁撮〉閲嶇粯锛?
   * 鍦?onDidScroll / 涓嬫媺鍥炶皟鍓嶅悓姝ワ紝浠呯敤浜庡垽鏂槸鍚﹀厑璁歌Е鍙戝埛鏂般€?
   */
  private galleryTimelineAtTopForPull: boolean = true;
  /** 涓嬫媺鏈洖鍒伴《閮ㄩ檮杩戝墠涓嶉噸澶嶈Е鍙戙€屽凡杈鹃槇鍊笺€嶉渿鍔紝閬垮厤鏉ュ洖鎷栧姩杩炵画鎸?*/
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

  private setGallerySelectionModeState(value: boolean): void {
    if (this.gallerySelectionMode === value) {
      return;
    }
    this.gallerySelectionMode = value;
    this.notifyMainGallerySelectionVisualRefresh();
  }

  private setGallerySelectedIdsStateLocal(value: string[]): void {
    this.gallerySelectedIds = value;
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
      set orderedDays(value: TimelineDayModel[]) { self.orderedDays = value; }
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
      get listVisibleFirstNodeIdx(): number { return self.listVisibleFirstNodeIdx; }
      set listVisibleFirstNodeIdx(value: number) { self.listVisibleFirstNodeIdx = value; }
      get listVisibleLastNodeIdx(): number { return self.listVisibleLastNodeIdx; }
      set listVisibleLastNodeIdx(value: number) { self.listVisibleLastNodeIdx = value; }
      get ignoreListFreezeUntilMs(): number { return self.ignoreListFreezeUntilMs; }
      set ignoreListFreezeUntilMs(value: number) { self.ignoreListFreezeUntilMs = value; }
      get pumpEpoch(): number { return self.pumpEpoch; }
      set pumpEpoch(value: number) { self.pumpEpoch = value; }
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
      syncListVisibleRoughToTimelineSliderTarget(): void { galleryAlbumSyncListVisibleRoughToTimelineSliderTarget(this); }
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
      set orderedDays(value: TimelineDayModel[]) { self.orderedDays = value; }
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
      set orderedDays(value: TimelineDayModel[]) { self.orderedDays = value; }
      get sections(): GalleryAlbumDaySectionState[] { return self.sections; }
      set sections(value: GalleryAlbumDaySectionState[]) { self.sections = value; }
      get visualPlaceholderMode(): boolean { return self.visualPlaceholderMode; }
      set visualPlaceholderMode(value: boolean) { self.visualPlaceholderMode = value; }
      get isDraggingOrFling(): boolean { return self.isDraggingOrFling; }
      set isDraggingOrFling(value: boolean) { self.isDraggingOrFling = value; }
      get timelineSidebarDragging(): boolean { return self.timelineSidebarDragging; }
      set timelineSidebarDragging(value: boolean) { self.timelineSidebarDragging = value; }
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
      get timelineSliderRatio(): number { return self.timelineSliderRatio; }
      set timelineSliderRatio(value: number) { self.timelineSliderRatio = value; }
      resolveDayByGlobalIndex(globalIndex: number): DayGlobalResolveResult | null {
        return galleryAlbumResolveDayByGlobalIndex(self.asTimelineGestureHost(), globalIndex);
      }
      resolveYearMonthByTimelineRatio(ratio: number): TimelineYearMonthPair | null {
        return galleryAlbumResolveYearMonthByTimelineRatio(self.asTimelineGestureHost(), ratio);
      }
      isInScrollInteractiveLogWindow(): boolean { return timelineGestureIsInScrollInteractiveLogWindow(self.asTimelineGestureHost()); }
      logScrollDebug(msg: string): void { timelineGestureLogScrollDebug(self.asTimelineGestureHost(), msg); }
      rebuildFlow(): void { galleryAlbumRebuildFlow(self.asVisibleLoadHost()); }
      pumpLoad(singleBatch?: boolean): void { galleryAlbumPumpLoad(self.asLoadOrchestratorHost(), singleBatch); }
      loadOneBatch(): Promise<number> { return galleryAlbumLoadOneBatch(self.asLoadOrchestratorHost()); }
    }
    return new VisibleLoadHostBridge();
  }

  // 鈹€鈹€ 鎵佸钩鍒楄〃锛堜緵璺宠浆鐙珛棰勮椤碉級 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  private countPhotoSlotsBeforeNode(nodeIdx: number): number {
    return galleryAlbumVisibleCountPhotoSlotsBeforeNode(this.asVisibleLoadHost(), nodeIdx);
  }

  /** orderedDays[0..dayIdx) 鐨勫叏灞€妲戒綅鍓嶇紑鍜?*/
  private globalSlotIndexAtDayStart(dayIdx: number): number {
    return galleryAlbumVisibleGlobalSlotIndexAtDayStart(this.asVisibleLoadHost(), dayIdx);
  }

  /**
   * 鏍规嵁 List 鍙鑺傜偣鍖洪棿鍒锋柊銆屽叏灞€鐓х墖妲戒綅銆嶇紦瀛橈紱鍙瀛樺湪 row 鍗冲啓鍏ワ紝渚?loadVisible 鍦?vis 閫€鍖栨椂浣跨敤銆?
   */
  private refreshLastKnownGlobalSlotsFromListIndices(firstIdx: number, lastIdx: number): void {
    galleryAlbumVisibleRefreshLastKnownGlobalSlotsFromListIndices(this.asVisibleLoadHost(), firstIdx, lastIdx);
  }

  private captureListScrollIndexAnchor(): void {
    galleryAlbumVisibleCaptureListScrollIndexAnchor(this.asVisibleLoadHost());
  }

  private approxGalleryFlowListNodeHeightVp(node: GalleryFlowNode): number {
    return galleryAlbumVisibleApproxGalleryFlowListNodeHeightVp(node);
  }

  /** 鑷?anchorFirst 璧峰悜涓嬨€屽悆鎺夈€峝eltaVp 鍐呭浣嶇Щ鍚庯紝杩戜技鐨勯鍙鑺傜偣涓嬫爣 */
  /**
   * 鐢?List 椤堕儴绱杩戜技楂樺害锛屼及绠?yVp 澶勫搴旂殑棣栦釜鑺傜偣涓嬫爣锛堜笌 Scroller.yOffset 鍚屽悜锛夈€?
   * 浠呬綔 refine 涓嬬晫锛屾鏁板皝椤堕伩鍏嶈秴闀垮垪琛ㄥ崟娆?O(n)銆?
   */
  private estimateFirstVisibleNodeIndexFromScrollY(yVp: number, total: number): number {
    return galleryAlbumVisibleEstimateFirstVisibleNodeIndexFromScrollY(this.asVisibleLoadHost(), yVp, total);
  }

  private consumeVerticalScrollDeltaAsNodeIndex(startIdx: number, deltaVp: number): number {
    return galleryAlbumVisibleConsumeVerticalScrollDeltaAsNodeIndex(this.asVisibleLoadHost(), startIdx, deltaVp);
  }

  /**
   * 涓?consumeVerticalScrollDeltaAsNodeIndex 瀵圭О锛歽 鍑忓皬锛堝垪琛ㄥ唴瀹瑰悜涓婃粴銆佺湅杈冩柊涓€渚э級鏃讹紝
   * 浠庨敋鐐硅妭鐐瑰悜涓婃秷璐?deltaVp 鐨勮繎浼奸珮搴︼紝寰楀埌鏇村皬鐨勯鍙鑺傜偣涓嬫爣銆?
   */
  private consumeVerticalScrollDeltaAsNodeIndexBackward(startIdx: number, deltaVp: number): number {
    return galleryAlbumVisibleConsumeVerticalScrollDeltaAsNodeIndexBackward(this.asVisibleLoadHost(), startIdx, deltaVp);
  }

  /**
   * 鐢?Scroller 绾靛悜鍋忕Щ鐩稿銆屼笂娆?onScrollIndex 閿氱偣銆嶇殑澧為噺锛屾妸澹扮О鐨?first/last 鍚戝墠鎺紝
   * 缂撹В ArkUI List + LazyForEach 涓嬬储寮曞洖璋冩粸鍚庝簬鐪熷疄瑙嗗彛鐨勯棶棰樸€?
   */
  private refineVisibleNodeIndicesAgainstScrollLag(claimedFirst: number, claimedLast: number): GalleryVisibleNodeRange {
    return galleryAlbumVisibleRefineVisibleNodeIndicesAgainstScrollLag(this.asVisibleLoadHost(), claimedFirst, claimedLast);
  }

  /** 缁熻 [first,last] 鑺傜偣鍖洪棿鍐?row 閲屼粛涓洪鏋讹紙null锛夌殑鐓х墖妲戒綅鏁帮紝鐢ㄤ簬鎸夊睆鍐呭崰浣嶆墿灞曟媺鍙栬寖鍥?*/
  private countSkeletonPhotoSlotsInFlowNodeRange(first: number, last: number): number {
    return galleryAlbumVisibleCountSkeletonPhotoSlotsInFlowNodeRange(this.asVisibleLoadHost(), first, last);
  }

  /** 涓嬫柟鍏ㄥ眬妲戒綅缂撳啿锛氫繚搴?+ 鎸夊綋鍓嶇獥鍙ｅ唴楠ㄦ灦妲戒綅鏁版斁澶э紙涓婇檺 cap锛?*/
  private computeLoadVisibleBufferAfterSlots(aggressive: boolean, scanFirst: number, scanLast: number): number {
    return galleryAlbumVisibleComputeLoadVisibleBufferAfterSlots(this.asVisibleLoadHost(), aggressive, scanFirst, scanLast);
  }

  /**
   * 婊氬姩闈欐鍚庢寜鍙鍖鸿Е鍙戔€滄棩绾т紭鍏堝姞杞解€濓細
   * - 鑻?Scroller.getVisibleRange 鍙敤锛氫互杩斿洖鍖洪棿涓哄敮涓€鍙鑺傜偣绐楋紝**璺宠繃 refine**锛屽啀鏄犲皠鍒板叏灞€妲戒綅骞舵墿灞?buffer锛堜笌 RecyclerView 棣栨湯鍙椤归┍鍔ㄥ姞杞戒竴鑷达級锛?
   * - 鍚﹀垯浠嶈蛋 refine + y 鍙嶆帹鍏滃簳锛?
   * - 鍙嶆煡鐩爣鏃ワ紝鑻ュ綋鍓?dayIndex 钀藉悗鍒欏墠绉诲埌鐩爣鏃ュ苟鍚姩 pumpLoad銆?
   *
   * 娉ㄦ剰锛氱幇鏈?sections 缁撴瀯鏄€滃墠缂€杩炵画鐪熷疄鏁版嵁鈥濓紝涓嶈兘瀹夊叏璺?offset锛堜細鎵撲贡鏄犲皠锛夛紝
   * 鍥犳姝ゅ浠呭仛鈥滄寜澶╂姠鍗犫€濊€屼笉鐩存帴鏀?dayOffsets 鍒颁腑闂撮〉銆?
   */
  private loadVisibleItemsThrottled(forceImmediate: boolean = false, aggressive: boolean = false): void {
    galleryAlbumVisibleLoadVisibleItemsThrottled(this.asVisibleLoadHost(), forceImmediate, aggressive);
  }

  /**
   * 璺ㄦ棩绐楀彛鍙兘杩滃ぇ浜?GALLERY_LOAD_VISIBLE_MULTI_DAY_CHAIN_MAX锛涘崟娈靛彧娉靛墠 N 澶╀細鍦ㄥ睆涓婂舰鎴愩€岃浇涓€娈点€佺┖涓€娈点€嶆潯绾广€?
   * 鎸夊浐瀹氬潡椤哄簭娉靛畬鏁翠釜 [loD, hiD]锛堝潡闂翠粛鍙?epoch / 浜や簰鎬?gate锛夈€?
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
   * 鍙妲戒綅鍖洪棿璺ㄥ涓棩鍘嗘棩鏃讹紝瀵圭獥鍙ｅ唴娑夊強鐨勬瘡涓棩椤哄簭鍚勮姹備竴鎵癸紝骞跺湪杩涘叆璇ユ棩鍓嶆妸 offset 瀵归綈鍒颁笌 [startG,endG] 閲嶅彔鐨勮捣鐐广€?
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
   * 鏃堕棿杞存澗鎵嬪悗鐨勪富鍔ㄦ仮澶嶏細涓嶄緷璧栫敤鎴峰啀婊戝姩锛岀洿鎺ユ媺璧峰彲瑙嗗尯鍔犺浇銆?
   * 鍙岄樁娈佃Е鍙戠敤浜庤鐩栥€岀▼搴忓寲 seek 灏氭湭瀹屾垚鍙鍖哄洖浼犮€嶇獥鍙ｃ€?
   */
  private kickPostTimelineReleaseLoad(): void {
    timelineGestureKickPostTimelineReleaseLoad(this.asTimelineGestureHost());
  }

  private endTimelineDrag(): void {
    this.timelineReleaseAwaitVisibleCallback = true;
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

  private invalidateNavigationGuard(): void {
    this.navigationGuardEpoch++;
  }

  private async openCategory(cat: MediaCategoryItem): Promise<void> {
    await galleryAlbumOpenCategory(this.asModeOrchestratorHost(), cat);
  }

  /**
   * 鏈€杩戞坊鍔狅細鎸?explore/recent_timeline 鍒嗘《鍚庨€愭棩鍒嗛〉鎷?recent_photos锛?
   * 鑱氬悎涓哄钩閾哄垪琛ㄥ苟澶嶇敤 CategoryGallery 棰勮椤垫墦寮€銆?
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
   * 鏀惰棌澶癸細GET gallery/timeline?is_collect=1 鍒嗘棩鍚庯紝鎸夋棩 GET getList锛坢ode=collect & is_collect=1锛夛紝
   * 涓?Web /p/collect 鎶撳寘涓€鑷淬€?
   */
  private async openCollectGallery(): Promise<void> {
    await galleryAlbumOpenCollectGallery(this.asModeOrchestratorHost());
  }

  // 鈹€鈹€ 鐢熷懡鍛ㄦ湡 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  private onEpochChange(): void {
    setTimeout((): void => {
      this.requestBootstrap(false);
    }, 0);
  }

  private onPageShowSignal(): void {
    galleryAlbumOnTabVisibleAgain(this.asLoadOrchestratorHost());
  }

  aboutToAppear(): void {
    // 椤甸潰閲嶆柊鍑虹幇鏃堕噸缃墦寮€鎬侊紝閬垮厤鎵嬪娍杩斿洖鍚庤鏃ч伄缃╃姸鎬佸崱浣?
    this.personOpening = false;
    this.categoryOpening = false;
    this.recentOpening = false;
    this.collectOpening = false;
    this.timelineReleaseAwaitVisibleCallback = false;
    gallerySetAlbumBackHandler((): boolean => galleryAlbumTryConsumeHardwareBack(this.asModeOrchestratorHost()));
    setTimeout((): void => {
      // 涓绘椂闂寸嚎锛氳嫢绂诲紑 Tab 鏃跺瓨杩囧揩鐓т笖鏈熼棿鏈?bump/鏈己鍒凤紝鐩存帴鎭㈠锛岄伩鍏嶆瘡娆″垏鍥為兘閲嶆媺鏃堕棿杞翠笌宸插姞杞藉潡
      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
        const snap = GalleryHomeTimelineCache.tryTakeRestore(this.baseUrl, GalleryTimelineRefreshStore.version);
        if (snap !== null) {
          galleryAlbumApplyMainTimelineCacheSnapshot(this.asLoadOrchestratorHost(), snap);
          this.loadGen++;
          galleryAlbumRebuildFlow(this.asVisibleLoadHost());
          setTimeout((): void => {
            galleryAlbumPumpLoad(this.asLoadOrchestratorHost());
          }, 0);
          return;
        }
      }
      this.requestBootstrap(false);
    }, 0);
  }

  /** 鍒囧埌鍏朵粬搴曢儴 Tab 鏃跺嵏杞斤細鎶婁富鏃堕棿绾垮揩鐓у啓鍏ュ唴瀛橈紝渚涗笅娆?aboutToAppear 鎭㈠ */
  aboutToDisappear(): void {
    timelineGestureCancelListSettledTimer(this.asTimelineGestureHost());
    this.isDraggingOrFling = false;
    this.timelineReleaseAwaitVisibleCallback = false;
    this.invalidateNavigationGuard();
    this.pumpEpoch++;
    timelineGestureRefreshVisualPlaceholderMode(this.asTimelineGestureHost());
    gallerySetAlbumBackHandler(null);
    const snap = galleryAlbumBuildMainTimelineCacheSnapshot(this.asLoadOrchestratorHost());
    if (snap !== null) {
      GalleryHomeTimelineCache.save(this.baseUrl, snap);
    }
  }

  onPageShow(): void {
    galleryAlbumOnTabVisibleAgain(this.asLoadOrchestratorHost());
  }

  /** Map<string,number> 鈫?骞宠鏁扮粍锛屼究浜庡揩鐓ц劚绂诲紩鐢紙椤荤敤鍛藉悕鎺ュ彛锛屾弧瓒?arkts-no-obj-literals-as-types锛?*/
  private clearBootstrapDebounceTimer(): void {
    if (this.bootstrapDebounceTimer >= 0) {
      try {
        clearTimeout(this.bootstrapDebounceTimer);
      } catch (_e) {}
      this.bootstrapDebounceTimer = -1;
    }
  }

  /**
   * 璇锋眰閲嶆柊鎷夋椂闂磋酱骞堕噸寤哄垪琛ㄣ€?
   * @param debounced true锛氱敤鎴疯繛鐐广€屽埛鏂般€嶆椂鍚堝苟涓轰竴娆★紱false锛氶灞忋€佺埗绾?epoch銆佷笂浼犲悗绔嬪嵆鎵ц銆?
   */
  private requestBootstrap(debounced: boolean): void {
    this.clearBootstrapDebounceTimer();
    if (debounced) {
      this.bootstrapDebounceTimer = setTimeout((): void => {
        this.bootstrapDebounceTimer = -1;
        void galleryAlbumBootstrap(this.asLoadOrchestratorHost());
      }, GALLERY_BOOTSTRAP_DEBOUNCE_MS);
    } else {
      void galleryAlbumBootstrap(this.asLoadOrchestratorHost());
    }
  }

  /** Home 鍓嶅彴淇″彿鎴?Tab 鍐嶆鏄剧ず锛氬厛澧為噺鍒狅紝鍐嶈 bump 闃叉姈鍏ㄩ噺鍒?*/
  private enterGallerySelectionModeFromToolbar(): void {
    if (this.gallerySelectionMode) {
      return;
    }
    playGalleryEnterSelectionHaptic();
    this.setGallerySelectionModeState(true);
    this.galleryTimelineRefreshing = false;
    galleryAlbumSetGallerySelectedIdsState(this.asSelectionGestureHost(), []);
  }

  /**
   * 鏃堕棿绾垮尯鍩熶笅鎷夊埛鏂帮細浣跨敤绯荤粺 Refresh 鍔ㄦ晥锛涢潪鍒楄〃椤剁銆佸閫夋垨瀛愭ā寮忔椂涓嶅彂璧风綉缁滆姹傘€?
   */
  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
      GalleryAlbumTopBar({
        inSearchMode: this.inSearchMode,
        inCategoryMode: this.inCategoryMode,
        inSmartCategoryMode: this.inSmartCategoryMode,
        inPersonMode: this.inPersonMode,
        gallerySelectionMode: this.gallerySelectionMode,
        gallerySelectedCount: this.gallerySelectedIds.length,
        searchQuery: this.searchQuery,
        topSafeInsetVp: this.topSafeInsetVp,
        pageShowSignal: this.pageShowSignal,
        onSearchQueryChange: (value: string): void => {
          this.searchQuery = value;
        },
        onSearchSubmit: (): void => {
          void galleryAlbumRunSearch(this.asModeOrchestratorHost(), this.searchQuery);
        },
        onExitSelection: (): void => {
          galleryAlbumExitSelection(this.asSelectionGestureHost());
        },
        onEnterSelection: (): void => {
          this.enterGallerySelectionModeFromToolbar();
        },
        onBackToGallery: (): void => {
          galleryAlbumBackToMain(this.asModeOrchestratorHost());
        }
      })

      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
        GalleryAlbumEntryChips({
          hidden: this.gallerySelectionMode,
          onOpenMediaCategory: (): void => {
            galleryAlbumExitSelection(this.asSelectionGestureHost());
            galleryAlbumPlayModeSwitchMotion(this.asModeOrchestratorHost());
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/MediaCategoryPage',
              params: { baseUrl: this.baseUrl }
            }).catch((_e: Error): void => {
              this.toast('鎵撳紑濯掍綋鍒嗙被澶辫触');
            });
          },
          onOpenSmartCategory: (): void => {
            galleryAlbumExitSelection(this.asSelectionGestureHost());
            galleryAlbumPlayModeSwitchMotion(this.asModeOrchestratorHost());
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/SmartCategoryPage',
              params: { baseUrl: this.baseUrl }
            }).catch((_e: Error): void => {
              this.toast('鎵撳紑鏅鸿兘鍒嗙被澶辫触');
            });
          },
          onOpenPerson: (): void => {
            galleryAlbumExitSelection(this.asSelectionGestureHost());
            galleryAlbumPlayModeSwitchMotion(this.asModeOrchestratorHost());
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/PersonPage',
              params: { baseUrl: this.baseUrl }
            }).catch((_e: Error): void => {
              this.toast('打开人物页失败');
            });
          },
          onOpenRecent: (): void => {
            galleryAlbumExitSelection(this.asSelectionGestureHost());
            galleryAlbumPlayModeSwitchMotion(this.asModeOrchestratorHost());
            void this.openRecentAdded();
          },
          onOpenCollect: (): void => {
            galleryAlbumExitSelection(this.asSelectionGestureHost());
            galleryAlbumPlayModeSwitchMotion(this.asModeOrchestratorHost());
            void galleryAlbumOpenCollectGallery(this.asModeOrchestratorHost());
          },
          onOpenRecycleBin: (): void => {
            galleryAlbumExitSelection(this.asSelectionGestureHost());
            galleryAlbumPlayModeSwitchMotion(this.asModeOrchestratorHost());
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/RecycleBinPage',
              params: { baseUrl: this.baseUrl }
            }).catch((_e: Error): void => {
              this.toast('打开回收站失败');
            });
          }
        })
      }

      // 鈹€鈹€ 鎼滅储缁撴灉瑙嗗浘 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
      if (this.inSearchMode) {
        GalleryAlbumSearchModeView({
          baseUrl: this.baseUrl,
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

      if (this.inCategoryMode) {
        GalleryAlbumCategoryModeView({
          baseUrl: this.baseUrl,
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

      // 鈹€鈹€ 鍥惧簱瑙嗗浘 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
        GalleryAlbumMainModeView({
          baseUrl: this.baseUrl,
          bootLoading: this.bootLoading,
          loadError: this.loadError,
          footText: this.footText,
          galleryTimelineRefreshing: this.galleryTimelineRefreshing,
          gallerySelectionMode: this.gallerySelectionMode,
          gallerySelectedCount: this.gallerySelectedIds.length,
          gallerySelectedIds: this.gallerySelectedIds,
          galleryBatchDownloading: this.galleryBatchDownloading,
          galleryBatchDeleting: this.galleryBatchDeleting,
          galleryMainListScrollEnabled: this.galleryMainListScrollEnabled,
          gallerySlideGestureActive: this.gallerySlideGestureActive,
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
          pickGalleryThumbFlatForRowOrCache: (node: GalleryFlowNode, xPx: number, yPx: number): number =>
            selectionPickGalleryThumbFlatForRowOrCache(this.asSelectionGestureHost(), node, xPx, yPx),
          onGalleryThumbLongPress: (item: GalleryListItem): void =>
            selectionOnGalleryThumbLongPress(this.asSelectionGestureHost(), item),
          beginGallerySlideSelectGesture: (ev: GestureEvent, item: GalleryListItem, anchorFlat: number): void =>
            selectionBeginGallerySlideSelectGesture(this.asSelectionGestureHost(), ev, item, anchorFlat),
          onGallerySlidePanUpdate: (ev: GestureEvent): void =>
            selectionOnGallerySlidePanUpdate(this.asSelectionGestureHost(), ev),
          onListScrollIndex: (firstIdx: number, lastIdx: number, _centerIdx: number): void => {
            this.listVisibleFirstNodeIdx = firstIdx;
            this.listVisibleLastNodeIdx = Math.max(firstIdx, lastIdx);
            galleryAlbumVisibleRefreshLastKnownGlobalSlotsFromListIndices(
              this.asVisibleLoadHost(),
              this.listVisibleFirstNodeIdx,
              this.listVisibleLastNodeIdx
            );
            galleryAlbumVisibleCaptureListScrollIndexAnchor(this.asVisibleLoadHost());
            if (this.timelineReleaseAwaitVisibleCallback && !this.timelineSidebarDragging) {
              this.timelineReleaseAwaitVisibleCallback = false;
              galleryAlbumVisibleLoadVisibleItemsImmediate(this.asVisibleLoadHost());
            }
            if (this.timelineSidebarDragging || this.timelineSeekInProgress) {
              return;
            }
            timelineGestureSyncTimelineHandleFromListThrottled(
              this.asTimelineGestureHost(),
              firstIdx,
              (idx: number): void => {
                galleryAlbumSyncTimelineSliderFromFirstIndex(this.asTimelineGestureHost(), idx);
              }
            );
            timelineGestureTouchTimelineBarOnScroll(this.asTimelineGestureHost());
          },
          onListDidScroll: (_offset: number, _scrollState: ScrollState): void => {
            timelineGestureMaybeLogMainScrollTick(this.asTimelineGestureHost(), _offset, _scrollState);
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
                stateChanged = true;
              }
              if (!this.listKineticScrolling) {
                this.listKineticScrolling = true;
                stateChanged = true;
              }
              if (!this.timelineSidebarDragging) {
                refreshedVisibleRangeWhileInteracting =
                  galleryAlbumVisibleRefreshVisibleRangeIfAvailable(this.asVisibleLoadHost());
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
              if (this.visualPlaceholderMode) {
                this.visualPlaceholderMode = false;
                stateChanged = true;
              }
              if (this.timelineReleaseAwaitVisibleCallback) {
                this.timelineReleaseAwaitVisibleCallback = false;
                galleryAlbumVisibleLoadVisibleItemsImmediate(this.asVisibleLoadHost());
              }
              if (wasDraggingOrFling) {
                timelineGestureScheduleMainListSettledWork(this.asTimelineGestureHost());
              }
            }
            if (stateChanged) {
              timelineGestureRefreshVisualPlaceholderMode(this.asTimelineGestureHost());
            }
            if (refreshedVisibleRangeWhileInteracting) {
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
            this.timelineDragStartRatio = this.timelineSliderRatio;
            this.lastTimelineDragScrollMs = 0;
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
            const th = Math.max(64, this.timelineScrubTrackHeightVp);
            let ratio = this.timelineDragStartRatio + (event.offsetY / th);
            ratio = Math.max(0, Math.min(1, ratio));
            if (Math.abs(ratio - this.timelineSliderRatio) < 0.001) {
              return;
            }
            this.timelineSliderRatio = ratio;
            this.timelineSidebarHighlightIndex =
              Math.max(0, Math.min(ymList.length - 1, Math.round(ratio * (ymList.length - 1))));
            this.timelineIndicatorY = galleryAlbumTimelineIndicatorYForRatio(th, ratio);
            timelineGestureArmTimelineDragWatchdog(this.asTimelineGestureHost());
          },
          onTimelinePanEnd: (_event: GestureEvent): void => {
            this.endTimelineDrag();
          },
          onTimelinePanCancel: (_event: GestureEvent): void => {
            this.endTimelineDrag();
          }
        })
      }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

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

      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
        if (this.uploading) {
          FnFullLoadingMask({ text: this.uploadText.length > 0 ? this.uploadText : '上传中...' })
        }
        if (!this.gallerySelectionMode) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(24)
              .fontColor([Color.White])
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          }
          .width(GALLERY_HOME_UPLOAD_FAB_SIZE_VP)
          .height(GALLERY_HOME_UPLOAD_FAB_SIZE_VP)
          .backgroundColor($r('app.color.brand_primary'))
          .shadow({ radius: 16, color: '#33000000', offsetX: 0, offsetY: 6 })
          .margin({
            right: GALLERY_HOME_UPLOAD_FAB_MARGIN_RIGHT_VP,
            bottom: GALLERY_HOME_UPLOAD_FAB_MARGIN_BOTTOM_VP
          })
          .onClick((): void => {
            galleryAlbumStartUpload(this.asModeOrchestratorHost());
          })
        }
      }
    }
    .width('100%')
    .height('100%')
  }
}
