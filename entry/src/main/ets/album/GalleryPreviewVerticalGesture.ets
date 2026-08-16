import { AnimatorResult, AttributeUpdater } from '@kit.ArkUI';

/**
 * 预览页纵向手势：未放大时下滑跟手退出、上滑打开官方 bindSheet 详情。
 *
 * 半模态展开后，媒体限制在剩余区域内（上下对称裁剪），并上移使画面中心落在剩余区中心。
 * 跟手走 AttributeUpdater，不写 @State，避免每帧重建 Swiper。
 *
 * 文档：
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-sheet-page
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-sheet-transition
 * https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-picture-preview
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-explicit-animation
 */

/** 未放大时纵向识别距离，避免微移抢走单击 */
export const GALLERY_VERTICAL_PAN_DISTANCE: number = 8;
/** 官方 bindSheet 档位速度阈值 */
export const GALLERY_VERTICAL_VELOCITY_THRESHOLD: number = 1000;
/** 下滑超过屏高该比例则退出 */
export const GALLERY_DISMISS_DISTANCE_RATIO: number = 0.22;
/** 上滑打开详情的位移阈值（vp） */
export const GALLERY_DETAILS_DISTANCE_VP: number = 72;
/** 下滑跟手时最小缩放，接近系统图库收起 */
export const GALLERY_DISMISS_SCALE_MIN: number = 0.86;
/** 上滑预览详情时照片跟手增益，避免先把画面拖出太多 */
export const GALLERY_DETAILS_DRAG_GAIN: number = 0.28;
/** 左亮度 / 右音量热区宽度占屏比 */
export const VIDEO_SIDE_ADJUST_WIDTH_RATIO: number = 0.28;
/** 上下各留出一段，避免抢占上滑详情 / 下滑退出 */
export const VIDEO_SIDE_ADJUST_VERTICAL_INSET_RATIO: number = 0.20;
/**
 * createAnimator 不支持 spring-motion / responsive-spring-motion（非法曲线会回退 ease）。
 * 按官方默认弹簧换算 interpolating-spring(velocity, mass, stiffness, damping)：
 * stiffness = (2π / response)^2，damping = 4π * dampingFraction / response。
 * 文档：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-animator
 */
export const GALLERY_SHEET_ANIMATOR_EASING: string = 'interpolating-spring(0, 1, 130.4, 18.85)';
/** 对应 responsive-spring-motion(0.347, 0.99) */
export const GALLERY_VERTICAL_ANIMATOR_EASING: string = 'interpolating-spring(0, 1, 327.8, 35.85)';
export const GALLERY_ANIMATOR_FRAME_RATE: ExpectedFrameRateRange = { min: 0, max: 120, expected: 120 };
/** 官方 SheetSize.MEDIUM：半模态父窗口高度的 60% */
export const GALLERY_SHEET_MEDIUM_RATIO: number = 0.6;

let dismissProgress: number = 0;
const dismissListeners: Array<(progress: number) => void> = [];

export function getGalleryPreviewDismissProgress(): number {
  return dismissProgress;
}

export function setGalleryPreviewDismissProgress(progress: number): void {
  const p = Math.max(0, Math.min(1, progress));
  if (Math.abs(p - dismissProgress) < 0.008) {
    return;
  }
  dismissProgress = p;
  const copy = dismissListeners.slice();
  for (let i = 0; i < copy.length; i++) {
    copy[i](p);
  }
}

export function addGalleryPreviewDismissListener(cb: (progress: number) => void): void {
  dismissListeners.push(cb);
}

export function removeGalleryPreviewDismissListener(cb: (progress: number) => void): void {
  const idx = dismissListeners.indexOf(cb);
  if (idx >= 0) {
    dismissListeners.splice(idx, 1);
  }
}

/** finish() 会额外打一帧终点值；中途打断时先清空回调，避免跳变。 */
export function quietFinishAnimator(animator: AnimatorResult | undefined): void {
  if (animator === undefined) {
    return;
  }
  animator.onFrame = (_value: number): void => {
  };
  animator.onFinish = (): void => {
  };
  try {
    animator.finish();
  } catch (_e) {
  }
}

export function galleryDetailsMediumHeightVp(viewportH: number): number {
  if (viewportH <= 1) {
    return 0;
  }
  return viewportH * GALLERY_SHEET_MEDIUM_RATIO;
}

export class GalleryDetailsFit {
  scale: number = 1;
  translateY: number = 0;
  /** 剩余区域高度；0 表示铺满视口、不裁切 */
  clipHeight: number = 0;
}

/**
 * 半模态让位：媒体中心对齐剩余区中心，超出部分上下对称裁剪。
 * translateY = -sheetH / 2，使画面中心从视口中心落到剩余区中心。
 */
export function galleryDetailsFit(
  sheetHeightVp: number,
  _viewportW: number,
  viewportH: number,
  _contentAspect: number
): GalleryDetailsFit {
  const out = new GalleryDetailsFit();
  if (viewportH <= 1 || sheetHeightVp <= 0) {
    return out;
  }
  const remainingH = Math.max(1, viewportH - sheetHeightVp);
  out.clipHeight = remainingH;
  out.translateY = -sheetHeightVp / 2;
  return out;
}

let detailsSheetHeightVp: number = 0;
const detailsFitListeners: Array<() => void> = [];

export function getGalleryPreviewDetailsSheetHeight(): number {
  return detailsSheetHeightVp;
}

export function setGalleryPreviewDetailsSheetHeight(heightVp: number): void {
  const next = Math.max(0, heightVp);
  if (Math.abs(next - detailsSheetHeightVp) < 0.2) {
    return;
  }
  detailsSheetHeightVp = next;
  const copy = detailsFitListeners.slice();
  for (let i = 0; i < copy.length; i++) {
    copy[i]();
  }
}

