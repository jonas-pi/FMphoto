/**
 * 媒体分类浏览页：展示某一分类（照片/视频/动图等）内所有媒体，
 * 按日期降序分组，3 列网格，点击进入大图预览。
 */
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { GalleryListItem } from '../model/FnApiTypes';
import {
  GalleryNetworkThumb,
  isGifItem,
  isVideoItem,
  nasUrl,
  pickThumb
} from '../album/GalleryAlbumCommon';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import { GalleryPreviewNavStore } from '../album/GalleryPreviewNavStore';
import { GalleryDeleteSyncStore } from '../album/GalleryDeleteSyncStore';
import { AppSession } from '../auth/AppSession';
import { FnStateText, FnTopBar } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';

// ─── 数据模型 ─────────────────────────────────────────────────────────────────

/** 一行 3 格（不足 3 格时 c1/c2 为 undefined） */
interface RowModel {
  /** 该行第一项在组内的索引，用于计算全局 flat 索引 */
  startIdx: number;
  c0: GalleryListItem;
  c1: GalleryListItem | undefined;
  c2: GalleryListItem | undefined;
}

interface DayGroup {
  label: string;
  sortKey: string;
  rows: RowModel[];
  count: number;
}

// ─── 工具函数 ─────────────────────────────────────────────────────────────────

