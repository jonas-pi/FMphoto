/**
 * 图库全屏预览「从哪来回哪去」共享元素转场。
 *
 * 官方能力：router 跨页使用 Image.sharedTransition，id 相同的组件在 push/back 时
 * 做位置与大小匹配（一镜到底）。pageTransition 需 duration 0，避免页面位移动画抢戏。
 * 文档：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-transition-animation-shared-elements
 */
export const GALLERY_PREVIEW_HERO_ACTIVE_KEY: string = 'galleryPreviewHeroActive';

/** 与系统图库接近的展开/收回时长 */
export const GALLERY_SHARED_TRANSITION_DURATION: number = 320;
export const GALLERY_SHARED_TRANSITION_CURVE: Curve = Curve.EaseInOut;

AppStorage.setOrCreate(GALLERY_PREVIEW_HERO_ACTIVE_KEY, false);

export function setGalleryPreviewHeroActive(active: boolean): void {
  AppStorage.setOrCreate(GALLERY_PREVIEW_HERO_ACTIVE_KEY, active);
}

export function gallerySharedTransitionId(itemId: string): string {
  if (itemId.length === 0) {
    return '';
  }
  return `gp_share_${itemId}`;
}

export function gallerySharedTransitionOptions(): sharedTransitionOptions {
  return {
    duration: GALLERY_SHARED_TRANSITION_DURATION,
    curve: GALLERY_SHARED_TRANSITION_CURVE,
    zIndex: 100,
    type: SharedTransitionEffectType.Exchange
  };
}

export class GalleryHeroFrame {
  w: number = 0;
  h: number = 0;
}

/** PixelMap 宽高比；失败返回 0 */
export function galleryPixelAspect(pix: PixelMap | undefined): number {
  if (pix === undefined) {
    return 0;
  }
  try {
    const info = pix.getImageInfoSync();
    const w = info.size.width;
    const h = info.size.height;
    if (w > 0 && h > 0) {
      return w / h;
    }
  } catch (_e) {
  }
  return 0;
}

/**
 * 全屏预览默认尺寸：在视口内按 Contain 适配后的实际显示框（vp）。
 * 官方 geometryTransition 示例：转场绑在裁剪容器上，子图 100% 铺满；
 * 系统分别插值宽高与位置（80x80 → 300x400），收回时不是四边等比缩放。
 * 文档：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-transition-animation-geometrytransition
 */
export function galleryContainFrame(aspect: number, boxW: number, boxH: number): GalleryHeroFrame {
  const out = new GalleryHeroFrame();
  if (aspect <= 0 || boxW <= 0 || boxH <= 0) {
    return out;
  }
  const boxAspect = boxW / boxH;
  if (aspect >= boxAspect) {
    out.w = boxW;
    out.h = boxW / aspect;
  } else {
    out.h = boxH;
    out.w = boxH * aspect;
  }
  return out;
}
