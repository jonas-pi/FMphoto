/**
 * 备份源 = 系统图库「来源文件夹」（相机 / 微信 / 截图 / 屏幕录制等）。
 * 只用 AlbumType.SOURCE，不混入「全部图片 / 收藏 / 视频」等虚拟系统相册。
 */
import { common } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  fnEnsureReadImageVideoGranted,
  fnRequestReadImageVideoAccess,
  FnReadImageVideoAuth
} from '../common/FnMediaPermission';

const DOMAIN = 0xFF00;
const TAG = 'BackupSources';

export class LocalAlbumSummary {
  name: string = '';
  albumUri: string = '';
  lpath: string = '';
  totalCount: number = 0;
  imageCount: number = 0;
  videoCount: number = 0;
  coverAssetUri: string = '';
  isCameraAlbum: boolean = false;
  isSourceAlbum: boolean = false;
}

export class LocalBackupSourceScan {
  albums: LocalAlbumSummary[] = [];
  auth: FnReadImageVideoAuth = FnReadImageVideoAuth.DENIED;
}

function tailPathSegment(path: string): string {
  const normalized = path.replace(/\\/g, '/').trim();
  if (normalized.length === 0) {
    return '';
  }
  const slash = normalized.lastIndexOf('/');
  if (slash >= 0 && slash < normalized.length - 1) {
    return normalized.substring(slash + 1);
  }
  return normalized;
}

function isTechnicalLabel(text: string): boolean {
  const t = text.trim();
  if (t.length === 0) {
    return true;
  }
  if (t.indexOf('file://') >= 0 || t.indexOf('albumName://') >= 0) {
    return true;
  }
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-/i.test(t)) {
    return true;
  }
  if (/^\d+$/.test(t)) {
    return true;
  }
  return false;
}

function compactToken(raw: string): string {
  return raw.trim().toLowerCase().replace(/[_\-\s.\\/]+/g, '');
}

/** 来源目录英文名 / 路径末段 → 与官方备份客户端一致的中文文件夹名 */
function canonicalFolderName(raw: string): string {
  const n = raw.trim();
  if (n.length === 0) {
    return '';
  }
  const basis = n.indexOf('/') >= 0 ? tailPathSegment(n) : n;
  const probe = compactToken(basis);
  const blob = compactToken(n);
  if (probe === 'camera' || probe === '100media' || blob.endsWith('dcimcamera')) {
    return '相机';
  }
  if (probe === 'screenshot' || probe === 'screenshots' || probe === '截屏' || blob.indexOf('screenshot') >= 0) {
    return '截图';
  }
  if (probe.indexOf('screenrecord') >= 0 || blob.indexOf('screenrecord') >= 0 ||
    probe === '录屏' || n.indexOf('屏幕录制') >= 0 || n.indexOf('录屏') >= 0) {
    return '屏幕录制';
  }
  if (probe === 'weixin' || probe === 'wechat' || probe === 'micromsg' ||
    blob.indexOf('weixin') >= 0 || blob.indexOf('wechat') >= 0 || blob.indexOf('micromsg') >= 0 ||
    blob.indexOf('comtencentmm') >= 0) {
    return '微信';
  }
  if (probe === 'huaweishare' || probe === 'hwshare' || probe === 'hishare' ||
    blob.indexOf('huaweishare') >= 0 || blob.indexOf('instantshare') >= 0 || n.indexOf('华为分享') >= 0) {
    return '华为分享';
  }
  return basis;
}

function isKnownSourceFolder(name: string): boolean {
  return name === '相机' || name === '截图' || name === '屏幕录制' || name === '微信' || name === '华为分享';
}

function isUsableFolderName(name: string): boolean {
  return name.length > 0 && !isTechnicalLabel(name) && !isVirtualAlbumName(name);
}

/** 相册名和路径里，优先采用能对上官方来源文件夹的那个 */
function resolvedFolderName(albumName: string, lpath: string): string {
  const fromName = canonicalFolderName(albumName);
  const fromPath = canonicalFolderName(lpath);
  if (isUsableFolderName(fromPath) && isKnownSourceFolder(fromPath) && !isKnownSourceFolder(fromName)) {
    return fromPath;
  }
  if (isUsableFolderName(fromName)) {
    return fromName;
  }
  if (isUsableFolderName(fromPath)) {
    return fromPath;
  }
  return '';
}