/** 从 "YYYY:MM:DD HH:mm:ss" 中提取 "YYYY-MM-DD" */
function parseDateKey(dateTime: string | undefined): string {
  if (dateTime === undefined || dateTime.length === 0) {
    return '1970-01-01';
  }
  const spaceIdx = dateTime.indexOf(' ');
  const datePart = spaceIdx > 0 ? dateTime.substring(0, spaceIdx) : dateTime;
  const segs = datePart.split(':');
  if (segs.length < 3) {
    return '1970-01-01';
  }
  const y = segs[0].padStart(4, '0');
  const m = segs[1].padStart(2, '0');
  const d = segs[2].padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function fmtDayLabel(sortKey: string): string {
  const parts = sortKey.split('-');
  if (parts.length < 3) {
    return sortKey;
  }
  return `${parts[0]}年${parseInt(parts[1], 10)}月${parseInt(parts[2], 10)}日`;
}

function groupByDate(items: GalleryListItem[]): DayGroup[] {
  const keyOrder: string[] = [];
  const mapItems: Map<string, GalleryListItem[]> = new Map();

  for (let i = 0; i < items.length; i++) {
    const key = parseDateKey(items[i].dateTime);
    if (!mapItems.has(key)) {
      mapItems.set(key, []);
      keyOrder.push(key);
    }
    (mapItems.get(key) as GalleryListItem[]).push(items[i]);
  }

  keyOrder.sort((a: string, b: string): number => {
    if (a > b) { return -1; }
    if (a < b) { return 1; }
    return 0;
  });

  const groups: DayGroup[] = [];
  for (let ki = 0; ki < keyOrder.length; ki++) {
    const key = keyOrder[ki];
    const dayItems = mapItems.get(key) as GalleryListItem[];
    const rows: RowModel[] = [];
    for (let ri = 0; ri < dayItems.length; ri += 3) {
      rows.push({
        startIdx: ri,
        c0: dayItems[ri],
        c1: ri + 1 < dayItems.length ? dayItems[ri + 1] : undefined,
        c2: ri + 2 < dayItems.length ? dayItems[ri + 2] : undefined,
      });
    }
    groups.push({ label: fmtDayLabel(key), sortKey: key, rows: rows, count: dayItems.length });
  }
  return groups;
}

// ─── 页面 ─────────────────────────────────────────────────────────────────────

@Entry
@Component
struct CategoryGallery {
  @State private groups: DayGroup[] = [];
  @State private title: string = '';
  @State private baseUrl: string = '';
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  /**
   * 用 @State 镜像深色标志：@StorageProp 在嵌套方法链中依赖追踪可能丢失，
   * @State 变更则必定触发 build() 重渲染，保证背景色实时同步。
   */
  @State private isDarkTheme: boolean = false;
  private flatItems: GalleryListItem[] = [];
  /** 每组在 flatItems 中的起始偏移 */
  private groupOffsets: number[] = [];
  /** 上次已处理的删除同步版本号 */
  private handledDeleteSyncVersion: number = 0;

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  private isDark(): boolean { return this.isDarkTheme; }

  /** 设置系统状态栏/导航栏颜色与页面背景保持一致，消除黑白配 */
  private applySystemBar(): void {
    try {
      const dark = this.isDarkTheme;
      const bg = dark ? '#FF1C1C1E' : '#FFF5F5F5';
      const content = dark ? '#FFFFFFFF' : '#FF000000';
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win): void => {
        win.setWindowSystemBarProperties({
          statusBarColor: bg,
          navigationBarColor: bg,
          statusBarContentColor: content,
          navigationBarContentColor: content
        }).catch((_e: Error): void => {});
      }).catch((_e: Error): void => {});
    } catch (_e) {}
  }

  onPageShow(): void {
    this.applyDeleteSyncIfNeeded();
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar();
  }

  onColorModeChanged(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.applySystemBar();
  }

  aboutToAppear(): void {
    this.isDarkTheme = this.colorMode === 1;
    this.baseUrl = CategoryGalleryNavStore.baseUrl;
    this.title = CategoryGalleryNavStore.title;
    const raw = CategoryGalleryNavStore.items;
    this.groups = groupByDate(raw);
    // 预览数据顺序必须与网格展示顺序一致，否则会出现“点这张打开另一张”
    const ordered: GalleryListItem[] = [];
    for (let gi = 0; gi < this.groups.length; gi++) {
      const rows = this.groups[gi].rows;
      for (let ri = 0; ri < rows.length; ri++) {
        ordered.push(rows[ri].c0);
        if (rows[ri].c1 !== undefined) {
          ordered.push(rows[ri].c1 as GalleryListItem);
        }
        if (rows[ri].c2 !== undefined) {
          ordered.push(rows[ri].c2 as GalleryListItem);
        }
      }
    }
    this.flatItems = ordered;
    let offset = 0;
    this.groupOffsets = [];
    for (let gi = 0; gi < this.groups.length; gi++) {
      this.groupOffsets.push(offset);
      offset += this.groups[gi].count;
    }
  }

  aboutToDisappear(): void {
    const client = AppSession.getClient();
    if (client !== null) {
      client.cancelPendingRequests();
    }
    CategoryGalleryNavStore.clear();
  }

  private openItem(groupIdx: number, idxInGroup: number): void {
    const base = groupIdx < this.groupOffsets.length ? this.groupOffsets[groupIdx] : 0;
    GalleryPreviewNavStore.openPreview(
      this.baseUrl,
      this.flatItems,
      base + idxInGroup
    );
  }

  private itemIdOf(it: GalleryListItem): string {
    if (it.id === undefined || it.id === null) {
      return '';
    }
    return String(it.id).trim();
  }

  /**
   * 按当前 flatItems 重建分组与偏移，不触发路由重建，尽量保持滚动位置。
   */
  private rebuildByFlatItems(): void {
    this.groups = groupByDate(this.flatItems);
    this.groupOffsets = [];
    let offset = 0;
    for (let gi = 0; gi < this.groups.length; gi++) {
      this.groupOffsets.push(offset);
      offset += this.groups[gi].count;
    }
  }

  /**
   * 从预览页返回时，按删除同步仓做增量删除；
   * 仅修改当前数据，不走整页重载，避免打断用户当前位置。
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
    // 数据尚未就绪时不消费版本号，避免删除同步被提前“吃掉”。
    if (this.flatItems.length === 0) {
      return;
    }
    const kept: GalleryListItem[] = [];
    let changed = false;
    for (let i = 0; i < this.flatItems.length; i++) {
      const id = this.itemIdOf(this.flatItems[i]);
      if (id.length > 0 && ids.indexOf(id) >= 0) {
        changed = true;
        continue;
      }
      kept.push(this.flatItems[i]);
    }
    if (changed) {
      this.flatItems = kept;
      this.rebuildByFlatItems();
      // 与当前页面会话源保持一致，避免二次进入时回弹已删项。
      CategoryGalleryNavStore.items = kept.slice();
    }
    this.handledDeleteSyncVersion = GalleryDeleteSyncStore.version;
  }

  @Builder
  private thumbCell(item: GalleryListItem, groupIdx: number, idxInGroup: number) {
    GalleryNetworkThumb({
      uri: nasUrl(this.baseUrl, pickThumb(item)),
      isVideo: isVideoItem(item),
      isGif: isGifItem(item),
    })
      .layoutWeight(1)
      .aspectRatio(1)
      .onClick((): void => {
        this.openItem(groupIdx, idxInGroup);
      })
  }

  build() {
    Column() {
      FnTopBar({
        title: this.title.length > 0 ? this.title : '媒体分类',
        rightText: `${this.flatItems.length} 项`
      })

      // ── 日期分组列表 ──────────────────────────────────────────────────────
      if (this.groups.length === 0) {
        FnStateText({ text: '暂无媒体' })
      } else {
        List() {
          ForEach(this.groups, (group: DayGroup, groupIdx: number) => {
            // 日期标题
            ListItem() {
              Text(group.label)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .padding({ left: 16, top: 14, bottom: 6 })
            }

            // 每行最多 3 格
            ForEach(group.rows, (row: RowModel) => {
              ListItem() {
                Row({ space: 2 }) {
                  this.thumbCell(row.c0, groupIdx, row.startIdx)
                  if (row.c1 !== undefined) {
                    this.thumbCell(row.c1 as GalleryListItem, groupIdx, row.startIdx + 1)
                  } else {
                    Blank().layoutWeight(1).aspectRatio(1)
                  }
                  if (row.c2 !== undefined) {
                    this.thumbCell(row.c2 as GalleryListItem, groupIdx, row.startIdx + 2)
                  } else {
                    Blank().layoutWeight(1).aspectRatio(1)
                  }
                }
                .width('100%')
                .padding({ left: 2, right: 2 })
              }
              .margin({ bottom: 2 })
            }, (row: RowModel) => `r_${groupIdx}_${row.startIdx}`)
          }, (group: DayGroup) => `g_${group.sortKey}`)
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(3)
        .scrollBar(BarState.Off)
        .backgroundColor(Color.Transparent)
        .edgeEffect(EdgeEffect.Spring)
        .divider({ strokeWidth: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 12, y: 0 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: -8, y: 0 });
  }
}
