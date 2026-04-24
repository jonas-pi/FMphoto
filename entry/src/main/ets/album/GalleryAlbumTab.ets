/**
 * 鍘熺敓鐩稿唽 Tab锛堝榻?fnos_gallery_mobile.py 搂2~搂4锛?
 *
 * 鏁版嵁閾捐矾锛?
 *   timeline 鈫?鎸夋棩闄嶅簭 鈫?姣忔棩 getList 椤哄簭鍒嗛〉
 *   鍋忕Щ閲忕敱 dayNextOffsets锛堥潪鍝嶅簲寮?Map锛夊悓姝ョ淮鎶わ紝閬垮厤 @State 寤惰繜瀵艰嚧閲嶅璇锋眰
 *
 * 鍔犺浇绛栫暐锛氳嚜椹卞姩娉碉紙pumpLoad锛夛紝姣忔壒瀹屾垚鍚庤嚜鍔ㄨ皟搴︿笅涓€鎵癸紙绾︿竴甯ч棿闅欙紝閬垮厤鍚屽抚鍐呰繛缁姠娓叉煋锛夈€?
 *   涓嶄緷璧栨粴鍔ㄤ簨浠讹紝褰诲簳瑙勯伩 "Drag gesture has been canceled" 瀵艰嚧鐨勫姞杞藉仠婊炪€?
 *   onDidScroll 浠呬綔澶囦唤閲嶅惎瑙﹀彂锛堟车鍥犻敊璇殏鍋滄椂鐢辨粴鍔ㄩ噸鍚級銆?
 *
 * 缂╃暐鍥撅細List + LazyForEach锛涢壌鏉冧笅杞戒笌 LRU 瑙?GalleryAlbumCommon銆?
 *   row 鐨?LazyForEach key 椤婚殢妲戒綅 flat 鍙樺寲锛堣 galleryFlowLazyKey锛夛紝鍚﹀垯楠ㄦ灦鏇挎崲涓虹湡瀹為」鍚庡瓙鏍戝彲鑳戒笉澶嶇敤鍒锋柊銆?
 * 澶у浘棰勮锛氱嫭绔嬮〉闈?pages/GalleryPreview锛圫wiper 璺熸墜銆佽鑼冭浆鍦猴級銆?
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
  loadCollectGalleryItems as requestCollectGalleryItems,
  loadMediaCategories as requestMediaCategories,
  loadPersons as requestPersons,
  loadRecentAddedItems as requestRecentAddedItems,
  loadSmartCategories as requestSmartCategories,
} from './galleryAlbumTab/GalleryAlbumModeLoaders';
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
  galleryAlbumOpenRecentAdded,
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
  selectionIsGalleryIdSelected,
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

/**
 * 鎸夋棩鍖哄潡锛氫娇鐢?@Observed 浠ヤ究鍚屾棩澶氭壒杩藉姞 items 鏃跺瓙鏍戝閲忓埛鏂帮紝
 * 閬垮厤浠呴潬 ForEach key 鍚?items.length 瀵艰嚧鏁存 Column 鍙嶅閲嶆寕杞斤紙瑙ｇ爜/甯冨眬鎴愭湰楂樸€佷綋鎰熸參锛夈€? */
@Observed
class DaySectionModel {
  year: number = 0;
  month: number = 0;
  day: number = 0;
  itemCount: number = 0;
  /** 褰撴棩宸插姞杞界収鐗囷細key 涓烘棩鍐?offset锛?..itemCount-1锛夛紝鏀寔涔卞簭/鍒嗛〉濉厖锛屼笌鍏ㄩ噺楠ㄦ灦鏄犲皠涓€鑷?*/
  slotByOffset: Map<number, GalleryListItem> = new Map<number, GalleryListItem>();
  nextOffset: number = 0;
}

// 鈹€鈹€鈹€ 涓?Tab 缁勪欢 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

@Component
export struct GalleryAlbumTab {
  @Prop baseUrl: string = '';
  @Prop @Watch('onEpochChange') albumReloadEpoch: number = 0;
  /** Home.onPageShow() 閫掑 鈫?瑙﹀彂鍒犻櫎鍚屾锛堝畨鍏ㄤ繚闅滐紝涓嶄緷璧栧瓙缁勪欢 onPageShow 浼犳挱锛?*/
  @Prop @Watch('onPageShowSignal') pageShowSignal: number = 0;

  @State private bootLoading: boolean = false;
  @State private loadError: string = '';
  @State private footText: string = '';
  @State private sections: DaySectionModel[] = [];

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
  /** pump 浠ｆ锛氭柊婊氬姩寮€濮嬫椂閫掑锛屾棫 pump/鍥炶皟绔嬪嵆澶辨晥锛堟墦鏂苟鍙戦摼璺級 */
  private pumpEpoch: number = 0;
  /** 鏃堕棿杞存澗鎵嬪悗鐭獥鍐呭拷鐣ョ▼搴忓寲婊氬姩瀵瑰喕缁撴€佺殑鍥炲啓锛岄槻姝⑩€滃繀椤诲啀婊戜竴涓嬫墠鍔犺浇鈥?*/
  private ignoreListFreezeUntilMs: number = 0;
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

  private asSelectionGestureHost(): SelectionGestureControllerHost {
    const self = this;
    class SelectionGestureHostBridge implements SelectionGestureControllerHost {
      getUIContext() { return self.getUIContext(); }
      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(value: string) { self.baseUrl = value; }
      get inSearchMode(): boolean { return self.inSearchMode; }
      set inSearchMode(value: boolean) { self.inSearchMode = value; }
      get gallerySelectionMode(): boolean { return self.gallerySelectionMode; }
      set gallerySelectionMode(value: boolean) { self.gallerySelectionMode = value; }
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
      set gallerySelectedIds(value: string[]) { self.gallerySelectedIds = value; }
      itemIdOf(item: GalleryListItem): string { return self.itemIdOf(item); }
      flatItems(): GalleryListItem[] { return self.flatItems(); }
      galleryThumbDomId(photoId: string): string { return self.galleryThumbDomId(photoId); }
      recordGalleryThumbRectFromDom(photoId: string, domId: string): void {
        self.recordGalleryThumbRectFromDom(photoId, domId);
      }
      setGallerySelectedIdsState(ids: string[]): void { self.setGallerySelectedIdsState(ids); }
      toast(msg: string): void { self.toast(msg); }
      openPreview(flatIndex: number): void { self.openPreview(flatIndex); }
      resolveGalleryFlatIndexForOpenPreview(item: GalleryListItem, hintFlat: number): number {
        return self.resolveGalleryFlatIndexForOpenPreview(item, hintFlat);
      }
    }
    return new SelectionGestureHostBridge();
  }

