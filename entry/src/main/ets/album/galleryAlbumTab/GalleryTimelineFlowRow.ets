import { UIContext } from '@kit.ArkUI';
import { GalleryListItem } from '../../model/FnApiTypes';
import { GalleryFlowNode } from '../GalleryFlowDataSource';
import {
  GalleryNetworkThumb,
  GalleryStaticThumbPlaceholder,
  GalleryThumbSkeleton,
  isGifItem,
  isVideoItem,
  nasUrl,
  pickThumbForGridDensity,
  thumbDensityCacheRank,
  thumbIdentityOfItem
} from '../GalleryAlbumCommon';
import { isLivePhotoItem } from '../livephoto/LivePhotoDetect';
import { gallerySharedTransitionId } from '../GallerySharedTransition';
import { GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE } from '../GallerySlidePick';
import {
  galleryGridArmInitialSlide,
  galleryGridCanStartSecondaryPan,
  galleryGridClearInitialSlide,
  galleryGridHandleRowTouch,
  galleryGridOnSecondaryPanFinish,
  galleryGridOnSecondaryPanStart,
  galleryGridOnSequenceLongPress,
  galleryGridOnSequencePanFinish,
  galleryGridShouldUpdateSecondaryPan,
  galleryGridShouldUpdateSequencePan,
  GalleryGridSlideTouchHost,
  GalleryGridSlideTouchSession,
  GALLERY_GRID_SEQUENCE_LONG_PRESS_MS
} from '../GalleryGridSlideTouch';
import { GalleryFingerWindowPoint } from './GalleryAlbumTabTypes';
import { GalleryViewGranularity } from './GalleryAlbumGranularity';
import { GalleryAlbumSelectionOverlay, GALLERY_SELECTION_SCOPE_ALBUM } from './GalleryAlbumSelectionOverlay';

/**
 * 时间线宫格行回调。对象由父组件长期持有，滚动复用时不重建，避免 @Prop 灌整屏。
 */
export interface GalleryTimelineFlowRowHost {
  itemIdOf(item: GalleryListItem): string;
  galleryThumbDomId(photoId: string): string;
  recordGalleryThumbRectFromDom(photoId: string, domId: string): void;
  onGalleryThumbTap(item: GalleryListItem, flatIndex: number): void;
  getFlatItems(): GalleryListItem[];
  endGallerySlideSelectGesture(): void;
  readGestureFingerWindow(ev: GestureEvent): GalleryFingerWindowPoint | null;
  pickGalleryThumbFlatForRowOrCache(node: GalleryFlowNode, xPx: number, yPx: number): number;
  onGalleryThumbLongPress(item: GalleryListItem): void;
  beginGallerySlideSelectGesture(ev: GestureEvent, item: GalleryListItem, anchorFlat: number): void;
  beginGallerySlideSelectGestureAtWindowPx(item: GalleryListItem, anchorFlat: number, xPx: number, yPx: number): void;
  onGallerySlidePanUpdate(ev: GestureEvent): void;
  shouldTrackGalleryThumbRect(): boolean;
  isSelectionMode(): boolean;
  isSlideActive(): boolean;
  endSlide(): void;
  followSlideAtWindowPx(xPx: number, yPx: number): void;
}

class EmptyGalleryTimelineFlowRowHost implements GalleryTimelineFlowRowHost {
  itemIdOf(_item: GalleryListItem): string {
    return '';
  }

  galleryThumbDomId(_photoId: string): string {
    return '';
  }

  recordGalleryThumbRectFromDom(_photoId: string, _domId: string): void {
  }

  onGalleryThumbTap(_item: GalleryListItem, _flatIndex: number): void {
  }

  getFlatItems(): GalleryListItem[] {
    return [];
  }

  endGallerySlideSelectGesture(): void {
  }

  readGestureFingerWindow(_ev: GestureEvent): GalleryFingerWindowPoint | null {
    return null;
  }

  pickGalleryThumbFlatForRowOrCache(_node: GalleryFlowNode, _xPx: number, _yPx: number): number {
    return -1;
  }

  onGalleryThumbLongPress(_item: GalleryListItem): void {
  }

  beginGallerySlideSelectGesture(_ev: GestureEvent, _item: GalleryListItem, _anchorFlat: number): void {
  }

  beginGallerySlideSelectGestureAtWindowPx(_item: GalleryListItem, _anchorFlat: number, _xPx: number,
    _yPx: number): void {
  }

  onGallerySlidePanUpdate(_ev: GestureEvent): void {
  }

  shouldTrackGalleryThumbRect(): boolean {
    return false;
  }

  isSelectionMode(): boolean {
    return false;
  }

