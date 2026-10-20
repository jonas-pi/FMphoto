/**
 * 全局任务队列：扫描、上传、下载、同步的进度，供「我的」页展示。
 */
import { taskPanelDisplayTitle, taskPanelItemActive } from '../album/FnTaskPanelLabels';
import { TaskPanelItem } from '../model/FnApiTypes';
import { FnTransferDirection, fnTransferDirectionLabel } from './FnTransferProgress';

export const FN_TRANSFER_QUEUE_VERSION: string = 'FN_TRANSFER_QUEUE_VERSION';

export enum FnTransferTaskStatus {
  RUNNING = 'running',
  COMPLETED = 'completed',
  FAILED = 'failed'
}

export interface FnTransferTaskSnapshot {
  id: string;
  direction: FnTransferDirection;
  title: string;
  current: number;
  total: number;
  detail: string;
  status: FnTransferTaskStatus;
  message: string;
  updatedAt: number;
}

function bumpQueueVersion(): void {
  const old = AppStorage.get<number>(FN_TRANSFER_QUEUE_VERSION) ?? 0;
  AppStorage.setOrCreate<number>(FN_TRANSFER_QUEUE_VERSION, old + 1);
}

export class FnTransferQueueStore {
  private static tasks: FnTransferTaskSnapshot[] = [];
  private static seq: number = 1;
  private static readonly MAX_TASKS: number = 30;

  static ensureStorage(): void {
    AppStorage.setOrCreate<number>(FN_TRANSFER_QUEUE_VERSION, 0);
  }

  static begin(direction: FnTransferDirection, title: string, total: number): string {
    const id = `transfer_${FnTransferQueueStore.seq++}`;
    const task: FnTransferTaskSnapshot = {
      id,
      direction,
      title,
      current: 0,
      total,
      detail: '',
      status: FnTransferTaskStatus.RUNNING,
      message: '',
      updatedAt: Date.now()
    };
    FnTransferQueueStore.tasks.unshift(task);
    if (FnTransferQueueStore.tasks.length > FnTransferQueueStore.MAX_TASKS) {
      FnTransferQueueStore.tasks.length = FnTransferQueueStore.MAX_TASKS;
    }
    bumpQueueVersion();
    return id;
  }

  static update(taskId: string, current: number, detail: string = '', total?: number): void {
    for (let i = 0; i < FnTransferQueueStore.tasks.length; i++) {
      if (FnTransferQueueStore.tasks[i].id !== taskId) {
        continue;
      }
      FnTransferQueueStore.tasks[i].current = current;
      if (total !== undefined && total > 0) {
        FnTransferQueueStore.tasks[i].total = total;
      }
      if (detail.length > 0) {
        FnTransferQueueStore.tasks[i].detail = detail;
      }
      FnTransferQueueStore.tasks[i].updatedAt = Date.now();
      bumpQueueVersion();
      return;
    }
  }

  static finish(taskId: string, ok: boolean, message: string = ''): void {
    for (let i = 0; i < FnTransferQueueStore.tasks.length; i++) {
      if (FnTransferQueueStore.tasks[i].id !== taskId) {
        continue;
      }
      FnTransferQueueStore.tasks[i].status = ok ? FnTransferTaskStatus.COMPLETED : FnTransferTaskStatus.FAILED;
      FnTransferQueueStore.tasks[i].message = message;
      FnTransferQueueStore.tasks[i].updatedAt = Date.now();
      bumpQueueVersion();
      return;
    }
  }

  static getTasks(): FnTransferTaskSnapshot[] {
    return FnTransferQueueStore.tasks.slice();
  }

  static activeCount(): number {
    let n = 0;
    for (let i = 0; i < FnTransferQueueStore.tasks.length; i++) {
      if (FnTransferQueueStore.tasks[i].status === FnTransferTaskStatus.RUNNING) {
        n++;
      }
    }
    return n;
  }

  static hasRunning(): boolean {
    return FnTransferQueueStore.activeCount() > 0;
  }

  private static isNasTaskId(id: string): boolean {
    return id.startsWith('nas:');
  }

  private static nasTaskKey(item: TaskPanelItem): string {
    const type = item.taskType.trim().length > 0 ? item.taskType.trim() : 'task';
    const id = item.taskId.trim().length > 0 ? item.taskId.trim() : item.name.trim();
    return `nas:${type}:${id}`;
  }