export function addGalleryPreviewDetailsFitListener(cb: () => void): void {
  detailsFitListeners.push(cb);
}

export function removeGalleryPreviewDetailsFitListener(cb: () => void): void {
  const idx = detailsFitListeners.indexOf(cb);
  if (idx >= 0) {
    detailsFitListeners.splice(idx, 1);
  }
}

export function resetGalleryPreviewDetailsFit(): void {
  detailsSheetHeightVp = 0;
  detailsFitListeners.splice(0, detailsFitListeners.length);
}

/** 跟手 scale/translate 直通渲染层；裁切窗口单独走 ClipUpdater，避免和位移绑在同一节点上把裁切一起带走。 */
export class GalleryPreviewSlideTransformUpdater extends AttributeUpdater<StackAttribute> {
  private lastScale: number = 1;
  private lastY: number = 0;

  initializeModifier(instance: StackAttribute): void {
    instance.scale({ x: this.lastScale, y: this.lastScale, centerX: '50%', centerY: '50%' });
    instance.translate({ x: 0, y: this.lastY });
  }

  onComponentChanged(component: StackAttribute): void {
    component.scale({ x: this.lastScale, y: this.lastScale, centerX: '50%', centerY: '50%' });
    component.translate({ x: 0, y: this.lastY });
  }

  apply(scale: number, translateY: number): void {
    this.lastScale = scale;
    this.lastY = translateY;
    this.attribute?.scale({ x: scale, y: scale, centerX: '50%', centerY: '50%' });
    this.attribute?.translate({ x: 0, y: translateY });
  }

  reset(): void {
    this.apply(1, 0);
  }
}

/**
 * 视口裁切直通。保持布局高度 100%，只用 clipShape 限制在剩余区，
 * 这样媒体仍按全屏 Contain 居中，再配合上移即可上下等比例裁剪。
 */
export class GalleryPreviewClipUpdater extends AttributeUpdater<StackAttribute> {
  private lastClipH: number = 0;
  private lastFullH: number = 0;

  initializeModifier(instance: StackAttribute): void {
    this.write(instance);
  }

  onComponentChanged(component: StackAttribute): void {
    this.write(component);
  }

  apply(clipHeight: number, fullHeight: number): void {
    this.lastClipH = clipHeight;
    this.lastFullH = fullHeight;
    const attr = this.attribute;
    if (attr) {
      this.write(attr);
    }
  }

  reset(): void {
    this.apply(0, this.lastFullH);
  }

  private write(target: StackAttribute): void {
    const clipped = this.lastClipH > 1 && this.lastFullH > 1 && this.lastClipH < this.lastFullH - 0.5;
    if (clipped) {
      target.clipShape(new Rect({ width: '100%', height: this.lastClipH }));
      return;
    }
    target.clipShape(new Rect({ width: '100%', height: '100%' }));
  }
}

/** 遮罩 / 顶底栏透明度直通，避免每帧重建 HdsNavigation */
export class GalleryPreviewOpacityUpdater extends AttributeUpdater<CommonAttribute> {
  private lastOpacity: number = 1;

  initializeModifier(instance: CommonAttribute): void {
    instance.opacity(this.lastOpacity);
  }

  onComponentChanged(component: CommonAttribute): void {
    component.opacity(this.lastOpacity);
  }

  apply(opacity: number): void {
    const next = Math.max(0, Math.min(1, opacity));
    this.lastOpacity = next;
    // 绑定前 attribute 为 null，只记下目标值，等 initializeModifier 生效
    this.attribute?.opacity(next);
  }
}

export function galleryIsVideoBrightnessVolumeZone(
  localX: number,
  localY: number,
  viewW: number,
  viewH: number
): boolean {
  if (viewW <= 1 || viewH <= 1) {
    return false;
  }
  const edgeW = viewW * VIDEO_SIDE_ADJUST_WIDTH_RATIO;
  if (localX > edgeW && localX < viewW - edgeW) {
    return false;
  }
  const insetH = viewH * VIDEO_SIDE_ADJUST_VERTICAL_INSET_RATIO;
  return localY >= insetH && localY <= viewH - insetH;
}

export function galleryVerticalPanIsHorizontal(offsetX: number, offsetY: number): boolean {
  return Math.abs(offsetX) > Math.abs(offsetY);
}

export function galleryDismissProgress(offsetY: number, viewH: number): number {
  if (viewH <= 1 || offsetY <= 0) {
    return 0;
  }
  return Math.max(0, Math.min(1, offsetY / (viewH * 0.48)));
}

export function galleryDismissScale(progress: number): number {
  return 1 - progress * (1 - GALLERY_DISMISS_SCALE_MIN);
}

export function galleryShouldDismissPage(offsetY: number, velocityY: number, viewH: number): boolean {
  if (offsetY <= 0) {
    return false;
  }
  if (velocityY >= GALLERY_VERTICAL_VELOCITY_THRESHOLD) {
    return true;
  }
  return offsetY >= viewH * GALLERY_DISMISS_DISTANCE_RATIO;
}

export function galleryShouldOpenDetails(offsetY: number, velocityY: number): boolean {
  if (offsetY >= 0) {
    return false;
  }
  if (velocityY <= -GALLERY_VERTICAL_VELOCITY_THRESHOLD) {
    return true;
  }
  return -offsetY >= GALLERY_DETAILS_DISTANCE_VP;
}

export function galleryShouldCloseDetails(offsetY: number, velocityY: number): boolean {
  if (offsetY <= 0) {
    return false;
  }
  if (velocityY >= GALLERY_VERTICAL_VELOCITY_THRESHOLD) {
    return true;
  }
  return offsetY >= GALLERY_DETAILS_DISTANCE_VP;
}
