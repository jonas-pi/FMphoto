import { GalleryListItem } from '../../model/FnApiTypes';

export interface PreviewDataChangeListener {
  onDataReloaded(): void;
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

  reloadAll(list: GalleryListItem[]): void {
    this.items = list;
    this.listeners.forEach((listener): void => {
      listener.onDataReloaded();
    });
  }
}
