import {
  GALLERY_TIMELINE_HIT_WIDTH_VP,
  GALLERY_TIMELINE_INDICATOR_PAD_VP,
  GALLERY_TIMELINE_LONG_PRESS_EXPAND_MS,
  GALLERY_TIMELINE_TRACK_DOM_ID,
} from './GalleryAlbumTabConstants';
import { YearMarker } from './GalleryAlbumTabTypes';

const GALLERY_TIMELINE_RING_WIDTH_VP: number = 18;
const GALLERY_TIMELINE_RING_HEIGHT_VP: number = 44;
const GALLERY_TIMELINE_RING_ACTIVE_SCALE: number = 1.12;
const GALLERY_TIMELINE_RING_RIGHT_MARGIN_VP: number = 4;
const GALLERY_TIMELINE_RING_BORDER_WIDTH_VP: number = 2.4;
const GALLERY_TIMELINE_YEAR_BADGE_WIDTH_VP: number = 44;
const GALLERY_TIMELINE_YEAR_BADGE_GAP_VP: number = 6;
const GALLERY_TIMELINE_PILL_WIDTH_VP: number = 108;
const GALLERY_TIMELINE_PILL_GAP_VP: number = 8;

@Component
export struct GalleryAlbumTimelineSidebar {
  @Prop trackInsetTopVp: number = 0;
  @Prop trackInsetBottomVp: number = 0;
  @Prop expandedChrome: boolean = false;
  @Prop scrollRailOnly: boolean = false;
  @Prop yearMarkers: YearMarker[] = [];
  @Prop pillLabel: string = '';
  @Prop timelineSidebarDragging: boolean = false;
  @Prop timelineBarVisible: boolean = false;
  @Prop timelinePressing: boolean = false;
  @Prop timelineLongPressExpanded: boolean = false;
  @Prop timelineIndicatorY: number = 0;
  @Prop timelineSliderRatio: number = 0;

  onSeekToCurrentRatio: () => void = () => {};
  onTrackHeightChange: (height: number) => void = (_: number) => {};
  onTouchStateChange: (event: TouchEvent) => void = (_: TouchEvent) => {};
  onLongPressExpand: () => void = () => {};
  onPanStart: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onPanUpdate: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onPanEnd: (event: GestureEvent) => void = (_: GestureEvent) => {};
  onPanCancel: (event: GestureEvent) => void = (_: GestureEvent) => {};

  private ringActive(): boolean {
    return this.timelineSidebarDragging || this.timelinePressing || this.timelineLongPressExpanded;
  }

  private ringScale(): number {
    return this.ringActive() ? GALLERY_TIMELINE_RING_ACTIVE_SCALE : 1;
  }

  private ringWidth(): number {
    return GALLERY_TIMELINE_RING_WIDTH_VP * this.ringScale();
  }

  private ringHeight(): number {
    return GALLERY_TIMELINE_RING_HEIGHT_VP * this.ringScale();
  }

  private ringX(): number {
    return GALLERY_TIMELINE_HIT_WIDTH_VP - this.ringWidth() - GALLERY_TIMELINE_RING_RIGHT_MARGIN_VP;
  }

  private ringY(): number {
    return Math.max(GALLERY_TIMELINE_INDICATOR_PAD_VP, this.timelineIndicatorY - this.ringHeight() / 2);
  }

  private yearBadgeX(): number {
    return this.ringX() - GALLERY_TIMELINE_YEAR_BADGE_WIDTH_VP - GALLERY_TIMELINE_YEAR_BADGE_GAP_VP;
  }

  private pillX(): number {
    return this.ringX() - GALLERY_TIMELINE_PILL_WIDTH_VP - GALLERY_TIMELINE_PILL_GAP_VP;
  }

  build() {
    Column() {
      if (this.trackInsetTopVp > 0) {
        Blank()
          .height(this.trackInsetTopVp)
          .hitTestBehavior(HitTestMode.None)
      }

      Stack({ alignContent: Alignment.TopStart }) {
        if (this.expandedChrome) {
          ForEach(this.yearMarkers, (marker: YearMarker) => {
            Text(`${marker.year}`)
              .width(GALLERY_TIMELINE_YEAR_BADGE_WIDTH_VP)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.gallery_timeline_year_badge_fg'))
              .textAlign(TextAlign.Center)
              .padding({ left: 6, right: 6, top: 4, bottom: 4 })
              .backgroundColor($r('app.color.gallery_timeline_year_badge_bg'))
              .borderRadius(10)
              .shadow({ radius: 10, color: '#22000000', offsetX: 0, offsetY: 4 })
              .position({ x: this.yearBadgeX(), y: marker.y - 12 })
          }, (m: YearMarker) => `ym_${m.year}`)
        }

        Column()
          .width(this.ringWidth())
          .height(this.ringHeight())
          .backgroundColor(Color.Transparent)
          .border({ width: GALLERY_TIMELINE_RING_BORDER_WIDTH_VP, color: $r('app.color.gallery_timeline_thumb_border') })
          .borderRadius(this.ringWidth())
          .shadow({
            radius: this.ringActive() ? 14 : 10,
            color: this.ringActive() ? '#42FFFFFF' : '#28FFFFFF',
            offsetX: 0,
            offsetY: 0
          })
          .position({ x: this.ringX(), y: this.ringY() })
          .animation({ duration: 180, curve: Curve.EaseOut })

        if (this.expandedChrome) {
          Text(this.pillLabel)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.gallery_timeline_month_pill_fg'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width(GALLERY_TIMELINE_PILL_WIDTH_VP)
            .textAlign(TextAlign.Center)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.gallery_timeline_month_pill_bg'))
            .borderRadius(12)
            .shadow({ radius: 12, color: '#22000000', offsetX: 0, offsetY: 5 })
            .position({ x: this.pillX(), y: Math.max(6, this.ringY() + this.ringHeight() / 2 - 20) })
            .scale({
              x: this.timelineSidebarDragging ? 1.15 : 1.0,
              y: this.timelineSidebarDragging ? 1.15 : 1.0
            })
            .animation({ duration: 180, curve: Curve.EaseOut })
            .gesture(TapGesture().onAction(this.onSeekToCurrentRatio))
        }
      }
      .width(GALLERY_TIMELINE_HIT_WIDTH_VP)
      .id(GALLERY_TIMELINE_TRACK_DOM_ID)
      .layoutWeight(1)
      .clip(false)
      .onAreaChange((_: Area, area: Area): void => {
        const h = area.height as number;
        if (h > 1) {
          this.onTrackHeightChange(h);
        }
      })
      .onTouch(this.onTouchStateChange)
      .parallelGesture(
        GestureGroup(GestureMode.Parallel,
          LongPressGesture({ repeat: false, duration: GALLERY_TIMELINE_LONG_PRESS_EXPAND_MS })
            .onAction(this.onLongPressExpand),
          PanGesture({ direction: PanDirection.Vertical, distance: 2 })
            .onActionStart(this.onPanStart)
            .onActionUpdate(this.onPanUpdate)
            .onActionEnd(this.onPanEnd)
            .onActionCancel(this.onPanCancel)
        )
      )
      .opacity(
        this.timelineSidebarDragging || this.timelinePressing || this.timelineLongPressExpanded || this.timelineBarVisible ? 1 : 0
      )
      .animation({ duration: 280, curve: Curve.EaseInOut })

      if (this.trackInsetBottomVp > 0) {
        Blank()
          .height(this.trackInsetBottomVp)
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(GALLERY_TIMELINE_HIT_WIDTH_VP)
    .height('100%')
    .clip(false)
  }
}
