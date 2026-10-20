/**
 * 轮询 NAS task-panel/list，把服务端后台任务合并进全局任务队列。
 */
import { AppSession } from '../auth/AppSession';
import { taskPanelItemActive } from '../album/FnTaskPanelLabels';
import { TaskPanelItem } from '../model/FnApiTypes';
import { FnTransferQueueStore } from '../common/FnTransferQueueStore';

const POLL_FAST_MS: number = 2500;
const POLL_SLOW_MS: number = 15000;

let pollTimer: number = -1;
let pollScheduled: boolean = false;

function clearPollTimer(): void {
  if (pollTimer >= 0) {
    clearTimeout(pollTimer);
    pollTimer = -1;
  }
}

function scheduleNext(delayMs: number): void {
  clearPollTimer();
  pollTimer = setTimeout((): void => {
    pollTimer = -1;
    void pollOnce();
  }, delayMs);
}

async function pollOnce(): Promise<void> {
  if (!pollScheduled) {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    stopNasTaskPanelSync();
    return;
  }
  let fast = FnTransferQueueStore.activeCount() > 0;
  try {
    const res = await client.getTaskPanelItems(12000);
    if (res.success && res.data !== undefined) {
      FnTransferQueueStore.syncNasTasks(res.data);
      for (let i = 0; i < res.data.length; i++) {
        if (res.data[i].running) {
          fast = true;
          break;
        }
      }
    }
  } catch (_e) {
  }
  if (!pollScheduled) {
    return;
  }
  scheduleNext(fast ? POLL_FAST_MS : POLL_SLOW_MS);
}

export function startNasTaskPanelSync(): void {
  if (pollScheduled) {
    return;
  }
  pollScheduled = true;
  void pollOnce();
}

export function stopNasTaskPanelSync(): void {
  pollScheduled = false;
  clearPollTimer();
  FnTransferQueueStore.clearNasTasks();
}

export function kickNasTaskPanelSync(): void {
  if (!pollScheduled) {
    startNasTaskPanelSync();
    return;
  }
  if (pollTimer < 0) {
    void pollOnce();
  }
}
