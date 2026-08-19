import { AttributeUpdater } from '@kit.ArkUI';

/** 跟手范围要明显大于切级阈值，否则捏合刚过阈值视觉就顶死，像只动了一点。 */
const PINCH_SCALE_MIN: number = 0.55;
const PINCH_SCALE_MAX: number = 1.55;
/** 小于该差值不写渲染属性，避免双指微抖反复改 transform。 */
const PINCH_SCALE_APPLY_EPSILON: number = 0.003;

/**
 * 捏合跟手缩放走 AttributeUpdater 直通渲染层，不经过 @State。
 * 官方：高频手势属性用 AttributeUpdater；组件刷新时 onComponentChanged 必须把当前值写回去，
 * 不能复位成 1，否则父组件任意 @Prop 刷新都会把跟手缩放掐断。
 */
export class GalleryPinchScaleUpdater extends AttributeUpdater<ListAttribute> {
  private lastScale: number = 1;
  private lastCenterX: number = 0;
  private lastCenterY: number = 0;

  initializeModifier(instance: ListAttribute): void {
    this.writeScale(instance, this.lastScale, this.lastCenterX, this.lastCenterY);
  }

  onComponentChanged(component: ListAttribute): void {
    this.writeScale(component, this.lastScale, this.lastCenterX, this.lastCenterY);
  }

  applyScale(scale: number, centerX: number, centerY: number): void {
    let next = scale;
    if (next < PINCH_SCALE_MIN) {
      next = PINCH_SCALE_MIN;
    } else if (next > PINCH_SCALE_MAX) {
      next = PINCH_SCALE_MAX;
    }
    const centerUnchanged = Math.abs(centerX - this.lastCenterX) < 0.5 &&
      Math.abs(centerY - this.lastCenterY) < 0.5;
    if (Math.abs(next - this.lastScale) < PINCH_SCALE_APPLY_EPSILON && centerUnchanged) {
      return;
    }
    this.lastScale = next;
    this.lastCenterX = centerX;
    this.lastCenterY = centerY;
    if (this.attribute !== undefined) {
      this.writeScale(this.attribute, next, centerX, centerY);
    }
  }

  resetScale(): void {
    this.lastScale = 1;
    this.lastCenterX = 0;
    this.lastCenterY = 0;
    if (this.attribute !== undefined) {
      this.writeScale(this.attribute, 1, 0, 0);
    }
  }

  private writeScale(target: ListAttribute, scale: number, centerX: number, centerY: number): void {
    target.scale({ x: scale, y: scale, centerX: centerX, centerY: centerY });
  }
}
