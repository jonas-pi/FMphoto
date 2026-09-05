/**
 * 划选贴边自动滚。
 *
 * 手指按在列表上时，系统会停掉 fling / 惯性滚动，但 scrollTo / scrollToIndex
 * 带动画的滚动除外。DisplaySync + scrollBy 是每帧一次瞬时跳变，高刷机上会
 * 「一帧帧」卡。这里用 List 自己的 scrollTo 线性动画带滚，选区在 onDidScroll
 * 里跟手，不再在帧回调里滚动。
 */
import { UIContext } from '@kit.ArkUI';
import { GallerySlideThumbRectPx } from './GallerySlidePick';

export const GALLERY_SLIDE_AUTO_SCROLL_EDGE_VP: number = 64;

/**
 * 贴边进入 / 最外沿速度。
 *
 * 对齐系统相册划选体感，取值取自官方贴边滚默认值（vp 与 dp 同量纲）：
 * - Android AutoScrollHelper：下限 315 dp/s、上限 1575 dp/s
 * - ArkUI Scroller.scrollEdge 文档示例：700 vp/s
 * 上限取 1200，介于文档示例与 AutoScrollHelper 天花板之间，避免缩略图跟不上。
 */
const GALLERY_SLIDE_AUTO_SCROLL_MIN_VEL_VP_S: number = 315;
const GALLERY_SLIDE_AUTO_SCROLL_MAX_VEL_VP_S: number = 1200;
/** 单次 scrollTo 动画时长上限，结束后若仍贴边则在 Idle 里续一段。 */
const GALLERY_SLIDE_AUTO_SCROLL_DURATION_MS: number = 6000;
const GALLERY_SLIDE_AUTO_SCROLL_DURATION_MIN_MS: number = 400;
const GALLERY_SLIDE_AUTO_SCROLL_RETARGET_MIN_MS: number = 160;
const GALLERY_SLIDE_AUTO_SCROLL_RETARGET_VEL_VP_S: number = 48;
/** 滚动累计超过该位移再跟一次选区；速度提高后略加密，避免漏选。 */
const GALLERY_SLIDE_AUTO_SCROLL_FOLLOW_VP: number = 12;

export class GallerySlideAutoScrollSession {
  uiContext: UIContext | null = null;
  scroller: Scroller = new Scroller();
  listDomId: string = '';
  topInsetVp: number = 0;
  bottomInsetVp: number = 0;
  isActive: () => boolean = (): boolean => false;
  shiftHitBoundsY: (dyPx: number) => void = (_dyPx: number): void => {};
  followPointer: (xPx: number, yPx: number, cacheOnly: boolean) => void =
    (_xPx: number, _yPx: number, _cacheOnly: boolean): void => {};
}

let autoScrollSession: GallerySlideAutoScrollSession | null = null;
let autoScrollPointerX: number = 0;
let autoScrollPointerY: number = 0;
let autoScrollListRect: GallerySlideThumbRectPx | null = null;
let autoScrollRunning: boolean = false;
let lastScrollToVel: number = 0;
let lastScrollToAtMs: number = 0;
let autoScrollFollowAccumVp: number = 0;

function vpToPx(session: GallerySlideAutoScrollSession, value: number): number {
  const ui = session.uiContext;
  if (ui === null) {
    return value;
  }
  try {
    return ui.vp2px(value);
  } catch (_e) {
    return value;
  }
}

function readListRect(session: GallerySlideAutoScrollSession): GallerySlideThumbRectPx | null {
  if (session.listDomId.length === 0 || session.uiContext === null) {
    return null;
  }
  try {
    const info = session.uiContext.getComponentUtils().getRectangleById(session.listDomId);
    const left = info.windowOffset.x as number;
    const top = info.windowOffset.y as number;
    const width = info.size.width as number;
    const height = info.size.height as number;
    if (!Number.isFinite(left) || !Number.isFinite(top) ||
      !Number.isFinite(width) || !Number.isFinite(height) || width < 1 || height < 1) {
      return null;
    }
    return { left: left, top: top, right: left + width, bottom: top + height };
  } catch (_e) {
    return null;
  }
}

