/**
 * 智能分类本地布局：自定义关键词 + 各组内顺序。
 * 用 Preferences 持久化（put 后必须 flush），按账号隔离。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSession } from '../auth/AppSession';
import { SmartCategoryItem } from '../model/FnApiTypes';
import { smartCategoryCover, smartCategoryCount, smartCategoryName } from './GalleryAlbumEntityData';

const PREF_NAME: string = 'fnos_client_prefs';
const K_LAYOUT_JSON: string = 'smart_category_layout_json';

export const SMART_CATEGORY_KEYWORD_MAX_LEN: number = 20;
export const SMART_CATEGORY_CUSTOM_MAX: number = 30;

export interface SmartCategoryCustomKeyword {
  id: string;
  keyword: string;
  cover?: string;
  count?: number;
}

export interface SmartCategoryLayout {
  account: string;
  custom: SmartCategoryCustomKeyword[];
  sceneOrder: string[];
  infoOrder: string[];
  customOrder: string[];
  /** 本地最后写入时间，供跨设备 Last-Write-Wins；0 表示尚未标记 */
  updatedAt: number;
}

export interface SmartCategoryMergedLists {
  sceneItems: SmartCategoryItem[];
  infoItems: SmartCategoryItem[];
  customItems: SmartCategoryItem[];
}

type LooseJson = Record<string, Object | string | number | boolean | undefined | null>;

function emptyLayout(account: string): SmartCategoryLayout {
  return {
    account: account,
    custom: [],
    sceneOrder: [],
    infoOrder: [],
    customOrder: [],
    updatedAt: 0
  };
}

export function smartCategoryCurrentAccount(): string {
  const stored = AppSession.getStored();
  return stored !== null ? stored.account.trim() : '';
}

export function smartCategoryEmptyLayout(account: string): SmartCategoryLayout {
  return emptyLayout(account);
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

function asTime(value: Object | string | number | boolean | undefined | null): number {
  if (typeof value === 'number' && Number.isFinite(value) && value >= 0) {
    return Math.floor(value);
  }
  if (typeof value === 'string') {
    const n = Number(value);
    if (Number.isFinite(n) && n >= 0) {
      return Math.floor(n);
    }
  }
  return 0;
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

function parseCustomList(raw: Object | string | number | boolean | undefined | null): SmartCategoryCustomKeyword[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  const arr = raw as Object[];
  const out: SmartCategoryCustomKeyword[] = [];
  const seenIds: Set<string> = new Set<string>();
  for (let i = 0; i < arr.length; i++) {
    const el = arr[i] as Object | string | number | boolean | undefined | null;
    if (typeof el !== 'object' || el === null) {
      continue;
    }
    const rec = el as LooseJson;
    const id = asString(rec['id'], '').trim();
    const keyword = asString(rec['keyword'], '').trim();
    if (id.length === 0 || keyword.length === 0 || seenIds.has(id)) {
      continue;
    }
    seenIds.add(id);
    const item: SmartCategoryCustomKeyword = { id: id, keyword: keyword };
    const cover = asString(rec['cover'], '').trim();
    if (cover.length > 0) {
      item.cover = cover;
    }
    const countRaw = asString(rec['count'], '').trim();
    if (countRaw.length > 0) {
      const countNum = Number(countRaw);
      if (Number.isFinite(countNum) && countNum >= 0) {
        item.count = Math.floor(countNum);
      }
    }
    out.push(item);
  }
  return out;
}

function parseAccountPayload(raw: Object | undefined | null): SmartCategoryLayout {
  if (raw === undefined || raw === null || typeof raw !== 'object') {
    return emptyLayout('');
  }
  const rec = raw as LooseJson;
  return {
    account: '',
    custom: parseCustomList(rec['custom']),
    sceneOrder: parseStringArray(rec['sceneOrder']),
    infoOrder: parseStringArray(rec['infoOrder']),
    customOrder: parseStringArray(rec['customOrder']),
    updatedAt: asTime(rec['updatedAt'])
  };
}

function parseStore(rawJson: string): Map<string, SmartCategoryLayout> {
  const map: Map<string, SmartCategoryLayout> = new Map<string, SmartCategoryLayout>();
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
        const layout = parseAccountPayload(rec[account]);
        layout.account = account;
        map.set(account, layout);
      }
      return map;
    }
    // 兼容单账号扁平结构
    if (parsed['custom'] !== undefined || parsed['sceneOrder'] !== undefined) {
      const account = asString(parsed['account'], '').trim();
      const layout = parseAccountPayload(parsed);
      layout.account = account;
      if (account.length > 0) {
        map.set(account, layout);
      }
    }
  } catch (_e) {
  }
  return map;
}

