/**
 * 相册列表懒加载数据源。
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
  /** 'row' 节点：本行包含的 1~3 个缩略图 */
  rowItems: GalleryListItem[] = [];
  /** 'row' 节点：每个缩略图在全量扁平列表中的索引（用于预览跳转） */
  rowFlatIndices: number[] = [];
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

  reloadAll(list: GalleryFlowNode[]): void {
    this.nodes = list;
    this.listeners.forEach((l: GalleryFlowDataChangeListener): void => {
      l.onDataReloaded();
    });
  }
}
