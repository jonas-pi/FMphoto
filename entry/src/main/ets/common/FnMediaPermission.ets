/**
 * 相册读取权限。调试签名的 Profile 含这项 ACL，可以弹窗申请。
 * 正式发布用的 Profile 没有这项 ACL，带上这个声明的正式包装不上去。
 */
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

const READ_IMAGE_VIDEO: Permissions = 'ohos.permission.READ_IMAGEVIDEO';

export async function fnEnsureReadImageVideoGranted(ctx: common.UIAbilityContext): Promise<boolean> {
  try {
    const atManager = abilityAccessCtrl.createAtManager();
    const tokenId = ctx.applicationInfo.accessTokenId;
    const status = await atManager.checkAccessToken(tokenId, READ_IMAGE_VIDEO);
    if (status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      return true;
    }
    const perms: Array<Permissions> = [READ_IMAGE_VIDEO];
    const result = await atManager.requestPermissionsFromUser(ctx, perms);
    const authResults = result.authResults;
    if (authResults.length === 0) {
      return false;
    }
    return authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  } catch (_e) {
    return false;
  }
}
