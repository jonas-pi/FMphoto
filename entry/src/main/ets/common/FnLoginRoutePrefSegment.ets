/**
 * 登录选路策略：按住横向滑动，指示器跟手，松手吸附到最近项。
 */
import {
  LOGIN_ENDPOINT_PREF_AUTO,
  LOGIN_ENDPOINT_PREF_BANDWIDTH,
  LOGIN_ENDPOINT_PREF_LAN,
  LOGIN_ENDPOINT_PREF_LATENCY,
  LOGIN_ENDPOINT_PREF_PUBLIC
} from '../network/LoginEndpointSelector';
import { fnArkUiSupportsSystemMaterial, fnHdsSegmentSystemMaterial } from './FnHdsOverlay';

const LOGIN_ROUTE_PREF_VALUES: string[] = [
  LOGIN_ENDPOINT_PREF_AUTO,
  LOGIN_ENDPOINT_PREF_LAN,
  LOGIN_ENDPOINT_PREF_PUBLIC,
  LOGIN_ENDPOINT_PREF_LATENCY,
  LOGIN_ENDPOINT_PREF_BANDWIDTH
];

const LOGIN_ROUTE_PREF_LABELS: string[] = ['自动', '内网', '公网', '延迟', '带宽'];
const LOGIN_ROUTE_ITEM_COUNT: number = LOGIN_ROUTE_PREF_VALUES.length;
const LOGIN_ROUTE_SEGMENT_HEIGHT_VP: number = 40;
const LOGIN_ROUTE_SEGMENT_RADIUS_VP: number = 20;
const LOGIN_ROUTE_SEGMENT_INNER_PAD_VP: number = 3;
const LOGIN_ROUTE_SEGMENT_INNER_RADIUS_VP: number = 17;

function fnLoginRoutePrefIndex(value: string): number {
  const idx = LOGIN_ROUTE_PREF_VALUES.indexOf(value);
  return idx >= 0 ? idx : 0;
}

@Component
export struct FnLoginRoutePrefSegment {
  @Prop @Watch('onSelectedValueChanged') selectedValue: string = LOGIN_ENDPOINT_PREF_AUTO;
  @Prop disabled: boolean = false;
  onValueChange: (value: string) => void = (_: string) => {};
  @State private selectedIndex: number = 0;
  @State private trackWidthVp: number = 0;
  @State private thumbXVp: number = LOGIN_ROUTE_SEGMENT_INNER_PAD_VP;
  @State private dragging: boolean = false;
  private panStartThumbX: number = 0;

  aboutToAppear(): void {
    this.selectedIndex = fnLoginRoutePrefIndex(this.selectedValue);
  }

  private onSelectedValueChanged(): void {
    if (this.dragging) {
      return;
    }
    const nextIndex = fnLoginRoutePrefIndex(this.selectedValue);
    if (nextIndex !== this.selectedIndex) {
      this.selectedIndex = nextIndex;
      this.thumbXVp = this.snapXForIndex(nextIndex);
    }
  }

  private itemWidth(): number {
    const inner = this.trackWidthVp - LOGIN_ROUTE_SEGMENT_INNER_PAD_VP * 2;
    if (inner <= 0) {
      return 0;
    }
    return inner / LOGIN_ROUTE_ITEM_COUNT;
  }

  private maxThumbX(): number {
    return LOGIN_ROUTE_SEGMENT_INNER_PAD_VP + this.itemWidth() * (LOGIN_ROUTE_ITEM_COUNT - 1);
  }

  private snapXForIndex(index: number): number {
    return LOGIN_ROUTE_SEGMENT_INNER_PAD_VP + index * this.itemWidth();
  }

  private clampThumbX(x: number): number {
    const minX = LOGIN_ROUTE_SEGMENT_INNER_PAD_VP;
    const maxX = this.maxThumbX();
    if (x < minX) {
      return minX;
    }
    if (x > maxX) {
      return maxX;
    }
    return x;
  }

  private indexFromThumbX(x: number): number {
    const w = this.itemWidth();
    if (w <= 0) {
      return this.selectedIndex;
    }
    const raw = Math.round((x - LOGIN_ROUTE_SEGMENT_INNER_PAD_VP) / w);
    return Math.max(0, Math.min(LOGIN_ROUTE_ITEM_COUNT - 1, raw));
  }