  isSlideActive(): boolean {
    return false;
  }

  endSlide(): void {
  }

  followSlideAtWindowPx(_xPx: number, _yPx: number): void {
  }
}

const EMPTY_FLOW_ROW_HOST: GalleryTimelineFlowRowHost = new EmptyGalleryTimelineFlowRowHost();

/**
 * 时间线缩略图行。@Reusable：快滑时整行（含划选手势）进复用池，避免每行重建 ListItem 子树。
 */
@Reusable
@Component({ freezeWhenInactive: true })
export struct GalleryTimelineFlowRow {
  @Prop node: GalleryFlowNode = new GalleryFlowNode();
  @Prop baseUrl: string = '';
  @Prop viewGranularity: GalleryViewGranularity = GalleryViewGranularity.DAY;
  @Prop gallerySelectionMode: boolean = false;
  @Prop timelineSidebarDragging: boolean = false;
  @Prop fadeInEnabled: boolean = true;
  host: GalleryTimelineFlowRowHost = EMPTY_FLOW_ROW_HOST;
  slideTouch: GalleryGridSlideTouchSession = new GalleryGridSlideTouchSession();
  private slideHost: GalleryGridSlideTouchHost | undefined = undefined;

  aboutToReuse(params: Record<string, Object | undefined | null>): void {
    const nextNode = params.node;
    if (nextNode !== undefined && nextNode !== null) {
      this.node = nextNode as GalleryFlowNode;
    }
    const nextBaseUrl = params.baseUrl;
    if (nextBaseUrl !== undefined && nextBaseUrl !== null) {
      this.baseUrl = nextBaseUrl as string;
    }
    this.ensureSlideHost();
  }

  aboutToAppear(): void {
    this.ensureSlideHost();
  }

  private ensureSlideHost(): void {
    if (this.slideHost !== undefined) {
      return;
    }
    const self = this;
    class RowSlideTouchHostBridge implements GalleryGridSlideTouchHost {
      getUIContext(): UIContext {
        return self.getUIContext();
      }

      isSelectionMode(): boolean {
        return self.host.isSelectionMode();
      }

      isSlideActive(): boolean {
        return self.host.isSlideActive();
      }

      endSlide(): void {
        self.host.endSlide();
      }

      followSlideAtWindowPx(xPx: number, yPx: number): void {
        self.host.followSlideAtWindowPx(xPx, yPx);
      }
    }
    this.slideHost = new RowSlideTouchHostBridge();
  }

  private currentSlideHost(): GalleryGridSlideTouchHost {
    this.ensureSlideHost();
    return this.slideHost as GalleryGridSlideTouchHost;
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

  private vpToPx(value: number): number {
    try {
      return this.getUIContext().vp2px(value);
    } catch (_e) {
      return value;
    }
  }

  private rowTrailingBlankSlots(): number[] {
    const blanks: number[] = [];
    const count = Math.max(0, this.node.rowColumnCount - this.node.rowSlotItems.length);
    for (let i = 0; i < count; i++) {
      blanks.push(i);
    }
    return blanks;
  }

  private beginFirstSlideAtNode(xPx: number, yPx: number): boolean {
    const all = this.host.getFlatItems();
    const fi = this.host.pickGalleryThumbFlatForRowOrCache(this.node, xPx, yPx);
    if (fi < 0 || fi >= all.length) {
      return false;
    }
    const item = all[fi];
    if (!this.host.isSelectionMode()) {
      this.host.onGalleryThumbLongPress(item);
    }
    this.host.beginGallerySlideSelectGestureAtWindowPx(item, fi, xPx, yPx);
    return true;
  }

  @Builder
  private buildThumbCell(item: GalleryListItem, flatIndex: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      GalleryNetworkThumb({
        uri: nasUrl(this.baseUrl, pickThumbForGridDensity(item, this.currentThumbDensity())),
        isVideo: isVideoItem(item),
        isGif: isGifItem(item),
        isLive: isLivePhotoItem(item),
        paused: this.timelineSidebarDragging,
        fadeInEnabled: this.fadeInEnabled,
        cacheIdentity: thumbIdentityOfItem(item),
        cacheRank: thumbDensityCacheRank(this.currentThumbDensity()),
        sharedTransitionId: gallerySharedTransitionId(this.host.itemIdOf(item))
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
        itemId: this.host.itemIdOf(item),
        visualScope: GALLERY_SELECTION_SCOPE_ALBUM,
        selectionMode: this.gallerySelectionMode
      })
    }
    .id(this.host.itemIdOf(item).length > 0 ? this.host.galleryThumbDomId(this.host.itemIdOf(item)) :
      `gt_na_${flatIndex}`)
    .onAreaChange((): void => {
      if (!this.host.shouldTrackGalleryThumbRect()) {
        return;
      }
      const pid = this.host.itemIdOf(item);
      if (pid.length > 0) {
        this.host.recordGalleryThumbRectFromDom(pid, this.host.galleryThumbDomId(pid));
      }
    })
    .layoutWeight(1)
    .aspectRatio(1)
    .backgroundColor(Color.Transparent)
    .draggable(false)
    .onClick((): void => {
      this.host.onGalleryThumbTap(item, flatIndex);
    })
  }

