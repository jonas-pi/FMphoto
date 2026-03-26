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
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { SessionPreferences } from '../auth/SessionPreferences';
import {
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
import { GalleryPreviewNavStore } from './GalleryPreviewNavStore';
import { CategoryGalleryNavStore } from './CategoryGalleryNavStore';

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
  /** WaterFlow + LazyForEach 数据源（与 sections 同步） */
  private flowDataSource: GalleryWaterFlowDataSource = new GalleryWaterFlowDataSource();

  private loadGen: number = 0;
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
    GalleryPreviewNavStore.openPreview(this.baseUrl, this.flatItems(), flatIndex, this.getUIContext());
  }

  // ── 搜索 ──────────────────────────────────────────────────────────────────

  /** 执行 AI 语义搜索并展示结果 */
  private async runSearch(keyword: string): Promise<void> {
    const kw = keyword.trim();
    if (kw.length === 0) {
      return;
    }
    this.inSearchMode = true;
    this.inCategoryMode = false;
    this.inSmartCategoryMode = false;
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
    this.inSearchMode = false;
    this.inCategoryMode = true;
    this.inSmartCategoryMode = false;
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
    const directVals: Array<number | undefined> = [
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
      if (v !== undefined && Number.isFinite(Number(v))) {
        return Math.max(0, Math.floor(Number(v)));
      }
    }
    // 兼容服务端字段变更：从原始对象中按常见计数字段名兜底提取
    const raw = item as unknown as Record<string, string | number | Object | undefined>;
    const keys: string[] = ['count', 'total', 'itemCount', 'item_count', 'photoCount', 'photo_count', 'num', 'size'];
    for (let i = 0; i < keys.length; i++) {
      const v = raw[keys[i]];
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
    this.inSearchMode = false;
    this.inCategoryMode = false;
    this.inSmartCategoryMode = true;
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
      const sceneRes = await client.getSmartRecCategories('scene', -1);
      const infoRes = await client.getSmartRecCategories('information', -1);
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

  // ── 生命周期 ─────────────────────────────────────────────────────────────

  private onEpochChange(): void {
    setTimeout((): void => { void this.bootstrap(); }, 0);
  }

  aboutToAppear(): void {
    setTimeout((): void => { void this.bootstrap(); }, 0);
  }

  // ── sections 更新 ────────────────────────────────────────────────────────

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

  // ── 数据加载 ─────────────────────────────────────────────────────────────

  private async bootstrap(): Promise<void> {
    const gen = ++this.loadGen;
    this.exhausted = false;
    this.dayIndex = 0;
    this.orderedDays = [];
    this.dayOffsets.clear();
    this.dayRounds.clear();
    this.dayEmptyRounds.clear();
    this.bootLoading = true;
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

    const tl = await workClient.getGalleryTimeline();
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
      return;
    }

    this.orderedDays = cells;
    this.bootLoading = false;
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
      this.exhausted = true;
      this.footText = '已加载全部照片';
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
      const res = await client.getGalleryList(st, et, DATE_FEED_BATCH, off, 'index');
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

  // ── build ──────────────────────────────────────────────────────────────────

  build() {
    Column() {
      // ── 顶部标题栏 ──────────────────────────────────────────────────────────
      Row() {
        Text(this.inSearchMode ? 'AI 搜索结果' : (this.inCategoryMode ? '媒体分类' : (this.inSmartCategoryMode ? '智能分类' : '图库')))
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode) {
          Button($r('app.string.gallery_refresh'), { type: ButtonType.Capsule, stateEffect: true })
            .fontSize(14)
            .height(36)
            .onClick((): void => {
              void this.bootstrap();
            })
        } else {
          Button('返回图库', { type: ButtonType.Capsule, stateEffect: true })
            .fontSize(14)
            .height(36)
            .onClick((): void => {
              this.clearSearch();
              this.clearCategory();
              this.clearSmartCategory();
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // ── 搜索栏（仅在“图库”主页面显示）─────────────────────────────────────────
      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode) {
        Row({ space: 8 }) {
          TextInput({ placeholder: 'AI 搜索照片…', text: this.searchQuery })
            .layoutWeight(1)
            .height(40)
            .borderRadius(20)
            .backgroundColor($r('app.color.card_background'))
            .fontSize(14)
            .placeholderColor($r('app.color.text_secondary'))
            .onChange((val: string): void => {
              this.searchQuery = val;
            })
            .onSubmit((): void => {
              void this.runSearch(this.searchQuery);
            })
          Button() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([$r('app.color.icon_primary')])
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.card_background'))
          .onClick((): void => {
            void this.runSearch(this.searchQuery);
          })
          Button() {
            Text('分类')
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
          }
          .height(40)
          .padding({ left: 12, right: 12 })
          .borderRadius(20)
          .backgroundColor($r('app.color.card_background'))
          .onClick((): void => {
            void this.loadMediaCategories();
          })
          Button() {
            Text('智能')
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
          }
          .height(40)
          .padding({ left: 12, right: 12 })
          .borderRadius(20)
          .backgroundColor($r('app.color.card_background'))
          .onClick((): void => {
            void this.loadSmartCategories();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
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
            // 搜索结果 3 列网格
            Grid() {
              ForEach(this.searchResults, (item: GalleryListItem, idx: number) => {
                GridItem() {
                  GalleryNetworkThumb({
                    uri: nasUrl(this.baseUrl, pickThumb(item)),
                    isVideo: isVideoItem(item),
                    isGif: isGifItem(item),
                  })
                  .width('100%')
                  .aspectRatio(1)
                  .onClick((): void => {
                    GalleryPreviewNavStore.openPreview(
                      this.baseUrl, this.searchResults, idx, this.getUIContext()
                    );
                  })
                }
              }, (item: GalleryListItem, idx: number) => `sr_${idx}_${pickThumb(item)}`)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(2)
            .rowsGap(2)
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)

            Blank().height(32)
          }
        }
        .width('100%')
        .layoutWeight(1)
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
              .width('100%')
              .height('100%')
              .padding({ left: 12, right: 12, top: 8 })
              .scrollBar(BarState.Auto)
              .edgeEffect(EdgeEffect.Spring)

              // 点击分类后等待网络响应时的加载遮罩
              if (this.categoryOpening) {
                Column({ space: 12 }) {
                  LoadingProgress().width(48).height(48).color(Color.White)
                  Text('加载中…')
                    .fontSize(14)
                    .fontColor(Color.White)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor('#80000000')
                .hitTestBehavior(HitTestMode.Block)
              }
            }
            .width('100%')
            .layoutWeight(1)
          }
        }
        .width('100%')
        .layoutWeight(1)
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
      }

      // ── 图库视图 ──────────────────────────────────────────────────────────────
      if (!this.inSearchMode && !this.inCategoryMode && !this.inSmartCategoryMode) {
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
                // row 节点：1~3 张缩略图水平排列
                ListItem() {
                  Row({ space: 2 }) {
                    ForEach(node.rowItems, (item: GalleryListItem, k: number) => {
                      GalleryNetworkThumb({
                        uri: nasUrl(this.baseUrl, pickThumb(item)),
                        isVideo: isVideoItem(item),
                        isGif: isGifItem(item),
                      })
                      .layoutWeight(1)
                      .aspectRatio(1)
                      .onClick((): void => {
                        this.openPreview(node.rowFlatIndices[k]);
                      })
                    }, (item: GalleryListItem, k: number) => `ti_${node.rowFlatIndices[k]}`)
                    // 末行不足 3 项时用空白占位，保持列宽一致
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
                }
              }
            }, (node: GalleryFlowNode) => node.key)

            // 底部状态行（foot / 加载中 / 底部留白）
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
                if (!this.exhausted && this.sections.length > 0) {
                  Row() {
                    LoadingProgress().width(24).height(24)
                    Text('加载中…').fontSize(12).fontColor($r('app.color.text_secondary')).margin({ left: 8 })
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                  .padding(12)
                }
                Blank().height(32)
              }
              .width('100%')
            }
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(4)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
          .divider({ strokeWidth: 0 })
          .onDidScroll((_offset: number, _scrollState: ScrollState): void => {
            if (!this.exhausted && !this.loadingMore && !this.bootLoading) {
              this.pumpLoad();
            }
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
