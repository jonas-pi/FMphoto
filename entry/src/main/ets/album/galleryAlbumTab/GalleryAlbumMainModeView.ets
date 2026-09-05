import { UIContext } from '@kit.ArkUI';
import { GalleryListItem } from '../../model/FnApiTypes';
import { FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { GalleryFlowNode, GalleryWaterFlowDataSource } from '../GalleryFlowDataSource';
import {
  GalleryNetworkThumb,
  GalleryStaticThumbPlaceholder,
  GalleryThumbSkeleton,
  getThumbLoadTelemetry,
  isGifItem,
  isVideoItem,
  nasUrl,
  pickThumbForGridDensity,
  thumbDensityCacheRank,
  thumbIdentityOfItem,
  setThumbHighThroughputLevel
} from '../GalleryAlbumCommon';
import { isLivePhotoItem } from '../livephoto/LivePhotoDetect';
import { gallerySharedTransitionId } from '../GallerySharedTransition';
import { GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE } from '../GallerySlidePick';
import {
  galleryGridArmInitialSlide,
  galleryGridCanStartSecondaryPan,
  galleryGridClearInitialSlide,
  galleryGridHandleListTouch,
  galleryGridHandleRowTouch,
  galleryGridOnSecondaryPanFinish,
  galleryGridOnSecondaryPanStart,
  galleryGridOnSequenceLongPress,
  galleryGridOnSequencePanFinish,
  galleryGridResetTouchTracking,
  galleryGridShouldUpdateSecondaryPan,
  galleryGridShouldUpdateSequencePan,
  GalleryGridSlideTouchHost,
  GalleryGridSlideTouchSession,
  GALLERY_GRID_SEQUENCE_LONG_PRESS_MS
} from '../GalleryGridSlideTouch';
import { gallerySlideAutoScrollOnListDidScroll } from '../GallerySlideAutoScroll';
import {
  GALLERY_TIMELINE_REFRESH_PULL_RATIO,
  galleryTimelineRefreshTriggerOffsetVp
} from './GalleryAlbumTabConstants';
import { GalleryFingerWindowPoint, YearMarker } from './GalleryAlbumTabTypes';
import { GalleryAlbumBatchActionBar } from '../GalleryAlbumBatchActionBar';
import { GalleryAlbumTimelineSidebar } from './GalleryAlbumTimelineSidebar';
import { GalleryViewGranularity, galleryViewGranularityAfterPinch } from './GalleryAlbumGranularity';
import { GalleryAlbumSelectionOverlay, GALLERY_SELECTION_SCOPE_ALBUM } from './GalleryAlbumSelectionOverlay';
import { GalleryPinchScaleUpdater } from './GalleryAlbumPinchScale';

const GALLERY_THUMB_THROUGHPUT_DROP_COOLDOWN_MS: number = 900;
const GALLERY_THUMB_NETWORK_PRESSURE_LOAD_MS_YEAR: number = 300;
const GALLERY_THUMB_NETWORK_PRESSURE_LOAD_MS_MONTH: number = 360;
const GALLERY_THUMB_NETWORK_PRESSURE_QUEUE_WAIT_MS_YEAR: number = 120;
const GALLERY_THUMB_NETWORK_PRESSURE_QUEUE_WAIT_MS_MONTH: number = 160;
/** 官方 PinchGesture 默认识别距离 5vp，过大容易先被 List 内置滑动抢走。 */
const GALLERY_GRANULARITY_PINCH_DISTANCE_VP: number = 5;
const GALLERY_GRANULARITY_PINCH_LOCK_MS: number = 320;
export const GALLERY_ALBUM_MAIN_LIST_DOM_ID: string = 'gallery_album_main_list';

@Component
export struct GalleryAlbumMainModeView {
  @Prop baseUrl: string = '';
  @Prop @Watch('onViewGranularityChanged') viewGranularity: GalleryViewGranularity = GalleryViewGranularity.DAY;
  @Prop gridColumns: number = 3;
  @Prop bootLoading: boolean = false;
  @Prop loadError: string = '';
  @Prop footText: string = '';
  @Prop contentInsetTopVp: number = 0;
  /** 仅状态栏/挖孔顶边高度，刷新区避让用；与 contentInsetTopVp（含顶栏）区分 */
  @Prop topSafeInsetVp: number = 0;
  @Prop contentInsetBottomVp: number = 0;
  @Prop modeSwitchOpacity: number = 1;
  @Prop modeSwitchOffsetY: number = 0;
  @Prop galleryTimelineRefreshing: boolean = false;
  @Prop gallerySelectionMode: boolean = false;
  @Prop granularityPinchEnabled: boolean = true;
  @Prop showBatchActionBar: boolean = true;
  @Prop galleryBatchDownloading: boolean = false;
  @Prop galleryBatchDeleting: boolean = false;
  @Prop galleryMainListScrollEnabled: boolean = true;
  @Prop gallerySlideGestureActive: boolean = false;
  @Prop galleryLongPressIgnoreClickUntil: number = 0;
  @Prop timelineSidebarDragging: boolean = false;
  @Prop isDraggingOrFling: boolean = false;
  @Prop sectionsLength: number = 0;
  @Prop orderedDaysLength: number = 0;
  @Prop timelineExpandedChrome: boolean = false;
  @Prop timelineScrollRailOnly: boolean = false;
  @Prop timelineYearMarkers: YearMarker[] = [];
  @Prop timelineScrubPillLabel: string = '';
  @Prop timelineBarVisible: boolean = false;
  @Prop timelinePressing: boolean = false;
  @Prop timelineLongPressExpanded: boolean = false;
  @Prop timelineIndicatorY: number = 0;
  @Prop timelineSliderRatio: number = 0;
  @Prop mainListDomId: string = GALLERY_ALBUM_MAIN_LIST_DOM_ID;

  scrollerRef: Scroller = new Scroller();
  flowDataSource: GalleryWaterFlowDataSource = new GalleryWaterFlowDataSource();
  private slideTouch: GalleryGridSlideTouchSession = new GalleryGridSlideTouchSession();
  private thumbThroughputLevel: number = 0;
  private thumbLastAdaptiveDropAtMs: number = 0;
  @State private granularityOpacity: number = 1;
  private pinchScaleUpdater: GalleryPinchScaleUpdater = new GalleryPinchScaleUpdater();
  private granularityPinchActive: boolean = false;
  /** 第二指落下即锁滚动，不必等 Pinch 识别成功，避免和 List/Refresh 内置滑动打架。 */
  private twoFingerScrollLocked: boolean = false;
  private pinchCenterX: number = 0;
  private pinchCenterY: number = 0;
  private pinchCenterFrozen: boolean = false;
  private pinchFollowScale: number = 1;
  private pinchLockUntilMs: number = 0;
  /** 官方 ComponentSnapshot：松手切级时盖住宫格重建，避免新骨架闪一帧。 */
  @State private pinchCoverPix: PixelMap | undefined = undefined;
  @State private pinchCoverScale: number = 1;
  @State private pinchCoverCenterX: number = 0;
  @State private pinchCoverCenterY: number = 0;
  @State private pinchCoverOpacity: number = 1;
  /**
   * 捏合/盖层期间锁住 Refresh。须为 @State：官方 refreshing=false 才能收起加载动画，
   * 且 pinch 重建 List 时 builder 销毁会中断收起（ts-container-refresh）。
   */
  @State private pinchRefreshLocked: boolean = false;
  /** 当前 Refresh 下拉偏移，供自定义 builder 判断是否该画出转圈。 */
  @State private refreshPullOffsetVp: number = 0;
  /**
   * 捏合会把 Refresh 偏移卡在非 0。在偏移回到接近 0 前不画转圈，
   * 避免 end 之后加载图标仍钉在顶部。
   */
  private refreshOffsetArmed: boolean = true;
  private pinchCoverDismissTimer: number = -1;

  itemIdOf: (item: GalleryListItem) => string = (_: GalleryListItem) => '';
  galleryThumbDomId: (photoId: string) => string = (_: string) => '';
  recordGalleryThumbRectFromDom: (photoId: string, domId: string) => void = (_: string, __: string) => {};
  onGalleryThumbTap: (item: GalleryListItem, flatIndex: number) => void = (_: GalleryListItem, __: number) => {};
  galleryFlowLazyKey: (node: GalleryFlowNode) => string = (_: GalleryFlowNode) => '';
  getFlatItems: () => GalleryListItem[] = () => [];
  endGallerySlideSelectGesture: () => void = () => {};
  readGestureFingerWindow: (ev: GestureEvent) => GalleryFingerWindowPoint | null = (_: GestureEvent) => null;
  pickGalleryThumbFlatForRowOrCache: (node: GalleryFlowNode, xPx: number, yPx: number) => number =
    (_: GalleryFlowNode, __: number, ___: number) => -1;
  onGalleryThumbLongPress: (item: GalleryListItem) => void = (_: GalleryListItem) => {};
  beginGallerySlideSelectGesture: (ev: GestureEvent, item: GalleryListItem, anchorFlat: number) => void =
    (_: GestureEvent, __: GalleryListItem, ___: number) => {};
  beginGallerySlideSelectGestureAtWindowPx: (item: GalleryListItem, anchorFlat: number, xPx: number, yPx: number) => void =
    (_: GalleryListItem, __: number, ___: number, ____: number) => {};
  onGallerySlidePanUpdate: (ev: GestureEvent) => void = (_: GestureEvent) => {};
  onGallerySlideTouchMoveWindow: (xPx: number, yPx: number) => void = (_: number, __: number) => {};
  onListScrollIndex: (firstIdx: number, lastIdx: number, centerIdx: number) => void =
    (_: number, __: number, ___: number) => {};
  onListDidScroll: (offset: number, scrollState: ScrollState) => void = (_: number, __: ScrollState) => {};
  onListVisibleContentChange: (start: VisibleListContentInfo, end: VisibleListContentInfo) => void =
    (_: VisibleListContentInfo, __: VisibleListContentInfo) => {};
  onRefreshOffsetChange: (offset: number) => void = (_: number) => {};
  onRefreshing: () => void = () => {};
  /** 捏合打断下拉刷新：宿主递增 epoch 并把 refreshing 置 false。 */
  onAbortTimelineRefreshing: () => void = () => {};
  onBatchDownload: () => void = () => {};
  onBatchDelete: () => void = () => {};
  onTimelineSeekToCurrentRatio: () => void = () => {};
  onTimelineTrackHeightChange: (height: number) => void = (_: number) => {};
  onTimelineTouchStateChange: (event: TouchEvent) => void = (_: TouchEvent) => {};
  onTimelineLongPressExpand: () => void = () => {};
  onTimelinePanStart: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onTimelinePanUpdate: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onTimelinePanEnd: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onTimelinePanCancel: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onGranularityPinchCommit: (mode: GalleryViewGranularity) => void = (_: GalleryViewGranularity): void => {};
  /** 捏合进行中通知宿主：禁止把 List 滚动写成 isDraggingOrFling，避免骨架门控和 @Prop 刷新掐断跟手。 */
  onGranularityPinchActiveChange: (active: boolean) => void = (_: boolean): void => {};

  private showTimelineSidebar(): boolean {
    return this.sectionsLength > 0 || this.orderedDaysLength > 0;
  }

  private maxThumbThroughputLevelForMode(): number {
    if (this.viewGranularity === GalleryViewGranularity.YEAR) {
      return 3;
    }
    if (this.viewGranularity === GalleryViewGranularity.MONTH) {
      return 2;
    }
    return 0;
  }

  private minThumbThroughputLevelForMode(): number {
    if (this.viewGranularity === GalleryViewGranularity.YEAR) {
      return 2;
    }
    if (this.viewGranularity === GalleryViewGranularity.MONTH) {
      return 1;
    }
    return 0;
  }

  private resetThumbThroughputAdaptation(): void {
    this.thumbThroughputLevel = this.maxThumbThroughputLevelForMode();
    this.thumbLastAdaptiveDropAtMs = 0;
  }

  private applyThumbThroughputLevel(): void {
    setThumbHighThroughputLevel(this.thumbThroughputLevel);
  }

  private syncThumbHighThroughputMode(): void {
    this.resetThumbThroughputAdaptation();
    this.applyThumbThroughputLevel();
  }

  private resetGranularityMotion(): void {
    this.granularityOpacity = 1;
  }

  private canRecognizeGranularityPinch(): boolean {
    if (!this.granularityPinchEnabled || this.timelineSidebarDragging || this.gallerySlideGestureActive) {
      return false;
    }
    return Date.now() >= this.pinchLockUntilMs;
  }

  private isGranularityPinchBlockingScroll(): boolean {
    return this.twoFingerScrollLocked || this.granularityPinchActive;
  }

  private lockTwoFingerScroll(): void {
    if (this.twoFingerScrollLocked) {
      return;
    }
    this.twoFingerScrollLocked = true;
    // 第二指落下时 Refresh 可能已处于 Drag/Refresh；立刻关动画并禁止再触发
    this.pinchRefreshLocked = true;
    this.refreshOffsetArmed = false;
    galleryGridResetTouchTracking(this.slideTouch);
    this.onGranularityPinchActiveChange(true);
    this.onAbortTimelineRefreshing();
  }

  private unlockTwoFingerScrollIfIdle(): void {
    if (this.granularityPinchActive) {
      return;
    }
    this.twoFingerScrollLocked = false;
    this.onGranularityPinchActiveChange(false);
    // 截图盖层还在时继续锁 Refresh，等盖层淡出后再允许下拉
    if (this.pinchCoverPix === undefined) {
      this.pinchRefreshLocked = false;
    }
  }

  /** 官方：refreshing 为 false 时刷新区应收起；捏合期间强制 false，避免 List 重建卡住转圈。 */
  private isTimelineRefreshVisualActive(): boolean {
    return this.galleryTimelineRefreshing && !this.pinchRefreshLocked && this.pinchCoverPix === undefined;
  }

  private canPullToRefreshNow(): boolean {
    return !this.gallerySelectionMode && !this.pinchRefreshLocked && this.pinchCoverPix === undefined;
  }

  /**
   * 转圈只在「正在刷新」或「用户正在下拉」时出现。
   * 官方 ts-container-refresh：自定义 builder 若带固定高度，会一直显示在刷新区下方。
   */
  private shouldShowGalleryRefreshSpinner(): boolean {
    if (this.pinchRefreshLocked || this.pinchCoverPix !== undefined) {
      return false;
    }
    if (this.isTimelineRefreshVisualActive()) {
      return true;
    }
    return this.refreshOffsetArmed && this.refreshPullOffsetVp > 8;
  }

  private onTimelineRefreshOffsetChange(offset: number): void {
    this.refreshPullOffsetVp = offset;
    if (offset < 2) {
      this.refreshOffsetArmed = true;
    }
    this.onRefreshOffsetChange(offset);
  }

  private onTimelineRefreshing(): void {
    if (!this.canPullToRefreshNow()) {
      this.onAbortTimelineRefreshing();
      return;
    }
    this.onRefreshing();
  }

  private onTimelineRefreshStateChange(state: RefreshStatus): void {
    if (!this.pinchRefreshLocked && this.pinchCoverPix === undefined) {
      return;
    }
    // 捏合已拦截 PAN，Refresh 可能仍停在 Refresh 态；再写一次 false 收起指示条
    if (state === RefreshStatus.Refresh) {
      this.onAbortTimelineRefreshing();
    }
  }

  private touchFingerCount(event: TouchEvent): number {
    if (event.touches === undefined) {
      return 0;
    }
    return event.touches.length;
  }

  private gestureFingerCount(event: BaseGestureEvent): number {
    if (event.fingerList === undefined) {
      return 0;
    }
    return event.fingerList.length;
  }

  private onGranularityPinchStart(event: GestureEvent): void {
    if (!this.canRecognizeGranularityPinch()) {
      return;
    }
    this.lockTwoFingerScroll();
    galleryGridResetTouchTracking(this.slideTouch);
    this.granularityPinchActive = true;
    this.pinchCenterX = event.pinchCenterX;
    this.pinchCenterY = event.pinchCenterY;
    this.pinchCenterFrozen = true;
    this.pinchFollowScale = 1;
    this.pinchScaleUpdater.applyScale(1, this.pinchCenterX, this.pinchCenterY);
  }

  private onGranularityPinchUpdate(event: GestureEvent): void {
    if (!this.granularityPinchActive) {
      return;
    }
    // 缩放中心只取识别成功那一帧，后续跟手只改 scale，避免 origin 每帧跳动。
    if (!this.pinchCenterFrozen) {
      this.pinchCenterX = event.pinchCenterX;
      this.pinchCenterY = event.pinchCenterY;
      this.pinchCenterFrozen = true;
    }
    this.pinchFollowScale = event.scale;
    this.pinchScaleUpdater.applyScale(this.pinchFollowScale, this.pinchCenterX, this.pinchCenterY);
  }

  private onGranularityPinchEnd(event: GestureEvent): void {
    if (!this.granularityPinchActive) {
      this.pinchScaleUpdater.resetScale();
      this.unlockTwoFingerScrollIfIdle();
      return;
    }
    this.granularityPinchActive = false;
    this.pinchCenterFrozen = false;
    const nextMode = galleryViewGranularityAfterPinch(this.viewGranularity, event.scale);
    if (nextMode === null) {
      this.pinchScaleUpdater.resetScale();
      this.unlockTwoFingerScrollIfIdle();
      return;
    }
    this.pinchLockUntilMs = Date.now() + GALLERY_GRANULARITY_PINCH_LOCK_MS;
    this.beginPinchCoverThenCommit(nextMode);
  }

  /**
   * 官方图库切级路径：手势期只缩放当前层；松手先截当前宫格，用 PixelMap 盖住，
   * 再改列数。截图拿的是目标组件变换前的内容，所以盖层继续带上跟手 scale。
   */
  private beginPinchCoverThenCommit(nextMode: GalleryViewGranularity): void {
    const coverScale: number = this.pinchFollowScale;
    const coverX: number = this.pinchCenterX;
    const coverY: number = this.pinchCenterY;
    let pix: PixelMap | undefined = undefined;
    try {
      pix = this.getUIContext().getComponentSnapshot().getSync(this.mainListDomId);
    } catch (_e) {
      pix = undefined;
    }
    this.clearPinchCoverTimer();
    this.releasePinchCoverPix();
    this.pinchCoverScale = coverScale;
    this.pinchCoverCenterX = coverX;
    this.pinchCoverCenterY = coverY;
    this.pinchCoverOpacity = 1;
    this.pinchCoverPix = pix;
    this.pinchScaleUpdater.resetScale();
    this.onGranularityPinchCommit(nextMode);
    this.unlockTwoFingerScrollIfIdle();
    this.onAbortTimelineRefreshing();
    if (pix === undefined) {
      this.pinchRefreshLocked = false;
      return;
    }
    // 盖层期间 List 不可滚，Refresh 无法回弹；保持锁直到淡出
    this.pinchRefreshLocked = true;
    this.schedulePinchCoverDismiss();
  }

  private schedulePinchCoverDismiss(): void {
    this.clearPinchCoverTimer();
    this.pinchCoverDismissTimer = setTimeout((): void => {
      this.pinchCoverDismissTimer = -1;
      try {
        this.getUIContext().animateTo(
          { duration: 200, curve: Curve.EaseOut },
          (): void => {
            this.pinchCoverOpacity = 0;
            this.pinchCoverScale = 1;
          }
        );
      } catch (_e) {
        this.pinchCoverOpacity = 0;
        this.pinchCoverScale = 1;
      }
      this.pinchCoverDismissTimer = setTimeout((): void => {
        this.pinchCoverDismissTimer = -1;
        this.releasePinchCoverPix();
        this.pinchCoverPix = undefined;
        this.pinchCoverOpacity = 1;
        this.refreshOffsetArmed = false;
        this.pinchRefreshLocked = false;
        this.onAbortTimelineRefreshing();
      }, 220);
    }, 120);
  }

  private clearPinchCoverTimer(): void {
    if (this.pinchCoverDismissTimer >= 0) {
      clearTimeout(this.pinchCoverDismissTimer);
      this.pinchCoverDismissTimer = -1;
    }
  }

  private releasePinchCoverPix(): void {
    const pix = this.pinchCoverPix;
    if (pix === undefined) {
      return;
    }
    try {
      pix.release();
    } catch (_e) {
    }
  }

  private onGranularityPinchCancel(): void {
    this.granularityPinchActive = false;
    this.pinchCenterFrozen = false;
    this.pinchFollowScale = 1;
    this.pinchScaleUpdater.resetScale();
    this.unlockTwoFingerScrollIfIdle();
  }

  /**
   * 官方手势拦截增强：List/Refresh 内置 PAN 与 Pinch 竞争时，双指直接拒掉内置滑动。
   * onGestureRecognizerJudgeBegin 可拿到即将成功的识别器，能拦组件内置手势。
   */
  private onGranularityGestureRecognizerJudgeBegin(
    event: BaseGestureEvent,
    current: GestureRecognizer
  ): GestureJudgeResult {
    const type = current.getType();
    if (type === GestureControl.GestureType.PINCH_GESTURE) {
      if (!this.canRecognizeGranularityPinch()) {
        return GestureJudgeResult.REJECT;
      }
      return GestureJudgeResult.CONTINUE;
    }
    if (current.isBuiltIn() && type === GestureControl.GestureType.PAN_GESTURE) {
      if (this.isGranularityPinchBlockingScroll() || this.gestureFingerCount(event) >= 2) {
        return GestureJudgeResult.REJECT;
      }
    }
    return GestureJudgeResult.CONTINUE;
  }

  private onMainListScrollFrameBegin(offset: number, _state: ScrollState): OnScrollFrameBeginHandlerResult {
    if (this.isGranularityPinchBlockingScroll()) {
      return { offsetRemain: 0 };
    }
    return { offsetRemain: offset };
  }

  aboutToAppear(): void {
    this.syncThumbHighThroughputMode();
    this.resetGranularityMotion();
  }

  aboutToDisappear(): void {
    this.granularityPinchActive = false;
    this.twoFingerScrollLocked = false;
    this.pinchRefreshLocked = false;
    this.pinchCenterFrozen = false;
    this.clearPinchCoverTimer();
    this.releasePinchCoverPix();
    this.pinchCoverPix = undefined;
    this.pinchScaleUpdater.resetScale();
    this.onGranularityPinchActiveChange(false);
    this.onAbortTimelineRefreshing();
    galleryGridResetTouchTracking(this.slideTouch);
    setThumbHighThroughputLevel(0);
  }

  private onViewGranularityChanged(): void {
    this.syncThumbHighThroughputMode();
    if (this.pinchCoverPix === undefined) {
      this.pinchScaleUpdater.resetScale();
    }
  }

  private currentThumbPressureLoadMs(): number {
    return this.viewGranularity === GalleryViewGranularity.YEAR
      ? GALLERY_THUMB_NETWORK_PRESSURE_LOAD_MS_YEAR
      : GALLERY_THUMB_NETWORK_PRESSURE_LOAD_MS_MONTH;
  }

  private currentThumbPressureQueueWaitMs(): number {
    return this.viewGranularity === GalleryViewGranularity.YEAR
      ? GALLERY_THUMB_NETWORK_PRESSURE_QUEUE_WAIT_MS_YEAR
      : GALLERY_THUMB_NETWORK_PRESSURE_QUEUE_WAIT_MS_MONTH;
  }

  private maybeDropThumbThroughputForPressure(scrollState: ScrollState): void {
    if (this.viewGranularity === GalleryViewGranularity.DAY) {
      return;
    }
    if (scrollState === ScrollState.Idle || this.timelineSidebarDragging) {
      return;
    }
    const now = Date.now();
    if ((now - this.thumbLastAdaptiveDropAtMs) < GALLERY_THUMB_THROUGHPUT_DROP_COOLDOWN_MS) {
      return;
    }
    const telemetry = getThumbLoadTelemetry();
    if (telemetry.sampleCount < 4) {
      return;
    }
    const queueThreshold = Math.max(3, Math.floor(telemetry.currentLimit / 3));
    const saturated = telemetry.active >= Math.max(1, telemetry.currentLimit - 2);
    const backlogHeavy = telemetry.queued >= queueThreshold;
    const loaderSlow = telemetry.avgLoadMs >= this.currentThumbPressureLoadMs() ||
      telemetry.avgQueueWaitMs >= this.currentThumbPressureQueueWaitMs();
    if (
      saturated &&
      backlogHeavy &&
      loaderSlow &&
      this.thumbThroughputLevel > this.minThumbThroughputLevelForMode()
    ) {
      this.thumbThroughputLevel--;
      this.thumbLastAdaptiveDropAtMs = now;
      this.applyThumbThroughputLevel();
    }
  }

  private handleListDidScroll(offset: number, scrollState: ScrollState): void {
    gallerySlideAutoScrollOnListDidScroll(offset, scrollState);
    if (!this.isGranularityPinchBlockingScroll() && this.pinchCoverPix === undefined) {
      this.maybeDropThumbThroughputForPressure(scrollState);
    }
    this.onListDidScroll(offset, scrollState);
  }

  private currentThumbDensity(): 'day' | 'month' | 'year' {
    if (this.viewGranularity === GalleryViewGranularity.YEAR) {
      return 'year';
    }
    if (this.viewGranularity === GalleryViewGranularity.MONTH) {
      return 'month';
    }
    return 'day';
  }

  private rowTrailingBlankSlots(node: GalleryFlowNode): number[] {
    const blanks: number[] = [];
    const count = Math.max(0, node.rowColumnCount - node.rowSlotItems.length);
    for (let i = 0; i < count; i++) {
      blanks.push(i);
    }
    return blanks;
  }

  private loadingSkeletonColumns(): number[] {
    const cols: number[] = [];
    for (let i = 0; i < Math.max(1, this.gridColumns); i++) {
      cols.push(i);
    }
    return cols;
  }

  private currentListCachedCount(): number {
    if (this.viewGranularity === GalleryViewGranularity.YEAR) {
      return 14;
    }
    if (this.viewGranularity === GalleryViewGranularity.MONTH) {
      return 8;
    }
    // 官方 List.cachedCount：可视行约 n/2；列数变多时每行更重，预加载行略减
    return this.gridColumns >= 4 ? 2 : 3;
  }

  private shouldTrackGalleryThumbRect(): boolean {
    return this.gallerySelectionMode || this.gallerySlideGestureActive || this.slideTouch.initialSlidePending;
  }

  private vpToPx(value: number): number {
    try {
      return this.getUIContext().vp2px(value);
    } catch (_e) {
      return value;
    }
  }

  private asSlideTouchHost(): GalleryGridSlideTouchHost {
    const self = this;
    class MainSlideTouchHostBridge implements GalleryGridSlideTouchHost {
      getUIContext(): UIContext { return self.getUIContext(); }
      isSelectionMode(): boolean { return self.gallerySelectionMode; }
      isSlideActive(): boolean { return self.gallerySlideGestureActive; }
      endSlide(): void { self.endGallerySlideSelectGesture(); }
      followSlideAtWindowPx(xPx: number, yPx: number): void { self.onGallerySlideTouchMoveWindow(xPx, yPx); }
    }
    return new MainSlideTouchHostBridge();
  }

  private beginMainFirstSlideAtNode(node: GalleryFlowNode, xPx: number, yPx: number): boolean {
    const all = this.getFlatItems();
    const fi = this.pickGalleryThumbFlatForRowOrCache(node, xPx, yPx);
    if (fi < 0 || fi >= all.length) {
      return false;
    }
    const item = all[fi];
    if (!this.gallerySelectionMode) {
      this.onGalleryThumbLongPress(item);
    }
    this.beginGallerySlideSelectGestureAtWindowPx(item, fi, xPx, yPx);
    return true;
  }

  private onMainListTouchEvent(event: TouchEvent): void {
    const fingerCount = this.touchFingerCount(event);
    if (event.type === TouchType.Down && fingerCount >= 2 && this.canRecognizeGranularityPinch()) {
      this.lockTwoFingerScroll();
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (fingerCount < 2) {
        this.unlockTwoFingerScrollIfIdle();
      }
    }
    galleryGridHandleListTouch(this.slideTouch, this.asSlideTouchHost(), event);
  }

  @Builder
  private buildGalleryTimelineThumbCell(item: GalleryListItem, flatIndex: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      GalleryNetworkThumb({
        uri: nasUrl(this.baseUrl, pickThumbForGridDensity(item, this.currentThumbDensity())),
        isVideo: isVideoItem(item),
        isGif: isGifItem(item),
        isLive: isLivePhotoItem(item),
        paused: this.timelineSidebarDragging ||
          (this.isDraggingOrFling && this.pinchCoverPix === undefined),
        fadeInEnabled: this.viewGranularity === GalleryViewGranularity.DAY && this.pinchCoverPix === undefined,
        cacheIdentity: thumbIdentityOfItem(item),
        cacheRank: thumbDensityCacheRank(this.currentThumbDensity()),
        sharedTransitionId: gallerySharedTransitionId(this.itemIdOf(item))
      })
        .width('100%')
        .aspectRatio(1)
      if (this.timelineSidebarDragging) {
        GalleryStaticThumbPlaceholder({
          animatePulse: this.timelineSidebarDragging
        })
          .width('100%')
          .aspectRatio(1)
          .hitTestBehavior(HitTestMode.None)
      }
      GalleryAlbumSelectionOverlay({
        itemId: this.itemIdOf(item),
        visualScope: GALLERY_SELECTION_SCOPE_ALBUM,
        selectionMode: this.gallerySelectionMode
      })
    }
    .id(this.itemIdOf(item).length > 0 ? this.galleryThumbDomId(this.itemIdOf(item)) : `gt_na_${flatIndex}`)
    .onAreaChange((): void => {
      if (!this.shouldTrackGalleryThumbRect()) {
        return;
      }
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
  private buildFlowNode(node: GalleryFlowNode) {
    if (node.kind === 'month') {
      ListItem() {
        Text(this.viewGranularity === GalleryViewGranularity.YEAR
          ? `${node.year}年`
          : `${node.year}年${node.month}月`)
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
            if (slot !== null && slot !== undefined) {
              const id = this.itemIdOf(slot);
              if (id.length > 0) {
                return `ti_${node.key}_${k}_${id}`;
              }
              const fi = node.rowSlotFlatIndices[k];
              if (fi >= 0) {
                return `ti_${node.key}_${k}_f${fi}`;
              }
            }
            return `sk_${node.key}_${k}`;
          })
          ForEach(this.rowTrailingBlankSlots(node), (blankIndex: number) => {
            Blank().layoutWeight(1)
          }, (blankIndex: number) => `bk_${node.key}_${blankIndex}`)
        }
        .width('100%')
        .padding({ left: 2, right: 2, top: 1, bottom: 1 })
        .onTouch((event: TouchEvent): void => {
          galleryGridHandleRowTouch(
            this.slideTouch,
            this.asSlideTouchHost(),
            event,
            (xPx: number, yPx: number): boolean => this.beginMainFirstSlideAtNode(node, xPx, yPx)
          );
        })
        .parallelGesture(GestureGroup(GestureMode.Parallel,
          GestureGroup(GestureMode.Sequence,
            LongPressGesture({ repeat: false, duration: GALLERY_GRID_SEQUENCE_LONG_PRESS_MS })
              .onAction((ev: GestureEvent): void => {
                if (!galleryGridOnSequenceLongPress(this.slideTouch, this.asSlideTouchHost())) {
                  return;
                }
                galleryGridClearInitialSlide(this.slideTouch);
                this.endGallerySlideSelectGesture();
                const pt = this.readGestureFingerWindow(ev);
                if (pt === null) {
                  return;
                }
                if (!this.beginMainFirstSlideAtNode(node, this.vpToPx(pt.x), this.vpToPx(pt.y))) {
                  return;
                }
                galleryGridArmInitialSlide(this.slideTouch);
              }),
            PanGesture({
              fingers: 1,
              direction: PanDirection.All,
              distance: GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE
            })
              .onActionUpdate((ev: GestureEvent): void => {
                if (!galleryGridShouldUpdateSequencePan(this.slideTouch, this.asSlideTouchHost())) {
                  return;
                }
                this.onGallerySlidePanUpdate(ev);
              })
              .onActionEnd((): void => {
                galleryGridOnSequencePanFinish(this.slideTouch, this.asSlideTouchHost());
              })
              .onActionCancel((): void => {
                galleryGridOnSequencePanFinish(this.slideTouch, this.asSlideTouchHost());
              })
          ),
          PanGesture({
            fingers: 1,
            direction: PanDirection.Horizontal,
            distance: GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE
          })
            .onActionStart((ev: GestureEvent): void => {
              this.slideTouch.secondaryPanDriving = false;
              if (!galleryGridCanStartSecondaryPan(this.slideTouch, this.asSlideTouchHost(), ev)) {
                return;
              }
              const pt = this.readGestureFingerWindow(ev);
              if (pt === null) {
                return;
              }
              const xPx = this.vpToPx(pt.x);
              const yPx = this.vpToPx(pt.y);
              const fi = this.pickGalleryThumbFlatForRowOrCache(node, xPx, yPx);
              if (fi < 0) {
                return;
              }
              const all = this.getFlatItems();
              if (fi >= all.length) {
                return;
              }
              galleryGridOnSecondaryPanStart(this.slideTouch);
              this.beginGallerySlideSelectGesture(ev, all[fi], fi);
            })
            .onActionUpdate((ev: GestureEvent): void => {
              if (!galleryGridShouldUpdateSecondaryPan(this.slideTouch, this.asSlideTouchHost())) {
                return;
              }
              this.onGallerySlidePanUpdate(ev);
            })
            .onActionEnd((): void => {
              galleryGridOnSecondaryPanFinish(this.slideTouch, this.asSlideTouchHost());
            })
            .onActionCancel((): void => {
              galleryGridOnSecondaryPanFinish(this.slideTouch, this.asSlideTouchHost());
            })
        ))
      }
      .draggable(false)
    }
  }

  /**
   * 自定义刷新区。官方 ts-container-refresh：
   * 未设高度时随下拉区域收到 0；一旦子节点带固定高度（如 Blank.height），会一直露在刷新区下方。
   * 挖孔避让（AVOID-01）：转圈用 margin 避开 TYPE_SYSTEM∪TYPE_CUTOUT，不把占位做成固定高度。
   */
  @Builder
  private galleryRefreshContent() {
    Column() {
      if (this.shouldShowGalleryRefreshSpinner()) {
        LoadingProgress()
          .width(32)
          .height(32)
          .margin({ top: this.topSafeInsetVp })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  private galleryRefreshTriggerOffsetVp(): number {
    return galleryTimelineRefreshTriggerOffsetVp(this.topSafeInsetVp);
  }

  build() {
    if (this.bootLoading) {
      Column({ space: 8 }) {
        ForEach([0, 1, 2, 3], (row: number) => {
          Row({ space: 8 }) {
            ForEach(this.loadingSkeletonColumns(), (_: number) => {
              GalleryThumbSkeleton().layoutWeight(1)
            }, (n: number) => `sk_${row}_${n}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: row === 0 ? this.contentInsetTopVp + 24 : 0 })
        }, (r: number) => `skr_${r}`)
      }
      .width('100%')
      .opacity(this.modeSwitchOpacity * this.granularityOpacity)
      .translate({ x: this.modeSwitchOffsetY, y: 0 })
      .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
    } else {
      Column() {
        if (this.loadError.length > 0) {
          Text(this.loadError)
            .fontSize(14)
            .fontColor(Color.Red)
            .width('100%')
            .padding({ left: 16, right: 16, top: this.contentInsetTopVp + 8 })
        }

        Stack() {
          Stack({ alignContent: Alignment.TopEnd }) {
            Refresh({ refreshing: this.isTimelineRefreshVisualActive(), builder: this.galleryRefreshContent() }) {
              List({ scroller: this.scrollerRef }) {
                if (this.contentInsetTopVp > 0) {
                  ListItem() {
                    Column()
                      .width('100%')
                      .height(this.contentInsetTopVp)
                  }
                }
                LazyForEach(this.flowDataSource, (node: GalleryFlowNode) => {
                  this.buildFlowNode(node)
                }, (node: GalleryFlowNode) => this.galleryFlowLazyKey(node))

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
                    Blank().height((this.showBatchActionBar && this.gallerySelectionMode ? 88 : 32) +
                      this.contentInsetBottomVp)
                  }
                  .width('100%')
                }
              }
              .id(this.mainListDomId)
              .width('100%')
              .height('100%')
              .cachedCount(this.currentListCachedCount())
              .edgeEffect(EdgeEffect.Spring)
              .scrollBar(BarState.Off)
              .scrollBarColor(Color.Transparent)
              .scrollBarWidth(0)
              .divider({ strokeWidth: 0 })
              .enableScrollInteraction(this.galleryMainListScrollEnabled && this.pinchCoverPix === undefined)
              .attributeModifier(this.pinchScaleUpdater)
              .onTouch((event: TouchEvent): void => {
                this.onMainListTouchEvent(event);
              })
              .onScrollIndex(this.onListScrollIndex)
              .onDidScroll((offset: number, scrollState: ScrollState): void => {
                this.handleListDidScroll(offset, scrollState);
              })
              .onScrollFrameBegin((offset: number, state: ScrollState): OnScrollFrameBeginHandlerResult => {
                return this.onMainListScrollFrameBegin(offset, state);
              })
              .onScrollVisibleContentChange((start: VisibleListContentInfo, end: VisibleListContentInfo): void => {
                this.onListVisibleContentChange(start, end);
              })
              .onGestureRecognizerJudgeBegin((
                event: BaseGestureEvent,
                current: GestureRecognizer,
                _others: Array<GestureRecognizer>
              ): GestureJudgeResult => {
                return this.onGranularityGestureRecognizerJudgeBegin(event, current);
              })
              .priorityGesture(
                PinchGesture({ fingers: 2, distance: GALLERY_GRANULARITY_PINCH_DISTANCE_VP })
                  .onActionStart((event: GestureEvent): void => {
                    this.onGranularityPinchStart(event);
                  })
                  .onActionUpdate((event: GestureEvent): void => {
                    this.onGranularityPinchUpdate(event);
                  })
                  .onActionEnd((event: GestureEvent): void => {
                    this.onGranularityPinchEnd(event);
                  })
                  .onActionCancel((): void => {
                    this.onGranularityPinchCancel();
                  })
              )
            }
            .width('100%')
            .height('100%')
            .clip(true)
            .refreshOffset(this.galleryRefreshTriggerOffsetVp())
            .pullDownRatio(GALLERY_TIMELINE_REFRESH_PULL_RATIO)
            .onOffsetChange((offset: number): void => {
              this.onTimelineRefreshOffsetChange(offset);
            })
            .pullToRefresh(this.canPullToRefreshNow())
            .onRefreshing((): void => {
              this.onTimelineRefreshing();
            })
            .onStateChange((state: RefreshStatus): void => {
              this.onTimelineRefreshStateChange(state);
            })
            .onGestureRecognizerJudgeBegin((
              event: BaseGestureEvent,
              current: GestureRecognizer,
              _others: Array<GestureRecognizer>
            ): GestureJudgeResult => {
              return this.onGranularityGestureRecognizerJudgeBegin(event, current);
            })

            if (this.pinchCoverPix !== undefined) {
              Image(this.pinchCoverPix)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Fill)
                .scale({
                  x: this.pinchCoverScale,
                  y: this.pinchCoverScale,
                  centerX: this.pinchCoverCenterX,
                  centerY: this.pinchCoverCenterY
                })
                .opacity(this.pinchCoverOpacity)
                .hitTestBehavior(HitTestMode.None)
            }

            if (this.showTimelineSidebar()) {
              GalleryAlbumTimelineSidebar({
                trackInsetTopVp: this.contentInsetTopVp,
                trackInsetBottomVp: this.contentInsetBottomVp,
                expandedChrome: this.timelineExpandedChrome,
                scrollRailOnly: this.timelineScrollRailOnly,
                yearMarkers: this.timelineYearMarkers,
                pillLabel: this.timelineScrubPillLabel,
                timelineSidebarDragging: this.timelineSidebarDragging,
                timelineBarVisible: this.timelineBarVisible,
                timelinePressing: this.timelinePressing,
                timelineLongPressExpanded: this.timelineLongPressExpanded,
                timelineIndicatorY: this.timelineIndicatorY,
                timelineSliderRatio: this.timelineSliderRatio,
                onSeekToCurrentRatio: this.onTimelineSeekToCurrentRatio,
                onTrackHeightChange: this.onTimelineTrackHeightChange,
                onTouchStateChange: this.onTimelineTouchStateChange,
                onLongPressExpand: this.onTimelineLongPressExpand,
                onPanStart: this.onTimelinePanStart,
                onPanUpdate: this.onTimelinePanUpdate,
                onPanEnd: this.onTimelinePanEnd,
                onPanCancel: this.onTimelinePanCancel
              })
            }
          }
          .width('100%')
          .height('100%')
          .clip(false)

          if (this.showBatchActionBar && this.gallerySelectionMode) {
            GalleryAlbumBatchActionBar({
              downloading: this.galleryBatchDownloading,
              deleting: this.galleryBatchDeleting,
              onDownload: this.onBatchDownload,
              onDelete: this.onBatchDelete
            })
              .width('100%')
              .height('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
      .opacity(this.modeSwitchOpacity * this.granularityOpacity)
      .translate({ x: this.modeSwitchOffsetY, y: 0 })
      .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
    }
  }
}
