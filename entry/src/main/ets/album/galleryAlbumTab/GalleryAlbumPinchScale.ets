import { AttributeUpdater } from '@kit.ArkUI';

const PINCH_SCALE_MIN: number = 0.82;
const PINCH_SCALE_MAX: number = 1.18;

/**
 * 捏合跟手缩放走属性直通，不经过 @State，避免每帧重建宫格。
 * 系统图库同样是手势期只做渲染层 scale，松手后再改列数。
 */
export class GalleryPinchScaleUpdater extends AttributeUpdater<ListAttribute> {
  initializeModifier(instance: ListAttribute): void {
    instance.scale({ x: 1, y: 1 });
  }

  onComponentChanged(component: ListAttribute): void {
    component.scale({ x: 1, y: 1 });
  }

  applyScale(scale: number, centerX: number, centerY: number): void {
    let next = scale;
    if (next < PINCH_SCALE_MIN) {
      next = PINCH_SCALE_MIN;
    } else if (next > PINCH_SCALE_MAX) {
      next = PINCH_SCALE_MAX;
    }
    this.attribute?.scale({ x: next, y: next, centerX: centerX, centerY: centerY });
  }

  resetScale(): void {
    this.applyScale(1, 0, 0);
  }
}
