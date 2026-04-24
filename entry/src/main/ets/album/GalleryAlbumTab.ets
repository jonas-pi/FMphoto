/**
 * 原生相册 Tab（对齐 fnos_gallery_mobile.py §2~§4）
 *
 * 数据链路：
 *   timeline → 按日降序 → 每日 getList 顺序分页
 *   偏移量由 dayNextOffsets（非响应式 Map）同步维护，避免 @State 延迟导致重复请求
 *
 * 加载策略：自驱动泵（pumpLoad），每批完成后自动调度下一批（约一帧间隙，避免同帧内连续抢渲染）。
 *   不依赖滚动事件，彻底规避 "Drag gesture has been canceled" 导致的加载停滞。
 *   onDidScroll 仅作备份重启触发（泵因错误暂停时由滚动重启）。
 *
 * 缩略图：List + LazyForEach；鉴权下载与 LRU 见 GalleryAlbumCommon。
 *   row 的 LazyForEach key 须随槽位 flat 变化（见 galleryFlowLazyKey），否则骨架替换为真实项后子树可能不复用刷新。
 * 大图预览：独立页面 pages/GalleryPreview（Swiper 跟手、规范转场）。
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

const DOMAIN = 0xFF00;
const TAG = 'GalleryTab';
/** 单日分页条数：适当增大可减少 HTTP 往返（服务端 limit 一般可接受 50～100） */
const DATE_FEED_BATCH = 50;
/** 有新增条数时泵的间隔（ms）；远小于旧版 80ms，多日多批时累计延迟明显降低 */
const PUMP_UI_GAP_MS = 16;
/** 每天内最大批次循环次数安全上限（兜底，防极端无限循环） */
const DAY_MAX_ROUNDS = 300;
/** 仅在 timeline 未给出 itemCount（0）时：连续空页达到该阈值才切日 */
const EMPTY_PAGE_ADVANCE_THRESHOLD = 2;
/** 手动点「刷新」防抖（ms）：合并连点，减轻 loadGen 与异步泵交错导致的短暂空白（界面动态操作宜节流合并） */
const GALLERY_BOOTSTRAP_DEBOUNCE_MS = 900;
/**
 * 时间线 Refresh 触发阈值（vp）：与系统 Refresh 一致。
 * 官方将 offset 限制在约 64vp 内，超出无效；此前用大数值会导致「图标/刷新已触发」而震动仍按大阈值，二者错位。
 */
const GALLERY_TIMELINE_REFRESH_OFFSET_VP = 64;
/** LazyForEach 全量骨架下列表项近似高度（vp）：用于 onScrollIndex 滞后时用 Scroller 纵向偏移推导真实视口锚点 */
const GALLERY_LIST_APPROX_MONTH_NODE_VP = 52;
const GALLERY_LIST_APPROX_DAY_NODE_VP = 36;
const GALLERY_LIST_APPROX_ROW_NODE_VP = 124;
/**
 * 用 Scroller.yOffset 反推首可见节点时，沿节点前缀累加近似高度的最大步数。
 * 旧硬编码 8000：列表很深时 y 已超过前 8000 个节点累计高度，仍返回 ~7999，loadVisible 锚到「上方死区」不再拉图。
 */
const GALLERY_SCROLL_Y_ESTIMATE_MAX_NODES = 120000;
/** 大跨度 offset 补偿时单帧内逐步消费的最大迭代，超出则用行高估算剩余位移，避免主线程长时间卡死 */
const GALLERY_SCROLL_DELTA_CONSUME_MAX_IT = 48000;
/** lastKnown 槽位窗：新回调过窄时不覆盖已有大窗，避免与 y 反推/时间轴窗打架形成「载一段、空一段」 */
const GALLERY_LAST_KNOWN_MIN_PREV_SLOT_SPAN = 80;
const GALLERY_LAST_KNOWN_DEGENERATE_NEW_SLOT_SPAN = 44;
const GALLERY_LAST_KNOWN_SHRINK_IGNORE_RATIO = 4;
/** refine：y 累加估算与锚点推进差过大时不再采信 estFromY，避免单侧把 first 拉飞 */
const GALLERY_REFINE_EST_ADV_MAX_DRIFT_NODES = 6000;
/** refine：锚点首索引与 y 反推首索引长期偏离时重同步，避免长距离滚动后 adv 与 est 双漂移、整段不出图 */
const GALLERY_REFINE_ANCHOR_RESYNC_NODE_DRIFT = 4200;
/** refine：List 声称的 (cf,cl) 跨度过小时仍保底「视口」节点跨度，避免 loadVisible 槽位窗过窄 */
const GALLERY_REFINE_MIN_VISIBLE_NODE_SPAN = 30;
/** loadVisible：用 y 反推首节点扩展 buffer 骨架扫描上沿，缓解无 getVisibleRange 时 refine 与 y 打架 */
const GALLERY_LOAD_VISIBLE_BUFFER_SCAN_WIN_NODES = 32;
/** getVisibleRange 命中时：骨架缓冲扫描在可见节点区间外再扩的节点数（同行 RecyclerView 式 prefetch margin） */
const GALLERY_LOAD_VISIBLE_SCROLLER_RANGE_PAD_NODES = 8;
/** loadVisible：在「当前 List 节点窗口」内按骨架槽位数扩展下方全局槽位缓冲，少依赖固定日粒度 */
const GALLERY_LOAD_VISIBLE_BUFFER_BASE_NON_AGGRESSIVE = 22;
const GALLERY_LOAD_VISIBLE_BUFFER_BASE_AGGRESSIVE = 10;
const GALLERY_LOAD_VISIBLE_SKELETON_SLOT_MULTIPLIER = 4;
const GALLERY_LOAD_VISIBLE_BUFFER_AFTER_CAP = 140;
/** 同屏跨多日时顺序按日各拉一批的上限：再大易拖长首帧；超出部分靠后续滚动或 pumpLoad 续载 */
const GALLERY_LOAD_VISIBLE_MULTI_DAY_CHAIN_MAX = 24;
/** 时间轴靠边区域宽度（vp），含细轨与滑块，便于点按 */
const GALLERY_TIMELINE_HIT_WIDTH_VP = 52;
const GALLERY_TIMELINE_RAIL_MIN_VP = 6;
const GALLERY_TIMELINE_RAIL_EXPANDED_VP = 7;
const GALLERY_TIMELINE_RAIL_DRAG_VP = 8;
const GALLERY_TIMELINE_THUMB_VP = 10;
/** 手柄/气泡在轨道上下预留（与 timelineIndicatorY 计算一致） */
const GALLERY_TIMELINE_INDICATOR_PAD_VP = 14;
const GALLERY_TIMELINE_INDICATOR_RESERVED_VP = GALLERY_TIMELINE_INDICATOR_PAD_VP * 2;
/** 上传成功后二次拉时间轴间隔（ms）：NAS 入库略延迟时提高新图出现概率 */
const GALLERY_UPLOAD_RECHECK_MS = 1600;
/** 最近添加分页条数：与抓包量级一致，减少往返次数同时避免单次过大 */
const GALLERY_RECENT_PAGE_LIMIT = 60;
/** 最近添加单日分页安全上限：防止服务端异常导致死循环 */
const GALLERY_RECENT_DAY_MAX_ROUNDS = 200;
/** 临时排障：主时间线滚动日志开关（定位卡顿路径，稳定后可改为 false） */
const GALLERY_SCROLL_DEBUG_LOG = false;
/** 滚动日志最小间隔（ms），避免高频刷日志反向放大卡顿 */
const GALLERY_SCROLL_LOG_THROTTLE_MS = 180;
/** 仅在最近交互窗口内打印泵/批次细粒度日志，避免无操作刷屏 */
const GALLERY_SCROLL_INTERACTIVE_LOG_WINDOW_MS = 2200;
/** 批次级噪声日志开关（short page / batch 明细）；排障时可手动打开 */
const GALLERY_BATCH_VERBOSE_LOG = false;
/** 时间轴拖动 watchdog：超过该时长未收到更新/结束则自动释放拖动态，避免占位模式锁死 */
const GALLERY_TIMELINE_DRAG_WATCHDOG_MS = 1200;
/** 仅「滚动条式」细轨提示时的自动隐藏（替代系统滚动条） */
const GALLERY_TIMELINE_RAIL_AUTO_HIDE_MS = 1000;
/** 长按/拖动展开后的自动隐藏（松手后仍可见一小段时间） */
const GALLERY_TIMELINE_EXPANDED_AUTO_HIDE_MS = 2200;
/** 靠边细轨上长按达到该时长后展开为完整时间轴 scrub */
const GALLERY_TIMELINE_LONG_PRESS_EXPAND_MS = 420;
/** 年份刻度相对命中区左缘的 x（负值向左溢出）；数值越大越靠右，贴近右侧细轨 */
const GALLERY_TIMELINE_YEAR_BADGE_X_VP = -22;
/** 年月 pill 右缘与年份刻度左缘的间距（vp） */
const GALLERY_TIMELINE_PILL_TO_YEAR_GAP_VP = 6;
/** 年月 pill 最小宽度：单行「年月日」不折行（过长时省略号） */
const GALLERY_TIMELINE_SCRUB_PILL_MIN_WIDTH_VP = 208;
/** 年月 pill 左上角 x：右缘贴近年份刻度左缘 */
const GALLERY_TIMELINE_SCRUB_PILL_X_VP =
  GALLERY_TIMELINE_YEAR_BADGE_X_VP - GALLERY_TIMELINE_PILL_TO_YEAR_GAP_VP - GALLERY_TIMELINE_SCRUB_PILL_MIN_WIDTH_VP;

/** 主时间线缩略图滑动连选：用于指尖坐标与缩略图区域相交判断（窗口坐标系，与 getRectangleById 一致） */
interface GalleryThumbHitRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

/** loadVisible 用：经滚动偏移补偿后的 List 节点下标区间 */
interface GalleryVisibleNodeRange {
  first: number;
  last: number;
}

/** 部分 SDK 在 List 绑定的 Scroller 上提供 getVisibleRange；存在则优先于 offset 估算 */
interface GalleryScrollerVisibleRange {
  start: number;
  end: number;
}

interface GalleryScrollerMaybeVisibleRange {
  getVisibleRange?: () => GalleryScrollerVisibleRange | null;
}

/** 指尖在窗口中的坐标（px），供 readGestureFingerWindow 返回；禁止内联对象类型以满足 arkts-no-obj-literals-as-types */
interface GalleryFingerWindowPoint {
  x: number;
  y: number;
}

/**
 * 不同 API 版本 FingerInfo 字段名可能不同，用可选字段做兼容读取（不做 unknown 断言，满足 arkts-no-any-unknown）。
 */
interface GalleryFingerCoordCompat {
  windowX?: number;
  windowY?: number;
  globalX?: number;
  globalY?: number;
  screenX?: number;
  screenY?: number;
  displayX?: number;
  displayY?: number;
  /** 部分版本仅提供相对触点坐标 */
  x?: number;
  y?: number;
}

// ─── 数据模型 ──────────────────────────────────────────────────────────────

interface TimelineDayModel {
  year: number;
  month: number;
  day: number;
  itemCount: number;
}

interface TimelineYearMonth {
  year: number;
  month: number;
  index: number;
}

interface TimelineYearMonthPair {
  year: number;
  month: number;
}

interface YearMarker {
  year: number;
  y: number;
}

/** 全局照片下标反查结果：满足 arkts-no-obj-literals-as-types / arkts-no-untyped-obj-literals */
interface DayGlobalResolveResult {
  dayIdx: number;
  dayOffset: number;
}

/**
 * 按日区块：使用 @Observed 以便同日多批追加 items 时子树增量刷新，
 * 避免仅靠 ForEach key 含 items.length 导致整段 Column 反复重挂载（解码/布局成本高、体感慢）。
 */
@Observed
class DaySectionModel {
  year: number = 0;
  month: number = 0;
  day: number = 0;
  itemCount: number = 0;
  /** 当日已加载照片：key 为日内 offset（0..itemCount-1），支持乱序/分页填充，与全量骨架映射一致 */
  slotByOffset: Map<number, GalleryListItem> = new Map<number, GalleryListItem>();
  nextOffset: number = 0;
}

// ─── 工具函数 ──────────────────────────────────────────────────────────────

function fmtDayStart(y: number, m: number, d: number): string {
  return `${y}:${m.toString().padStart(2, '0')}:${d.toString().padStart(2, '0')} 00:00:00`;
}

function fmtDayEnd(y: number, m: number, d: number): string {
  return `${y}:${m.toString().padStart(2, '0')}:${d.toString().padStart(2, '0')} 23:59:59`;
}

function ymKey(y: number, m: number): string {
  return `${y}-${m}`;
}

function dayKey(y: number, m: number, d: number): string {
  return `${y}-${m}-${d}`;
}

function parseTimelineDayCells(raw: Array<Record<string, number | undefined>>): TimelineDayModel[] {
  const out: TimelineDayModel[] = [];
  for (let i = 0; i < raw.length; i++) {
    const x = raw[i];
    const year = x['year'];
    const month = x['month'];
    const day = x['day'];
    if (year === undefined || month === undefined || day === undefined) {
      continue;
    }
    const yi = Number(year);
    const mi = Number(month);
    const di = Number(day);
    if (!Number.isFinite(yi) || !Number.isFinite(mi) || !Number.isFinite(di)) {
      continue;
    }
    const itemCount = x['itemCount'];
    const itemCountSnake = x['item_count'];
    const ic = itemCount !== undefined ? itemCount : itemCountSnake;
    const cnt = ic !== undefined && Number.isFinite(Number(ic)) ? Math.max(0, Math.floor(Number(ic))) : 0;
    out.push({ year: Math.floor(yi), month: Math.floor(mi), day: Math.floor(di), itemCount: cnt });
  }
  return out;
}

function sortDaysDesc(cells: TimelineDayModel[]): TimelineDayModel[] {
  return cells.slice().sort((a: TimelineDayModel, b: TimelineDayModel): number => {
    if (a.year !== b.year) {
      return b.year - a.year;
    }
    if (a.month !== b.month) {
      return b.month - a.month;
    }
    return b.day - a.day;
  });
}

function listFromData(data: GalleryGetListData | undefined): GalleryListItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  // 对齐 Python: isinstance(raw_list, list) 检查，非数组类型一律返回空（服务端偶发 null / 数字等异常值）
  const raw = data.list ?? data.items ?? data.photos ?? data.records;
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw as GalleryListItem[];
}

// ─── 主 Tab 组件 ───────────────────────────────────────────────────────────

@Component
export struct GalleryAlbumTab {
  @Prop baseUrl: string = '';
  @Prop @Watch('onEpochChange') albumReloadEpoch: number = 0;
  /** Home.onPageShow() 递增 → 触发删除同步（安全保障，不依赖子组件 onPageShow 传播） */
  @Prop @Watch('onPageShowSignal') pageShowSignal: number = 0;

  @State private bootLoading: boolean = false;
  @State private loadError: string = '';
  @State private footText: string = '';
  @State private sections: DaySectionModel[] = [];

  // ── 搜索状态 ────────────────────────────────────────────────────────────────
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
  /** 打开「收藏」聚合列表时的全屏遮罩（与最近添加一致） */
  @State private collectOpening: boolean = false;
  @State private personError: string = '';
  @State private personItems: AiPersonItem[] = [];
  @State private personStatVersion: number = 0;
  /** 上传状态 */
  @State private uploading: boolean = false;
  @State private uploadText: string = '';
  /** 主图库长按多选（与系统拖拽/中转站解耦：缩略图已 draggable(false)） */
  @State private gallerySelectionMode: boolean = false;
  @State private gallerySelectedIds: string[] = [];
  @State private galleryBatchDeleting: boolean = false;
  @State private galleryBatchDownloading: boolean = false;
  /**
   * 主时间线 List 是否响应手指滚动。
   * 划选时临时关闭，避免 List 抢走 Pan；LazyForEach 行 key 勿随多选切换，否则子树重建会中断当前指下手势。
   */
  @State private galleryMainListScrollEnabled: boolean = true;
  /**
   * 统一交互状态机：
   * - timelineSidebarDragging: 时间轴手势进行中
   * - isDraggingOrFling: 主列表正在拖动/惯性（Scroll/Fling）
   * - visualPlaceholderMode: 图片加载门控（时间轴拖动或主列表拖动/惯性时为 true）
   *
   * 约束：任何图片请求开关都只看 visualPlaceholderMode，避免多状态互相覆盖。
   */
  @State private timelineSidebarDragging: boolean = false;
  @State private listKineticScrolling: boolean = false;
  @State private isDraggingOrFling: boolean = false;
  @State private visualPlaceholderMode: boolean = false;
  /** 主列表 Idle 后 settled 防抖定时器 id；再次滚动时取消 */
  private listSettledTimer: number = -1;
  /** settled 防抖代次，避免旧定时器回写 */
  private listSettledGen: number = 0;
  /** 滚动排障：上次滚动日志时间戳 */
  private lastScrollDebugLogMs: number = 0;
  /** 滚动排障：上次滚动状态文本（仅状态变化或节流到期才打印） */
  private lastScrollDebugState: string = 'init';
  /** 最近一次主列表交互时间（用于限制泵日志仅在交互窗口输出） */
  private lastMainListInteractMs: number = 0;
  /** 时间轴拖动态 watchdog 定时器 */
  private timelineDragWatchdogTimer: number = -1;
  /** 时间轴拖动会话代次（用于取消旧 watchdog 回写） */
  private timelineDragWatchdogGen: number = 0;
  /** 滚动时触达时间轴显隐的节流时间戳，避免每帧重置 show/hide 定时器 */
  private lastTimelineBarTouchMs: number = 0;
  /** 主列表 -> 时间轴手柄位置同步节流时间戳（避免 onScrollIndex 高频驱动手柄重绘） */
  private lastTimelineHandleSyncMs: number = 0;
  /** 时间轴是否显示（滚动中/交互中显式可见，静止后自动淡出） */
  @State private timelineBarVisible: boolean = false;
  /** 时间轴按压态：手指在轨道上（用于显隐与触感，不等同于「展开 scrub」） */
  @State private timelinePressing: boolean = false;
  /** 长按细轨后进入完整展开态（年月气泡、年份刻度等）；纵向拖动也会进入展开 */
  @State private timelineLongPressExpanded: boolean = false;
  /** 滑块比例 [0,1]，0=最新，1=最早 */
  @State private timelineSliderRatio: number = 0;
  /** 当前高亮月份在时间轴年月列表中的下标 */
  @State private timelineSidebarHighlightIndex: number = 0;
  /** 指示标签的 Y 位置（vp） */
  @State private timelineIndicatorY: number = 12;
  /** 时间轴可用轨道高度（vp），由 onAreaChange 实测写入 */
  @State private timelineScrubTrackHeightVp: number = 500;
  /** 拖动开始时比例 */
  private timelineDragStartRatio: number = 0;
  /** 拖动节流（ms） */
  private lastTimelineDragScrollMs: number = 0;
  /** 自动隐藏定时器 */
  private timelineHideTimer: number = -1;
  /** seek 保护标记：松手后短窗内阻断反向同步 */
  private timelineSeekInProgress: boolean = false;
  /** seek 监视器代次：新拖动可取消旧任务 */
  private timelineSeekGen: number = 0;
  /** 当前 List 可见节点区间（由 onScrollIndex 回传） */
  private listVisibleFirstNodeIdx: number = 0;
  private listVisibleLastNodeIdx: number = 0;
  /**
   * onScrollIndex 最近一次回调时的 Scroller 纵向偏移与首索引。
   * LazyForEach + 全量骨架下列表常「滚动了很久才更新 first/last」，用 (yNow - anchorY) 向前推进节点以贴合真实视口。
   */
  private listScrollIndexAnchorYVp: number = 0;
  private listScrollIndexAnchorFirst: number = 0;
  private listScrollIndexAnchorHave: boolean = false;
  /**
   * 全时间线「照片槽位」下标缓存（与 countPhotoSlotsBeforeNode 一致）：
   * 可见区只有标题行时 onScrollIndex 会得到 visEnd<=visStart，导致 loadVisible 永远不触发；
   * 用最近一次有效可视槽位作为松手/静止后的加载锚点。
   */
  private lastKnownGlobalPhotoSlotStart: number = 0;
  private lastKnownGlobalPhotoSlotEndExclusive: number = 0;
  /** 可视区预加载缓冲（以“照片槽位”计） */
  private readonly visiblePhotoBufferSlots: number = 12;
  /** 可视区驱动加载节流：避免 Idle 抖动时高频触发 loadVisibleItems */
  private lastLoadVisibleAtMs: number = 0;
  /** pump 代次：新滚动开始时递增，旧 pump/回调立即失效（打断并发链路） */
  private pumpEpoch: number = 0;
  /** 时间轴松手后短窗内忽略程序化滚动对冻结态的回写，防止“必须再滑一下才加载” */
  private ignoreListFreezeUntilMs: number = 0;
  /** 视觉冻结期（拖动/Fling）收到的数据变更延迟到解冻后再一次性刷新，避免滚动条不跟手 */
  private pendingFlowRebuild: boolean = false;
  /** 避免滚动停止后重复触发同一目标日的抢占加载 */
  private lastVisibleLoadDayIdx: number = -1;
  /** 模式切换时内容层动效（淡入 + 轻微位移） */
  @State private modeSwitchOpacity: number = 1;
  @State private modeSwitchOffsetY: number = 0;
  /** WaterFlow + LazyForEach 数据源（与 sections 同步） */
  private flowDataSource: GalleryWaterFlowDataSource = new GalleryWaterFlowDataSource();

  private loadGen: number = 0;
  private personStatGen: number = 0;
  private personStatOverrides: Map<string, string> = new Map<string, string>();
  private orderedDays: TimelineDayModel[] = [];
  private dayIndex: number = 0;
  private loadingMore: boolean = false;
  private exhausted: boolean = false;
  private dayOffsets: Map<string, number> = new Map<string, number>();
  /** 每天已请求的批次数（安全上限，防止 itemCount 不准时无限循环） */
  private dayRounds: Map<string, number> = new Map<string, number>();
  /** 每天连续空页计数（防止单次空页误切日） */
  private dayEmptyRounds: Map<string, number> = new Map<string, number>();
  private scrollerRef: Scroller = new Scroller();
  /** 上次已处理的删除同步版本号 */
  private handledDeleteSyncVersion: number = 0;
  /** 长按后在此时间戳之前忽略单击，避免误进预览 */
  private galleryLongPressIgnoreClickUntil: number = 0;
  /**
   * 「划选段」进行中：为 true 时 onDidScroll 不清空命中缓存；且 Row 上 Pan 切为全向以跨行划选。
   * 为 @State 以便多选态下在「仅横向 Pan / 全向 Pan」间切换（对齐系统相册：纵滑列表、横滑划选）。
   */
  @State private gallerySlideGestureActive: boolean = false;
  /** 各缩略图最近一次布局在窗口中的矩形（仅当前可见/曾布局项有值；列表滚动时会清空以防脏矩形） */
  private galleryThumbHitBounds: Map<string, GalleryThumbHitRect> = new Map<string, GalleryThumbHitRect>();
  /** AI 搜索结果列表划选命中矩形（键为扁平下标字符串，与 `sg_${flat}` 对应） */
  private searchThumbHitBounds: Map<string, GalleryThumbHitRect> = new Map<string, GalleryThumbHitRect>();
  /** 滑动连选：fingerList 不可用时，用长按参考点 + Pan offset 估算指尖位置 */
  private gallerySlideRefX: number = 0;
  private gallerySlideRefY: number = 0;
  private gallerySlideHasRef: boolean = false;
  /**
   * 划选锚点：长按起始缩略图在扁平列表中的下标（与 flow row 的 rowSlotFlatIndices 一致，行优先 3 列一行）。
   */
  private gallerySlideAnchorFlat: number = -1;
  /**
   * 进入本次划选前已选中的 id（不含后续滑动临时扩选时可再收缩的部分通过「区间并集」计算）。
   * 在 begin 时取 snapshot，保证缩回手指时只去掉「当前 flat 区间」内、且不在此集合中的项。
   */
  private gallerySlideUnionBase: string[] = [];
  /**
   * 当前划选区间终点 flat；指尖短暂离开缩略图时沿用上一次命中，避免选中闪烁。
   */
  private gallerySlideLastEndFlat: number = -1;
  /** 划选时仅当终点 flat 变化时才提交 @State，减轻列表整表刷新卡顿 */
  private gallerySlideLastAppliedEndFlat: number = -99999;
  /** 防抖定时器 id（<0 表示未挂起） */
  private bootstrapDebounceTimer: number = -1;
  /** 与 GalleryTimelineRefreshStore.version 对齐：成功 bootstrap 时间轴后更新，避免重复全量刷 */
  private lastBootstrapSatisfiedRefreshVersion: number = 0;
  /** 时间线 List 下拉刷新：系统 Refresh 动效绑定 */
  @State private galleryTimelineRefreshing: boolean = false;
  /**
   * 时间线是否在列表顶端（Scroller 垂直偏移≈0）。非 @State，避免滚动时整页重绘；
   * 在 onDidScroll / 下拉回调前同步，仅用于判断是否允许触发刷新。
   */
  private galleryTimelineAtTopForPull: boolean = true;
  /** 下拉未回到顶部附近前不重复触发「已达阈值」震动，避免来回拖动连续振 */
  private galleryPullRefreshThresholdHapticDone: boolean = false;