function storeToJson(map: Map<string, SmartCategoryLayout>): string {
  const byAccount: Record<string, LooseJson> = {};
  map.forEach((layout: SmartCategoryLayout, account: string): void => {
    const customObjs: Record<string, string>[] = [];
    for (let c = 0; c < layout.custom.length; c++) {
      const row = layout.custom[c];
      const rec: Record<string, string> = {};
      rec['id'] = row.id;
      rec['keyword'] = row.keyword;
      if (row.cover !== undefined && row.cover.length > 0) {
        rec['cover'] = row.cover;
      }
      if (row.count !== undefined && row.count >= 0) {
        rec['count'] = `${row.count}`;
      }
      customObjs.push(rec);
    }
    const payload: LooseJson = {};
    payload['custom'] = customObjs;
    payload['sceneOrder'] = layout.sceneOrder;
    payload['infoOrder'] = layout.infoOrder;
    payload['customOrder'] = layout.customOrder;
    const updatedAt = layout.updatedAt > 0 ? layout.updatedAt : 0;
    if (updatedAt > 0) {
      payload['updatedAt'] = updatedAt;
    }
    byAccount[account] = payload;
  });
  const root: LooseJson = {};
  root['byAccount'] = byAccount;
  return JSON.stringify(root);
}

export async function smartCategoryLoadLayout(
  ctx: common.UIAbilityContext,
  account: string
): Promise<SmartCategoryLayout> {
  const acc = account.trim();
  if (acc.length === 0) {
    return emptyLayout('');
  }
  const p = await openPrefs(ctx);
  if (p === null) {
    return emptyLayout(acc);
  }
  try {
    const raw = await p.get(K_LAYOUT_JSON, '') as string;
    const map = parseStore(raw);
    const found = map.get(acc);
    if (found === undefined) {
      return emptyLayout(acc);
    }
    found.account = acc;
    return found;
  } catch (_e) {
    return emptyLayout(acc);
  }
}

export async function smartCategorySaveLayout(
  ctx: common.UIAbilityContext,
  layout: SmartCategoryLayout
): Promise<boolean> {
  const acc = layout.account.trim();
  if (acc.length === 0) {
    return false;
  }
  const p = await openPrefs(ctx);
  if (p === null) {
    return false;
  }
  try {
    const raw = await p.get(K_LAYOUT_JSON, '') as string;
    const map = parseStore(raw);
    const updatedAt = layout.updatedAt > 0 ? layout.updatedAt : Date.now();
    map.set(acc, {
      account: acc,
      custom: layout.custom,
      sceneOrder: layout.sceneOrder,
      infoOrder: layout.infoOrder,
      customOrder: layout.customOrder,
      updatedAt: updatedAt
    });
    await p.put(K_LAYOUT_JSON, storeToJson(map));
    await p.flush();
    return true;
  } catch (_e) {
    return false;
  }
}

export function smartCategoryNewCustomId(): string {
  return `c_${Date.now()}_${Math.floor(Math.random() * 1000000000)}`;
}

function foldKey(text: string): string {
  return text.trim().toLowerCase();
}

export function applySmartCategoryNameOrder(
  items: SmartCategoryItem[],
  order: string[]
): SmartCategoryItem[] {
  const byName: Map<string, SmartCategoryItem> = new Map<string, SmartCategoryItem>();
  for (let i = 0; i < items.length; i++) {
    const name = smartCategoryName(items[i]);
    if (!byName.has(name)) {
      byName.set(name, items[i]);
    }
  }
  const out: SmartCategoryItem[] = [];
  const used: Set<string> = new Set<string>();
  for (let i = 0; i < order.length; i++) {
    const name = order[i];
    const item = byName.get(name);
    if (item !== undefined && !used.has(name)) {
      out.push(item);
      used.add(name);
    }
  }
  for (let i = 0; i < items.length; i++) {
    const name = smartCategoryName(items[i]);
    if (!used.has(name)) {
      out.push(items[i]);
      used.add(name);
    }
  }
  return out;
}

