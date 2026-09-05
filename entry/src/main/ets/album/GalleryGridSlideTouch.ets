import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 宫格多选的触摸 / 划选会话。
 *
 * 主时间线已验证的收尾：
 * - Down 用本地定时器进入多选（不依赖 Sequence 在重建后仍活着）
 * - 划选进行中必须在 Up/Cancel 解锁 List.scroll
 * - 已在多选后，长按不再改选中；横向 Pan 才划选
 *
 * 分类子页 / 回收站 / 搜索原先只靠 Sequence(LongPress→Pan)，
 * 首次进入多选会重建行节点，Pan 收不到 End/Cancel，滚动和点选一起锁死。
 * 各宫格页共用本模块，避免再复制出一套收尾。
 */

const GALLERY_GRID_SLIDE_LOG_DOMAIN: number = 0xFF00;
/**
 * 划选诊断统一 TAG。真机过滤：
 * hdc shell hilog | findstr GridSlide
 */
export const GALLERY_GRID_SLIDE_LOG_TAG: string = 'GridSlide';

export function galleryGridSlideLog(event: string, detail: string = ''): void {
  if (detail.length > 0) {
    hilog.info(GALLERY_GRID_SLIDE_LOG_DOMAIN, GALLERY_GRID_SLIDE_LOG_TAG,
      '%{public}s %{public}s', event, detail);
    return;
  }
  hilog.info(GALLERY_GRID_SLIDE_LOG_DOMAIN, GALLERY_GRID_SLIDE_LOG_TAG, '%{public}s', event);
}

function galleryGridTouchTypeName(type: TouchType): string {
  if (type === TouchType.Down) {
    return 'Down';
  }
  if (type === TouchType.Move) {
    return 'Move';
  }
  if (type === TouchType.Up) {
    return 'Up';
  }
  if (type === TouchType.Cancel) {
    return 'Cancel';
  }
  return `${type}`;
}

function galleryGridSlideSessionDetail(
  where: string,
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost
): string {
  return `${where} sel=${host.isSelectionMode() ? '1' : '0'} slide=${host.isSlideActive() ? '1' : '0'}` +
    ` down=${session.touchDownActive ? '1' : '0'} pendLp=${session.touchPendingLongPress ? '1' : '0'}` +
    ` drive=${session.touchSlideDriving ? '1' : '0'} init=${session.initialSlidePending ? '1' : '0'}` +
    ` pan2=${session.secondaryPanDriving ? '1' : '0'}`;
}

/** Sequence 长按识别时长，与主时间线 LongPressGesture 一致 */
export const GALLERY_GRID_SEQUENCE_LONG_PRESS_MS: number = 420;
/** 触摸兜底长按，略短于 Sequence，保证松手前已进入划选 */
export const GALLERY_GRID_TOUCH_LONG_PRESS_MS: number = 380;
/** 长按未完成时超过该位移则取消触摸长按，避免和滚动抢手 */
export const GALLERY_GRID_TOUCH_SLOP_VP: number = 10;

export class GalleryGridTouchPoint {
  x: number = 0;
  y: number = 0;
}

/**
 * 单页一份。不要放进 @State：跟手坐标不应触发整表刷新。
 */
export class GalleryGridSlideTouchSession {
  /** Sequence 长按已开始划选，等全向 Pan 跟手 */
  initialSlidePending: boolean = false;
  /** 触摸定时器路径在跟手，Row.onTouch Move 才驱动选区 */
  touchSlideDriving: boolean = false;
  /** 已在多选后的横向 Pan 正在划选 */
  secondaryPanDriving: boolean = false;
  touchDownActive: boolean = false;
  touchPendingLongPress: boolean = false;
  touchLongPressTimer: number = -1;
  touchStartX: number = 0;
  touchStartY: number = 0;
  touchLastX: number = 0;
  touchLastY: number = 0;
}

export interface GalleryGridSlideTouchHost {
  getUIContext(): UIContext;
  isSelectionMode(): boolean;
  isSlideActive(): boolean;
  endSlide(): void;
  followSlideAtWindowPx(xPx: number, yPx: number): void;
}

export function galleryGridReadTouchFingerWindow(
  ev: TouchEvent,
  host: GalleryGridSlideTouchHost
): GalleryGridTouchPoint | null {
  if (ev.touches === undefined || ev.touches.length < 1) {
    return null;
  }
  const f0 = ev.touches[0];
  const x = f0.windowX ?? f0.displayX ?? f0.x;
  const y = f0.windowY ?? f0.displayY ?? f0.y;
  if (x === undefined || y === undefined || !Number.isFinite(x) || !Number.isFinite(y)) {
    return null;
  }
  // TouchEvent 窗口坐标是 vp，命中框 getRectangleById 是 px；不换算就会 timer_miss
  try {
    return { x: host.getUIContext().vp2px(x), y: host.getUIContext().vp2px(y) };
  } catch (_e) {
    return { x, y };
  }
}

