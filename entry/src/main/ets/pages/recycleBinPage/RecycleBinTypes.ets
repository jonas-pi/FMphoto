export const RB_PAGE_LIMIT = 80;
export const RB_SAFETY_MAX_OFFSET = 50000;

/** 彻底删除每批提交的 id 上限：请求体小，失败时也容易定位到具体批次。 */
export const RB_DELETE_BATCH_SIZE = 100;
/** delete 返回只表示任务已受理，轮询列表确认真正删掉的间隔与总时长。 */
export const RB_DELETE_SETTLE_POLL_MS = 1500;
export const RB_DELETE_SETTLE_TIMEOUT_MS = 30000;

export interface RbThumbHitRect {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface RbFingerWindowPoint {
  x: number;
  y: number;
}

export interface RbFingerCoordCompat {
  windowX?: number;
  windowY?: number;
  globalX?: number;
  globalY?: number;
  screenX?: number;
  screenY?: number;
  displayX?: number;
  displayY?: number;
  x?: number;
  y?: number;
}

export function formatRecycleApiTime(d: Date): string {
  const y = d.getFullYear();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  const h = d.getHours();
  const mi = d.getMinutes();
  const s = d.getSeconds();
  const p2 = (n: number): string => n.toString().padStart(2, '0');
  return `${y}:${p2(m)}:${p2(day)} ${p2(h)}:${p2(mi)}:${p2(s)}`;
}
