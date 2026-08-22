import { GalleryListItem } from '../../model/FnApiTypes';

/**
 * LazyForEach 监听器与官方 DataChangeListener 对齐。
 * Swiper 追加数据必须走 onDataAdd，不能 onDataReloaded，否则会重建全部页并出现重复画面。
 */
export interface PreviewDataChangeListener {
  onDataReloaded(): void;
  onDataAdd?(index: number): void;
  onDataAdded?(index: number): void;
}

export class PreviewItemsDataSource {
  private items: GalleryListItem[] = [];
  private listeners: PreviewDataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): GalleryListItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: PreviewDataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: PreviewDataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }

  /**
   * 直接引用调用方数组，收藏等原地改写才能同步到 LazyForEach。
   * 因此 appendItems 会改同一份列表，页面侧禁止再 push 一遍。
   */
  reloadAll(list: GalleryListItem[]): void {
    this.items = list;
    this.listeners.forEach((listener): void => {
      listener.onDataReloaded();
    });
  }

  appendItems(list: GalleryListItem[]): void {
    if (list.length === 0) {
      return;
    }
    for (let i = 0; i < list.length; i++) {
      this.items.push(list[i]);
      this.notifyItemAdded(this.items.length - 1);
    }
  }

  private notifyItemAdded(index: number): void {
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      if (listener.onDataAdd !== undefined) {
        listener.onDataAdd(index);
      } else if (listener.onDataAdded !== undefined) {
        listener.onDataAdded(index);
      } else {
        listener.onDataReloaded();
      }
    }
  }
}