  build() {
    Row({ space: 2 }) {
      ForEach(this.node.rowSlotItems, (slot: GalleryListItem | null, k: number) => {
        if (slot !== null && slot !== undefined) {
          this.buildThumbCell(slot, this.node.rowSlotFlatIndices[k])
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
          const id = this.host.itemIdOf(slot);
          if (id.length > 0) {
            return `ti_${this.node.key}_${k}_${id}`;
          }
          const fi = this.node.rowSlotFlatIndices[k];
          if (fi >= 0) {
            return `ti_${this.node.key}_${k}_f${fi}`;
          }
        }
        return `sk_${this.node.key}_${k}`;
      })
      ForEach(this.rowTrailingBlankSlots(), (_blankIndex: number) => {
        Blank().layoutWeight(1)
      }, (_blankIndex: number) => `bk_${this.node.key}_${_blankIndex}`)
    }
    .width('100%')
    .padding({ left: 2, right: 2, top: 1, bottom: 1 })
    .onTouch((event: TouchEvent): void => {
      galleryGridHandleRowTouch(
        this.slideTouch,
        this.currentSlideHost(),
        event,
        (xPx: number, yPx: number): boolean => this.beginFirstSlideAtNode(xPx, yPx)
      );
    })
    .parallelGesture(GestureGroup(GestureMode.Parallel,
      GestureGroup(GestureMode.Sequence,
        LongPressGesture({ repeat: false, duration: GALLERY_GRID_SEQUENCE_LONG_PRESS_MS })
          .onAction((ev: GestureEvent): void => {
            if (!galleryGridOnSequenceLongPress(this.slideTouch, this.currentSlideHost())) {
              return;
            }
            galleryGridClearInitialSlide(this.slideTouch);
            this.host.endGallerySlideSelectGesture();
            const pt = this.host.readGestureFingerWindow(ev);
            if (pt === null) {
              return;
            }
            if (!this.beginFirstSlideAtNode(this.vpToPx(pt.x), this.vpToPx(pt.y))) {
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
            if (!galleryGridShouldUpdateSequencePan(this.slideTouch, this.currentSlideHost())) {
              return;
            }
            this.host.onGallerySlidePanUpdate(ev);
          })
          .onActionEnd((): void => {
            galleryGridOnSequencePanFinish(this.slideTouch, this.currentSlideHost());
          })
          .onActionCancel((): void => {
            galleryGridOnSequencePanFinish(this.slideTouch, this.currentSlideHost());
          })
      ),
      PanGesture({
        fingers: 1,
        direction: PanDirection.Horizontal,
        distance: GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE
      })
        .onActionStart((ev: GestureEvent): void => {
          this.slideTouch.secondaryPanDriving = false;
          if (!galleryGridCanStartSecondaryPan(this.slideTouch, this.currentSlideHost(), ev)) {
            return;
          }
          const pt = this.host.readGestureFingerWindow(ev);
          if (pt === null) {
            return;
          }
          const xPx = this.vpToPx(pt.x);
          const yPx = this.vpToPx(pt.y);
          const fi = this.host.pickGalleryThumbFlatForRowOrCache(this.node, xPx, yPx);
          if (fi < 0) {
            return;
          }
          const all = this.host.getFlatItems();
          if (fi >= all.length) {
            return;
          }
          galleryGridOnSecondaryPanStart(this.slideTouch);
          this.host.beginGallerySlideSelectGesture(ev, all[fi], fi);
        })
        .onActionUpdate((ev: GestureEvent): void => {
          if (!galleryGridShouldUpdateSecondaryPan(this.slideTouch, this.currentSlideHost())) {
            return;
          }
          this.host.onGallerySlidePanUpdate(ev);
        })
        .onActionEnd((): void => {
          galleryGridOnSecondaryPanFinish(this.slideTouch, this.currentSlideHost());
        })
        .onActionCancel((): void => {
          galleryGridOnSecondaryPanFinish(this.slideTouch, this.currentSlideHost());
        })
    ))
  }
}
