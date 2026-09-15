/**
 * 相册读取权限：公开发布包不声明 READ_IMAGEVIDEO。
 * 仅当签名 Profile 已预授时 check 为 true；否则走系统选图，不弹授权窗。
 */
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

const READ_IMAGE_VIDEO: Permissions = 'ohos.permission.READ_IMAGEVIDEO';

export async function fnEnsureReadImageVideoGranted(ctx: common.UIAbilityContext): Promise<boolean> {
  try {
    const atManager = abilityAccessCtrl.createAtManager();
    const tokenId = ctx.applicationInfo.accessTokenId;
    const status = await atManager.checkAccessToken(tokenId, READ_IMAGE_VIDEO);
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  } catch (_e) {
    return false;
  }
}
