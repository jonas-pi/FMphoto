/**
 * 智能分类封面计数缓存。
 * 与点进分类后的 magic-search 条数对齐，写入 Preferences，跨启动复用；
 * 点进某个分类时用当次结果覆盖对应条目。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { SmartCategoryItem } from '../model/FnApiTypes';
import { smartCategoryName } from './GalleryAlbumEntityData';
import { smartCategoryPatchCountByName } from './SmartCategoryLayoutPreferences';

const PREF_NAME: string = 'fnos_client_prefs';
const K_COUNT_JSON: string = 'smart_category_count_json';
const PERSIST_DEBOUNCE_MS: number = 360;

type LooseJson = Record<string, Object | string | number | boolean | undefined | null>;

export class SmartCategoryCountStore {
  static version: number = 0;
  private static byName: Map<string, number> = new Map<string, number>();
  private static loadedAccount: string = '';
  private static persistCtx: common.UIAbilityContext | undefined = undefined;
  private static persistAccount: string = '';
  private static persistTimer: number = -1;
  private static persistSeq: number = 0;

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
    SmartCategoryCountStore.schedulePersist();
    return SmartCategoryCountStore.version;
  }

  static get(name: string): number {
    const value = SmartCategoryCountStore.byName.get(name.trim());
    if (value === undefined) {
      return -1;
    }
    return value;
  }

  static has(name: string): boolean {
    return SmartCategoryCountStore.get(name) >= 0;
  }

  static applyToItems(items: SmartCategoryItem[]): SmartCategoryItem[] {
    let current = items;
    for (let i = 0; i < items.length; i++) {
      const name = smartCategoryName(items[i]);
      const cached = SmartCategoryCountStore.get(name);
      if (cached >= 0) {
        current = smartCategoryPatchCountByName(current, name, cached);
      }
    }
    return current;
  }

  static async ensureLoaded(
    ctx: common.UIAbilityContext | undefined,
    account: string
  ): Promise<void> {
    const acc = account.trim();
    if (ctx === undefined || acc.length === 0) {
      return;
    }
    SmartCategoryCountStore.persistCtx = ctx;
    SmartCategoryCountStore.persistAccount = acc;
    if (SmartCategoryCountStore.loadedAccount === acc) {
      return;
    }
    if (SmartCategoryCountStore.loadedAccount.length > 0) {
      SmartCategoryCountStore.byName.clear();
    }
    const map = await SmartCategoryCountStore.readDisk(ctx);
    const rows = map.get(acc);
    if (rows !== undefined) {
      rows.forEach((n: number, key: string): void => {
        if (n >= 0) {
          SmartCategoryCountStore.byName.set(key, n);
        }
      });
    }
    SmartCategoryCountStore.loadedAccount = acc;
    SmartCategoryCountStore.version++;
  }

  static async flush(): Promise<void> {
    SmartCategoryCountStore.clearPersistTimer();
    await SmartCategoryCountStore.saveNow();
  }

  private static schedulePersist(): void {
    if (SmartCategoryCountStore.persistCtx === undefined ||
      SmartCategoryCountStore.persistAccount.length === 0) {
      return;
    }
    SmartCategoryCountStore.clearPersistTimer();
    SmartCategoryCountStore.persistTimer = setTimeout((): void => {
      SmartCategoryCountStore.persistTimer = -1;
      void SmartCategoryCountStore.saveNow();
    }, PERSIST_DEBOUNCE_MS);
  }

  private static clearPersistTimer(): void {
    if (SmartCategoryCountStore.persistTimer >= 0) {
      clearTimeout(SmartCategoryCountStore.persistTimer);
      SmartCategoryCountStore.persistTimer = -1;
    }
  }

  private static async saveNow(): Promise<void> {
    const ctx = SmartCategoryCountStore.persistCtx;
    const acc = SmartCategoryCountStore.persistAccount;
    if (ctx === undefined || acc.length === 0) {
      return;
    }
    const seq = ++SmartCategoryCountStore.persistSeq;
    const p = await SmartCategoryCountStore.openPrefs(ctx);
    if (p === null || seq !== SmartCategoryCountStore.persistSeq) {
      return;
    }
    try {
      const raw = await p.get(K_COUNT_JSON, '') as string;
      const map = SmartCategoryCountStore.parseStore(raw);
      map.set(acc, SmartCategoryCountStore.snapshot());
      await p.put(K_COUNT_JSON, SmartCategoryCountStore.storeToJson(map));
      await p.flush();
    } catch (_e) {
    }
  }

  private static snapshot(): Map<string, number> {
    const out: Map<string, number> = new Map<string, number>();
    SmartCategoryCountStore.byName.forEach((n: number, key: string): void => {
      out.set(key, n);
    });
    return out;
  }

  private static async readDisk(
    ctx: common.UIAbilityContext
  ): Promise<Map<string, Map<string, number>>> {
    const p = await SmartCategoryCountStore.openPrefs(ctx);
    if (p === null) {
      return new Map<string, Map<string, number>>();
    }
    try {
      const raw = await p.get(K_COUNT_JSON, '') as string;
      return SmartCategoryCountStore.parseStore(raw);
    } catch (_e) {
      return new Map<string, Map<string, number>>();
    }
  }

  private static async openPrefs(
    ctx: common.UIAbilityContext
  ): Promise<preferences.Preferences | null> {
    try {
      return await preferences.getPreferences(ctx, PREF_NAME);
    } catch (_e) {
      return null;
    }
  }

  private static parseStore(rawJson: string): Map<string, Map<string, number>> {
    const map: Map<string, Map<string, number>> = new Map<string, Map<string, number>>();
    if (rawJson.length === 0) {
      return map;
    }
    try {
      const parsed = JSON.parse(rawJson) as LooseJson;
      const byAccount = parsed['byAccount'];
      if (byAccount === undefined || typeof byAccount !== 'object' || byAccount === null ||
        Array.isArray(byAccount)) {
        return map;
      }
      const rec = byAccount as Record<string, Object>;
      const accounts: string[] = Object.keys(rec);
      for (let i = 0; i < accounts.length; i++) {
        const account = accounts[i];
        const rows = SmartCategoryCountStore.parseRows(rec[account]);
        if (rows.size > 0) {
          map.set(account, rows);
        }
      }
    } catch (_e) {
    }
    return map;
  }

  private static parseRows(raw: Object | undefined): Map<string, number> {
    const out: Map<string, number> = new Map<string, number>();
    if (raw === undefined || typeof raw !== 'object' || raw === null) {
      return out;
    }
    const rec = raw as LooseJson;
    const rowsVal = rec['rows'];
    if (!Array.isArray(rowsVal)) {
      return out;
    }
    const arr = rowsVal as Object[];
    for (let i = 0; i < arr.length; i++) {
      const el = arr[i];
      if (typeof el !== 'object' || el === null) {
        continue;
      }
      const row = el as LooseJson;
      const nameVal = row['name'];
      const countVal = row['count'];
      const name = typeof nameVal === 'string' ? nameVal.trim() : '';
      const countNum = typeof countVal === 'number' ? countVal : Number(countVal);
      if (name.length === 0 || !Number.isFinite(countNum) || countNum < 0) {
        continue;
      }
      out.set(name, Math.floor(countNum));
    }
    return out;
  }

  private static storeToJson(map: Map<string, Map<string, number>>): string {
    const byAccount: Record<string, Object> = {};
    map.forEach((rows: Map<string, number>, account: string): void => {
      const rowObjs: Record<string, string>[] = [];
      rows.forEach((count: number, name: string): void => {
        const rec: Record<string, string> = {};
        rec['name'] = name;
        rec['count'] = `${count}`;
        rowObjs.push(rec);
      });
      const payload: Record<string, Object> = {};
      payload['rows'] = rowObjs;
      byAccount[account] = payload;
    });
    const root: Record<string, Object> = {};
    root['byAccount'] = byAccount;
    return JSON.stringify(root);
  }
}