  private indexFromLocalX(localX: number): number {
    const w = this.itemWidth();
    if (w <= 0) {
      return this.selectedIndex;
    }
    const raw = Math.floor((localX - LOGIN_ROUTE_SEGMENT_INNER_PAD_VP) / w);
    return Math.max(0, Math.min(LOGIN_ROUTE_ITEM_COUNT - 1, raw));
  }

  private commitIndex(index: number): void {
    if (this.disabled) {
      return;
    }
    this.selectedIndex = index;
    this.thumbXVp = this.snapXForIndex(index);
    this.onValueChange(LOGIN_ROUTE_PREF_VALUES[index]);
  }

  private onPanStart(): void {
    if (this.disabled) {
      return;
    }
    this.dragging = true;
    this.panStartThumbX = this.thumbXVp;
  }

  private onPanUpdate(offsetX: number): void {
    if (this.disabled || this.itemWidth() <= 0) {
      return;
    }
    this.thumbXVp = this.clampThumbX(this.panStartThumbX + offsetX);
  }

  private onPanEnd(): void {
    if (this.disabled) {
      this.dragging = false;
      return;
    }
    this.dragging = false;
    this.commitIndex(this.indexFromThumbX(this.thumbXVp));
  }

  private onTapLocalX(localX: number): void {
    if (this.disabled) {
      return;
    }
    this.commitIndex(this.indexFromLocalX(localX));
  }

  @Builder
  private segmentTrack() {
    Row()
      .width('100%')
      .height(LOGIN_ROUTE_SEGMENT_HEIGHT_VP)
      .borderRadius(LOGIN_ROUTE_SEGMENT_RADIUS_VP)
      .borderWidth(1)
      .borderColor($r('app.color.login_input_border'))
      .backgroundColor(fnArkUiSupportsSystemMaterial() ? Color.Transparent : $r('app.color.login_input_fill'))
      .systemMaterial(fnHdsSegmentSystemMaterial())
  }

  @Builder
  private segmentThumb() {
    Row()
      .width(this.itemWidth() > 0 ? this.itemWidth() : 0)
      .height(LOGIN_ROUTE_SEGMENT_HEIGHT_VP - LOGIN_ROUTE_SEGMENT_INNER_PAD_VP * 2)
      .borderRadius(LOGIN_ROUTE_SEGMENT_INNER_RADIUS_VP)
      .backgroundColor($r('app.color.brand_primary'))
      .offset({ x: this.thumbXVp, y: LOGIN_ROUTE_SEGMENT_INNER_PAD_VP })
      .animation(this.dragging ? { duration: 0 } : { duration: 180, curve: Curve.EaseOut })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private segmentLabels() {
    Row() {
      ForEach(LOGIN_ROUTE_PREF_LABELS, (label: string, idx: number) => {
        Text(label)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontSize(13)
          .fontWeight(this.indexFromThumbX(this.thumbXVp) === idx ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.indexFromThumbX(this.thumbXVp) === idx ?
            $r('app.color.button_primary_fg') : $r('app.color.text_secondary'))
      }, (label: string, idx: number) => `login_route_seg_label_${idx}_${label}`)
    }
    .width('100%')
    .height(LOGIN_ROUTE_SEGMENT_HEIGHT_VP)
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Column({ space: 10 }) {
      Text($r('app.string.login_route_pref_title'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)

      Stack({ alignContent: Alignment.TopStart }) {
        this.segmentTrack()
        this.segmentThumb()
        this.segmentLabels()
      }
      .width('100%')
      .height(LOGIN_ROUTE_SEGMENT_HEIGHT_VP)
      .clip(true)
      .opacity(this.disabled ? 0.45 : 1)
      .onAreaChange((_old, area: Area) => {
        const w = area.width as number;
        if (w > 0 && w !== this.trackWidthVp) {
          this.trackWidthVp = w;
          this.thumbXVp = this.snapXForIndex(this.selectedIndex);
        }
      })
      .priorityGesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 2 })
          .onActionStart((): void => {
            this.onPanStart();
          })
          .onActionUpdate((event: GestureEvent): void => {
            this.onPanUpdate(event.offsetX);
          })
          .onActionEnd((): void => {
            this.onPanEnd();
          })
          .onActionCancel((): void => {
            this.onPanEnd();
          })
      )
      .gesture(
        TapGesture()
          .onAction((event: GestureEvent): void => {
            if (event.fingerList.length > 0) {
              this.onTapLocalX(event.fingerList[0].localX);
            }
          })
      )
    }
    .width('100%')
  }
}
