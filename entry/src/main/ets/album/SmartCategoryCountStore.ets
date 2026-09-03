/**
 * 智能分类封面计数：与点进分类后的 magic-search 条数对齐。
 * 静态缓存跨页面实例，避免返回列表后又被接口 itemCount 盖掉。
 */
export class SmartCategoryCountStore {
  static version: number = 0;
  private static byName: Map<string, number> = new Map<string, number>();

  static put(name: string, count: number): number {
    const key = name.trim();
    const n = Math.max(0, Math.floor(count));
    if (key.length === 0) {
      return SmartCategoryCountStore.version;
    }
    const prev = SmartCategoryCountStore.byName.get(key);
    if (prev === n) {
      return SmartCategoryCountStore.version;
    }
    SmartCategoryCountStore.byName.set(key, n);
    SmartCategoryCountStore.version++;
    return SmartCategoryCountStore.version;
  }

  static get(name: string): number {
    const value = SmartCategoryCountStore.byName.get(name.trim());
    if (value === undefined) {
      return -1;
    }
    return value;
  }
}
