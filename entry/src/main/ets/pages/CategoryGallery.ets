/**
 * 媒体分类浏览页：展示某一分类（照片/视频/动图等）内所有媒体，
 * 按日期降序分组，3 列网格；长按 + 滑动连选、批量下载/删除（与图库主时间线交互一致）。
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
import { GalleryTimelineRefreshStore } from '../album/GalleryTimelineRefreshStore';
import {
  galleryItemsMatchingSelectedIds,
  runBatchDownloadGalleryItems
} from '../album/GalleryBatchDownload';
import { playGalleryEnterSelectionHaptic } from '../album/GallerySelectionHaptic';
import { AppSession } from '../auth/AppSession';
import { FnFullLoadingMask, FnStateText } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
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
  GALLERY_BATCH_DESTRUCTIVE_BG
} from '../common/GalleryButtonStyles';
import {
  GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE,
  GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE,
  pickIndexedFlatForSlidePointer
} from '../album/GallerySlidePick';

// ─── 数据模型 ─────────────────────────────────────────────────────────────────

/** 一行 3 格（不足 3 格时 c1/c2 为 undefined） */
interface RowModel {
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

interface CgThumbHitRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

interface CgFingerWindowPoint {
  x: number;
  y: number;
}

interface CgFingerCoordCompat {
  windowX?: number;
  windowY?: number;
  globalX?: number;
  globalY?: number;
  screenX?: number;
  screenY?: number;
  displayX?: number;
  displayY?: number;
  x?: number;
  y?: number;
}

// ─── 工具函数 ─────────────────────────────────────────────────────────────────

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

function groupByDate(items: GalleryListItem[], useCreatedAt: boolean = false): DayGroup[] {
  const keyOrder: string[] = [];
  const mapItems: Map<string, GalleryListItem[]> = new Map();

  for (let i = 0; i < items.length; i++) {
    /**
     * 最近添加模式优先使用 createdAt（入库时间）做分组日期；
     * 其它场景维持 dateTime（拍摄时间）分组。
     * 这样可保证“最近添加”按最近入库日期靠前，同时不改变同一天内原始顺序。
     */
    const dt = useCreatedAt ? (items[i].createdAt ?? items[i].dateTime) : items[i].dateTime;
    const key = parseDateKey(dt);
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
  @State private isDarkTheme: boolean = false;
  private flatItems: GalleryListItem[] = [];
  private groupOffsets: number[] = [];
  private handledDeleteSyncVersion: number = 0;

  @State private selectionMode: boolean = false;
  @State private selectedIds: string[] = [];
  @State private cgSlideGestureActive: boolean = false;
  @State private cgScrollEnabled: boolean = true;
  @State private cgBatchDeleting: boolean = false;
  @State private cgBatchDownloading: boolean = false;

  private cgLongPressIgnoreUntil: number = 0;
  private cgThumbHitBounds: Map<string, CgThumbHitRect> = new Map();
  private cgSlideRefX: number = 0;
  private cgSlideRefY: number = 0;
  private cgSlideHasRef: boolean = false;
  private cgSlideAnchorFlat: number = -1;
  private cgSlideUnionBase: string[] = [];
  private cgSlideLastEndFlat: number = -1;
  private cgSlideLastAppliedEndFlat: number = -99999;

  onBackPress(): boolean {
    if (this.selectionMode) {
      this.exitCgSelection();
      return true;
    }
    this.getUIContext().getRouter().back();
    return true;
  }

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
    const useCreatedAt = this.title.trim() === '最近添加';
    this.groups = groupByDate(raw, useCreatedAt);
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

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {}
  }

  private itemIdOf(it: GalleryListItem): string {
    if (it.id === undefined || it.id === null) {
      return '';
    }
    return String(it.id).trim();
  }

  private flatPos(groupIdx: number, idxInGroup: number): number {
    const base = groupIdx >= 0 && groupIdx < this.groupOffsets.length ? this.groupOffsets[groupIdx] : 0;
    return base + idxInGroup;
  }

  private cgDomId(flatIdx: number): string {
    return `cgcell_${flatIdx}`;
  }

  private exitCgSelection(): void {
    this.selectionMode = false;
    this.selectedIds = [];
    this.endCgSlideSelectGesture();
    this.cgLongPressIgnoreUntil = 0;
    this.cgThumbHitBounds.clear();
  }

  private toggleToolbarMode(): void {
    if (this.selectionMode) {
      this.exitCgSelection();
    } else {
      this.selectionMode = true;
    }
  }

  private isCgIdSelected(id: string): boolean {
    return id.length > 0 && this.selectedIds.indexOf(id) >= 0;
  }

  private setCgSelectedIds(next: string[]): void {
    this.selectedIds = next;
  }

  private toggleCgId(id: string): void {
    if (id.length === 0) {
      return;
    }
    const idx = this.selectedIds.indexOf(id);
    if (idx >= 0) {
      const next: string[] = [];
      for (let i = 0; i < this.selectedIds.length; i++) {
        if (i !== idx) {
          next.push(this.selectedIds[i]);
        }
      }
      this.setCgSelectedIds(next);
    } else {
      const next: string[] = this.selectedIds.slice();
      next.push(id);
      this.setCgSelectedIds(next);
    }
  }

  private readGestureFingerWindow(ev: GestureEvent): CgFingerWindowPoint | null {
    const fl = ev.fingerList;
    if (fl === undefined || fl.length < 1) {
      return null;
    }
    const f0 = fl[0] as CgFingerCoordCompat;
    const x = f0.windowX ?? f0.globalX ?? f0.screenX ?? f0.displayX ?? f0.x;
    const y = f0.windowY ?? f0.globalY ?? f0.screenY ?? f0.displayY ?? f0.y;
    if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
      return null;
    }
    const out: CgFingerWindowPoint = { x: x, y: y };
    return out;
  }

