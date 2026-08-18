import { AnimatorResult, AttributeUpdater } from '@kit.ArkUI';

/**
 * 预览页纵向手势：未放大时下滑跟手退出、上滑打开官方 bindSheet 详情。
 *
 * 半模态是系统叠层，自身遮挡下层，不要 clipShape 裁出洞（会露出页面浅底）。
 * 避让只把画面中心平移到剩余区；跟手走 AttributeUpdater，不写 @State。
 *
 * 文档：
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-sheet-page
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-sheet-transition
 * https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-picture-preview
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs/faqs-arkui-1365
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
 * 官方：interpolatingSpring 是 0→1 阻尼弹簧，初速度要归一化（绝对速度/改变量），
 * 时长由物理参数决定。ζ<1 会过冲，createAnimator 采样超出 [begin,end] 就是「动画逃逸」。
 * 避让用临界阻尼 ζ=1，周期仍对齐 bindSheet 的 0.347。
 * 文档：arkts-spring-curve、arkts-animation-smoothing、faqs-arkui-1365
 */
export const GALLERY_SHEET_SPRING_STIFFNESS: number = 327.8;
/** 4π * 1.0 / 0.347，临界阻尼，避免过冲把画面推出剩余区 */
export const GALLERY_SHEET_SPRING_DAMPING: number = 36.21;
/** 对应 responsive-spring-motion(0.347, 0.99)，用于下滑跟手松手回弹 */
export const GALLERY_VERTICAL_ANIMATOR_EASING: string = 'interpolating-spring(0, 1, 327.8, 35.85)';
export const GALLERY_ANIMATOR_FRAME_RATE: ExpectedFrameRateRange = { min: 0, max: 120, expected: 120 };

/** 弹出避让由 Slide 走 animateTo，true 时跟手高度不要再写 */
let detailsAvoidAnimating: boolean = false;
/** interpolatingSpring 归一化初速度，供避让属性动画继承跟手速度 */
let detailsFitNormVel: number = 0;

export function setGalleryPreviewDetailsAvoidAnimating(animating: boolean): void {
  detailsAvoidAnimating = animating;
}

export function isGalleryPreviewDetailsAvoidAnimating(): boolean {
  return detailsAvoidAnimating;
}

export function setGalleryPreviewDetailsFitNormVel(normalizedVelocity: number): void {
  let v = normalizedVelocity;
  if (v > 2.5) {
    v = 2.5;
  } else if (v < -0.5) {
    v = -0.5;
  }
  detailsFitNormVel = v;
}

export function getGalleryPreviewDetailsFitNormVel(): number {
  return detailsFitNormVel;
}

/** 松手时半模态高度方向的速度（vp/s），供避让弹簧继承，避免从 0 急刹停顿 */
let detailsAvoidVelocityVpPerSec: number = 0;

export function setGalleryPreviewDetailsAvoidVelocity(vpPerSec: number): void {
  detailsAvoidVelocityVpPerSec = vpPerSec;
}

export function takeGalleryPreviewDetailsAvoidVelocity(): number {
  const v = detailsAvoidVelocityVpPerSec;
  detailsAvoidVelocityVpPerSec = 0;
  return v;
}

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
    animator.cancel();
  } catch (_e) {
  }
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

/** 跟手向上位移换算成半模态高度，使松手后避让动画从当前画面接着播 */
export function gallerySheetHeightFromAvoidY(translateY: number): number {
  if (translateY >= -0.5) {
    return 0;
  }
  return -translateY * 2;
}

export class GalleryDetailsFit {
  scale: number = 1;
  translateY: number = 0;
}

/**
 * 半模态让位：画面中心对齐剩余区中心（translateY = -半模态高 / 2）。
 * 官方 bindSheet 本身盖住下层，不裁切；FAQ 改的是 Video 布局高度，
 * 这里 Swiper 子项写死 height 100%，改高度不生效，只平移让系统半模态遮挡下半。
 * 文档：faqs-arkui-1365、ts-universal-attributes-sheet-transition
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
  const usedH = Math.min(sheetHeightVp, viewportH - 1);
  out.translateY = -usedH / 2;
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
  detailsAvoidVelocityVpPerSec = 0;
  detailsFitNormVel = 0;
  detailsAvoidAnimating = false;
  detailsFitListeners.splice(0, detailsFitListeners.length);
}

/** 跟手 scale/translate 直通渲染层；弹出避让改走 animateTo，不裁切。 */
export class GalleryPreviewSlideTransformUpdater extends AttributeUpdater<StackAttribute> {
  private lastScale: number = 1;
  private lastY: number = 0;
  /** 属性动画占用 translate 时不再直通，避免和 animateTo 抢同一属性 */
  private translateLocked: boolean = false;

  lockTranslate(locked: boolean): void {
    this.translateLocked = locked;
  }

  getTranslateY(): number {
    return this.lastY;
  }

  initializeModifier(instance: StackAttribute): void {
    instance.scale({ x: this.lastScale, y: this.lastScale, centerX: '50%', centerY: '50%' });
    if (!this.translateLocked) {
      instance.translate({ x: 0, y: this.lastY });
    }
  }

  onComponentChanged(component: StackAttribute): void {
    component.scale({ x: this.lastScale, y: this.lastScale, centerX: '50%', centerY: '50%' });
    if (!this.translateLocked) {
      component.translate({ x: 0, y: this.lastY });
    }
  }

  apply(scale: number, translateY: number): void {
    this.lastScale = scale;
    if (!this.translateLocked) {
      this.lastY = translateY;
    }
    this.attribute?.scale({ x: scale, y: scale, centerX: '50%', centerY: '50%' });
    if (!this.translateLocked) {
      this.attribute?.translate({ x: 0, y: this.lastY });
    }
  }

  reset(): void {
    this.translateLocked = false;
    this.apply(1, 0);
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
