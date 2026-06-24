/**
 * 本地系统相册查询服务。
 * 利用 photoAccessHelper 查询本机相册中的图片/视频元数据，
 * 用于与 NAS 时间线对比实现「前台增量同步」。
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


/**
 * 查询本地相册中的图片和视频。
 * @param ctx UIAbilityContext
 * @param limit 最大返回条数（默认 500，避免首次查询过慢）
 */
export async function queryLocalPhotos(
  ctx: common.UIAbilityContext,
  limit: number = 500
): Promise<LocalPhotoEntry[]> {
  let fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> | undefined = undefined;
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.orderByDesc(photoAccessHelper.PhotoKeys.DATE_MODIFIED);
    const fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: [
        photoAccessHelper.PhotoKeys.URI,
        photoAccessHelper.PhotoKeys.DISPLAY_NAME,
        photoAccessHelper.PhotoKeys.SIZE,
        photoAccessHelper.PhotoKeys.DATE_MODIFIED,
        photoAccessHelper.PhotoKeys.DATE_MODIFIED_MS
      ],
      predicates: predicates
    };
    fetchResult = await helper.getAssets(fetchOptions);
    const assets: photoAccessHelper.PhotoAsset[] = await fetchResult.getAllObjects();
    const entries: LocalPhotoEntry[] = [];
    const count = Math.min(assets.length, limit);
    for (let i = 0; i < count; i++) {
      const asset = assets[i];
      entries.push({
        uri: asset.uri,
        fileName: asset.displayName ?? '',
        fileSize: photoAssetFileSize(asset),
        dateModifiedMs: photoAssetDateModifiedMs(asset),
        mimeType: ''
      });
    }
    hilog.info(DOMAIN, TAG, 'queryLocalPhotos count=%{public}d limit=%{public}d', entries.length, limit);
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
