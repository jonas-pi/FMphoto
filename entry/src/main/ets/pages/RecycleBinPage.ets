/**
 * 相册回收站：列表 + 多选恢复（GET recycle-bin/list，POST recycle-bin/restore）
 * 多选手势与图库主时间线一致：每行 Row + LongPress + Pan 划选 + 命中矩形缓存。
 */
import { common } from '@kit.AbilityKit';
import { UIContext, window } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import {
  GalleryNetworkThumb,
  nasUrl,
  trimThumbPixCacheForList
} from '../album/GalleryAlbumCommon';
import { FnListDataSource } from '../common/FnListDataSource';
import { RecycleBinListItem } from '../model/FnApiTypes';
import {
  FnFullLoadingMask,
  FnHdsPillButton,
  FnInlineLoading,
  FnStateText
} from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import {
  recycleBinConfirmBatchDownload,
  recycleBinConfirmRestore,
  recycleBinLoadAll,
  RecycleBinActionsHost
} from './recycleBinPage/RecycleBinActions';
import { RecycleBinBatchBar } from './recycleBinPage/RecycleBinBatchBar';
import { RecycleBinChrome } from './recycleBinPage/RecycleBinChrome';
import {
  recycleBinBeginSlideSelectGesture,
  recycleBinDomId,
  recycleBinEndSlideSelectGesture,
  recycleBinExitSelection,
  recycleBinIsIdSelected,
  recycleBinNumericIdOf,
  recycleBinOnCellClick,
  recycleBinOnSlidePanUpdate,
  recycleBinOnSlideTouchMoveWindow,
  recycleBinOnThumbLongPress,
  recycleBinPickThumbFlatForRow,
  recycleBinReadGestureFingerWindow,
  recycleBinRecordThumbRect,
  recycleBinSlidePanDistance,
  recycleBinThumbRelOf,
  recycleBinToggleToolbarMode,
  RecycleBinSelectionHost
} from './recycleBinPage/RecycleBinSelectionController';
import { RbFingerWindowPoint, RbThumbHitRect } from './recycleBinPage/RecycleBinTypes';

const RECYCLE_BIN_CONTENT_INSET_TOP_VP: number = 68;
const RECYCLE_BIN_COLUMNS_PER_ROW: number = 4;

interface RecycleBinRowBlockCell {
  flatIdx: number;
  item?: RecycleBinListItem;
  thumbRel: string;
  numericId: number;
}

interface RecycleBinRowBlock {
  key: string;
  rowIdx: number;
  rowStart: number;
  cells: RecycleBinRowBlockCell[];
}

@Entry
@Component
struct RecycleBinPage {
  @State private baseUrl: string = '';
  @State private loading: boolean = false;
  @State private restoring: boolean = false;
  @State private rbBatchDownloading: boolean = false;
  @State private rbBackgroundLoading: boolean = false;
  @State private error: string = '';
  @State @Watch('onItemsChanged') private items: RecycleBinListItem[] = [];
  @State private selectionMode: boolean = false;
  @State private selectedIds: number[] = [];
  @State private rbSlideGestureActive: boolean = false;
  @State private rbScrollEnabled: boolean = true;
  @State private rbThumbLoadingPaused: boolean = false;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @State private systemTopInsetVp: number = 0;

  private rbLongPressIgnoreUntil: number = 0;
  private rbThumbHitBounds: Map<string, RbThumbHitRect> = new Map();
  private rbSlideRefX: number = 0;
  private rbSlideRefY: number = 0;
  private rbSlideHasRef: boolean = false;
  private rbSlideAnchorFlat: number = -1;
  private rbSlideUnionBase: number[] = [];
  private rbSlideLastEndFlat: number = -1;
  private rbSlideLastAppliedEndFlat: number = -99999;
  private rbThumbResumeTimer: number = -1;
  private rbRowBlocks: RecycleBinRowBlock[] = [];
  private rbRowSource: FnListDataSource<RecycleBinRowBlock> = new FnListDataSource<RecycleBinRowBlock>();
  private rbInitialSlidePending: boolean = false;

  onBackPress(): boolean {
    if (this.selectionMode) {
      this.exitSelection();
      return true;
    }
    this.getUIContext().getRouter().back();
    return true;
  }