function cachedListRect(session: GallerySlideAutoScrollSession): GallerySlideThumbRectPx | null {
  if (autoScrollListRect !== null) {
    return autoScrollListRect;
  }
  autoScrollListRect = readListRect(session);
  return autoScrollListRect;
}

function easedVelocity(ratio: number): number {
  const t = Math.max(0, Math.min(1, ratio));
  const eased = t * t;
  return GALLERY_SLIDE_AUTO_SCROLL_MIN_VEL_VP_S +
    (GALLERY_SLIDE_AUTO_SCROLL_MAX_VEL_VP_S - GALLERY_SLIDE_AUTO_SCROLL_MIN_VEL_VP_S) * eased;
}

function isScrollerAtBottom(session: GallerySlideAutoScrollSession): boolean {
  try {
    return session.scroller.isAtEnd();
  } catch (_e) {
    return false;
  }
}

function readScrollerYOffset(session: GallerySlideAutoScrollSession): number {
  try {
    const yRaw = session.scroller.currentOffset().yOffset;
    return typeof yRaw === 'number' && Number.isFinite(yRaw) ? yRaw : 0;
  } catch (_e) {
    return 0;
  }
}

function isScrollerAtTop(session: GallerySlideAutoScrollSession): boolean {
  return readScrollerYOffset(session) <= 0.5;
}

function computeVelocityVpPerSec(
  session: GallerySlideAutoScrollSession,
  yPx: number,
  checkEdge: boolean
): number {
  if (!session.isActive()) {
    return 0;
  }
  const rect = cachedListRect(session);
  if (rect === null) {
    return 0;
  }
  const edgePx = Math.max(1, vpToPx(session, GALLERY_SLIDE_AUTO_SCROLL_EDGE_VP));
  const visibleTop = rect.top + vpToPx(session, session.topInsetVp);
  const visibleBottom = rect.bottom - vpToPx(session, session.bottomInsetVp);
  const bottomStart = visibleBottom - edgePx;
  if (yPx > bottomStart) {
    if (checkEdge && isScrollerAtBottom(session)) {
      return 0;
    }
    return easedVelocity((yPx - bottomStart) / edgePx);
  }
  const topEnd = visibleTop + edgePx;
  if (yPx < topEnd) {
    if (checkEdge && isScrollerAtTop(session)) {
      return 0;
    }
    return -easedVelocity((topEnd - yPx) / edgePx);
  }
  return 0;
}

function cancelAnimatedScroll(session: GallerySlideAutoScrollSession): void {
  try {
    session.scroller.scrollTo({
      xOffset: 0,
      yOffset: readScrollerYOffset(session),
      animation: false
    });
  } catch (_e) {
  }
}

function startAnimatedScroll(session: GallerySlideAutoScrollSession, velVpS: number): void {
  const currentY = readScrollerYOffset(session);
  let targetY = currentY + velVpS * (GALLERY_SLIDE_AUTO_SCROLL_DURATION_MS / 1000);
  if (targetY < 0) {
    targetY = 0;
  }
  const distance = Math.abs(targetY - currentY);
  if (distance < 0.5) {
    return;
  }
  const durationMs = Math.max(
    GALLERY_SLIDE_AUTO_SCROLL_DURATION_MIN_MS,
    Math.min(
      GALLERY_SLIDE_AUTO_SCROLL_DURATION_MS,
      Math.round(distance / Math.abs(velVpS) * 1000)
    )
  );
  try {
    session.scroller.scrollTo({
      xOffset: 0,
      yOffset: targetY,
      animation: { duration: durationMs, curve: Curve.Linear, canOverScroll: false }
    });
    lastScrollToVel = velVpS;
    lastScrollToAtMs = Date.now();
  } catch (_e) {
  }
}

