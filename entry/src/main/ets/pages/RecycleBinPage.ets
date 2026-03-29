/**
 * 相册回收站：列表 + 多选恢复（GET recycle-bin/list，POST recycle-bin/restore）
 * 多选手势与图库主时间线一致：每行 Row + LongPress + Pan 划选 + 命中矩形缓存。
 */
import { AppSession } from '../auth/AppSession';
import { GalleryPreviewNavStore } from '../album/GalleryPreviewNavStore';
import { playGalleryEnterSelectionHaptic } from '../album/GallerySelectionHaptic';
import { GalleryListItem, RecycleBinListItem } from '../model/FnApiTypes';
import { GalleryNetworkThumb, nasUrl } from '../album/GalleryAlbumCommon';
import { runBatchDownloadGalleryItems } from '../album/GalleryBatchDownload';
import { FnFullLoadingMask, FnInlineLoading, FnStateText } from '../common/FnUiCommon';
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
  GALLERY_BATCH_BAR_SPACE_VP
} from '../common/GalleryButtonStyles';
import {
  GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE,
  GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE,
  pickIndexedFlatForSlidePointer
} from '../album/GallerySlidePick';

const RB_PAGE_LIMIT = 80;
const RB_SAFETY_MAX_OFFSET = 50000;

function fmtRecycleApiTime(d: Date): string {
  const y = d.getFullYear();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  const h = d.getHours();
  const mi = d.getMinutes();
  const s = d.getSeconds();
  const p2 = (n: number): string => n.toString().padStart(2, '0');
  return `${y}:${p2(m)}:${p2(day)} ${p2(h)}:${p2(mi)}:${p2(s)}`;
}

interface RbThumbHitRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

interface RbFingerWindowPoint {
  x: number;
  y: number;
}

interface RbFingerCoordCompat {
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

@Entry
@Component
struct RecycleBinPage {
  @State private baseUrl: string = '';
  @State private loading: boolean = false;
  @State private restoring: boolean = false;
  @State private rbBatchDownloading: boolean = false;
  @State private error: string = '';
  @State private items: RecycleBinListItem[] = [];
  @State private selectionMode: boolean = false;
  @State private selectedIds: number[] = [];
  /** 划选进行中：Pan 切全向，并暂时关闭 List 滚动 */
  @State private rbSlideGestureActive: boolean = false;
  @State private rbScrollEnabled: boolean = true;

  private rbLongPressIgnoreUntil: number = 0;
  private rbThumbHitBounds: Map<string, RbThumbHitRect> = new Map();
  private rbSlideRefX: number = 0;
  private rbSlideRefY: number = 0;
  private rbSlideHasRef: boolean = false;
  private rbSlideAnchorFlat: number = -1;
  private rbSlideUnionBase: number[] = [];
  private rbSlideLastEndFlat: number = -1;
  private rbSlideLastAppliedEndFlat: number = -99999;

  onBackPress(): boolean {
    if (this.selectionMode) {
      this.exitSelection();
      return true;
    }
    this.getUIContext().getRouter().back();
    return true;
  }

  aboutToAppear(): void {
    const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
    if (rp !== undefined && rp['baseUrl'] !== undefined) {
      this.baseUrl = String(rp['baseUrl']);
    }
    void this.loadAll();
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {}
  }

  private rbDomId(flatIdx: number): string {
    return `rbcell_${flatIdx}`;
  }

  private exitSelection(): void {
    this.selectionMode = false;
    this.selectedIds = [];
    this.endRbSlideSelectGesture();
    this.rbLongPressIgnoreUntil = 0;
    this.rbThumbHitBounds.clear();
  }

  private toggleToolbarMode(): void {
    if (this.selectionMode) {
      this.exitSelection();
    } else {
      this.selectionMode = true;
    }
  }

  private numericIdOf(it: RecycleBinListItem): number {
    const raw = it.id;
    if (raw === undefined || raw === null) {
      return -1;
    }
    const n = Math.floor(Number(raw));
    return Number.isFinite(n) && n > 0 ? n : -1;
  }

  private thumbRelOf(it: RecycleBinListItem): string {
    const g = this.toGalleryItem(it);
    const t = g !== undefined ? g.thumb : undefined;
    return t !== undefined && t.length > 0 ? t : '';
  }

