/**
 * 将成对图+视频写入系统相册为官方动态照片（PhotoSubtype.MOVING_PHOTO）。
 * 无 WRITE_IMAGEVIDEO 时须放在 SaveButton 点击回调中调用。
 */
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { LivePhotoPairFiles } from './LivePhotoSandbox';

function imageExtForAsset(path: string): string {
  const dot = path.lastIndexOf('.');
  const ext = dot >= 0 ? path.substring(dot + 1).toLowerCase() : 'jpg';
  if (ext === 'jpg' || ext === 'jpeg' || ext === 'png' || ext === 'heic' || ext === 'heif') {
    return ext === 'jpeg' ? 'jpg' : ext;
  }
  return 'jpg';
}

export async function createMovingPhotoAsset(
  context: common.UIAbilityContext,
  pair: LivePhotoPairFiles,
  title: string
): Promise<boolean> {
  if (pair.imageUri.length === 0 || pair.videoUri.length === 0) {
    return false;
  }
  const safeTitle = title.trim().length > 0 ? title.trim() : `moving_photo_${Date.now()}`;
  try {
    const helper = photoAccessHelper.getPhotoAccessHelper(context);
    const req: photoAccessHelper.MediaAssetChangeRequest =
      photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
        context,
        photoAccessHelper.PhotoType.IMAGE,
        imageExtForAsset(pair.imagePath),
        {
          title: safeTitle,
          subtype: photoAccessHelper.PhotoSubtype.MOVING_PHOTO
        }
      );
    req.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, pair.imageUri);
    req.addResource(photoAccessHelper.ResourceType.VIDEO_RESOURCE, pair.videoUri);
    await helper.applyChanges(req);
    return true;
  } catch (_e) {
    return false;
  }
}
