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

function toLocalPhotoEntry(asset: photoAccessHelper.PhotoAsset): LocalPhotoEntry {
  return {
    uri: asset.uri,
    fileName: asset.displayName ?? '',
    fileSize: photoAssetFileSize(asset),
    dateModifiedMs: photoAssetDateModifiedMs(asset),
    mimeType: ''
  };
}

/**
 * 查询本地相册中的图片和视频。
 * 使用 predicates.limit + 游标迭代，避免 getAllObjects 全量拉齐再截断。
 * @param ctx UIAbilityContext
 * @param limit 最大返回条数（默认 500）
 */
export async function queryLocalPhotos(
  ctx: common.UIAbilityContext,
  limit: number = 500
): Promise<LocalPhotoEntry[]> {
  let fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
    const safeLimit: number = Math.max(1, Math.floor(limit));
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.orderByDesc(photoAccessHelper.PhotoKeys.DATE_MODIFIED);
    predicates.limit(safeLimit, 0);
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
    const total: number = fetchResult.getCount();
    const want: number = Math.min(Math.max(0, total), safeLimit);
    const entries: LocalPhotoEntry[] = [];
    if (want <= 0) {
      hilog.info(DOMAIN, TAG, 'queryLocalPhotos count=0 limit=%{public}d', safeLimit);
      return entries;
    }
    // 游标迭代：只物化前 want 条，避免 getAllObjects 全库进内存
    let asset: photoAccessHelper.PhotoAsset = await fetchResult.getFirstObject();
    entries.push(toLocalPhotoEntry(asset));
    for (let i = 1; i < want; i++) {
      if (fetchResult.isAfterLast()) {
        break;
      }
      asset = await fetchResult.getNextObject();
      entries.push(toLocalPhotoEntry(asset));
    }
    hilog.info(
      DOMAIN,
      TAG,
      'queryLocalPhotos count=%{public}d total=%{public}d limit=%{public}d',
      entries.length,
      total,
      safeLimit
    );
    return entries;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'queryLocalPhotos failed: %{public}s', String(e));
    return [];
  } finally {
    if (fetchResult !== undefined) {
      try {
        fetchResult.close();
      } catch (_e) {
      }
    }
  }
}
