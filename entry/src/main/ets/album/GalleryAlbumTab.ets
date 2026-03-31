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
 * 缩略图：WaterFlow + LazyForEach 懒加载；鉴权下载与 LRU 见 GalleryAlbumCommon。
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
/** 上传成功后二次拉时间轴间隔（ms）：NAS 入库略延迟时提高新图出现概率 */
const GALLERY_UPLOAD_RECHECK_MS = 1600;
/** 最近添加分页条数：与抓包量级一致，减少往返次数同时避免单次过大 */
const GALLERY_RECENT_PAGE_LIMIT = 60;
/** 最近添加单日分页安全上限：防止服务端异常导致死循环 */
const GALLERY_RECENT_DAY_MAX_ROUNDS = 200;

/** 主时间线缩略图滑动连选：用于指尖坐标与缩略图区域相交判断（窗口坐标系，与 getRectangleById 一致） */
interface GalleryThumbHitRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
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
  items: GalleryListItem[] = [];
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
   * 划选锚点：长按起始缩略图在扁平列表中的下标（与 flow row 的 rowFlatIndices 一致，行优先 3 列一行）。
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
    for (let i = 0; i < this.sections.length; i++) {
      const items = this.sections[i].items;
      for (let j = 0; j < items.length; j++) {
        out.push(items[j]);
      }
    }
    return out;
  }

  /** 由 sections 重建 List 节点（月/日标题 + 按行分组的缩略图行）并通知 LazyForEach */
  private rebuildFlow(): void {
    const nodes: GalleryFlowNode[] = [];
    let flat = 0;
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
      // 按 3 项分行
      let ri = 0;
      while (ri < sec.items.length) {
        const rn = new GalleryFlowNode();
        rn.kind = 'row';
        rn.key = `r_${flat}`;
        const cnt = Math.min(3, sec.items.length - ri);
        for (let k = 0; k < cnt; k++) {
          rn.rowItems.push(sec.items[ri + k]);
          rn.rowFlatIndices.push(flat + k);
        }
        nodes.push(rn);
        flat += cnt;
        ri += cnt;
      }
    }
    this.flowDataSource.reloadAll(nodes);
  }

  private openPreview(flatIndex: number): void {
    if (flatIndex < 0) {
      return;
    }
    GalleryPreviewNavStore.openPreview(this.baseUrl, this.flatItems(), flatIndex);
  }

  private itemIdOf(it: GalleryListItem): string {
    if (it.id === undefined || it.id === null) {
      return '';
    }
    return String(it.id).trim();
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
      for (let k = node.rowItems.length - 1; k >= 0; k--) {
        const id = this.itemIdOf(node.rowItems[k]);
        if (id.length === 0) {
          continue;
        }
        const cached = this.galleryThumbHitBounds.get(id);
        if (cached === undefined) {
          continue;
        }
        if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
          return node.rowFlatIndices[k];
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
      for (let k = node.rowItems.length - 1; k >= 0; k--) {
        const id = this.itemIdOf(node.rowItems[k]);
        if (id.length === 0) {
          continue;
        }
        const flat = node.rowFlatIndices[k];
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
        for (let k = 0; k < node.rowItems.length; k++) {
          if (node.rowFlatIndices[k] === seed) {
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
    for (let k = node.rowItems.length - 1; k >= 0; k--) {
      const id = this.itemIdOf(node.rowItems[k]);
      if (id.length === 0) {
        continue;
      }
      const cached = this.galleryThumbHitBounds.get(id);
      if (cached !== undefined) {
        if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
          return node.rowFlatIndices[k];
        }
        continue;
      }
      if (this.hitGalleryThumbDomPx(id, xPx, yPx)) {
        return node.rowFlatIndices[k];
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
    let flat = 0;
    for (let si = 0; si < this.sections.length; si++) {
      const items = this.sections[si].items;
      const secEnd = flat + items.length - 1;
      if (secEnd < a) {
        flat += items.length;
        continue;
      }
      for (let j = 0; j < items.length; j++) {
        const fi = flat;
        flat++;
        if (fi > b) {
          return out;
        }
        if (fi >= a) {
          const id = this.itemIdOf(items[j]);
          if (id.length > 0) {
            out.push(id);
          }
        }
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
    this.openPreview(flatIndex);
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
      const kept: GalleryListItem[] = [];
      for (let i = 0; i < sec.items.length; i++) {
        const id = this.itemIdOf(sec.items[i]);
        if (id.length > 0 && ids.indexOf(id) >= 0) {
          changed = true;
          continue;
        }
        kept.push(sec.items[i]);
      }
      if (kept.length !== sec.items.length) {
        sec.items = kept;
      }
      if (sec.items.length === 0) {
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

  private parsePersonTimeline(
    rawList: Array<Record<string, string | number | undefined>>
  ): TimelineDayModel[] {
    const out: TimelineDayModel[] = [];
    for (let i = 0; i < rawList.length; i++) {
      const x = rawList[i];
      let y = 0;
      let m = 0;
      let d = 0;
      const yy = x['year'];
      const mm = x['month'];
      const dd = x['day'];
      if (typeof yy === 'number' && typeof mm === 'number' && typeof dd === 'number') {
        y = Math.floor(yy);
        m = Math.floor(mm);
        d = Math.floor(dd);
      } else {
        const stRaw = x['start_time'] ?? x['startTime'];
        const st = stRaw !== undefined ? String(stRaw) : '';
        if (st.length < 10) {
          continue;
        }
        const space = st.indexOf(' ');
        const date = space > 0 ? st.substring(0, space) : st;
        const seg = date.split(':');
        if (seg.length < 3) {
          continue;
        }
        y = Number(seg[0]);
        m = Number(seg[1]);
        d = Number(seg[2]);
      }
      if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) {
        continue;
      }
      const cRaw =
        x['itemCount'] ?? x['item_count'] ?? x['count'] ?? x['total'] ?? x['size'] ?? x['num'];
      const c = cRaw !== undefined && Number.isFinite(Number(cRaw)) ? Math.max(0, Math.floor(Number(cRaw))) : 0;
      out.push({ year: Math.floor(y), month: Math.floor(m), day: Math.floor(d), itemCount: c });
    }
    return sortDaysDesc(out);
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
    let title = this.personName(item);
    // 跳转成功后短延时关闭 loading；失败路径立即关闭
    let keepOpening = false;
    try {
      const client = AppSession.getClient();
      if (client === null) {
        this.toast('未登录');
        return;
      }
      // 对齐官方链路：先请求 detail（用于后端侧缓存/统计链路）
      const detail = await client.getAiPersonDetail(pid);
      let detailItemCount = 0;
      if (detail.success && detail.data !== undefined) {
        if (detail.data.name !== undefined && detail.data.name.length > 0) {
          title = detail.data.name;
        }
        const cntRaw = detail.data.itemCount;
        if (cntRaw !== undefined && Number.isFinite(Number(cntRaw))) {
          detailItemCount = Math.max(0, Math.floor(Number(cntRaw)));
        }
      }

      const tl = await client.getAiPersonPhotoTimeline(pid);
      if (!tl.success || tl.data === undefined) {
        this.toast(tl.message ?? '人物时间线加载失败');
        return;
      }
      const raw = tl.data.list ?? [];
      const rawIn: Array<Record<string, string | number | undefined>> = [];
      for (let i = 0; i < raw.length; i++) {
        const el = raw[i];
        if (typeof el === 'object' && el !== null) {
          rawIn.push(el as Record<string, string | number | undefined>);
        }
      }
      const days = this.parsePersonTimeline(rawIn);
      const merged: GalleryListItem[] = [];
      for (let di = 0; di < days.length; di++) {
        const day = days[di];
        const st = fmtDayStart(day.year, day.month, day.day);
        const et = fmtDayEnd(day.year, day.month, day.day);
        let off = 0;
        let rounds = 0;
        while (rounds < DAY_MAX_ROUNDS) {
          const one = await client.getAiPersonPhotoList(pid, st, et, DATE_FEED_BATCH, off, 20000);
          if (!one.success || one.data === undefined) {
            break;
          }
          const list = listFromData(one.data);
          if (list.length === 0) {
            break;
          }
          for (let i = 0; i < list.length; i++) {
            merged.push(list[i]);
          }
          off += list.length;
          rounds++;
          if (detailItemCount > 0 && merged.length >= detailItemCount) {
            break;
          }
          if (list.length < DATE_FEED_BATCH) {
            break;
          }
          if (day.itemCount > 0 && off >= day.itemCount) {
            break;
          }
        }
      }
      if (merged.length === 0) {
        this.toast('该人物暂无可预览媒体');
        return;
      }
      keepOpening = true;
      const opened = await CategoryGalleryNavStore.open(this.baseUrl, title, merged, this.getUIContext());
      if (!opened) {
        keepOpening = false;
        this.toast('打开人物媒体失败');
        return;
      }
      // 给路由切换一点缓冲，避免加载动画收起与转场间出现空档
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
      sectionsPlain.push({
        year: s.year,
        month: s.month,
        day: s.day,
        itemCount: s.itemCount,
        nextOffset: s.nextOffset,
        items: s.items.slice()
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
      sec.items = p.items.slice();
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
      n += this.sections[i].items.length;
    }
    return n;
  }

  private upsertSection(day: TimelineDayModel, newItems: GalleryListItem[], newOffset: number): void {
    const idx = this.sections.findIndex(
      (s: DaySectionModel): boolean =>
        s.year === day.year && s.month === day.month && s.day === day.day
    );
    if (idx < 0) {
      const sec = new DaySectionModel();
      sec.year = day.year;
      sec.month = day.month;
      sec.day = day.day;
      sec.itemCount = day.itemCount;
      sec.items = newItems.slice();
      sec.nextOffset = newOffset;
      this.sections = this.sections.concat([sec]);
    } else {
      const sec = this.sections[idx];
      for (let i = 0; i < newItems.length; i++) {
        sec.items.push(newItems[i]);
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
    // 停留在 AI 搜索/分类/人物等子视图时勿拉主时间线，避免「退回主界面像重载」；离开子视图时再消费 bump（见 backToGallery）
    if (this.inSearchMode || this.inCategoryMode || this.inSmartCategoryMode || this.inPersonMode) {
      return;
    }
    if (GalleryTimelineRefreshStore.version > this.lastBootstrapSatisfiedRefreshVersion) {
      this.requestBootstrap(true);
    }
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
  private pumpLoad(): void {
    if (this.loadingMore || this.exhausted) {
      return;
    }
    /**
     * bootstrap 在 await getGalleryTimeline 之前会同步清空 orderedDays。
     * 此窗口内若 onDidScroll / 上次泵的 setTimeout 触发 pumpLoad，loadOneBatch 会看到 dayIndex>=length 且 length===0，
     * 误判为「已扫完所有日」并 exhausted=true，随后新时间轴回填后 pumpLoad 被直接 return，表现为空列表 +「已加载全部照片」。
     */
    if (this.orderedDays.length === 0) {
      return;
    }
    this.loadingMore = true;
    const gen = this.loadGen;
    void this.loadOneBatch().then((added: number): void => {
      this.loadingMore = false;
      if (gen !== this.loadGen || this.exhausted) {
        return;
      }
      if (added === -1) {
        // 耗尽或已被新的 loadGen 取消，停止泵
        return;
      }
      if (added === -2) {
        // 网络错误，3 秒后重试（避免频繁失败）
        setTimeout((): void => {
          this.pumpLoad();
        }, 3000);
        return;
      }
      if (added === -3) {
        // 时间轴显示仍有剩余但本批空：同一 offset 稍后重试（避免误切日 + 减轻压力）
        setTimeout((): void => {
          this.pumpLoad();
        }, 500);
        return;
      }
      // added >= 0：有数据时等一帧供 UI；切日时立即继续
      setTimeout((): void => {
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
        hilog.warn(DOMAIN, TAG,
          'short page end day %{public}s off=%{public}d got=%{public}d newOff=%{public}d itemCount=%{public}d',
          key, off, list.length, newOff, day.itemCount);
        this.dayIndex++;
        return list.length;
      }

      const emptyNow = list.length === 0 ? (emptyRounds + 1) : 0;
      const timelineSaysMore = day.itemCount > 0 && newOff < day.itemCount;
      const transientEmpty = list.length === 0 && timelineSaysMore;

      hilog.warn(DOMAIN, TAG,
        'batch %{public}s off=%{public}d got=%{public}d newOff=%{public}d itemCount=%{public}d total=%{public}s emptyRounds=%{public}d transient=%{public}d',
        key, off, list.length, newOff, day.itemCount,
        total !== undefined ? String(total) : 'n/a',
        list.length === 0 ? (emptyRounds + 1) : 0,
        transientEmpty ? 1 : 0);

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
      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode && !this.inPersonMode) {
        Row({ space: 8 }) {
          Button() {
            Text('媒体分类')
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
          .visibility(this.gallerySelectionMode ? Visibility.Hidden : Visibility.Visible)
          .enabled(!this.gallerySelectionMode)
          .onClick((): void => {
            this.exitGallerySelection();
            this.playModeSwitchMotion();
            void this.openRecentAdded();
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
                    ForEach(node.rowItems, (item: GalleryListItem, k: number) => {
                      this.buildGalleryTimelineThumbCell(item, node.rowFlatIndices[k])
                    }, (item: GalleryListItem, k: number) => `ti_${node.rowFlatIndices[k]}`)
                    if (node.rowItems.length === 1) {
                      Blank().layoutWeight(1)
                      Blank().layoutWeight(1)
                    }
                    if (node.rowItems.length === 2) {
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
              node.key)

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
            .cachedCount(4)
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
            .divider({ strokeWidth: 0 })
            .enableScrollInteraction(this.galleryMainListScrollEnabled)
            .onDidScroll((_offset: number, _scrollState: ScrollState): void => {
              this.syncGalleryTimelineAtTopForPull();
              // 划选异常未收到 End/Cancel 时 scrollEnabled 可能一直为 false；能滚动时在此恢复
              if (!this.gallerySlideGestureActive && !this.galleryMainListScrollEnabled) {
                this.galleryMainListScrollEnabled = true;
              }
              if (!this.gallerySlideGestureActive) {
                this.clearGalleryThumbHitBounds();
              }
              if (!this.exhausted && !this.loadingMore && !this.bootLoading) {
                this.pumpLoad();
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
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
