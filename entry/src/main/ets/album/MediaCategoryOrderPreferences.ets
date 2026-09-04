/**
 * 相册页媒体分类（智能相册上方宫格）的本地排序。
 * Preferences 按账号隔离，put 后必须 flush。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import { MediaCategoryItem } from '../model/FnApiTypes';
import { categoryTitle } from './GalleryAlbumEntityData';

const PREF_NAME: string = 'fnos_client_prefs';
const K_ORDER_JSON: string = 'media_category_order_json';

type LooseJson = Record<string, Object | string | number | boolean | undefined | null>;

let cachedAccount: string = '';
let cachedOrder: string[] = [];
let cacheReady: boolean = false;

function stableIdOf(item: MediaCategoryItem): string {
  if (item.id !== undefined) {
    const idText: string = `${item.id}`.trim();
    if (idText.length > 0) {
      return `id:${idText}`;
    }
  }
  const key: string = item.key !== undefined ? item.key.trim() : '';
  if (key.length > 0) {
    return `key:${key}`;
  }
  return `name:${categoryTitle(item)}`;
}

function currentAccount(): string {
  const stored = AppSession.getStored();
  return stored !== null ? stored.account.trim() : '';
}

function abilityContextFromUi(ui: UIContext): common.UIAbilityContext | undefined {
  try {
    const ctx = ui.getHostContext();
    if (ctx === undefined || ctx === null) {
      return undefined;
    }
    return ctx as common.UIAbilityContext;
  } catch (_e) {
    return undefined;
  }
}

async function openPrefs(ctx: common.UIAbilityContext): Promise<preferences.Preferences | null> {
  try {
    return await preferences.getPreferences(ctx, PREF_NAME);
  } catch (_e) {
    return null;
  }
}

function asString(value: Object | string | number | boolean | undefined | null, fallback: string): string {
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  return fallback;
}

function parseStringArray(raw: Object | string | number | boolean | undefined | null): string[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  const arr = raw as Object[];
  const out: string[] = [];
  for (let i = 0; i < arr.length; i++) {
    const text = asString(arr[i] as Object | string | number | boolean | undefined | null, '').trim();
    if (text.length > 0) {
      out.push(text);
    }
  }
  return out;
}

function parseStore(rawJson: string): Map<string, string[]> {
  const map: Map<string, string[]> = new Map<string, string[]>();
  if (rawJson.length === 0) {
    return map;
  }
  try {
    const parsed = JSON.parse(rawJson) as LooseJson;
    const byAccount = parsed['byAccount'];
    if (byAccount !== undefined && typeof byAccount === 'object' && byAccount !== null && !Array.isArray(byAccount)) {
      const rec = byAccount as Record<string, Object>;
      const keys: string[] = Object.keys(rec);
      for (let i = 0; i < keys.length; i++) {
        const account = keys[i];
        map.set(account, parseStringArray(rec[account]));
      }
    }
  } catch (_e) {
  }
  return map;
}

function storeToJson(map: Map<string, string[]>): string {
  const byAccount: Record<string, string[]> = {};
  map.forEach((order: string[], account: string): void => {
    byAccount[account] = order;
  });
  const root: LooseJson = {};
  root['byAccount'] = byAccount;
  return JSON.stringify(root);
}

export function applyMediaCategoryOrder(items: MediaCategoryItem[], order: string[]): MediaCategoryItem[] {
  if (items.length <= 0 || order.length <= 0) {
    return items;
  }
  const byId: Map<string, MediaCategoryItem> = new Map<string, MediaCategoryItem>();
  for (let i = 0; i < items.length; i++) {
    const id = stableIdOf(items[i]);
    if (!byId.has(id)) {
      byId.set(id, items[i]);
    }
  }
  const out: MediaCategoryItem[] = [];
  const used: Set<string> = new Set<string>();
  for (let i = 0; i < order.length; i++) {
    const id = order[i];
    const item = byId.get(id);
    if (item !== undefined && !used.has(id)) {
      out.push(item);
      used.add(id);
    }
  }
  for (let i = 0; i < items.length; i++) {
    const id = stableIdOf(items[i]);
    if (!used.has(id)) {
      out.push(items[i]);
      used.add(id);
    }
  }
  return out;
}

export function mediaCategoryOrderFromItems(items: MediaCategoryItem[]): string[] {
  const out: string[] = [];
  const used: Set<string> = new Set<string>();
  for (let i = 0; i < items.length; i++) {
    const id = stableIdOf(items[i]);
    if (id.length > 0 && !used.has(id)) {
      out.push(id);
      used.add(id);
    }
  }
  return out;
}

export function mediaCategoryMoveItems(list: MediaCategoryItem[], from: number, to: number): MediaCategoryItem[] {
  if (from === to || from < 0 || to < 0 || from >= list.length || to >= list.length) {
    return list;
  }
  const next: MediaCategoryItem[] = list.slice();
  const removed: MediaCategoryItem[] = next.splice(from, 1);
  if (removed.length <= 0) {
    return list;
  }
  next.splice(to, 0, removed[0]);
  return next;
}

async function loadOrderLocked(ctx: common.UIAbilityContext, account: string): Promise<string[]> {
  if (cacheReady && cachedAccount === account) {
    return cachedOrder;
  }
  const p = await openPrefs(ctx);
  if (p === null) {
    cachedAccount = account;
    cachedOrder = [];
    cacheReady = true;
    return cachedOrder;
  }
  try {
    const raw = await p.get(K_ORDER_JSON, '') as string;
    const map = parseStore(raw);
    const found = map.get(account);
    cachedAccount = account;
    cachedOrder = found !== undefined ? found : [];
    cacheReady = true;
    return cachedOrder;
  } catch (_e) {
    cachedAccount = account;
    cachedOrder = [];
    cacheReady = true;
    return cachedOrder;
  }
}

export async function mediaCategoryItemsWithSavedOrder(
  ctx: common.UIAbilityContext | undefined,
  items: MediaCategoryItem[]
): Promise<MediaCategoryItem[]> {
  const account = currentAccount();
  if (ctx === undefined || account.length === 0 || items.length <= 0) {
    return items;
  }
  const order = await loadOrderLocked(ctx, account);
  return applyMediaCategoryOrder(items, order);
}

export async function mediaCategoryItemsWithSavedOrderFromUi(
  ui: UIContext,
  items: MediaCategoryItem[]
): Promise<MediaCategoryItem[]> {
  return mediaCategoryItemsWithSavedOrder(abilityContextFromUi(ui), items);
}

export async function mediaCategoryPersistOrder(
  ctx: common.UIAbilityContext | undefined,
  items: MediaCategoryItem[]
): Promise<void> {
  const account = currentAccount();
  if (ctx === undefined || account.length === 0) {
    return;
  }
  const order = mediaCategoryOrderFromItems(items);
  cachedAccount = account;
  cachedOrder = order;
  cacheReady = true;
  const p = await openPrefs(ctx);
  if (p === null) {
    return;
  }
  try {
    const raw = await p.get(K_ORDER_JSON, '') as string;
    const map = parseStore(raw);
    map.set(account, order);
    await p.put(K_ORDER_JSON, storeToJson(map));
    await p.flush();
  } catch (_e) {
  }
}

export async function mediaCategoryPersistOrderFromUi(ui: UIContext, items: MediaCategoryItem[]): Promise<void> {
  await mediaCategoryPersistOrder(abilityContextFromUi(ui), items);
}