function applyCustomOrder(
  custom: SmartCategoryCustomKeyword[],
  order: string[]
): SmartCategoryCustomKeyword[] {
  const byId: Map<string, SmartCategoryCustomKeyword> = new Map<string, SmartCategoryCustomKeyword>();
  for (let i = 0; i < custom.length; i++) {
    byId.set(custom[i].id, custom[i]);
  }
  const out: SmartCategoryCustomKeyword[] = [];
  const used: Set<string> = new Set<string>();
  for (let i = 0; i < order.length; i++) {
    const id = order[i];
    const row = byId.get(id);
    if (row !== undefined && !used.has(id)) {
      out.push(row);
      used.add(id);
    }
  }
  for (let i = 0; i < custom.length; i++) {
    const id = custom[i].id;
    if (!used.has(id)) {
      out.push(custom[i]);
      used.add(id);
    }
  }
  return out;
}

export function smartCategoryItemsFromCustom(custom: SmartCategoryCustomKeyword[]): SmartCategoryItem[] {
  const out: SmartCategoryItem[] = [];
  for (let i = 0; i < custom.length; i++) {
    const row = custom[i];
    const item: SmartCategoryItem = {
      name: row.keyword,
      customId: row.id,
      count: row.count !== undefined ? row.count : 0
    };
    if (row.cover !== undefined && row.cover.length > 0) {
      item.cover = row.cover;
    }
    out.push(item);
  }
  return out;
}

export function smartCategoryMergeDisplay(
  sceneItems: SmartCategoryItem[],
  infoItems: SmartCategoryItem[],
  layout: SmartCategoryLayout
): SmartCategoryMergedLists {
  const orderedCustom = applyCustomOrder(layout.custom, layout.customOrder);
  return {
    sceneItems: applySmartCategoryNameOrder(sceneItems, layout.sceneOrder),
    infoItems: applySmartCategoryNameOrder(infoItems, layout.infoOrder),
    customItems: smartCategoryItemsFromCustom(orderedCustom)
  };
}

export function smartCategoryLayoutFromDisplay(
  account: string,
  sceneItems: SmartCategoryItem[],
  infoItems: SmartCategoryItem[],
  customItems: SmartCategoryItem[]
): SmartCategoryLayout {
  const sceneOrder: string[] = [];
  for (let i = 0; i < sceneItems.length; i++) {
    sceneOrder.push(smartCategoryName(sceneItems[i]));
  }
  const infoOrder: string[] = [];
  for (let i = 0; i < infoItems.length; i++) {
    infoOrder.push(smartCategoryName(infoItems[i]));
  }
  const custom: SmartCategoryCustomKeyword[] = [];
  const customOrder: string[] = [];
  for (let i = 0; i < customItems.length; i++) {
    const item = customItems[i];
    const id = item.customId !== undefined ? item.customId.trim() : '';
    const keyword = smartCategoryName(item).trim();
    if (id.length === 0 || keyword.length === 0) {
      continue;
    }
    const row: SmartCategoryCustomKeyword = { id: id, keyword: keyword };
    const cover = smartCategoryCover(item);
    if (cover.length > 0) {
      row.cover = cover;
    }
    const count = smartCategoryCount(item);
    if (count > 0) {
      row.count = count;
    }
    custom.push(row);
    customOrder.push(id);
  }
  return {
    account: account,
    custom: custom,
    sceneOrder: sceneOrder,
    infoOrder: infoOrder,
    customOrder: customOrder,
    updatedAt: 0
  };
}

export function smartCategoryCustomIdOf(item: SmartCategoryItem): string {
  return item.customId !== undefined ? item.customId.trim() : '';
}

export function smartCategoryIsCustom(item: SmartCategoryItem): boolean {
  return smartCategoryCustomIdOf(item).length > 0;
}

export function smartCategoryWithCover(
  item: SmartCategoryItem,
  cover: string,
  count: number
): SmartCategoryItem {
  const next: SmartCategoryItem = {
    id: item.id,
    name: item.name,
    count: count,
    total: count,
    itemCount: count,
    poster: item.poster,
    customId: item.customId
  };
  if (cover.length > 0) {
    next.cover = cover;
  } else if (item.cover !== undefined && item.cover.length > 0) {
    next.cover = item.cover;
  }
  return next;
}