function isVirtualAlbumName(name: string): boolean {
  const n = name.trim();
  if (n.length === 0 || n === '未命名文件夹') {
    return true;
  }
  const blocked: string[] = [
    '全部', '所有照片', '所有图片', '全部图片', '最近项目', '最近添加', '收藏', '视频', '图片',
    '回收站', '最近删除', '隐藏', '隐藏相册', '人像', '地点', '事物', '卡证',
    'all', 'favorites', 'videos', 'images', 'camera roll'
  ];
  const lower = n.toLowerCase();
  for (let i = 0; i < blocked.length; i++) {
    if (n === blocked[i] || lower === blocked[i]) {
      return true;
    }
  }
  return false;
}

function isCameraAlbumName(name: string): boolean {
  return canonicalFolderName(name) === '相机';
}

function refreshCameraFlag(row: LocalAlbumSummary): void {
  const byName = isCameraAlbumName(row.name);
  const path = row.lpath.replace(/\\/g, '/').toLowerCase();
  const byPath = path.endsWith('/dcim/camera') || path.endsWith('/camera');
  row.isCameraAlbum = byName || byPath;
}

export function displayAlbumFolderName(album: LocalAlbumSummary): string {
  const resolved = resolvedFolderName(album.name, album.lpath);
  if (resolved.length > 0) {
    return resolved;
  }
  return '未命名文件夹';
}

export function albumBackupMergeKey(album: LocalAlbumSummary): string {
  if (album.lpath.length > 0) {
    return album.lpath;
  }
  if (album.albumUri.length > 0) {
    return album.albumUri;
  }
  return `albumName://${displayAlbumFolderName(album)}`;
}

function albumTotalCount(album: photoAccessHelper.Album): number {
  const base = Number(album.count);
  if (Number.isFinite(base) && base > 0) {
    return Math.floor(base);
  }
  const images = Number(album.imageCount ?? 0);
  const videos = Number(album.videoCount ?? 0);
  const parts = (Number.isFinite(images) ? images : 0) + (Number.isFinite(videos) ? videos : 0);
  if (parts > 0) {
    return Math.floor(parts);
  }
  if ((album.coverUri ?? '').trim().length > 0) {
    return 1;
  }
  return 0;
}

function readLpath(album: photoAccessHelper.Album): string {
  try {
    const value = album.lpath;
    if (value === undefined) {
      return '';
    }
    return value.trim();
  } catch (_e) {
    return '';
  }
}

class AlbumFieldSnap {
  name: string = '';
  albumUri: string = '';
  lpath: string = '';
  totalCount: number = 0;
  imageCount: number = 0;
  videoCount: number = 0;
  coverAssetUri: string = '';
  subtype: photoAccessHelper.AlbumSubtype = photoAccessHelper.AlbumSubtype.USER_GENERIC;
}

function snapFromAlbum(album: photoAccessHelper.Album): AlbumFieldSnap {
  const snap = new AlbumFieldSnap();
  snap.name = (album.albumName ?? '').trim();
  snap.albumUri = (album.albumUri ?? '').trim();
  snap.lpath = readLpath(album);
  snap.totalCount = albumTotalCount(album);
  snap.imageCount = Math.floor(album.imageCount ?? 0);
  snap.videoCount = Math.floor(album.videoCount ?? 0);
  snap.coverAssetUri = (album.coverUri ?? '').trim();
  snap.subtype = album.albumSubtype;
  return snap;
}

function mergeSnap(base: AlbumFieldSnap, extra: AlbumFieldSnap): void {
  const baseResolved = resolvedFolderName(base.name, base.lpath);
  const extraResolved = resolvedFolderName(extra.name, extra.lpath);
  if (extraResolved.length > 0 && (baseResolved.length === 0 ||
    (isKnownSourceFolder(extraResolved) && !isKnownSourceFolder(baseResolved)))) {
    base.name = extra.name.length > 0 ? extra.name : extraResolved;
    if (extra.lpath.length > 0) {
      base.lpath = extra.lpath;
    }
  } else if (base.lpath.length === 0 && extra.lpath.length > 0) {
    base.lpath = extra.lpath;
  }
  if (base.name.length === 0 && extra.name.length > 0) {
    base.name = extra.name;
  }
  if (base.totalCount <= 0 && extra.totalCount > 0) {
    base.totalCount = extra.totalCount;
  }
  if (base.coverAssetUri.length === 0 && extra.coverAssetUri.length > 0) {
    base.coverAssetUri = extra.coverAssetUri;
  }
  if (base.imageCount <= 0 && extra.imageCount > 0) {
    base.imageCount = extra.imageCount;
  }
  if (base.videoCount <= 0 && extra.videoCount > 0) {
    base.videoCount = extra.videoCount;
  }
}