  private asTimelineGestureHost(): TimelineGestureControllerHost {
    const self = this;
    class TimelineGestureHostBridge implements TimelineGestureControllerHost {
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
      get ignoreListFreezeUntilMs(): number { return self.ignoreListFreezeUntilMs; }
      set ignoreListFreezeUntilMs(value: number) { self.ignoreListFreezeUntilMs = value; }
      get pumpEpoch(): number { return self.pumpEpoch; }
      set pumpEpoch(value: number) { self.pumpEpoch = value; }
      resolveYearMonthByTimelineRatio(ratio: number): TimelineYearMonthPair | null {
        return self.resolveYearMonthByTimelineRatio(ratio);
      }
      flowHasVisibleYearMonth(year: number, month: number): boolean {
        return self.flowHasVisibleYearMonth(year, month);
      }
      startTimelineSeekWatchdog(year: number, month: number): void {
        self.startTimelineSeekWatchdog(year, month);
      }
      seekTimelineListToDisplayRatio(ratio: number): void { self.seekTimelineListToDisplayRatio(ratio); }
      syncGalleryTimelineAtTopForPull(): void { self.syncGalleryTimelineAtTopForPull(); }
      clearGalleryThumbHitBounds(): void { self.clearGalleryThumbHitBounds(); }
      flushPendingFlowRebuild(): void { self.flushPendingFlowRebuild(); }
      loadVisibleItemsThrottled(forceImmediate?: boolean, aggressive?: boolean): void {
        self.loadVisibleItemsThrottled(forceImmediate, aggressive);
      }
      loadVisibleItemsImmediate(): void { self.loadVisibleItemsImmediate(); }
      syncListVisibleRoughToTimelineSliderTarget(): void { self.syncListVisibleRoughToTimelineSliderTarget(); }
      pumpLoad(singleBatch?: boolean): void { self.pumpLoad(singleBatch); }
      runMainListScrollSettledWork(epochAtSchedule?: number): void {
        self.runMainListScrollSettledWork(epochAtSchedule);
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
      exitGallerySelection(): void { self.exitGallerySelection(); }
      requestBootstrap(forceImmediate: boolean): void { self.requestBootstrap(forceImmediate); }
      bootstrap(showFullBleedSkeleton?: boolean): Promise<void> { return self.bootstrap(showFullBleedSkeleton); }
      itemIdOf(item: GalleryListItem): string { return self.itemIdOf(item); }
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
      set gallerySelectionMode(value: boolean) { self.gallerySelectionMode = value; }
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
      applyDeleteSyncIfNeeded(): void { self.applyDeleteSyncIfNeeded(); }
      enrichPersonStats(items: AiPersonItem[], gen: number): Promise<void> { return self.enrichPersonStats(items, gen); }
      rebuildFlow(): void { self.rebuildFlow(); }
      countGalleryListedItems(): number { return self.countGalleryListedItems(); }
      upsertSection(day: TimelineDayModel, list: GalleryListItem[], newOffset: number): void {
        self.upsertSection(day, list, newOffset);
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
      get timelineSliderRatio(): number { return self.timelineSliderRatio; }
      set timelineSliderRatio(value: number) { self.timelineSliderRatio = value; }
      resolveDayByGlobalIndex(globalIndex: number): DayGlobalResolveResult | null {
        return self.resolveDayByGlobalIndex(globalIndex);
      }
      resolveYearMonthByTimelineRatio(ratio: number): TimelineYearMonthPair | null {
        return self.resolveYearMonthByTimelineRatio(ratio);
      }
      isInScrollInteractiveLogWindow(): boolean { return self.isInScrollInteractiveLogWindow(); }
      logScrollDebug(msg: string): void { self.logScrollDebug(msg); }
      rebuildFlow(): void { self.rebuildFlow(); }
      pumpLoad(singleBatch?: boolean): void { self.pumpLoad(singleBatch); }
      loadOneBatch(): Promise<number> { return self.loadOneBatch(); }
    }
    return new VisibleLoadHostBridge();
  }

  // 鈹€鈹€ 鎵佸钩鍒楄〃锛堜緵璺宠浆鐙珛棰勮椤碉級 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  private flatItems(): GalleryListItem[] {
    const out: GalleryListItem[] = [];
    const secByDay = new Map<string, DaySectionModel>();
    for (let i = 0; i < this.sections.length; i++) {
      const s = this.sections[i];
      secByDay.set(dayKey(s.year, s.month, s.day), s);
    }
    if (this.orderedDays.length > 0) {
      for (let di = 0; di < this.orderedDays.length; di++) {
        const d = this.orderedDays[di];
        const sec = secByDay.get(dayKey(d.year, d.month, d.day));
        if (sec === undefined) {
          continue;
        }
        const cnt = Math.max(0, d.itemCount);
        for (let off = 0; off < cnt; off++) {
          const it = sec.slotByOffset.get(off);
          if (it !== undefined) {
            out.push(it);
          }
        }
      }
      return out;
    }
    for (let i = 0; i < this.sections.length; i++) {
      const sec = this.sections[i];
      const keys = Array.from(sec.slotByOffset.keys()).sort((a: number, b: number): number => a - b);
      for (let j = 0; j < keys.length; j++) {
        const it = sec.slotByOffset.get(keys[j]);
        if (it !== undefined) {
          out.push(it);
        }
      }
    }
    return out;
  }

  /**
   * 鐢辨椂闂磋酱 + 宸插姞杞?section 閲嶅缓 List 鑺傜偣锛?
   * 1) 浼樺厛鎸?orderedDays锛堝畬鏁存椂闂磋酱锛夐摵鍑哄畬鏁存棩缁撴瀯涓庨鏋惰锛岀‘淇濇€婚珮搴︿粠涓€寮€濮嬪氨姝ｇ‘锛?
   * 2) 瀵瑰凡鍔犺浇鐨勫尯娈碉紝鐢ㄧ湡瀹炲浘鐗囪鐩栧搴旈鏋舵Ы浣嶏紱
   * 3) 鏈姞杞介儴鍒嗙户缁繚鐣?skeleton锛屽崰浣嶄絾涓嶈Е鍙戠綉缁滆姹傘€?
   *
   * 杩欐牱鎷栧埌搴曟椂涓嶄細鍑虹幇鈥滅湅璧锋潵鍒板簳浣嗗疄闄呬笂鍙槸宸插姞杞藉埌搴曗€濈殑闂銆?
   */
  private rebuildFlow(): void {
    if (this.timelineSidebarDragging || this.isDraggingOrFling) {
      this.pendingFlowRebuild = true;
      return;
    }
    const nodes: GalleryFlowNode[] = [];
    // day -> section 绱㈠紩锛孫(1) 鍛戒腑宸插姞杞芥暟鎹?
    const secMap = new Map<string, DaySectionModel>();
    for (let i = 0; i < this.sections.length; i++) {
      const s = this.sections[i];
      secMap.set(dayKey(s.year, s.month, s.day), s);
    }

    // 鎵佸钩绱㈠紩浠呯粺璁♀€滅湡瀹炲凡鍔犺浇鍥剧墖鈥濓紙棰勮/澶氶€変粛鍙綔鐢ㄤ簬鐪熷疄鍥撅級
    let flatLoaded = 0;

    // 鏈夊畬鏁存椂闂磋酱鏃朵紭鍏堜娇鐢ㄥ畠鏋勫缓鍏ㄩ噺楠ㄦ灦锛涘惁鍒欓€€鍖栦负鏃ц涓猴紙浠?sections锛?
    if (this.orderedDays.length > 0) {
      for (let i = 0; i < this.orderedDays.length; i++) {
        const day = this.orderedDays[i];
        const prevDay = i > 0 ? this.orderedDays[i - 1] : undefined;
        const showMonth = prevDay === undefined || ymKey(day.year, day.month) !== ymKey(prevDay.year, prevDay.month);
        if (showMonth) {
          const mn = new GalleryFlowNode();
          mn.kind = 'month';
          mn.key = `m_${day.year}_${day.month}_od_${i}`;
          mn.year = day.year;
          mn.month = day.month;
          nodes.push(mn);
        }

        const dn = new GalleryFlowNode();
        dn.kind = 'day';
        dn.key = `d_${day.year}_${day.month}_${day.day}_od_${i}`;
        dn.year = day.year;
        dn.month = day.month;
        dn.day = day.day;
        nodes.push(dn);

        const sec = secMap.get(dayKey(day.year, day.month, day.day));
        const totalCount = Math.max(0, day.itemCount);
        const totalRows = Math.ceil(totalCount / 3);

        for (let row = 0; row < totalRows; row++) {
          const rn = new GalleryFlowNode();
          rn.kind = 'row';
          rn.key = `r_${day.year}_${day.month}_${day.day}_row_${row}`;

          const rowStart = row * 3;
          const totalInRow = Math.min(3, Math.max(0, totalCount - rowStart));
          for (let k = 0; k < totalInRow; k++) {
            const localOff = rowStart + k;
            const it = sec !== undefined ? sec.slotByOffset.get(localOff) : undefined;
            if (it !== undefined) {
              rn.rowSlotItems.push(it);
              rn.rowSlotFlatIndices.push(flatLoaded);
              flatLoaded++;
            } else {
              rn.rowSlotItems.push(null);
              rn.rowSlotFlatIndices.push(-1);
            }
          }
          nodes.push(rn);
        }
      }
    } else {
      // 鍏滃簳锛氭棤鏃堕棿杞存椂鎸夊凡鍔犺浇 section 鏋勫缓锛堟棫琛屼负锛?
      for (let i = 0; i < this.sections.length; i++) {
        const sec = this.sections[i];
        const prev = i > 0 ? this.sections[i - 1] : undefined;
        const showMonth = prev === undefined || ymKey(sec.year, sec.month) !== ymKey(prev.year, prev.month);
        if (showMonth) {
          const mn = new GalleryFlowNode();
          mn.kind = 'month';
          mn.key = `m_${sec.year}_${sec.month}_i${i}`;
          mn.year = sec.year;
          mn.month = sec.month;
          nodes.push(mn);
        }
        const dn = new GalleryFlowNode();
        dn.kind = 'day';
        dn.key = `d_${sec.year}_${sec.month}_${sec.day}`;
        dn.year = sec.year;
        dn.month = sec.month;
        dn.day = sec.day;
        nodes.push(dn);

        const keys = Array.from(sec.slotByOffset.keys()).sort((a: number, b: number): number => a - b);
        if (keys.length === 0) {
          continue;
        }
        const maxOff = keys[keys.length - 1];
        const totalCount = Math.max(maxOff + 1, sec.itemCount > 0 ? sec.itemCount : keys.length);
        const totalRows = Math.ceil(totalCount / 3);
        for (let row = 0; row < totalRows; row++) {
          const rn = new GalleryFlowNode();
          rn.kind = 'row';
          rn.key = `r_${sec.year}_${sec.month}_${sec.day}_row_${row}`;
          const rowStart = row * 3;
          const totalInRow = Math.min(3, Math.max(0, totalCount - rowStart));
          for (let k = 0; k < totalInRow; k++) {
            const localOff = rowStart + k;
            const it = sec.slotByOffset.get(localOff);
            if (it !== undefined) {
              rn.rowSlotItems.push(it);
              rn.rowSlotFlatIndices.push(flatLoaded);
              flatLoaded++;
            } else {
              rn.rowSlotItems.push(null);
              rn.rowSlotFlatIndices.push(-1);
            }
          }
          nodes.push(rn);
        }
      }
    }
    this.listScrollIndexAnchorHave = false;
    this.flowDataSource.reloadAll(nodes);
  }

  /**
   * rebuild / flush 鍚?LazyForEach 鐨?onScrollIndex 甯镐粛婊炲悗銆?
   * 浼樺厛浣跨敤 Scroller.getVisibleRange锛堣嫢瀛樺湪锛夛紱鍚﹀垯**浠呯敤 1vp 寰皟**瑙﹀彂妗嗘灦鍥炰紶 onScrollIndex銆?
   * 涓嶅啀鐢?y/鍥哄畾 vp 鍙嶆帹鑺傜偣涓嬫爣锛氬叏閲忛鏋朵笅琛岄珮涓庛€岃妭鐐广€嶉潪绾挎€у搴旓紝鏄撴妸 loadVisible 閿氬埌灞忓銆?
   */
  private tryApplyScrollerVisibleRangeIfAvailable(total: number): boolean {
    return galleryAlbumVisibleTryApplyScrollerVisibleRangeIfAvailable(this.asVisibleLoadHost(), total);
  }

  /** 鏃?getVisibleRange 鏃讹細杞诲井婊氬姩浠ヨЕ鍙?onScrollIndex锛岄伩鍏嶇敤閿欒 offset 鍙嶆帹瑕嗙洊 listVisible* */
  private nudgeListScrollForScrollIndexRefresh(): void {
    galleryAlbumVisibleNudgeListScrollForScrollIndexRefresh(this.asVisibleLoadHost());
  }

  private forceRefreshVisibleRange(): void {
    galleryAlbumVisibleForceRefreshVisibleRange(this.asVisibleLoadHost());
  }

  private flushPendingFlowRebuild(): void {
    galleryAlbumVisibleFlushPendingFlowRebuild(this.asVisibleLoadHost());
  }

  /** 鏍规嵁浜や簰鐘舵€佺粺涓€璁＄畻鍗犱綅妯″紡寮€鍏筹紙鍞竴鍑哄彛锛岄伩鍏嶅鐘舵€佽鐩栵級 */
  private refreshVisualPlaceholderMode(): void {
    timelineGestureRefreshVisualPlaceholderMode(this.asTimelineGestureHost());
  }

  private touchTimelineBarOnScroll(): void {
    timelineGestureTouchTimelineBarOnScroll(this.asTimelineGestureHost());
  }

  private syncTimelineHandleFromListThrottled(firstIdx: number): void {
    timelineGestureSyncTimelineHandleFromListThrottled(this.asTimelineGestureHost(), firstIdx, (idx: number): void => {
      this.syncTimelineSliderFromFirstIndex(idx);
    });
  }

  private scrollStateText(state: ScrollState): string {
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

  private logScrollDebug(msg: string): void {
    timelineGestureLogScrollDebug(this.asTimelineGestureHost(), msg);
  }

  private isInScrollInteractiveLogWindow(): boolean {
    return timelineGestureIsInScrollInteractiveLogWindow(this.asTimelineGestureHost());
  }

  private cancelTimelineDragWatchdog(): void {
    timelineGestureCancelTimelineDragWatchdog(this.asTimelineGestureHost());
  }

  private armTimelineDragWatchdog(): void {
    timelineGestureArmTimelineDragWatchdog(this.asTimelineGestureHost());
  }

  private maybeLogMainScrollTick(offset: number, state: ScrollState): void {
    timelineGestureMaybeLogMainScrollTick(this.asTimelineGestureHost(), offset, state);
  }

  private cancelListSettledTimer(invalidateGen: boolean = true): void {
    timelineGestureCancelListSettledTimer(this.asTimelineGestureHost(), invalidateGen);
  }

  private scheduleMainListSettledWork(): void {
    timelineGestureScheduleMainListSettledWork(this.asTimelineGestureHost());
  }

  /**
   * 涓诲垪琛ㄦ粴鍔ㄥ凡缁撴潫涓斾笉鍐嶅崰浣嶅悗锛氬悓姝ラ《閮ㄦ椂闂磋酱銆佹仮澶嶆粴鍔ㄦ潯銆佹竻鐞嗗懡涓紦瀛樸€佽Е鍙戞车鍔犺浇銆?
   * 鐢?onDidScroll 涓?Idle 闃叉姈瀹氭椂鍣ㄥ叡鐢紝閬垮厤婕忚皟 pump銆?
   */
  private runMainListScrollSettledWork(epochAtSchedule: number = -1): void {
    timelineGestureRunMainListScrollSettledWork(this.asTimelineGestureHost(), epochAtSchedule);
  }

  /** 瀹屾暣灞曞紑 scrub锛氭嫋鍔ㄦ椂闂磋酱鎴栭暱鎸夌粏杞?*/
  private timelineScrubExpandedChrome(): boolean {
    return timelineGestureTimelineScrubExpandedChrome(this.asTimelineGestureHost());
  }

  /** 浠呭垪琛ㄦ粴鍔ㄨЕ鍙戠殑銆岀粏杞ㄣ€嶆彁绀猴紝涓嶅崰婊′氦浜掓牱寮?*/
  private timelineScrubScrollRailOnly(): boolean {
    return timelineGestureTimelineScrubScrollRailOnly(this.asTimelineGestureHost());
  }

  /** 鏄剧ず鏃堕棿杞村苟閲嶇疆鑷姩闅愯棌鍊掕鏃讹紙鎵嬫寚鍦ㄨ建閬撲笂鏃朵笉鍚姩鍊掕鏃讹級 */
  private showTimelineBar(): void {
    timelineGestureShowTimelineBar(this.asTimelineGestureHost());
  }

  /** 鑾峰彇鏃堕棿杞村勾鏈堝垪琛紙瀹屾暣鏃堕棿杞翠紭鍏堬細orderedDays锛?*/
  private getTimelineYearMonths(): TimelineYearMonth[] {
    return collectTimelineYearMonths(this.orderedDays, this.sections);
    // 鍏滃簳锛氳嫢 orderedDays 灏氭湭鍙敤锛岄€€鍖栦负 sections
  }

  /** 姣斾緥 -> 骞存湀锛?=鏈€鏂帮紝1=鏈€鏃╋級 */
  private resolveYearMonthByTimelineRatio(ratio: number): TimelineYearMonthPair | null {
    return resolveTimelineYearMonthByRatio(this.getTimelineYearMonths(), ratio);
  }

  /**
   * 涓嶄緷璧?List 鍙鍖虹储寮曪細鎸夊綋鍓嶆椂闂磋酱婊戝潡姣斾緥瀵归綈 pump 璧风偣銆?
   * 瑙ｅ喅銆屾澗鎵嬪悗鏈Е鍙?onScrollIndex锛寁isStart==visEnd 瀵艰嚧姘歌繙涓?pump銆嶇殑闂銆?
   *
   * 娉ㄦ剰锛氬悓涓€鑷劧鏈堝搴?**澶氭潯** orderedDays锛堟寜鏃ラ檷搴忥級锛屾棫瀹炵幇鍙彇鍛戒腑绗竴鏉＄殑妲戒綅鍖洪棿锛?
   * lastKnownGlobal 浠呰鐩栥€屼竴澶┿€嶏紝鍚屽睆鍏跺畠鏃ヤ細闀挎湡楠ㄦ灦涓嶆媺鍙栵紱鍚戜笂婊戞椂甯歌〃鐜颁负鍥哄畾涓€鏉°€屾甯︺€嶃€?
   */
  private alignPumpToTimelineSliderTarget(): boolean {
    return galleryAlbumVisibleAlignPumpToTimelineSliderTarget(this.asVisibleLoadHost());
  }

  /** 褰撳墠 flow 涓槸鍚﹀凡鏈夋寚瀹氬勾鏈堣妭鐐?*/
  private flowHasVisibleYearMonth(year: number, month: number): boolean {
    return hasFlowVisibleYearMonth(this.flowDataSource, year, month);
  }

  /** 鎸囧畾骞存湀宸插彲瑙佹椂鎵ц绮剧‘璺宠浆 */
  private tryScrollListToYearMonthIfVisible(year: number, month: number): boolean {
    const idx = findFlowScrollIndexForYearMonth(this.flowDataSource, year, month);
    if (idx < 0) {
      return false;
    }
    try {
      this.scrollerRef.scrollToIndex(idx, false, ScrollAlign.START);
      return true;
    } catch (_e) {
      return false;
    }
  }

  /**
   * 鏃堕棿杞存澗鎵嬪悗锛氱▼搴忓寲 scrollToIndex 瀹屾垚鍓?onScrollIndex / Scroller.yOffset 甯镐粛鍋滃湪鏃х姸鎬侊紝
   * loadVisible 浼氳瀵瑰噯銆屼笂涓€灞忋€嶏紱鎸夋粦鍧楃洰鏍囧勾鏈堝湪 flow 涓畾浣嶉涓?row锛堝惁鍒欐湀/鏃ュご锛夛紝寮鸿鍒锋柊 listVisible*銆?
   */
  private syncListVisibleRoughToTimelineSliderTarget(): void {
    const ym = this.resolveYearMonthByTimelineRatio(this.timelineSliderRatio);
    if (ym === null) {
      return;
    }
    const range = findFlowRoughVisibleRangeForYearMonth(this.flowDataSource, ym.year, ym.month);
    if (range === null) {
      return;
    }
    this.listVisibleFirstNodeIdx = range.first;
    this.listVisibleLastNodeIdx = range.last;
    this.refreshLastKnownGlobalSlotsFromListIndices(range.first, range.last);
    this.captureListScrollIndexAnchor();
  }

  /** 鎸夋瘮渚嬩及绠楁粴鍔紙鐢ㄤ簬鎷栧姩涓窡鎵嬪弽棣堬級 */
  private scrollListByRatioEstimate(ratio: number): void {
    const total = this.flowDataSource.totalCount();
    if (total <= 0) {
      return;
    }
    const clamped = Math.max(0, Math.min(1, ratio));
    if (clamped >= 0.995) {
      try {
        this.scrollerRef.scrollToIndex(total - 1, false, ScrollAlign.END);
      } catch (_e) {}
      return;
    }
    const estimatedTotalVp = total * 120;
    const y = Math.max(0, clamped * estimatedTotalVp);
    try {
      this.scrollerRef.scrollTo({ xOffset: 0, yOffset: y });
    } catch (_e) {}
  }

  /** 鏉炬墜鍚庢寜鐩爣姣斾緥瀵归綈锛堝彲瑙佸垯绮剧‘锛屼笉鍙鍏堜及绠楋級 */
  private seekTimelineListToDisplayRatio(ratio: number): void {
    // 绋嬪簭鍖栬烦杞細鐬棿鏀瑰彉 yOffset锛屼笌鏃?onScrollIndex 閿氱偣涓嶅彲姣旓紝閬垮厤 loadVisible 鐢ㄩ敊澧為噺
    this.listScrollIndexAnchorHave = false;
    const ym = this.resolveYearMonthByTimelineRatio(ratio);
    if (ym === null) {
      return;
    }
    if (this.tryScrollListToYearMonthIfVisible(ym.year, ym.month)) {
      return;
    }
    this.scrollListByRatioEstimate(ratio);
  }

  /** 鑳屾櫙鐩戣锛氱洰鏍囨湀鍑虹幇鍚庡啀绮剧‘ scrollToIndex锛岀‘淇濇嫋鍒板簳鑳藉埌鏈€鏃╂棩鏈?*/
  private startTimelineSeekWatchdog(targetYear: number, targetMonth: number): void {
    this.timelineSeekGen++;
    const gen = this.timelineSeekGen;
    const started = Date.now();
    const tick = (): void => {
      if (gen !== this.timelineSeekGen) {
        return;
      }
      if (Date.now() - started > 60_000) {
        return;
      }
      if (this.flowHasVisibleYearMonth(targetYear, targetMonth)) {
        this.tryScrollListToYearMonthIfVisible(targetYear, targetMonth);
        return;
      }
      if (!this.loadingMore && !this.exhausted) {
        this.pumpLoad();
      }
      if (this.exhausted) {
        return;
      }
      setTimeout(tick, 250);
    };
    setTimeout(tick, 250);
  }

  /** 鐢?firstVisibleIndex 绮剧‘鍚屾鏃堕棿杞达紙閬垮厤楂樺害浼扮畻璇樊瀵艰嚧鏍囩鍥為《锛?*/
  private syncTimelineSliderFromFirstIndex(firstIdx: number): void {
    const sync = resolveTimelineSliderSyncResult(
      this.flowDataSource,
      this.getTimelineYearMonths(),
      firstIdx,
      this.timelineScrubTrackHeightVp,
      this.timelineSliderRatio,
      this.timelineSidebarHighlightIndex
    );
    if (sync === null) {
      return;
    }
    this.timelineSliderRatio = sync.ratio;
    this.timelineSidebarHighlightIndex = sync.highlightIndex;
    this.timelineIndicatorY = sync.indicatorY;
    // 寰皬鍙樺寲涓嶆洿鏂?@State锛屽噺灏戞墜鏌勫眰缁嗙閲嶇粯
  }

  private getCurrentHighlightYear(): number {
    return getTimelineHighlightYear(
      this.getTimelineYearMonths(),
      this.timelineSidebarHighlightIndex,
      new Date().getFullYear()
    );
  }

  private getCurrentHighlightMonth(): number {
    return getTimelineHighlightMonth(
      this.getTimelineYearMonths(),
      this.timelineSidebarHighlightIndex,
      new Date().getMonth() + 1
    );
  }

  /** 涓庡垪琛ㄩ敋鐐瑰榻愮殑銆屾棩銆嶏細浠庡綋鍓嶅彲瑙侀鑺傜偣鍚戝墠鎵炬渶杩戠殑 day/row 鑺傜偣 */
  private getCurrentHighlightDay(): number {
    return getTimelineHighlightDay(
      this.flowDataSource,
      this.listVisibleFirstNodeIdx,
      new Date().getDate()
    );
  }

  /** 鏃堕棿杞村睍寮€姘旀场锛氬畬鏁村勾鏈堟棩锛堜笉璁?maxWidth锛岄伩鍏嶈鎴垚銆?鈥︺€嶏級 */
  private getTimelineScrubPillLabel(): string {
    return `${this.getCurrentHighlightYear()}年${this.getCurrentHighlightMonth()}月${this.getCurrentHighlightDay()}日`;
  }

  private getYearMarkersForTrack(): YearMarker[] {
    const ymList = this.getTimelineYearMonths();
    if (ymList.length === 0 || this.timelineScrubTrackHeightVp <= 0) {
      return [];
    }
    const out: YearMarker[] = [];
    const seen = new Set<number>();
    let lastY = -999;
    const th = this.timelineScrubTrackHeightVp;
    for (let i = 0; i < ymList.length; i++) {
      const year = ymList[i].year;
      if (seen.has(year)) {
        continue;
      }
      seen.add(year);
      const ratio = ymList.length > 1 ? i / (ymList.length - 1) : 0;
      const y = this.timelineIndicatorYForRatio(th, ratio);
      if (y - lastY >= 22) {
        out.push({ year, y });
        lastY = y;
      }
    }
    return out;
  }

  /** 涓?buildTimelineSidebar 鍐呮粦鍧?姘旀场绾靛悜浣嶇疆涓€鑷达紝闅忚建閬撻珮搴︾缉鏀?*/
  private timelineIndicatorYForRatio(thRaw: number, ratio: number): number {
    return calcTimelineIndicatorYForRatio(thRaw, ratio);
  }

  /** 璁＄畻鏌愬ぉ鏌?offset 鍦ㄢ€滃叏閲忔椂闂磋酱鐓х墖搴忓垪鈥濅腑鐨勫叏灞€涓嬫爣 */
  private calculateGlobalIndex(day: TimelineDayModel, offsetInDay: number): number {
    let acc = 0;
    for (let i = 0; i < this.orderedDays.length; i++) {
      const d = this.orderedDays[i];
      if (d.year === day.year && d.month === day.month && d.day === day.day) {
        return acc + Math.max(0, offsetInDay);
      }
      acc += Math.max(0, d.itemCount);
    }
    return acc + Math.max(0, offsetInDay);
  }

  /** 鏍规嵁鍏ㄥ眬鐓х墖涓嬫爣鍙嶆煡鎵€灞炲ぉ涓庡ぉ鍐?offset */
  private resolveDayByGlobalIndex(globalIndex: number): DayGlobalResolveResult | null {
    if (this.orderedDays.length === 0) {
      return null;
    }
    const g = Math.max(0, globalIndex);
    let acc = 0;
    for (let i = 0; i < this.orderedDays.length; i++) {
      const cnt = Math.max(0, this.orderedDays[i].itemCount);
      if (g < acc + cnt) {
        const hit: DayGlobalResolveResult = { dayIdx: i, dayOffset: g - acc };
        return hit;
      }
      acc += cnt;
    }
    const last = this.orderedDays.length - 1;
    const tail: DayGlobalResolveResult = {
      dayIdx: last,
      dayOffset: Math.max(0, this.orderedDays[last].itemCount - 1)
    };
    return tail;
  }

  /** 缁熻鍦?nodeIdx 涔嬪墠鍏辨湁澶氬皯鈥滅収鐗囨Ы浣嶁€濓紙鐪熷疄 + skeleton锛?*/
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
    timelineGestureEndTimelineDrag(this.asTimelineGestureHost());
  }


  private openPreview(flatIndex: number): void {
    if (flatIndex < 0) {
      return;
    }
    GalleryPreviewNavStore.openPreview(this.baseUrl, this.flatItems(), flatIndex);
  }

  /** 浠ユ潯鐩?id 瀵归綈 flatItems 椤哄簭锛岄伩鍏?rowSlotFlatIndices 涓?flatItems 鐭殏涓嶄竴鑷存椂銆岀缉鐣ュ浘涓庨瑙堜笉鏄悓涓€寮犮€?*/
  private resolveGalleryFlatIndexForOpenPreview(item: GalleryListItem, hintFlat: number): number {
    const id = this.itemIdOf(item);
    const items = this.flatItems();
    if (id.length > 0) {
      for (let i = 0; i < items.length; i++) {
        if (this.itemIdOf(items[i]) === id) {
          return i;
        }
      }
    }
    if (items.length <= 0) {
      return hintFlat >= 0 ? hintFlat : 0;
    }
    if (hintFlat >= 0 && hintFlat < items.length) {
      return hintFlat;
    }
    return Math.max(0, Math.min(items.length - 1, hintFlat));
  }

  private itemIdOf(it: GalleryListItem): string {
    if (it.id === undefined || it.id === null) {
      return '';
    }
    return String(it.id).trim();
  }

  /**
   * 涓绘椂闂寸嚎 List + LazyForEach 鐨?item key銆?
   * row 蹇呴』鎶娿€屾Ы浣嶆槸鍚﹀凡鏈?flat / 鐪熷疄椤广€嶇紪杩?key锛氫粎 `rebuildFlow` 鏇挎崲 `rowSlotItems` 鏃惰嫢 `node.key` 涓嶅彉锛?
   * 妗嗘灦浼氬鐢ㄥ瓙鏍戣€屼笉閲嶈窇 item 鏋勫缓锛岄鏋舵牸涓嶄細鎹㈡垚 GalleryNetworkThumb锛岃〃鐜颁负鍙湁婊戝姩鍚庢墠銆屽姞杞姐€嶃€?
   */
  private galleryFlowLazyKey(node: GalleryFlowNode): string {
    if (node.kind !== 'row') {
      return node.key;
    }
    const fi = node.rowSlotFlatIndices;
    let slotSig = '';
    for (let i = 0; i < fi.length; i++) {
      if (i > 0) {
        slotSig += 'x';
      }
      slotSig += `${fi[i]}`;
    }
    return `${node.key}_s${slotSig}`;
  }

  private exitGallerySelection(): void {
    this.gallerySelectionMode = false;
    this.galleryTimelineRefreshing = false;
    this.setGallerySelectedIdsState([]);
    this.gallerySlideGestureActive = false;
    this.gallerySlideHasRef = false;
    this.gallerySlideAnchorFlat = -1;
    this.gallerySlideUnionBase = [];
    this.gallerySlideLastEndFlat = -1;
    this.gallerySlideLastAppliedEndFlat = -99999;
    this.galleryThumbHitBounds.clear();
    this.searchThumbHitBounds.clear();
    this.galleryMainListScrollEnabled = true;
  }

  /**
   * 鍒ゆ柇涓ょ粍 id 鏄惁浣滀负闆嗗悎鐩稿悓锛堥『搴忔棤鍏筹級锛岄伩鍏嶅垝閫夊悎骞舵椂浠呴『搴忓彉鍖栦篃瑙﹀彂鏁磋〃鍒锋柊銆?
   * 浣跨敤 Set 璁℃暟锛岄伩鍏嶅ぇ鍥鹃€夊尯涓?O(n log n) 鎺掑簭銆?
   */
  private sameGalleryIdBagUnordered(a: string[], b: string[]): boolean {
    if (a.length !== b.length) {
      return false;
    }
    if (a.length === 0) {
      return true;
    }
    const cnt = new Map<string, number>();
    for (let i = 0; i < a.length; i++) {
      const k = a[i];
      cnt.set(k, (cnt.get(k) ?? 0) + 1);
    }
    for (let i = 0; i < b.length; i++) {
      const k = b[i];
      const c = (cnt.get(k) ?? 0) - 1;
      if (c < 0) {
        return false;
      }
      cnt.set(k, c);
    }
    let allZero = true;
    cnt.forEach((v: number): void => {
      if (v !== 0) {
        allZero = false;
      }
    });
    return allZero;
  }

  /**
   * 缁熶竴鍐欏叆閫変腑 id 鍒楄〃骞剁淮鎶?Set锛涢泦鍚堜笌褰撳墠鐩稿悓鏃惰烦杩囪祴鍊硷紝鍑忓皯鏃犳晥 @State 鍒锋柊銆?
   */
  private setGallerySelectedIdsState(next: string[]): void {
    if (this.sameGalleryIdBagUnordered(this.gallerySelectedIds, next)) {
      return;
    }
    this.gallerySelectedIds = next;
  }

  /** 鍒楄〃婊氬姩鍚庢竻绌哄懡涓煩褰紝閬垮厤绂诲睆椤规畫鐣欐棫鍧愭爣瀵艰嚧璇€?*/
  private clearGalleryThumbHitBounds(): void {
    this.galleryThumbHitBounds.clear();
  }

  /**
   * 鐢熸垚 getRectangleById / id() 鍙敤鐨?DOM 鏍囪瘑锛堜粎瀛楁瘝鏁板瓧涓庝笅鍒掔嚎锛岄伩鍏嶉潪娉?id锛夈€?
   */
  private galleryThumbDomId(photoId: string): string {
    let s = '';
    for (let i = 0; i < photoId.length; i++) {
      const c = photoId.charCodeAt(i);
      if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95) {
        s += String.fromCharCode(c);
      } else {
        s += '_';
      }
    }
    return `gt_${s.length > 0 ? s : 'noid'}`;
  }

