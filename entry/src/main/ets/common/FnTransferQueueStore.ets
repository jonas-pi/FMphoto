/**
 * 全局传输队列：后台上传/下载/同步进度，供「我的」页展示。
 */
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

  static update(taskId: string, current: number, detail: string = ''): void {
    for (let i = 0; i < FnTransferQueueStore.tasks.length; i++) {
      if (FnTransferQueueStore.tasks[i].id !== taskId) {
        continue;
      }
      FnTransferQueueStore.tasks[i].current = current;
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
