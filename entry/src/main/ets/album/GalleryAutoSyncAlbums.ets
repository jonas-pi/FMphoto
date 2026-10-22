/**
 * 同步到 NAS 时的「按本机相册名建同名相册」支持。
 *
 * 规则（对齐 NAS 实测行为）：
 * - 名字先清洗：去首尾空白 / 控制字符，超长截断到 40（UI 上限）；
 * - 先按名字查 album/list，命中直接复用 id；
 * - 没命中才 create；create 返回「同名已存在」时再查一次（并发或用户在 NAS 端刚建过）；
 * - albumId 进程内缓存，归档失败时清掉缓存，下次重新解析。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppSession } from '../auth/AppSession';
import { fnDiagRecord } from '../common/FnDiagLog';
import { FnHttpClient } from '../network/FnHttpClient';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncAlbums';
const MAX_ALBUM_NAME = 40;

const albumIdCache: Map<string, string> = new Map<string, string>();
/** 缓存归属：换账号或换 NAS 时整表丢弃，避免拿着上一台的相册 id 去归档 */
let cacheOwner: string = '';

function currentOwner(): string {
  const stored = AppSession.getStored();
  if (stored === null) {
    return '';
  }
  const nas = stored.fnIdInput.trim().length > 0
    ? stored.fnIdInput.trim()
    : (stored.domainInput.trim().length > 0 ? stored.domainInput.trim() : stored.baseUrl.trim());
  return `${nas}|${stored.account.trim()}`;
}

function ensureCacheOwner(): void {
  const owner = currentOwner();
  if (owner !== cacheOwner) {
    albumIdCache.clear();
    cacheOwner = owner;
  }
}

export function normalizeAlbumName(raw: string): string {
  let name = raw.replace(/[\u0000-\u001f]/g, '').trim();
  if (name.length > MAX_ALBUM_NAME) {
    name = name.substring(0, MAX_ALBUM_NAME);
  }
  return name;
}

function isDuplicateAlbumMessage(message: string): boolean {
  const low = message.toLowerCase();
  return low.indexOf('already exist') >= 0 || message.indexOf('相同') >= 0 || message.indexOf('已存在') >= 0;
}

function readAlbumId(data: Object | undefined): string {
  if (data === undefined) {
    return '';
  }
  const record = data as Record<string, Object | string | number | undefined>;
  const raw = record['albumId'];
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    return `${Math.floor(raw)}`;
  }
  if (typeof raw === 'string' && raw.trim().length > 0) {
    return raw.trim();
  }
  return '';
}

async function findAlbumIdByName(client: FnHttpClient, name: string): Promise<string> {
  const res = await client.getUserAlbumList();
  if (!res.success || res.data === undefined) {
    // 不记相册名与 albumId。
    const msg: string = (res.message ?? '').trim();
    hilog.info(DOMAIN, TAG, 'album list failed: %{public}s', msg);
    fnDiagRecord('W', TAG, `album resolve failed ${msg.substring(0, 80)}`);
    return '';
  }
  const list = res.data.list ?? [];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    const albumName = (item.albumName ?? '').trim();
    if (albumName !== name) {
      continue;
    }
    const rawId = item.albumId;
    if (rawId !== undefined && rawId !== null) {
      const idText = `${rawId}`.trim();
      if (idText.length > 0) {
        return idText;
      }
    }
  }
  return '';
}

/** 解析本地相册名对应的 NAS 相册 id；失败返回空串（调用方按「不归档」处理）。 */
export async function ensureNasAlbumId(client: FnHttpClient, rawName: string): Promise<string> {
  ensureCacheOwner();
  const name = normalizeAlbumName(rawName);
  if (name.length === 0) {
    return '';
  }
  const cached = albumIdCache.get(name);
  if (cached !== undefined && cached.length > 0) {
    return cached;
  }
  const existing = await findAlbumIdByName(client, name);
  if (existing.length > 0) {
    albumIdCache.set(name, existing);
    return existing;
  }
  const created = await client.createUserAlbum(name, []);
  if (created.success) {
    const id = readAlbumId(created.data);
    if (id.length > 0) {
      albumIdCache.set(name, id);
      hilog.info(DOMAIN, TAG, 'album created');
      return id;
    }
    return '';
  }
  // 同名已存在（并发 / 用户刚在 NAS 端建过）：重新查一次再复用
  if (isDuplicateAlbumMessage(created.message ?? '')) {
    const again = await findAlbumIdByName(client, name);
    if (again.length > 0) {
      albumIdCache.set(name, again);
      hilog.info(DOMAIN, TAG, 'album reused after duplicate');
      return again;
    }
  }
  const createMsg: string = (created.message ?? '').trim();
  hilog.info(DOMAIN, TAG, 'album create failed msg=%{public}s', createMsg);
  fnDiagRecord('W', TAG, `album resolve failed ${createMsg.substring(0, 80)}`);
  return '';
}

/** 把已上传成功的照片批量加入同名相册；返回是否全部成功。 */
export async function archivePhotosToNasAlbum(
  client: FnHttpClient,
  rawName: string,
  photoIds: string[]
): Promise<boolean> {
  ensureCacheOwner();
  const name = normalizeAlbumName(rawName);
  if (name.length === 0 || photoIds.length === 0) {
    return true;
  }
  const albumId = await ensureNasAlbumId(client, name);
  if (albumId.length === 0) {
    return false;
  }
  const res = await client.addPhotosToUserAlbum(albumId, name, photoIds);
  if (!res.success) {
    // 不记相册名与 albumId。
    hilog.info(DOMAIN, TAG, 'addTo album failed count=%{public}d msg=%{public}s',
      photoIds.length, res.message ?? '');
    albumIdCache.delete(name);
    return false;
  }
  hilog.info(DOMAIN, TAG, 'archived count=%{public}d', photoIds.length);
  return true;
}
