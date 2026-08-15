/**
 * 图库多选「划选」共用：平铺索引 + 矩形缓存 + 预算化 DOM 命中。
 * CategoryGallery、回收站、主 Tab 搜索列表等同构逻辑集中于此，避免复制粘贴。
 */

/** 与 getRectangleById 窗口坐标一致的轴对齐矩形 */
export interface GallerySlideThumbRectPx {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

/** 每帧 getRectangleById 上限。划选跟手以矩形缓存为主，DOM 只作漏检兜底。 */
export const GALLERY_SLIDE_DOM_BUDGET_PER_FRAME = 4;
/** 以划选终点/锚点 flat 为中心的窗口半径 */
export const GALLERY_SLIDE_FLAT_RADIUS = 15;
/** 列表尾部兜底扫描的项数 */
export const GALLERY_SLIDE_TAIL_FLAT = 12;
/** 主时间线 WaterFlow：锚点所在行向上下扩展的行数 */
export const GALLERY_SLIDE_FLOW_ROW_RADIUS = 6;
/** 主时间线尾部兜底 row 数 */
export const GALLERY_SLIDE_TAIL_FLOW_ROWS = 8;

/** 划选进行中 Pan 更易触发 */
export const GALLERY_SLIDE_PAN_DISTANCE_VP_ACTIVE = 5;
/** 多选未划选时横向 Pan，略提高阈值减少误触 */
export const GALLERY_SLIDE_PAN_DISTANCE_VP_IDLE = 8;

export function gallerySlideRectContainsPx(
  rect: GallerySlideThumbRectPx,
  xPx: number,
  yPx: number
): boolean {
  return xPx >= rect.left && xPx <= rect.right && yPx >= rect.top && yPx <= rect.bottom;
}

export function gallerySlideShiftRectsByYPx(
  bounds: Map<string, GallerySlideThumbRectPx>,
  dyPx: number
): void {
  if (!Number.isFinite(dyPx) || Math.abs(dyPx) < 0.5) {
    return;
  }
  bounds.forEach((rect: GallerySlideThumbRectPx): void => {
    rect.top += dyPx;
    rect.bottom += dyPx;
  });
}

/**
 * 划选 Pan 更新：先信缓存几何命中，再在 seed±半径内按预算 DOM。
 * 官方图库划选不在跟手路径上回查 getRectangleById。
 */
export function pickIndexedFlatForSlidePointer(
  xPx: number,
  yPx: number,
  flatCount: number,
  slideLastEndFlat: number,
  slideAnchorFlat: number,
  pickFromFullCache: (ax: number, ay: number) => number,
  getCachedRect: (flatIdx: number) => GallerySlideThumbRectPx | undefined,
  testDomContainsPoint: (flatIdx: number, ax: number, ay: number) => boolean,
  recordThumbAfterDomHit: (flatIdx: number) => void
): number {
  const fromCache = pickFromFullCache(xPx, yPx);
  if (fromCache >= 0) {
    return fromCache;
  }
  if (flatCount <= 0) {
    return -1;
  }
  const seed = slideLastEndFlat >= 0 ? slideLastEndFlat : slideAnchorFlat;
  let domBudget = GALLERY_SLIDE_DOM_BUDGET_PER_FRAME;
  if (seed >= 0 && seed < flatCount) {
    const lo = Math.max(0, seed - GALLERY_SLIDE_FLAT_RADIUS);
    const hi = Math.min(flatCount - 1, seed + GALLERY_SLIDE_FLAT_RADIUS);
    for (let fi = hi; fi >= lo; fi--) {
      const cached = getCachedRect(fi);
      if (cached !== undefined && gallerySlideRectContainsPx(cached, xPx, yPx)) {
        return fi;
      }
      if (domBudget <= 0) {
        continue;
      }
      domBudget--;
      if (testDomContainsPoint(fi, xPx, yPx)) {
        recordThumbAfterDomHit(fi);
        return fi;
      }
    }
  }
  return -1;
}
