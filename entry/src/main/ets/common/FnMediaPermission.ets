/**
 * 相册读取权限申请（READ_IMAGEVIDEO，需签名 Profile 含 ACL）。
 */
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

const READ_IMAGE_VIDEO: Permissions = 'ohos.permission.READ_IMAGEVIDEO';

export async function fnEnsureReadImageVideoGranted(ctx: common.UIAbilityContext): Promise<boolean> {
  const atManager = abilityAccessCtrl.createAtManager();
  const tokenId = ctx.applicationInfo.accessTokenId;
  const status = await atManager.checkAccessToken(tokenId, READ_IMAGE_VIDEO);
  if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
    return true;
  }
  try {
    const result = await atManager.requestPermissionsFromUser(ctx, [READ_IMAGE_VIDEO]);
    if (result.authResults.length === 0) {
      return false;
    }
    return result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  } catch (_e) {
    return false;
  }
}
