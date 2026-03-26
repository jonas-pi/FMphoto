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
  MagicSearchItem
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
        Text(this.inSearchMode ? 'AI 搜索结果' : '图库')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (!this.inSearchMode) {
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
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // ── 搜索栏 ──────────────────────────────────────────────────────────────
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
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

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

      // ── 图库视图 ──────────────────────────────────────────────────────────────
      if (!this.inSearchMode) {
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