  private toGalleryItem(it: RecycleBinListItem): GalleryListItem | undefined {
    const nid = this.numericIdOf(it);
    const uuid = it.photoUUID !== undefined ? it.photoUUID.trim() : '';
    if (nid < 0 || uuid.length === 0) {
      return undefined;
    }
    const sid = `${nid}`;
    const thumb = `/p/api/v1/stream/p/t/${sid}/s/${uuid}`;
    const out: GalleryListItem = {
      id: sid,
      thumb: thumb,
      category: it.category,
      fileType: it.fileType,
      filename: it.fileName,
      name: it.fileName
    };
    return out;
  }

  private galleryListForRecycleSelection(): GalleryListItem[] {
    const out: GalleryListItem[] = [];
    const want = new Set<number>();
    for (let i = 0; i < this.selectedIds.length; i++) {
      want.add(this.selectedIds[i]);
    }
    for (let i = 0; i < this.items.length; i++) {
      const nid = this.numericIdOf(this.items[i]);
      if (nid >= 0 && want.has(nid)) {
        const g = this.toGalleryItem(this.items[i]);
        if (g !== undefined) {
          out.push(g);
        }
      }
    }
    return out;
  }

  private galleryListForPreview(): GalleryListItem[] {
    const out: GalleryListItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const g = this.toGalleryItem(this.items[i]);
      if (g !== undefined) {
        out.push(g);
      }
    }
    return out;
  }

  private previewIndexForFlatIndex(flatIdx: number): number {
    let k = 0;
    for (let i = 0; i < flatIdx && i < this.items.length; i++) {
      if (this.toGalleryItem(this.items[i]) !== undefined) {
        k++;
      }
    }
    return k;
  }

  private isIdSelected(nid: number): boolean {
    return this.selectedIds.indexOf(nid) >= 0;
  }

  private setRbSelectedIds(next: number[]): void {
    this.selectedIds = next;
  }

  private toggleIdSelected(nid: number): void {
    const idx = this.selectedIds.indexOf(nid);
    if (idx >= 0) {
      const next: number[] = [];
      for (let i = 0; i < this.selectedIds.length; i++) {
        if (i !== idx) {
          next.push(this.selectedIds[i]);
        }
      }
      this.setRbSelectedIds(next);
    } else {
      const next: number[] = [];
      for (let i = 0; i < this.selectedIds.length; i++) {
        next.push(this.selectedIds[i]);
      }
      next.push(nid);
      this.setRbSelectedIds(next);
    }
  }

  private readGestureFingerWindow(ev: GestureEvent): RbFingerWindowPoint | null {
    const fl = ev.fingerList;
    if (fl === undefined || fl.length < 1) {
      return null;
    }
    const f0 = fl[0] as RbFingerCoordCompat;
    const x = f0.windowX ?? f0.globalX ?? f0.screenX ?? f0.displayX ?? f0.x;
    const y = f0.windowY ?? f0.globalY ?? f0.screenY ?? f0.displayY ?? f0.y;
    if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
      return null;
    }
    const out: RbFingerWindowPoint = { x: x, y: y };
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

  private recordRbThumbRect(flatIdx: number): void {
    if (flatIdx < 0 || flatIdx >= this.items.length) {
      return;
    }
    try {
      const info = this.getUIContext().getComponentUtils().getRectangleById(this.rbDomId(flatIdx));
      const x = info.windowOffset.x as number;
      const y = info.windowOffset.y as number;
      const w = info.size.width as number;
      const h = info.size.height as number;
      if (!Number.isFinite(w) || !Number.isFinite(h) || w < 1 || h < 1) {
        this.rbThumbHitBounds.delete(`${flatIdx}`);
        return;
      }
      const rect: RbThumbHitRect = { left: x, top: y, right: x + w, bottom: y + h };
      this.rbThumbHitBounds.set(`${flatIdx}`, rect);
    } catch (_e) {
    }
  }

