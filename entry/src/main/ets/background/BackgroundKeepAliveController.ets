import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent } from '@kit.AbilityKit';
import type { WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xFF00;
const TAG = 'BgKeepAlive';
const SUSPEND_REASON = 'FNOS: background grace for session state';
const BG_TRANSIENT_TASK_SYSCAP = 'SystemCapability.ResourceSchedule.BackgroundTaskManager.TransientTask';
const BG_CONTINUOUS_TASK_SYSCAP = 'SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask';

export class BackgroundKeepAliveController {
  private static suspendRequestId: number = -1;
  private static longRunningActive: boolean = false;
  private static startInFlight: boolean = false;
  private static stopInFlight: boolean = false;
  private static appInBackground: boolean = false;
  private static activeDataTransferCount: number = 0;
  private static lastContext: common.UIAbilityContext | undefined = undefined;

  static onAbilityBackground(context: common.UIAbilityContext): void {
    BackgroundKeepAliveController.lastContext = context;
    BackgroundKeepAliveController.appInBackground = true;
    BackgroundKeepAliveController.requestSuspendDelaySafe();
    BackgroundKeepAliveController.reconcileDataTransferBackground(context);
  }

  static onAbilityForegroundOrDestroy(context: common.UIAbilityContext): void {
    BackgroundKeepAliveController.lastContext = context;
    BackgroundKeepAliveController.appInBackground = false;
    BackgroundKeepAliveController.reconcileDataTransferBackground(context);
    BackgroundKeepAliveController.cancelSuspendDelaySafe();
  }

  static beginDataTransfer(context: common.UIAbilityContext, reason: string): void {
    BackgroundKeepAliveController.lastContext = context;
    BackgroundKeepAliveController.activeDataTransferCount++;
    hilog.info(
      DOMAIN,
      TAG,
      'beginDataTransfer reason=%{public}s count=%{public}d background=%{public}s',
      reason,
      BackgroundKeepAliveController.activeDataTransferCount,
      BackgroundKeepAliveController.appInBackground ? 'true' : 'false'
    );
    BackgroundKeepAliveController.reconcileDataTransferBackground(context);
  }

  static endDataTransfer(reason: string): void {
    if (BackgroundKeepAliveController.activeDataTransferCount > 0) {
      BackgroundKeepAliveController.activeDataTransferCount--;
    }
    hilog.info(
      DOMAIN,
      TAG,
      'endDataTransfer reason=%{public}s count=%{public}d background=%{public}s',
      reason,
      BackgroundKeepAliveController.activeDataTransferCount,
      BackgroundKeepAliveController.appInBackground ? 'true' : 'false'
    );
    BackgroundKeepAliveController.reconcileDataTransferBackground();
  }

  static async withDataTransfer<T>(
    context: common.UIAbilityContext,
    reason: string,
    task: () => Promise<T>
  ): Promise<T> {
    BackgroundKeepAliveController.beginDataTransfer(context, reason);
    try {
      return await task();
    } finally {
      BackgroundKeepAliveController.endDataTransfer(reason);
    }
  }

  private static requestSuspendDelaySafe(): void {
    BackgroundKeepAliveController.cancelSuspendDelaySafe();
    if (canIUse(BG_TRANSIENT_TASK_SYSCAP)) {
      try {
        // @SuppressWarnings syscap
        const delayInfo = backgroundTaskManager.requestSuspendDelay(SUSPEND_REASON, (): void => {
          hilog.warn(
            DOMAIN,
            TAG,
            'suspend quota callback, cancel id=%{public}d',
            BackgroundKeepAliveController.suspendRequestId
          );
          BackgroundKeepAliveController.cancelSuspendDelaySafe();
        });
        BackgroundKeepAliveController.suspendRequestId = delayInfo.requestId;
        hilog.info(DOMAIN, TAG, 'requestSuspendDelay ok id=%{public}d', delayInfo.requestId);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'requestSuspendDelay failed: %{public}s', String(e));
      }
    } else {
      hilog.info(DOMAIN, TAG, 'skip requestSuspendDelay: syscap unsupported');
    }
  }

  private static cancelSuspendDelaySafe(): void {
    if (BackgroundKeepAliveController.suspendRequestId < 0) {
      return;
    }
    const id = BackgroundKeepAliveController.suspendRequestId;
    BackgroundKeepAliveController.suspendRequestId = -1;
    if (canIUse(BG_TRANSIENT_TASK_SYSCAP)) {
      try {
        // @SuppressWarnings syscap
        backgroundTaskManager.cancelSuspendDelay(id);
      } catch (_e) {
      }
    }
  }

  private static shouldHoldDataTransferBackground(): boolean {
    return BackgroundKeepAliveController.appInBackground &&
      BackgroundKeepAliveController.activeDataTransferCount > 0;
  }

  private static reconcileDataTransferBackground(context?: common.UIAbilityContext): void {
    const ctx = context ?? BackgroundKeepAliveController.lastContext;
    if (ctx === undefined) {
      return;
    }
    if (BackgroundKeepAliveController.shouldHoldDataTransferBackground()) {
      void BackgroundKeepAliveController.startDataTransferBackgroundSafe(ctx);
      return;
    }
    void BackgroundKeepAliveController.stopDataTransferBackgroundSafe(ctx);
  }

  private static async startDataTransferBackgroundSafe(context: common.UIAbilityContext): Promise<void> {
    if (
      BackgroundKeepAliveController.longRunningActive ||
      BackgroundKeepAliveController.startInFlight ||
      !BackgroundKeepAliveController.shouldHoldDataTransferBackground()
    ) {
      return;
    }
    if (!canIUse(BG_CONTINUOUS_TASK_SYSCAP)) {
      hilog.info(DOMAIN, TAG, 'skip startBackgroundRunning: syscap unsupported');
      return;
    }
    BackgroundKeepAliveController.startInFlight = true;
    try {
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

      // @SuppressWarnings syscap
      await backgroundTaskManager.startBackgroundRunning(
        context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        agent
      );
      BackgroundKeepAliveController.longRunningActive = true;
      hilog.info(DOMAIN, TAG, 'startBackgroundRunning DATA_TRANSFER ok');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'startBackgroundRunning skipped or failed: %{public}s', String(e));
    } finally {
      BackgroundKeepAliveController.startInFlight = false;
      if (!BackgroundKeepAliveController.shouldHoldDataTransferBackground()) {
        BackgroundKeepAliveController.reconcileDataTransferBackground(context);
      }
    }
  }

  private static async stopDataTransferBackgroundSafe(context: common.UIAbilityContext): Promise<void> {
    if (!BackgroundKeepAliveController.longRunningActive || BackgroundKeepAliveController.stopInFlight) {
      return;
    }
    BackgroundKeepAliveController.stopInFlight = true;
    BackgroundKeepAliveController.longRunningActive = false;
    if (!canIUse(BG_CONTINUOUS_TASK_SYSCAP)) {
      BackgroundKeepAliveController.stopInFlight = false;
      return;
    }
    try {
      // @SuppressWarnings syscap
      await backgroundTaskManager.stopBackgroundRunning(context);
      hilog.info(DOMAIN, TAG, 'stopBackgroundRunning ok');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'stopBackgroundRunning: %{public}s', String(e));
    } finally {
      BackgroundKeepAliveController.stopInFlight = false;
      if (BackgroundKeepAliveController.shouldHoldDataTransferBackground()) {
        BackgroundKeepAliveController.reconcileDataTransferBackground(context);
      }
    }
  }
}
