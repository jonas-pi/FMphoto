/**
 * 应用市场评分窗。成功拉起不代表用户提交了；
 * 只有接口返回「已经评过」时，才记下并收起入口。
 */
import { commentManager } from '@kit.AppGalleryKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

const PREF_NAME: string = 'fnos_client_prefs';
const K_COMMENT_DONE: string = 'app_gallery_comment_done';
const COMMENT_SYSCAP: string = 'SystemCapability.AppGalleryService.Distribution.Comment';

const ERR_NO_HUAWEI_ID: number = 1021500006;
const ERR_ALREADY_THIS_VERSION: number = 1021500007;
const ERR_COMMENT_LIMIT: number = 1021500008;
const ERR_WITHIN_YEAR: number = 1021500009;

export const APP_GALLERY_RATE_SHOWN: string = 'shown';
export const APP_GALLERY_RATE_ALREADY: string = 'already';
export const APP_GALLERY_RATE_NEED_ID: string = 'need_id';
export const APP_GALLERY_RATE_FAILED: string = 'failed';

export function fnAppGalleryCommentAvailable(): boolean {
  try {
    return canIUse(COMMENT_SYSCAP);
  } catch (_e) {
    return false;
  }
}

async function openPrefs(ctx: common.UIAbilityContext): Promise<preferences.Preferences | null> {
  try {
    return await preferences.getPreferences(ctx, PREF_NAME);
  } catch (_e) {
    return null;
  }
}

export async function fnIsAppGalleryCommentDone(ctx: common.UIAbilityContext): Promise<boolean> {
  try {
    const p = await openPrefs(ctx);
    if (p === null) {
      return false;
    }
    return (await p.get(K_COMMENT_DONE, '0') as string) === '1';
  } catch (_e) {
    return false;
  }
}

export async function fnMarkAppGalleryCommentDone(ctx: common.UIAbilityContext): Promise<void> {
  try {
    const p = await openPrefs(ctx);
    if (p === null) {
      return;
    }
    await p.put(K_COMMENT_DONE, '1');
    await p.flush();
  } catch (_e) {
  }
}

function isAlreadyCommented(code: number): boolean {
  return code === ERR_ALREADY_THIS_VERSION || code === ERR_COMMENT_LIMIT || code === ERR_WITHIN_YEAR;
}

export async function fnShowAppGalleryComment(ctx: common.UIAbilityContext): Promise<string> {
  if (!fnAppGalleryCommentAvailable()) {
    return APP_GALLERY_RATE_FAILED;
  }
  try {
    await commentManager.showCommentDialog(ctx);
    return APP_GALLERY_RATE_SHOWN;
  } catch (e) {
    const code = (e as BusinessError).code;
    if (isAlreadyCommented(code)) {
      await fnMarkAppGalleryCommentDone(ctx);
      return APP_GALLERY_RATE_ALREADY;
    }
    if (code === ERR_NO_HUAWEI_ID) {
      return APP_GALLERY_RATE_NEED_ID;
    }
    return APP_GALLERY_RATE_FAILED;
  }
}
