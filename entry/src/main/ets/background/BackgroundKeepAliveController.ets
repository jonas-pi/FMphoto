/**
 * 后台保活：基于鸿蒙 Background Tasks Kit（@ohos 官方能力，非轮询/恶意常驻）。
 *
 * 1) 短时任务 requestSuspendDelay：进后台时申请挂起宽限，便于状态收尾；回前台须 cancel，避免浪费配额。
 * 2) 长时任务 startBackgroundRunning(DATA_TRANSFER)：与 NAS 同步、图库拉取等数据传输场景匹配；
 *    须在 module.json5 声明 backgroundModes 与 KEEP_BACKGROUND_RUNNING。
 *
 * 配额与策略由系统统一下发，应用不得假设「永久后台」。
 *
 * 崩溃防护：
 *   - 所有系统 API 均包裹在独立 try-catch 中，防止单点异常扩散
 *   - startBackgroundRunning 使用枚举值 BackgroundMode.DATA_TRANSFER（非字符串）
 *   - 回前台/销毁时优先 stopBackgroundRunning，再 cancelSuspendDelay
 */
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent } from '@kit.AbilityKit';
import type { WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'BgKeepAlive';
const SUSPEND_REASON = 'FNOS: background grace for session state';

export class BackgroundKeepAliveController {
  private static suspendRequestId: number = -1;
  private static longRunningActive: boolean = false;

  /** UIAbility 进入后台时调用 */
  static onAbilityBackground(context: common.UIAbilityContext): void {
    BackgroundKeepAliveController.requestSuspendDelaySafe();
    void BackgroundKeepAliveController.startDataTransferBackgroundSafe(context);
  }

  /** UIAbility 回到前台或即将销毁时调用 */
  static onAbilityForegroundOrDestroy(context: common.UIAbilityContext): void {
    void BackgroundKeepAliveController.stopDataTransferBackgroundSafe(context);
    BackgroundKeepAliveController.cancelSuspendDelaySafe();
  }

  // ── 短时任务 ───────────────────────────────────────────────────────────

  private static requestSuspendDelaySafe(): void {
    BackgroundKeepAliveController.cancelSuspendDelaySafe();
    try {
      const delayInfo = backgroundTaskManager.requestSuspendDelay(SUSPEND_REASON, (): void => {
        hilog.warn(DOMAIN, TAG, 'suspend quota callback, cancel id=%{public}d',
          BackgroundKeepAliveController.suspendRequestId);
        BackgroundKeepAliveController.cancelSuspendDelaySafe();
      });
      BackgroundKeepAliveController.suspendRequestId = delayInfo.requestId;
      hilog.info(DOMAIN, TAG, 'requestSuspendDelay ok id=%{public}d', delayInfo.requestId);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'requestSuspendDelay failed: %{public}s', String(e));
    }
  }

  private static cancelSuspendDelaySafe(): void {
    if (BackgroundKeepAliveController.suspendRequestId < 0) {
      return;
    }
    const id = BackgroundKeepAliveController.suspendRequestId;
    BackgroundKeepAliveController.suspendRequestId = -1;
    try {
      backgroundTaskManager.cancelSuspendDelay(id);
    } catch (_e) {
      // 已失效或被系统回收，忽略
    }
  }

  // ── 长时任务（数据传输模式） ─────────────────────────────────────────────

  private static async startDataTransferBackgroundSafe(context: common.UIAbilityContext): Promise<void> {
    if (BackgroundKeepAliveController.longRunningActive) {
      return;
    }
    try {
      // abilityInfo 在少数机型/时序下可能未就绪，全量保护
      if (context.abilityInfo === null || context.abilityInfo === undefined) {
        hilog.warn(DOMAIN, TAG, 'skip startBackgroundRunning: abilityInfo not ready');
        return;
      }
      const bundleName: string = context.abilityInfo.bundleName ?? '';
      const abilityName: string = context.abilityInfo.name ?? '';
      if (bundleName.length === 0 || abilityName.length === 0) {
        hilog.warn(DOMAIN, TAG, 'skip startBackgroundRunning: empty bundle/ability name');
        return;
      }

      const agent: WantAgent = await wantAgent.getWantAgent({
        wants: [{ bundleName: bundleName, abilityName: abilityName }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0
      });

      // 使用官方枚举值（DATA_TRANSFER = 1），避免传 string[] 导致运行时 TypeError
      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        agent
      );
      BackgroundKeepAliveController.longRunningActive = true;
      hilog.info(DOMAIN, TAG, 'startBackgroundRunning DATA_TRANSFER ok');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'startBackgroundRunning skipped or failed: %{public}s', String(e));
      // 不设 longRunningActive，允许下次重试
    }
  }

  private static async stopDataTransferBackgroundSafe(context: common.UIAbilityContext): Promise<void> {
    if (!BackgroundKeepAliveController.longRunningActive) {
      return;
    }
    BackgroundKeepAliveController.longRunningActive = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
      hilog.info(DOMAIN, TAG, 'stopBackgroundRunning ok');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'stopBackgroundRunning: %{public}s', String(e));
    }
  }
}