  /**
   * 鍦ㄥ竷灞€鍙樺寲鍚庡埛鏂拌缂╃暐鍥惧湪绐楀彛涓殑鐭╁舰锛屼緵銆岄暱鎸夊悗婊戝姩銆嶈繛閫夊仛鐩镐氦鍒ゆ柇銆?
   * 浼樺厛浣跨敤瀹樻柟 componentUtils.getRectangleById锛堜笌鎸囧皷 window 鍧愭爣涓€鑷达級銆?
   */
  private recordGalleryThumbRectFromDom(photoId: string, domId: string): void {
    if (photoId.length === 0) {
      return;
    }
    try {
      const info = this.getUIContext().getComponentUtils().getRectangleById(domId);
      const x = info.windowOffset.x as number;
      const y = info.windowOffset.y as number;
      const w = info.size.width as number;
      const h = info.size.height as number;
      if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
        this.galleryThumbHitBounds.delete(photoId);
        return;
      }
      const rect: GalleryThumbHitRect = {
        left: x,
        top: y,
        right: x + w,
        bottom: y + h
      };
      this.galleryThumbHitBounds.set(photoId, rect);
    } catch (_e) {
      // 棰勮鍣ㄦ垨鏈寕杞藉畬鎴愭椂鍙兘鎶涢敊锛岃繛閫夐檷绾т负浠呬緷璧栭暱鎸夎捣鐐?
    }
  }

  /**
   * 浠庢墜鍔夸簨浠惰鍙栨寚灏栦綅缃紙涓嶅悓鐗堟湰瀛楁鍚嶄笉鍚岋級銆?
   * 鏁板€煎崟浣嶅涓?vp锛堥€昏緫鍍忕礌锛夛紝闇€涓?getRectangleById 杩斿洖鐨?px 鍦?resolveSlidePointerWindowPx 涓粺涓€銆?
   */
  private readGestureFingerWindow(ev: GestureEvent): GalleryFingerWindowPoint | null {
    return selectionReadGestureFingerWindow(this.asSelectionGestureHost(), ev);
  }

  /**
   * PanGesture.offsetX/Y 涓?vp锛沢etRectangleById 涓?px銆傚皢浣嶇Щ浠?vp 鎹㈢畻鍒?px锛屼笌鍛戒腑鐭╁舰涓€鑷淬€?
   */
  private panOffsetVpToPx(deltaVp: number): number {
    return selectionPanOffsetVpToPx(this.asSelectionGestureHost(), deltaVp);
  }

  /**
   * 闀挎寜鍒ゅ畾鎴愬姛鍚庯細杩涘叆鍒掗€夋锛屽叧闂?List 婊氬姩锛岃褰曢敋鐐?flat 涓庡凡鏈夐€変腑闆嗭紝渚涖€岃浼樺厛杩炵画鍖洪棿銆嶅疄鏃跺苟闆嗐€?
   */
  private beginGallerySlideSelectGesture(ev: GestureEvent, item: GalleryListItem, anchorFlat: number): void {
    selectionBeginGallerySlideSelectGesture(this.asSelectionGestureHost(), ev, item, anchorFlat);
  }

  /** 鍒掗€夋缁撴潫锛氭仮澶?List 婊氬姩銆佹竻绌哄垝閫変复鏃剁姸鎬侊紝鍏佽 onDidScroll 鍐嶆娓呯┖鍛戒腑缂撳瓨 */
  private endGallerySlideSelectGesture(): void {
    selectionEndGallerySlideSelectGesture(this.asSelectionGestureHost());
  }

  /**
   * 灏嗗綋鍓嶅垝閫夋寚閽堢粺涓€鍒扮獥鍙ｅ儚绱犲潗鏍囷紝涓?getRectangleById 涓€鑷淬€?
   */
  private resolveSlidePointerWindowPx(ev: GestureEvent): GalleryFingerWindowPoint | null {
    return selectionResolveSlidePointerWindowPx(this.asSelectionGestureHost(), ev);
  }

  /**
   * 鐢?getRectangleById 鍒ゆ柇鐐规槸鍚﹁惤鍦ㄥ崟寮犵缉鐣ュ浘鍐咃紙浠呴檺鏈灏戦噺璋冪敤锛岀姝㈠湪鍏ㄥ垪琛?Pan 姣忓抚閲屾壂锛夈€?
   */
  private hitGalleryThumbDomPx(photoId: string, xPx: number, yPx: number): boolean {
    return selectionHitGalleryThumbDomPx(this.asSelectionGestureHost(), photoId, xPx, yPx);
  }

  /**
   * 鏍规嵁鎸囧皷绐楀彛鍧愭爣鍛戒腑缂╃暐鍥?flat锛涗粎浣跨敤 onAreaChange 鍐欏叆鐨?galleryThumbHitBounds銆?
   * 鍒掗€?Pan 鐨勮繛缁洿鏂拌鐢?pickGalleryThumbFlatUnderPointForSlide锛堢紦瀛樿娓呯┖鍚庝粛浼?DOM 鍥為€€锛夈€?
   * 鑷悗鍚戝墠鎵?row锛屼笌鍚庣粯鍒剁殑鏍煎湪涓婂眰涓€鑷淬€?
   */
  private pickGalleryThumbFlatUnderPoint(xPx: number, yPx: number): number {
    return selectionPickGalleryThumbFlatUnderPoint(this.asSelectionGestureHost(), xPx, yPx);
  }

  /**
   * 鍒掗€?Pan 鍛戒腑锛氬厛缂撳瓨锛涚己澶辨椂鍦ㄩ敋鐐?缁堢偣闄勮繎鐨勫皯閲忚鍐呭仛 DOM锛堟瘡甯ч绠楋級锛岄伩鍏嶅叏琛?getRectangleById 鍗℃涓荤嚎绋嬨€?
   */
  private pickGalleryThumbFlatUnderPointForSlide(xPx: number, yPx: number): number {
    return selectionPickGalleryThumbFlatUnderPointForSlide(this.asSelectionGestureHost(), xPx, yPx);
  }

  private pickSearchThumbFlatUnderPointForSlide(xPx: number, yPx: number): number {
    return selectionPickSearchThumbFlatUnderPoint(this.asSelectionGestureHost(), xPx, yPx);
  }

  /**
   * 闀挎寜 / Pan 璧风偣锛氬厛璧板叏灞€缂撳瓨鍛戒腑锛屽け璐ュ垯鍙**褰撳墠琛?*鏈€澶?3 鏍煎仛 getRectangleById锛堟仮澶嶃€岄暱鎸夊惎鍔ㄥ閫?+ 鍒掗€夈€嶄笖涓嶆妸 DOM 鏌ヨ鏀捐繘 Pan 姣忓抚锛夈€?
   */
  private pickGalleryThumbFlatForRowOrCache(node: GalleryFlowNode, xPx: number, yPx: number): number {
    return selectionPickGalleryThumbFlatForRowOrCache(this.asSelectionGestureHost(), node, xPx, yPx);
  }

  /**
   * 鏀堕泦鎵佸钩涓嬫爣闂尯闂?[lo, hi]锛堣浼樺厛锛夊唴鎵€鏈夌缉鐣ュ浘 id銆?
   * 鐩存帴鎸?sections 鎺ㄨ繘 flat锛岃烦杩囨暣娈垫棭浜?lo 鐨勬棩锛岃秴杩?hi 鍗冲仠锛岄伩鍏嶆瘡娆℃壂鍏?flow銆?
   */
  private collectGalleryIdsInFlatRange(lo: number, hi: number): string[] {
    let a = lo;
    let b = hi;
    if (a > b) {
      const t = a;
      a = b;
      b = t;
    }
    const out: string[] = [];
    const all = this.flatItems();
    if (all.length === 0) {
      return out;
    }
    const lo2 = Math.max(0, a);
    const hi2 = Math.min(b, all.length - 1);
    if (lo2 > hi2) {
      return out;
    }
    for (let fi = lo2; fi <= hi2; fi++) {
      const id = this.itemIdOf(all[fi]);
      if (id.length > 0) {
        out.push(id);
      }
    }
    return out;
  }

  private searchThumbDomId(flatIdx: number): string {
    return selectionSearchThumbDomId(this.asSelectionGestureHost(), flatIdx);
  }

  private recordSearchThumbRect(flatIdx: number): void {
    selectionRecordSearchThumbRect(this.asSelectionGestureHost(), flatIdx);
  }

  private hitSearchThumbDomPx(flatIdx: number, xPx: number, yPx: number): boolean {
    return selectionHitSearchThumbDomPx(this.asSelectionGestureHost(), flatIdx, xPx, yPx);
  }

  private pickSearchThumbFlatUnderPoint(xPx: number, yPx: number): number {
    return selectionPickSearchThumbFlatUnderPoint(this.asSelectionGestureHost(), xPx, yPx);
  }

  private pickSearchThumbFlatForRow(rowStart: number, xPx: number, yPx: number): number {
    return selectionPickSearchThumbFlatForRow(this.asSelectionGestureHost(), rowStart, xPx, yPx);
  }

  private collectSearchIdsInFlatRange(lo: number, hi: number): string[] {
    let a = lo;
    let b = hi;
    if (a > b) {
      const t = a;
      a = b;
      b = t;
    }
    const out: string[] = [];
    const n = this.searchResults.length;
    for (let fi = a; fi <= b && fi < n; fi++) {
      const id = this.itemIdOf(this.searchResults[fi]);
      if (id.length > 0) {
        out.push(id);
      }
    }
    return out;
  }

  /**
   * 浠ヨ涓哄熀鏁扮殑鍒掗€夛細閫変腑闆?= 杩涘叆鍒掗€夊墠宸叉湁閫変腑 鈭?閿氱偣 flat锝炵粓鐐?flat 鐨勮繛缁尯闂达紙鍚腑闂存暣琛岋級銆?
   * 缁堢偣鐢辨寚灏栦笅閭ｅ紶缂╃暐鍥惧喅瀹氾紱鎸囧皷绂诲紑鏍煎瓙鏃舵部鐢?gallerySlideLastEndFlat锛岄伩鍏嶉棯鐑併€?
   */
  private applyGallerySlideRowRangeSelection(endFlat: number): void {
    selectionApplyGallerySlideRowRangeSelection(this.asSelectionGestureHost(), endFlat);
  }

  /**
   * Parallel 涓?Pan 鍙兘鍦ㄩ暱鎸夎Е鍙戝墠灏辨敹鍒?update锛屽繀椤荤瓑 begin 鍚庡啀澶勭悊銆?
   * 瀹炴椂鍐欏叆 gallerySelectedIds锛屾寜銆岃浼樺厛 flat 杩炵画鍖洪棿銆嶆墿閫夈€?
   */
  private onGallerySlidePanUpdate(ev: GestureEvent): void {
    selectionOnGallerySlidePanUpdate(this.asSelectionGestureHost(), ev);
  }

  /**
   * 鏄惁宸查€夛紙渚?UI 缁戝畾锛夈€?
   * 蹇呴』鐩存帴璇?@State gallerySelectedIds锛屼笉鍙粎鐢ㄦ櫘閫氬瓧娈?Set 鍒ゆ柇锛屽惁鍒?ArkUI 鏃犳硶寤虹珛渚濊禆锛?
   * 浼氬嚭鐜伴《鏍忋€屽凡閫夋嫨 x 寮犮€嶅彉鍖栬€岀缉鐣ュ浘鍕?閬僵涓嶉噸缁樼殑闂銆?
   */
  private isGalleryIdSelected(id: string): boolean {
    return selectionIsGalleryIdSelected(this.asSelectionGestureHost(), id);
  }

  private toggleGallerySelectedId(id: string): void {
    selectionToggleGallerySelectedId(this.asSelectionGestureHost(), id);
  }

  /** 闀挎寜杩涘叆澶氶€?鍦ㄥ閫変笅鍒囨崲褰撳墠椤癸紱鍒掗€夎繘琛屼腑蹇界暐锛岄伩鍏嶄笌 Pan 鎶㈤€昏緫 */
  private onGalleryThumbLongPress(item: GalleryListItem): void {
    selectionOnGalleryThumbLongPress(this.asSelectionGestureHost(), item);
  }

  private onGalleryThumbTap(item: GalleryListItem, flatIndex: number): void {
    selectionOnGalleryThumbTap(this.asSelectionGestureHost(), item, flatIndex);
  }

  private onSearchThumbTap(item: GalleryListItem, flatIndex: number): void {
    selectionOnSearchThumbTap(this.asSelectionGestureHost(), item, flatIndex);
  }

  /** 鎵归噺绉诲叆鍥炴敹绔欙細閫愭潯璋冪敤鐜版湁 API锛屾垚鍔熷悗 bump 鏃堕棿杞村苟闃叉姈鍒锋柊 */
  private async confirmAndBatchDeleteGallery(): Promise<void> {
    if (this.gallerySelectedIds.length === 0 || this.galleryBatchDeleting) {
      return;
    }
    try {
      const dlg = await this.getUIContext().getPromptAction().showDialog({
        title: '批量移入回收站',
        message: '将所选照片/视频移入回收站？',
        buttons: [
          { text: '取消', color: '#99000000' },
          { text: '移入回收站', color: '#E5484D' }
        ]
      });
      if (dlg.index !== 1) {
        return;
      }
    } catch (_e) {
      return;
    }
    const client = AppSession.getClient();
    if (client === null) {
      this.toast('未登录');
      return;
    }
    this.galleryBatchDeleting = true;
    const ids = this.gallerySelectedIds.slice();
    let ok = 0;
    try {
      for (let i = 0; i < ids.length; i++) {
        const res = await client.addPhotoToRecycleBin(ids[i], 22000);
        if (res.success) {
          ok++;
          GalleryDeleteSyncStore.markDeleted(ids[i]);
        }
      }
    } finally {
      this.galleryBatchDeleting = false;
    }
    GalleryTimelineRefreshStore.bump();
    this.exitGallerySelection();
    this.toast(`已移入回收站 ${ok}/${ids.length}`);
    this.requestBootstrap(true);
  }

  private async askBatchDownloadImageQuality(): Promise<'original' | 'thumb' | 'cancel'> {
    try {
      const choice = await this.getUIContext().getPromptAction().showActionMenu({
        title: '批量下载图片',
        buttons: [
          { text: '原图（体积较大）', color: '#007AFF' },
          { text: '缩略图（更快）', color: '#007AFF' }
        ]
      });
      if (choice.index < 0) {
        return 'cancel';
      }
      return choice.index === 0 ? 'original' : 'thumb';
    } catch (_e) {
      return 'cancel';
    }
  }

  private async confirmAndBatchDownloadGallery(): Promise<void> {
    if (this.gallerySelectedIds.length === 0 || this.galleryBatchDownloading) {
      return;
    }
    const list = this.inSearchMode ? this.searchResults : this.flatItems();
    const items = galleryItemsMatchingSelectedIds(list, this.gallerySelectedIds);
    if (items.length === 0) {
      this.toast('没有可下载的项');
      return;
    }
    this.galleryBatchDownloading = true;
    try {
      await runBatchDownloadGalleryItems(
        this.baseUrl,
        items,
        (msg: string): void => {
          this.toast(msg);
        },
        (): Promise<'original' | 'thumb' | 'cancel'> => this.askBatchDownloadImageQuality()
      );
    } finally {
      this.galleryBatchDownloading = false;
    }
  }

  /**
   * 澶勭悊棰勮椤靛垹闄ゅ悓姝ワ細澧為噺鍒犺锛涜嫢鍚屾椂瀛樺湪 GalleryTimelineRefreshStore bump锛?
   * 鐢?onAlbumTabVisibleAgain 鍐嶈Е鍙戦槻鎶栧悗鐨勫叏閲?bootstrap锛屼笌鏃堕棿杞村榻愩€?
   */
  private applyDeleteSyncIfNeeded(): void {
    if (this.handledDeleteSyncVersion === GalleryDeleteSyncStore.version) {
      return;
    }
    const ids = GalleryDeleteSyncStore.snapshotIds();
    if (ids.length === 0) {
      this.handledDeleteSyncVersion = GalleryDeleteSyncStore.version;
      return;
    }
    // 涓诲垪琛ㄦ暟鎹皻鏈畬鎴?bootstrap 鏃讹紝涓嶆彁鍓嶆秷璐瑰垹闄ょ増鏈彿銆?
    if (this.sections.length === 0 && this.searchResults.length === 0) {
      return;
    }
    let changed = false;
    // 涓诲浘搴?sections锛氬垹闄ゅ懡涓殑鏉＄洰锛屽苟娓呯悊绌?section
    for (let si = this.sections.length - 1; si >= 0; si--) {
      const sec = this.sections[si];
      const keys = Array.from(sec.slotByOffset.keys());
      for (let j = 0; j < keys.length; j++) {
        const off = keys[j];
        const it = sec.slotByOffset.get(off);
        if (it === undefined) {
          continue;
        }
        const id = this.itemIdOf(it);
        if (id.length > 0 && ids.indexOf(id) >= 0) {
          sec.slotByOffset.delete(off);
          changed = true;
        }
      }
      if (sec.slotByOffset.size === 0) {
        this.sections.splice(si, 1);
      }
    }
    // 鎼滅储缁撴灉瑙嗗浘锛堣嫢褰撳墠鍦ㄦ悳绱㈡ā寮忥級涔熷悓姝ュ垹闄?
    if (this.searchResults.length > 0) {
      const searchKept: GalleryListItem[] = [];
      for (let i = 0; i < this.searchResults.length; i++) {
        const id = this.itemIdOf(this.searchResults[i]);
        if (id.length > 0 && ids.indexOf(id) >= 0) {
          changed = true;
          continue;
        }
        searchKept.push(this.searchResults[i]);
      }
      if (searchKept.length !== this.searchResults.length) {
        this.searchResults = searchKept;
      }
    }
    if (changed) {
      this.rebuildFlow();
    }
    this.handledDeleteSyncVersion = GalleryDeleteSyncStore.version;
  }

  // 鈹€鈹€ 鎼滅储 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  /** 鎵ц AI 璇箟鎼滅储骞跺睍绀虹粨鏋?*/
  private async runSearch(keyword: string): Promise<void> {
    await galleryAlbumRunSearch(this.asModeOrchestratorHost(), keyword);
  }

  /** 娓呴櫎鎼滅储锛屽洖鍒板浘搴撹鍥?*/
  private clearSearch(): void {
    galleryAlbumClearSearch(this.asModeOrchestratorHost());
  }

  private clearCategory(): void {
    galleryAlbumClearCategory(this.asModeOrchestratorHost());
  }

  private clearSmartCategory(): void {
    galleryAlbumClearSmartCategory(this.asModeOrchestratorHost());
  }

  private clearPerson(): void {
    galleryAlbumClearPerson(this.asModeOrchestratorHost());
  }

  private backToGallery(): void {
    galleryAlbumBackToMain(this.asModeOrchestratorHost());
  }

  /** 绯荤粺杩斿洖閿細瀛愯鍥惧唴鍏堥€€鍥炲浘搴撲富鐣岄潰 */
  private tryConsumeAlbumHardwareBack(): boolean {
    return galleryAlbumTryConsumeHardwareBack(this.asModeOrchestratorHost());
  }

  /** 缁熶竴妯″紡鍒囨崲鍔ㄦ晥锛屽噺灏戠‖鍒囨劅 */
  private playModeSwitchMotion(): void {
    galleryAlbumPlayModeSwitchMotion(this.asModeOrchestratorHost());
  }

  private startUpload(): void {
    galleryAlbumStartUpload(this.asModeOrchestratorHost());
  }

  private async pickAndUpload(): Promise<void> {
    await galleryAlbumPickAndUpload(this.asModeOrchestratorHost());
  }

  private async loadMediaCategories(): Promise<void> {
    await galleryAlbumLoadMediaCategories(this.asModeOrchestratorHost());
  }

  private async loadSmartCategories(): Promise<void> {
    await galleryAlbumLoadSmartCategories(this.asModeOrchestratorHost());
  }

  private async enrichPersonStats(items: AiPersonItem[], gen: number): Promise<void> {
    await galleryAlbumEnrichPersonStats(this.asModeOrchestratorHost(), items, gen);
  }

  private async loadPersons(): Promise<void> {
    await galleryAlbumLoadPersons(this.asModeOrchestratorHost());
  }

  /** 鎵撳紑浜虹墿鍥惧簱锛氫笌 PersonPage / 棰勮璇︽儏浜虹墿琛屽叡鐢?PersonAlbumOpenHelper */
  private async openPerson(item: AiPersonItem): Promise<void> {
    await galleryAlbumOpenPerson(this.asModeOrchestratorHost(), item);
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {
    }
  }

  private async openCategory(cat: MediaCategoryItem): Promise<void> {
    await galleryAlbumOpenCategory(this.asModeOrchestratorHost(), cat);
  }

  /**
   * 鏈€杩戞坊鍔狅細鎸?explore/recent_timeline 鍒嗘《鍚庨€愭棩鍒嗛〉鎷?recent_photos锛?
   * 鑱氬悎涓哄钩閾哄垪琛ㄥ苟澶嶇敤 CategoryGallery 棰勮椤垫墦寮€銆?
   */
  private async openRecentAdded(): Promise<void> {
    await galleryAlbumOpenRecentAdded(this.asModeOrchestratorHost());
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
    this.onAlbumTabVisibleAgain();
  }

  aboutToAppear(): void {
    // 椤甸潰閲嶆柊鍑虹幇鏃堕噸缃墦寮€鎬侊紝閬垮厤鎵嬪娍杩斿洖鍚庤鏃ч伄缃╃姸鎬佸崱浣?
    this.personOpening = false;
    this.categoryOpening = false;
    this.recentOpening = false;
    this.collectOpening = false;
    gallerySetAlbumBackHandler((): boolean => this.tryConsumeAlbumHardwareBack());
    setTimeout((): void => {
      // 涓绘椂闂寸嚎锛氳嫢绂诲紑 Tab 鏃跺瓨杩囧揩鐓т笖鏈熼棿鏈?bump/鏈己鍒凤紝鐩存帴鎭㈠锛岄伩鍏嶆瘡娆″垏鍥為兘閲嶆媺鏃堕棿杞翠笌宸插姞杞藉潡
      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
        const snap = GalleryHomeTimelineCache.tryTakeRestore(this.baseUrl, GalleryTimelineRefreshStore.version);
        if (snap !== null) {
          this.applyMainTimelineCacheSnapshot(snap);
          this.loadGen++;
          this.rebuildFlow();
          setTimeout((): void => {
            this.pumpLoad();
          }, 0);
          return;
        }
      }
      this.requestBootstrap(false);
    }, 0);
  }

  /** 鍒囧埌鍏朵粬搴曢儴 Tab 鏃跺嵏杞斤細鎶婁富鏃堕棿绾垮揩鐓у啓鍏ュ唴瀛橈紝渚涗笅娆?aboutToAppear 鎭㈠ */
  aboutToDisappear(): void {
    this.cancelListSettledTimer();
    this.isDraggingOrFling = false;
    this.pumpEpoch++;
    this.refreshVisualPlaceholderMode();
    gallerySetAlbumBackHandler(null);
    const snap = this.buildMainTimelineCacheSnapshot();
    if (snap !== null) {
      GalleryHomeTimelineCache.save(this.baseUrl, snap);
    }
  }

  onPageShow(): void {
    this.onAlbumTabVisibleAgain();
  }

  /** Map<string,number> 鈫?骞宠鏁扮粍锛屼究浜庡揩鐓ц劚绂诲紩鐢紙椤荤敤鍛藉悕鎺ュ彛锛屾弧瓒?arkts-no-obj-literals-as-types锛?*/
  private mapStringNumToArrays(m: Map<string, number>): GalleryHomeStringNumMapArrays {
    const keys: string[] = [];
    const vals: number[] = [];
    m.forEach((v: number, k: string): void => {
      keys.push(k);
      vals.push(v);
    });
    const out: GalleryHomeStringNumMapArrays = { keys: keys, vals: vals };
    return out;
  }

  private fillMapFromArrays(m: Map<string, number>, keys: string[], vals: number[]): void {
    m.clear();
    for (let i = 0; i < keys.length; i++) {
      if (i < vals.length) {
        m.set(keys[i], vals[i]);
      }
    }
  }

  /**
   * 鏋勯€犲彲缂撳瓨鐨勪富鏃堕棿绾垮揩鐓э紙浠呬富瑙嗗浘锛涗笉鍚悳绱?鍒嗙被/浜虹墿绛夊瓙妯″紡锛夈€?
   * 銆屾椂闂磋酱鏆傛棤鏁版嵁銆嶄篃缂撳瓨锛岄伩鍏嶇┖缁撹鍙嶅鎵撴帴鍙ｃ€?
   */
  private buildMainTimelineCacheSnapshot(): GalleryHomeTimelineSnapshot | null {
    if (this.inSearchMode || this.inCategoryMode || this.inSmartCategoryMode || this.inPersonMode) {
      return null;
    }
    if (this.bootLoading) {
      return null;
    }
    if (this.loadError.length > 0 && this.sections.length === 0) {
      return null;
    }
    const emptyNoFoot =
      this.orderedDays.length === 0 && this.sections.length === 0 && this.footText !== '时间轴暂无数据';
    if (emptyNoFoot) {
      return null;
    }
    const sectionsPlain: GalleryHomeSectionPlain[] = [];
    for (let i = 0; i < this.sections.length; i++) {
      const s = this.sections[i];
      const offs: number[] = [];
      const imgs: GalleryListItem[] = [];
      const keys = Array.from(s.slotByOffset.keys()).sort((a: number, b: number): number => a - b);
      for (let j = 0; j < keys.length; j++) {
        const k = keys[j];
        const v = s.slotByOffset.get(k);
        if (v !== undefined) {
          offs.push(k);
          imgs.push(v);
        }
      }
      sectionsPlain.push({
        year: s.year,
        month: s.month,
        day: s.day,
        itemCount: s.itemCount,
        nextOffset: s.nextOffset,
        slotOffsets: offs,
        slotItems: imgs
      });
    }
    const orderedPlain: GalleryHomeDayPlain[] = [];
    for (let i = 0; i < this.orderedDays.length; i++) {
      const d = this.orderedDays[i];
      orderedPlain.push({ year: d.year, month: d.month, day: d.day, itemCount: d.itemCount });
    }
    const off = this.mapStringNumToArrays(this.dayOffsets);
    const rnd = this.mapStringNumToArrays(this.dayRounds);
    const emp = this.mapStringNumToArrays(this.dayEmptyRounds);
    const snapshot: GalleryHomeTimelineSnapshot = {
      orderedDays: orderedPlain,
      sections: sectionsPlain,
      dayOffsetsKeys: off.keys,
      dayOffsetsVals: off.vals,
      dayRoundsKeys: rnd.keys,
      dayRoundsVals: rnd.vals,
      dayEmptyKeys: emp.keys,
      dayEmptyVals: emp.vals,
      dayIndex: this.dayIndex,
      exhausted: this.exhausted,
      footText: this.footText,
      refreshVersionAtSave: GalleryTimelineRefreshStore.version
    };
    return snapshot;
  }

  /** 浠庡唴瀛樺揩鐓ф仮澶嶄富鏃堕棿绾夸笌娉电姸鎬侊紙椤诲凡鐢?tryTakeRestore 鏍￠獙鐗堟湰涓庤处鍙凤級 */
  private applyMainTimelineCacheSnapshot(snap: GalleryHomeTimelineSnapshot): void {
    const od: TimelineDayModel[] = [];
    for (let i = 0; i < snap.orderedDays.length; i++) {
      const d = snap.orderedDays[i];
      od.push({ year: d.year, month: d.month, day: d.day, itemCount: d.itemCount });
    }
    this.orderedDays = od;
    const secs: DaySectionModel[] = [];
    for (let i = 0; i < snap.sections.length; i++) {
      const p = snap.sections[i];
      const sec = new DaySectionModel();
      sec.year = p.year;
      sec.month = p.month;
      sec.day = p.day;
      sec.itemCount = p.itemCount;
      sec.nextOffset = p.nextOffset;
      sec.slotByOffset.clear();
      if (p.slotOffsets !== undefined && p.slotItems !== undefined && p.slotOffsets.length === p.slotItems.length) {
        for (let j = 0; j < p.slotOffsets.length; j++) {
          sec.slotByOffset.set(p.slotOffsets[j], p.slotItems[j]);
        }
      } else if (p.items !== undefined) {
        for (let j = 0; j < p.items.length; j++) {
          sec.slotByOffset.set(j, p.items[j]);
        }
      }
      secs.push(sec);
    }
    this.sections = secs;
    this.fillMapFromArrays(this.dayOffsets, snap.dayOffsetsKeys, snap.dayOffsetsVals);
    this.fillMapFromArrays(this.dayRounds, snap.dayRoundsKeys, snap.dayRoundsVals);
    this.fillMapFromArrays(this.dayEmptyRounds, snap.dayEmptyKeys, snap.dayEmptyVals);
    this.dayIndex = snap.dayIndex;
    this.exhausted = snap.exhausted;
    this.footText = snap.footText;
    this.loadError = '';
    this.bootLoading = false;
    this.loadingMore = false;
    this.lastBootstrapSatisfiedRefreshVersion = snap.refreshVersionAtSave;
  }

  // 鈹€鈹€ sections 鏇存柊 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

  /** 宸插啓鍏?sections 鐨勫獟浣撴€绘暟锛岀敤浜庡尯鍒嗐€岀湡路鍏ㄩ儴鍔犺浇瀹屻€嶄笌銆岀珵鎬?鎺ュ彛寮傚父瀵艰嚧闆舵潯銆?*/
  private countGalleryListedItems(): number {
    let n = 0;
    for (let i = 0; i < this.sections.length; i++) {
      n += this.sections[i].slotByOffset.size;
    }
    return n;
  }

  private upsertSection(day: TimelineDayModel, newItems: GalleryListItem[], newOffset: number): void {
    const idx = this.sections.findIndex(
      (s: DaySectionModel): boolean =>
        s.year === day.year && s.month === day.month && s.day === day.day
    );
    const startOff = newOffset - newItems.length;
    if (idx < 0) {
      const sec = new DaySectionModel();
      sec.year = day.year;
      sec.month = day.month;
      sec.day = day.day;
      sec.itemCount = day.itemCount;
      for (let i = 0; i < newItems.length; i++) {
        sec.slotByOffset.set(startOff + i, newItems[i]);
      }
      sec.nextOffset = newOffset;
      this.sections = this.sections.concat([sec]);
    } else {
      const sec = this.sections[idx];
      sec.itemCount = day.itemCount;
      for (let i = 0; i < newItems.length; i++) {
        sec.slotByOffset.set(startOff + i, newItems[i]);
      }
      sec.nextOffset = newOffset;
    }
    this.rebuildFlow();
  }

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
        void this.bootstrap();
      }, GALLERY_BOOTSTRAP_DEBOUNCE_MS);
    } else {
      void this.bootstrap();
    }
  }

  /** Home 鍓嶅彴淇″彿鎴?Tab 鍐嶆鏄剧ず锛氬厛澧為噺鍒狅紝鍐嶈 bump 闃叉姈鍏ㄩ噺鍒?*/
  private onAlbumTabVisibleAgain(): void {
    galleryAlbumOnTabVisibleAgain(this.asLoadOrchestratorHost());
  }

  /** 涓嶆敼鍙樺瓙妯″紡 UI锛屼粎閲嶆媺濯掍綋鍒嗙被鐡风爾锛堥瑙堝垹闄よ棰戝悗鏇存柊銆岃棰戙€嶇瓑鏁伴噺锛?*/
  private async refreshMediaCategoriesInPlace(): Promise<void> {
    await galleryAlbumRefreshMediaCategoriesInPlace(this.asLoadOrchestratorHost());
  }

  private async refreshSmartCategoriesInPlace(): Promise<void> {
    await galleryAlbumRefreshSmartCategoriesInPlace(this.asLoadOrchestratorHost());
  }

  private async refreshPersonListInPlace(): Promise<void> {
    await galleryAlbumRefreshPersonListInPlace(this.asLoadOrchestratorHost());
  }

  private markTimelineRefreshCaughtUp(): void {
    galleryAlbumMarkTimelineRefreshCaughtUp(this.asLoadOrchestratorHost());
  }

  /**
   * 鏍规嵁 Scroller 鍨傜洿鍋忕Щ鍒ゆ柇鏄惁澶勪簬鍒楄〃椤剁锛岀敤浜庝笅鎷夊埛鏂伴棬绂侊紙浠呴《绔墠鍏佽鐪熸鎷夊彇鏃堕棿杞达級銆?
   */
  private syncGalleryTimelineAtTopForPull(): void {
    galleryAlbumSyncTimelineAtTopForPull(this.asLoadOrchestratorHost());
  }

  /** 椤舵爮澶氶€夋寜閽細杩涘叆澶氶€夛紙浠?0 椤瑰紑濮嬶紝涓庨暱鎸夐寮犺繘鍏ヤ竴鑷寸殑鍙墿灞曡涓猴級 */
  private enterGallerySelectionModeFromToolbar(): void {
    if (this.gallerySelectionMode) {
      return;
    }
    playGalleryEnterSelectionHaptic();
    this.gallerySelectionMode = true;
    this.galleryTimelineRefreshing = false;
    this.setGallerySelectedIdsState([]);
  }

  /**
   * 鏃堕棿绾垮尯鍩熶笅鎷夊埛鏂帮細浣跨敤绯荤粺 Refresh 鍔ㄦ晥锛涢潪鍒楄〃椤剁銆佸閫夋垨瀛愭ā寮忔椂涓嶅彂璧风綉缁滆姹傘€?
   */
  private async onGalleryTimelinePullRefresh(): Promise<void> {
    await galleryAlbumOnTimelinePullRefresh(this.asLoadOrchestratorHost());
  }

  // 鈹€鈹€ 鏁版嵁鍔犺浇 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
  /**
   * 鍏ㄩ噺閲嶅缓鏃堕棿绾夸笌鍒楄〃銆?
   * @param showFullBleedSkeleton true锛氶灞?寮哄埛鏃堕摵婊￠鏋讹紱false锛氫笅鎷夊埛鏂扮瓑鍦烘櫙淇濈暀鍒楄〃鍖哄煙锛屼粎鐢?Refresh 瀹樻柟鍔ㄦ晥銆?
   */
  private async bootstrap(showFullBleedSkeleton: boolean = true): Promise<void> {
    await galleryAlbumBootstrap(this.asLoadOrchestratorHost(), showFullBleedSkeleton);
  }

  /**
   * 鑷┍鍔ㄦ壒閲忓姞杞芥车锛坰elf-pumping锛夈€?
   *
   * 鍘熺悊锛氭瘡鎵瑰畬鎴愬悗鑷姩鍦ㄧ煭鏆傛殏鍋滃悗缁х画涓嬩竴鎵癸紝瀹屽叏涓嶄緷璧栨粴鍔ㄤ簨浠躲€?
   * 杩欐槸瑙ｅ喅 "Drag gesture has been canceled" 瀵艰嚧 onDidScroll 涓嶈Е鍙戠殑鏍规湰鏂规銆?
   * loadingMore 瀹堝崼闃叉骞跺彂璋冪敤锛沴oadGen 淇濊瘉鍒锋柊鍚庢棫娉佃嚜鍔ㄥ仠姝€?
   */
  private pumpLoad(singleBatch: boolean = false): void {
    galleryAlbumPumpLoad(this.asLoadOrchestratorHost(), singleBatch);
  }

  /**
   * 鍔犺浇鍗曟壒鏁版嵁銆傝繑鍥烇細
   *   >0  = 鏈壒鏂板鏉℃暟
   *    0  = 鏈壒鏃犳柊澧烇紙宸插垏鏃ユ垨褰撴棩缁撴潫锛?
   *   -1  = 鑰楀敖/宸插埛鏂帮紙搴斿仠姝級
   *   -2  = 缃戠粶閿欒锛堟车搴斿欢杩熼噸璇曪級
   *   -3  = 鏆傛€佺┖椤碉細timeline 浠嶆樉绀烘湁鍓╀綑鏉℃暟浣嗘湰鎵逛负绌猴紝闇€寤惰繜鍚庡悓 offset 閲嶈瘯锛堟案涓嶅洜姝ゅ己鍒跺垏鏃ワ級
   *
   * 鍒囨棩绛栫暐锛堝榻?fnos_gallery_mobile.py `_load_batch`锛夛細
   *   1) `len==0` 鎴?`newOff>=itemCount` 鎴?**`len<limit`锛堢煭椤碉級** 鈫?杩涘叆涓嬩竴鏃?
   *   2) 褰?`itemCount>0` 涓?`newOff<itemCount` 鏃剁┖椤典负鏆傛€侊紝鍙噸璇曚笉鍒囨棩锛堢姝€岀┖椤?N 娆℃斁寮冨綋鏃ャ€嶄涪鍥撅級
   */
  private async loadOneBatch(): Promise<number> {
    return await galleryAlbumLoadOneBatch(this.asLoadOrchestratorHost());
  }

  /**
   * 绾瑙夊眰锛氫笉缁戝畾浠讳綍鎵嬪娍锛屾墜鍔跨粺涓€鐢卞灞?Row 瀹瑰櫒澶勭悊銆?
   * GalleryNetworkThumb 鑷韩宸茶 HitTestMode.None锛屽灞?Stack 榛樿 Default锛?
   * 瑙︽懜浜嬩欢浼氶€忎紶鑷崇埗绾?Row锛岀敱 Row 鐨?gesture/parallelGesture 缁熶竴鍝嶅簲銆?
   */

  // 鈹€鈹€ build 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

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
        onSearchQueryChange: (value: string): void => {
          this.searchQuery = value;
        },
        onSearchSubmit: (): void => {
          void this.runSearch(this.searchQuery);
        },
        onExitSelection: (): void => {
          this.exitGallerySelection();
        },
        onEnterSelection: (): void => {
          this.enterGallerySelectionModeFromToolbar();
        },
        onBackToGallery: (): void => {
          this.backToGallery();
        }
      })

      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
        GalleryAlbumEntryChips({
          hidden: this.gallerySelectionMode,
          onOpenMediaCategory: (): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/MediaCategoryPage',
              params: { baseUrl: this.baseUrl }
            }).catch((_e: Error): void => {
              this.toast('鎵撳紑濯掍綋鍒嗙被澶辫触');
            });
          },
          onOpenSmartCategory: (): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/SmartCategoryPage',
              params: { baseUrl: this.baseUrl }
            }).catch((_e: Error): void => {
              this.toast('鎵撳紑鏅鸿兘鍒嗙被澶辫触');
            });
          },
          onOpenPerson: (): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/PersonPage',
              params: { baseUrl: this.baseUrl }
            }).catch((_e: Error): void => {
              this.toast('打开人物页失败');
            });
          },
          onOpenRecent: (): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            void this.openRecentAdded();
          },
          onOpenCollect: (): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            void this.openCollectGallery();
          },
          onOpenRecycleBin: (): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
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
          galleryBatchDownloading: this.galleryBatchDownloading,
          galleryBatchDeleting: this.galleryBatchDeleting,
          galleryMainListScrollEnabled: this.galleryMainListScrollEnabled,
          gallerySlideGestureActive: this.gallerySlideGestureActive,
          modeSwitchOpacity: this.modeSwitchOpacity,
          modeSwitchOffsetY: this.modeSwitchOffsetY,
          itemIdOf: (item: GalleryListItem): string => this.itemIdOf(item),
          isGalleryIdSelected: (id: string): boolean => this.isGalleryIdSelected(id),
          searchThumbDomId: (flatIndex: number): string => this.searchThumbDomId(flatIndex),
          recordSearchThumbRect: (flatIndex: number): void => this.recordSearchThumbRect(flatIndex),
          onSearchThumbTap: (item: GalleryListItem, flatIndex: number): void => this.onSearchThumbTap(item, flatIndex),
          readGestureFingerWindow: (ev: GestureEvent): GalleryFingerWindowPoint | null => this.readGestureFingerWindow(ev),
          pickSearchThumbFlatForRow: (rowStart: number, xPx: number, yPx: number): number =>
            this.pickSearchThumbFlatForRow(rowStart, xPx, yPx),
          onGalleryThumbLongPress: (item: GalleryListItem): void => this.onGalleryThumbLongPress(item),
          beginGallerySlideSelectGesture: (ev: GestureEvent, item: GalleryListItem, anchorFlat: number): void =>
            this.beginGallerySlideSelectGesture(ev, item, anchorFlat),
          endGallerySlideSelectGesture: (): void => this.endGallerySlideSelectGesture(),
          onGallerySlidePanUpdate: (ev: GestureEvent): void => this.onGallerySlidePanUpdate(ev),
          ensureMainListScrollEnabled: (): void => {
            this.galleryMainListScrollEnabled = true;
          },
          clearSearchThumbHitBounds: (): void => {
            this.searchThumbHitBounds.clear();
          },
          onBatchDownload: (): void => {
            void this.confirmAndBatchDownloadGallery();
          },
          onBatchDelete: (): void => {
            void this.confirmAndBatchDeleteGallery();
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
            void this.openCategory(item);
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
            void this.runSearch(keyword);
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
            void this.openPerson(item);
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
          galleryBatchDownloading: this.galleryBatchDownloading,
          galleryBatchDeleting: this.galleryBatchDeleting,
          galleryMainListScrollEnabled: this.galleryMainListScrollEnabled,
          gallerySlideGestureActive: this.gallerySlideGestureActive,
          timelineSidebarDragging: this.timelineSidebarDragging,
          isDraggingOrFling: this.isDraggingOrFling,
          sectionsLength: this.sections.length,
          orderedDaysLength: this.orderedDays.length,
          timelineExpandedChrome: this.timelineScrubExpandedChrome(),
          timelineScrollRailOnly: this.timelineScrubScrollRailOnly(),
          timelineYearMarkers: this.getYearMarkersForTrack(),
          timelineScrubPillLabel: this.getTimelineScrubPillLabel(),
          timelineBarVisible: this.timelineBarVisible,
          timelinePressing: this.timelinePressing,
          timelineLongPressExpanded: this.timelineLongPressExpanded,
          timelineIndicatorY: this.timelineIndicatorY,
          timelineSliderRatio: this.timelineSliderRatio,
          scrollerRef: this.scrollerRef,
          flowDataSource: this.flowDataSource,
          itemIdOf: (item: GalleryListItem): string => this.itemIdOf(item),
          isGalleryIdSelected: (id: string): boolean => this.isGalleryIdSelected(id),
          galleryThumbDomId: (photoId: string): string => this.galleryThumbDomId(photoId),
          recordGalleryThumbRectFromDom: (photoId: string, domId: string): void =>
            this.recordGalleryThumbRectFromDom(photoId, domId),
          onGalleryThumbTap: (item: GalleryListItem, flatIndex: number): void => this.onGalleryThumbTap(item, flatIndex),
          galleryFlowLazyKey: (node: GalleryFlowNode): string => this.galleryFlowLazyKey(node),
          getFlatItems: (): GalleryListItem[] => this.flatItems(),
          endGallerySlideSelectGesture: (): void => this.endGallerySlideSelectGesture(),
          readGestureFingerWindow: (ev: GestureEvent): GalleryFingerWindowPoint | null => this.readGestureFingerWindow(ev),
          pickGalleryThumbFlatForRowOrCache: (node: GalleryFlowNode, xPx: number, yPx: number): number =>
            this.pickGalleryThumbFlatForRowOrCache(node, xPx, yPx),
          onGalleryThumbLongPress: (item: GalleryListItem): void => this.onGalleryThumbLongPress(item),
          beginGallerySlideSelectGesture: (ev: GestureEvent, item: GalleryListItem, anchorFlat: number): void =>
            this.beginGallerySlideSelectGesture(ev, item, anchorFlat),
          onGallerySlidePanUpdate: (ev: GestureEvent): void => this.onGallerySlidePanUpdate(ev),
          onListScrollIndex: (firstIdx: number, lastIdx: number, _centerIdx: number): void => {
            this.listVisibleFirstNodeIdx = firstIdx;
            this.listVisibleLastNodeIdx = Math.max(firstIdx, lastIdx);
            this.refreshLastKnownGlobalSlotsFromListIndices(this.listVisibleFirstNodeIdx, this.listVisibleLastNodeIdx);
            this.captureListScrollIndexAnchor();
            if (this.timelineSidebarDragging || this.timelineSeekInProgress) {
              return;
            }
            this.syncTimelineHandleFromListThrottled(firstIdx);
            this.touchTimelineBarOnScroll();
          },
          onListDidScroll: (_offset: number, _scrollState: ScrollState): void => {
            this.maybeLogMainScrollTick(_offset, _scrollState);
            const draggingOrFling = _scrollState === ScrollState.Scroll || _scrollState === ScrollState.Fling;
            const shouldFreezeByListScroll =
              draggingOrFling && !this.timelineSeekInProgress && Date.now() >= this.ignoreListFreezeUntilMs;
            const wasDraggingOrFling = this.isDraggingOrFling;
            let stateChanged = false;
            if (shouldFreezeByListScroll) {
              if (!this.isDraggingOrFling) {
                this.pumpEpoch++;
                this.cancelListSettledTimer();
                this.isDraggingOrFling = true;
                stateChanged = true;
              }
              if (!this.listKineticScrolling) {
                this.listKineticScrolling = true;
                stateChanged = true;
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
              if (wasDraggingOrFling) {
                this.scheduleMainListSettledWork();
              }
            }
            if (stateChanged) {
              this.refreshVisualPlaceholderMode();
            }
            if (draggingOrFling || this.timelineSidebarDragging) {
              this.touchTimelineBarOnScroll();
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
            void this.onGalleryTimelinePullRefresh();
          },
          onBatchDownload: (): void => {
            void this.confirmAndBatchDownloadGallery();
          },
          onBatchDelete: (): void => {
            void this.confirmAndBatchDeleteGallery();
          },
          onTimelineSeekToCurrentRatio: (): void => {
            this.seekTimelineListToDisplayRatio(this.timelineSliderRatio);
          },
          onTimelineTrackHeightChange: (height: number): void => {
            this.timelineScrubTrackHeightVp = height;
          },
          onTimelineTouchStateChange: (event: TouchEvent): void => {
            if (event.type === TouchType.Down) {
              this.timelinePressing = true;
              this.refreshVisualPlaceholderMode();
              this.showTimelineBar();
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.timelinePressing = false;
              this.timelineLongPressExpanded = false;
              this.refreshVisualPlaceholderMode();
              if (!this.timelineSidebarDragging) {
                this.showTimelineBar();
              }
            }
          },
          onTimelineLongPressExpand: (): void => {
            if (!this.timelineSidebarDragging) {
              this.timelineLongPressExpanded = true;
              this.showTimelineBar();
            }
          },
          onTimelinePanStart: (_event: GestureEvent): void => {
            this.timelineSidebarDragging = true;
            this.timelineLongPressExpanded = false;
            this.timelineDragStartRatio = this.timelineSliderRatio;
            this.lastTimelineDragScrollMs = 0;
            this.refreshVisualPlaceholderMode();
            this.armTimelineDragWatchdog();
            if (this.timelineHideTimer >= 0) {
              clearTimeout(this.timelineHideTimer);
              this.timelineHideTimer = -1;
            }
          },
          onTimelinePanUpdate: (event: GestureEvent): void => {
            const ymList = this.getTimelineYearMonths();
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
            this.timelineIndicatorY = this.timelineIndicatorYForRatio(th, ratio);
            this.armTimelineDragWatchdog();
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
            this.startUpload();
          })
        }
      }
    }
    .width('100%')
    .height('100%')
  }
}





