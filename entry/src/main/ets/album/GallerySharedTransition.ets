/**
 * 图库全屏预览「从哪来回哪去」共享元素转场。
 *
 * 官方能力：router 跨页使用 sharedTransition，id 相同且非空的组件在 push/back 时
 * 做位置与大小匹配（一镜到底）。官方示例源/目标页 pageTransition 均为
 * RouteType.None + duration 0，页面本身不做位移，完全由共享元素驱动。
 * 源页（Home 等）预览走 None + 延迟透明度淡出（背景等共享元素展开完再消失），
 * 其它路由保留滑入滑出。目标页仍为 None/0，遮罩单独延迟淡入。
 * 文档：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-transition-animation-shared-elements
 * 最佳实践：https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-one-shot-to-the-end
 */
export const GALLERY_PREVIEW_HERO_ACTIVE_KEY: string = 'galleryPreviewHeroActive';

/** 官方一镜到底示例多用 Friction；过短的 EaseInOut 容易在宽高跳变时显得卡、像逃逸 */
export const GALLERY_SHARED_TRANSITION_DURATION: number = 260;
export const GALLERY_SHARED_TRANSITION_CURVE: Curve = Curve.Friction;
/**
 * 官方自定义导航一镜到底：背景在共享元素到位后再淡入/淡出（delay 后再动透明度）。
 * 文档：开发指南「共享元素转场」自定义 Navigation 示例
 * 「页面由透明逐渐变为设置背景色」；返回时 delay 后再把背景收到 Transparent。
 * 源页 pageTransition 只做透明度、不做位移，避免与 sharedTransition 双重驱动位置。
 */
export const GALLERY_SCRIM_FADE_DURATION: number = 120;
export const GALLERY_SCRIM_FADE_DELAY: number = GALLERY_SHARED_TRANSITION_DURATION;
/** 转场 + 背景淡出结束后再关 hero 开关，避免源页 pageTransition 中途翻分支 */
const GALLERY_HERO_RESET_DELAY_MS: number =
  GALLERY_SCRIM_FADE_DELAY + GALLERY_SCRIM_FADE_DURATION + 80;

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
