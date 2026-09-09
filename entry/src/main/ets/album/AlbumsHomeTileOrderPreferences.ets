/**
 * 相册首页顶部宫格（媒体分类 + 用户相册）混合长按排序。
 * Preferences 按账号隔离，put 后必须 flush。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import { MediaCategoryItem, UserAlbumItem } from '../model/FnApiTypes';
import { mediaCategoryStableId, userAlbumId, userAlbumName } from './GalleryAlbumEntityData';

const PREF_NAME: string = 'fnos_client_prefs';
const K_TILE_ORDER_JSON: string = 'albums_home_tile_order_json';
const K_TILE_HIDDEN_JSON: string = 'albums_home_tile_hidden_json';

type LooseJson = Record<string, Object | string | number | boolean | undefined | null>;

let cachedAccount: string = '';
let cachedOrder: string[] = [];
let cachedHidden: string[] = [];
let cacheReady: boolean = false;

export class AlbumsHomeTile {
  kind: string = 'media';
  media: MediaCategoryItem | undefined = undefined;
  album: UserAlbumItem | undefined = undefined;
}

export function albumsHomeMediaTileKey(item: MediaCategoryItem): string {
  return `m:${mediaCategoryStableId(item)}`;
}

export function albumsHomeAlbumTileKey(item: UserAlbumItem): string {
  const id = userAlbumId(item);
  if (id.length > 0) {
    return `u:${id}`;
  }
  return `u:name:${userAlbumName(item)}`;
}

export function albumsHomeTileKey(tile: AlbumsHomeTile): string {
  if (tile.kind === 'user-album') {
    const album = tile.album;
    if (album !== undefined) {
      return albumsHomeAlbumTileKey(album);
    }
    return 'u:';
  }
  const media = tile.media;
  if (media !== undefined) {
    return albumsHomeMediaTileKey(media);
  }
  return 'm:';
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

export function albumsHomeOrderFromTiles(tiles: AlbumsHomeTile[]): string[] {
  const out: string[] = [];
  const used: Set<string> = new Set<string>();
  for (let i = 0; i < tiles.length; i++) {
    const id = albumsHomeTileKey(tiles[i]);
    if (id.length > 0 && !used.has(id)) {
      out.push(id);
      used.add(id);
    }
  }
  return out;
}

function applyAlbumsHomeTileOrder(tiles: AlbumsHomeTile[], order: string[]): AlbumsHomeTile[] {
  if (tiles.length <= 0 || order.length <= 0) {
    return tiles;
  }
  const byId: Map<string, AlbumsHomeTile> = new Map<string, AlbumsHomeTile>();
  for (let i = 0; i < tiles.length; i++) {
    const id = albumsHomeTileKey(tiles[i]);
    if (!byId.has(id)) {
      byId.set(id, tiles[i]);
    }
  }
  const out: AlbumsHomeTile[] = [];
  const used: Set<string> = new Set<string>();
  for (let i = 0; i < order.length; i++) {
    const id = order[i];
    const item = byId.get(id);
    if (item !== undefined && !used.has(id)) {
      out.push(item);
      used.add(id);
    }
  }
  for (let i = 0; i < tiles.length; i++) {
    const id = albumsHomeTileKey(tiles[i]);
    if (!used.has(id)) {
      out.push(tiles[i]);
      used.add(id);
    }
  }
  return out;
}

export function buildAlbumsHomeTiles(
  media: MediaCategoryItem[],
  albums: UserAlbumItem[],
  order: string[],
  hidden: string[]
): AlbumsHomeTile[] {
  const tiles: AlbumsHomeTile[] = [];
  for (let i = 0; i < media.length; i++) {
    const tile = new AlbumsHomeTile();
    tile.kind = 'media';
    tile.media = media[i];
    tiles.push(tile);
  }
  for (let i = 0; i < albums.length; i++) {
    const tile = new AlbumsHomeTile();
    tile.kind = 'user-album';
    tile.album = albums[i];
    tiles.push(tile);
  }
  return filterAlbumsHomeTiles(applyAlbumsHomeTileOrder(tiles, order), hidden);
}

export function filterAlbumsHomeTiles(tiles: AlbumsHomeTile[], hidden: string[]): AlbumsHomeTile[] {
  if (hidden.length <= 0) {
    return tiles;
  }
  const hiddenSet: Set<string> = new Set<string>();
  for (let i = 0; i < hidden.length; i++) {
    hiddenSet.add(hidden[i]);
  }
  const out: AlbumsHomeTile[] = [];
  for (let i = 0; i < tiles.length; i++) {
    if (!hiddenSet.has(albumsHomeTileKey(tiles[i]))) {
      out.push(tiles[i]);
    }
  }
  return out;
}

export function albumsHomeMoveTiles(list: AlbumsHomeTile[], from: number, to: number): AlbumsHomeTile[] {
  if (from === to || from < 0 || to < 0 || from >= list.length || to >= list.length) {
    return list;
  }
  const next: AlbumsHomeTile[] = list.slice();
  const removed: AlbumsHomeTile[] = next.splice(from, 1);
  if (removed.length <= 0) {
    return list;
  }
  next.splice(to, 0, removed[0]);
  return next;
}

export function albumsHomeMediaFromTiles(tiles: AlbumsHomeTile[]): MediaCategoryItem[] {
  const out: MediaCategoryItem[] = [];
  for (let i = 0; i < tiles.length; i++) {
    const media = tiles[i].media;
    if (tiles[i].kind === 'media' && media !== undefined) {
      out.push(media);
    }
  }
  return out;
}

export function albumsHomeMergeMediaOrder(
  visibleTiles: AlbumsHomeTile[],
  allMedia: MediaCategoryItem[]
): MediaCategoryItem[] {
  const visible = albumsHomeMediaFromTiles(visibleTiles);
  const used: Set<string> = new Set<string>();
  const out: MediaCategoryItem[] = [];
  for (let i = 0; i < visible.length; i++) {
    const id = mediaCategoryStableId(visible[i]);
    if (!used.has(id)) {
      out.push(visible[i]);
      used.add(id);
    }
  }
  for (let i = 0; i < allMedia.length; i++) {
    const id = mediaCategoryStableId(allMedia[i]);
    if (!used.has(id)) {
      out.push(allMedia[i]);
      used.add(id);
    }
  }
  return out;
}

async function loadLayoutLocked(ctx: common.UIAbilityContext, account: string): Promise<void> {
  if (cacheReady && cachedAccount === account) {
    return;
  }
  const p = await openPrefs(ctx);
  if (p === null) {
    cachedAccount = account;
    cachedOrder = [];
    cachedHidden = [];
    cacheReady = true;
    return;
  }
  try {
    const orderRaw = await p.get(K_TILE_ORDER_JSON, '') as string;
    const hiddenRaw = await p.get(K_TILE_HIDDEN_JSON, '') as string;
    const orderMap = parseStore(orderRaw);
    const hiddenMap = parseStore(hiddenRaw);
    const foundOrder = orderMap.get(account);
    const foundHidden = hiddenMap.get(account);
    cachedAccount = account;
    cachedOrder = foundOrder !== undefined ? foundOrder : [];
    cachedHidden = foundHidden !== undefined ? foundHidden : [];
    cacheReady = true;
  } catch (_e) {
    cachedAccount = account;
    cachedOrder = [];
    cachedHidden = [];
    cacheReady = true;
  }
}

export async function albumsHomeTileOrderFromUi(ui: UIContext): Promise<string[]> {
  const account = currentAccount();
  const ctx = abilityContextFromUi(ui);
  if (ctx === undefined || account.length === 0) {
    return [];
  }
  await loadLayoutLocked(ctx, account);
  return cachedOrder;
}

export async function albumsHomeHiddenKeysFromUi(ui: UIContext): Promise<string[]> {
  const account = currentAccount();
  const ctx = abilityContextFromUi(ui);
  if (ctx === undefined || account.length === 0) {
    return [];
  }
  await loadLayoutLocked(ctx, account);
  return cachedHidden.slice();
}

async function persistStringArray(
  ctx: common.UIAbilityContext,
  account: string,
  prefKey: string,
  values: string[]
): Promise<void> {
  const p = await openPrefs(ctx);
  if (p === null) {
    return;
  }
  try {
    const raw = await p.get(prefKey, '') as string;
    const map = parseStore(raw);
    map.set(account, values);
    await p.put(prefKey, storeToJson(map));
    await p.flush();
  } catch (_e) {
  }
}

export async function albumsHomePersistTileOrderFromUi(ui: UIContext, tiles: AlbumsHomeTile[]): Promise<void> {
  const account = currentAccount();
  const ctx = abilityContextFromUi(ui);
  if (ctx === undefined || account.length === 0) {
    return;
  }
  const order = albumsHomeOrderFromTiles(tiles);
  cachedAccount = account;
  cachedOrder = order;
  cacheReady = true;
  await persistStringArray(ctx, account, K_TILE_ORDER_JSON, order);
}

export async function albumsHomePersistHiddenKeysFromUi(ui: UIContext, hidden: string[]): Promise<void> {
  const account = currentAccount();
  const ctx = abilityContextFromUi(ui);
  if (ctx === undefined || account.length === 0) {
    return;
  }
  cachedAccount = account;
  cachedHidden = hidden.slice();
  cacheReady = true;
  await persistStringArray(ctx, account, K_TILE_HIDDEN_JSON, cachedHidden);
}

export class AlbumsHomeLayoutSnapshot {
  order: string[] = [];
  hidden: string[] = [];
}

export async function albumsHomeSnapshotFromCtx(
  ctx: common.UIAbilityContext | undefined
): Promise<AlbumsHomeLayoutSnapshot> {
  const snap = new AlbumsHomeLayoutSnapshot();
  const account = currentAccount();
  if (ctx === undefined || account.length === 0) {
    return snap;
  }
  await loadLayoutLocked(ctx, account);
  snap.order = cachedOrder.slice();
  snap.hidden = cachedHidden.slice();
  return snap;
}

export async function albumsHomeApplyLayoutFromCtx(
  ctx: common.UIAbilityContext | undefined,
  order: string[],
  hidden: string[]
): Promise<void> {
  const account = currentAccount();
  if (ctx === undefined || account.length === 0) {
    return;
  }
  cachedAccount = account;
  cachedOrder = order.slice();
  cachedHidden = hidden.slice();
  cacheReady = true;
  await persistStringArray(ctx, account, K_TILE_ORDER_JSON, cachedOrder);
  await persistStringArray(ctx, account, K_TILE_HIDDEN_JSON, cachedHidden);
}
