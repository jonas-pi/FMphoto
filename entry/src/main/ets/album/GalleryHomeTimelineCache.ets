/**
 * 图库主时间线内存快照：切换底部 Tab 离开相册再返回时复用，避免每次重拉时间轴与已加载列表。
 * - 保存时机：GalleryAlbumTab 即将卸载（用户切到其他 Tab）。
 * - 失效：全量 bootstrap（含下拉刷新）、GalleryTimelineRefreshStore.bump（上传/预览删除等）、baseUrl/token 变化。
 */
import { GalleryListItem } from '../model/FnApiTypes';
import { AppSession } from '../auth/AppSession';

/** 与 GalleryAlbumTab 内 TimelineDayModel 字段一致，便于序列化 */
export interface GalleryHomeDayPlain {
  year: number;
  month: number;
  day: number;
  itemCount: number;
}

export interface GalleryHomeSectionPlain {
  year: number;
  month: number;
  day: number;
  itemCount: number;
  nextOffset: number;
  /** 稀疏槽位：与 slotItems 等长，表示该照片在当日内的 offset */
  slotOffsets?: number[];
  slotItems?: GalleryListItem[];
  /** 旧版快照：连续 items（offset 0..len-1），仅用于兼容恢复 */
  items?: GalleryListItem[];
}

/** Map<string, number> 序列化为平行数组（快照用）；禁止内联 { keys; vals } 作类型以满足 arkts-no-obj-literals-as-types */
export interface GalleryHomeStringNumMapArrays {
  keys: string[];
  vals: number[];
}

export interface GalleryHomeTimelineSnapshot {
  orderedDays: GalleryHomeDayPlain[];
  sections: GalleryHomeSectionPlain[];
  dayOffsetsKeys: string[];
  dayOffsetsVals: number[];
  dayRoundsKeys: string[];
  dayRoundsVals: number[];
  dayEmptyKeys: string[];
  dayEmptyVals: number[];
  dayIndex: number;
  exhausted: boolean;
  footText: string;
  /** 与保存时 GalleryTimelineRefreshStore.version 一致；恢复前必须仍相等，否则视为需网络刷新 */
  refreshVersionAtSave: number;
}

export class GalleryHomeTimelineCache {
  private static snap: GalleryHomeTimelineSnapshot | null = null;
  private static baseUrlNorm: string = '';
  private static tokenSnapshot: string = '';
  private static ready: boolean = false;

  /** bump、即将全量 bootstrap 时调用，丢弃快照 */
  static invalidate(): void {
    GalleryHomeTimelineCache.ready = false;
    GalleryHomeTimelineCache.snap = null;
    GalleryHomeTimelineCache.baseUrlNorm = '';
    GalleryHomeTimelineCache.tokenSnapshot = '';
  }

  /**
   * @param baseUrl 当前 NAS 根地址（与 Tab 传入一致）
   * @param timelineRefreshVersion 当前全局刷新版本，须与快照内 refreshVersionAtSave 一致
   */
  static tryTakeRestore(baseUrl: string, timelineRefreshVersion: number): GalleryHomeTimelineSnapshot | null {
    if (!GalleryHomeTimelineCache.ready || GalleryHomeTimelineCache.snap === null) {
      return null;
    }
    const st = AppSession.getStored();
    if (st === null) {
      GalleryHomeTimelineCache.invalidate();
      return null;
    }
    const bu = baseUrl.trim();
    if (bu !== GalleryHomeTimelineCache.baseUrlNorm || st.token !== GalleryHomeTimelineCache.tokenSnapshot) {
      GalleryHomeTimelineCache.invalidate();
      return null;
    }
    const s = GalleryHomeTimelineCache.snap;
    if (s.refreshVersionAtSave !== timelineRefreshVersion) {
      return null;
    }
    return s;
  }

  static save(baseUrl: string, data: GalleryHomeTimelineSnapshot): void {
    const st = AppSession.getStored();
    if (st === null) {
      return;
    }
    GalleryHomeTimelineCache.baseUrlNorm = baseUrl.trim();
    GalleryHomeTimelineCache.tokenSnapshot = st.token;
    GalleryHomeTimelineCache.snap = data;
    GalleryHomeTimelineCache.ready = true;
  }
}
