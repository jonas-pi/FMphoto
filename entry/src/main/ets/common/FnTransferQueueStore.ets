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

/** 已向服务端 clear-done、尚未从 list 消失的 NAS 任务，避免轮询把它们加回来。 */
let suppressedNasIds: string[] = [];

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

  /** 只看同一种本地任务。服务端缩略图、人脸、扫描不挡住上传或同步。 */
  static hasRunningDirection(direction: FnTransferDirection): boolean {
    for (let i = 0; i < FnTransferQueueStore.tasks.length; i++) {
      const task = FnTransferQueueStore.tasks[i];
      if (task.status === FnTransferTaskStatus.RUNNING && task.direction === direction) {
        return true;
      }
    }
    return false;
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
    const seenNasIds = new Set<string>();
    const nasNext: FnTransferTaskSnapshot[] = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const key = FnTransferQueueStore.nasTaskKey(item);
      seenNasIds.add(key);
      if (FnTransferQueueStore.isSuppressedNasId(key)) {
        if (item.running) {
          FnTransferQueueStore.releaseNasId(key);
        } else {
          continue;
        }
      }
      if (!taskPanelItemActive(item)) {
        continue;
      }
      const snap = FnTransferQueueStore.snapshotFromPanelItem(item);
      freshKeys.add(snap.id);
      nasNext.push(snap);
    }
    FnTransferQueueStore.dropSuppressedNasIdsMissing(seenNasIds);
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

  static completedNasIds(): string[] {
    const ids: string[] = [];
    for (let i = 0; i < FnTransferQueueStore.tasks.length; i++) {
      const task = FnTransferQueueStore.tasks[i];
      if (task.status === FnTransferTaskStatus.COMPLETED && FnTransferQueueStore.isNasTaskId(task.id)) {
        ids.push(task.id);
      }
    }
    return ids;
  }

  static suppressNasIds(ids: string[]): void {
    for (let i = 0; i < ids.length; i++) {
      if (!FnTransferQueueStore.isSuppressedNasId(ids[i])) {
        suppressedNasIds.push(ids[i]);
      }
    }
  }

  static releaseNasIds(ids: string[]): void {
    if (ids.length === 0 || suppressedNasIds.length === 0) {
      return;
    }
    const next: string[] = [];
    for (let i = 0; i < suppressedNasIds.length; i++) {
      let drop = false;
      for (let j = 0; j < ids.length; j++) {
        if (suppressedNasIds[i] === ids[j]) {
          drop = true;
          break;
        }
      }
      if (!drop) {
        next.push(suppressedNasIds[i]);
      }
    }
    suppressedNasIds = next;
  }

  private static isSuppressedNasId(id: string): boolean {
    for (let i = 0; i < suppressedNasIds.length; i++) {
      if (suppressedNasIds[i] === id) {
        return true;
      }
    }
    return false;
  }

  private static releaseNasId(id: string): void {
    const ids: string[] = [];
    ids.push(id);
    FnTransferQueueStore.releaseNasIds(ids);
  }

  private static dropSuppressedNasIdsMissing(seen: Set<string>): void {
    if (suppressedNasIds.length === 0) {
      return;
    }
    const next: string[] = [];
    for (let i = 0; i < suppressedNasIds.length; i++) {
      if (seen.has(suppressedNasIds[i])) {
        next.push(suppressedNasIds[i]);
      }
    }
    suppressedNasIds = next;
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
