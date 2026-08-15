/**
 * 划选贴边自动滚：与系统图库一致，DisplaySync 对齐 vsync，scrollBy 无动画相对位移。
 * 主时间线、搜索、分类子页、回收站共用。
 */
import { UIContext } from '@kit.ArkUI';
import { displaySync } from '@kit.ArkGraphics2D';
import { GallerySlideThumbRectPx } from './GallerySlidePick';

export const GALLERY_SLIDE_AUTO_SCROLL_EDGE_VP: number = 64;

const GALLERY_SLIDE_AUTO_SCROLL_MIN_VEL_VP_S: number = 140;
const GALLERY_SLIDE_AUTO_SCROLL_MAX_VEL_VP_S: number = 520;
const GALLERY_SLIDE_AUTO_SCROLL_DT_MIN_S: number = 0.004;
const GALLERY_SLIDE_AUTO_SCROLL_DT_MAX_S: number = 0.032;
const GALLERY_SLIDE_AUTO_SCROLL_NS_PER_S: number = 1000000000;
const GALLERY_SLIDE_AUTO_SCROLL_FRAME_RATE: ExpectedFrameRateRange = { expected: 60, min: 30, max: 120 };

export class GallerySlideAutoScrollSession {
  uiContext: UIContext | null = null;
  scroller: Scroller = new Scroller();
  listDomId: string = '';
  topInsetVp: number = 0;
  bottomInsetVp: number = 0;
  isActive: () => boolean = (): boolean => false;
  shiftHitBoundsY: (dyPx: number) => void = (_dyPx: number): void => {};
  followPointer: (xPx: number, yPx: number) => void = (_xPx: number, _yPx: number): void => {};
}

let autoScrollSync: displaySync.DisplaySync | null = null;
let autoScrollSession: GallerySlideAutoScrollSession | null = null;
let autoScrollPointerX: number = 0;
let autoScrollPointerY: number = 0;
let autoScrollLastTsNs: number = 0;
let autoScrollListRect: GallerySlideThumbRectPx | null = null;
let autoScrollRunning: boolean = false;

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

function computeVelocityVpPerSec(session: GallerySlideAutoScrollSession, yPx: number): number {
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
    try {
      if (session.scroller.isAtEnd()) {
        return 0;
      }
    } catch (_e) {
    }
    return easedVelocity((yPx - bottomStart) / edgePx);
  }
  const topEnd = visibleTop + edgePx;
  if (yPx < topEnd) {
    try {
      const off = session.scroller.currentOffset();
      const yRaw = off.yOffset;
      const y = typeof yRaw === 'number' && Number.isFinite(yRaw) ? yRaw : 0;
      if (y <= 0.5) {
        return 0;
      }
    } catch (_e) {
    }
    return -easedVelocity((topEnd - yPx) / edgePx);
  }
  return 0;
}

function scrollByVp(session: GallerySlideAutoScrollSession, deltaVp: number): void {
  if (Math.abs(deltaVp) < 0.01) {
    return;
  }
  try {
    session.scroller.scrollBy(0, deltaVp);
    session.shiftHitBoundsY(-vpToPx(session, deltaVp));
  } catch (_e) {
  }
}

function onFrame(info: displaySync.IntervalInfo): void {
  const session = autoScrollSession;
  if (session === null || !session.isActive()) {
    gallerySlideAutoScrollStop();
    return;
  }
  const velocityVpS = computeVelocityVpPerSec(session, autoScrollPointerY);
  if (velocityVpS === 0) {
    gallerySlideAutoScrollStop();
    return;
  }
  let dtS = GALLERY_SLIDE_AUTO_SCROLL_DT_MAX_S;
  if (autoScrollLastTsNs > 0 && info.timestamp > autoScrollLastTsNs) {
    dtS = (info.timestamp - autoScrollLastTsNs) / GALLERY_SLIDE_AUTO_SCROLL_NS_PER_S;
  }
  autoScrollLastTsNs = info.timestamp;
  if (dtS < GALLERY_SLIDE_AUTO_SCROLL_DT_MIN_S) {
    dtS = GALLERY_SLIDE_AUTO_SCROLL_DT_MIN_S;
  } else if (dtS > GALLERY_SLIDE_AUTO_SCROLL_DT_MAX_S) {
    dtS = GALLERY_SLIDE_AUTO_SCROLL_DT_MAX_S;
  }
  scrollByVp(session, velocityVpS * dtS);
  session.followPointer(autoScrollPointerX, autoScrollPointerY);
}

function ensureSync(): displaySync.DisplaySync {
  if (autoScrollSync !== null) {
    return autoScrollSync;
  }
  const sync = displaySync.create();
  sync.setExpectedFrameRateRange(GALLERY_SLIDE_AUTO_SCROLL_FRAME_RATE);
  sync.on('frame', (info: displaySync.IntervalInfo): void => {
    onFrame(info);
  });
  autoScrollSync = sync;
  return sync;
}

export function gallerySlideAutoScrollStop(): void {
  autoScrollSession = null;
  autoScrollLastTsNs = 0;
  autoScrollListRect = null;
  autoScrollRunning = false;
  if (autoScrollSync !== null) {
    try {
      autoScrollSync.stop();
    } catch (_e) {
    }
  }
}

export function gallerySlideAutoScrollUpdate(
  session: GallerySlideAutoScrollSession,
  xPx: number,
  yPx: number
): void {
  autoScrollPointerX = xPx;
  autoScrollPointerY = yPx;
  const velocityVpS = computeVelocityVpPerSec(session, yPx);
  if (velocityVpS === 0) {
    if (autoScrollRunning) {
      gallerySlideAutoScrollStop();
    }
    return;
  }
  if (autoScrollRunning && autoScrollSession === session) {
    return;
  }
  autoScrollSession = session;
  autoScrollLastTsNs = 0;
  autoScrollListRect = readListRect(session);
  try {
    ensureSync().start();
    autoScrollRunning = true;
  } catch (_e) {
    autoScrollSession = null;
    autoScrollRunning = false;
  }
}