export function galleryGridClearInitialSlide(session: GalleryGridSlideTouchSession): void {
  session.initialSlidePending = false;
}

export function galleryGridArmInitialSlide(session: GalleryGridSlideTouchSession): void {
  session.touchSlideDriving = false;
  session.secondaryPanDriving = false;
  session.initialSlidePending = true;
}

export function galleryGridResetTouchTracking(session: GalleryGridSlideTouchSession): void {
  if (session.touchLongPressTimer >= 0) {
    try {
      clearTimeout(session.touchLongPressTimer);
    } catch (_e) {
    }
    session.touchLongPressTimer = -1;
  }
  session.touchDownActive = false;
  session.touchPendingLongPress = false;
  session.touchSlideDriving = false;
  session.secondaryPanDriving = false;
}

function galleryGridSlopPx(host: GalleryGridSlideTouchHost): number {
  try {
    return host.getUIContext().vp2px(GALLERY_GRID_TOUCH_SLOP_VP);
  } catch (_e) {
    return GALLERY_GRID_TOUCH_SLOP_VP;
  }
}

/**
 * @param pickAndBeginFirstSlide 未进多选时长按命中缩略图后：进入多选并按窗口坐标开始划选
 */
export function galleryGridStartTouchLongPress(
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost,
  pt: GalleryGridTouchPoint,
  pickAndBeginFirstSlide: (xPx: number, yPx: number) => boolean
): void {
  if (host.isSelectionMode() || host.isSlideActive()) {
    return;
  }
  galleryGridResetTouchTracking(session);
  session.touchDownActive = true;
  session.touchPendingLongPress = true;
  session.touchStartX = pt.x;
  session.touchStartY = pt.y;
  session.touchLastX = pt.x;
  session.touchLastY = pt.y;
  session.touchLongPressTimer = setTimeout((): void => {
    session.touchLongPressTimer = -1;
    if (!session.touchDownActive || !session.touchPendingLongPress ||
      host.isSelectionMode() || host.isSlideActive()) {
      return;
    }
    if (!pickAndBeginFirstSlide(session.touchLastX, session.touchLastY)) {
      session.touchPendingLongPress = false;
      galleryGridSlideLog('timer_miss',
        `${galleryGridSlideSessionDetail('lp', session, host)} xy=${Math.round(session.touchLastX)},${Math.round(session.touchLastY)}`);
      return;
    }
    session.touchSlideDriving = true;
    session.touchPendingLongPress = false;
    galleryGridSlideLog('timer_begin', galleryGridSlideSessionDetail('lp', session, host));
  }, GALLERY_GRID_TOUCH_LONG_PRESS_MS);
}

function galleryGridCancelPendingLongPressIfMoved(
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost,
  pt: GalleryGridTouchPoint
): void {
  session.touchLastX = pt.x;
  session.touchLastY = pt.y;
  const dx = pt.x - session.touchStartX;
  const dy = pt.y - session.touchStartY;
  const slopPx = galleryGridSlopPx(host);
  if ((dx * dx + dy * dy) > (slopPx * slopPx)) {
    galleryGridResetTouchTracking(session);
  }
}

/**
 * 上一轮划选没收到 Up 时，新的 Down 先解锁，避免 enableScrollInteraction(false) 残留。
 * 主时间线同一指不会在划选中再 Down，因此不会误打断正在跟手的划选。
 */
function galleryGridEndStaleSlideOnDown(
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost
): void {
  if (!host.isSlideActive()) {
    return;
  }
  galleryGridSlideLog('stale_down_end', galleryGridSlideSessionDetail('stale', session, host));
  galleryGridClearInitialSlide(session);
  host.endSlide();
  galleryGridResetTouchTracking(session);
}

/** 行级 onTouch：未多选时武装触摸长按；划选中必须在 Up/Cancel 解锁滚动 */
export function galleryGridHandleRowTouch(
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost,
  event: TouchEvent,
  pickAndBeginFirstSlide: (xPx: number, yPx: number) => boolean
): void {
  const touchPt = galleryGridReadTouchFingerWindow(event, host);
  if (event.type === TouchType.Down || event.type === TouchType.Up || event.type === TouchType.Cancel) {
    galleryGridSlideLog(
      `row_${galleryGridTouchTypeName(event.type)}`,
      galleryGridSlideSessionDetail('row', session, host)
    );
  }
  if (event.type === TouchType.Down) {
    galleryGridEndStaleSlideOnDown(session, host);
    if (touchPt !== null && !host.isSelectionMode()) {
      galleryGridStartTouchLongPress(session, host, touchPt, pickAndBeginFirstSlide);
    }
    return;
  }
  if (!host.isSlideActive()) {
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      galleryGridClearInitialSlide(session);
      galleryGridResetTouchTracking(session);
      return;
    }
    if (session.touchPendingLongPress && touchPt !== null && event.type === TouchType.Move) {
      galleryGridCancelPendingLongPressIfMoved(session, host, touchPt);
    }
    return;
  }
  if (event.type === TouchType.Move) {
    if (touchPt !== null && session.touchSlideDriving) {
      host.followSlideAtWindowPx(touchPt.x, touchPt.y);
    }
    return;
  }
  if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
    galleryGridClearInitialSlide(session);
    host.endSlide();
    galleryGridResetTouchTracking(session);
  }
}

