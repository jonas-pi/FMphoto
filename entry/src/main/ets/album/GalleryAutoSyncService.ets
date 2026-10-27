/**
 * 本地系统相册查询（需 READ_IMAGEVIDEO ACL Profile + 用户授权）。
 */
import { common } from '@kit.AbilityKit';
import { dataSharePredicates } from '@kit.ArkData';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagRecord } from '../common/FnDiagLog';
import {
  LocalSourcePhoto,
  photoAssetDateModifiedMs,
  photoAssetDateTakenMs,
  photoAssetFileSize,
  photoAssetSubtype,
  scanLocalBackupSourcePhotos
} from '../sync/AlbumBackupLocalSources';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncSvc';

/** 本地相册条目（精简版，只保留同步所需字段） */
export interface LocalPhotoEntry {
  uri: string;
  fileName: string;
  fileSize: number;
  dateModifiedMs: number;
  /** 拍摄时间（毫秒）。0 表示未知；「按拍摄日期」只用它，不用 dateModifiedMs。 */
  dateTakenMs: number;
  mimeType: string;
  photoSubtype: number;
  /** 来源相册名（相机 / 微信 / 截图…），用于同步时在 NAS 建同名相册；空表示不归档 */
  sourceAlbumName: string;
  /** 来源目录路径（如 /DCIM/Camera），用于「按设备文件夹」目录模式拼目标目录；空表示未知 */
  sourceAlbumPath: string;
}

/** PhotoKeys 没有「来源目录」字段，来源相册名由 AlbumBackupLocalSources 建索引后回填。 */
function sourceAlbumNamePlaceholder(): string {
  return '';
}

function toLocalPhotoEntry(asset: photoAccessHelper.PhotoAsset): LocalPhotoEntry {
  return {
    uri: asset.uri,
    fileName: asset.displayName ?? '',
    fileSize: photoAssetFileSize(asset),
    dateModifiedMs: photoAssetDateModifiedMs(asset),
    dateTakenMs: photoAssetDateTakenMs(asset),
    mimeType: '',
    photoSubtype: photoAssetSubtype(asset),
    sourceAlbumName: sourceAlbumNamePlaceholder(),
    sourceAlbumPath: ''
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
        photoAccessHelper.PhotoKeys.DATE_TAKEN,
        photoAccessHelper.PhotoKeys.DATE_TAKEN_MS,
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
 * 只扫描「备份源」选中的相册。
 * 备份源即扫描范围：选中相册之外的文件根本不会被枚举，
 * 因此既不参与「新媒体」判定，也不会被上传。
 */
export class LocalAlbumPhotoScan {
  entries: LocalPhotoEntry[] = [];
  /** 真正枚举过的相册数 */
  albumsScanned: number = 0;
  granted: boolean = true;
  failed: boolean = false;
}

export async function queryLocalPhotosInAlbums(
  ctx: common.UIAbilityContext,
  selectedKeys: string[],
  progress: LocalPhotoScanProgress | null = null
): Promise<LocalAlbumPhotoScan> {
  const out = new LocalAlbumPhotoScan();
  const scanResult = await scanLocalBackupSourcePhotos(
    ctx,
    selectedKeys,
    (count: number): void => {
      if (progress !== null) {
        progress.onLoaded(count);
      }
    }
  );
  out.albumsScanned = scanResult.albumsScanned;
  out.granted = scanResult.granted;
  out.failed = scanResult.failed;
  const scanned: LocalSourcePhoto[] = scanResult.photos;
  const entries: LocalPhotoEntry[] = [];
  for (let i = 0; i < scanned.length; i++) {
    const s = scanned[i];
    entries.push({
      uri: s.uri,
      fileName: s.fileName,
      fileSize: s.fileSize,
      dateModifiedMs: s.dateModifiedMs,
      dateTakenMs: s.dateTakenMs,
      mimeType: '',
      photoSubtype: s.photoSubtype,
      sourceAlbumName: s.albumName,
      sourceAlbumPath: s.albumPath
    });
  }
  out.entries = entries;
  hilog.info(DOMAIN, TAG, 'queryLocalPhotosInAlbums count=%{public}d albums=%{public}d failed=%{public}s',
    entries.length, out.albumsScanned, out.failed ? '1' : '0');
  return out;
}

/**
 * 查询本机相册里的全部图片和视频。
 * 按页取，避免一次 getAllObjects 把整库放进内存。
 */
export async function queryLocalPhotos(
  ctx: common.UIAbilityContext,
  progress: LocalPhotoScanProgress | null = null,
  failOnError: boolean = false
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
        // 分页没往前走。忽略现有照片时不能只记下前面几页，否则后面的私有照片仍会被上传。
        if (failOnError) {
          throw new Error('local photo scan incomplete');
        }
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
    // 扫描失败时只返回部分结果，界面却会显示「没有新增照片」。
    // 忽略现有照片必须整库都读到，读到一半就抛出，避免只忽略前半部分。
    if (failOnError) {
      throw e as Error;
    }
    const em: string = String(e);
    hilog.warn(DOMAIN, TAG, 'queryLocalPhotos failed: %{public}s', String(e));
    fnDiagRecord('W', TAG, `local photo scan failed, got ${entries.length} ${em.substring(0, 90)}`);
    return entries;
  }
}