function shouldRetargetScroll(velVpS: number): boolean {
  if (lastScrollToVel === 0) {
    return true;
  }
  if ((velVpS > 0) !== (lastScrollToVel > 0)) {
    return true;
  }
  if ((Date.now() - lastScrollToAtMs) < GALLERY_SLIDE_AUTO_SCROLL_RETARGET_MIN_MS) {
    return false;
  }
  return Math.abs(velVpS - lastScrollToVel) >= GALLERY_SLIDE_AUTO_SCROLL_RETARGET_VEL_VP_S;
}

function resetAutoScrollState(): void {
  autoScrollSession = null;
  autoScrollListRect = null;
  autoScrollRunning = false;
  lastScrollToVel = 0;
  lastScrollToAtMs = 0;
  autoScrollFollowAccumVp = 0;
}

export function gallerySlideAutoScrollIsRunning(): boolean {
  return autoScrollRunning;
}

/** 当前贴边自动滚的有符号速度：正数向列表尾部，负数向列表头部。 */
export function gallerySlideAutoScrollVelocityVpS(): number {
  return autoScrollRunning ? lastScrollToVel : 0;
}

/** 当前贴边滚方向：1 向后、-1 向前、0 未滚动。 */
export function gallerySlideAutoScrollDirection(): number {
  const velocity = gallerySlideAutoScrollVelocityVpS();
  if (velocity > 0) {
    return 1;
  }
  if (velocity < 0) {
    return -1;
  }
  return 0;
}

export function gallerySlideAutoScrollStop(): void {
  const session = autoScrollSession;
  resetAutoScrollState();
  if (session !== null) {
    cancelAnimatedScroll(session);
  }
}

export function gallerySlideAutoScrollUpdate(
  session: GallerySlideAutoScrollSession,
  xPx: number,
  yPx: number
): void {
  autoScrollPointerX = xPx;
  autoScrollPointerY = yPx;
  const velocityVpS = computeVelocityVpPerSec(session, yPx, true);
  if (velocityVpS === 0) {
    if (autoScrollRunning) {
      gallerySlideAutoScrollStop();
    }
    return;
  }
  autoScrollSession = session;
  if (!autoScrollRunning) {
    autoScrollListRect = readListRect(session);
    autoScrollRunning = true;
    autoScrollFollowAccumVp = 0;
    startAnimatedScroll(session, velocityVpS);
    return;
  }
  if (shouldRetargetScroll(velocityVpS)) {
    startAnimatedScroll(session, velocityVpS);
  }
}

/**
 * 列表实际滚动时跟手。scrollTo 动画走 List 自己的 vsync，选区在这里更新，
 * 不要在 DisplaySync 回调里 scrollBy。
 */
export function gallerySlideAutoScrollOnListDidScroll(offset: number, scrollState: ScrollState): void {
  const session = autoScrollSession;
  if (!autoScrollRunning || session === null) {
    return;
  }
  if (!session.isActive()) {
    gallerySlideAutoScrollStop();
    return;
  }
  if (Number.isFinite(offset) && Math.abs(offset) >= 0.01) {
    autoScrollFollowAccumVp += Math.abs(offset);
  }
  if (autoScrollFollowAccumVp >= GALLERY_SLIDE_AUTO_SCROLL_FOLLOW_VP) {
    autoScrollFollowAccumVp = 0;
    session.followPointer(autoScrollPointerX, autoScrollPointerY, true);
  }
  if (scrollState === ScrollState.Idle && (Date.now() - lastScrollToAtMs) > 80) {
    const velocityVpS = computeVelocityVpPerSec(session, autoScrollPointerY, true);
    if (velocityVpS === 0) {
      gallerySlideAutoScrollStop();
      return;
    }
    startAnimatedScroll(session, velocityVpS);
  }
}
