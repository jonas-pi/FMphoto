/**
 * 相册列表懒加载数据源。
 *
 * 与 List/LazyForEach 配合：reloadAll / notifyDataReload 会通知已注册的 DataChangeListener（框架挂载 LazyForEach 时注册）。
 * flush、全量替换后可再调一次 notifyDataReload 做二次脉冲，缓解部分机型子树延迟刷新。
 * 若仅内存替换节点字段而 LazyForEach 的 **item key 不变**，部分场景下子项仍可能不刷新，
 * 故 GalleryAlbumTab 对 row 使用带槽位签名的 key（galleryFlowLazyKey）。
 *
 * 节点类型：
 *   month — 年月大标题（全行）
 *   day   — 日期小标题（全行）
 *   row   — 最多 3 项缩略图构成的一行（便于全行节点直接由 List 渲染，无需 WaterFlow 的跨列能力）
 */
import { GalleryListItem } from '../model/FnApiTypes';

export class GalleryFlowNode {
  kind: 'month' | 'day' | 'row' = 'row';
  key: string = '';
  year: number = 0;
  month: number = 0;
  day: number = 0;
  /**
   * 'row' 节点：每槽 1~3 个，与 rowSlotFlatIndices 等长。
   * null 表示该槽仍为骨架（timeline 已知 itemCount 但尚未加载到该 offset）。
   */
  rowSlotItems: (GalleryListItem | null)[] = [];
  /** 与 rowSlotItems 对齐：已加载槽为 flatItems 下标；骨架槽为 -1 */
  rowSlotFlatIndices: number[] = [];
}

interface GalleryFlowDataChangeListener {
  onDataReloaded(): void;
}

export class GalleryWaterFlowDataSource {
  private nodes: GalleryFlowNode[] = [];
  private listeners: GalleryFlowDataChangeListener[] = [];

  totalCount(): number {
    return this.nodes.length;
  }

  getData(index: number): GalleryFlowNode {
    return this.nodes[index];
  }

  registerDataChangeListener(listener: GalleryFlowDataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: GalleryFlowDataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }

  /** 与 IDataSource / LazyForEach 约定一致：显式通知全量重载（reloadAll 末尾也会调用） */
  notifyDataReload(): void {
    this.listeners.forEach((l: GalleryFlowDataChangeListener): void => {
      l.onDataReloaded();
    });
  }

  reloadAll(list: GalleryFlowNode[]): void {
    this.nodes = list;
    this.notifyDataReload();
  }
}