  // ── 扁平列表（供跳转独立预览页） ─────────────────────────────────────────

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
   * 由时间轴 + 已加载 section 重建 List 节点：
   * 1) 优先按 orderedDays（完整时间轴）铺出完整日结构与骨架行，确保总高度从一开始就正确；
   * 2) 对已加载的区段，用真实图片覆盖对应骨架槽位；
   * 3) 未加载部分继续保留 skeleton，占位但不触发网络请求。
   *
   * 这样拖到底时不会出现“看起来到底但实际上只是已加载到底”的问题。
   */
  private rebuildFlow(): void {
    if (this.timelineSidebarDragging || this.isDraggingOrFling) {
      this.pendingFlowRebuild = true;
      return;
    }
    const nodes: GalleryFlowNode[] = [];
    // day -> section 索引，O(1) 命中已加载数据
    const secMap = new Map<string, DaySectionModel>();
    for (let i = 0; i < this.sections.length; i++) {
      const s = this.sections[i];
      secMap.set(dayKey(s.year, s.month, s.day), s);
    }

    // 扁平索引仅统计“真实已加载图片”（预览/多选仍只作用于真实图）
    let flatLoaded = 0;

    // 有完整时间轴时优先使用它构建全量骨架；否则退化为旧行为（仅 sections）
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
      // 兜底：无时间轴时按已加载 section 构建（旧行为）
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
   * rebuild / flush 后 LazyForEach 的 onScrollIndex 常仍滞后。
   * 优先使用 Scroller.getVisibleRange（若存在）；否则**仅用 1vp 微调**触发框架回传 onScrollIndex。
   * 不再用 y/固定 vp 反推节点下标：全量骨架下行高与「节点」非线性对应，易把 loadVisible 锚到屏外。
   */
  private tryApplyScrollerVisibleRangeIfAvailable(total: number): boolean {
    try {
      const sc = this.scrollerRef as GalleryScrollerMaybeVisibleRange;
      if (sc.getVisibleRange === undefined) {
        return false;
      }
      const range = sc.getVisibleRange();
      if (range === null || range === undefined) {
        return false;
      }
      const st = range.start;
      const en = range.end;
      if (typeof st !== 'number' || typeof en !== 'number' || !Number.isFinite(st) || !Number.isFinite(en)) {
        return false;
      }
      const first = Math.max(0, Math.min(total - 1, Math.floor(st)));
      const last = Math.max(first, Math.min(total - 1, Math.floor(en)));
      this.listVisibleFirstNodeIdx = first;
      this.listVisibleLastNodeIdx = last;
      this.logScrollDebug(`forceRefresh visible range by API: ${first} ~ ${last}`);
      return true;
    } catch (_e) {
      return false;
    }
  }

  /** 无 getVisibleRange 时：轻微滚动以触发 onScrollIndex，避免用错误 offset 反推覆盖 listVisible* */
  private nudgeListScrollForScrollIndexRefresh(): void {
    this.logScrollDebug('forceRefresh: 1vp nudge for onScrollIndex');
    try {
      const off = this.scrollerRef.currentOffset();
      const yRaw = off.yOffset;
      const y = typeof yRaw === 'number' && Number.isFinite(yRaw) ? yRaw : 0;
      this.scrollerRef.scrollTo({ xOffset: 0, yOffset: y + 1 });
      setTimeout((): void => {
        try {
          this.scrollerRef.scrollTo({ xOffset: 0, yOffset: y });
        } catch (_e2) {
        }
      }, 16);
    } catch (_e) {
    }
  }

  private forceRefreshVisibleRange(): void {
    const total = this.flowDataSource.totalCount();
    if (total <= 0) {
      return;
    }
    if (this.tryApplyScrollerVisibleRangeIfAvailable(total)) {
      this.refreshLastKnownGlobalSlotsFromListIndices(this.listVisibleFirstNodeIdx, this.listVisibleLastNodeIdx);
      this.captureListScrollIndexAnchor();
      return;
    }
    this.nudgeListScrollForScrollIndexRefresh();
  }

  private flushPendingFlowRebuild(): void {
    if (!this.pendingFlowRebuild) {
      return;
    }
    if (this.timelineSidebarDragging || this.isDraggingOrFling) {
      return;
    }
    this.pendingFlowRebuild = false;
    this.rebuildFlow();
    this.flowDataSource.notifyDataReload();
    this.forceRefreshVisibleRange();
    setTimeout((): void => {
      if (this.visualPlaceholderMode || this.isDraggingOrFling) {
        return;
      }
      this.lastLoadVisibleAtMs = 0;
      this.loadVisibleItemsThrottled(true, false);
    }, 16);
  }

  /** 根据交互状态统一计算占位模式开关（唯一出口，避免多状态覆盖） */
  private refreshVisualPlaceholderMode(): void {
    const next = this.timelineSidebarDragging || this.isDraggingOrFling;
    if (this.visualPlaceholderMode !== next) {
      this.visualPlaceholderMode = next;
    }
  }

  private touchTimelineBarOnScroll(): void {
    const now = Date.now();
    if (!this.timelineBarVisible || now - this.lastTimelineBarTouchMs >= 100) {
      this.lastTimelineBarTouchMs = now;
      this.showTimelineBar();
    }
  }

  private syncTimelineHandleFromListThrottled(firstIdx: number): void {
    const now = Date.now();
    if (now - this.lastTimelineHandleSyncMs < 80) {
      return;
    }
    this.lastTimelineHandleSyncMs = now;
    this.syncTimelineSliderFromFirstIndex(firstIdx);
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
    if (!GALLERY_SCROLL_DEBUG_LOG) {
      return;
    }
    hilog.info(DOMAIN, TAG, '[scroll-debug] %{public}s', msg);
  }

  private isInScrollInteractiveLogWindow(): boolean {
    const now = Date.now();
    return now - this.lastMainListInteractMs <= GALLERY_SCROLL_INTERACTIVE_LOG_WINDOW_MS;
  }

  private cancelTimelineDragWatchdog(): void {
    if (this.timelineDragWatchdogTimer >= 0) {
      clearTimeout(this.timelineDragWatchdogTimer);
      this.timelineDragWatchdogTimer = -1;
    }
  }

  private armTimelineDragWatchdog(): void {
    this.cancelTimelineDragWatchdog();
    const gen = ++this.timelineDragWatchdogGen;
    this.timelineDragWatchdogTimer = setTimeout((): void => {
      if (gen !== this.timelineDragWatchdogGen) {
        return;
      }
      this.timelineDragWatchdogTimer = -1;
      if (!this.timelineSidebarDragging) {
        return;
      }
      this.timelineSidebarDragging = false;
      this.timelinePressing = false;
      this.timelineLongPressExpanded = false;
      this.timelineSeekInProgress = false;
      this.refreshVisualPlaceholderMode();
      this.showTimelineBar();
      this.logScrollDebug('timeline drag watchdog release');
      this.runMainListScrollSettledWork();
    }, GALLERY_TIMELINE_DRAG_WATCHDOG_MS);
  }

  private maybeLogMainScrollTick(offset: number, state: ScrollState): void {
    if (!GALLERY_SCROLL_DEBUG_LOG) {
      return;
    }
    this.lastMainListInteractMs = Date.now();
    const now = Date.now();
    const st = this.scrollStateText(state);
    const changed = st !== this.lastScrollDebugState;
    if (!changed && now - this.lastScrollDebugLogMs < GALLERY_SCROLL_LOG_THROTTLE_MS) {
      return;
    }
    this.lastScrollDebugState = st;
    this.lastScrollDebugLogMs = now;
    this.logScrollDebug(
      `state=${st}, offset=${offset.toFixed(1)}, placeholder=${this.visualPlaceholderMode ? 1 : 0}, `
      + `kinetic=${this.listKineticScrolling ? 1 : 0}, dragFling=${this.isDraggingOrFling ? 1 : 0}, `
      + `dayIndex=${this.dayIndex}, exhausted=${this.exhausted ? 1 : 0}, loadingMore=${this.loadingMore ? 1 : 0}`
    );
  }

  private cancelListSettledTimer(invalidateGen: boolean = true): void {
    if (this.listSettledTimer >= 0) {
      clearTimeout(this.listSettledTimer);
      this.listSettledTimer = -1;
    }
    if (invalidateGen) {
      this.listSettledGen++;
    }
  }

  private scheduleMainListSettledWork(): void {
    this.cancelListSettledTimer(false);
    const gen = ++this.listSettledGen;
    const epoch = this.pumpEpoch;
    // Idle 边沿已清掉 drag/placeholder，立刻按可视区拉图；原 220ms 定时器只做二次对齐 + pump，避免「停手还要等一段才出图」
    if (!this.isDraggingOrFling && !this.visualPlaceholderMode && !this.timelineSidebarDragging) {
      this.loadVisibleItemsThrottled(true, false);
    }
    this.listSettledTimer = setTimeout((): void => {
      if (gen !== this.listSettledGen) {
        return;
      }
      if (epoch !== this.pumpEpoch) {
        return;
      }
      if (this.listSettledTimer < 0) {
        return;
      }
      this.listSettledTimer = -1;
      if (this.isDraggingOrFling || this.visualPlaceholderMode) {
        return;
      }
      this.logScrollDebug('settled release: loadVisible + settledWork');
      this.loadVisibleItemsThrottled();
      this.runMainListScrollSettledWork(epoch);
    }, 220);
  }

  /**
   * 主列表滚动已结束且不再占位后：同步顶部时间轴、恢复滚动条、清理命中缓存、触发泵加载。
   * 由 onDidScroll 与 Idle 防抖定时器共用，避免漏调 pump。
   */
  private runMainListScrollSettledWork(epochAtSchedule: number = -1): void {
    if (epochAtSchedule >= 0 && epochAtSchedule !== this.pumpEpoch) {
      return;
    }
    if (this.isDraggingOrFling || this.visualPlaceholderMode) {
      return;
    }
    if (this.timelineSidebarDragging || this.timelineSeekInProgress) {
      return;
    }
    this.syncGalleryTimelineAtTopForPull();
    if (!this.gallerySlideGestureActive && !this.galleryMainListScrollEnabled) {
      this.galleryMainListScrollEnabled = true;
    }
    if (!this.gallerySlideGestureActive) {
      this.clearGalleryThumbHitBounds();
    }
    if (!this.exhausted && !this.loadingMore && !this.bootLoading) {
      // settled 后仅补 1 个 batch，避免一次触发长链自驱动
      this.pumpLoad(true);
    }
    this.flushPendingFlowRebuild();
  }

  /** 完整展开 scrub：拖动时间轴或长按细轨 */
  private timelineScrubExpandedChrome(): boolean {
    return this.timelineSidebarDragging || this.timelineLongPressExpanded;
  }

  /** 仅列表滚动触发的「细轨」提示，不占满交互样式 */
  private timelineScrubScrollRailOnly(): boolean {
    return this.timelineBarVisible && !this.timelineScrubExpandedChrome();
  }

  /** 显示时间轴并重置自动隐藏倒计时（手指在轨道上时不启动倒计时） */
  private showTimelineBar(): void {
    this.timelineBarVisible = true;
    if (this.timelineHideTimer >= 0) {
      clearTimeout(this.timelineHideTimer);
      this.timelineHideTimer = -1;
    }
    if (this.timelineSidebarDragging || this.timelinePressing) {
      return;
    }
    const hideMs = this.timelineScrubExpandedChrome()
      ? GALLERY_TIMELINE_EXPANDED_AUTO_HIDE_MS
      : GALLERY_TIMELINE_RAIL_AUTO_HIDE_MS;
    this.timelineHideTimer = setTimeout((): void => {
      this.timelineHideTimer = -1;
      this.timelineBarVisible = false;
      this.timelineLongPressExpanded = false;
    }, hideMs);
  }

  /** 获取时间轴年月列表（完整时间轴优先：orderedDays） */
  private getTimelineYearMonths(): TimelineYearMonth[] {
    const out: TimelineYearMonth[] = [];
    const seen = new Set<string>();
    for (let i = 0; i < this.orderedDays.length; i++) {
      const d = this.orderedDays[i];
      const k = ymKey(d.year, d.month);
      if (!seen.has(k)) {
        seen.add(k);
        out.push({ year: d.year, month: d.month, index: i });
      }
    }
    // 兜底：若 orderedDays 尚未可用，退化为 sections
    if (out.length === 0) {
      for (let i = 0; i < this.sections.length; i++) {
        const s = this.sections[i];
        const k = ymKey(s.year, s.month);
        if (!seen.has(k)) {
          seen.add(k);
          out.push({ year: s.year, month: s.month, index: i });
        }
      }
    }
    return out;
  }

  /** 比例 -> 年月（0=最新，1=最早） */
  private resolveYearMonthByTimelineRatio(ratio: number): TimelineYearMonthPair | null {
    const ymList = this.getTimelineYearMonths();
    if (ymList.length === 0) {
      return null;
    }
    const t = Math.max(0, Math.min(1, ratio));
    const idx = Math.round(t * (ymList.length - 1));
    const c = Math.max(0, Math.min(ymList.length - 1, idx));
    return { year: ymList[c].year, month: ymList[c].month };
  }

  /**
   * 不依赖 List 可见区索引：按当前时间轴滑块比例对齐 pump 起点。
   * 解决「松手后未触发 onScrollIndex，visStart==visEnd 导致永远不 pump」的问题。
   *
   * 注意：同一自然月对应 **多条** orderedDays（按日降序），旧实现只取命中第一条的槽位区间，
   * lastKnownGlobal 仅覆盖「一天」，同屏其它日会长期骨架不拉取；向上滑时常表现为固定一条「死带」。
   */
  private alignPumpToTimelineSliderTarget(): boolean {
    const ym = this.resolveYearMonthByTimelineRatio(this.timelineSliderRatio);
    if (ym === null || this.orderedDays.length === 0) {
      return false;
    }
    let lo = this.orderedDays.length;
    let hi = -1;
    for (let i = 0; i < this.orderedDays.length; i++) {
      const d = this.orderedDays[i];
      if (d.year === ym.year && d.month === ym.month) {
        if (i < lo) {
          lo = i;
        }
        if (i > hi) {
          hi = i;
        }
      }
    }
    if (lo > hi || lo < 0 || hi < 0) {
      return false;
    }
    this.dayIndex = lo;
    this.lastVisibleLoadDayIdx = lo;
    const d0 = this.orderedDays[lo];
    const k0 = dayKey(d0.year, d0.month, d0.day);
    this.dayOffsets.set(k0, 0);
    const gStart = this.globalSlotIndexAtDayStart(lo);
    const dLast = this.orderedDays[hi];
    const gEndExclusive = this.globalSlotIndexAtDayStart(hi) + Math.max(0, dLast.itemCount);
    this.lastKnownGlobalPhotoSlotStart = gStart;
    this.lastKnownGlobalPhotoSlotEndExclusive = Math.max(gStart + 1, gEndExclusive);
    return true;
  }

  /** 当前 flow 中是否已有指定年月节点 */
  private flowHasVisibleYearMonth(year: number, month: number): boolean {
    const total = this.flowDataSource.totalCount();
    for (let i = 0; i < total; i++) {
      const node = this.flowDataSource.getData(i);
      if ((node.kind === 'month' || node.kind === 'day') && node.year === year && node.month === month) {
        return true;
      }
    }
    return false;
  }

  /** 指定年月已可见时执行精确跳转 */
  private tryScrollListToYearMonthIfVisible(year: number, month: number): boolean {
    const total = this.flowDataSource.totalCount();
    if (total <= 0) {
      return false;
    }
    let idx = -1;
    for (let i = 0; i < total; i++) {
      const node = this.flowDataSource.getData(i);
      if ((node.kind === 'month' || node.kind === 'day') && node.year === year && node.month === month) {
        idx = i;
        break;
      }
    }
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
   * 时间轴松手后：程序化 scrollToIndex 完成前 onScrollIndex / Scroller.yOffset 常仍停在旧状态，
   * loadVisible 会误对准「上一屏」；按滑块目标年月在 flow 中定位首个 row（否则月/日头），强行刷新 listVisible*。
   */
  private syncListVisibleRoughToTimelineSliderTarget(): void {
    const ym = this.resolveYearMonthByTimelineRatio(this.timelineSliderRatio);
    if (ym === null) {
      return;
    }
    const total = this.flowDataSource.totalCount();
    if (total <= 0) {
      return;
    }
    let firstIdx = -1;
    for (let i = 0; i < total; i++) {
      const node = this.flowDataSource.getData(i);
      if (node.year === ym.year && node.month === ym.month && node.kind === 'row') {
        firstIdx = i;
        break;
      }
    }
    if (firstIdx < 0) {
      for (let i = 0; i < total; i++) {
        const node = this.flowDataSource.getData(i);
        if (node.year === ym.year && node.month === ym.month && (node.kind === 'month' || node.kind === 'day')) {
          firstIdx = i;
          break;
        }
      }
    }
    if (firstIdx < 0) {
      return;
    }
    const span = 56;
    const lastIdx = Math.min(total - 1, Math.max(firstIdx, firstIdx + span));
    this.listVisibleFirstNodeIdx = firstIdx;
    this.listVisibleLastNodeIdx = lastIdx;
    this.refreshLastKnownGlobalSlotsFromListIndices(firstIdx, lastIdx);
    this.captureListScrollIndexAnchor();
  }

  /** 按比例估算滚动（用于拖动中跟手反馈） */
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

  /** 松手后按目标比例对齐（可见则精确，不可见先估算） */
  private seekTimelineListToDisplayRatio(ratio: number): void {
    // 程序化跳转会瞬间改变 yOffset，与旧 onScrollIndex 锚点不可比，避免 loadVisible 用错增量
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

  /** 背景监视：目标月出现后再精确 scrollToIndex，确保拖到底能到最早日期 */
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

  /** 用 firstVisibleIndex 精确同步时间轴（避免高度估算误差导致标签回顶） */
  private syncTimelineSliderFromFirstIndex(firstIdx: number): void {
    const ymList = this.getTimelineYearMonths();
    const total = this.flowDataSource.totalCount();
    if (ymList.length === 0 || total <= 0 || firstIdx < 0) {
      return;
    }
    const clamped = Math.min(firstIdx, total - 1);
    let year = -1;
    let month = -1;
    for (let i = clamped; i >= 0; i--) {
      const node = this.flowDataSource.getData(i);
      if ((node.kind === 'month' || node.kind === 'day') && node.year > 0 && node.month > 0) {
        year = node.year;
        month = node.month;
        break;
      }
    }
    if (year < 0) {
      return;
    }
    let idx = -1;
    for (let i = 0; i < ymList.length; i++) {
      if (ymList[i].year === year && ymList[i].month === month) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return;
    }
    const ratio = ymList.length > 1 ? idx / (ymList.length - 1) : 0;
    // 微小变化不更新 @State，减少手柄层细碎重绘
    if (Math.abs(ratio - this.timelineSliderRatio) < 0.01 && idx === this.timelineSidebarHighlightIndex) {
      return;
    }
    this.timelineSliderRatio = ratio;
    this.timelineSidebarHighlightIndex = idx;
    const th = Math.max(80, this.timelineScrubTrackHeightVp);
    this.timelineIndicatorY = this.timelineIndicatorYForRatio(th, ratio);
  }

  private getCurrentHighlightYear(): number {
    const ymList = this.getTimelineYearMonths();
    if (ymList.length === 0) {
      return new Date().getFullYear();
    }
    const idx = Math.max(0, Math.min(ymList.length - 1, this.timelineSidebarHighlightIndex));
    return ymList[idx].year;
  }

  private getCurrentHighlightMonth(): number {
    const ymList = this.getTimelineYearMonths();
    if (ymList.length === 0) {
      return new Date().getMonth() + 1;
    }
    const idx = Math.max(0, Math.min(ymList.length - 1, this.timelineSidebarHighlightIndex));
    return ymList[idx].month;
  }

  /** 与列表锚点对齐的「日」：从当前可见首节点向前找最近的 day/row 节点 */
  private getCurrentHighlightDay(): number {
    const total = this.flowDataSource.totalCount();
    if (total <= 0) {
      return new Date().getDate();
    }
    const anchor = Math.max(0, Math.min(this.listVisibleFirstNodeIdx, total - 1));
    for (let i = anchor; i >= 0; i--) {
      const n = this.flowDataSource.getData(i);
      if (n.year > 0 && n.month > 0 && n.day > 0 && (n.kind === 'day' || n.kind === 'row')) {
        return n.day;
      }
    }
    return new Date().getDate();
  }

  /** 时间轴展开气泡：完整年月日（不设 maxWidth，避免被截成「2…」） */
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

  /** 与 buildTimelineSidebar 内滑块/气泡纵向位置一致，随轨道高度缩放 */
  private timelineIndicatorYForRatio(thRaw: number, ratio: number): number {
    const th = Math.max(thRaw, GALLERY_TIMELINE_INDICATOR_RESERVED_VP + 40);
    const span = Math.max(th - GALLERY_TIMELINE_INDICATOR_RESERVED_VP, 40);
    return GALLERY_TIMELINE_INDICATOR_PAD_VP + ratio * span;
  }

  /** 计算某天某 offset 在“全量时间轴照片序列”中的全局下标 */
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

  /** 根据全局照片下标反查所属天与天内 offset */
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

  /** 统计在 nodeIdx 之前共有多少“照片槽位”（真实 + skeleton） */
  private countPhotoSlotsBeforeNode(nodeIdx: number): number {
    const totalNodes = this.flowDataSource.totalCount();
    const end = Math.max(0, Math.min(totalNodes, nodeIdx));
    let acc = 0;
    for (let i = 0; i < end; i++) {
      const n = this.flowDataSource.getData(i);
      if (n.kind === 'row') {
        acc += n.rowSlotItems.length;
      }
    }
    return acc;
  }

  /** orderedDays[0..dayIdx) 的全局槽位前缀和 */
  private globalSlotIndexAtDayStart(dayIdx: number): number {
    let acc = 0;
    const lim = Math.max(0, Math.min(dayIdx, this.orderedDays.length));
    for (let i = 0; i < lim; i++) {
      acc += Math.max(0, this.orderedDays[i].itemCount);
    }
    return acc;
  }

  /**
   * 根据 List 可见节点区间刷新「全局照片槽位」缓存；只要存在 row 即写入，供 loadVisible 在 vis 退化时使用。
   */
  private refreshLastKnownGlobalSlotsFromListIndices(firstIdx: number, lastIdx: number): void {
    const totalNodes = this.flowDataSource.totalCount();
    if (totalNodes <= 0) {
      return;
    }
    let first = Math.max(0, Math.min(totalNodes - 1, firstIdx));
    let last = Math.max(first, Math.min(totalNodes - 1, lastIdx));
    let visStart = this.countPhotoSlotsBeforeNode(first);
    let visEndExclusive = this.countPhotoSlotsBeforeNode(last + 1);
    if (visEndExclusive <= visStart) {
      let rowIdx = -1;
      for (let i = first; i <= last; i++) {
        const n = this.flowDataSource.getData(i);
        if (n.kind === 'row') {
          rowIdx = i;
          break;
        }
      }
      if (rowIdx < 0) {
        for (let i = first; i < totalNodes; i++) {
          const n = this.flowDataSource.getData(i);
          if (n.kind === 'row') {
            rowIdx = i;
            break;
          }
        }
      }
      if (rowIdx >= 0) {
        visStart = this.countPhotoSlotsBeforeNode(rowIdx);
        visEndExclusive = Math.max(visStart + 1, this.countPhotoSlotsBeforeNode(rowIdx + 1));
      }
    }
    if (visEndExclusive > visStart) {
      const newSpan = visEndExclusive - visStart;
      const prevStart = this.lastKnownGlobalPhotoSlotStart;
      const prevEnd = this.lastKnownGlobalPhotoSlotEndExclusive;
      const prevSpan = prevEnd - prevStart;
      if (prevSpan >= GALLERY_LAST_KNOWN_MIN_PREV_SLOT_SPAN &&
        newSpan < GALLERY_LAST_KNOWN_DEGENERATE_NEW_SLOT_SPAN &&
        newSpan * GALLERY_LAST_KNOWN_SHRINK_IGNORE_RATIO < prevSpan) {
        return;
      }
      this.lastKnownGlobalPhotoSlotStart = visStart;
      this.lastKnownGlobalPhotoSlotEndExclusive = visEndExclusive;
    }
  }

  private captureListScrollIndexAnchor(): void {
    try {
      const off = this.scrollerRef.currentOffset();
      const yRaw = off.yOffset;
      const y = typeof yRaw === 'number' && Number.isFinite(yRaw) ? Math.max(0, yRaw) : 0;
      this.listScrollIndexAnchorYVp = y;
      this.listScrollIndexAnchorFirst = Math.max(0, this.listVisibleFirstNodeIdx);
      this.listScrollIndexAnchorHave = true;
    } catch (_e) {
      this.listScrollIndexAnchorHave = false;
    }
  }

  private approxGalleryFlowListNodeHeightVp(node: GalleryFlowNode): number {
    if (node.kind === 'month') {
      return GALLERY_LIST_APPROX_MONTH_NODE_VP;
    }
    if (node.kind === 'day') {
      return GALLERY_LIST_APPROX_DAY_NODE_VP;
    }
    return GALLERY_LIST_APPROX_ROW_NODE_VP;
  }

  /** 自 anchorFirst 起向下「吃掉」deltaVp 内容位移后，近似的首可见节点下标 */
  /**
   * 由 List 顶部累计近似高度，估算 yVp 处对应的首个节点下标（与 Scroller.yOffset 同向）。
   * 仅作 refine 下界，步数封顶避免超长列表单次 O(n)。
   */
  private estimateFirstVisibleNodeIndexFromScrollY(yVp: number, total: number): number {
    if (total <= 0 || !Number.isFinite(yVp) || yVp <= 0.5) {
      return 0;
    }
    const minByOffset = Math.ceil(yVp / 16) + 8000;
    const maxWalk = Math.min(total, GALLERY_SCROLL_Y_ESTIMATE_MAX_NODES, Math.max(16000, minByOffset));
    let cum = 0;
    for (let i = 0; i < maxWalk; i++) {
      const step = Math.max(1, this.approxGalleryFlowListNodeHeightVp(this.flowDataSource.getData(i)));
      if (cum + step > yVp) {
        return i;
      }
      cum += step;
    }
    if (cum <= yVp) {
      if (maxWalk < total) {
        const remain = yVp - cum;
        const guess = Math.max(1, GALLERY_LIST_APPROX_ROW_NODE_VP);
        const extra = Math.min(total - 1 - maxWalk, Math.max(0, Math.ceil(remain / guess)));
        return Math.min(total - 1, maxWalk + extra);
      }
      return total - 1;
    }
    return Math.max(0, maxWalk - 1);
  }

  private consumeVerticalScrollDeltaAsNodeIndex(startIdx: number, deltaVp: number): number {
    const total = this.flowDataSource.totalCount();
    if (total <= 0 || deltaVp <= 0.5) {
      return Math.max(0, Math.min(Math.max(0, total - 1), startIdx));
    }
    let i = Math.max(0, Math.min(total - 1, startIdx));
    let budget = deltaVp;
    let it = 0;
    while (i < total - 1 && budget > 0.5) {
      it++;
      if (it > GALLERY_SCROLL_DELTA_CONSUME_MAX_IT) {
        const guess = GALLERY_LIST_APPROX_ROW_NODE_VP;
        const extra = Math.min(total - 1 - i, Math.max(0, Math.ceil(budget / guess)));
        i += extra;
        break;
      }
      const h = this.approxGalleryFlowListNodeHeightVp(this.flowDataSource.getData(i));
      const step = Math.max(1, h);
      if (budget <= step) {
        break;
      }
      budget -= step;
      i++;
    }
    return Math.min(total - 1, i);
  }

  /**
   * 与 consumeVerticalScrollDeltaAsNodeIndex 对称：y 减小（列表内容向上滚、看较新一侧）时，
   * 从锚点节点向上消费 deltaVp 的近似高度，得到更小的首可见节点下标。
   */
  private consumeVerticalScrollDeltaAsNodeIndexBackward(startIdx: number, deltaVp: number): number {
    const total = this.flowDataSource.totalCount();
    if (total <= 0 || deltaVp <= 0.5) {
      return Math.max(0, Math.min(Math.max(0, total - 1), startIdx));
    }
    let i = Math.max(0, Math.min(total - 1, startIdx));
    let budget = deltaVp;
    let it = 0;
    while (i > 0 && budget > 0.5) {
      it++;
      if (it > GALLERY_SCROLL_DELTA_CONSUME_MAX_IT) {
        const guess = GALLERY_LIST_APPROX_ROW_NODE_VP;
        const extra = Math.min(i, Math.max(0, Math.ceil(budget / guess)));
        i -= extra;
        break;
      }
      const h = this.approxGalleryFlowListNodeHeightVp(this.flowDataSource.getData(i - 1));
      const step = Math.max(1, h);
      if (budget <= step) {
        break;
      }
      budget -= step;
      i--;
    }
    return Math.max(0, i);
  }

  /**
   * 用 Scroller 纵向偏移相对「上次 onScrollIndex 锚点」的增量，把声称的 first/last 向前推，
   * 缓解 ArkUI List + LazyForEach 下索引回调滞后于真实视口的问题。
   */
  private refineVisibleNodeIndicesAgainstScrollLag(claimedFirst: number, claimedLast: number): GalleryVisibleNodeRange {
    const totalNodes = this.flowDataSource.totalCount();
    if (totalNodes <= 0) {
      return { first: 0, last: 0 };
    }
    let cf = Math.max(0, Math.min(totalNodes - 1, claimedFirst));
    let cl = Math.max(cf, Math.min(totalNodes - 1, claimedLast));

    let yNow = 0;
    try {
      const off = this.scrollerRef.currentOffset();
      const yRaw = off.yOffset;
      yNow = typeof yRaw === 'number' && Number.isFinite(yRaw) ? Math.max(0, yRaw) : 0;
    } catch (_e) {
      yNow = 0;
    }
    const estFromY = this.estimateFirstVisibleNodeIndexFromScrollY(yNow, totalNodes);

    if (this.listScrollIndexAnchorHave) {
      const angDr = Math.abs(this.listScrollIndexAnchorFirst - estFromY);
      if (angDr > GALLERY_REFINE_ANCHOR_RESYNC_NODE_DRIFT) {
        this.listScrollIndexAnchorYVp = yNow;
        this.listScrollIndexAnchorFirst = Math.max(0, Math.min(totalNodes - 1, estFromY));
      }
    }

    if (!this.listScrollIndexAnchorHave) {
      const drift = Math.abs(cf - estFromY);
      const driftTh = Math.max(3500, Math.min(12000, Math.floor(totalNodes / 4)));
      const first0 = drift > driftTh ? estFromY : Math.max(cf, estFromY);
      const span0 = Math.max(Math.max(0, cl - cf), GALLERY_REFINE_MIN_VISIBLE_NODE_SPAN);
      const last0 = Math.min(totalNodes - 1, Math.max(cl, first0 + span0));
      return { first: Math.min(totalNodes - 1, first0), last: Math.max(first0, last0) };
    }

    const deltaRaw = yNow - this.listScrollIndexAnchorYVp;
    // 阈值略放宽：过窄时长期落在微动分支。注意 loadVisible 开头 capture 后常出现 deltaRaw≈0，若仍走「deltaRaw<0 ? min : max」
    // 会在 deltaRaw===0 时误用 max(cf,est)（偏更大首索引），上滑看较新一侧时加载窗长期偏下，屏内骨架永远不拉。
    if (Math.abs(deltaRaw) <= 8) {
      const span0 = Math.max(Math.max(0, cl - cf), GALLERY_REFINE_MIN_VISIBLE_NODE_SPAN);
      let first0: number;
      if (Math.abs(deltaRaw) <= 1.0) {
        const driftCe = Math.abs(cf - estFromY);
        first0 =
          driftCe > GALLERY_REFINE_EST_ADV_MAX_DRIFT_NODES ? estFromY : cf;
      } else if (deltaRaw < 0) {
        first0 = Math.min(cf, estFromY);
      } else {
        first0 = Math.max(cf, estFromY);
      }
      const last0 = Math.min(totalNodes - 1, Math.max(cl, first0 + span0));
      return { first: Math.min(totalNodes - 1, first0), last: Math.max(first0, last0) };
    }
    const span = Math.max(Math.max(0, cl - cf), GALLERY_REFINE_MIN_VISIBLE_NODE_SPAN);
    let first2: number;
    if (deltaRaw > 1) {
      const adv = this.consumeVerticalScrollDeltaAsNodeIndex(this.listScrollIndexAnchorFirst, deltaRaw);
      const advC = Math.min(totalNodes - 1, Math.max(0, adv));
      const estUse =
        Math.abs(estFromY - advC) > GALLERY_REFINE_EST_ADV_MAX_DRIFT_NODES ? advC : estFromY;
      first2 = Math.max(cf, advC, estUse);
    } else {
      const adv = this.consumeVerticalScrollDeltaAsNodeIndexBackward(this.listScrollIndexAnchorFirst, -deltaRaw);
      const advC = Math.min(totalNodes - 1, Math.max(0, adv));
      const estUse =
        Math.abs(estFromY - advC) > GALLERY_REFINE_EST_ADV_MAX_DRIFT_NODES ? advC : estFromY;
      // 与下滑对称：下滑 max(cf,adv,est) 偏向更大首索引；上滑 min(cf,adv,est) 偏向更小首索引
      first2 = Math.max(0, Math.min(cf, advC, estUse));
    }
    const last2 = Math.min(totalNodes - 1, Math.max(cl, first2 + span));
    return { first: first2, last: Math.max(first2, last2) };
  }

  /** 统计 [first,last] 节点区间内 row 里仍为骨架（null）的照片槽位数，用于按屏内占位扩展拉取范围 */
  private countSkeletonPhotoSlotsInFlowNodeRange(first: number, last: number): number {
    const total = this.flowDataSource.totalCount();
    if (total <= 0) {
      return 0;
    }
    const f = Math.max(0, Math.min(total - 1, first));
    const l = Math.max(f, Math.min(total - 1, last));
    let c = 0;
    for (let i = f; i <= l; i++) {
      const n = this.flowDataSource.getData(i);
      if (n.kind !== 'row') {
        continue;
      }
      for (let k = 0; k < n.rowSlotItems.length; k++) {
        const s = n.rowSlotItems[k];
        if (s === null || s === undefined) {
          c++;
        }
      }
    }
    return c;
  }

  /** 下方全局槽位缓冲：保底 + 按当前窗口内骨架槽位数放大（上限 cap） */
  private computeLoadVisibleBufferAfterSlots(aggressive: boolean, scanFirst: number, scanLast: number): number {
    const sk = this.countSkeletonPhotoSlotsInFlowNodeRange(scanFirst, scanLast);
    const base = aggressive ? GALLERY_LOAD_VISIBLE_BUFFER_BASE_AGGRESSIVE : GALLERY_LOAD_VISIBLE_BUFFER_BASE_NON_AGGRESSIVE;
    const extra = Math.min(GALLERY_LOAD_VISIBLE_BUFFER_AFTER_CAP, sk * GALLERY_LOAD_VISIBLE_SKELETON_SLOT_MULTIPLIER);
    return Math.max(base, extra);
  }

  /**
   * 滚动静止后按可视区触发“日级优先加载”：
   * - 若 Scroller.getVisibleRange 可用：以返回区间为唯一可见节点窗，**跳过 refine**，再映射到全局槽位并扩展 buffer（与 RecyclerView 首末可见项驱动加载一致）；
   * - 否则仍走 refine + y 反推兜底；
   * - 反查目标日，若当前 dayIndex 落后则前移到目标日并启动 pumpLoad。
   *
   * 注意：现有 sections 结构是“前缀连续真实数据”，不能安全跳 offset（会打乱映射），
   * 因此此处仅做“按天抢占”而不直接改 dayOffsets 到中间页。
   */
  private loadVisibleItemsThrottled(forceImmediate: boolean = false, aggressive: boolean = false): void {
    const now = Date.now();
    if (!forceImmediate && now - this.lastLoadVisibleAtMs < 300) {
      if (this.isInScrollInteractiveLogWindow()) {
        this.logScrollDebug('loadVisible throttled');
      }
      return;
    }
    this.lastLoadVisibleAtMs = now;
    if (this.bootLoading || this.orderedDays.length === 0 || this.visualPlaceholderMode || this.isDraggingOrFling) {
      if (GALLERY_SCROLL_DEBUG_LOG) {
        this.logScrollDebug(
          `loadVisible skip: boot=${this.bootLoading ? 1 : 0}, days=${this.orderedDays.length}, `
          + `placeholder=${this.visualPlaceholderMode ? 1 : 0}, dragFling=${this.isDraggingOrFling ? 1 : 0}`
        );
      }
      return;
    }
    const totalNodes = this.flowDataSource.totalCount();
    if (totalNodes <= 0) {
      return;
    }
    /**
     * LazyForEach + 全量骨架下 onScrollIndex 滞后：若 Scroller 提供 getVisibleRange，则刷新 listVisible* 并重捕锚点。
     * 命中时后续 **不再跑 refine**（与 RecyclerView findFirstVisibleItemPosition 同源，避免 y 反推/锚点消费叠在 API 上制造细缝）。
     */
    let loadVisibleUsedScrollerRange = false;
    if (this.tryApplyScrollerVisibleRangeIfAvailable(totalNodes)) {
      loadVisibleUsedScrollerRange = true;
      this.refreshLastKnownGlobalSlotsFromListIndices(this.listVisibleFirstNodeIdx, this.listVisibleLastNodeIdx);
      this.captureListScrollIndexAnchor();
    }
    let refFirst = Math.max(0, Math.min(totalNodes - 1, this.listVisibleFirstNodeIdx));
    let refLast = Math.max(refFirst, Math.min(totalNodes - 1, this.listVisibleLastNodeIdx));
    /**
     * 时间轴松手（aggressive）：programmatic seek 后 onScrollIndex 常仍指向 seek 前的旧可见区，
     * 若此处继续用 List 换算的 visStart，会把 dayIndex 拉回旧月份，表现为直松手不出图、要多滑一大段才追上。
     * 因此激进路径一律以滑块比例对齐后的全局槽位为准。
     */
    let visStart = 0;
    let visEndExclusive = 0;
    let usedAggressiveTimelineAnchor = false;
    if (aggressive && this.alignPumpToTimelineSliderTarget()) {
      visStart = this.lastKnownGlobalPhotoSlotStart;
      visEndExclusive = this.lastKnownGlobalPhotoSlotEndExclusive;
      usedAggressiveTimelineAnchor = visEndExclusive > visStart;
    }
    if (!usedAggressiveTimelineAnchor) {
      let refinedFirst: number;
      let refinedLast: number;
      if (loadVisibleUsedScrollerRange) {
        refinedFirst = Math.max(0, Math.min(totalNodes - 1, this.listVisibleFirstNodeIdx));
        refinedLast = Math.max(refinedFirst, Math.min(totalNodes - 1, this.listVisibleLastNodeIdx));
      } else {
        const refined = this.refineVisibleNodeIndicesAgainstScrollLag(this.listVisibleFirstNodeIdx, this.listVisibleLastNodeIdx);
        refinedFirst = refined.first;
        refinedLast = refined.last;
      }
      const firstNode = Math.max(0, Math.min(totalNodes - 1, refinedFirst));
      const lastNode = Math.max(firstNode, Math.min(totalNodes - 1, refinedLast));
      refFirst = firstNode;
      refLast = lastNode;
      visStart = this.countPhotoSlotsBeforeNode(firstNode);
      visEndExclusive = this.countPhotoSlotsBeforeNode(lastNode + 1);
      if (visEndExclusive <= visStart) {
        if (this.lastKnownGlobalPhotoSlotEndExclusive > this.lastKnownGlobalPhotoSlotStart) {
          visStart = this.lastKnownGlobalPhotoSlotStart;
          visEndExclusive = this.lastKnownGlobalPhotoSlotEndExclusive;
        }
      }
      if (visEndExclusive <= visStart) {
        this.refreshLastKnownGlobalSlotsFromListIndices(refinedFirst, refinedLast);
        if (this.lastKnownGlobalPhotoSlotEndExclusive > this.lastKnownGlobalPhotoSlotStart) {
          visStart = this.lastKnownGlobalPhotoSlotStart;
          visEndExclusive = this.lastKnownGlobalPhotoSlotEndExclusive;
        }
      }
      if (visEndExclusive <= visStart) {
        // 仍无效：时间轴松手用滑块目标对齐；否则只能等下次可见区刷新
        if (aggressive && this.alignPumpToTimelineSliderTarget() && !this.loadingMore && !this.exhausted) {
          const epoch = this.pumpEpoch;
          this.pumpLoad(true);
          setTimeout((): void => {
            if (epoch !== this.pumpEpoch || this.isDraggingOrFling || this.visualPlaceholderMode) {
              return;
            }
            this.pumpLoad(true);
          }, 40);
        }
        return;
      }
    }
    // 骨架缓冲扫描区间：Scroller 可见区命中时只做固定 prefetch margin（同行做法）；否则才用 y 反推扩展。
    let bufferScanFirst = refFirst;
    let bufferScanLast = refLast;
    if (!usedAggressiveTimelineAnchor) {
      if (loadVisibleUsedScrollerRange) {
        bufferScanFirst = Math.max(0, refFirst - GALLERY_LOAD_VISIBLE_SCROLLER_RANGE_PAD_NODES);
        bufferScanLast = Math.min(totalNodes - 1, refLast + GALLERY_LOAD_VISIBLE_SCROLLER_RANGE_PAD_NODES);
        bufferScanLast = Math.max(bufferScanFirst, bufferScanLast);
      } else {
        let yVis = 0;
        try {
          const off2 = this.scrollerRef.currentOffset();
          const yRaw2 = off2.yOffset;
          yVis = typeof yRaw2 === 'number' && Number.isFinite(yRaw2) ? Math.max(0, yRaw2) : 0;
        } catch (_e2) {
          yVis = 0;
        }
        const estNode = this.estimateFirstVisibleNodeIndexFromScrollY(yVis, totalNodes);
        if (estNode < refFirst) {
          const visLo = this.countPhotoSlotsBeforeNode(estNode);
          if (visLo < visStart) {
            visStart = visLo;
          }
        }
        bufferScanFirst = Math.max(0, Math.min(refFirst, estNode));
        const winNodes = Math.max(GALLERY_LOAD_VISIBLE_BUFFER_SCAN_WIN_NODES, refLast - refFirst + 1);
        const estLastHint = Math.min(totalNodes - 1, Math.max(refLast, estNode + winNodes - 1));
        bufferScanLast = Math.min(totalNodes - 1, Math.max(refLast, estLastHint));
        bufferScanLast = Math.max(bufferScanFirst, bufferScanLast);
      }
    }
    const bufferSlots = this.computeLoadVisibleBufferAfterSlots(aggressive, bufferScanFirst, bufferScanLast);
    const start = Math.max(0, visStart - bufferSlots);
    const end = Math.max(start, visEndExclusive - 1 + bufferSlots);
    const startHit = this.resolveDayByGlobalIndex(start);
    if (startHit === null) {
      if (this.isInScrollInteractiveLogWindow()) {
        this.logScrollDebug(
          `loadVisible miss: start=${start}, end=${end}, listFirst=${this.listVisibleFirstNodeIdx}, `
          + `listLast=${this.listVisibleLastNodeIdx}, timelineAnchor=${usedAggressiveTimelineAnchor ? 1 : 0}`
        );
      }
      return;
    }
    // 日级抢占：对齐到当前可视区所在日。原先非 aggressive 每次最多 dayIndex+1，会导致长时间在「上一屏」上方按天泵数据。
    if (startHit.dayIdx !== this.lastVisibleLoadDayIdx || startHit.dayIdx !== this.dayIndex) {
      const nextIdx = startHit.dayIdx;
      this.dayIndex = nextIdx;
      this.lastVisibleLoadDayIdx = nextIdx;
      if (this.isInScrollInteractiveLogWindow()) {
        this.logScrollDebug(`loadVisible jump dayIndex -> ${nextIdx} (target=${startHit.dayIdx}, start=${start}, end=${end})`);
      }
    }
    // 激进恢复：把该日请求 offset 直接对齐到可视 dayOffset，优先填充“当前页”
    if (aggressive && this.dayIndex >= 0 && this.dayIndex < this.orderedDays.length) {
      const d = this.orderedDays[this.dayIndex];
      const k = dayKey(d.year, d.month, d.day);
      const alignedStart = Math.max(0, startHit.dayOffset);
      const curOff = this.dayOffsets.get(k) ?? 0;
      if (curOff !== alignedStart) {
        this.dayOffsets.set(k, alignedStart);
        if (this.isInScrollInteractiveLogWindow()) {
          this.logScrollDebug(`loadVisible align day offset -> ${alignedStart} (dayOffset=${startHit.dayOffset})`);
        }
      }
    }
    const endHit = this.resolveDayByGlobalIndex(end);
    if (endHit === null) {
      return;
    }
    const loD = startHit.dayIdx;
    const hiD = endHit.dayIdx;
    const spanDays = hiD - loD;

    if (!this.loadingMore && !this.exhausted) {
      if (this.isInScrollInteractiveLogWindow()) {
        this.logScrollDebug(
          `loadVisible trigger ${aggressive ? 'continuous' : 'single-batch'} pump: `
          + `dayIndex=${this.dayIndex}, start=${start}, end=${end}, spanDays=${spanDays}`
        );
      }
      // 视口 [start,end] 跨多日且每日仅少量槽位时：只泵首日会长期只出一张图；按日各拉一批覆盖窗口内多日。
      if (spanDays > 0) {
        const epochBand = this.pumpEpoch;
        void this.pumpVisibleDayBandAllChunks(loD, hiD, start, end, epochBand);
      } else if (aggressive) {
        const epoch = this.pumpEpoch;
        this.pumpLoad(true);
        // 松手恢复补第二批：优先把当前可视区补满，避免“附近有图、页内缺图”
        setTimeout((): void => {
          if (epoch !== this.pumpEpoch || this.isDraggingOrFling || this.visualPlaceholderMode) {
            return;
          }
          this.pumpLoad(true);
        }, 40);
      } else {
        this.pumpLoad(true);
        const skFollow = this.countSkeletonPhotoSlotsInFlowNodeRange(refFirst, refLast);
        if (skFollow >= 6) {
          const epochSk = this.pumpEpoch;
          setTimeout((): void => {
            if (epochSk !== this.pumpEpoch || this.isDraggingOrFling || this.visualPlaceholderMode) {
              return;
            }
            this.pumpLoad(true);
          }, 24);
        }
      }
    }
  }

  /**
   * 跨日窗口可能远大于 GALLERY_LOAD_VISIBLE_MULTI_DAY_CHAIN_MAX；单段只泵前 N 天会在屏上形成「载一段、空一段」条纹。
   * 按固定块顺序泵完整个 [loD, hiD]（块间仍受 epoch / 交互态 gate）。
   */
  private async pumpVisibleDayBandAllChunks(
    loD: number,
    hiD: number,
    startG: number,
    endG: number,
    epoch: number
  ): Promise<void> {
    let curLo = Math.max(0, loD);
    const hiCap = Math.max(curLo, Math.min(hiD, this.orderedDays.length - 1));
    while (curLo <= hiCap) {
      if (epoch !== this.pumpEpoch || this.exhausted || this.bootLoading) {
        return;
      }
      if (this.visualPlaceholderMode || this.isDraggingOrFling) {
        return;
      }
      const hiChunk = Math.min(hiCap, curLo + GALLERY_LOAD_VISIBLE_MULTI_DAY_CHAIN_MAX - 1);
      await this.pumpVisibleDayBandSequential(curLo, hiChunk, startG, endG, epoch);
      curLo = hiChunk + 1;
    }
  }

  /**
   * 可见槽位区间跨多个日历日时，对窗口内涉及的每个日顺序各请求一批，并在进入该日前把 offset 对齐到与 [startG,endG] 重叠的起点。
   */
  private async pumpVisibleDayBandSequential(
    loDayIdx: number,
    hiDayIdx: number,
    startG: number,
    endG: number,
    epoch: number
  ): Promise<void> {
    if (this.visualPlaceholderMode || this.isDraggingOrFling) {
      return;
    }
    const lo = Math.max(0, loDayIdx);
    const hi = Math.max(lo, Math.min(hiDayIdx, this.orderedDays.length - 1));
    for (let d = lo; d <= hi; d++) {
      if (epoch !== this.pumpEpoch || this.exhausted || this.bootLoading) {
        return;
      }
      if (this.visualPlaceholderMode || this.isDraggingOrFling) {
        return;
      }
      let waitGuard = 0;
      while (this.loadingMore && waitGuard < 120) {
        await new Promise<void>((resolve) => setTimeout(resolve, 30));
        waitGuard++;
        if (epoch !== this.pumpEpoch) {
          return;
        }
      }
      if (this.loadingMore) {
        return;
      }

      const day = this.orderedDays[d];
      const k = dayKey(day.year, day.month, day.day);
      const g0 = this.globalSlotIndexAtDayStart(d);
      const g1 = g0 + Math.max(0, day.itemCount);
      if (endG < g0 || startG >= g1) {
        continue;
      }
      const overlapStart = Math.max(startG, g0);
      const localNeed = Math.min(Math.max(0, overlapStart - g0), Math.max(0, day.itemCount - 1));
      const curOff = this.dayOffsets.get(k) ?? 0;
      if (localNeed > curOff) {
        this.dayOffsets.set(k, localNeed);
      }

      this.dayIndex = d;
      this.lastVisibleLoadDayIdx = d;

      const gen = this.loadGen;
      this.loadingMore = true;
      let added = 0;
      try {
        added = await this.loadOneBatch();
      } finally {
        this.loadingMore = false;
      }

      if (epoch !== this.pumpEpoch || gen !== this.loadGen) {
        return;
      }
      if (added === -1) {
        return;
      }
      if (added === -2) {
        const e2 = this.pumpEpoch;
        setTimeout((): void => {
          if (e2 !== this.pumpEpoch || this.isDraggingOrFling || this.visualPlaceholderMode) {
            return;
          }
          this.pumpLoad(true);
        }, 3000);
        return;
      }
      if (added === -3) {
        const e3 = this.pumpEpoch;
        setTimeout((): void => {
          if (e3 !== this.pumpEpoch || this.isDraggingOrFling || this.visualPlaceholderMode) {
            return;
          }
          this.pumpLoad(true);
        }, 500);
        return;
      }

      await new Promise<void>((resolve) => setTimeout(resolve, added > 0 ? PUMP_UI_GAP_MS : 2));
    }
  }

  private loadVisibleItems(): void {
    this.loadVisibleItemsThrottled();
  }

  private loadVisibleItemsImmediate(): void {
    this.lastLoadVisibleAtMs = 0;
    // 时间轴松手恢复用：绕过节流 + 激进对齐 + 连续泵，确保“立即开始出图”
    this.loadVisibleItemsThrottled(true, true);
  }

  /**
   * 时间轴松手后的主动恢复：不依赖用户再滑动，直接拉起可视区加载。
   * 双阶段触发用于覆盖「程序化 seek 尚未完成可见区回传」窗口。
   */
  private kickPostTimelineReleaseLoad(): void {
    this.flushPendingFlowRebuild();
    this.syncListVisibleRoughToTimelineSliderTarget();
    this.loadVisibleItemsImmediate();
    // 若可见区索引尚未就绪，loadVisible 可能只走了时间轴对齐分支；再兜底一次 pump
    if (!this.loadingMore && !this.exhausted && !this.bootLoading) {
      this.pumpLoad(true);
    }
    const epoch = this.pumpEpoch;
    setTimeout((): void => {
      if (epoch !== this.pumpEpoch || this.timelineSidebarDragging || this.isDraggingOrFling) {
        return;
      }
      this.flushPendingFlowRebuild();
      this.syncListVisibleRoughToTimelineSliderTarget();
      this.loadVisibleItemsImmediate();
      if (!this.loadingMore && !this.exhausted && !this.bootLoading) {
        this.pumpLoad(true);
      }
    }, 120);
  }

  private endTimelineDrag(): void {
    this.cancelTimelineDragWatchdog();
    this.timelineDragWatchdogGen++;
    // 程序化 seek 期间屏蔽列表滚动对冻结态的回写（短窗）
    this.ignoreListFreezeUntilMs = Date.now() + 900;
    // 先释放拖动态，避免 placeholder 长时间锁住导致停手后不出图
    this.timelineSidebarDragging = false;
    this.timelinePressing = false;
    this.timelineLongPressExpanded = false;
    this.refreshVisualPlaceholderMode();
    this.timelineSeekInProgress = true;
    this.seekTimelineListToDisplayRatio(this.timelineSliderRatio);
    const ym = this.resolveYearMonthByTimelineRatio(this.timelineSliderRatio);
    if (ym !== null && !this.flowHasVisibleYearMonth(ym.year, ym.month)) {
      this.startTimelineSeekWatchdog(ym.year, ym.month);
    }
    setTimeout((): void => {
      this.timelineSeekInProgress = false;
      this.isDraggingOrFling = false;
      this.listKineticScrolling = false;
      this.visualPlaceholderMode = false;
      // seek 刚结束的一小段时间继续屏蔽回写，确保主动恢复链路先跑起来
      this.ignoreListFreezeUntilMs = Date.now() + 600;
      this.refreshVisualPlaceholderMode();
      // 结束拖动后主动拉起加载，不依赖用户再滑动
      this.kickPostTimelineReleaseLoad();
      this.runMainListScrollSettledWork();
      this.showTimelineBar();
    }, 120);
  }

  @Builder
  private buildTimelineSidebar() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.timelineScrubExpandedChrome()) {
        ForEach(this.getYearMarkersForTrack(), (marker: YearMarker) => {
          Text(`${marker.year}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.gallery_timeline_year_badge_fg'))
            .backgroundColor($r('app.color.gallery_timeline_year_badge_bg'))
            .padding({ left: 5, right: 5, top: 3, bottom: 3 })
            .borderRadius(4)
            .position({ x: GALLERY_TIMELINE_YEAR_BADGE_X_VP, y: marker.y - 9 })
        }, (m: YearMarker) => `ym_${m.year}`)
      }

      Column()
        .width(this.timelineScrubExpandedChrome()
          ? (this.timelineSidebarDragging ? GALLERY_TIMELINE_RAIL_DRAG_VP : GALLERY_TIMELINE_RAIL_EXPANDED_VP)
          : GALLERY_TIMELINE_RAIL_MIN_VP)
        .height('100%')
        .backgroundColor(this.timelineSidebarDragging
          ? $r('app.color.gallery_timeline_rail_drag')
          : (this.timelineScrubExpandedChrome()
            ? $r('app.color.gallery_timeline_rail_expanded')
            : $r('app.color.gallery_timeline_rail')))
        .borderRadius(3)
        .position({
          x: this.timelineScrubExpandedChrome()
            ? (this.timelineSidebarDragging
              ? GALLERY_TIMELINE_HIT_WIDTH_VP - GALLERY_TIMELINE_RAIL_DRAG_VP
              : GALLERY_TIMELINE_HIT_WIDTH_VP - GALLERY_TIMELINE_RAIL_EXPANDED_VP)
            : GALLERY_TIMELINE_HIT_WIDTH_VP - GALLERY_TIMELINE_RAIL_MIN_VP,
          y: 0
        })
        .animation({ duration: 180, curve: Curve.EaseOut })

      // 列表滚动时的「系统滚动条替身」：细轨 + 滑块位置点；长按或拖动后显示完整 scrub
      if (this.timelineScrubScrollRailOnly()) {
        Circle()
          .width(GALLERY_TIMELINE_THUMB_VP)
          .height(GALLERY_TIMELINE_THUMB_VP)
          .fill($r('app.color.gallery_timeline_thumb_fill'))
          .stroke($r('app.color.gallery_timeline_thumb_border'))
          .strokeWidth(1.5)
          .position({
            x: GALLERY_TIMELINE_HIT_WIDTH_VP - GALLERY_TIMELINE_RAIL_MIN_VP - GALLERY_TIMELINE_THUMB_VP + 1,
            y: Math.max(
              GALLERY_TIMELINE_INDICATOR_PAD_VP,
              this.timelineIndicatorY - GALLERY_TIMELINE_THUMB_VP / 2
            )
          })
      }

      if (this.timelineScrubExpandedChrome()) {
        Text(this.getTimelineScrubPillLabel())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.timelineSidebarDragging
            ? $r('app.color.button_primary_fg')
            : $r('app.color.gallery_timeline_month_pill_fg'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(GALLERY_TIMELINE_SCRUB_PILL_MIN_WIDTH_VP)
          .textAlign(TextAlign.Center)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.timelineSidebarDragging
            ? $r('app.color.brand_primary')
            : $r('app.color.gallery_timeline_month_pill_bg'))
          .borderRadius(12)
          .position({ x: GALLERY_TIMELINE_SCRUB_PILL_X_VP, y: Math.max(6, this.timelineIndicatorY - 20) })
          .scale({
            x: this.timelineSidebarDragging ? 1.15 : 1.0,
            y: this.timelineSidebarDragging ? 1.15 : 1.0
          })
          .animation({ duration: 180, curve: Curve.EaseOut })
          .gesture(
            TapGesture().onAction((): void => {
              this.seekTimelineListToDisplayRatio(this.timelineSliderRatio);
            })
          )
      }
    }
    .width(GALLERY_TIMELINE_HIT_WIDTH_VP)
    .height('100%')
    .clip(false)
    .onAreaChange((_: Area, area: Area): void => {
      const h = area.height as number;
      if (h > 1) {
        this.timelineScrubTrackHeightVp = h;
      }
    })
    .onTouch((event: TouchEvent): void => {
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
    })
    .parallelGesture(
      GestureGroup(GestureMode.Parallel,
        LongPressGesture({ repeat: false, duration: GALLERY_TIMELINE_LONG_PRESS_EXPAND_MS })
          .onAction((): void => {
            if (!this.timelineSidebarDragging) {
              this.timelineLongPressExpanded = true;
              this.showTimelineBar();
            }
          }),
        PanGesture({ direction: PanDirection.Vertical, distance: 2 })
          .onActionStart((_event: GestureEvent): void => {
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
          })
          .onActionUpdate((event: GestureEvent): void => {
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
            this.timelineSidebarHighlightIndex = Math.max(0, Math.min(ymList.length - 1, Math.round(ratio * (ymList.length - 1))));
            this.timelineIndicatorY = this.timelineIndicatorYForRatio(th, ratio);
            // 视觉冻结策略：拖动过程中不实时滚动主列表，松手后一次性 seek 对齐并批量恢复图片。
            this.armTimelineDragWatchdog();
          })
          .onActionEnd((_event: GestureEvent): void => {
            this.endTimelineDrag();
          })
          .onActionCancel((_event: GestureEvent): void => {
            this.endTimelineDrag();
          })
      )
    )
    .opacity(
      this.timelineSidebarDragging || this.timelinePressing || this.timelineLongPressExpanded || this.timelineBarVisible ? 1 : 0
    )
    .animation({ duration: 280, curve: Curve.EaseInOut })
  }

  private openPreview(flatIndex: number): void {
    if (flatIndex < 0) {
      return;
    }
    GalleryPreviewNavStore.openPreview(this.baseUrl, this.flatItems(), flatIndex);
  }

  /** 以条目 id 对齐 flatItems 顺序，避免 rowSlotFlatIndices 与 flatItems 短暂不一致时「缩略图与预览不是同一张」 */
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
   * 主时间线 List + LazyForEach 的 item key。
   * row 必须把「槽位是否已有 flat / 真实项」编进 key：仅 `rebuildFlow` 替换 `rowSlotItems` 时若 `node.key` 不变，
   * 框架会复用子树而不重跑 item 构建，骨架格不会换成 GalleryNetworkThumb，表现为只有滑动后才「加载」。
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
   * 判断两组 id 是否作为集合相同（顺序无关），避免划选合并时仅顺序变化也触发整表刷新。
   * 使用 Set 计数，避免大图选区下 O(n log n) 排序。
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
   * 统一写入选中 id 列表并维护 Set；集合与当前相同时跳过赋值，减少无效 @State 刷新。
   */
  private setGallerySelectedIdsState(next: string[]): void {
    if (this.sameGalleryIdBagUnordered(this.gallerySelectedIds, next)) {
      return;
    }
    this.gallerySelectedIds = next;
  }

  /** 列表滚动后清空命中矩形，避免离屏项残留旧坐标导致误选 */
  private clearGalleryThumbHitBounds(): void {
    this.galleryThumbHitBounds.clear();
  }

  /**
   * 生成 getRectangleById / id() 可用的 DOM 标识（仅字母数字与下划线，避免非法 id）。
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
   * 在布局变化后刷新该缩略图在窗口中的矩形，供「长按后滑动」连选做相交判断。
   * 优先使用官方 componentUtils.getRectangleById（与指尖 window 坐标一致）。
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
      // 预览器或未挂载完成时可能抛错，连选降级为仅依赖长按起点
    }
  }

  /**
   * 从手势事件读取指尖位置（不同版本字段名不同）。
   * 数值单位多为 vp（逻辑像素），需与 getRectangleById 返回的 px 在 resolveSlidePointerWindowPx 中统一。
   */
  private readGestureFingerWindow(ev: GestureEvent): GalleryFingerWindowPoint | null {
    const fl = ev.fingerList;
    if (fl === undefined || fl.length < 1) {
      return null;
    }
    const f0 = fl[0] as GalleryFingerCoordCompat;
    const x = f0.windowX ?? f0.globalX ?? f0.screenX ?? f0.displayX ?? f0.x;
    const y = f0.windowY ?? f0.globalY ?? f0.screenY ?? f0.displayY ?? f0.y;
    if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
      return null;
    }
    const out: GalleryFingerWindowPoint = { x: x, y: y };
    return out;
  }

  /**
   * PanGesture.offsetX/Y 为 vp；getRectangleById 为 px。将位移从 vp 换算到 px，与命中矩形一致。
   */
  private panOffsetVpToPx(deltaVp: number): number {
    const probePx = 100;
    const probeVp = px2vp(probePx);
    if (probeVp < 0.0001) {
      return deltaVp;
    }
    return deltaVp * (probePx / probeVp);
  }

  /**
   * 长按判定成功后：进入划选段，关闭 List 滚动，记录锚点 flat 与已有选中集，供「行优先连续区间」实时并集。
   */
  private beginGallerySlideSelectGesture(ev: GestureEvent, item: GalleryListItem, anchorFlat: number): void {
    this.gallerySlideGestureActive = true;
    this.galleryMainListScrollEnabled = false;
    this.gallerySlideAnchorFlat = anchorFlat >= 0 ? anchorFlat : -1;
    this.gallerySlideUnionBase = this.gallerySelectedIds.slice();
    this.gallerySlideLastEndFlat = this.gallerySlideAnchorFlat;
    this.gallerySlideLastAppliedEndFlat = -99999;
    const anchorId = this.itemIdOf(item);
    if (this.inSearchMode) {
      this.recordSearchThumbRect(anchorFlat);
    } else if (anchorId.length > 0) {
      this.recordGalleryThumbRectFromDom(anchorId, this.galleryThumbDomId(anchorId));
    }
    const win = this.readGestureFingerWindow(ev);
    if (win !== null) {
      // FingerInfo 通常为 vp，与 componentUtils 矩形（px）对齐
      this.gallerySlideRefX = vp2px(win.x);
      this.gallerySlideRefY = vp2px(win.y);
      this.gallerySlideHasRef = true;
    } else if (this.inSearchMode) {
      const rs = this.searchThumbHitBounds.get(`${anchorFlat}`);
      if (rs !== undefined) {
        this.gallerySlideRefX = (rs.left + rs.right) * 0.5;
        this.gallerySlideRefY = (rs.top + rs.bottom) * 0.5;
        this.gallerySlideHasRef = true;
      } else {
        this.gallerySlideHasRef = false;
      }
    } else if (anchorId.length > 0) {
      const r = this.galleryThumbHitBounds.get(anchorId);
      if (r !== undefined) {
        this.gallerySlideRefX = (r.left + r.right) * 0.5;
        this.gallerySlideRefY = (r.top + r.bottom) * 0.5;
        this.gallerySlideHasRef = true;
      } else {
        this.gallerySlideHasRef = false;
      }
    } else {
      this.gallerySlideHasRef = false;
    }
    // 长按当下即按「锚点～锚点」区间刷新一次，与后续 Pan 实时更新规则一致
    this.applyGallerySlideRowRangeSelection(this.gallerySlideLastEndFlat);
  }

  /** 划选段结束：恢复 List 滚动、清空划选临时状态，允许 onDidScroll 再次清空命中缓存 */
  private endGallerySlideSelectGesture(): void {
    // 已处于干净状态时直接返回，避免对 @State 的冗余写入引发不必要的重渲染
    if (!this.gallerySlideGestureActive && this.galleryMainListScrollEnabled) {
      return;
    }
    this.gallerySlideGestureActive = false;
    this.gallerySlideHasRef = false;
    this.gallerySlideAnchorFlat = -1;
    this.gallerySlideUnionBase = [];
    this.gallerySlideLastEndFlat = -1;
    this.gallerySlideLastAppliedEndFlat = -99999;
    this.galleryMainListScrollEnabled = true;
  }

  /**
   * 将当前划选指针统一到窗口像素坐标，与 getRectangleById 一致。
   */
  private resolveSlidePointerWindowPx(ev: GestureEvent): GalleryFingerWindowPoint | null {
    const win = this.readGestureFingerWindow(ev);
    if (win !== null) {
      const px: GalleryFingerWindowPoint = { x: vp2px(win.x), y: vp2px(win.y) };
      return px;
    }
    if (!this.gallerySlideHasRef) {
      return null;
    }
    const out: GalleryFingerWindowPoint = {
      x: this.gallerySlideRefX + this.panOffsetVpToPx(ev.offsetX),
      y: this.gallerySlideRefY + this.panOffsetVpToPx(ev.offsetY)
    };
    return out;
  }

  /**
   * 用 getRectangleById 判断点是否落在单张缩略图内（仅限本行少量调用，禁止在全列表 Pan 每帧里扫）。
   */
  private hitGalleryThumbDomPx(photoId: string, xPx: number, yPx: number): boolean {
    if (photoId.length === 0) {
      return false;
    }
    try {
      const domId = this.galleryThumbDomId(photoId);
      const info = this.getUIContext().getComponentUtils().getRectangleById(domId);
      const left = info.windowOffset.x as number;
      const top = info.windowOffset.y as number;
      const w = info.size.width as number;
      const h = info.size.height as number;
      if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
        return false;
      }
      return xPx >= left && xPx <= left + w && yPx >= top && yPx <= top + h;
    } catch (_e) {
      return false;
    }
  }

  /**
   * 根据指尖窗口坐标命中缩略图 flat；仅使用 onAreaChange 写入的 galleryThumbHitBounds。
   * 划选 Pan 的连续更新请用 pickGalleryThumbFlatUnderPointForSlide（缓存被清空后仍会 DOM 回退）。
   * 自后向前扫 row，与后绘制的格在上层一致。
   */
  private pickGalleryThumbFlatUnderPoint(xPx: number, yPx: number): number {
    if (this.inSearchMode) {
      return this.pickSearchThumbFlatUnderPoint(xPx, yPx);
    }
    if (this.galleryThumbHitBounds.size === 0) {
      return -1;
    }
    const n = this.flowDataSource.totalCount();
    for (let i = n - 1; i >= 0; i--) {
      const node = this.flowDataSource.getData(i);
      if (node.kind !== 'row') {
        continue;
      }
      for (let k = node.rowSlotItems.length - 1; k >= 0; k--) {
        const slot = node.rowSlotItems[k];
        if (slot === null || slot === undefined) {
          continue;
        }
        const id = this.itemIdOf(slot);
        if (id.length === 0) {
          continue;
        }
        const cached = this.galleryThumbHitBounds.get(id);
        if (cached === undefined) {
          continue;
        }
        if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
          return node.rowSlotFlatIndices[k];
        }
      }
    }
    return -1;
  }

  /**
   * 划选 Pan 命中：先缓存；缺失时在锚点/终点附近的少量行内做 DOM（每帧预算），避免全表 getRectangleById 卡死主线程。
   */
  private pickGalleryThumbFlatUnderPointForSlide(xPx: number, yPx: number): number {
    const fromCache = this.pickGalleryThumbFlatUnderPoint(xPx, yPx);
    if (fromCache >= 0) {
      return fromCache;
    }
    const seed = this.gallerySlideLastEndFlat >= 0 ? this.gallerySlideLastEndFlat : this.gallerySlideAnchorFlat;
    const nFlow = this.flowDataSource.totalCount();
    let domBudget = GALLERY_SLIDE_DOM_BUDGET_PER_FRAME;

    const tryRowNode = (node: GalleryFlowNode): number => {
      if (node.kind !== 'row') {
        return -1;
      }
      for (let k = node.rowSlotItems.length - 1; k >= 0; k--) {
        const slot = node.rowSlotItems[k];
        if (slot === null || slot === undefined) {
          continue;
        }
        const id = this.itemIdOf(slot);
        if (id.length === 0) {
          continue;
        }
        const flat = node.rowSlotFlatIndices[k];
        const cached = this.galleryThumbHitBounds.get(id);
        if (cached !== undefined &&
          xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
          return flat;
        }
        if (domBudget <= 0) {
          continue;
        }
        domBudget--;
        if (this.hitGalleryThumbDomPx(id, xPx, yPx)) {
          this.recordGalleryThumbRectFromDom(id, this.galleryThumbDomId(id));
          return flat;
        }
      }
      return -1;
    };

    if (seed >= 0) {
      let centerRi = -1;
      for (let i = 0; i < nFlow; i++) {
        const node = this.flowDataSource.getData(i);
        if (node.kind !== 'row') {
          continue;
        }
        for (let k = 0; k < node.rowSlotItems.length; k++) {
          if (node.rowSlotFlatIndices[k] === seed) {
            centerRi = i;
            break;
          }
        }
        if (centerRi >= 0) {
          break;
        }
      }
      const loR = centerRi >= 0 ? Math.max(0, centerRi - GALLERY_SLIDE_FLOW_ROW_RADIUS) : 0;
      const hiR = centerRi >= 0 ? Math.min(nFlow - 1, centerRi + GALLERY_SLIDE_FLOW_ROW_RADIUS) : nFlow - 1;
      for (let ri = hiR; ri >= loR; ri--) {
        const hit = tryRowNode(this.flowDataSource.getData(ri));
        if (hit >= 0) {
          return hit;
        }
      }
    }

    domBudget = GALLERY_SLIDE_DOM_BUDGET_PER_FRAME;
    let tailRows = 0;
    for (let ri = nFlow - 1; ri >= 0 && tailRows < GALLERY_SLIDE_TAIL_FLOW_ROWS; ri--) {
      const node = this.flowDataSource.getData(ri);
      if (node.kind !== 'row') {
        continue;
      }
      tailRows++;
      const hit = tryRowNode(node);
      if (hit >= 0) {
        return hit;
      }
    }
    return -1;
  }

  private pickSearchThumbFlatUnderPointForSlide(xPx: number, yPx: number): number {
    return pickIndexedFlatForSlidePointer(
      xPx,
      yPx,
      this.searchResults.length,
      this.gallerySlideLastEndFlat,
      this.gallerySlideAnchorFlat,
      (ax: number, ay: number): number => this.pickSearchThumbFlatUnderPoint(ax, ay),
      (fi: number) => this.searchThumbHitBounds.get(`${fi}`),
      (fi: number, ax: number, ay: number): boolean => this.hitSearchThumbDomPx(fi, ax, ay),
      (fi: number): void => {
        this.recordSearchThumbRect(fi);
      }
    );
  }

  /**
   * 长按 / Pan 起点：先走全局缓存命中，失败则只对**当前行**最多 3 格做 getRectangleById（恢复「长按启动多选 + 划选」且不把 DOM 查询放进 Pan 每帧）。
   */
  private pickGalleryThumbFlatForRowOrCache(node: GalleryFlowNode, xPx: number, yPx: number): number {
    const fromCache = this.pickGalleryThumbFlatUnderPoint(xPx, yPx);
    if (fromCache >= 0) {
      return fromCache;
    }
    if (node.kind !== 'row') {
      return -1;
    }
    for (let k = node.rowSlotItems.length - 1; k >= 0; k--) {
      const slot = node.rowSlotItems[k];
      if (slot === null || slot === undefined) {
        continue;
      }
      const id = this.itemIdOf(slot);
      if (id.length === 0) {
        continue;
      }
      const cached = this.galleryThumbHitBounds.get(id);
      if (cached !== undefined) {
        if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
          return node.rowSlotFlatIndices[k];
        }
        continue;
      }
      if (this.hitGalleryThumbDomPx(id, xPx, yPx)) {
        return node.rowSlotFlatIndices[k];
      }
    }
    return -1;
  }

  /**
   * 收集扁平下标闭区间 [lo, hi]（行优先）内所有缩略图 id。
   * 直接按 sections 推进 flat，跳过整段早于 lo 的日，超过 hi 即停，避免每次扫全 flow。
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
    return `sg_${flatIdx}`;
  }

  private recordSearchThumbRect(flatIdx: number): void {
    if (flatIdx < 0 || flatIdx >= this.searchResults.length) {
      return;
    }
    try {
      const info = this.getUIContext().getComponentUtils().getRectangleById(this.searchThumbDomId(flatIdx));
      const x = info.windowOffset.x as number;
      const y = info.windowOffset.y as number;
      const w = info.size.width as number;
      const h = info.size.height as number;
      if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
        this.searchThumbHitBounds.delete(`${flatIdx}`);
        return;
      }
      const rect: GalleryThumbHitRect = {
        left: x,
        top: y,
        right: x + w,
        bottom: y + h
      };
      this.searchThumbHitBounds.set(`${flatIdx}`, rect);
    } catch (_e) {
    }
  }

  private hitSearchThumbDomPx(flatIdx: number, xPx: number, yPx: number): boolean {
    if (flatIdx < 0 || flatIdx >= this.searchResults.length) {
      return false;
    }
    try {
      const info = this.getUIContext().getComponentUtils().getRectangleById(this.searchThumbDomId(flatIdx));
      const left = info.windowOffset.x as number;
      const top = info.windowOffset.y as number;
      const w = info.size.width as number;
      const h = info.size.height as number;
      if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
        return false;
      }
      return xPx >= left && xPx <= left + w && yPx >= top && yPx <= top + h;
    } catch (_e) {
      return false;
    }
  }

  private pickSearchThumbFlatUnderPoint(xPx: number, yPx: number): number {
    const n = this.searchResults.length;
    if (this.searchThumbHitBounds.size === 0 || n <= 0) {
      return -1;
    }
    for (let i = n - 1; i >= 0; i--) {
      const cached = this.searchThumbHitBounds.get(`${i}`);
      if (cached === undefined) {
        continue;
      }
      if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
        return i;
      }
    }
    return -1;
  }

  private pickSearchThumbFlatForRow(rowStart: number, xPx: number, yPx: number): number {
    const n = this.searchResults.length;
    const fromCache = this.pickSearchThumbFlatUnderPoint(xPx, yPx);
    if (fromCache >= rowStart && fromCache < rowStart + 3 && fromCache < n) {
      return fromCache;
    }
    for (let k = 2; k >= 0; k--) {
      const fi = rowStart + k;
      if (fi >= n) {
        continue;
      }
      const cached = this.searchThumbHitBounds.get(`${fi}`);
      if (cached !== undefined) {
        if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
          return fi;
        }
        continue;
      }
      if (this.hitSearchThumbDomPx(fi, xPx, yPx)) {
        return fi;
      }
    }
    return -1;
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

  private searchRowCount(): number {
    const n = this.searchResults.length;
    return n <= 0 ? 0 : Math.floor((n + 2) / 3);
  }

  private searchRowIndexArray(): number[] {
    const c = this.searchRowCount();
    const out: number[] = [];
    for (let i = 0; i < c; i++) {
      out.push(i);
    }
    return out;
  }

  /**
   * 以行为基数的划选：选中集 = 进入划选前已有选中 ∪ 锚点 flat～终点 flat 的连续区间（含中间整行）。
   * 终点由指尖下那张缩略图决定；指尖离开格子时沿用 gallerySlideLastEndFlat，避免闪烁。
   */
  private applyGallerySlideRowRangeSelection(endFlat: number): void {
    if (this.gallerySlideAnchorFlat < 0) {
      return;
    }
    const ef = endFlat >= 0 ? endFlat : this.gallerySlideAnchorFlat;
    // 划选拖拽过程中：终点 flat 未变则不必重算、不写 @State，显著降低卡顿
    if (this.gallerySlideGestureActive && ef === this.gallerySlideLastAppliedEndFlat) {
      return;
    }
    let lo = this.gallerySlideAnchorFlat;
    let hi = ef;
    if (lo > hi) {
      const t = lo;
      lo = hi;
      hi = t;
    }
    const rangeIds = this.inSearchMode
      ? this.collectSearchIdsInFlatRange(lo, hi)
      : this.collectGalleryIdsInFlatRange(lo, hi);
    const seen = new Set<string>();
    const base = this.gallerySlideUnionBase;
    for (let i = 0; i < base.length; i++) {
      seen.add(base[i]);
    }
    const next: string[] = base.slice();
    for (let i = 0; i < rangeIds.length; i++) {
      const id = rangeIds[i];
      if (id.length > 0 && !seen.has(id)) {
        seen.add(id);
        next.push(id);
      }
    }
    this.gallerySlideLastAppliedEndFlat = ef;
    this.setGallerySelectedIdsState(next);
  }

  /**
   * Parallel 下 Pan 可能在长按触发前就收到 update，必须等 begin 后再处理。
   * 实时写入 gallerySelectedIds，按「行优先 flat 连续区间」扩选。
   */
  private onGallerySlidePanUpdate(ev: GestureEvent): void {
    if (!this.gallerySlideGestureActive) {
      return;
    }
    const pt = this.resolveSlidePointerWindowPx(ev);
    if (pt === null) {
      return;
    }
    const hitFlat = this.inSearchMode ?
      this.pickSearchThumbFlatUnderPointForSlide(pt.x, pt.y) :
      this.pickGalleryThumbFlatUnderPointForSlide(pt.x, pt.y);
    if (hitFlat >= 0) {
      this.gallerySlideLastEndFlat = hitFlat;
    }
    this.applyGallerySlideRowRangeSelection(this.gallerySlideLastEndFlat);
  }

  /**
   * 是否已选（供 UI 绑定）。
   * 必须直接读 @State gallerySelectedIds，不可仅用普通字段 Set 判断，否则 ArkUI 无法建立依赖，
   * 会出现顶栏「已选择 x 张」变化而缩略图勾/遮罩不重绘的问题。
   */
  private isGalleryIdSelected(id: string): boolean {
    return id.length > 0 && this.gallerySelectedIds.indexOf(id) >= 0;
  }

  private toggleGallerySelectedId(id: string): void {
    if (id.length === 0) {
      return;
    }
    const idx = this.gallerySelectedIds.indexOf(id);
    if (idx >= 0) {
      const next: string[] = [];
      for (let i = 0; i < this.gallerySelectedIds.length; i++) {
        if (i !== idx) {
          next.push(this.gallerySelectedIds[i]);
        }
      }
      this.setGallerySelectedIdsState(next);
    } else {
      const next: string[] = this.gallerySelectedIds.slice();
      next.push(id);
      this.setGallerySelectedIdsState(next);
    }
    // 已选可为 0：仍保持多选模式，由顶栏「取消」显式退出（与系统相册一致）
  }

  /** 长按进入多选/在多选下切换当前项；划选进行中忽略，避免与 Pan 抢逻辑 */
  private onGalleryThumbLongPress(item: GalleryListItem): void {
    const id = this.itemIdOf(item);
    if (id.length === 0) {
      this.toast('该媒体无 ID，无法多选');
      return;
    }
    if (this.gallerySlideGestureActive) {
      return;
    }
    this.galleryLongPressIgnoreClickUntil = Date.now() + 500;
    if (!this.gallerySelectionMode) {
      playGalleryEnterSelectionHaptic();
      this.gallerySelectionMode = true;
      this.galleryTimelineRefreshing = false;
      this.setGallerySelectedIdsState([id]);
    } else {
      this.toggleGallerySelectedId(id);
    }
  }

  private onGalleryThumbTap(item: GalleryListItem, flatIndex: number): void {
    if (Date.now() < this.galleryLongPressIgnoreClickUntil) {
      return;
    }
    if (this.gallerySelectionMode) {
      const id = this.itemIdOf(item);
      if (id.length > 0) {
        this.toggleGallerySelectedId(id);
      }
      return;
    }
    const idx = this.resolveGalleryFlatIndexForOpenPreview(item, flatIndex);
    this.openPreview(idx);
  }

  private onSearchThumbTap(item: GalleryListItem, flatIndex: number): void {
    if (Date.now() < this.galleryLongPressIgnoreClickUntil) {
      return;
    }
    if (this.gallerySelectionMode) {
      const id = this.itemIdOf(item);
      if (id.length > 0) {
        this.toggleGallerySelectedId(id);
      }
      return;
    }
    if (flatIndex < 0 || flatIndex >= this.searchResults.length) {
      return;
    }
    GalleryPreviewNavStore.openPreview(this.baseUrl, this.searchResults, flatIndex);
  }

  /** 批量移入回收站：逐条调用现有 API，成功后 bump 时间轴并防抖刷新 */
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
   * 处理预览页删除同步：增量删行；若同时存在 GalleryTimelineRefreshStore bump，
   * 由 onAlbumTabVisibleAgain 再触发防抖后的全量 bootstrap，与时间轴对齐。
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
    // 主列表数据尚未完成 bootstrap 时，不提前消费删除版本号。
    if (this.sections.length === 0 && this.searchResults.length === 0) {
      return;
    }
    let changed = false;
    // 主图库 sections：删除命中的条目，并清理空 section
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
    // 搜索结果视图（若当前在搜索模式）也同步删除
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

  // ── 搜索 ──────────────────────────────────────────────────────────────────

  /** 执行 AI 语义搜索并展示结果 */
  private async runSearch(keyword: string): Promise<void> {
    const kw = keyword.trim();
    if (kw.length === 0) {
      return;
    }
    this.exitGallerySelection();
    this.playModeSwitchMotion();
    this.inSearchMode = true;
    this.inCategoryMode = false;
    this.inSmartCategoryMode = false;
    this.inPersonMode = false;
    this.searchLoading = true;
    this.searchError = '';
    this.searchResults = [];

    const client = AppSession.getClient();
    if (client === null) {
      this.searchError = '未登录';
      this.searchLoading = false;
      return;
    }
    try {
      const res = await client.doMagicSearch(kw);
      if (!res.success || res.data === undefined) {
        this.searchError = res.message ?? '搜索失败';
        this.searchLoading = false;
        return;
      }
      const rawList = res.data.list ?? [];
      this.searchResults = rawList.map((item: MagicSearchItem): GalleryListItem => {
        // 优先使用服务端返回的完整媒体条目（可正确识别视频/图片）
        const hasRichMedia =
          item.additional !== undefined ||
          item.thumbnail !== undefined ||
          item.category !== undefined ||
          item.fileType !== undefined;
        if (hasRichMedia) {
          return item as GalleryListItem;
        }
        // 兼容旧版 magic-search：仅有 id + session 时回退拼接缩略图 URL
        const id = item.id !== undefined ? String(item.id) : '';
        const session = item.session !== undefined ? item.session : '';
        if (id.length > 0 && session.length > 0) {
          const fallback: GalleryListItem = {
            id: id,
            thumb: `/p/api/v1/stream/p/t/${id}/s/${session}`
          };
          return fallback;
        }
        return item as GalleryListItem;
      });
      if (this.searchResults.length === 0) {
        this.searchError = '未找到相关媒体';
      }
    } catch (e) {
      this.searchError = String(e) || '搜索异常';
    }
    this.searchLoading = false;
  }

  /** 清除搜索，回到图库视图 */
  private clearSearch(): void {
    this.inSearchMode = false;
    this.searchQuery = '';
    this.searchResults = [];
    this.searchError = '';
    this.searchLoading = false;
  }

  private clearCategory(): void {
    this.inCategoryMode = false;
    this.categoryLoading = false;
    this.categoryError = '';
    this.categoryItems = [];
  }

  private clearSmartCategory(): void {
    this.inSmartCategoryMode = false;
    this.smartCategoryLoading = false;
    this.smartCategoryError = '';
    this.smartSceneItems = [];
    this.smartInfoItems = [];
  }

  private clearPerson(): void {
    this.inPersonMode = false;
    this.personLoading = false;
    this.personError = '';
    this.personItems = [];
  }

  private backToGallery(): void {
    this.exitGallerySelection();
    this.playModeSwitchMotion();
    this.clearSearch();
    this.clearCategory();
    this.clearSmartCategory();
    this.clearPerson();
    // 子视图期间若发生过 bump（删图/上传等），回到主时间线再补一次防抖刷新；无 bump 则不碰主列表，保留内存态
    if (GalleryTimelineRefreshStore.version > this.lastBootstrapSatisfiedRefreshVersion) {
      this.requestBootstrap(true);
    }
  }

  /** 系统返回键：子视图内先退回图库主界面 */
  private tryConsumeAlbumHardwareBack(): boolean {
    if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
      return false;
    }
    this.backToGallery();
    return true;
  }

  /** 统一模式切换动效，减少硬切感 */
  private playModeSwitchMotion(): void {
    this.getUIContext().animateTo(
      { duration: FN_TAB_SWITCH_OUT_DURATION, curve: FN_TAB_SWITCH_CURVE },
      (): void => {
        this.modeSwitchOpacity = 0.9;
        this.modeSwitchOffsetY = 10;
      }
    );
    setTimeout((): void => {
      this.getUIContext().animateTo(
        { duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE },
        (): void => {
          this.modeSwitchOpacity = 1;
          this.modeSwitchOffsetY = 0;
        }
      );
    }, 90);
  }

  private startUpload(): void {
    if (this.uploading) {
      return;
    }
    this.exitGallerySelection();
    void this.pickAndUpload();
  }

  private async pickAndUpload(): Promise<void> {
    const client = AppSession.getClient();
    if (client === null) {
      this.toast('未登录');
      return;
    }
    let uris: string[] = [];
    try {
      const opt = new picker.PhotoSelectOptions();
      opt.maxSelectNumber = 20;
      opt.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      const out = await new picker.PhotoViewPicker().select(opt);
      uris = out.photoUris ?? [];
    } catch (_e) {
      return;
    }
    if (uris.length === 0) {
      return;
    }
    this.uploading = true;
    this.uploadText = `上传中 0/${uris.length}…`;
    let ok = 0;
    let firstFailMsg = '';
    // 设置中的相册父目录：upload/path 无返回时作为 trim-path 目录，避免空路径被网关 400 拒绝
    const sUp = AppSession.getStored();
    const albumDirHint =
      sUp !== null && sUp.albumParentGuid.trim().length > 0 ? sUp.albumParentGuid.trim() : undefined;
    for (let i = 0; i < uris.length; i++) {
      this.uploadText = `上传中 ${i + 1}/${uris.length}…`;
      const res = await client.uploadPhotoByUri(uris[i], 150000, albumDirHint);
      if (res.success) {
        ok++;
      } else if (firstFailMsg.length === 0) {
        const em = res.message ?? '';
        firstFailMsg = em.length > 0 ? em : '上传失败';
      }
    }
    this.uploading = false;
    this.uploadText = '';
    if (ok > 0) {
      this.toast(`上传完成 ${ok}/${uris.length}`);
      GalleryTimelineRefreshStore.bump();
      this.requestBootstrap(false);
      setTimeout((): void => {
        void this.bootstrap(false);
      }, GALLERY_UPLOAD_RECHECK_MS);
    } else {
      this.toast(firstFailMsg.length > 0 ? firstFailMsg : '上传失败，请稍后重试');
    }
  }

  private parseCategoryMedia(item: MediaCategoryItem): GalleryListItem[] {
    const raw = item.list ?? item.items;
    if (!Array.isArray(raw)) {
      return [];
    }
    const out: GalleryListItem[] = [];
    for (let i = 0; i < raw.length; i++) {
      const it = raw[i];
      if (typeof it === 'object' && it !== null) {
        out.push(it as GalleryListItem);
      }
    }
    return out;
  }

  private categoryTitle(item: MediaCategoryItem): string {
    // normalizeCategoryItem 已将名称统一映射到 item.name
    const t = item.name ?? item.title ?? item.label;
    return t !== undefined && t.length > 0 ? t : '未命名分类';
  }

  private categoryCount(item: MediaCategoryItem): number {
    // normalizeCategoryItem 已将数量统一映射到 item.count
    const c = item.count ?? item.total;
    return c !== undefined && Number.isFinite(Number(c)) ? Math.max(0, Math.floor(Number(c))) : 0;
  }

  private categoryCover(item: MediaCategoryItem): string {
    // normalizeCategoryItem 已将封面 URL 统一映射到 item.cover
    if (item.cover !== undefined && item.cover.length > 0) {
      return item.cover;
    }
    if (item.thumb !== undefined && item.thumb.length > 0) {
      return item.thumb;
    }
    if (typeof item.thumbnail === 'string' && (item.thumbnail as string).length > 0) {
      return item.thumbnail as string;
    }
    if (typeof item.thumbnail === 'object' && item.thumbnail !== null) {
      const tb = item.thumbnail;
      const u = tb.mUrl ?? tb.sUrl ?? tb.xsUrl ?? tb.xxsUrl ?? tb.originalUrl;
      if (u !== undefined && u.length > 0) {
        return u;
      }
    }
    return '';
  }

  private async loadMediaCategories(): Promise<void> {
    this.exitGallerySelection();
    this.playModeSwitchMotion();
    this.inSearchMode = false;
    this.inCategoryMode = true;
    this.inSmartCategoryMode = false;
    this.inPersonMode = false;
    this.categoryLoading = true;
    this.categoryError = '';
    this.categoryItems = [];
    const client = AppSession.getClient();
    if (client === null) {
      this.categoryError = '未登录';
      this.categoryLoading = false;
      return;
    }
    try {
      const res = await client.getMediaCategoryList();
      if (!res.success || res.data === undefined) {
        this.categoryError = res.message ?? '媒体分类加载失败';
        this.categoryLoading = false;
        return;
      }
      const raw = res.data.list ?? res.data.items ?? [];
      const out: MediaCategoryItem[] = [];
      for (let i = 0; i < raw.length; i++) {
        const el = raw[i];
        if (typeof el === 'object' && el !== null) {
          out.push(el as MediaCategoryItem);
        }
      }
      this.categoryItems = out;
      if (out.length === 0) {
        this.categoryError = '暂无媒体分类（接口返回为空或字段不匹配）';
      }
    } catch (e) {
      this.categoryError = String(e) || '媒体分类加载异常';
    }
    this.categoryLoading = false;
  }

  private smartCategoryName(item: SmartCategoryItem): string {
    const n = item.name;
    return n !== undefined && n.length > 0 ? n : '未命名分类';
  }

  private smartCategoryCount(item: SmartCategoryItem): number {
    const directVals: Array<number | string | undefined> = [
      item.count,
      item.total,
      item.itemCount,
      item.item_count,
      item.photoCount,
      item.photo_count,
      item.num,
      item.size
    ];
    for (let i = 0; i < directVals.length; i++) {
      const v = directVals[i];
      if (typeof v === 'number' && Number.isFinite(v)) {
        return Math.max(0, Math.floor(v));
      }
      if (typeof v === 'string') {
        const n = Number(v);
        if (Number.isFinite(n)) {
          return Math.max(0, Math.floor(n));
        }
      }
    }
    return 0;
  }

  private smartCategoryCover(item: SmartCategoryItem): string {
    const p = item.poster;
    if (p === undefined || p === null) {
      return '';
    }
    const id = p.photoId !== undefined ? String(p.photoId) : '';
    const uuid = p.uuid !== undefined ? p.uuid : '';
    if (id.length === 0 || uuid.length === 0) {
      return '';
    }
    return `/p/api/v1/stream/p/t/${id}/s/${uuid}`;
  }

  private async loadSmartCategories(): Promise<void> {
    this.exitGallerySelection();
    this.playModeSwitchMotion();
    this.inSearchMode = false;
    this.inCategoryMode = false;
    this.inSmartCategoryMode = true;
    this.inPersonMode = false;
    this.smartCategoryLoading = true;
    this.smartCategoryError = '';
    this.smartSceneItems = [];
    this.smartInfoItems = [];
    const client = AppSession.getClient();
    if (client === null) {
      this.smartCategoryError = '未登录';
      this.smartCategoryLoading = false;
      return;
    }
    try {
      const pair = await Promise.all([
        client.getSmartRecCategories('scene', -1),
        client.getSmartRecCategories('information', -1)
      ]);
      const sceneRes = pair[0];
      const infoRes = pair[1];
      const sceneRaw = sceneRes.success && sceneRes.data !== undefined ? (sceneRes.data.list ?? sceneRes.data.items ?? []) : [];
      const infoRaw = infoRes.success && infoRes.data !== undefined ? (infoRes.data.list ?? infoRes.data.items ?? []) : [];
      const sceneOut: SmartCategoryItem[] = [];
      const infoOut: SmartCategoryItem[] = [];
      for (let i = 0; i < sceneRaw.length; i++) {
        const el = sceneRaw[i];
        if (typeof el === 'object' && el !== null) {
          sceneOut.push(el as SmartCategoryItem);
        }
      }
      for (let i = 0; i < infoRaw.length; i++) {
        const el = infoRaw[i];
        if (typeof el === 'object' && el !== null) {
          infoOut.push(el as SmartCategoryItem);
        }
      }
      this.smartSceneItems = sceneOut;
      this.smartInfoItems = infoOut;
      if (sceneOut.length === 0 && infoOut.length === 0) {
        this.smartCategoryError = '暂无智能分类（请先在系统设置中开启智能识别）';
      }
    } catch (e) {
      this.smartCategoryError = String(e) || '智能分类加载异常';
    }
    this.smartCategoryLoading = false;
  }

  private personName(item: AiPersonItem): string {
    const n = item.name ?? item.nickName;
    return n !== undefined && n.length > 0 ? n : '未命名人物';
  }

  private personFace(item: AiPersonItem): string {
    if (item.faceUrl !== undefined && item.faceUrl.length > 0) {
      return item.faceUrl;
    }
    const id = item.faceId ?? item.avatarId ?? item.posterId ?? item.coverId ?? item.id;
    if (id === undefined || id === null) {
      return '';
    }
    const idStr = String(id);
    return idStr.length > 0 ? `/p/api/v1/stream/face/${idStr}` : '';
  }

  private personId(item: AiPersonItem): string {
    const id = item.id;
    if (id === undefined || id === null) {
      return '';
    }
    return String(id);
  }

  private personStatText(item: AiPersonItem): string {
    const pid = this.personId(item);
    if (pid.length > 0) {
      const txt = this.personStatOverrides.get(pid);
      if (txt !== undefined && txt.length > 0) {
        return txt;
      }
    }
    const photoRaw = item.photoCount;
    const videoRaw = item.videoCount;
    const photo = photoRaw !== undefined && Number.isFinite(Number(photoRaw))
      ? Math.max(0, Math.floor(Number(photoRaw)))
      : -1;
    const video = videoRaw !== undefined && Number.isFinite(Number(videoRaw))
      ? Math.max(0, Math.floor(Number(videoRaw)))
      : -1;
    if (photo >= 0 || video >= 0) {
      const p = photo >= 0 ? photo : 0;
      const v = video >= 0 ? video : 0;
      return `${p} 张照片 · ${v} 个视频`;
    }
    const totalRaw = item.itemCount ?? item.count ?? item.total;
    const total = totalRaw !== undefined && Number.isFinite(Number(totalRaw))
      ? Math.max(0, Math.floor(Number(totalRaw)))
      : 0;
    return `共 ${total} 项`;
  }

  private async enrichPersonStats(items: AiPersonItem[], gen: number): Promise<void> {
    const client = AppSession.getClient();
    if (client === null) {
      return;
    }
    for (let i = 0; i < items.length; i++) {
      if (gen !== this.personStatGen) {
        return;
      }
      const pid = this.personId(items[i]);
      if (pid.length === 0) {
        continue;
      }
      if (this.personStatOverrides.has(pid)) {
        continue;
      }
      const one = await client.getAiPersonDetail(pid, 12000);
      if (gen !== this.personStatGen) {
        return;
      }
      if (!one.success || one.data === undefined) {
        continue;
      }
      const pRaw = one.data.photoCount;
      const vRaw = one.data.videoCount;
      if (!Number.isFinite(Number(pRaw)) && !Number.isFinite(Number(vRaw))) {
        continue;
      }
      const p = Number.isFinite(Number(pRaw)) ? Math.max(0, Math.floor(Number(pRaw))) : 0;
      const v = Number.isFinite(Number(vRaw)) ? Math.max(0, Math.floor(Number(vRaw))) : 0;
      this.personStatOverrides.set(pid, `${p} 张照片 · ${v} 个视频`);
      this.personStatVersion++;
    }
  }

  private async loadPersons(): Promise<void> {
    this.exitGallerySelection();
    this.playModeSwitchMotion();
    // 进入人物列表时先清理“打开人物媒体”遮罩状态，避免从主页进入误显示
    this.personOpening = false;
    this.inSearchMode = false;
    this.inCategoryMode = false;
    this.inSmartCategoryMode = false;
    this.inPersonMode = true;
    this.personLoading = true;
    this.personError = '';
    this.personItems = [];
    this.personStatOverrides.clear();
    this.personStatVersion++;
    this.personStatGen++;
    const client = AppSession.getClient();
    if (client === null) {
      this.personError = '未登录';
      this.personLoading = false;
      return;
    }
    try {
      const res = await client.getAiPersonList(true, -1, 0);
      if (!res.success || res.data === undefined) {
        this.personError = res.message ?? '人物列表加载失败';
        this.personLoading = false;
        return;
      }
      const raw = res.data.list ?? res.data.items ?? res.data.records ?? [];
      const out: AiPersonItem[] = [];
      for (let i = 0; i < raw.length; i++) {
        const el = raw[i];
        if (typeof el === 'object' && el !== null) {
          out.push(el as AiPersonItem);
        }
      }
      this.personItems = out;
      const gen = this.personStatGen;
      void this.enrichPersonStats(out, gen);
      if (out.length === 0) {
        this.personError = '暂无人物（请先在系统设置中开启智能识别）';
      }
    } catch (e) {
      this.personError = String(e) || '人物列表加载异常';
    }
    this.personLoading = false;
  }

  /** 打开人物图库：与 PersonPage / 预览详情人物行共用 PersonAlbumOpenHelper */
  private async openPerson(item: AiPersonItem): Promise<void> {
    if (this.personOpening) {
      return;
    }
    const pid = this.personId(item);
    if (pid.length === 0) {
      this.toast('人物 ID 无效');
      return;
    }
    this.personOpening = true;
    let keepOpening = false;
    try {
      const r = await openPersonAlbumById(
        this.baseUrl,
        pid,
        this.personName(item),
        this.getUIContext()
      );
      if (!r.ok) {
        if (r.errorMessage.length > 0) {
          this.toast(r.errorMessage);
        }
        return;
      }
      keepOpening = true;
      setTimeout((): void => {
        this.personOpening = false;
      }, 280);
    } finally {
      if (!keepOpening) {
        this.personOpening = false;
      }
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {
    }
  }

  private async openCategory(cat: MediaCategoryItem): Promise<void> {
    if (this.categoryOpening) {
      return;
    }
    this.categoryOpening = true;
    const catTitle = this.categoryTitle(cat);

    try {
      // 优先用分类项自带的媒体列表
      const local = this.parseCategoryMedia(cat);
      if (local.length > 0) {
        CategoryGalleryNavStore.open(this.baseUrl, catTitle, local, this.getUIContext());
        return;
      }
      const client = AppSession.getClient();
      if (client === null) {
        this.toast('未登录');
        return;
      }
      // 使用 search/results，首选 {keyword:"", filters:[{file_type}], antiFilters:[]} 格式
      const fetched = await client.searchResultsByCategory(cat);
      if (!fetched.success || fetched.data === undefined || fetched.data.length === 0) {
        this.toast(fetched.message ?? '该分类暂无可预览媒体');
        return;
      }
      CategoryGalleryNavStore.open(this.baseUrl, catTitle, fetched.data, this.getUIContext());
    } finally {
      this.categoryOpening = false;
    }
  }

  /**
   * 最近添加：按 explore/recent_timeline 分桶后逐日分页拉 recent_photos，
   * 聚合为平铺列表并复用 CategoryGallery 预览页打开。
   */
  private async openRecentAdded(): Promise<void> {
    if (this.recentOpening) {
      return;
    }
    const client = AppSession.getClient();
    if (client === null) {
      this.toast('未登录');
      return;
    }
    this.recentOpening = true;
    try {
      const tl = await client.getRecentTimeline();
      if (!tl.success || tl.data === undefined) {
        this.toast(tl.message ?? '最近添加时间轴加载失败');
        return;
      }
      const rawList = tl.data.list ?? [];
      const cellsIn: Array<Record<string, number | undefined>> = [];
      for (let i = 0; i < rawList.length; i++) {
        const el = rawList[i];
        if (typeof el === 'object' && el !== null) {
          cellsIn.push(el as Record<string, number | undefined>);
        }
      }
      const days = sortDaysDesc(parseTimelineDayCells(cellsIn)).filter(
        (d: TimelineDayModel): boolean => d.itemCount > 0
      );
      if (days.length === 0) {
        this.toast('最近添加暂无数据');
        return;
      }

      const merged: GalleryListItem[] = [];
      const seen = new Set<string>();
      for (let di = 0; di < days.length; di++) {
        const day = days[di];
        const st = fmtDayStart(day.year, day.month, day.day);
        const et = fmtDayEnd(day.year, day.month, day.day);
        let off = 0;
        let rounds = 0;
        for (;;) {
          const one = await client.getRecentPhotos(st, et, GALLERY_RECENT_PAGE_LIMIT, off, 'recent');
          if (!one.success || one.data === undefined) {
            break;
          }
          const list = listFromData(one.data);
          if (list.length <= 0) {
            break;
          }
          for (let i = 0; i < list.length; i++) {
            const it = list[i];
            const key = this.itemIdOf(it);
            // 优先以稳定 ID 去重；无 ID 时退化为缩略图地址去重，避免跨页重复展示
            const dedupKey = key.length > 0 ? key : (pickThumb(it).trim().length > 0 ? pickThumb(it).trim() : `${st}_${i}`);
            if (!seen.has(dedupKey)) {
              seen.add(dedupKey);
              merged.push(it);
            }
          }
          off += list.length;
          rounds++;
          if (list.length < GALLERY_RECENT_PAGE_LIMIT) {
            break;
          }
          if (day.itemCount > 0 && off >= day.itemCount) {
            break;
          }
          if (rounds >= GALLERY_RECENT_DAY_MAX_ROUNDS) {
            break;
          }
        }
      }

      if (merged.length <= 0) {
        this.toast('最近添加暂无可预览媒体');
        return;
      }
      CategoryGalleryNavStore.open(this.baseUrl, '最近添加', merged, this.getUIContext());
    } finally {
      this.recentOpening = false;
    }
  }

  /**
   * 收藏夹：GET gallery/timeline?is_collect=1 分日后，按日 GET getList（mode=collect & is_collect=1），
   * 与 Web /p/collect 抓包一致。
   */
  private async openCollectGallery(): Promise<void> {
    if (this.collectOpening) {
      return;
    }
    const client = AppSession.getClient();
    if (client === null) {
      this.toast('未登录');
      return;
    }
    this.collectOpening = true;
    try {
      const tl = await client.getCollectGalleryTimeline();
      if (!tl.success || tl.data === undefined) {
        this.toast(tl.message ?? '收藏时间轴加载失败');
        return;
      }
      const rawList = tl.data.list ?? [];
      const cellsIn: Array<Record<string, number | undefined>> = [];
      for (let i = 0; i < rawList.length; i++) {
        const el = rawList[i];
        if (typeof el === 'object' && el !== null) {
          cellsIn.push(el as Record<string, number | undefined>);
        }
      }
      const days = sortDaysDesc(parseTimelineDayCells(cellsIn)).filter(
        (d: TimelineDayModel): boolean => d.itemCount > 0
      );
      if (days.length === 0) {
        this.toast('暂无收藏');
        return;
      }

      const merged: GalleryListItem[] = [];
      const seen = new Set<string>();
      for (let di = 0; di < days.length; di++) {
        const day = days[di];
        const st = fmtDayStart(day.year, day.month, day.day);
        const et = fmtDayEnd(day.year, day.month, day.day);
        let off = 0;
        let rounds = 0;
        for (;;) {
          const one = await client.getCollectGalleryList(st, et, GALLERY_RECENT_PAGE_LIMIT, off);
          if (!one.success || one.data === undefined) {
            break;
          }
          const list = listFromData(one.data);
          if (list.length <= 0) {
            break;
          }
          for (let i = 0; i < list.length; i++) {
            const it = list[i];
            const key = this.itemIdOf(it);
            const dedupKey = key.length > 0 ? key : (pickThumb(it).trim().length > 0 ? pickThumb(it).trim() : `${st}_${i}`);
            if (!seen.has(dedupKey)) {
              seen.add(dedupKey);
              merged.push(it);
            }
          }
          off += list.length;
          rounds++;
          if (list.length < GALLERY_RECENT_PAGE_LIMIT) {
            break;
          }
          if (day.itemCount > 0 && off >= day.itemCount) {
            break;
          }
          if (rounds >= GALLERY_RECENT_DAY_MAX_ROUNDS) {
            break;
          }
        }
      }

      if (merged.length <= 0) {
        this.toast('收藏暂无可预览媒体');
        return;
      }
      CategoryGalleryNavStore.open(this.baseUrl, '收藏', merged, this.getUIContext());
    } finally {
      this.collectOpening = false;
    }
  }

  // ── 生命周期 ─────────────────────────────────────────────────────────────

  private onEpochChange(): void {
    setTimeout((): void => {
      this.requestBootstrap(false);
    }, 0);
  }

  private onPageShowSignal(): void {
    this.onAlbumTabVisibleAgain();
  }

  aboutToAppear(): void {
    // 页面重新出现时重置打开态，避免手势返回后被旧遮罩状态卡住
    this.personOpening = false;
    this.categoryOpening = false;
    this.recentOpening = false;
    this.collectOpening = false;
    gallerySetAlbumBackHandler((): boolean => this.tryConsumeAlbumHardwareBack());
    setTimeout((): void => {
      // 主时间线：若离开 Tab 时存过快照且期间未 bump/未强刷，直接恢复，避免每次切回都重拉时间轴与已加载块
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

  /** 切到其他底部 Tab 时卸载：把主时间线快照写入内存，供下次 aboutToAppear 恢复 */
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

  /** Map<string,number> → 平行数组，便于快照脱离引用（须用命名接口，满足 arkts-no-obj-literals-as-types） */
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
   * 构造可缓存的主时间线快照（仅主视图；不含搜索/分类/人物等子模式）。
   * 「时间轴暂无数据」也缓存，避免空结论反复打接口。
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

  /** 从内存快照恢复主时间线与泵状态（须已由 tryTakeRestore 校验版本与账号） */
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

  // ── sections 更新 ────────────────────────────────────────────────────────

  /** 已写入 sections 的媒体总数，用于区分「真·全部加载完」与「竞态/接口异常导致零条」 */
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
   * 请求重新拉时间轴并重建列表。
   * @param debounced true：用户连点「刷新」时合并为一次；false：首屏、父级 epoch、上传后立即执行。
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

  /** Home 前台信号或 Tab 再次显示：先增量删，再视 bump 防抖全量刷 */
  private onAlbumTabVisibleAgain(): void {
    this.applyDeleteSyncIfNeeded();
    const needTimelineCatchUp = GalleryTimelineRefreshStore.version > this.lastBootstrapSatisfiedRefreshVersion;
    // 搜索：applyDeleteSyncIfNeeded 已从 searchResults 剪掉预览删除项，此处仅需消费 bump 版本避免反复判断
    if (this.inSearchMode) {
      if (needTimelineCatchUp) {
        this.markTimelineRefreshCaughtUp();
      }
      return;
    }
    /**
     * 子视图下不拉主时间轴；但预览里删视频会 bump，「媒体分类 / 智能分类 / 人物」入口上的数量与封面仍会陈旧，
     * 回到 Home 时补一轮就地刷新（与主时间线的 requestBootstrap 互斥由 needTimelineCatchUp 统一表达）。
     */
    if (this.inCategoryMode || this.inSmartCategoryMode || this.inPersonMode) {
      if (needTimelineCatchUp) {
        if (this.inCategoryMode) {
          void this.refreshMediaCategoriesInPlace();
        } else if (this.inSmartCategoryMode) {
          void this.refreshSmartCategoriesInPlace();
        } else {
          void this.refreshPersonListInPlace();
        }
      }
      return;
    }
    if (needTimelineCatchUp) {
      this.requestBootstrap(true);
    }
  }

  /** 不改变子模式 UI，仅重拉媒体分类瓷砖（预览删除视频后更新「视频」等数量） */
  private async refreshMediaCategoriesInPlace(): Promise<void> {
    if (!this.inCategoryMode || this.categoryLoading) {
      this.markTimelineRefreshCaughtUp();
      return;
    }
    this.categoryLoading = true;
    this.categoryError = '';
    const client = AppSession.getClient();
    if (client === null) {
      this.categoryLoading = false;
      this.markTimelineRefreshCaughtUp();
      return;
    }
    try {
      const res = await client.getMediaCategoryList();
      if (res.success && res.data !== undefined) {
        const raw = res.data.list ?? res.data.items ?? [];
        const out: MediaCategoryItem[] = [];
        for (let i = 0; i < raw.length; i++) {
          const el = raw[i];
          if (typeof el === 'object' && el !== null) {
            out.push(el as MediaCategoryItem);
          }
        }
        this.categoryItems = out;
      }
    } catch (_e) {
    }
    this.categoryLoading = false;
    this.markTimelineRefreshCaughtUp();
  }

  private async refreshSmartCategoriesInPlace(): Promise<void> {
    if (!this.inSmartCategoryMode || this.smartCategoryLoading) {
      this.markTimelineRefreshCaughtUp();
      return;
    }
    this.smartCategoryLoading = true;
    this.smartCategoryError = '';
    const client = AppSession.getClient();
    if (client === null) {
      this.smartCategoryLoading = false;
      this.markTimelineRefreshCaughtUp();
      return;
    }
    try {
      const pair = await Promise.all([
        client.getSmartRecCategories('scene', -1),
        client.getSmartRecCategories('information', -1)
      ]);
      const sceneRes = pair[0];
      const infoRes = pair[1];
      const sceneRaw =
        sceneRes.success && sceneRes.data !== undefined ? (sceneRes.data.list ?? sceneRes.data.items ?? []) : [];
      const infoRaw =
        infoRes.success && infoRes.data !== undefined ? (infoRes.data.list ?? infoRes.data.items ?? []) : [];
      const sceneOut: SmartCategoryItem[] = [];
      const infoOut: SmartCategoryItem[] = [];
      for (let i = 0; i < sceneRaw.length; i++) {
        const el = sceneRaw[i];
        if (typeof el === 'object' && el !== null) {
          sceneOut.push(el as SmartCategoryItem);
        }
      }
      for (let i = 0; i < infoRaw.length; i++) {
        const el = infoRaw[i];
        if (typeof el === 'object' && el !== null) {
          infoOut.push(el as SmartCategoryItem);
        }
      }
      this.smartSceneItems = sceneOut;
      this.smartInfoItems = infoOut;
    } catch (_e) {
    }
    this.smartCategoryLoading = false;
    this.markTimelineRefreshCaughtUp();
  }

  private async refreshPersonListInPlace(): Promise<void> {
    if (!this.inPersonMode || this.personLoading) {
      this.markTimelineRefreshCaughtUp();
      return;
    }
    this.personStatOverrides.clear();
    this.personStatVersion++;
    this.personStatGen++;
    const gen = this.personStatGen;
    this.personLoading = true;
    this.personError = '';
    const client = AppSession.getClient();
    if (client === null) {
      this.personLoading = false;
      this.markTimelineRefreshCaughtUp();
      return;
    }
    try {
      const res = await client.getAiPersonList(true, -1, 0);
      if (gen !== this.personStatGen) {
        this.personLoading = false;
        this.markTimelineRefreshCaughtUp();
        return;
      }
      if (!res.success || res.data === undefined) {
        this.personLoading = false;
        this.markTimelineRefreshCaughtUp();
        return;
      }
      const raw = res.data.list ?? res.data.items ?? res.data.records ?? [];
      const out: AiPersonItem[] = [];
      for (let i = 0; i < raw.length; i++) {
        const el = raw[i];
        if (typeof el === 'object' && el !== null) {
          out.push(el as AiPersonItem);
        }
      }
      this.personItems = out;
      void this.enrichPersonStats(out, gen);
    } catch (_e) {
    }
    this.personLoading = false;
    this.markTimelineRefreshCaughtUp();
  }

  private markTimelineRefreshCaughtUp(): void {
    this.lastBootstrapSatisfiedRefreshVersion = GalleryTimelineRefreshStore.version;
  }

  /**
   * 根据 Scroller 垂直偏移判断是否处于列表顶端，用于下拉刷新门禁（仅顶端才允许真正拉取时间轴）。
   */
  private syncGalleryTimelineAtTopForPull(): void {
    try {
      const off = this.scrollerRef.currentOffset();
      const yRaw = off.yOffset;
      const y = typeof yRaw === 'number' ? yRaw : 0;
      this.galleryTimelineAtTopForPull = !Number.isFinite(y) || y <= 0.5;
    } catch (_e) {
      this.galleryTimelineAtTopForPull = true;
    }
  }

  /** 顶栏多选按钮：进入多选（从 0 项开始，与长按首张进入一致的可扩展行为） */
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
   * 时间线区域下拉刷新：使用系统 Refresh 动效；非列表顶端、多选或子模式时不发起网络请求。
   */
  private async onGalleryTimelinePullRefresh(): Promise<void> {
    this.syncGalleryTimelineAtTopForPull();
    if (!this.galleryTimelineAtTopForPull || this.gallerySelectionMode) {
      this.galleryTimelineRefreshing = false;
      return;
    }
    this.galleryTimelineRefreshing = true;
    try {
      this.clearBootstrapDebounceTimer();
      await this.bootstrap(false);
    } finally {
      this.galleryTimelineRefreshing = false;
      this.galleryPullRefreshThresholdHapticDone = false;
    }
  }

  // ── 数据加载 ─────────────────────────────────────────────────────────────
  /**
   * 全量重建时间线与列表。
   * @param showFullBleedSkeleton true：首屏/强刷时铺满骨架；false：下拉刷新等场景保留列表区域，仅用 Refresh 官方动效。
   */
  private async bootstrap(showFullBleedSkeleton: boolean = true): Promise<void> {
    // 任意全量拉取（含下拉刷新、顶栏刷新）均丢弃内存快照，避免与网络结果不一致
    GalleryHomeTimelineCache.invalidate();
    const gen = ++this.loadGen;
    this.exhausted = false;
    this.dayIndex = 0;
    this.orderedDays = [];
    this.dayOffsets.clear();
    this.dayRounds.clear();
    this.dayEmptyRounds.clear();
    if (showFullBleedSkeleton) {
      this.bootLoading = true;
    } else {
      this.bootLoading = false;
    }
    this.loadError = '';
    this.sections = [];
    this.footText = '';
    this.rebuildFlow();

    const client = AppSession.getClient();
    if (client === null) {
      if (gen !== this.loadGen) { return; }
      this.bootLoading = false;
      this.loadError = '未登录';
      return;
    }

    let workClient = client;
    if (workClient.getLongToken().length === 0) {
      const tok = await workClient.fetchFnosLongTokenProbe(12000);
      if (tok.length > 0) {
        const cur = AppSession.getStored();
        if (cur !== null) {
          cur.fnosLongToken = tok;
          AppSession.apply(cur);
          try {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
            void SessionPreferences.save(ctx, cur);
          } catch (_e) { /* ignore */ }
          const refreshed = AppSession.getClient();
          if (refreshed !== null) { workClient = refreshed; }
        }
      }
    }

    let tl = await workClient.getGalleryTimeline();
    if (gen !== this.loadGen) { return; }
    // 长时间未用后服务端会话过期 → HTTP 401：静默 WS 重登（依赖本地保存的密码）后重试时间轴
    if (tl.success !== true || tl.data === undefined) {
      const em0 = tl.message !== undefined && tl.message.length > 0 ? tl.message : '';
      if (isHttpUnauthorizedMessage(em0)) {
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        const ok = await tryRecoverSessionAfterAuthFailure(ctx);
        if (ok) {
          const c2 = AppSession.getClient();
          if (c2 !== null) {
            workClient = c2;
            tl = await workClient.getGalleryTimeline();
          }
        }
      }
    }
    if (gen !== this.loadGen) { return; }
    if (tl.success !== true || tl.data === undefined) {
      const em = tl.message !== undefined && tl.message.length > 0 ? tl.message : '时间轴加载失败';
      const prev = '';
      hilog.warn(DOMAIN, TAG, 'timeline fail: %{public}s body: %{public}s', em, prev || '(none)');
      this.bootLoading = false;
      this.loadError = prev.length > 0 ? `${em}\n${prev}` : em;
      return;
    }

    const rawList = tl.data.list ?? [];
    const cellsIn: Array<Record<string, number | undefined>> = [];
    for (let i = 0; i < rawList.length; i++) {
      const el = rawList[i];
      if (typeof el === 'object' && el !== null) {
        cellsIn.push(el as Record<string, number | undefined>);
      }
    }
    const cells = sortDaysDesc(parseTimelineDayCells(cellsIn)).filter(
      (c: TimelineDayModel): boolean => c.itemCount > 0
    );
    if (cells.length === 0) {
      this.bootLoading = false;
      this.footText = '时间轴暂无数据';
      this.rebuildFlow();
      this.markTimelineRefreshCaughtUp();
      return;
    }

    this.orderedDays = cells;
    this.bootLoading = false;
    this.markTimelineRefreshCaughtUp();
    // 启动自驱动加载泵
    this.pumpLoad();
  }

  /**
   * 自驱动批量加载泵（self-pumping）。
   *
   * 原理：每批完成后自动在短暂暂停后继续下一批，完全不依赖滚动事件。
   * 这是解决 "Drag gesture has been canceled" 导致 onDidScroll 不触发的根本方案。
   * loadingMore 守卫防止并发调用；loadGen 保证刷新后旧泵自动停止。
   */
  private pumpLoad(singleBatch: boolean = false): void {
    // 严格门控：时间轴拖动占位期间禁止启动/续跑泵
    if (this.visualPlaceholderMode || this.isDraggingOrFling) {
      if (this.isInScrollInteractiveLogWindow()) {
        this.logScrollDebug('pump hold: placeholder/dragging (entry)');
      }
      return;
    }
    if (this.loadingMore || this.exhausted) {
      if (GALLERY_SCROLL_DEBUG_LOG && this.isInScrollInteractiveLogWindow()) {
        this.logScrollDebug(
          `pump skip: loadingMore=${this.loadingMore ? 1 : 0}, exhausted=${this.exhausted ? 1 : 0}, days=${this.orderedDays.length}`
        );
      }
      return;
    }
    /**
     * bootstrap 在 await getGalleryTimeline 之前会同步清空 orderedDays。
     * 此窗口内若 onDidScroll / 上次泵的 setTimeout 触发 pumpLoad，loadOneBatch 会看到 dayIndex>=length 且 length===0，
     * 误判为「已扫完所有日」并 exhausted=true，随后新时间轴回填后 pumpLoad 被直接 return，表现为空列表 +「已加载全部照片」。
     */
    if (this.orderedDays.length === 0) {
      if (this.isInScrollInteractiveLogWindow()) {
        this.logScrollDebug('pump skip: orderedDays empty');
      }
      return;
    }
    this.loadingMore = true;
    const gen = this.loadGen;
    const epoch = this.pumpEpoch;
    void this.loadOneBatch().then((added: number): void => {
      if (epoch !== this.pumpEpoch) {
        this.loadingMore = false;
        if (this.isInScrollInteractiveLogWindow()) {
          this.logScrollDebug(`pump canceled by epoch: start=${epoch}, current=${this.pumpEpoch}`);
        }
        return;
      }
      this.loadingMore = false;
      if (this.isInScrollInteractiveLogWindow()) {
        this.logScrollDebug(`pump result: added=${added}, dayIndex=${this.dayIndex}, gen=${gen}, curGen=${this.loadGen}`);
      }
      if (gen !== this.loadGen || this.exhausted) {
        return;
      }
      if (added === -1) {
        // 耗尽或已被新的 loadGen 取消，停止泵
        return;
      }
      if (added === -2) {
        if (singleBatch) {
          return;
        }
        // 网络错误，3 秒后重试（避免频繁失败）
        const retryEpoch = this.pumpEpoch;
        setTimeout((): void => {
          if (retryEpoch !== this.pumpEpoch) {
            return;
          }
          this.pumpLoad();
        }, 3000);
        return;
      }
      if (added === -3) {
        if (singleBatch) {
          return;
        }
        // 时间轴显示仍有剩余但本批空：同一 offset 稍后重试（避免误切日 + 减轻压力）
        const retryEpoch = this.pumpEpoch;
        setTimeout((): void => {
          if (retryEpoch !== this.pumpEpoch) {
            return;
          }
          this.pumpLoad();
        }, 500);
        return;
      }
      if (singleBatch) {
        return;
      }
      // 交互占位期暂停自驱动连续泵，避免滚动期列表高频重建导致卡顿/闪退。
      if (this.visualPlaceholderMode || this.isDraggingOrFling) {
        if (this.isInScrollInteractiveLogWindow()) {
          this.logScrollDebug('pump hold: placeholder/dragging');
        }
        return;
      }
      // added >= 0：有数据时等一帧供 UI；切日时立即继续
      const nextEpoch = this.pumpEpoch;
      setTimeout((): void => {
        if (nextEpoch !== this.pumpEpoch) {
          return;
        }
        this.pumpLoad();
      }, added > 0 ? PUMP_UI_GAP_MS : 0);
    });
  }

  /**
   * 加载单批数据。返回：
   *   >0  = 本批新增条数
   *    0  = 本批无新增（已切日或当日结束）
   *   -1  = 耗尽/已刷新（应停止）
   *   -2  = 网络错误（泵应延迟重试）
   *   -3  = 暂态空页：timeline 仍显示有剩余条数但本批为空，需延迟后同 offset 重试（永不因此强制切日）
   *
   * 切日策略（对齐 fnos_gallery_mobile.py `_load_batch`）：
   *   1) `len==0` 或 `newOff>=itemCount` 或 **`len<limit`（短页）** → 进入下一日
   *   2) 当 `itemCount>0` 且 `newOff<itemCount` 时空页为暂态，只重试不切日（禁止「空页 N 次放弃当日」丢图）
   */
  private async loadOneBatch(): Promise<number> {
    if (this.exhausted) {
      return -1;
    }
    if (this.dayIndex >= this.orderedDays.length) {
      // length===0：时间轴尚未回填或已被新一轮 bootstrap 清空，绝非「已全部加载」
      if (this.orderedDays.length === 0) {
        return -1;
      }
      this.exhausted = true;
      if (this.countGalleryListedItems() > 0) {
        this.footText = '已加载全部照片';
      } else {
        this.footText = '未获取到照片';
      }
      return -1;
    }

    const gen = this.loadGen;
    const day = this.orderedDays[this.dayIndex];
    const key = dayKey(day.year, day.month, day.day);
    const off = this.dayOffsets.get(key) ?? 0;
    const rounds = this.dayRounds.get(key) ?? 0;
    const emptyRounds = this.dayEmptyRounds.get(key) ?? 0;
    const itemCountBasedMax = day.itemCount > 0
      ? Math.ceil(day.itemCount / DATE_FEED_BATCH) + 20
      : DAY_MAX_ROUNDS;
    const dayMaxRounds = Math.max(DAY_MAX_ROUNDS, itemCountBasedMax);

    // 动态安全上限：单日请求超过上限仍未结束，强制切日（避免极端无限循环）
    if (rounds >= dayMaxRounds) {
      hilog.warn(DOMAIN, TAG, 'day %{public}s exceeded max rounds %{public}d, force advance', key, dayMaxRounds);
      this.dayIndex++;
      return 0;
    }

    const client = AppSession.getClient();
    if (client === null) {
      this.footText = '未登录';
      this.exhausted = true;
      return -1;
    }

    try {
      const st = fmtDayStart(day.year, day.month, day.day);
      const et = fmtDayEnd(day.year, day.month, day.day);
      let res = await client.getGalleryList(st, et, DATE_FEED_BATCH, off, 'index');
      if (gen !== this.loadGen) {
        return -1;
      }

      if (res.success !== true) {
        const em0 = res.message !== undefined && res.message.length > 0 ? res.message : '';
        if (isHttpUnauthorizedMessage(em0)) {
          const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
          const recovered = await tryRecoverSessionAfterAuthFailure(ctx);
          if (recovered) {
            const c2 = AppSession.getClient();
            if (c2 !== null) {
              res = await c2.getGalleryList(st, et, DATE_FEED_BATCH, off, 'index');
            }
          }
        }
      }
      if (gen !== this.loadGen) {
        return -1;
      }

      if (res.success !== true) {
        const em = res.message !== undefined && res.message.length > 0 ? res.message : '加载失败';
        hilog.warn(DOMAIN, TAG, 'getList fail %{public}s off=%{public}d: %{public}s', key, off, em);
        this.footText = em;
        return -2; // 网络错误，通知泵延迟重试
      }

      // res.data 可能运行时为 null（服务端异常），与 Python isinstance 检查对齐：视同空列表 → 切日
      const list = listFromData(res.data as GalleryGetListData | undefined);
      const total = res.data?.total;
      const newOff = off + list.length;
      this.dayOffsets.set(key, newOff);

      if (list.length > 0) {
        this.upsertSection(day, list, newOff);
        this.dayEmptyRounds.set(key, 0);
      } else {
        this.dayEmptyRounds.set(key, emptyRounds + 1);
      }

      // 与 Python 一致：本批条数 < limit 即视为当日已结束（最后一页），无需再请求下一 offset
      if (list.length > 0 && list.length < DATE_FEED_BATCH) {
        this.dayRounds.set(key, rounds + 1);
        if (GALLERY_BATCH_VERBOSE_LOG) {
          hilog.warn(DOMAIN, TAG,
            'short page end day %{public}s off=%{public}d got=%{public}d newOff=%{public}d itemCount=%{public}d',
            key, off, list.length, newOff, day.itemCount);
        }
        this.dayIndex++;
        return list.length;
      }

      const emptyNow = list.length === 0 ? (emptyRounds + 1) : 0;
      const timelineSaysMore = day.itemCount > 0 && newOff < day.itemCount;
      const transientEmpty = list.length === 0 && timelineSaysMore;

      if (GALLERY_BATCH_VERBOSE_LOG) {
        hilog.warn(DOMAIN, TAG,
          'batch %{public}s off=%{public}d got=%{public}d newOff=%{public}d itemCount=%{public}d total=%{public}s emptyRounds=%{public}d transient=%{public}d',
          key, off, list.length, newOff, day.itemCount,
          total !== undefined ? String(total) : 'n/a',
          list.length === 0 ? (emptyRounds + 1) : 0,
          transientEmpty ? 1 : 0);
      }

      if (!transientEmpty) {
        this.dayRounds.set(key, rounds + 1);
      }

      if (transientEmpty) {
        return -3;
      }

      const reachTimelineEnd = day.itemCount > 0 && newOff >= day.itemCount;
      const shouldAdvanceDay = list.length === 0 && (
        reachTimelineEnd ||
        (day.itemCount <= 0 && emptyNow >= EMPTY_PAGE_ADVANCE_THRESHOLD)
      );
      if (shouldAdvanceDay) {
        this.dayIndex++;
      }

      return list.length;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadOneBatch error: %{public}s', String(e));
      this.footText = String(e) || '请求异常';
      return -2;
    }
  }

  /**
   * 纯视觉层：不绑定任何手势，手势统一由外层 Row 容器处理。
   * GalleryNetworkThumb 自身已设 HitTestMode.None，外层 Stack 默认 Default，
   * 触摸事件会透传至父级 Row，由 Row 的 gesture/parallelGesture 统一响应。
   */
  @Builder
  private buildGalleryTimelineThumbCell(item: GalleryListItem, flatIndex: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 仅时间轴手柄拖动时用静态占位；普通列表滑动不覆盖已加载真实图
      if (this.timelineSidebarDragging) {
        GalleryStaticThumbPlaceholder({ animatePulse: this.timelineSidebarDragging })
          .width('100%')
          .aspectRatio(1)
      } else {
        GalleryNetworkThumb({
          uri: nasUrl(this.baseUrl, pickThumb(item)),
          isVideo: isVideoItem(item),
          isGif: isGifItem(item),
          paused: false
        })
          .width('100%')
          .aspectRatio(1)
      }
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#55000000')
        .opacity(this.gallerySelectionMode && this.isGalleryIdSelected(this.itemIdOf(item)) ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
        .animation({ duration: 0, curve: Curve.Linear })
      Row() {
        Blank().layoutWeight(1)
        Column() {
          if (this.isGalleryIdSelected(this.itemIdOf(item))) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(24)
              .fontColor([$r('app.color.brand_primary')])
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          } else {
            Stack({ alignContent: Alignment.Center }) {
              Circle()
                .width(22)
                .height(22)
                .fill(Color.Transparent)
                .stroke(Color.White)
                .strokeWidth(2)
            }
            .width(24)
            .height(24)
          }
        }
        .padding({ top: 6, right: 6 })
      }
      .width('100%')
      .hitTestBehavior(HitTestMode.None)
      .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
    }
    .id(this.itemIdOf(item).length > 0 ? this.galleryThumbDomId(this.itemIdOf(item)) : `gt_na_${flatIndex}`)
    .onAreaChange((): void => {
      const pid = this.itemIdOf(item);
      if (pid.length > 0) {
        this.recordGalleryThumbRectFromDom(pid, this.galleryThumbDomId(pid));
      }
    })
    .layoutWeight(1)
    .aspectRatio(1)
    .backgroundColor(Color.Transparent)
    .draggable(false)
    .onClick((): void => {
      this.onGalleryThumbTap(item, flatIndex);
    })
  }

  @Builder
  private buildSearchGridThumbCell(item: GalleryListItem, flatIndex: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      GalleryNetworkThumb({
        uri: nasUrl(this.baseUrl, pickThumb(item)),
        isVideo: isVideoItem(item),
        isGif: isGifItem(item),
      })
        .width('100%')
        .aspectRatio(1)
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#55000000')
        .opacity(this.gallerySelectionMode && this.isGalleryIdSelected(this.itemIdOf(item)) ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
        .animation({ duration: 0, curve: Curve.Linear })
      Row() {
        Blank().layoutWeight(1)
        Column() {
          if (this.isGalleryIdSelected(this.itemIdOf(item))) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
              .fontSize(24)
              .fontColor([$r('app.color.brand_primary')])
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          } else {
            Stack({ alignContent: Alignment.Center }) {
              Circle()
                .width(22)
                .height(22)
                .fill(Color.Transparent)
                .stroke(Color.White)
                .strokeWidth(2)
            }
            .width(24)
            .height(24)
          }
        }
        .padding({ top: 6, right: 6 })
      }
      .width('100%')
      .hitTestBehavior(HitTestMode.None)
      .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
    }
    .id(this.searchThumbDomId(flatIndex))
    .onAreaChange((): void => {
      this.recordSearchThumbRect(flatIndex);
    })
    .layoutWeight(1)
    .aspectRatio(1)
    .backgroundColor(Color.Transparent)
    .draggable(false)
    .onClick((): void => {
      this.onSearchThumbTap(item, flatIndex);
    })
  }

  @Builder
  private searchCellSlot(rowIdx: number, col: number) {
    if (rowIdx * 3 + col >= this.searchResults.length) {
      Blank().layoutWeight(1).aspectRatio(1)
    } else {
      this.buildSearchGridThumbCell(this.searchResults[rowIdx * 3 + col], rowIdx * 3 + col);
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
      // ── 顶部标题栏 ──────────────────────────────────────────────────────────
      Row() {
        if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
          // 顶栏 1-2-1：左「图库/取消」、中搜索、右「多选」；批量操作在底部栏与分类页一致
          Row() {
          Row() {
            Stack({ alignContent: Alignment.Center }) {
              Text('图库')
                .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .lineHeight(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
              Button($r('app.string.gallery_batch_cancel'), { type: ButtonType.Capsule, stateEffect: true })
                .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .backgroundColor($r('app.color.button_primary_bg'))
                .fontColor($r('app.color.button_primary_fg'))
                .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
                .onClick((): void => {
                  this.exitGallerySelection();
                })
            }
          }
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          .justifyContent(FlexAlign.Start)

          Row({ space: 8 }) {
            Stack({ alignContent: Alignment.Center }) {
              TextInput({ placeholder: 'AI 搜索照片…', text: this.searchQuery })
                .width('100%')
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .borderRadius(18)
                .backgroundColor($r('app.color.card_background'))
                .fontSize(14)
                .placeholderColor($r('app.color.text_secondary'))
                .enabled(!this.gallerySelectionMode)
                .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
                .onChange((val: string): void => {
                  this.searchQuery = val;
                })
                .onSubmit((): void => {
                  void this.runSearch(this.searchQuery);
                })
              Text(`已选择 ${this.gallerySelectedIds.length} 张`)
                .width('100%')
                .fontSize(GALLERY_TOP_BAR_SUBTITLE_FONT_VP)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .textAlign(TextAlign.Center)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
            }
            .layoutWeight(1)
            .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)

            Stack({ alignContent: Alignment.Center }) {
              Button() {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(17)
                  .fontColor([$r('app.color.icon_primary')])
              }
              .width(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .borderRadius(18)
              .backgroundColor($r('app.color.card_background'))
              .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
              .onClick((): void => {
                void this.runSearch(this.searchQuery);
              })
              Column()
                .width(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
            }
            .width(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
            .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          }
          .layoutWeight(2)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          .margin({ left: 4, right: 4 })

          Row() {
            Stack({ alignContent: Alignment.Center }) {
              Button($r('app.string.gallery_multiselect'), { type: ButtonType.Capsule, stateEffect: true })
                .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .backgroundColor($r('app.color.button_secondary_bg'))
                .fontColor($r('app.color.button_secondary_fg'))
                .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
                .accessibilityText($r('app.string.gallery_multiselect'))
                .onClick((): void => {
                  this.enterGallerySelectionModeFromToolbar();
                })
            }
          }
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          .justifyContent(FlexAlign.End)
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
        } else if (this.inSearchMode) {
          Row() {
            Stack({ alignContent: Alignment.Center }) {
              Button('返回图库', { type: ButtonType.Capsule, stateEffect: true })
                .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .backgroundColor($r('app.color.button_secondary_bg'))
                .fontColor($r('app.color.button_secondary_fg'))
                .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
                .onClick((): void => {
                  this.backToGallery();
                })
              Button($r('app.string.gallery_batch_cancel'), { type: ButtonType.Capsule, stateEffect: true })
                .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .backgroundColor($r('app.color.button_primary_bg'))
                .fontColor($r('app.color.button_primary_fg'))
                .visibility(this.gallerySelectionMode ? Visibility.Visible : Visibility.Hidden)
                .onClick((): void => {
                  this.exitGallerySelection();
                })
            }
          }
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          .justifyContent(FlexAlign.Start)

          Text(this.gallerySelectionMode ? `已选择 ${this.gallerySelectedIds.length} 张` : 'AI 搜索结果')
            .layoutWeight(2)
            .fontSize(this.gallerySelectionMode ? GALLERY_TOP_BAR_SUBTITLE_FONT_VP : GALLERY_TOP_BAR_TITLE_FONT_VP)
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor($r('app.color.text_primary'))

          Row() {
            Stack({ alignContent: Alignment.Center }) {
              Button($r('app.string.gallery_multiselect'), { type: ButtonType.Capsule, stateEffect: true })
                .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
                .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
                .backgroundColor($r('app.color.button_secondary_bg'))
                .fontColor($r('app.color.button_secondary_fg'))
                .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
                .accessibilityText($r('app.string.gallery_multiselect'))
                .onClick((): void => {
                  this.enterGallerySelectionModeFromToolbar();
                })
            }
          }
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          .justifyContent(FlexAlign.End)
        } else {
          Row()
            .layoutWeight(1)
            .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)

          Text(this.inCategoryMode ? '媒体分类' : (this.inSmartCategoryMode ? '智能分类' : '人物'))
            .layoutWeight(2)
            .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor($r('app.color.text_primary'))

          Row() {
            Button('返回图库', { type: ButtonType.Capsule, stateEffect: true })
              .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .backgroundColor($r('app.color.button_secondary_bg'))
              .fontColor($r('app.color.button_secondary_fg'))
              .onClick((): void => {
                this.backToGallery();
              })
          }
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          .justifyContent(FlexAlign.End)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: GALLERY_TOP_BAR_PAD_LEFT_VP,
        right: GALLERY_TOP_BAR_PAD_RIGHT_VP,
        top: GALLERY_TOP_BAR_PAD_TOP_VP,
        bottom: GALLERY_TOP_BAR_PAD_BOTTOM_VP
      })

      // ── 主页面分类入口：多选时隐藏但占位不变（Visibility.Hidden），避免时间线列表整体上移
      // 芯片较多时单行放不下：Flex 自动换行（第二行继续从左排），避免挤压或横向手势与列表冲突
      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
        Flex({
          direction: FlexDirection.Row,
          wrap: FlexWrap.Wrap,
          justifyContent: FlexAlign.Start,
          alignItems: ItemAlign.Center
        }) {
          Button() {
            Text('媒体分类')
              .fontSize(GALLERY_HOME_NAV_CHIP_FONT_VP)
              .fontColor($r('app.color.text_primary'))
          }
          .height(GALLERY_HOME_NAV_CHIP_HEIGHT_VP)
          .padding({ left: GALLERY_HOME_NAV_CHIP_PAD_H_VP, right: GALLERY_HOME_NAV_CHIP_PAD_H_VP })
          .borderRadius(GALLERY_HOME_NAV_CHIP_RADIUS_VP)
          .backgroundColor($r('app.color.card_background'))
          .margin({ right: 8, bottom: 8 })
          .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
          .enabled(!this.gallerySelectionMode)
          .onClick((): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/MediaCategoryPage',
              params: { baseUrl: this.baseUrl }
            }).catch((_e: Error): void => {
              this.toast('打开媒体分类失败');
            });
          })
          Button() {
            Text('智能分类')
              .fontSize(GALLERY_HOME_NAV_CHIP_FONT_VP)
              .fontColor($r('app.color.text_primary'))
          }
          .height(GALLERY_HOME_NAV_CHIP_HEIGHT_VP)
          .padding({ left: GALLERY_HOME_NAV_CHIP_PAD_H_VP, right: GALLERY_HOME_NAV_CHIP_PAD_H_VP })
          .borderRadius(GALLERY_HOME_NAV_CHIP_RADIUS_VP)
          .backgroundColor($r('app.color.card_background'))
          .margin({ right: 8, bottom: 8 })
          .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
          .enabled(!this.gallerySelectionMode)
          .onClick((): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/SmartCategoryPage',
              params: { baseUrl: this.baseUrl }
            }).catch((_e: Error): void => {
              this.toast('打开智能分类失败');
            });
          })
          Button() {
            Text('人物')
              .fontSize(GALLERY_HOME_NAV_CHIP_FONT_VP)
              .fontColor($r('app.color.text_primary'))
          }
          .height(GALLERY_HOME_NAV_CHIP_HEIGHT_VP)
          .padding({ left: GALLERY_HOME_NAV_CHIP_PAD_H_VP, right: GALLERY_HOME_NAV_CHIP_PAD_H_VP })
          .borderRadius(GALLERY_HOME_NAV_CHIP_RADIUS_VP)
          .backgroundColor($r('app.color.card_background'))
          .margin({ right: 8, bottom: 8 })
          .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
          .enabled(!this.gallerySelectionMode)
          .onClick((): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/PersonPage',
              params: { baseUrl: this.baseUrl }
            }).catch((_e: Error): void => {
              this.toast('打开人物页失败');
            });
          })
          Button() {
            Text('最近添加')
              .fontSize(GALLERY_HOME_NAV_CHIP_FONT_VP)
              .fontColor($r('app.color.text_primary'))
          }
          .height(GALLERY_HOME_NAV_CHIP_HEIGHT_VP)
          .padding({ left: GALLERY_HOME_NAV_CHIP_PAD_H_VP, right: GALLERY_HOME_NAV_CHIP_PAD_H_VP })
          .borderRadius(GALLERY_HOME_NAV_CHIP_RADIUS_VP)
          .backgroundColor($r('app.color.card_background'))
          .margin({ right: 8, bottom: 8 })
          .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
          .enabled(!this.gallerySelectionMode)
          .onClick((): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            void this.openRecentAdded();
          })
          Button() {
            Text('收藏')
              .fontSize(GALLERY_HOME_NAV_CHIP_FONT_VP)
              .fontColor($r('app.color.text_primary'))
          }
          .height(GALLERY_HOME_NAV_CHIP_HEIGHT_VP)
          .padding({ left: GALLERY_HOME_NAV_CHIP_PAD_H_VP, right: GALLERY_HOME_NAV_CHIP_PAD_H_VP })
          .borderRadius(GALLERY_HOME_NAV_CHIP_RADIUS_VP)
          .backgroundColor($r('app.color.card_background'))
          .margin({ right: 8, bottom: 8 })
          .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
          .enabled(!this.gallerySelectionMode)
          .onClick((): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            void this.openCollectGallery();
          })
          Button() {
            Text('回收站')
              .fontSize(GALLERY_HOME_NAV_CHIP_FONT_VP)
              .fontColor($r('app.color.text_primary'))
          }
          .height(GALLERY_HOME_NAV_CHIP_HEIGHT_VP)
          .padding({ left: GALLERY_HOME_NAV_CHIP_PAD_H_VP, right: GALLERY_HOME_NAV_CHIP_PAD_H_VP })
          .borderRadius(GALLERY_HOME_NAV_CHIP_RADIUS_VP)
          .backgroundColor($r('app.color.card_background'))
          .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
          .enabled(!this.gallerySelectionMode)
          .onClick((): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            this.getUIContext().getRouter().pushUrl({
              url: 'pages/RecycleBinPage',
              params: { baseUrl: this.baseUrl }
            }).catch((_e: Error): void => {
              this.toast('打开回收站失败');
            });
          })
          .margin({ right: 8, bottom: 8 })
        }
        .width('100%')
        .padding({
          left: GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_LEFT_VP,
          right: GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_RIGHT_VP,
          bottom: GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_BOTTOM_VP
        })
      }

      // ── 搜索结果视图 ──────────────────────────────────────────────────────────
      if (this.inSearchMode) {
        Column() {
          if (this.searchLoading) {
            Row() {
              LoadingProgress().width(28).height(28)
              Text('AI 搜索中…').fontSize(14).fontColor($r('app.color.text_secondary')).margin({ left: 10 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 40 })
          } else if (this.searchError.length > 0) {
            Text(this.searchError)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 40, left: 24, right: 24 })
          } else {
            Column() {
              List() {
                ForEach(this.searchRowIndexArray(), (rowIdx: number) => {
                  ListItem() {
                    Row({ space: 2 }) {
                      this.searchCellSlot(rowIdx, 0)
                      this.searchCellSlot(rowIdx, 1)
                      this.searchCellSlot(rowIdx, 2)
                    }
                    .width('100%')
                    .padding({ left: 2, right: 2, top: 1, bottom: 1 })
                    .parallelGesture(GestureGroup(GestureMode.Parallel,
                      LongPressGesture({ repeat: false, duration: 420 })
                        .onAction((ev: GestureEvent): void => {
                          this.endGallerySlideSelectGesture();
                          const pt = this.readGestureFingerWindow(ev);
                          if (pt === null) {
                            return;
                          }
                          const xPx = vp2px(pt.x);
                          const yPx = vp2px(pt.y);
                          const rowStart = rowIdx * 3;
                          const fi = this.pickSearchThumbFlatForRow(rowStart, xPx, yPx);
                          if (fi < 0 || fi >= this.searchResults.length) {
                            return;
                          }
                          const longPressItem = this.searchResults[fi];
                          this.onGalleryThumbLongPress(longPressItem);
                          if (!this.gallerySelectionMode) {
                            return;
                          }
                          if (this.gallerySlideGestureActive) {
                            return;
                          }
                          this.beginGallerySlideSelectGesture(ev, longPressItem, fi);
                        }),
                      PanGesture({
                        fingers: 1,
                        direction: this.gallerySlideGestureActive ? PanDirection.All : PanDirection.Horizontal,
                        distance: this.gallerySlideGestureActive ? GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE :
                          GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE
                      })
                        .onActionStart((ev: GestureEvent): void => {
                          if (!this.gallerySelectionMode) {
                            return;
                          }
                          if (this.gallerySlideGestureActive) {
                            this.endGallerySlideSelectGesture();
                          }
                          const pt = this.readGestureFingerWindow(ev);
                          if (pt === null) {
                            return;
                          }
                          const xPx = vp2px(pt.x);
                          const yPx = vp2px(pt.y);
                          const rowStart = rowIdx * 3;
                          const fi = this.pickSearchThumbFlatForRow(rowStart, xPx, yPx);
                          if (fi < 0 || fi >= this.searchResults.length) {
                            return;
                          }
                          this.beginGallerySlideSelectGesture(ev, this.searchResults[fi], fi);
                        })
                        .onActionUpdate((ev: GestureEvent): void => {
                          this.onGallerySlidePanUpdate(ev);
                        })
                        .onActionEnd((): void => {
                          this.endGallerySlideSelectGesture();
                        })
                        .onActionCancel((): void => {
                          this.endGallerySlideSelectGesture();
                        })
                    ))
                    .onGestureJudgeBegin((gestureInfo: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
                      if (gestureInfo.type !== GestureControl.GestureType.PAN_GESTURE) {
                        return GestureJudgeResult.CONTINUE;
                      }
                      if (!this.gallerySelectionMode) {
                        return GestureJudgeResult.REJECT;
                      }
                      return GestureJudgeResult.CONTINUE;
                    })
                  }
                  .draggable(false)
                }, (rowIdx: number) => `srrow_${rowIdx}`)
                ListItem() {
                  Column() {
                    Blank()
                      .width('100%')
                      .height(this.gallerySelectionMode && this.gallerySelectedIds.length > 0 ? 88 : 32)
                  }
                  .width('100%')
                }
              }
              .width('100%')
              .layoutWeight(1)
              .cachedCount(6)
              .edgeEffect(EdgeEffect.Spring)
              .scrollBar(BarState.Auto)
              .divider({ strokeWidth: 0 })
              .enableScrollInteraction(this.galleryMainListScrollEnabled)
              .onDidScroll((_offset: number, _scrollState: ScrollState): void => {
                if (!this.gallerySlideGestureActive && !this.galleryMainListScrollEnabled) {
                  this.galleryMainListScrollEnabled = true;
                }
                if (!this.gallerySlideGestureActive) {
                  this.searchThumbHitBounds.clear();
                }
              })

              if (this.gallerySelectionMode && this.gallerySelectedIds.length > 0) {
                Row({ space: GALLERY_BATCH_BAR_SPACE_VP }) {
                  Button($r('app.string.gallery_batch_download'), { type: ButtonType.Capsule, stateEffect: true })
                    .layoutWeight(1)
                    .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
                    .fontColor($r('app.color.text_primary'))
                    .backgroundColor($r('app.color.card_background'))
                    .enabled(!this.galleryBatchDownloading)
                    .onClick((): void => {
                      void this.confirmAndBatchDownloadGallery();
                    })
                  Button($r('app.string.gallery_batch_delete'), { type: ButtonType.Capsule, stateEffect: true })
                    .layoutWeight(1)
                    .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
                    .fontColor(Color.White)
                    .backgroundColor(GALLERY_BATCH_DESTRUCTIVE_BG)
                    .enabled(!this.galleryBatchDeleting)
                    .onClick((): void => {
                      void this.confirmAndBatchDeleteGallery();
                    })
                }
                .width('100%')
                .padding({
                  left: GALLERY_BATCH_BAR_PAD_LEFT_VP,
                  right: GALLERY_BATCH_BAR_PAD_RIGHT_VP,
                  top: GALLERY_BATCH_BAR_PAD_TOP_VP,
                  bottom: GALLERY_BATCH_BAR_PAD_BOTTOM_VP
                })
                .backgroundColor($r('app.color.page_background'))
              }
            }
            .width('100%')
            .layoutWeight(1)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .opacity(this.modeSwitchOpacity)
        .translate({ x: 0, y: this.modeSwitchOffsetY })
        .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
      }

      if (this.inCategoryMode) {
        Column() {
          if (this.categoryLoading) {
            Row() {
              LoadingProgress().width(28).height(28)
              Text('媒体分类加载中…').fontSize(14).fontColor($r('app.color.text_secondary')).margin({ left: 10 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 40 })
          } else if (this.categoryError.length > 0) {
            Text(this.categoryError)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 40, left: 24, right: 24 })
          } else {
            Stack({ alignContent: Alignment.Center }) {
              Grid() {
                ForEach(this.categoryItems, (cat: MediaCategoryItem, idx: number) => {
                  GridItem() {
                    Column({ space: 8 }) {
                      GalleryNetworkThumb({
                        uri: nasUrl(this.baseUrl, this.categoryCover(cat)),
                        isVideo: false,
                        isGif: false,
                      })
                        .width('100%')
                        .aspectRatio(1)
                      Text(this.categoryTitle(cat))
                        .fontSize(13)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                      Text(`${this.categoryCount(cat)} 项`)
                        .fontSize(11)
                        .fontColor($r('app.color.text_secondary'))
                        .width('100%')
                    }
                    .width('100%')
                    .padding({ left: 2, right: 2, bottom: 8 })
                    .onClick((): void => {
                      void this.openCategory(cat);
                    })
                  }
                }, (cat: MediaCategoryItem, i: number) => `mc_${i}_${this.categoryTitle(cat)}`)
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(8)
              .rowsGap(8)
              .cachedCount(4)
              .width('100%')
              .height('100%')
              .padding({ left: 12, right: 12, top: 8 })
              .scrollBar(BarState.Auto)
              .edgeEffect(EdgeEffect.Spring)

              // 点击分类后等待网络响应时的加载遮罩
              if (this.categoryOpening) {
                FnFullLoadingMask({ text: '加载中…' })
              }
            }
            .width('100%')
            .layoutWeight(1)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .opacity(this.modeSwitchOpacity)
        .translate({ x: 0, y: this.modeSwitchOffsetY })
        .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
      }

      if (this.inSmartCategoryMode) {
        Column() {
          if (this.smartCategoryLoading) {
            Row() {
              LoadingProgress().width(28).height(28)
              Text('智能分类加载中…').fontSize(14).fontColor($r('app.color.text_secondary')).margin({ left: 10 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 40 })
          } else if (this.smartCategoryError.length > 0) {
            Text(this.smartCategoryError)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 40, left: 24, right: 24 })
          } else {
            List() {
              if (this.smartSceneItems.length > 0) {
                ListItem() {
                  Text('场景事物')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                }
                ListItem() {
                  Grid() {
                    ForEach(this.smartSceneItems, (item: SmartCategoryItem, idx: number) => {
                      GridItem() {
                        Column({ space: 8 }) {
                          GalleryNetworkThumb({
                            uri: nasUrl(this.baseUrl, this.smartCategoryCover(item)),
                            isVideo: false,
                            isGif: false,
                          })
                            .width('100%')
                            .aspectRatio(1)
                          Text(this.smartCategoryName(item))
                            .fontSize(13)
                            .fontColor($r('app.color.text_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                          Text('点击发起AI搜索')
                            .fontSize(11)
                            .fontColor($r('app.color.text_secondary'))
                            .width('100%')
                        }
                        .width('100%')
                        .padding({ left: 2, right: 2, bottom: 8 })
                        .onClick((): void => {
                          this.searchQuery = this.smartCategoryName(item);
                          void this.runSearch(this.smartCategoryName(item));
                        })
                      }
                    }, (_item: SmartCategoryItem, i: number) => `sc_scene_${i}`)
                  }
                  .columnsTemplate('1fr 1fr')
                  .columnsGap(8)
                  .rowsGap(8)
                  .cachedCount(4)
                  .width('100%')
                  .padding({ left: 12, right: 12 })
                }
              }
              if (this.smartInfoItems.length > 0) {
                ListItem() {
                  Text('资料记录')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')
                    .padding({ left: 14, right: 14, top: 16, bottom: 8 })
                }
                ListItem() {
                  Grid() {
                    ForEach(this.smartInfoItems, (item: SmartCategoryItem, idx: number) => {
                      GridItem() {
                        Column({ space: 8 }) {
                          GalleryNetworkThumb({
                            uri: nasUrl(this.baseUrl, this.smartCategoryCover(item)),
                            isVideo: false,
                            isGif: false,
                          })
                            .width('100%')
                            .aspectRatio(1)
                          Text(this.smartCategoryName(item))
                            .fontSize(13)
                            .fontColor($r('app.color.text_primary'))
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width('100%')
                          Text('点击发起AI搜索')
                            .fontSize(11)
                            .fontColor($r('app.color.text_secondary'))
                            .width('100%')
                        }
                        .width('100%')
                        .padding({ left: 2, right: 2, bottom: 8 })
                        .onClick((): void => {
                          this.searchQuery = this.smartCategoryName(item);
                          void this.runSearch(this.smartCategoryName(item));
                        })
                      }
                    }, (_item: SmartCategoryItem, i: number) => `sc_info_${i}`)
                  }
                  .columnsTemplate('1fr 1fr')
                  .columnsGap(8)
                  .rowsGap(8)
                  .cachedCount(4)
                  .width('100%')
                  .padding({ left: 12, right: 12, bottom: 10 })
                }
              }
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            .divider({ strokeWidth: 0 })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .opacity(this.modeSwitchOpacity)
        .translate({ x: 0, y: this.modeSwitchOffsetY })
        .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
      }

      if (this.inPersonMode) {
        Column() {
          if (this.personLoading) {
            Row() {
              LoadingProgress().width(28).height(28)
              Text('人物加载中…').fontSize(14).fontColor($r('app.color.text_secondary')).margin({ left: 10 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 40 })
          } else if (this.personError.length > 0) {
            Text(this.personError)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 40, left: 24, right: 24 })
          } else {
            Grid() {
              ForEach(this.personItems, (item: AiPersonItem, idx: number) => {
                GridItem() {
                  Column({ space: 8 }) {
                    GalleryNetworkThumb({
                      uri: nasUrl(this.baseUrl, this.personFace(item))
                    })
                      .width('100%')
                      .aspectRatio(1)
                      .borderRadius(12)
                    Text(this.personName(item))
                      .fontSize(13)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                    Text(this.personStatText(item))
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .width('100%')
                  }
                  .width('100%')
                  .padding({ left: 2, right: 2, bottom: 8 })
                  .onClick((): void => {
                    void this.openPerson(item);
                  })
                }
              }, (_item: AiPersonItem, i: number) => `person_${i}`)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(8)
            .rowsGap(8)
            .cachedCount(6)
            .width('100%')
            .layoutWeight(1)
            .padding({ left: 12, right: 12, top: 8, bottom: 10 })
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            if (this.personOpening) {
              FnFullLoadingMask({ text: '加载人物媒体中…' })
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .opacity(this.modeSwitchOpacity)
        .translate({ x: 0, y: this.modeSwitchOffsetY })
        .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
      }

      // ── 图库视图 ──────────────────────────────────────────────────────────────
      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
        if (this.bootLoading) {
          Column({ space: 8 }) {
            ForEach([0, 1, 2, 3], (row: number) => {
              Row({ space: 8 }) {
                ForEach([0, 1, 2], (_: number) => {
                  GalleryThumbSkeleton().layoutWeight(1)
                }, (n: number) => `sk_${row}_${n}`)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: row === 0 ? 24 : 0 })
            }, (r: number) => `skr_${r}`)
          }
          .width('100%')
        }

        if (!this.bootLoading && this.loadError.length > 0) {
          Text(this.loadError)
            .fontSize(14)
            .fontColor(Color.Red)
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })
        }

        if (!this.bootLoading) {
          Column() {
            // 时间轴仅叠在「可滚动图区」上，不覆盖顶栏/分类芯片，也不压多选底部操作条（该条在本 Stack 外）
            Stack({ alignContent: Alignment.TopEnd }) {
          // 官方 Refresh：offset 为触发刷新所需下拉距离（vp）；friction 略增使下拉更「实在」
          Refresh({ refreshing: this.galleryTimelineRefreshing, offset: GALLERY_TIMELINE_REFRESH_OFFSET_VP, friction: 78 }) {
            List({ scroller: this.scrollerRef }) {
            LazyForEach(this.flowDataSource, (node: GalleryFlowNode) => {
              if (node.kind === 'month') {
                ListItem() {
                  Text(`${node.year}年${node.month}月`)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 20, bottom: 4 })
                }
              } else if (node.kind === 'day') {
                ListItem() {
                  Text(`${node.month}月${node.day}日`)
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 2, bottom: 4 })
                }
              } else {
                // row 节点 —— 手势方案遵循鸿蒙官方文档最佳实践：
                //   ① 点击：每个缩略图 Stack 上用 .onClick()（事件回调，不参与手势竞争，与 List 滚动零冲突）
                //   ② 长按：Row 上 parallelGesture(LongPressGesture) — 长按需静止，与滚动天然不冲突
                //   ③ 划选 Pan：多选且未在划选段时仅 Horizontal，纵向交给 List；进入划选后改为 All 以跨行。
                //      非多选态 onGestureJudgeBegin 对 Pan REJECT，List 滚动畅通。
                ListItem() {
                  Row({ space: 2 }) {
                    ForEach(node.rowSlotItems, (slot: GalleryListItem | null, k: number) => {
                      if (slot !== null && slot !== undefined) {
                        this.buildGalleryTimelineThumbCell(slot, node.rowSlotFlatIndices[k])
                      } else {
                        if (this.timelineSidebarDragging) {
                          GalleryStaticThumbPlaceholder({
                            animatePulse: this.timelineSidebarDragging
                          })
                            .layoutWeight(1)
                            .aspectRatio(1)
                        } else {
                          GalleryThumbSkeleton()
                            .layoutWeight(1)
                            .aspectRatio(1)
                        }
                      }
                    }, (slot: GalleryListItem | null, k: number) => {
                      const fi = node.rowSlotFlatIndices[k];
                      if (slot !== null && slot !== undefined && fi >= 0) {
                        return `ti_${fi}`;
                      }
                      return `sk_${node.key}_${k}`;
                    })
                    if (node.rowSlotItems.length === 1) {
                      Blank().layoutWeight(1)
                      Blank().layoutWeight(1)
                    }
                    if (node.rowSlotItems.length === 2) {
                      Blank().layoutWeight(1)
                    }
                  }
                  .width('100%')
                  .padding({ left: 2, right: 2, top: 1, bottom: 1 })
                  .parallelGesture(GestureGroup(GestureMode.Parallel,
                    LongPressGesture({ repeat: false, duration: 420 })
                      .onAction((ev: GestureEvent): void => {
                        // 上一轮若未收到 Pan End/Cancel，gallerySlideGestureActive 会残留，导致二次长按无法 begin
                        this.endGallerySlideSelectGesture();
                        const pt = this.readGestureFingerWindow(ev);
                        if (pt === null) {
                          return;
                        }
                        const xPx = vp2px(pt.x);
                        const yPx = vp2px(pt.y);
                        const fi = this.pickGalleryThumbFlatForRowOrCache(node, xPx, yPx);
                        if (fi < 0) {
                          return;
                        }
                        const all = this.flatItems();
                        if (fi >= all.length) {
                          return;
                        }
                        const longPressItem = all[fi];
                        this.onGalleryThumbLongPress(longPressItem);
                        if (!this.gallerySelectionMode) {
                          return;
                        }
                        if (this.gallerySlideGestureActive) {
                          return;
                        }
                        this.beginGallerySlideSelectGesture(ev, longPressItem, fi);
                      }),
                    PanGesture({
                      fingers: 1,
                      direction: this.gallerySlideGestureActive ? PanDirection.All : PanDirection.Horizontal,
                      distance: this.gallerySlideGestureActive ? GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE :
                        GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE
                    })
                      .onActionStart((ev: GestureEvent): void => {
                        // 二次划选：多选下先横向拖动即进入划选（纵向由 Horizontal Pan 不接管，列表可滚）
                        if (!this.gallerySelectionMode) {
                          return;
                        }
                        if (this.gallerySlideGestureActive) {
                          this.endGallerySlideSelectGesture();
                        }
                        const pt = this.readGestureFingerWindow(ev);
                        if (pt === null) {
                          return;
                        }
                        const xPx = vp2px(pt.x);
                        const yPx = vp2px(pt.y);
                        const fi = this.pickGalleryThumbFlatForRowOrCache(node, xPx, yPx);
                        if (fi < 0) {
                          return;
                        }
                        const all = this.flatItems();
                        if (fi >= all.length) {
                          return;
                        }
                        this.beginGallerySlideSelectGesture(ev, all[fi], fi);
                      })
                      .onActionUpdate((ev: GestureEvent): void => {
                        this.onGallerySlidePanUpdate(ev);
                      })
                      .onActionEnd((): void => {
                        this.endGallerySlideSelectGesture();
                      })
                      .onActionCancel((): void => {
                        this.endGallerySlideSelectGesture();
                      })
                  ))
                  .onGestureJudgeBegin((gestureInfo: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
                    if (gestureInfo.type !== GestureControl.GestureType.PAN_GESTURE) {
                      return GestureJudgeResult.CONTINUE;
                    }
                    // 非多选：Row 的 Pan 不参与，List 独占纵向滑动
                    if (!this.gallerySelectionMode) {
                      return GestureJudgeResult.REJECT;
                    }
                    // 多选：未划选时为横向 Pan（不抢纵向）；划选中为全向 Pan，由 enableScrollInteraction(false) 避免与 List 抢
                    return GestureJudgeResult.CONTINUE;
                  })
                }
                .draggable(false)
              }
            }, (node: GalleryFlowNode) =>
              // 键不得包含 gallerySelectionMode：长按进入多选时若变 key 会重建子树，手势中断，滑动连选失效。多选态下 gesture 仍随 @State 重算。
              this.galleryFlowLazyKey(node))

            // 底部：仅状态文案 + 留白；分页由 pumpLoad 自驱动，不展示「加载中…」行
            ListItem() {
              Column({ space: 4 }) {
                if (this.footText.length > 0) {
                  Text(this.footText)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding(12)
                }
                Blank().height(this.gallerySelectionMode && this.gallerySelectedIds.length > 0 ? 88 : 32)
              }
              .width('100%')
            }
          }
            .width('100%')
            .height('100%')
            .cachedCount(this.isDraggingOrFling ? 3 : 16)
            .edgeEffect(EdgeEffect.Spring)
            // 系统滚动条由右侧时间轴细轨替代；BarState.Off 在部分机型上需配合宽度/透明色才彻底不绘制
            .scrollBar(BarState.Off)
            .scrollBarColor(Color.Transparent)
            .scrollBarWidth(0)
            .divider({ strokeWidth: 0 })
            .enableScrollInteraction(this.galleryMainListScrollEnabled)
            .onScrollIndex((firstIdx: number, lastIdx: number, _centerIdx: number): void => {
              this.listVisibleFirstNodeIdx = firstIdx;
              this.listVisibleLastNodeIdx = Math.max(firstIdx, lastIdx);
              this.refreshLastKnownGlobalSlotsFromListIndices(this.listVisibleFirstNodeIdx, this.listVisibleLastNodeIdx);
              this.captureListScrollIndexAnchor();
              if (this.timelineSidebarDragging || this.timelineSeekInProgress) {
                return;
              }
              this.syncTimelineHandleFromListThrottled(firstIdx);
              this.touchTimelineBarOnScroll();
            })
            .onDidScroll((_offset: number, _scrollState: ScrollState): void => {
              this.maybeLogMainScrollTick(_offset, _scrollState);
              const draggingOrFling = _scrollState === ScrollState.Scroll || _scrollState === ScrollState.Fling;
              // 时间轴松手后的程序化 seek 滚动不应再次把页面打回“冻结态”，否则会出现松手不出图。
              const shouldFreezeByListScroll =
                draggingOrFling && !this.timelineSeekInProgress && Date.now() >= this.ignoreListFreezeUntilMs;
              const wasDraggingOrFling = this.isDraggingOrFling;
              let stateChanged = false;
              if (shouldFreezeByListScroll) {
                if (!this.isDraggingOrFling) {
                  // 二次滚动立即打断旧 pump/settled 回调
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
                // 关键：Idle 时立刻释放占位，避免 loadVisible 长时间被 placeholder 阻断
                if (this.visualPlaceholderMode) {
                  this.visualPlaceholderMode = false;
                  stateChanged = true;
                }
                // 仅在“交互态 -> Idle”边沿调度，抑制 Idle 抖动反复触发 settled
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
            })
          }
          .width('100%')
          .height('100%')
          // 下拉位移：达到与 offset 相同的阈值时给一次震动（多选下不监听，避免无关回调）
          .onOffsetChange((offset: number): void => {
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
          })
          // 多选时关闭下拉触发刷新，避免 Refresh 与划选/长按争抢纵向手势
          .pullToRefresh(!this.gallerySelectionMode)
          .onRefreshing((): void => {
            void this.onGalleryTimelinePullRefresh();
          })

            if (this.sections.length > 0 || this.orderedDays.length > 0) {
              this.buildTimelineSidebar()
            }
          }
          .width('100%')
          .layoutWeight(1)
          .clip(false)

            if (this.gallerySelectionMode && this.gallerySelectedIds.length > 0) {
              Row({ space: GALLERY_BATCH_BAR_SPACE_VP }) {
                Button($r('app.string.gallery_batch_download'), { type: ButtonType.Capsule, stateEffect: true })
                  .layoutWeight(1)
                  .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.card_background'))
                  .enabled(!this.galleryBatchDownloading)
                  .onClick((): void => {
                    void this.confirmAndBatchDownloadGallery();
                  })
                Button($r('app.string.gallery_batch_delete'), { type: ButtonType.Capsule, stateEffect: true })
                  .layoutWeight(1)
                  .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
                  .fontColor(Color.White)
                  .backgroundColor(GALLERY_BATCH_DESTRUCTIVE_BG)
                  .enabled(!this.galleryBatchDeleting)
                  .onClick((): void => {
                    void this.confirmAndBatchDeleteGallery();
                  })
              }
              .width('100%')
              .padding({
                left: GALLERY_BATCH_BAR_PAD_LEFT_VP,
                right: GALLERY_BATCH_BAR_PAD_RIGHT_VP,
                top: GALLERY_BATCH_BAR_PAD_TOP_VP,
                bottom: GALLERY_BATCH_BAR_PAD_BOTTOM_VP
              })
              .backgroundColor($r('app.color.page_background'))
            }
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      if (this.galleryBatchDeleting) {
        FnFullLoadingMask({ text: '移入回收站中…' })
      }
      if (this.galleryBatchDownloading) {
        FnFullLoadingMask({ text: '下载中…' })
      }
      if (this.recentOpening) {
        FnFullLoadingMask({ text: '加载最近添加中…' })
      }
      if (this.collectOpening) {
        FnFullLoadingMask({ text: '加载收藏中…' })
      }

      // 仅在图库主视图显示上传入口，避免与子模式操作冲突
      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
        if (this.uploading) {
          FnFullLoadingMask({ text: this.uploadText.length > 0 ? this.uploadText : '上传中…' })
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