  private static snapshotFromPanelItem(item: TaskPanelItem): FnTransferTaskSnapshot {
    const snap: FnTransferTaskSnapshot = {
      id: FnTransferQueueStore.nasTaskKey(item),
      direction: FnTransferDirection.NAS,
      title: taskPanelDisplayTitle(item),
      current: item.successCount,
      total: item.total,
      detail: item.running && item.error.length > 0 ? item.error : '',
      status: FnTransferTaskStatus.RUNNING,
      message: '',
      updatedAt: Date.now()
    };
    if (!item.running) {
      if (item.error.length > 0) {
        snap.status = FnTransferTaskStatus.FAILED;
        snap.message = item.error;
      } else {
        snap.status = FnTransferTaskStatus.COMPLETED;
        if (item.total > 0) {
          snap.message = `已完成 ${item.successCount}/${item.total}`;
        } else if (item.percent >= 100) {
          snap.message = '已完成';
        } else {
          snap.message = '已完成';
        }
      }
    } else if (item.total <= 0) {
      snap.detail = snap.detail.length > 0 ? snap.detail : '处理中…';
    }
    return snap;
  }

  /** 合并 NAS task-panel 任务；本地 transfer_* 任务不受影响。 */
  static syncNasTasks(items: TaskPanelItem[]): void {
    const local: FnTransferTaskSnapshot[] = [];
    const staleNas: FnTransferTaskSnapshot[] = [];
    for (let i = 0; i < FnTransferQueueStore.tasks.length; i++) {
      const t = FnTransferQueueStore.tasks[i];
      if (FnTransferQueueStore.isNasTaskId(t.id)) {
        staleNas.push(t);
      } else {
        local.push(t);
      }
    }
    const freshKeys = new Set<string>();
    const nasNext: FnTransferTaskSnapshot[] = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (!taskPanelItemActive(item)) {
        continue;
      }
      const snap = FnTransferQueueStore.snapshotFromPanelItem(item);
      freshKeys.add(snap.id);
      nasNext.push(snap);
    }
    for (let i = 0; i < staleNas.length; i++) {
      const old = staleNas[i];
      if (freshKeys.has(old.id)) {
        continue;
      }
      if (old.status === FnTransferTaskStatus.RUNNING) {
        old.status = FnTransferTaskStatus.COMPLETED;
        old.message = old.message.length > 0 ? old.message : '已完成';
        old.updatedAt = Date.now();
      }
      if (old.status === FnTransferTaskStatus.COMPLETED || old.status === FnTransferTaskStatus.FAILED) {
        nasNext.push(old);
      }
    }
    FnTransferQueueStore.tasks = local.concat(nasNext);
    FnTransferQueueStore.tasks.sort((a: FnTransferTaskSnapshot, b: FnTransferTaskSnapshot): number => {
      return b.updatedAt - a.updatedAt;
    });
    if (FnTransferQueueStore.tasks.length > FnTransferQueueStore.MAX_TASKS) {
      FnTransferQueueStore.tasks.length = FnTransferQueueStore.MAX_TASKS;
    }
    bumpQueueVersion();
  }

  static clearNasTasks(): void {
    const kept: FnTransferTaskSnapshot[] = [];
    for (let i = 0; i < FnTransferQueueStore.tasks.length; i++) {
      if (!FnTransferQueueStore.isNasTaskId(FnTransferQueueStore.tasks[i].id)) {
        kept.push(FnTransferQueueStore.tasks[i]);
      }
    }
    if (kept.length !== FnTransferQueueStore.tasks.length) {
      FnTransferQueueStore.tasks = kept;
      bumpQueueVersion();
    }
  }

  static completedCount(): number {
    let n = 0;
    for (let i = 0; i < FnTransferQueueStore.tasks.length; i++) {
      if (FnTransferQueueStore.tasks[i].status === FnTransferTaskStatus.COMPLETED) {
        n++;
      }
    }
    return n;
  }

  /** 移除已完成任务；进行中与失败项保留。返回清除条数。 */
  static clearCompleted(): number {
    const before = FnTransferQueueStore.tasks.length;
    const kept: FnTransferTaskSnapshot[] = [];
    for (let i = 0; i < FnTransferQueueStore.tasks.length; i++) {
      const task = FnTransferQueueStore.tasks[i];
      if (task.status !== FnTransferTaskStatus.COMPLETED) {
        kept.push(task);
      }
    }
    FnTransferQueueStore.tasks = kept;
    const removed = before - kept.length;
    if (removed > 0) {
      bumpQueueVersion();
    }
    return removed;
  }

  static directionLabel(direction: FnTransferDirection): string {
    return fnTransferDirectionLabel(direction);
  }

  static statusLabel(status: FnTransferTaskStatus): string {
    if (status === FnTransferTaskStatus.COMPLETED) {
      return '已完成';
    }
    if (status === FnTransferTaskStatus.FAILED) {
      return '失败';
    }
    return '进行中';
  }

  static progressPercent(task: FnTransferTaskSnapshot): number {
    if (task.total <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(100, Math.round((task.current / task.total) * 100)));
  }
}
