import {
  GALLERY_TIMELINE_HIT_WIDTH_VP,
  GALLERY_TIMELINE_INDICATOR_PAD_VP,
  GALLERY_TIMELINE_LONG_PRESS_EXPAND_MS,
  GALLERY_TIMELINE_RAIL_DRAG_VP,
  GALLERY_TIMELINE_RAIL_EXPANDED_VP,
  GALLERY_TIMELINE_RAIL_MIN_VP,
  GALLERY_TIMELINE_SCRUB_PILL_MIN_WIDTH_VP,
  GALLERY_TIMELINE_SCRUB_PILL_X_VP,
  GALLERY_TIMELINE_THUMB_VP,
  GALLERY_TIMELINE_YEAR_BADGE_X_VP
} from './GalleryAlbumTabConstants';
import { YearMarker } from './GalleryAlbumTabTypes';

@Component
export struct GalleryAlbumTimelineSidebar {
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

  private railWidth(): number {
    if (!this.expandedChrome) {
      return GALLERY_TIMELINE_RAIL_MIN_VP;
    }
    return this.timelineSidebarDragging ? GALLERY_TIMELINE_RAIL_DRAG_VP : GALLERY_TIMELINE_RAIL_EXPANDED_VP;
  }

  private railX(): number {
    return GALLERY_TIMELINE_HIT_WIDTH_VP - this.railWidth();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.expandedChrome) {
        ForEach(this.yearMarkers, (marker: YearMarker) => {
          Text(`${marker.year}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.gallery_timeline_year_badge_fg'))
            .backgroundColor($r('app.color.gallery_timeline_year_badge_bg'))
            .padding({ left: 5, right: 5, top: 3, bottom: 3 })
            .borderRadius(4)
            .position({ x: GALLERY_TIMELINE_YEAR_BADGE_X_VP, y: marker.y - 9 })
        }, (m: YearMarker) => `ym_${m.year}`)
      }

      Column()
        .width(this.railWidth())
        .height('100%')
        .backgroundColor(this.timelineSidebarDragging
          ? $r('app.color.gallery_timeline_rail_drag')
          : (this.expandedChrome
            ? $r('app.color.gallery_timeline_rail_expanded')
            : $r('app.color.gallery_timeline_rail')))
        .borderRadius(3)
        .position({ x: this.railX(), y: 0 })
        .animation({ duration: 180, curve: Curve.EaseOut })

      if (this.scrollRailOnly) {
        Circle()
          .width(GALLERY_TIMELINE_THUMB_VP)
          .height(GALLERY_TIMELINE_THUMB_VP)
          .fill($r('app.color.gallery_timeline_thumb_fill'))
          .stroke($r('app.color.gallery_timeline_thumb_border'))
          .strokeWidth(1.5)
          .position({
            x: GALLERY_TIMELINE_HIT_WIDTH_VP - GALLERY_TIMELINE_RAIL_MIN_VP - GALLERY_TIMELINE_THUMB_VP + 1,
            y: Math.max(GALLERY_TIMELINE_INDICATOR_PAD_VP, this.timelineIndicatorY - GALLERY_TIMELINE_THUMB_VP / 2)
          })
      }

      if (this.expandedChrome) {
        Text(this.pillLabel)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.timelineSidebarDragging
            ? $r('app.color.button_primary_fg')
            : $r('app.color.gallery_timeline_month_pill_fg'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(GALLERY_TIMELINE_SCRUB_PILL_MIN_WIDTH_VP)
          .textAlign(TextAlign.Center)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.timelineSidebarDragging
            ? $r('app.color.brand_primary')
            : $r('app.color.gallery_timeline_month_pill_bg'))
          .borderRadius(12)
          .position({ x: GALLERY_TIMELINE_SCRUB_PILL_X_VP, y: Math.max(6, this.timelineIndicatorY - 20) })
          .scale({
            x: this.timelineSidebarDragging ? 1.15 : 1.0,
            y: this.timelineSidebarDragging ? 1.15 : 1.0
          })
          .animation({ duration: 180, curve: Curve.EaseOut })
          .gesture(TapGesture().onAction(this.onSeekToCurrentRatio))
      }
    }
    .width(GALLERY_TIMELINE_HIT_WIDTH_VP)
    .height('100%')
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
  }
}