/** 列表级 onTouch：Sequence 被重建吃掉 End 时，仍能靠这里的 Up/Cancel 解锁 */
export function galleryGridHandleListTouch(
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost,
  event: TouchEvent
): void {
  const pt = galleryGridReadTouchFingerWindow(event, host);
  if (event.type === TouchType.Down || event.type === TouchType.Up || event.type === TouchType.Cancel) {
    galleryGridSlideLog(
      `list_${galleryGridTouchTypeName(event.type)}`,
      galleryGridSlideSessionDetail('list', session, host)
    );
  }
  if (event.type === TouchType.Down) {
    galleryGridEndStaleSlideOnDown(session, host);
    return;
  }
  if (host.isSlideActive()) {
    if (event.type === TouchType.Move) {
      // 行节点被多选刷新拆掉时，List 仍能收到 Move；Sequence Pan 未接上也能跟手
      if (pt !== null && (session.touchSlideDriving || session.initialSlidePending)) {
        host.followSlideAtWindowPx(pt.x, pt.y);
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      galleryGridClearInitialSlide(session);
      host.endSlide();
      galleryGridResetTouchTracking(session);
    }
    return;
  }
  if (session.touchPendingLongPress && pt !== null && event.type === TouchType.Move) {
    galleryGridCancelPendingLongPressIfMoved(session, host, pt);
    return;
  }
  if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
    galleryGridClearInitialSlide(session);
    galleryGridResetTouchTracking(session);
  }
}

/**
 * Sequence LongPress 是否还要自己 begin。
 * 触摸定时器通常更早进入划选；此时 LongPress 仍会成功并进入后续 Pan。
 * 必须把 initialSlidePending 接上，否则 Pan 吞位移、选区不更新，表现为划不动。
 * @returns true：调用方继续 begin+arm；false：已交接或应忽略
 */
export function galleryGridOnSequenceLongPress(
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost
): boolean {
  if (host.isSlideActive()) {
    galleryGridArmInitialSlide(session);
    galleryGridSlideLog('seq_lp_handoff', galleryGridSlideSessionDetail('seq', session, host));
    return false;
  }
  if (host.isSelectionMode()) {
    return false;
  }
  return true;
}

export function galleryGridShouldUpdateSequencePan(
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost
): boolean {
  return session.initialSlidePending && host.isSlideActive();
}

export function galleryGridOnSequencePanFinish(
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost
): void {
  galleryGridClearInitialSlide(session);
  galleryGridSlideLog('seq_pan_end', galleryGridSlideSessionDetail('seq', session, host));
  host.endSlide();
}

export function galleryGridCanStartSecondaryPan(
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost,
  ev: GestureEvent
): boolean {
  if (!host.isSelectionMode() || host.isSlideActive() || session.initialSlidePending) {
    return false;
  }
  // 主时间线：左滑不划选，避免和系统返回手势抢
  if (Number.isFinite(ev.offsetX) && ev.offsetX < 0) {
    return false;
  }
  return true;
}

export function galleryGridOnSecondaryPanStart(session: GalleryGridSlideTouchSession): void {
  session.touchSlideDriving = false;
  session.secondaryPanDriving = true;
  galleryGridSlideLog('sec_pan_start', `init=${session.initialSlidePending ? '1' : '0'}`);
}

export function galleryGridShouldUpdateSecondaryPan(
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost
): boolean {
  return session.secondaryPanDriving && host.isSelectionMode() &&
    !session.initialSlidePending && host.isSlideActive();
}

export function galleryGridOnSecondaryPanFinish(
  session: GalleryGridSlideTouchSession,
  host: GalleryGridSlideTouchHost
): void {
  if (session.secondaryPanDriving && !session.initialSlidePending && host.isSlideActive()) {
    galleryGridSlideLog('sec_pan_end', galleryGridSlideSessionDetail('sec', session, host));
    host.endSlide();
  }
  session.secondaryPanDriving = false;
}
