/**
 * 本地系统相册查询（需 READ_IMAGEVIDEO ACL Profile + 用户授权）。
 */
import { common } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncSvc';

/** 本地相册条目（精简版，只保留同步所需字段） */
export interface LocalPhotoEntry {
  uri: string;
  fileName: string;
  fileSize: number;
  dateModifiedMs: number;
  mimeType: string;
  photoSubtype: number;
  /** 来源相册名（相机 / 微信 / 截图…），用于同步时在 NAS 建同名相册；空表示不归档 */
  sourceAlbumName: string;
}

/** PhotoKeys 没有「来源目录」字段，来源相册名由 AlbumBackupLocalSources 建索引后回填。 */
function sourceAlbumNamePlaceholder(): string {
  return '';
}

function photoAssetFileSize(asset: photoAccessHelper.PhotoAsset): number {
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
  return 0;
}

function photoAssetDateModifiedMs(asset: photoAccessHelper.PhotoAsset): number {
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
  return 0;
}

function photoAssetSubtype(asset: photoAccessHelper.PhotoAsset): number {
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
  }
  return photoAccessHelper.PhotoSubtype.DEFAULT;
}

function toLocalPhotoEntry(asset: photoAccessHelper.PhotoAsset): LocalPhotoEntry {
  return {
    uri: asset.uri,
    fileName: asset.displayName ?? '',
    fileSize: photoAssetFileSize(asset),
    dateModifiedMs: photoAssetDateModifiedMs(asset),
    mimeType: '',
    photoSubtype: photoAssetSubtype(asset),
    sourceAlbumName: sourceAlbumNamePlaceholder()
  };
}

const LOCAL_PHOTO_PAGE_SIZE: number = 400;

export interface LocalPhotoScanProgress {
  onLoaded(count: number): void;
}

async function queryLocalPhotoPage(
  ctx: common.UIAbilityContext,
  limit: number,
  offset: number
): Promise<LocalPhotoEntry[]> {
  let fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.orderByDesc(photoAccessHelper.PhotoKeys.DATE_MODIFIED);
    predicates.limit(limit, offset);
    const fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: [
        photoAccessHelper.PhotoKeys.URI,
        photoAccessHelper.PhotoKeys.DISPLAY_NAME,
        photoAccessHelper.PhotoKeys.SIZE,
        photoAccessHelper.PhotoKeys.DATE_MODIFIED,
        photoAccessHelper.PhotoKeys.DATE_MODIFIED_MS,
        photoAccessHelper.PhotoKeys.PHOTO_SUBTYPE
      ],
      predicates: predicates
    };
    fetchResult = await helper.getAssets(fetchOptions);
    if (fetchResult.getCount() <= 0) {
      return [];
    }
    const assets = await fetchResult.getAllObjects();
    const entries: LocalPhotoEntry[] = [];
    const count = Math.min(assets.length, limit);
    for (let i = 0; i < count; i++) {
      entries.push(toLocalPhotoEntry(assets[i]));
    }
    return entries;
  } finally {
    if (fetchResult !== undefined) {
      try {
        fetchResult.close();
      } catch (_e) {
      }
    }
  }
}

/**
 * 查询本机相册里的全部图片和视频。
 * 按页取，避免一次 getAllObjects 把整库放进内存。
 */
export async function queryLocalPhotos(
  ctx: common.UIAbilityContext,
  progress: LocalPhotoScanProgress | null = null
): Promise<LocalPhotoEntry[]> {
  const entries: LocalPhotoEntry[] = [];
  let offset = 0;
  try {
    while (true) {
      const page = await queryLocalPhotoPage(ctx, LOCAL_PHOTO_PAGE_SIZE, offset);
      if (page.length === 0) {
        break;
      }
      if (offset > 0 && page[0].uri === entries[0].uri) {
        hilog.warn(DOMAIN, TAG, 'queryLocalPhotos offset ignored at %{public}d', offset);
        break;
      }
      for (let i = 0; i < page.length; i++) {
        entries.push(page[i]);
      }
      offset += page.length;
      if (progress !== null) {
        progress.onLoaded(entries.length);
      }
      if (page.length < LOCAL_PHOTO_PAGE_SIZE) {
        break;
      }
      await new Promise<void>((resolve: () => void) => {
        setTimeout((): void => {
          resolve();
        }, 0);
      });
    }
    hilog.info(DOMAIN, TAG, 'queryLocalPhotos count=%{public}d', entries.length);
    return entries;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'queryLocalPhotos failed: %{public}s', String(e));
    return entries;
  }
}