/** 按分类名回写封面数量，与点进分类后的实际媒体条数对齐。 */
export function smartCategoryPatchCountByName(
  items: SmartCategoryItem[],
  name: string,
  count: number
): SmartCategoryItem[] {
  const keyword = name.trim();
  const n = Math.max(0, Math.floor(count));
  if (keyword.length === 0 || items.length === 0) {
    return items;
  }
  let changed = false;
  const out: SmartCategoryItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (smartCategoryName(item) !== keyword || smartCategoryCount(item) === n) {
      out.push(item);
      continue;
    }
    changed = true;
    const cover = item.cover !== undefined ? item.cover : '';
    out.push(smartCategoryWithCover(item, cover, n));
  }
  return changed ? out : items;
}

export interface SmartCategoryCoverPatch {
  customId: string;
  cover: string;
  count: number;
}

export function smartCategoryApplyCoverPatches(
  items: SmartCategoryItem[],
  patches: SmartCategoryCoverPatch[]
): SmartCategoryItem[] {
  if (patches.length === 0) {
    return items;
  }
  const byId: Map<string, SmartCategoryCoverPatch> = new Map<string, SmartCategoryCoverPatch>();
  for (let i = 0; i < patches.length; i++) {
    byId.set(patches[i].customId, patches[i]);
  }
  const out: SmartCategoryItem[] = [];
  let changed = false;
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const id = smartCategoryCustomIdOf(item);
    const patch = id.length > 0 ? byId.get(id) : undefined;
    if (patch === undefined) {
      out.push(item);
      continue;
    }
    changed = true;
    out.push(smartCategoryWithCover(item, patch.cover, patch.count));
  }
  return changed ? out : items;
}

export function smartCategoryMonogram(item: SmartCategoryItem): string {
  const name = smartCategoryName(item);
  return name.length > 0 ? name.substring(0, 1) : '分';
}

export function smartCategoryValidateNewKeyword(
  raw: string,
  sceneItems: SmartCategoryItem[],
  infoItems: SmartCategoryItem[],
  customItems: SmartCategoryItem[]
): string {
  const keyword = raw.trim();
  if (keyword.length === 0) {
    return '请输入关键词';
  }
  if (keyword.length > SMART_CATEGORY_KEYWORD_MAX_LEN) {
    return `关键词最多 ${SMART_CATEGORY_KEYWORD_MAX_LEN} 个字`;
  }
  if (customItems.length >= SMART_CATEGORY_CUSTOM_MAX) {
    return `最多添加 ${SMART_CATEGORY_CUSTOM_MAX} 个自定义分类`;
  }
  const folded = foldKey(keyword);
  for (let i = 0; i < customItems.length; i++) {
    if (foldKey(smartCategoryName(customItems[i])) === folded) {
      return '该关键词已存在';
    }
  }
  for (let i = 0; i < sceneItems.length; i++) {
    if (foldKey(smartCategoryName(sceneItems[i])) === folded) {
      return '与场景分类重名';
    }
  }
  for (let i = 0; i < infoItems.length; i++) {
    if (foldKey(smartCategoryName(infoItems[i])) === folded) {
      return '与资料分类重名';
    }
  }
  return '';
}

export function smartCategoryMoveItems(list: SmartCategoryItem[], from: number, to: number): void {
  if (from === to || from < 0 || to < 0 || from >= list.length || to >= list.length) {
    return;
  }
  const removed: SmartCategoryItem[] = list.splice(from, 1);
  if (removed.length > 0) {
    list.splice(to, 0, removed[0]);
  }
}

export async function smartCategoryPersistFromDisplay(
  ctx: common.UIAbilityContext | undefined,
  sceneItems: SmartCategoryItem[],
  infoItems: SmartCategoryItem[],
  customItems: SmartCategoryItem[]
): Promise<void> {
  if (ctx === undefined) {
    return;
  }
  const account = smartCategoryCurrentAccount();
  if (account.length === 0) {
    return;
  }
  const layout = smartCategoryLayoutFromDisplay(account, sceneItems, infoItems, customItems);
  await smartCategorySaveLayout(ctx, layout);
}