  private hitRbThumbDomPx(flatIdx: number, xPx: number, yPx: number): boolean {
    if (flatIdx < 0 || flatIdx >= this.items.length) {
      return false;
    }
    try {
      const info = this.getUIContext().getComponentUtils().getRectangleById(this.rbDomId(flatIdx));
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

  private pickRbThumbFlatUnderPoint(xPx: number, yPx: number): number {
    const n = this.items.length;
    if (this.rbThumbHitBounds.size === 0 || n <= 0) {
      return -1;
    }
    for (let i = n - 1; i >= 0; i--) {
      const cached = this.rbThumbHitBounds.get(`${i}`);
      if (cached === undefined) {
        continue;
      }
      if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
        return i;
      }
    }
    return -1;
  }

  private pickRbThumbFlatForRow(rowStart: number, xPx: number, yPx: number): number {
    const n = this.items.length;
    const fromCache = this.pickRbThumbFlatUnderPoint(xPx, yPx);
    if (fromCache >= rowStart && fromCache < rowStart + 3 && fromCache < n) {
      return fromCache;
    }
    for (let k = 2; k >= 0; k--) {
      const fi = rowStart + k;
      if (fi >= n) {
        continue;
      }
      const cached = this.rbThumbHitBounds.get(`${fi}`);
      if (cached !== undefined) {
        if (xPx >= cached.left && xPx <= cached.right && yPx >= cached.top && yPx <= cached.bottom) {
          return fi;
        }
        continue;
      }
      if (this.hitRbThumbDomPx(fi, xPx, yPx)) {
        return fi;
      }
    }
    return -1;
  }

  private pickRbThumbFlatForSlidePointer(xPx: number, yPx: number): number {
    return pickIndexedFlatForSlidePointer(
      xPx,
      yPx,
      this.items.length,
      this.rbSlideLastEndFlat,
      this.rbSlideAnchorFlat,
      (ax: number, ay: number): number => this.pickRbThumbFlatUnderPoint(ax, ay),
      (fi: number) => this.rbThumbHitBounds.get(`${fi}`),
      (fi: number, ax: number, ay: number): boolean => this.hitRbThumbDomPx(fi, ax, ay),
      (fi: number): void => {
        this.recordRbThumbRect(fi);
      }
    );
  }

  private collectRbIdsInFlatRange(lo: number, hi: number): number[] {
    let a = lo;
    let b = hi;
    if (a > b) {
      const t = a;
      a = b;
      b = t;
    }
    const out: number[] = [];
    const n = this.items.length;
    for (let fi = a; fi <= b && fi < n; fi++) {
      const nid = this.numericIdOf(this.items[fi]);
      if (nid >= 0) {
        out.push(nid);
      }
    }
    return out;
  }

  private applyRbSlideRowRangeSelection(endFlat: number): void {
    if (this.rbSlideAnchorFlat < 0) {
      return;
    }
    const ef = endFlat >= 0 ? endFlat : this.rbSlideAnchorFlat;
    if (this.rbSlideGestureActive && ef === this.rbSlideLastAppliedEndFlat) {
      return;
    }
    let lo = this.rbSlideAnchorFlat;
    let hi = ef;
    if (lo > hi) {
      const t = lo;
      lo = hi;
      hi = t;
    }
    const rangeIds = this.collectRbIdsInFlatRange(lo, hi);
    const seen = new Set<number>();
    const next: number[] = [];
    const base = this.rbSlideUnionBase;
    for (let i = 0; i < base.length; i++) {
      const v = base[i];
      seen.add(v);
      next.push(v);
    }
    for (let i = 0; i < rangeIds.length; i++) {
      const id = rangeIds[i];
      if (!seen.has(id)) {
        seen.add(id);
        next.push(id);
      }
    }
    this.rbSlideLastAppliedEndFlat = ef;
    this.setRbSelectedIds(next);
  }

  private beginRbSlideSelectGesture(ev: GestureEvent, anchorFlat: number): void {
    this.rbSlideGestureActive = true;
    this.rbScrollEnabled = false;
    this.rbSlideAnchorFlat = anchorFlat >= 0 ? anchorFlat : -1;
    this.rbSlideUnionBase = this.selectedIds.slice();
    this.rbSlideLastEndFlat = this.rbSlideAnchorFlat;
    this.rbSlideLastAppliedEndFlat = -99999;
    try {
      this.recordRbThumbRect(anchorFlat);
    } catch (_e) {}
    const win = this.readGestureFingerWindow(ev);
    if (win !== null) {
      this.rbSlideRefX = vp2px(win.x);
      this.rbSlideRefY = vp2px(win.y);
      this.rbSlideHasRef = true;
    } else {
      const cached = this.rbThumbHitBounds.get(`${anchorFlat}`);
      if (cached !== undefined) {
        this.rbSlideRefX = (cached.left + cached.right) * 0.5;
        this.rbSlideRefY = (cached.top + cached.bottom) * 0.5;
        this.rbSlideHasRef = true;
      } else {
        this.rbSlideHasRef = false;
      }
    }
    this.applyRbSlideRowRangeSelection(this.rbSlideLastEndFlat);
  }

  private endRbSlideSelectGesture(): void {
    if (!this.rbSlideGestureActive && this.rbScrollEnabled) {
      return;
    }
    this.rbSlideGestureActive = false;
    this.rbSlideHasRef = false;
    this.rbSlideAnchorFlat = -1;
    this.rbSlideUnionBase = [];
    this.rbSlideLastEndFlat = -1;
    this.rbSlideLastAppliedEndFlat = -99999;
    this.rbScrollEnabled = true;
  }

  private resolveSlidePointerWindowPx(ev: GestureEvent): RbFingerWindowPoint | null {
    const win = this.readGestureFingerWindow(ev);
    if (win !== null) {
      const px: RbFingerWindowPoint = { x: vp2px(win.x), y: vp2px(win.y) };
      return px;
    }
    if (!this.rbSlideHasRef) {
      return null;
    }
    const out: RbFingerWindowPoint = {
      x: this.rbSlideRefX + this.panOffsetVpToPx(ev.offsetX),
      y: this.rbSlideRefY + this.panOffsetVpToPx(ev.offsetY)
    };
    return out;
  }

  private onRbSlidePanUpdate(ev: GestureEvent): void {
    if (!this.rbSlideGestureActive) {
      return;
    }
    const pt = this.resolveSlidePointerWindowPx(ev);
    if (pt === null) {
      return;
    }
    const hitFlat = this.pickRbThumbFlatForSlidePointer(pt.x, pt.y);
    if (hitFlat >= 0) {
      this.rbSlideLastEndFlat = hitFlat;
    }
    this.applyRbSlideRowRangeSelection(this.rbSlideLastEndFlat);
  }

  private onRbThumbLongPress(it: RecycleBinListItem, flatIdx: number): void {
    const nid = this.numericIdOf(it);
    if (nid < 0) {
      this.toast('该条目无有效 ID，无法多选');
      return;
    }
    if (this.rbSlideGestureActive) {
      return;
    }
    this.rbLongPressIgnoreUntil = Date.now() + 500;
    if (!this.selectionMode) {
      playGalleryEnterSelectionHaptic();
      this.selectionMode = true;
      this.setRbSelectedIds([nid]);
    } else {
      this.toggleIdSelected(nid);
    }
  }

  private rbRowCount(): number {
    const n = this.items.length;
    return n <= 0 ? 0 : Math.floor((n + 2) / 3);
  }

  private rbRowIndexArray(): number[] {
    const c = this.rbRowCount();
    const out: number[] = [];
    for (let i = 0; i < c; i++) {
      out.push(i);
    }
    return out;
  }

  private async loadAll(): Promise<void> {
    this.loading = true;
    this.error = '';
    const client = AppSession.getClient();
    if (client === null) {
      this.loading = false;
      this.error = '未登录';
      return;
    }
    const endStr = fmtRecycleApiTime(new Date());
    const startStr = '2000:01:01 00:00:00';
    const merged: RecycleBinListItem[] = [];
    let offset = 0;
    try {
      for (;;) {
        const res = await client.getRecycleBinList(offset, RB_PAGE_LIMIT, startStr, endStr);
        if (!res.success || res.data === undefined) {
          this.error = res.message ?? '回收站列表加载失败';
          break;
        }
        const batch = res.data.list;
        if (!Array.isArray(batch)) {
          break;
        }
        for (let i = 0; i < batch.length; i++) {
          const el = batch[i];
          if (typeof el === 'object' && el !== null) {
            merged.push(el as RecycleBinListItem);
          }
        }
        if (batch.length < RB_PAGE_LIMIT) {
          break;
        }
        offset += RB_PAGE_LIMIT;
        if (offset > RB_SAFETY_MAX_OFFSET) {
          break;
        }
      }
      this.items = merged;
    } catch (e) {
      this.error = String(e) || '回收站列表加载失败';
    }
    this.loading = false;
  }

  private async askRbBatchDownloadQuality(): Promise<'original' | 'thumb' | 'cancel'> {
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

  private async confirmBatchDownloadRecycle(): Promise<void> {
    if (this.selectedIds.length === 0 || this.rbBatchDownloading) {
      return;
    }
    const items = this.galleryListForRecycleSelection();
    if (items.length === 0) {
      this.toast('没有可下载的项');
      return;
    }
    this.rbBatchDownloading = true;
    try {
      await runBatchDownloadGalleryItems(
        this.baseUrl,
        items,
        (msg: string): void => {
          this.toast(msg);
        },
        (): Promise<'original' | 'thumb' | 'cancel'> => this.askRbBatchDownloadQuality()
      );
    } finally {
      this.rbBatchDownloading = false;
    }
  }

  private async confirmRestore(): Promise<void> {
    if (this.selectedIds.length === 0) {
      this.toast('请先选择要还原的照片');
      return;
    }
    try {
      const dlg = await this.getUIContext().getPromptAction().showDialog({
        title: '还原到相册',
        message: `将还原已选的 ${this.selectedIds.length} 项，是否继续？`,
        buttons: [
          { text: '取消', color: '#99000000' },
          { text: '还原', color: '#0284C7' }
        ]
      });
      if (dlg.index !== 1) {
        return;
      }
    } catch (_e) {
      return;
    }
    void this.runRestore();
  }

  private async runRestore(): Promise<void> {
    if (this.restoring || this.selectedIds.length === 0) {
      return;
    }
    const client = AppSession.getClient();
    if (client === null) {
      this.toast('未登录');
      return;
    }
    this.restoring = true;
    const ids = this.selectedIds.slice();
    const res = await client.restoreRecycleBinPhotos(ids);
    this.restoring = false;
    if (!res.success) {
      this.toast(res.message ?? '还原失败');
      return;
    }
    this.toast('已提交还原');
    this.exitSelection();
    void this.loadAll();
  }

  private onCellClick(it: RecycleBinListItem, flatIdx: number): void {
    if (Date.now() < this.rbLongPressIgnoreUntil) {
      return;
    }
    const nid = this.numericIdOf(it);
    if (this.selectionMode) {
      if (nid >= 0) {
        this.toggleIdSelected(nid);
      }
      return;
    }
    const g = this.toGalleryItem(it);
    if (g === undefined) {
      this.toast('无法预览该项');
      return;
    }
    const list = this.galleryListForPreview();
    const pIdx = this.previewIndexForFlatIndex(flatIdx);
    GalleryPreviewNavStore.openPreview(this.baseUrl, list, pIdx);
  }

  @Builder
  private thumbCell(it: RecycleBinListItem, flatIdx: number, thumbRel: string, nid: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (thumbRel.length > 0) {
        GalleryNetworkThumb({
          uri: nasUrl(this.baseUrl, thumbRel),
          isVideo: false,
          isGif: false,
        })
          .width('100%')
          .aspectRatio(1)
      } else {
        Column() {
          Text('—')
            .fontSize(22)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .aspectRatio(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.card_background'))
      }
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#55000000')
        .opacity(this.selectionMode && nid >= 0 && this.isIdSelected(nid) ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
      Row() {
        Blank().layoutWeight(1)
        Column() {
          if (nid >= 0 && this.isIdSelected(nid)) {
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
    .layoutWeight(1)
    .aspectRatio(1)
    .id(this.rbDomId(flatIdx))
    .onAreaChange((): void => {
      this.recordRbThumbRect(flatIdx);
    })
    .onClick((): void => {
      this.onCellClick(it, flatIdx);
    })
  }

  @Builder
  private rbCellSlot(rowIdx: number, col: number) {
    if (rowIdx * 3 + col >= this.items.length) {
      Blank().layoutWeight(1).aspectRatio(1)
    } else {
      this.thumbCell(
        this.items[rowIdx * 3 + col],
        rowIdx * 3 + col,
        this.thumbRelOf(this.items[rowIdx * 3 + col]),
        this.numericIdOf(this.items[rowIdx * 3 + col])
      );
    }
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
                this.exitSelection();
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

        Text(this.selectionMode ? `已选 ${this.selectedIds.length} 项` : '回收站')
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

      if (this.loading) {
        FnInlineLoading({ text: '加载回收站…' }).layoutWeight(1)
      } else if (this.error.length > 0) {
        Column({ space: 12 }) {
          FnStateText({ text: this.error })
          Button('刷新')
            .onClick((): void => {
              void this.loadAll();
            })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.items.length === 0) {
        FnStateText({ text: '回收站为空' }).layoutWeight(1)
      } else {
        Stack() {
          Column() {
          List() {
            ForEach(this.rbRowIndexArray(), (rowIdx: number) => {
              ListItem() {
                Row({ space: 2 }) {
                  this.rbCellSlot(rowIdx, 0)
                  this.rbCellSlot(rowIdx, 1)
                  this.rbCellSlot(rowIdx, 2)
                }
                .width('100%')
                .padding({ left: 2, right: 2, top: 1, bottom: 1 })
                .parallelGesture(GestureGroup(GestureMode.Parallel,
                  LongPressGesture({ repeat: false, duration: 420 })
                    .onAction((ev: GestureEvent): void => {
                      this.endRbSlideSelectGesture();
                      const rowStart = rowIdx * 3;
                      const pt = this.readGestureFingerWindow(ev);
                      if (pt === null) {
                        return;
                      }
                      const xPx = vp2px(pt.x);
                      const yPx = vp2px(pt.y);
                      const fi = this.pickRbThumbFlatForRow(rowStart, xPx, yPx);
                      if (fi < 0 || fi >= this.items.length) {
                        return;
                      }
                      const longPressItem = this.items[fi];
                      this.onRbThumbLongPress(longPressItem, fi);
                      if (!this.selectionMode) {
                        return;
                      }
                      if (this.rbSlideGestureActive) {
                        return;
                      }
                      this.beginRbSlideSelectGesture(ev, fi);
                    }),
                  PanGesture({
                    fingers: 1,
                    direction: this.rbSlideGestureActive ? PanDirection.All : PanDirection.Horizontal,
                    distance: this.rbSlideGestureActive ? GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE :
                      GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE
                  })
                    .onActionStart((ev: GestureEvent): void => {
                      if (!this.selectionMode) {
                        return;
                      }
                      if (this.rbSlideGestureActive) {
                        this.endRbSlideSelectGesture();
                      }
                      const rowStart = rowIdx * 3;
                      const pt = this.readGestureFingerWindow(ev);
                      if (pt === null) {
                        return;
                      }
                      const xPx = vp2px(pt.x);
                      const yPx = vp2px(pt.y);
                      const fi = this.pickRbThumbFlatForRow(rowStart, xPx, yPx);
                      if (fi < 0 || fi >= this.items.length) {
                        return;
                      }
                      this.beginRbSlideSelectGesture(ev, fi);
                    })
                    .onActionUpdate((ev: GestureEvent): void => {
                      this.onRbSlidePanUpdate(ev);
                    })
                    .onActionEnd((): void => {
                      this.endRbSlideSelectGesture();
                    })
                    .onActionCancel((): void => {
                      this.endRbSlideSelectGesture();
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
            }, (rowIdx: number) => `rbrow_${rowIdx}`)
            ListItem() {
              Column() {
                Blank()
                  .width('100%')
                  .height(this.selectionMode && this.selectedIds.length > 0 ? 80 : 32)
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
          .enableScrollInteraction(this.rbScrollEnabled)
          .onDidScroll((_offset: number, _scrollState: ScrollState): void => {
            if (!this.rbSlideGestureActive && !this.rbScrollEnabled) {
              this.rbScrollEnabled = true;
            }
            if (!this.rbSlideGestureActive) {
              this.rbThumbHitBounds.clear();
            }
          })

          if (this.selectionMode && this.selectedIds.length > 0) {
            Row({ space: GALLERY_BATCH_BAR_SPACE_VP }) {
              Button($r('app.string.gallery_batch_download'), { type: ButtonType.Capsule, stateEffect: true })
                .layoutWeight(1)
                .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.card_background'))
                .enabled(!this.rbBatchDownloading)
                .onClick((): void => {
                  void this.confirmBatchDownloadRecycle();
                })
              Button('还原', { type: ButtonType.Capsule, stateEffect: true })
                .layoutWeight(1)
                .height(GALLERY_BATCH_ACTION_HEIGHT_VP)
                .fontColor(Color.White)
                .backgroundColor($r('app.color.brand_primary'))
                .enabled(!this.restoring)
                .onClick((): void => {
                  void this.confirmRestore();
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

          if (this.restoring || this.rbBatchDownloading) {
            FnFullLoadingMask({ text: this.restoring ? '正在还原…' : '下载中…' })
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
