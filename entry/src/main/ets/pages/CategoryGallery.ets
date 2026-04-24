/**
 * 媒体分类浏览页：展示某一分类（照片/视频/动图等）内所有媒体，
 * 按日期降序分组，3 列网格；长按 + 滑动连选、批量下载/删除（与图库主时间线交互一致）。
 */
import { UIContext, window } from '@kit.ArkUI';
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
import { AppSession } from '../auth/AppSession';
import { FnFullLoadingMask, FnStateText } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import { GalleryAlbumBatchActionBar } from '../album/galleryAlbumTab/GalleryAlbumBatchActionBar';
import {
  categoryGalleryApplyDeleteSyncIfNeeded,
  categoryGalleryConfirmBatchDelete,
  categoryGalleryConfirmBatchDownload,
  categoryGalleryRebuildByFlatItems,
  CategoryGalleryBatchActionsHost
} from './categoryGallery/CategoryGalleryBatchActions';
import { CategoryGalleryChrome } from './categoryGallery/CategoryGalleryChrome';
import {
  categoryGalleryBeginSlideSelectGesture,
  categoryGalleryDomId,
  categoryGalleryEndSlideSelectGesture,
  categoryGalleryExitSelection,
  categoryGalleryFlatPos,
  categoryGalleryIsIdSelected,
  categoryGalleryItemIdOf,
  categoryGalleryOnCellClick,
  categoryGalleryOnSlidePanUpdate,
  categoryGalleryOnThumbLongPress,
  categoryGalleryPickFlatForRow,
  categoryGalleryReadGestureFingerWindow,
  categoryGalleryRecordThumbRect,
  categoryGalleryRowGlobalStartFlat,
  categoryGallerySlidePanDistance,
  categoryGalleryToggleToolbarMode,
  CategoryGallerySelectionHost
} from './categoryGallery/CategoryGallerySelectionController';
import {
  buildCategoryGalleryViewData,
  CgThumbHitRect,
  DayGroup,
  RowModel
} from './categoryGallery/CategoryGalleryTypes';

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
    const useCreatedAt = this.title.trim() === '最近添加';
    const viewData = buildCategoryGalleryViewData(CategoryGalleryNavStore.items, useCreatedAt);
    this.groups = viewData.groups;
    this.flatItems = viewData.flatItems;
    this.groupOffsets = viewData.groupOffsets;
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
    return categoryGalleryItemIdOf(it);
  }

  private flatPos(groupIdx: number, idxInGroup: number): number {
    return categoryGalleryFlatPos(this.asSelectionHost(), groupIdx, idxInGroup);
  }

  private cgDomId(flatIdx: number): string {
    return categoryGalleryDomId(flatIdx);
  }

  private exitCgSelection(): void {
    categoryGalleryExitSelection(this.asSelectionHost());
  }

  private toggleToolbarMode(): void {
    categoryGalleryToggleToolbarMode(this.asSelectionHost());
  }

  private isCgIdSelected(id: string): boolean {
    return categoryGalleryIsIdSelected(this.asSelectionHost(), id);
  }

  private recordCgThumbRect(flatIdx: number): void {
    categoryGalleryRecordThumbRect(this.asSelectionHost(), flatIdx);
  }

  private readGestureFingerWindow(ev: GestureEvent) {
    return categoryGalleryReadGestureFingerWindow(ev);
  }

  private pickCgFlatForRow(rowStart: number, xPx: number, yPx: number): number {
    return categoryGalleryPickFlatForRow(this.asSelectionHost(), rowStart, xPx, yPx);
  }

  private beginCgSlideSelectGesture(ev: GestureEvent, anchorFlat: number): void {
    categoryGalleryBeginSlideSelectGesture(this.asSelectionHost(), ev, anchorFlat);
  }

  private endCgSlideSelectGesture(): void {
    categoryGalleryEndSlideSelectGesture(this.asSelectionHost());
  }

  private onCgSlidePanUpdate(ev: GestureEvent): void {
    categoryGalleryOnSlidePanUpdate(this.asSelectionHost(), ev);
  }

  private onCgThumbLongPress(item: GalleryListItem, flatIdx: number): void {
    categoryGalleryOnThumbLongPress(this.asSelectionHost(), item, flatIdx);
  }

  private openItemAtFlat(flatIdx: number): void {
    if (flatIdx < 0 || flatIdx >= this.flatItems.length) {
      return;
    }
    GalleryPreviewNavStore.openPreview(this.baseUrl, this.flatItems, flatIdx);
  }

  private onCgCellClick(item: GalleryListItem, flatIdx: number): void {
    categoryGalleryOnCellClick(this.asSelectionHost(), item, flatIdx);
  }

  private rowGlobalStartFlat(groupIdx: number, row: RowModel): number {
    return categoryGalleryRowGlobalStartFlat(this.asSelectionHost(), groupIdx, row);
  }

  private async confirmCgBatchDownload(): Promise<void> {
    await categoryGalleryConfirmBatchDownload(this.asBatchActionsHost());
  }

  private async confirmCgBatchDelete(): Promise<void> {
    await categoryGalleryConfirmBatchDelete(this.asBatchActionsHost());
  }

  private rebuildByFlatItems(): void {
    categoryGalleryRebuildByFlatItems(this.asBatchActionsHost());
  }

  private applyDeleteSyncIfNeeded(): void {
    categoryGalleryApplyDeleteSyncIfNeeded(this.asBatchActionsHost());
  }

  private asSelectionHost(): CategoryGallerySelectionHost {
    const self = this;
    class CategoryGallerySelectionHostBridge implements CategoryGallerySelectionHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get flatItems(): GalleryListItem[] { return self.flatItems; }
      set flatItems(v: GalleryListItem[]) { self.flatItems = v; }

      get groupOffsets(): number[] { return self.groupOffsets; }
      set groupOffsets(v: number[]) { self.groupOffsets = v; }

      get selectionMode(): boolean { return self.selectionMode; }
      set selectionMode(v: boolean) { self.selectionMode = v; }

      get selectedIds(): string[] { return self.selectedIds; }
      set selectedIds(v: string[]) { self.selectedIds = v; }

      get cgSlideGestureActive(): boolean { return self.cgSlideGestureActive; }
      set cgSlideGestureActive(v: boolean) { self.cgSlideGestureActive = v; }

      get cgScrollEnabled(): boolean { return self.cgScrollEnabled; }
      set cgScrollEnabled(v: boolean) { self.cgScrollEnabled = v; }

      get cgLongPressIgnoreUntil(): number { return self.cgLongPressIgnoreUntil; }
      set cgLongPressIgnoreUntil(v: number) { self.cgLongPressIgnoreUntil = v; }

      get cgThumbHitBounds(): Map<string, CgThumbHitRect> { return self.cgThumbHitBounds; }
      set cgThumbHitBounds(v: Map<string, CgThumbHitRect>) { self.cgThumbHitBounds = v; }

      get cgSlideRefX(): number { return self.cgSlideRefX; }
      set cgSlideRefX(v: number) { self.cgSlideRefX = v; }

      get cgSlideRefY(): number { return self.cgSlideRefY; }
      set cgSlideRefY(v: number) { self.cgSlideRefY = v; }

      get cgSlideHasRef(): boolean { return self.cgSlideHasRef; }
      set cgSlideHasRef(v: boolean) { self.cgSlideHasRef = v; }

      get cgSlideAnchorFlat(): number { return self.cgSlideAnchorFlat; }
      set cgSlideAnchorFlat(v: number) { self.cgSlideAnchorFlat = v; }

      get cgSlideUnionBase(): string[] { return self.cgSlideUnionBase; }
      set cgSlideUnionBase(v: string[]) { self.cgSlideUnionBase = v; }

      get cgSlideLastEndFlat(): number { return self.cgSlideLastEndFlat; }
      set cgSlideLastEndFlat(v: number) { self.cgSlideLastEndFlat = v; }

      get cgSlideLastAppliedEndFlat(): number { return self.cgSlideLastAppliedEndFlat; }
      set cgSlideLastAppliedEndFlat(v: number) { self.cgSlideLastAppliedEndFlat = v; }

      toast(msg: string): void { self.toast(msg); }
      openItemAtFlat(flatIdx: number): void { self.openItemAtFlat(flatIdx); }
    }
    return new CategoryGallerySelectionHostBridge();
  }

  private asBatchActionsHost(): CategoryGalleryBatchActionsHost {
    const self = this;
    class CategoryGalleryBatchActionsHostBridge implements CategoryGalleryBatchActionsHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(v: string) { self.baseUrl = v; }

      get title(): string { return self.title; }
      set title(v: string) { self.title = v; }

      get groups(): DayGroup[] { return self.groups; }
      set groups(v: DayGroup[]) { self.groups = v; }

      get flatItems(): GalleryListItem[] { return self.flatItems; }
      set flatItems(v: GalleryListItem[]) { self.flatItems = v; }

      get groupOffsets(): number[] { return self.groupOffsets; }
      set groupOffsets(v: number[]) { self.groupOffsets = v; }

      get handledDeleteSyncVersion(): number { return self.handledDeleteSyncVersion; }
      set handledDeleteSyncVersion(v: number) { self.handledDeleteSyncVersion = v; }

      get selectedIds(): string[] { return self.selectedIds; }
      set selectedIds(v: string[]) { self.selectedIds = v; }

      get cgBatchDeleting(): boolean { return self.cgBatchDeleting; }
      set cgBatchDeleting(v: boolean) { self.cgBatchDeleting = v; }

      get cgBatchDownloading(): boolean { return self.cgBatchDownloading; }
      set cgBatchDownloading(v: boolean) { self.cgBatchDownloading = v; }

      toast(msg: string): void { self.toast(msg); }
      exitSelection(): void { self.exitCgSelection(); }
    }
    return new CategoryGalleryBatchActionsHostBridge();
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
      CategoryGalleryChrome({
        selectionMode: this.selectionMode,
        selectedCount: this.selectedIds.length,
        title: this.title,
        totalCount: this.flatItems.length,
        onCancelSelection: (): void => {
          this.exitCgSelection();
        },
        onBack: (): void => {
          this.getUIContext().getRouter().back();
        },
        onToggleMode: (): void => {
          this.toggleToolbarMode();
        }
      })

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
                          if (!this.selectionMode || this.cgSlideGestureActive) {
                            return;
                          }
                          this.beginCgSlideSelectGesture(ev, fi);
                        }),
                      PanGesture({
                        fingers: 1,
                        direction: this.cgSlideGestureActive ? PanDirection.All : PanDirection.Horizontal,
                        distance: categoryGallerySlidePanDistance(this.cgSlideGestureActive)
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
              GalleryAlbumBatchActionBar({
                downloading: this.cgBatchDownloading,
                deleting: this.cgBatchDeleting,
                onDownload: (): void => {
                  void this.confirmCgBatchDownload();
                },
                onDelete: (): void => {
                  void this.confirmCgBatchDelete();
                }
              })
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
