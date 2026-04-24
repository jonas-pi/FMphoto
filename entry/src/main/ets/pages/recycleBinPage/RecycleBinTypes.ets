export const RB_PAGE_LIMIT = 80;
export const RB_SAFETY_MAX_OFFSET = 50000;

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