  private panOffsetVpToPx(deltaVp: number): number {
    const probePx = 100;
    const probeVp = px2vp(probePx);
    if (probeVp < 0.0001) {
      return deltaVp;
    }
    return deltaVp * (probePx / probeVp);
  }

  private recordCgThumbRect(flatIdx: number): void {
    if (flatIdx < 0 || flatIdx >= this.flatItems.length) {
      return;
    }
    try {
      const info = this.getUIContext().getComponentUtils().getRectangleById(this.cgDomId(flatIdx));
      const x = info.windowOffset.x as number;
      const y = info.windowOffset.y as number;
      const w = info.size.width as number;
      const h = info.size.height as number;
      if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
        this.cgThumbHitBounds.delete(`${flatIdx}`);
        return;
      }
      const rect: CgThumbHitRect = { left: x, top: y, right: x + w, bottom: y + h };
      this.cgThumbHitBounds.set(`${flatIdx}`, rect);
    } catch (_e) {
    }
  }

  private hitCgThumbDomPx(flatIdx: number, xPx: number, yPx: number): boolean {
    if (flatIdx < 0 || flatIdx >= this.flatItems.length) {
      return false;
    }
    try {
      const info = this.getUIContext().getComponentUtils().getRectangleById(this.cgDomId(flatIdx));
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

  private pickCgFlatUnderPoint(xPx: number, yPx: number): number {
    const n = this.flatItems.length;
    if (this.cgThumbHitBounds.size === 0 || n <= 0) {
      return -1;
    }
    for (let i = n - 1; i >= 0; i--) {
      const cached = this.cgThumbHitBounds.get(`${i}`);
      if (cached === undefined) {
        continue;
      }
      if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
        return i;
      }
    }
    return -1;
  }

  private pickCgFlatForRow(rowStart: number, xPx: number, yPx: number): number {
    const n = this.flatItems.length;
    const fromCache = this.pickCgFlatUnderPoint(xPx, yPx);
    if (fromCache >= rowStart && fromCache < rowStart + 3 && fromCache < n) {
      return fromCache;
    }
    for (let k = 2; k >= 0; k--) {
      const fi = rowStart + k;
      if (fi >= n) {
        continue;
      }
      const cached = this.cgThumbHitBounds.get(`${fi}`);
      if (cached !== undefined) {
        if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
          return fi;
        }
        continue;
      }
      if (this.hitCgThumbDomPx(fi, xPx, yPx)) {
        return fi;
      }
    }
    return -1;
  }

  private pickCgFlatForSlidePointer(xPx: number, yPx: number): number {
    return pickIndexedFlatForSlidePointer(
      xPx,
      yPx,
      this.flatItems.length,
      this.cgSlideLastEndFlat,
      this.cgSlideAnchorFlat,
      (ax: number, ay: number): number => this.pickCgFlatUnderPoint(ax, ay),
      (fi: number) => this.cgThumbHitBounds.get(`${fi}`),
      (fi: number, ax: number, ay: number): boolean => this.hitCgThumbDomPx(fi, ax, ay),
      (fi: number): void => {
        this.recordCgThumbRect(fi);
      }
    );
  }

  private collectCgIdsInFlatRange(lo: number, hi: number): string[] {
    let a = lo;
    let b = hi;
    if (a > b) {
      const t = a;
      a = b;
      b = t;
    }
    const out: string[] = [];
    const n = this.flatItems.length;
    for (let fi = a; fi <= b && fi < n; fi++) {
      const id = this.itemIdOf(this.flatItems[fi]);
      if (id.length > 0) {
        out.push(id);
      }
    }
    return out;
  }

  private applyCgSlideRowRangeSelection(endFlat: number): void {
    if (this.cgSlideAnchorFlat < 0) {
      return;
    }
    const ef = endFlat >= 0 ? endFlat : this.cgSlideAnchorFlat;
    if (this.cgSlideGestureActive && ef === this.cgSlideLastAppliedEndFlat) {
      return;
    }
    let lo = this.cgSlideAnchorFlat;
    let hi = ef;
    if (lo > hi) {
      const t = lo;
      lo = hi;
      hi = t;
    }
    const rangeIds = this.collectCgIdsInFlatRange(lo, hi);
    const seen = new Set<string>();
    const next: string[] = [];
    const base = this.cgSlideUnionBase;
    for (let i = 0; i < base.length; i++) {
      seen.add(base[i]);
      next.push(base[i]);
    }
    for (let i = 0; i < rangeIds.length; i++) {
      const id = rangeIds[i];
      if (id.length > 0 && !seen.has(id)) {
        seen.add(id);
        next.push(id);
      }
    }
    this.cgSlideLastAppliedEndFlat = ef;
    this.setCgSelectedIds(next);
  }

  private beginCgSlideSelectGesture(ev: GestureEvent, anchorFlat: number): void {
    this.cgSlideGestureActive = true;
    this.cgScrollEnabled = false;
    this.cgSlideAnchorFlat = anchorFlat >= 0 ? anchorFlat : -1;
    this.cgSlideUnionBase = this.selectedIds.slice();
    this.cgSlideLastEndFlat = this.cgSlideAnchorFlat;
    this.cgSlideLastAppliedEndFlat = -99999;
    this.recordCgThumbRect(anchorFlat);
    const win = this.readGestureFingerWindow(ev);
    if (win !== null) {
      this.cgSlideRefX = vp2px(win.x);
      this.cgSlideRefY = vp2px(win.y);
      this.cgSlideHasRef = true;
    } else {
      const cached = this.cgThumbHitBounds.get(`${anchorFlat}`);
      if (cached !== undefined) {
        this.cgSlideRefX = (cached.left + cached.right) * 0.5;
        this.cgSlideRefY = (cached.top + cached.bottom) * 0.5;
        this.cgSlideHasRef = true;
      } else {
        this.cgSlideHasRef = false;
      }
    }
    this.applyCgSlideRowRangeSelection(this.cgSlideLastEndFlat);
  }

  private endCgSlideSelectGesture(): void {
    if (!this.cgSlideGestureActive && this.cgScrollEnabled) {
      return;
    }
    this.cgSlideGestureActive = false;
    this.cgSlideHasRef = false;
    this.cgSlideAnchorFlat = -1;
    this.cgSlideUnionBase = [];
    this.cgSlideLastEndFlat = -1;
    this.cgSlideLastAppliedEndFlat = -99999;
    this.cgScrollEnabled = true;
  }

  private resolveCgSlidePointerWindowPx(ev: GestureEvent): CgFingerWindowPoint | null {
    const win = this.readGestureFingerWindow(ev);
    if (win !== null) {
      const px: CgFingerWindowPoint = { x: vp2px(win.x), y: vp2px(win.y) };
      return px;
    }
    if (!this.cgSlideHasRef) {
      return null;
    }
    const out: CgFingerWindowPoint = {
      x: this.cgSlideRefX + this.panOffsetVpToPx(ev.offsetX),
      y: this.cgSlideRefY + this.panOffsetVpToPx(ev.offsetY)
    };
    return out;
  }

  private onCgSlidePanUpdate(ev: GestureEvent): void {
    if (!this.cgSlideGestureActive) {
      return;
    }
    const pt = this.resolveCgSlidePointerWindowPx(ev);
    if (pt === null) {
      return;
    }
    const hitFlat = this.pickCgFlatForSlidePointer(pt.x, pt.y);
    if (hitFlat >= 0) {
      this.cgSlideLastEndFlat = hitFlat;
    }
    this.applyCgSlideRowRangeSelection(this.cgSlideLastEndFlat);
  }

  private onCgThumbLongPress(item: GalleryListItem, flatIdx: number): void {
    const id = this.itemIdOf(item);
    if (id.length === 0) {
      this.toast('该媒体无 ID，无法多选');
      return;
    }
    if (this.cgSlideGestureActive) {
      return;
    }
    this.cgLongPressIgnoreUntil = Date.now() + 500;
    if (!this.selectionMode) {
      playGalleryEnterSelectionHaptic();
      this.selectionMode = true;
      this.setCgSelectedIds([id]);
    } else {
      this.toggleCgId(id);
    }
  }

  private openItemAtFlat(flatIdx: number): void {
    if (flatIdx < 0 || flatIdx >= this.flatItems.length) {
      return;
    }
    GalleryPreviewNavStore.openPreview(this.baseUrl, this.flatItems, flatIdx);
  }

  private onCgCellClick(item: GalleryListItem, flatIdx: number): void {
    if (Date.now() < this.cgLongPressIgnoreUntil) {
      return;
    }
    const id = this.itemIdOf(item);
    if (this.selectionMode) {
      if (id.length > 0) {
        this.toggleCgId(id);
      }
      return;
    }
    this.openItemAtFlat(flatIdx);
  }

  private rowGlobalStartFlat(groupIdx: number, row: RowModel): number {
    return this.flatPos(groupIdx, row.startIdx);
  }

  private async askCgBatchDownloadQuality(): Promise<'original' | 'thumb' | 'cancel'> {
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

  private async confirmCgBatchDownload(): Promise<void> {
    if (this.selectedIds.length === 0 || this.cgBatchDownloading) {
      return;
    }
    const items = galleryItemsMatchingSelectedIds(this.flatItems, this.selectedIds);
    if (items.length === 0) {
      this.toast('没有可下载的项');
      return;
    }
    this.cgBatchDownloading = true;
    try {
      await runBatchDownloadGalleryItems(
        this.baseUrl,
        items,
        (msg: string): void => {
          this.toast(msg);
        },
        (): Promise<'original' | 'thumb' | 'cancel'> => this.askCgBatchDownloadQuality()
      );
    } finally {
      this.cgBatchDownloading = false;
    }
  }

  private async confirmCgBatchDelete(): Promise<void> {
    if (this.selectedIds.length === 0 || this.cgBatchDeleting) {
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
    this.cgBatchDeleting = true;
    const ids = this.selectedIds.slice();
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
      this.cgBatchDeleting = false;
    }
    GalleryTimelineRefreshStore.bump();
    this.toast(`已移入回收站 ${ok}/${ids.length}`);
    this.exitCgSelection();
    this.applyDeleteSyncIfNeeded();
  }

  private rebuildByFlatItems(): void {
    const useCreatedAt = this.title.trim() === '最近添加';
    this.groups = groupByDate(this.flatItems, useCreatedAt);
    this.groupOffsets = [];
    let offset = 0;
    for (let gi = 0; gi < this.groups.length; gi++) {
      this.groupOffsets.push(offset);
      offset += this.groups[gi].count;
    }
  }

  private applyDeleteSyncIfNeeded(): void {
    if (this.handledDeleteSyncVersion === GalleryDeleteSyncStore.version) {
      return;
    }
    const ids = GalleryDeleteSyncStore.snapshotIds();
    if (ids.length === 0) {
      this.handledDeleteSyncVersion = GalleryDeleteSyncStore.version;
      return;
    }
    /**
     * 预览删除后 GalleryPreview 会先改掉 CategoryGalleryNavStore；若本页尚未重跑 aboutToAppear，
     * flatItems 可能仍为空，先前直接 return 且不推进 handled 版本会导致界面永远不刷。
     */
    if (this.flatItems.length === 0 && CategoryGalleryNavStore.items.length > 0) {
      this.flatItems = CategoryGalleryNavStore.items.slice();
    }
    if (this.flatItems.length === 0) {
      this.handledDeleteSyncVersion = GalleryDeleteSyncStore.version;
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
      CategoryGalleryNavStore.items = kept.slice();
    }
    this.handledDeleteSyncVersion = GalleryDeleteSyncStore.version;
  }

  @Builder
  private thumbCellWithFlat(item: GalleryListItem, flatIdx: number) {
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
        .opacity(this.selectionMode && this.isCgIdSelected(this.itemIdOf(item)) ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
      Row() {
        Blank().layoutWeight(1)
        Column() {
          if (this.isCgIdSelected(this.itemIdOf(item))) {
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
      .visibility(this.selectionMode ? Visibility.Visible : Visibility.Hidden)
    }
    .width('100%')
    .layoutWeight(1)
    .aspectRatio(1)
    .id(this.cgDomId(flatIdx))
    .onAreaChange((): void => {
      this.recordCgThumbRect(flatIdx);
    })
    .onClick((): void => {
      this.onCgCellClick(item, flatIdx);
    })
  }

  build() {
    Column() {
      Row() {
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Button($r('app.string.gallery_batch_cancel'), { type: ButtonType.Capsule, stateEffect: true })
              .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .backgroundColor($r('app.color.button_primary_bg'))
              .fontColor($r('app.color.button_primary_fg'))
              .visibility(this.selectionMode ? Visibility.Visible : Visibility.Hidden)
              .onClick((): void => {
                this.exitCgSelection();
              })
            Button('返回', { type: ButtonType.Capsule, stateEffect: true })
              .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .backgroundColor($r('app.color.button_secondary_bg'))
              .fontColor($r('app.color.button_secondary_fg'))
              .visibility(this.selectionMode ? Visibility.Hidden : Visibility.Visible)
              .onClick((): void => {
                this.getUIContext().getRouter().back();
              })
          }
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.Start)

        Text(this.selectionMode ? `已选 ${this.selectedIds.length} 项` : (this.title.length > 0 ? this.title : '媒体分类'))
          .layoutWeight(2)
          .fontSize(this.selectionMode ? GALLERY_TOP_BAR_SUBTITLE_FONT_VP : GALLERY_TOP_BAR_TITLE_FONT_VP)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.text_primary'))

        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Button(this.selectionMode ? '完成' : $r('app.string.gallery_multiselect'), { type: ButtonType.Capsule, stateEffect: true })
              .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
              .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
              .backgroundColor($r('app.color.button_secondary_bg'))
              .fontColor($r('app.color.button_secondary_fg'))
              .onClick((): void => {
                this.toggleToolbarMode();
              })
          }
        }
        .layoutWeight(1)
        .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .padding({
        left: GALLERY_TOP_BAR_PAD_LEFT_VP,
        right: GALLERY_TOP_BAR_PAD_RIGHT_VP,
        top: GALLERY_TOP_BAR_PAD_TOP_VP,
        bottom: GALLERY_TOP_BAR_PAD_BOTTOM_VP
      })
      .alignItems(VerticalAlign.Center)

      Text(`${this.flatItems.length} 项`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ left: 16, bottom: 4 })
        .visibility(this.selectionMode ? Visibility.Hidden : Visibility.Visible)

      if (this.groups.length === 0) {
        FnStateText({ text: '暂无媒体' }).layoutWeight(1)
      } else {
        Stack() {
          Column() {
          List() {
            ForEach(this.groups, (group: DayGroup, groupIdx: number) => {
              ListItem() {
                Text(group.label)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .padding({ left: 16, top: 14, bottom: 6 })
              }

              ForEach(group.rows, (row: RowModel) => {
                ListItem() {
                  Row({ space: 2 }) {
                    this.thumbCellWithFlat(row.c0, this.flatPos(groupIdx, row.startIdx))
                    if (row.c1 !== undefined) {
                      this.thumbCellWithFlat(row.c1 as GalleryListItem, this.flatPos(groupIdx, row.startIdx + 1))
                    } else {
                      Blank().layoutWeight(1).aspectRatio(1)
                    }
                    if (row.c2 !== undefined) {
                      this.thumbCellWithFlat(row.c2 as GalleryListItem, this.flatPos(groupIdx, row.startIdx + 2))
                    } else {
                      Blank().layoutWeight(1).aspectRatio(1)
                    }
                  }
                  .width('100%')
                  .padding({ left: 2, right: 2, top: 1, bottom: 1 })
                  .parallelGesture(GestureGroup(GestureMode.Parallel,
                    LongPressGesture({ repeat: false, duration: 420 })
                      .onAction((ev: GestureEvent): void => {
                        this.endCgSlideSelectGesture();
                        const rowStart = this.rowGlobalStartFlat(groupIdx, row);
                        const pt = this.readGestureFingerWindow(ev);
                        if (pt === null) {
                          return;
                        }
                        const xPx = vp2px(pt.x);
                        const yPx = vp2px(pt.y);
                        const fi = this.pickCgFlatForRow(rowStart, xPx, yPx);
                        if (fi < 0 || fi >= this.flatItems.length) {
                          return;
                        }
                        const longPressItem = this.flatItems[fi];
                        this.onCgThumbLongPress(longPressItem, fi);
                        if (!this.selectionMode) {
                          return;
                        }
                        if (this.cgSlideGestureActive) {
                          return;
                        }
                        this.beginCgSlideSelectGesture(ev, fi);
                      }),
                    PanGesture({
                      fingers: 1,
                      direction: this.cgSlideGestureActive ? PanDirection.All : PanDirection.Horizontal,
                      distance: this.cgSlideGestureActive ? GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE :
                        GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE
                    })
                      .onActionStart((ev: GestureEvent): void => {
                        if (!this.selectionMode) {
                          return;
                        }
                        if (this.cgSlideGestureActive) {
                          this.endCgSlideSelectGesture();
                        }
                        const rowStart = this.rowGlobalStartFlat(groupIdx, row);
                        const pt = this.readGestureFingerWindow(ev);
                        if (pt === null) {
                          return;
                        }
                        const xPx = vp2px(pt.x);
                        const yPx = vp2px(pt.y);
                        const fi = this.pickCgFlatForRow(rowStart, xPx, yPx);
                        if (fi < 0 || fi >= this.flatItems.length) {
                          return;
                        }
                        this.beginCgSlideSelectGesture(ev, fi);
                      })
                      .onActionUpdate((ev: GestureEvent): void => {
                        this.onCgSlidePanUpdate(ev);
                      })
                      .onActionEnd((): void => {
                        this.endCgSlideSelectGesture();
                      })
                      .onActionCancel((): void => {
                        this.endCgSlideSelectGesture();
                      })
                  ))
                  .onGestureJudgeBegin((gestureInfo: GestureInfo, _event: BaseGestureEvent): GestureJudgeResult => {
                    if (gestureInfo.type !== GestureControl.GestureType.PAN_GESTURE) {
                      return GestureJudgeResult.CONTINUE;
                    }
                    if (!this.selectionMode) {
                      return GestureJudgeResult.REJECT;
                    }
                    return GestureJudgeResult.CONTINUE;
                  })
                }
                .draggable(false)
                .margin({ bottom: 2 })
              }, (row: RowModel) => `r_${groupIdx}_${row.startIdx}`)
            }, (group: DayGroup) => `g_${group.sortKey}`)
            ListItem() {
              Column() {
                Blank()
                  .width('100%')
                  .height(this.selectionMode && this.selectedIds.length > 0 ? 88 : 24)
              }
              .width('100%')
            }
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(4)
          .scrollBar(BarState.Auto)
          .backgroundColor(Color.Transparent)
          .edgeEffect(EdgeEffect.Spring)
          .divider({ strokeWidth: 0 })
          .enableScrollInteraction(this.cgScrollEnabled)
          .onDidScroll((_offset: number, _scrollState: ScrollState): void => {
            if (!this.cgSlideGestureActive && !this.cgScrollEnabled) {
              this.cgScrollEnabled = true;
            }
            if (!this.cgSlideGestureActive) {
              this.cgThumbHitBounds.clear();
            }
          })

          if (this.selectionMode && this.selectedIds.length > 0) {
            Row({ space: GALLERY_BATCH_BAR_SPACE_VP }) {
              Button($r('app.string.gallery_batch_download'), { type: ButtonType.Capsule, stateEffect: true })
                .layoutWeight(1)
                .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.card_background'))
                .enabled(!this.cgBatchDownloading)
                .onClick((): void => {
                  void this.confirmCgBatchDownload();
                })
              Button($r('app.string.gallery_batch_delete'), { type: ButtonType.Capsule, stateEffect: true })
                .layoutWeight(1)
                .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
                .fontColor(Color.White)
                .backgroundColor(GALLERY_BATCH_DESTRUCTIVE_BG)
                .enabled(!this.cgBatchDeleting)
                .onClick((): void => {
                  void this.confirmCgBatchDelete();
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
          .height('100%')

          if (this.cgBatchDeleting || this.cgBatchDownloading) {
            FnFullLoadingMask({ text: this.cgBatchDeleting ? '移入回收站中…' : '下载中…' })
          }
        }
        .layoutWeight(1)
        .width('100%')
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
