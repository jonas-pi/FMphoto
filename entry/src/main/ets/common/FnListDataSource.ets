interface FnListDataChangeListener {
  onDataReloaded(): void;
}

export class FnListDataSource<T> {
  private items: T[] = [];
  private listeners: FnListDataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  registerDataChangeListener(listener: FnListDataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: FnListDataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  notifyDataReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  reloadAll(items: T[]): void {
    this.items = items;
    this.notifyDataReload();
  }
}
