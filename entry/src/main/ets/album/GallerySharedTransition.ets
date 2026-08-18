/**
 * 图库全屏预览「从哪来回哪去」共享元素转场。
 *
 * 官方能力：router 跨页使用 sharedTransition，id 相同且非空的组件在 push/back 时
 * 做位置与大小匹配（一镜到底）。官方示例源/目标页 pageTransition 均为
 * RouteType.None + duration 0，页面本身不做位移，完全由共享元素驱动。
 * 源页（Home 等）仍按 heroActive 分支：预览走 None/0，其它路由保留滑入滑出。
 * 文档：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-transition-animation-shared-elements
 * 最佳实践：https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-one-shot-to-the-end
 */
export const GALLERY_PREVIEW_HERO_ACTIVE_KEY: string = 'galleryPreviewHeroActive';

/** 与系统图库接近的展开/收回时长 */
export const GALLERY_SHARED_TRANSITION_DURATION: number = 220;
export const GALLERY_SHARED_TRANSITION_CURVE: Curve = Curve.EaseInOut;
/** 遮罩在共享元素快结束时再淡入/淡出，避免一开始滤掉网格 */
export const GALLERY_SCRIM_FADE_DURATION: number = 90;
export const GALLERY_SCRIM_FADE_DELAY: number = 110;
/** 转场结束后再关 hero 开关，避免源页 pageTransition 中途翻分支 */
const GALLERY_HERO_RESET_DELAY_MS: number = GALLERY_SHARED_TRANSITION_DURATION + 80;

AppStorage.setOrCreate(GALLERY_PREVIEW_HERO_ACTIVE_KEY, false);

/** 延迟复位代次：新会话 open 时自增，作废上一轮 setTimeout */
let galleryHeroResetGen: number = 0;

export function setGalleryPreviewHeroActive(active: boolean): void {
  if (active) {
    galleryHeroResetGen++;
  }
  AppStorage.setOrCreate(GALLERY_PREVIEW_HERO_ACTIVE_KEY, active);
}

/** 预览页销毁后延迟关闭 hero；带代次校验，避免连点时旧定时器打断新转场 */
export function scheduleGalleryPreviewHeroInactive(): void {
  const gen = ++galleryHeroResetGen;
  setTimeout((): void => {
    if (gen === galleryHeroResetGen) {
      AppStorage.setOrCreate(GALLERY_PREVIEW_HERO_ACTIVE_KEY, false);
    }
  }, GALLERY_HERO_RESET_DELAY_MS);
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
