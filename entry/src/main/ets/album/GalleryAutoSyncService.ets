/**
 * 本地系统相册查询服务。
 * 利用 photoAccessHelper 查询本机相册中的图片/视频元数据，
 * 用于与 NAS 时间线对比实现「前台增量同步」。
 *
 * HarmonyOS NEXT 限制：无后台相册监听 API，只能在 App 前台时主动查询。
 */
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'AutoSyncSvc';

/** 本地相册条目（精简版，只保留同步所需字段） */
export interface LocalPhotoEntry {
  /** 系统 URI（content://...） */
  uri: string;
  /** 文件名（含扩展名） */
  fileName: string;
  /** 文件大小（字节） */
  fileSize: number;
  /** 修改时间（Unix 毫秒） */
  dateModifiedMs: number;
  /** MIME 类型 */
  mimeType: string;
}

/**
 * 查询本地相册中的图片和视频。
 * @param ctx UIAbilityContext
 * @param limit 最大返回条数（默认 500，避免首次查询过慢）
 * @returns 按修改时间倒序排列的本地媒体列表
 */
export async function queryLocalPhotos(
  ctx: common.UIAbilityContext,
  limit: number = 500
): Promise<LocalPhotoEntry[]> {
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
    const predicates = new photoAccessHelper.DataSharePredicates();
    predicates.sortByDesc(photoAccessHelper.PhotoColumns.DATE_MODIFIED);
    const result = await helper.getAssets(predicates);
    const entries: LocalPhotoEntry[] = [];
    const count = Math.min(result.count, limit);
    for (let i = 0; i < count; i++) {
      const asset = await result.getNext();
      if (asset === null) {
        break;
      }
      entries.push({
        uri: asset.uri,
        fileName: asset.displayName ?? '',
        fileSize: asset.size,
        dateModifiedMs: asset.dateModified,
        mimeType: asset.mimeType
      });
    }
    hilog.info(
      DOMAIN,
      TAG,
      'queryLocalPhotos count=%{public}d limit=%{public}d',
      entries.length,
      limit
    );
    return entries;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'queryLocalPhotos failed: %{public}s', String(e));
    return [];
  }
}

/**
 * 通过 URI 读取文件内容为 ArrayBuffer（用于上传）。
 * 注意：此操作在主线程执行可能阻塞 UI，建议在后台任务中调用。
 */
export async function readPhotoByUri(
  ctx: common.UIAbilityContext,
  uri: string
): Promise<ArrayBuffer | undefined> {
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
    const asset = await helper.getAsset(uri);
    if (asset === null) {
      return undefined;
    }
    // 使用 fileIo 读取文件内容
    const { fileIo } = await import('@kit.CoreFileKit');
    const fd = await asset.open('r');
    const stat = await fileIo.stat(fd);
    const buffer = new ArrayBuffer(stat.size);
    await fileIo.read(fd, buffer);
    await asset.close(fd);
    return buffer;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'readPhotoByUri failed: %{public}s', String(e));
    return undefined;
  }
}