  private vpToPx(value: number): number {
    try {
      return this.getUIContext().vp2px(value);
    } catch (_e) {
      return value;
    }
  }

  private pxToVp(value: number): number {
    try {
      return this.getUIContext().px2vp(value);
    } catch (_e) {
      return value;
    }
  }

  private armInitialRbSlideGesture(ev: GestureEvent, anchorFlat: number): void {
    this.rbInitialSlidePending = true;
    this.beginRbSlideSelectGesture(ev, anchorFlat);
  }

  private clearInitialRbSlideGesture(): void {
    this.rbInitialSlidePending = false;
  }

  private contentInsetTopVp(): number {
    return this.systemTopInsetVp + RECYCLE_BIN_CONTENT_INSET_TOP_VP;
  }

  private syncSystemAvoidArea(win: window.Window): void {
    try {
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.systemTopInsetVp = Math.max(0, this.pxToVp(area.topRect.height));
    } catch (_e) {
      this.systemTopInsetVp = 0;
    }
  }

  private applySystemBar(): void {
    try {
      const dark = this.colorMode === 1;
      const content = dark ? '#FFFFFFFF' : '#FF000000';
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win): void => {
        win.setWindowLayoutFullScreen(true).catch((_e: Error): void => {});
        this.syncSystemAvoidArea(win);
        win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: content,
          navigationBarContentColor: content
        }).catch((_e: Error): void => {});
      }).catch((_e: Error): void => {});
    } catch (_e) {}
  }

  onColorModeChanged(): void {
    this.applySystemBar();
  }

  aboutToAppear(): void {
    this.applySystemBar();
    this.rbThumbLoadingPaused = false;
    this.rebuildRowBlocks();
    const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
    if (rp !== undefined && rp['baseUrl'] !== undefined) {
      this.baseUrl = String(rp['baseUrl']);
    }
    void this.loadAll();
  }

  aboutToDisappear(): void {
    this.clearRbThumbResumeTimer();
    this.recycleThumbCache(true);
    this.rbRowBlocks = [];
    this.rbRowSource.reloadAll([]);
    const client = AppSession.getClient();
    if (client !== null) {
      client.cancelPendingRequests();
    }
  }

  onItemsChanged(): void {
    this.rebuildRowBlocks();
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {}
  }

  private rbDomId(flatIdx: number): string {
    return recycleBinDomId(flatIdx);
  }

  private exitSelection(): void {
    recycleBinExitSelection(this.asSelectionHost());
  }

  private toggleToolbarMode(): void {
    recycleBinToggleToolbarMode(this.asSelectionHost());
  }

  private numericIdOf(it: RecycleBinListItem): number {
    return recycleBinNumericIdOf(it);
  }

  private thumbRelOf(it: RecycleBinListItem): string {
    return recycleBinThumbRelOf(it);
  }

  private topHeroImageUri(): string {
    if (this.items.length === 0) {
      return '';
    }
    const rel = this.thumbRelOf(this.items[0]);
    return rel.length > 0 ? nasUrl(this.baseUrl, rel) : '';
  }

  private isIdSelected(nid: number): boolean {
    return recycleBinIsIdSelected(this.asSelectionHost(), nid);
  }

  private readGestureFingerWindow(ev: GestureEvent) {
    return recycleBinReadGestureFingerWindow(ev);
  }

  private readTouchFingerWindow(ev: TouchEvent): RbFingerWindowPoint | null {
    if (ev.touches === undefined || ev.touches.length < 1) {
      return null;
    }
    const f0 = ev.touches[0];
    const x = f0.windowX ?? f0.displayX ?? f0.x;
    const y = f0.windowY ?? f0.displayY ?? f0.y;
    if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
      return null;
    }
    return { x, y };
  }

  private recordRbThumbRect(flatIdx: number): void {
    recycleBinRecordThumbRect(this.asSelectionHost(), flatIdx);
  }

  private pickRbThumbFlatForRow(rowStart: number, xPx: number, yPx: number): number {
    return recycleBinPickThumbFlatForRow(this.asSelectionHost(), rowStart, xPx, yPx);
  }

  private beginRbSlideSelectGesture(ev: GestureEvent, anchorFlat: number): void {
    recycleBinBeginSlideSelectGesture(this.asSelectionHost(), ev, anchorFlat);
  }

  private endRbSlideSelectGesture(): void {
    recycleBinEndSlideSelectGesture(this.asSelectionHost());
  }

  private onRbSlidePanUpdate(ev: GestureEvent): void {
    recycleBinOnSlidePanUpdate(this.asSelectionHost(), ev);
  }

  private onRbSlideTouchMoveWindow(xPx: number, yPx: number): void {
    recycleBinOnSlideTouchMoveWindow(this.asSelectionHost(), xPx, yPx);
  }

  private onRbThumbLongPress(it: RecycleBinListItem, flatIdx: number): void {
    recycleBinOnThumbLongPress(this.asSelectionHost(), it, flatIdx);
  }

  private onCellClick(it: RecycleBinListItem, flatIdx: number): void {
    recycleBinOnCellClick(this.asSelectionHost(), it, flatIdx);
  }

  private buildRowBlocks(): RecycleBinRowBlock[] {
    const blocks: RecycleBinRowBlock[] = [];
    const rowCount = Math.ceil(this.items.length / RECYCLE_BIN_COLUMNS_PER_ROW);
    for (let rowIdx = 0; rowIdx < rowCount; rowIdx++) {
      const rowStart = rowIdx * RECYCLE_BIN_COLUMNS_PER_ROW;
      const cells: RecycleBinRowBlockCell[] = [];
      let cellSig = '';
      for (let col = 0; col < RECYCLE_BIN_COLUMNS_PER_ROW; col++) {
        const flatIdx = rowStart + col;
        if (flatIdx >= this.items.length) {
          cells.push({
            flatIdx: -1,
            thumbRel: '',
            numericId: -1
          });
          cellSig += `_sk${col}`;
          continue;
        }
        const item = this.items[flatIdx];
        const numericId = this.numericIdOf(item);
        cells.push({
          flatIdx,
          item,
          thumbRel: this.thumbRelOf(item),
          numericId
        });
        cellSig += numericId >= 0 ? `_id${numericId}` : `_idx${flatIdx}`;
      }
      blocks.push({
        key: `rbrow_${rowIdx}${cellSig}`,
        rowIdx,
        rowStart,
        cells
      });
    }
    return blocks;
  }

  private rebuildRowBlocks(): void {
    this.rbRowBlocks = this.buildRowBlocks();
    this.rbRowSource.reloadAll(this.rbRowBlocks);
  }

  private rbCellAt(block: RecycleBinRowBlock, col: number): RecycleBinRowBlockCell | undefined {
    if (col < 0 || col >= block.cells.length) {
      return undefined;
    }
    return block.cells[col];
  }

  private rbCellHasItem(block: RecycleBinRowBlock, col: number): boolean {
    const cell = this.rbCellAt(block, col);
    return cell !== undefined && cell.item !== undefined && cell.flatIdx >= 0;
  }

  private rbCellItem(block: RecycleBinRowBlock, col: number): RecycleBinListItem {
    return this.rbCellAt(block, col)?.item as RecycleBinListItem;
  }

  private rbCellFlatIdx(block: RecycleBinRowBlock, col: number): number {
    return this.rbCellAt(block, col)?.flatIdx ?? -1;
  }

  private rbCellThumbRel(block: RecycleBinRowBlock, col: number): string {
    return this.rbCellAt(block, col)?.thumbRel ?? '';
  }

  private rbCellNumericId(block: RecycleBinRowBlock, col: number): number {
    return this.rbCellAt(block, col)?.numericId ?? -1;
  }

  private rbCellStableKey(block: RecycleBinRowBlock, col: number): string {
    const cell = this.rbCellAt(block, col);
    if (cell === undefined || cell.item === undefined || cell.flatIdx < 0) {
      return `rbcell_${block.rowIdx}_${col}_empty`;
    }
    const photoUUID = cell.item.photoUUID !== undefined ? String(cell.item.photoUUID).trim() : '';
    if (photoUUID.length > 0) {
      return `rbcell_${block.rowIdx}_${col}_uuid_${photoUUID}`;
    }
    if (cell.numericId >= 0) {
      return `rbcell_${block.rowIdx}_${col}_id_${cell.numericId}`;
    }
    return `rbcell_${block.rowIdx}_${col}_flat_${cell.flatIdx}`;
  }

  private async loadAll(): Promise<void> {
    await recycleBinLoadAll(this.asActionsHost());
  }

  private async confirmBatchDownloadRecycle(): Promise<void> {
    await recycleBinConfirmBatchDownload(this.asActionsHost());
  }

  private async confirmRestore(): Promise<void> {
    await recycleBinConfirmRestore(this.asActionsHost());
  }

  private clearRbThumbResumeTimer(): void {
    if (this.rbThumbResumeTimer >= 0) {
      clearTimeout(this.rbThumbResumeTimer);
      this.rbThumbResumeTimer = -1;
    }
  }

  private recycleThumbCache(aggressive: boolean = false): void {
    trimThumbPixCacheForList(this.items.length, aggressive);
  }

  private onListScrollStateChange(scrollState: ScrollState): void {
    if (!this.rbSlideGestureActive && !this.rbScrollEnabled) {
      this.rbScrollEnabled = true;
    }
    if (!this.rbSlideGestureActive) {
      this.rbThumbHitBounds.clear();
    }
    if (scrollState !== ScrollState.Idle) {
      this.clearRbThumbResumeTimer();
      if (!this.rbThumbLoadingPaused) {
        this.rbThumbLoadingPaused = true;
      }
      this.recycleThumbCache(false);
      return;
    }
    this.clearRbThumbResumeTimer();
    this.rbThumbResumeTimer = setTimeout((): void => {
      this.rbThumbResumeTimer = -1;
      this.rbThumbLoadingPaused = false;
    }, 96);
  }

  private asSelectionHost(): RecycleBinSelectionHost {
    const self = this;
    class RecycleBinSelectionHostBridge implements RecycleBinSelectionHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(v: string) { self.baseUrl = v; }

      get items(): RecycleBinListItem[] { return self.items; }
      set items(v: RecycleBinListItem[]) { self.items = v; }

      get selectionMode(): boolean { return self.selectionMode; }
      set selectionMode(v: boolean) { self.selectionMode = v; }

      get selectedIds(): number[] { return self.selectedIds; }
      set selectedIds(v: number[]) { self.selectedIds = v; }

      get rbSlideGestureActive(): boolean { return self.rbSlideGestureActive; }
      set rbSlideGestureActive(v: boolean) { self.rbSlideGestureActive = v; }

      get rbScrollEnabled(): boolean { return self.rbScrollEnabled; }
      set rbScrollEnabled(v: boolean) { self.rbScrollEnabled = v; }

      get rbLongPressIgnoreUntil(): number { return self.rbLongPressIgnoreUntil; }
      set rbLongPressIgnoreUntil(v: number) { self.rbLongPressIgnoreUntil = v; }

      get rbThumbHitBounds(): Map<string, RbThumbHitRect> { return self.rbThumbHitBounds; }
      set rbThumbHitBounds(v: Map<string, RbThumbHitRect>) { self.rbThumbHitBounds = v; }

      get rbSlideRefX(): number { return self.rbSlideRefX; }
      set rbSlideRefX(v: number) { self.rbSlideRefX = v; }

      get rbSlideRefY(): number { return self.rbSlideRefY; }
      set rbSlideRefY(v: number) { self.rbSlideRefY = v; }

      get rbSlideHasRef(): boolean { return self.rbSlideHasRef; }
      set rbSlideHasRef(v: boolean) { self.rbSlideHasRef = v; }

      get rbSlideAnchorFlat(): number { return self.rbSlideAnchorFlat; }
      set rbSlideAnchorFlat(v: number) { self.rbSlideAnchorFlat = v; }

      get rbSlideUnionBase(): number[] { return self.rbSlideUnionBase; }
      set rbSlideUnionBase(v: number[]) { self.rbSlideUnionBase = v; }

      get rbSlideLastEndFlat(): number { return self.rbSlideLastEndFlat; }
      set rbSlideLastEndFlat(v: number) { self.rbSlideLastEndFlat = v; }

      get rbSlideLastAppliedEndFlat(): number { return self.rbSlideLastAppliedEndFlat; }
      set rbSlideLastAppliedEndFlat(v: number) { self.rbSlideLastAppliedEndFlat = v; }

      toast(msg: string): void { self.toast(msg); }
    }
    return new RecycleBinSelectionHostBridge();
  }

  private asActionsHost(): RecycleBinActionsHost {
    const self = this;
    class RecycleBinActionsHostBridge implements RecycleBinActionsHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(v: string) { self.baseUrl = v; }

      get loading(): boolean { return self.loading; }
      set loading(v: boolean) { self.loading = v; }

      get restoring(): boolean { return self.restoring; }
      set restoring(v: boolean) { self.restoring = v; }

      get rbBatchDownloading(): boolean { return self.rbBatchDownloading; }
      set rbBatchDownloading(v: boolean) { self.rbBatchDownloading = v; }

      get rbBackgroundLoading(): boolean { return self.rbBackgroundLoading; }
      set rbBackgroundLoading(v: boolean) { self.rbBackgroundLoading = v; }

      get error(): string { return self.error; }
      set error(v: string) { self.error = v; }

      get items(): RecycleBinListItem[] { return self.items; }
      set items(v: RecycleBinListItem[]) { self.items = v; }

      get selectedIds(): number[] { return self.selectedIds; }
      set selectedIds(v: number[]) { self.selectedIds = v; }

      toast(msg: string): void { self.toast(msg); }
      exitSelection(): void { self.exitSelection(); }
    }
    return new RecycleBinActionsHostBridge();
  }

  @Builder
  private thumbCell(it: RecycleBinListItem, flatIdx: number, thumbRel: string, nid: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (thumbRel.length > 0) {
        GalleryNetworkThumb({
          uri: nasUrl(this.baseUrl, thumbRel),
          isVideo: false,
          isGif: false,
          paused: this.rbThumbLoadingPaused,
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
  private rbCellSlot(block: RecycleBinRowBlock, col: number) {
    if (!this.rbCellHasItem(block, col)) {
      Blank().layoutWeight(1).aspectRatio(1)
    } else {
      this.thumbCell(
        this.rbCellItem(block, col),
        this.rbCellFlatIdx(block, col),
        this.rbCellThumbRel(block, col),
        this.rbCellNumericId(block, col)
      )
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {

      if (this.loading) {
        FnInlineLoading({ text: '加载回收站…' }).layoutWeight(1)
      } else if (this.error.length > 0) {
        Column({ space: 12 }) {
          FnStateText({ text: this.error })
          FnHdsPillButton({
            text: '刷新',
            widthValue: 104,
            heightValue: 40,
            fontSizeValue: 16,
            fontColorValue: $r('app.color.brand_primary'),
            action: (): void => {
              void this.loadAll();
            }
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
              LazyForEach(this.rbRowSource, (block: RecycleBinRowBlock) => {
                ListItem() {
                  Row({ space: 2 }) {
                    ForEach(block.cells, (_cell: RecycleBinRowBlockCell, col: number) => {
                      this.rbCellSlot(block, col)
                    }, (_cell: RecycleBinRowBlockCell, col: number) => this.rbCellStableKey(block, col))
                  }
                  .width('100%')
                  .padding({ left: 2, right: 2, top: 1, bottom: 1 })
                  .onTouch((event: TouchEvent): void => {
                    if (!this.rbSlideGestureActive) {
                      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                        this.clearInitialRbSlideGesture();
                      }
                      return;
                    }
                    if (event.type === TouchType.Move) {
                      const pt = this.readTouchFingerWindow(event);
                      if (pt === null) {
                        return;
                      }
                      this.onRbSlideTouchMoveWindow(pt.x, pt.y);
                    }
                  })
                  .parallelGesture(GestureGroup(GestureMode.Parallel,
                    GestureGroup(GestureMode.Sequence,
                      LongPressGesture({ repeat: false, duration: 420 })
                        .onAction((ev: GestureEvent): void => {
                          this.clearInitialRbSlideGesture();
                          this.endRbSlideSelectGesture();
                          const pt = this.readGestureFingerWindow(ev);
                          if (pt === null) {
                            return;
                          }
                          const xPx = this.vpToPx(pt.x);
                          const yPx = this.vpToPx(pt.y);
                          const fi = this.pickRbThumbFlatForRow(block.rowStart, xPx, yPx);
                          if (fi < 0 || fi >= this.items.length) {
                            return;
                          }
                          const longPressItem = this.items[fi];
                          const wasSelectionMode = this.selectionMode;
                          this.onRbThumbLongPress(longPressItem, fi);
                          if (!wasSelectionMode) {
                            this.armInitialRbSlideGesture(ev, fi);
                          }
                        }),
                      PanGesture({
                        fingers: 1,
                        direction: PanDirection.All,
                        distance: recycleBinSlidePanDistance(true)
                      })
                        .onActionUpdate((ev: GestureEvent): void => {
                          if (!this.rbInitialSlidePending || !this.rbSlideGestureActive) {
                            return;
                          }
                          this.onRbSlidePanUpdate(ev);
                        })
                        .onActionEnd((): void => {
                          this.clearInitialRbSlideGesture();
                          this.endRbSlideSelectGesture();
                        })
                        .onActionCancel((): void => {
                          this.clearInitialRbSlideGesture();
                          this.endRbSlideSelectGesture();
                        })
                    ),
                    PanGesture({
                      fingers: 1,
                      direction: PanDirection.Horizontal,
                      distance: recycleBinSlidePanDistance(this.selectionMode)
                    })
                      .onActionStart((ev: GestureEvent): void => {
                        if (!this.selectionMode) {
                          return;
                        }
                        if (this.rbSlideGestureActive || this.rbInitialSlidePending) {
                          return;
                        }
                        const pt = this.readGestureFingerWindow(ev);
                        if (pt === null) {
                          return;
                        }
                        const xPx = this.vpToPx(pt.x);
                        const yPx = this.vpToPx(pt.y);
                        const fi = this.pickRbThumbFlatForRow(block.rowStart, xPx, yPx);
                        if (fi < 0 || fi >= this.items.length) {
                          return;
                        }
                        this.beginRbSlideSelectGesture(ev, fi);
                      })
                      .onActionUpdate((ev: GestureEvent): void => {
                        this.onRbSlidePanUpdate(ev);
                      })
                      .onActionEnd((): void => {
                        this.clearInitialRbSlideGesture();
                        this.endRbSlideSelectGesture();
                      })
                      .onActionCancel((): void => {
                        this.clearInitialRbSlideGesture();
                        this.endRbSlideSelectGesture();
                      })
                  ))
                }
                .draggable(false)
              }, (block: RecycleBinRowBlock) => block.key)
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
            .cachedCount(3)
            .margin({ top: this.contentInsetTopVp() })
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
            .divider({ strokeWidth: 0 })
            .enableScrollInteraction(this.rbScrollEnabled)
            .onTouch((event: TouchEvent): void => {
              if (!this.rbSlideGestureActive) {
                if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.clearInitialRbSlideGesture();
                }
                return;
              }
              if (event.type === TouchType.Move) {
                const pt = this.readTouchFingerWindow(event);
                if (pt === null) {
                  return;
                }
                this.onRbSlideTouchMoveWindow(pt.x, pt.y);
                return;
              }
              if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.clearInitialRbSlideGesture();
                this.endRbSlideSelectGesture();
              }
            })
            .onDidScroll((_offset: number, scrollState: ScrollState): void => {
              this.onListScrollStateChange(scrollState);
            })

            if (this.rbBackgroundLoading) {
              Row({ space: 8 }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                Text('继续加载中')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 8, bottom: this.selectionMode && this.selectedIds.length > 0 ? 8 : 0 })
            }

            if (this.selectionMode && this.selectedIds.length > 0) {
              RecycleBinBatchBar({
                downloading: this.rbBatchDownloading,
                restoring: this.restoring,
                onDownload: (): void => {
                  void this.confirmBatchDownloadRecycle();
                },
                onRestore: (): void => {
                  void this.confirmRestore();
                }
              })
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

      Column() {
        RecycleBinChrome({
          selectionMode: this.selectionMode,
          selectedCount: this.selectedIds.length,
          topSafeInsetVp: this.systemTopInsetVp,
          onCancelSelection: (): void => {
            this.exitSelection();
          },
          onBack: (): void => {
            this.getUIContext().getRouter().back();
          },
          onToggleMode: (): void => {
            this.toggleToolbarMode();
          }
        })

        Blank()
          .layoutWeight(1)
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
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