function rowFromSnap(snap: AlbumFieldSnap, isSource: boolean): LocalAlbumSummary | undefined {
  if (snap.totalCount <= 0) {
    hilog.info(DOMAIN, TAG, 'drop empty count name=%{public}s lpath=%{public}s', snap.name, snap.lpath);
    return undefined;
  }
  if (snap.subtype === photoAccessHelper.AlbumSubtype.FAVORITE ||
    snap.subtype === photoAccessHelper.AlbumSubtype.VIDEO ||
    snap.subtype === photoAccessHelper.AlbumSubtype.IMAGE) {
    return undefined;
  }
  const row = new LocalAlbumSummary();
  row.lpath = snap.lpath;
  row.name = resolvedFolderName(snap.name, snap.lpath);
  if (row.name.length === 0) {
    row.name = canonicalFolderName(snap.name);
  }
  row.albumUri = snap.albumUri;
  row.totalCount = snap.totalCount;
  row.imageCount = snap.imageCount;
  row.videoCount = snap.videoCount;
  row.coverAssetUri = snap.coverAssetUri;
  row.isSourceAlbum = isSource;
  refreshCameraFlag(row);
  const shown = displayAlbumFolderName(row);
  if (isVirtualAlbumName(shown)) {
    hilog.info(DOMAIN, TAG, 'drop virtual name=%{public}s raw=%{public}s lpath=%{public}s count=%{public}d',
      shown, snap.name, snap.lpath, snap.totalCount);
    return undefined;
  }
  if (row.albumUri.length === 0 && row.lpath.length === 0 && row.name.length === 0) {
    return undefined;
  }
  return row;
}

async function readAlbumObjects(
  helper: photoAccessHelper.PhotoAccessHelper,
  albumType: photoAccessHelper.AlbumType,
  albumSubtype: photoAccessHelper.AlbumSubtype,
  options: photoAccessHelper.FetchOptions | undefined
): Promise<photoAccessHelper.Album[]> {
  let albumFetch: photoAccessHelper.FetchResult<photoAccessHelper.Album> | undefined = undefined;
  try {
    if (options === undefined) {
      albumFetch = await helper.getAlbums(albumType, albumSubtype);
    } else {
      albumFetch = await helper.getAlbums(albumType, albumSubtype, options);
    }
    const albums = await albumFetch.getAllObjects();
    hilog.info(DOMAIN, TAG, 'getAlbums type=%{public}d sub=%{public}d n=%{public}d columns=%{public}s',
      albumType, albumSubtype, albums.length, options === undefined ? 'default' : 'named');
    return albums;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'getAlbums type=%{public}d sub=%{public}d %{public}s', albumType, albumSubtype, String(e));
    return [];
  } finally {
    albumFetch?.close();
  }
}

function labelFetchOptions(): photoAccessHelper.FetchOptions {
  const predicates = new dataSharePredicates.DataSharePredicates();
  const options: photoAccessHelper.FetchOptions = {
    fetchColumns: [
      photoAccessHelper.AlbumKeys.URI,
      photoAccessHelper.AlbumKeys.ALBUM_NAME,
      photoAccessHelper.AlbumKeys.ALBUM_LPATH,
      'count',
      'cover_uri',
      'image_count',
      'video_count'
    ],
    predicates: predicates
  };
  return options;
}

