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
import { fnDiagRecord } from '../common/FnDiagLog';

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
export function canonicalFolderName(raw: string): string {
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

/** 逐页列出某个来源相册里的照片 URI，用于建立「照片 → 来源相册名」索引。 */
function albumAssetPageOptions(offset: number, limit: number): photoAccessHelper.FetchOptions {
  const predicates = new dataSharePredicates.DataSharePredicates();
  predicates.limit(limit, offset);
  // 必须取全列：只取 URI 时读取 displayName/size 会抛 member not exist
  const options: photoAccessHelper.FetchOptions = {
    fetchColumns: [
      photoAccessHelper.PhotoKeys.URI,
      photoAccessHelper.PhotoKeys.DISPLAY_NAME,
      photoAccessHelper.PhotoKeys.SIZE,
      photoAccessHelper.PhotoKeys.DATE_MODIFIED,
      photoAccessHelper.PhotoKeys.DATE_MODIFIED_MS,
      photoAccessHelper.PhotoKeys.DATE_TAKEN,
      photoAccessHelper.PhotoKeys.DATE_TAKEN_MS,
      photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE
    ],
    predicates: predicates
  };
  return options;
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

/* ---------- 本机媒体字段读取（相册层与扫描共用） ---------- */

export function photoAssetFileSize(asset: photoAccessHelper.PhotoAsset): number {
  try {
    const raw = asset.get(photoAccessHelper.PhotoKeys.SIZE);
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      return raw;
    }
    if (typeof raw === 'string') {
      const parsed = Number(raw);
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
  } catch (_e) {
    // 没取到 size 时按 0 处理，不影响是否同步
  }
  return 0;
}

export function photoAssetDateModifiedMs(asset: photoAccessHelper.PhotoAsset): number {
  try {
    const raw = asset.get(photoAccessHelper.PhotoKeys.DATE_MODIFIED_MS);
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      return raw;
    }
    if (typeof raw === 'string') {
      const parsed = Number(raw);
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
    const sec = asset.get(photoAccessHelper.PhotoKeys.DATE_MODIFIED);
    if (typeof sec === 'number' && Number.isFinite(sec)) {
      return sec * 1000;
    }
  } catch (_e) {
    // 没取到时间时按 0 处理
  }
  return 0;
}

/**
 * 拍摄时间，统一成毫秒。
 * DATE_TAKEN_MS 文档单位是毫秒；DATE_TAKEN 有的系统给毫秒、有的给秒。
 * 1e12 以上（约 2001 年之后的毫秒）原样使用，更小的正数按秒换算。
 * 读不到时返回 0，调用方不得用修改时间或当前时间填目录。
 */
function takenStampToMs(raw: number): number {
  if (raw >= 1e12) {
    return raw;
  }
  return raw * 1000;
}

function readPositiveNumber(raw: number | string | boolean): number {
  if (typeof raw === 'number' && Number.isFinite(raw) && raw > 0) {
    return raw;
  }
  if (typeof raw === 'string') {
    const parsed = Number(raw);
    if (Number.isFinite(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return 0;
}

export function photoAssetDateTakenMs(asset: photoAccessHelper.PhotoAsset): number {
  try {
    const ms = readPositiveNumber(asset.get(photoAccessHelper.PhotoKeys.DATE_TAKEN_MS));
    if (ms > 0) {
      return takenStampToMs(ms);
    }
  } catch (_e) {
    // 列不存在时继续读 DATE_TAKEN
  }
  try {
    const taken = readPositiveNumber(asset.get(photoAccessHelper.PhotoKeys.DATE_TAKEN));
    if (taken > 0) {
      return takenStampToMs(taken);
    }
  } catch (_e) {
    fnDiagRecord('W', TAG, 'photo taken time read failed');
  }
  return 0;
}

export function photoAssetSubtype(asset: photoAccessHelper.PhotoAsset): number {
  try {
    const raw = asset.get(photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE);
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      return raw;
    }
    if (typeof raw === 'string') {
      const parsed = Number(raw);
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
  } catch (_e) {
    // 读不到 subtype 时实况照片会被当成普通图处理。
    fnDiagRecord('W', TAG, 'photo subtype read failed');
  }
  return photoAccessHelper.PhotoSubtype.DEFAULT;
}

/** 扫描到的一条本机媒体（连同它所属的来源相册）。 */
export class LocalSourcePhoto {
  uri: string = '';
  fileName: string = '';
  fileSize: number = 0;
  dateModifiedMs: number = 0;
  /** 拍摄时间（毫秒）。0 表示系统没给拍摄时间，目录模式不得改用修改时间。 */
  dateTakenMs: number = 0;
  photoSubtype: number = 0;
  /** 所属相册名（相机 / 微信 / 截图…） */
  albumName: string = '';
  /** 所属相册的设备内路径，如 /DCIM/Camera */
  albumPath: string = '';
  /** 所属相册的合并键（与「备份源」列表里的值一致） */
  albumKey: string = '';
}

/**
 * 只扫描「备份源」里选中的相册。
 *
 * 备份源决定扫描范围：选中的相册之外的文件根本不会被枚举，
 * 因此既不会进入「新媒体」判定，也不会被上传。
 * selectedKeys 为空表示「备份所有文件夹」，此时返回空数组，由调用方改用全库扫描。
 */
export class LocalSourceScanResult {
  photos: LocalSourcePhoto[] = [];
  /** 真正枚举过的相册数（用于区分「备份源一个都没对上」与「相册是空的」） */
  albumsScanned: number = 0;
  /** 读图权限是否具备 */
  granted: boolean = true;
  /** 扫描过程中是否出错（异常 / 相册信息缺失），出错时不能当成「没有可同步项目」 */
  failed: boolean = false;
  /** 选中的 key 中有多少在当前本机相册里找不到 */
  missingKeys: number = 0;
}

export async function scanLocalBackupSourcePhotos(
  ctx: common.UIAbilityContext,
  selectedKeys: string[],
  onLoaded: ((count: number) => void) | null = null
): Promise<LocalSourceScanResult> {
  const result = new LocalSourceScanResult();
  if (selectedKeys.length === 0) {
    return result;
  }
  const wanted = new Set<string>(selectedKeys);
  const seenUri: Set<string> = new Set<string>();
  const matchedKeys: Set<string> = new Set<string>();
  try {
    const granted = await fnEnsureReadImageVideoGranted(ctx);
    if (!granted) {
      result.granted = false;
      result.failed = true;
      fnDiagRecord('W', TAG, 'source scan skipped: no permission');
      return result;
    }
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
    // 相册的合并信息（key/名字/路径）与选择页保持一致：按 albumUri 索引
    const merged = await fetchBackupSourceAlbums(helper);
    const infoByUri: Map<string, LocalAlbumSummary> = new Map<string, LocalAlbumSummary>();
    for (let i = 0; i < merged.length; i++) {
      const uri = (merged[i].albumUri ?? '').trim();
      if (uri.length > 0 && !infoByUri.has(uri)) {
        infoByUri.set(uri, merged[i]);
      }
    }
    // 原始 Album 对象用于枚举资源
    const rawCombos: Array<[photoAccessHelper.AlbumType, photoAccessHelper.AlbumSubtype]> = [
      [photoAccessHelper.AlbumType.SOURCE, photoAccessHelper.AlbumSubtype.SOURCE_GENERIC],
      [photoAccessHelper.AlbumType.SOURCE, photoAccessHelper.AlbumSubtype.ANY],
      [photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumSubtype.ANY],
      [photoAccessHelper.AlbumType.SYSTEM, photoAccessHelper.AlbumSubtype.ANY]
    ];
    const scannedAlbums: Set<string> = new Set<string>();
    let albumCount = 0;
    for (let c = 0; c < rawCombos.length; c++) {
      const rawAlbums = await readAlbumObjects(helper, rawCombos[c][0], rawCombos[c][1], undefined);
      for (let i = 0; i < rawAlbums.length; i++) {
        const album = rawAlbums[i];
        const albumUri = (album.albumUri ?? '').trim();
        // albumUri 可能取不到：此时用相册自身的快照兜底，避免选中的相册被整体跳过
        const row: LocalAlbumSummary | undefined =
          albumUri.length > 0 ? infoByUri.get(albumUri) : rowFromSnap(snapFromAlbum(album), true);
        const dedupeKey = albumUri.length > 0
          ? albumUri
          : (row !== undefined ? `${row.name}|${row.lpath}` : `idx-${c}-${i}`);
        if (scannedAlbums.has(dedupeKey)) {
          continue;
        }
        if (row === undefined) {
          continue;
        }
        const name = displayAlbumFolderName(row);
        if (name.length === 0 || isVirtualAlbumName(name)) {
          continue;
        }
        const key = albumBackupMergeKey(row);
        if (!wanted.has(key)) {
          // 备份源之外的相册：整个相册都不扫
          continue;
        }
        matchedKeys.add(key);
        scannedAlbums.add(dedupeKey);
        albumCount++;
        const lpath = (row.lpath ?? '').trim();
        let offset = 0;
        let firstUri = '';
        while (true) {
          let page: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
          try {
            page = await album.getAssets(albumAssetPageOptions(offset, 500));
            const assets = await page.getAllObjects();
            if (assets.length === 0) {
              break;
            }
            // offset 被忽略时会一直返回第一页，这里必须停，否则死循环
            const headUri = (assets[0].uri ?? '').trim();
            if (offset > 0 && headUri.length > 0 && headUri === firstUri) {
              hilog.warn(DOMAIN, TAG, 'getAssets offset ignored at %{public}d', offset);
              break;
            }
            if (offset === 0) {
              firstUri = headUri;
            }
            for (let j = 0; j < assets.length; j++) {
              const oneUri = (assets[j].uri ?? '').trim();
              if (oneUri.length === 0) {
                continue;
              }
              // 同一张照片可能同时属于多个已选相册：按 URI 去重，避免重复上传/落两个目录
              if (seenUri.has(oneUri)) {
                continue;
              }
              seenUri.add(oneUri);
              const p = new LocalSourcePhoto();
              p.uri = oneUri;
              p.fileName = assets[j].displayName ?? '';
              p.fileSize = photoAssetFileSize(assets[j]);
              p.dateModifiedMs = photoAssetDateModifiedMs(assets[j]);
              p.dateTakenMs = photoAssetDateTakenMs(assets[j]);
              p.photoSubtype = photoAssetSubtype(assets[j]);
              p.albumName = name;
              p.albumPath = lpath;
              p.albumKey = key;
              result.photos.push(p);
            }
            if (assets.length < 500) {
              break;
            }
            offset += assets.length;
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'source album assets failed %{public}s', String(e));
            result.failed = true;
            break;
          } finally {
            page?.close();
          }
        }
        if (onLoaded !== null) {
          onLoaded(result.photos.length);
        }
      }
    }
    result.albumsScanned = albumCount;
    for (let i = 0; i < selectedKeys.length; i++) {
      if (!matchedKeys.has(selectedKeys[i])) {
        result.missingKeys++;
      }
    }
    hilog.info(DOMAIN, TAG, 'source scan photos=%{public}d albums=%{public}d missing=%{public}d',
      result.photos.length, albumCount, result.missingKeys);
    fnDiagRecord('I', 'AlbumBackup', 'source scan photos=' + String(result.photos.length) +
      ' albums=' + String(albumCount) + ' missing=' + String(result.missingKeys) +
      ' failed=' + (result.failed ? '1' : '0'));
    return result;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'source scan failed %{public}s', String(e));
    fnDiagRecord('W', TAG, `source scan failed ${String(e).substring(0, 90)}`);
    result.failed = true;
    return result;
  }
}

/** 一个来源相册的引用信息。 */
export class LocalAlbumRef {
  /** 显示名（相机 / 微信 / 截图…），建同名相册用 */
  name: string = '';
  /** 合并键：与「备份源」列表里存的值一致（lpath / albumUri / albumName://x） */
  key: string = '';
  /** 设备内路径，如 /DCIM/Camera；「按设备文件夹」目录模式用它拼目标目录 */
  lpath: string = '';
}

/**
 * 建立「照片 uri → 来源相册引用」映射。
 * 一次遍历同时给出三样东西：
 * - name：建 NAS 同名相册；
 * - key：按「备份源」筛选；
 * - lpath：按设备文件夹摆放时拼目标目录。
 * 读不到权限或没有来源相册时返回空表。
 */
export async function buildLocalAlbumRefIndex(ctx: common.UIAbilityContext): Promise<Map<string, LocalAlbumRef>> {
  const index: Map<string, LocalAlbumRef> = new Map<string, LocalAlbumRef>();
  try {
    const granted = await fnEnsureReadImageVideoGranted(ctx);
    if (!granted) {
      hilog.info(DOMAIN, TAG, 'album ref index skipped: no permission');
      fnDiagRecord('W', TAG, 'no permission, album ref index skipped');
      return index;
    }
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
    const albums = await readAlbumObjects(
      helper,
      photoAccessHelper.AlbumType.SOURCE,
      photoAccessHelper.AlbumSubtype.SOURCE_GENERIC,
      undefined
    );
    for (let i = 0; i < albums.length; i++) {
      const row = rowFromSnap(snapFromAlbum(albums[i]), true);
      if (row === undefined) {
        continue;
      }
      const name = displayAlbumFolderName(row);
      if (name.length === 0 || isVirtualAlbumName(name)) {
        continue;
      }
      const ref = new LocalAlbumRef();
      ref.name = name;
      ref.key = albumBackupMergeKey(row);
      ref.lpath = (row.lpath ?? '').trim();
      let offset = 0;
      while (true) {
        let page: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
        try {
          page = await albums[i].getAssets(albumAssetPageOptions(offset, 500));
          const assets = await page.getAllObjects();
          for (let j = 0; j < assets.length; j++) {
            const uri = (assets[j].uri ?? '').trim();
            if (uri.length > 0) {
              index.set(uri, ref);
            }
          }
          if (assets.length < 500) {
            break;
          }
          offset += assets.length;
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'album assets failed %{public}s', String(e));
          break;
        } finally {
          page?.close();
        }
      }
    }
    hilog.info(DOMAIN, TAG, 'album ref index albums=%{public}d photos=%{public}d', albums.length, index.size);
    return index;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'album ref index failed %{public}s', String(e));
    return index;
  }
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
    hilog.info(DOMAIN, TAG, 'drop empty count album');
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
    hilog.info(DOMAIN, TAG, 'drop virtual album count=%{public}d', snap.totalCount);
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
  if (options === undefined) {
    const base = await readAlbumObjectsWith(helper, albumType, albumSubtype, undefined);
    return base === null ? [] : base;
  }
  // 部分系统版本对列集里的 ALBUM_LPATH 报 invalid parameter，逐级降列重试
  const attempts: photoAccessHelper.FetchOptions[] = [
    options,
    labelFetchOptionsNoLpath(),
    labelFetchOptionsCountOnly()
  ];
  for (let i = 0; i < attempts.length; i++) {
    const albums = await readAlbumObjectsWith(helper, albumType, albumSubtype, attempts[i]);
    if (albums !== null) {
      return albums;
    }
    hilog.info(DOMAIN, TAG, 'getAlbums fallback attempt=%{public}d', i + 1);
  }
  return [];
}

async function readAlbumObjectsWith(
  helper: photoAccessHelper.PhotoAccessHelper,
  albumType: photoAccessHelper.AlbumType,
  albumSubtype: photoAccessHelper.AlbumSubtype,
  options: photoAccessHelper.FetchOptions | undefined
): Promise<photoAccessHelper.Album[] | null> {
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
    return null;
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

/** 降级 1：去掉 ALBUM_LPATH（部分系统版本不认这一列，报 invalid parameter）。 */
function labelFetchOptionsNoLpath(): photoAccessHelper.FetchOptions {
  const predicates = new dataSharePredicates.DataSharePredicates();
  const options: photoAccessHelper.FetchOptions = {
    fetchColumns: [
      photoAccessHelper.AlbumKeys.URI,
      photoAccessHelper.AlbumKeys.ALBUM_NAME,
      'count',
      'cover_uri',
      'image_count',
      'video_count'
    ],
    predicates: predicates
  };
  return options;
}

/** 降级 2：只取计数（连 name/lpath 都不带），靠 albumUri 与其它快照合并。 */
function labelFetchOptionsCountOnly(): photoAccessHelper.FetchOptions {
  const predicates = new dataSharePredicates.DataSharePredicates();
  const options: photoAccessHelper.FetchOptions = {
    fetchColumns: [
      'count',
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
      'raw album count=%{public}d cover=%{public}s source=%{public}s',
      snap.totalCount, snap.coverAssetUri.length > 0 ? '1' : '0', isSource ? '1' : '0');
    try {
      const row = rowFromSnap(snap, isSource);
      if (row !== undefined) {
        hilog.info(DOMAIN, TAG, 'keep album count=%{public}d', row.totalCount);
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
