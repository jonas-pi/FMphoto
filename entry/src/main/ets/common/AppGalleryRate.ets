/**
 * 应用市场评分窗。成功拉起不代表用户提交了；
 * 只有接口返回「已经评过」时，才记下并收起入口。
 */
import { commentManager } from '@kit.AppGalleryKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { UIContext } from '@kit.ArkUI';

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

export class AppGalleryRateOutcome {
  kind: string = APP_GALLERY_RATE_FAILED;
  detail: string = '';
}

function rateOutcome(kind: string, detail: string = ''): AppGalleryRateOutcome {
  const outcome = new AppGalleryRateOutcome();
  outcome.kind = kind;
  outcome.detail = detail;
  return outcome;
}

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

function errorDetail(err: Object): string {
  const be = err as BusinessError;
  const code = be.code;
  const message = be.message !== undefined ? be.message : '';
  if (message.length > 0) {
    return `${code} ${message}`;
  }
  return `${code}`;
}

let presentingComment: boolean = false;
let openingToastId: number = -1;
let resultToastTimer: number = -1;

function showRateToast(ui: UIContext, message: string): void {
  if (message.length === 0) {
    return;
  }
  try {
    ui.getPromptAction().showToast({
      message: message,
      duration: 2200
    });
  } catch (_e) {
  }
}

function delayMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

function dismissOpeningToast(ui: UIContext): void {
  if (openingToastId < 0) {
    return;
  }
  const toastId = openingToastId;
  openingToastId = -1;
  try {
    ui.getPromptAction().closeToast(toastId);
  } catch (_e) {
  }
}

function queueRateResultToast(ui: UIContext, message: string): void {
  dismissOpeningToast(ui);
  if (resultToastTimer >= 0) {
    clearTimeout(resultToastTimer);
  }
  resultToastTimer = setTimeout((): void => {
    resultToastTimer = -1;
    showRateToast(ui, message);
  }, 360);
}

/** 先画出「正在打开评分」，再拉起评分窗。评分窗的连接会占住界面线程。 */
export async function fnPresentAppGalleryComment(ui: UIContext): Promise<void> {
  if (presentingComment) {
    showRateToast(ui, '正在打开评分');
    return;
  }
  presentingComment = true;
  dismissOpeningToast(ui);
  const startedAt = Date.now();
  try {
    try {
      openingToastId = await ui.getPromptAction().openToast({
        message: '正在打开评分',
        duration: 2200
      });
    } catch (_e) {
      openingToastId = -1;
      showRateToast(ui, '正在打开评分');
    }
    await delayMs(50);
    const result = await fnShowAppGalleryComment(ui.getHostContext() as common.UIAbilityContext);
    const elapsed = Date.now() - startedAt;
    if (result.kind === APP_GALLERY_RATE_SHOWN) {
      if (elapsed < 800) {
        queueRateResultToast(ui, '评分窗口没有留住');
      } else {
        dismissOpeningToast(ui);
      }
      return;
    }
    if (result.kind === APP_GALLERY_RATE_ALREADY) {
      queueRateResultToast(ui, '这个版本已经评过了');
      return;
    }
    if (result.kind === APP_GALLERY_RATE_NEED_ID) {
      queueRateResultToast(ui, '系统未登录华为账号，暂时无法评分');
      return;
    }
    const detail = result.detail.length > 0 ? result.detail : '暂时无法打开评分';
    queueRateResultToast(ui, detail);
  } catch (_e) {
    queueRateResultToast(ui, '评分没有打开');
  } finally {
    const wait = 1200 - (Date.now() - startedAt);
    if (wait <= 0) {
      presentingComment = false;
      return;
    }
    setTimeout((): void => {
      presentingComment = false;
    }, wait);
  }
}

export async function fnShowAppGalleryComment(ctx: common.UIAbilityContext): Promise<AppGalleryRateOutcome> {
  if (!fnAppGalleryCommentAvailable()) {
    return rateOutcome(APP_GALLERY_RATE_FAILED, '当前系统没有评分能力');
  }
  try {
    await commentManager.showCommentDialog(ctx);
    return rateOutcome(APP_GALLERY_RATE_SHOWN);
  } catch (e) {
    const code = (e as BusinessError).code;
    if (isAlreadyCommented(code)) {
      await fnMarkAppGalleryCommentDone(ctx);
      return rateOutcome(APP_GALLERY_RATE_ALREADY);
    }
    if (code === ERR_NO_HUAWEI_ID) {
      return rateOutcome(APP_GALLERY_RATE_NEED_ID);
    }
    return rateOutcome(APP_GALLERY_RATE_FAILED, errorDetail(e as Object));
  }
}