async function fetchAlbumCombo(
  helper: photoAccessHelper.PhotoAccessHelper,
  albumType: photoAccessHelper.AlbumType,
  albumSubtype: photoAccessHelper.AlbumSubtype,
  isSource: boolean
): Promise<LocalAlbumSummary[]> {
  const out: LocalAlbumSummary[] = [];
  const baseAlbums = await readAlbumObjects(helper, albumType, albumSubtype, undefined);
  const namedAlbums = await readAlbumObjects(helper, albumType, albumSubtype, labelFetchOptions());
  const byUri = new Map<string, AlbumFieldSnap>();
  const order: string[] = [];
  const absorb = (album: photoAccessHelper.Album, index: number): void => {
    const snap = snapFromAlbum(album);
    const key = snap.albumUri.length > 0 ? snap.albumUri : `idx-${index}-${snap.name}`;
    const prev = byUri.get(key);
    if (prev === undefined) {
      byUri.set(key, snap);
      order.push(key);
      return;
    }
    mergeSnap(prev, snap);
  };
  for (let i = 0; i < baseAlbums.length; i++) {
    absorb(baseAlbums[i], i);
  }
  for (let i = 0; i < namedAlbums.length; i++) {
    absorb(namedAlbums[i], baseAlbums.length + i);
  }
  for (let i = 0; i < order.length; i++) {
    const snap = byUri.get(order[i]);
    if (snap === undefined) {
      continue;
    }
    hilog.info(DOMAIN, TAG,
      'raw name=%{public}s lpath=%{public}s count=%{public}d cover=%{public}s source=%{public}s',
      snap.name, snap.lpath, snap.totalCount, snap.coverAssetUri.length > 0 ? '1' : '0', isSource ? '1' : '0');
    try {
      const row = rowFromSnap(snap, isSource);
      if (row !== undefined) {
        hilog.info(DOMAIN, TAG, 'keep name=%{public}s lpath=%{public}s count=%{public}d',
          displayAlbumFolderName(row), row.lpath, row.totalCount);
        out.push(row);
      }
    } catch (itemErr) {
      hilog.warn(DOMAIN, TAG, 'skip album %{public}s', String(itemErr));
    }
  }
  return out;
}

function dedupePreferSource(rows: LocalAlbumSummary[]): LocalAlbumSummary[] {
  const byName = new Map<string, LocalAlbumSummary>();
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const name = displayAlbumFolderName(row);
    if (isVirtualAlbumName(name)) {
      continue;
    }
    const prev = byName.get(name);
    if (prev === undefined) {
      byName.set(name, row);
      continue;
    }
    if (row.isSourceAlbum && !prev.isSourceAlbum) {
      byName.set(name, row);
      continue;
    }
    if (row.isSourceAlbum === prev.isSourceAlbum && row.totalCount > prev.totalCount) {
      byName.set(name, row);
    }
  }
  const out: LocalAlbumSummary[] = [];
  byName.forEach((value: LocalAlbumSummary): void => {
    out.push(value);
  });
  out.sort((a: LocalAlbumSummary, b: LocalAlbumSummary): number => {
    if (a.isCameraAlbum !== b.isCameraAlbum) {
      return a.isCameraAlbum ? -1 : 1;
    }
    return displayAlbumFolderName(a).localeCompare(displayAlbumFolderName(b));
  });
  return out;
}

async function fetchBackupSourceAlbums(helper: photoAccessHelper.PhotoAccessHelper): Promise<LocalAlbumSummary[]> {
  const sourceRows = await fetchAlbumCombo(
    helper,
    photoAccessHelper.AlbumType.SOURCE,
    photoAccessHelper.AlbumSubtype.SOURCE_GENERIC,
    true
  );
  const sourceAnyRows = await fetchAlbumCombo(
    helper,
    photoAccessHelper.AlbumType.SOURCE,
    photoAccessHelper.AlbumSubtype.ANY,
    true
  );
  const userRows = await fetchAlbumCombo(
    helper,
    photoAccessHelper.AlbumType.USER,
    photoAccessHelper.AlbumSubtype.ANY,
    false
  );
  const systemRows = await fetchAlbumCombo(
    helper,
    photoAccessHelper.AlbumType.SYSTEM,
    photoAccessHelper.AlbumSubtype.ANY,
    false
  );
  const merged = dedupePreferSource(sourceRows.concat(sourceAnyRows).concat(userRows).concat(systemRows));
  hilog.info(DOMAIN, TAG, 'backup sources=%{public}d', merged.length);
  return merged;
}

export async function scanLocalBackupSourceAlbums(
  ctx: common.UIAbilityContext,
  requestIfNeeded: boolean = true
): Promise<LocalBackupSourceScan> {
  const result = new LocalBackupSourceScan();
  const auth = requestIfNeeded
    ? await fnRequestReadImageVideoAccess(ctx)
    : (await fnEnsureReadImageVideoGranted(ctx) ? FnReadImageVideoAuth.GRANTED : FnReadImageVideoAuth.DENIED);
  result.auth = auth;
  if (auth !== FnReadImageVideoAuth.GRANTED) {
    return result;
  }
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
    result.albums = await fetchBackupSourceAlbums(helper);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'scan failed %{public}s', String(e));
    result.auth = FnReadImageVideoAuth.ERROR;
  }
  return result;
}

export async function listLocalBackupSourceAlbums(ctx: common.UIAbilityContext): Promise<LocalAlbumSummary[]> {
  const scan = await scanLocalBackupSourceAlbums(ctx, true);
  return scan.albums;
}
