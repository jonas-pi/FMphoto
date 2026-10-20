/**
 * 解析飞牛 repeat-photo / task-panel 返回。
 */
import {
  GalleryListItem,
  RepeatPhotoGroup,
  RepeatPhotoListData,
  RepeatPhotoMergeData,
  RepeatPhotoTaskProgress,
  TaskPanelItem
} from '../../model/FnApiTypes';
import { normalizeGalleryListItems } from '../../album/GalleryListItemNormalize';

type LooseRec = Record<string, Object | string | number | boolean | undefined | null>;

function asLoose(value: Object | undefined | null): LooseRec | undefined {
  if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
    return undefined;
  }
  return value as LooseRec;
}

function readText(rec: LooseRec, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const raw = rec[keys[i]];
    if (raw === undefined || raw === null) {
      continue;
    }
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      return `${Math.floor(raw)}`;
    }
    const text = String(raw).trim();
    if (text.length > 0 && text !== 'null' && text !== 'undefined') {
      return text;
    }
  }
  return '';
}

function readNumber(rec: LooseRec, keys: string[]): number {
  for (let i = 0; i < keys.length; i++) {
    const raw = rec[keys[i]];
    if (typeof raw === 'number' && Number.isFinite(raw)) {
      return raw;
    }
    if (typeof raw === 'string') {
      const n = Number(raw);
      if (Number.isFinite(n)) {
        return n;
      }
    }
  }
  return 0;
}

function readStringArray(rec: LooseRec, key: string): string[] {
  const raw = rec[key];
  if (!Array.isArray(raw)) {
    return [];
  }
  const out: string[] = [];
  for (let i = 0; i < raw.length; i++) {
    const el: Object | string | number | boolean | undefined | null = raw[i] as Object | string | number | boolean | undefined | null;
    if (typeof el === 'string' && el.trim().length > 0) {
      out.push(el.trim());
    } else if (typeof el === 'number' && Number.isFinite(el)) {
      out.push(`${el}`);
    }
  }
  return out;
}

function readObjectArray(rec: LooseRec, keys: string[]): Object[] {
  for (let i = 0; i < keys.length; i++) {
    const raw = rec[keys[i]];
    if (Array.isArray(raw)) {
      return raw as Object[];
    }
  }
  return [];
}

export function jsonScalarId(id: string): string {
  const trimmed = id.trim();
  const n = Number(trimmed);
  if (Number.isFinite(n) && n > 0 && `${Math.floor(n)}` === trimmed) {
    return `${Math.floor(n)}`;
  }
  return '';
}

export function parseRepeatPhotoGroup(payload: Object | undefined): RepeatPhotoGroup | undefined {
  const rec = asLoose(payload);
  if (rec === undefined) {
    return undefined;
  }
  const id = readText(rec, ['id', 'groupId', 'group_id']);
  const photos = normalizeGalleryListItems(readObjectArray(rec, ['photos', 'list', 'items']) as GalleryListItem[]);
  if (id.length === 0 && photos.length === 0) {
    return undefined;
  }
  const group = new RepeatPhotoGroup();
  group.id = id;
  group.photos = photos;
  group.datetimes = readStringArray(rec, 'datetimes');
  group.recommendedIndex = Math.max(0, Math.floor(readNumber(rec, ['recommendedIndex', 'recommended_index'])));
  if (group.recommendedIndex >= group.photos.length && group.photos.length > 0) {
    group.recommendedIndex = 0;
  }
  return group;
}

export function parseRepeatPhotoListData(payload: Object | undefined): RepeatPhotoListData {
  const out = new RepeatPhotoListData();
  let rec = asLoose(payload);
  if (rec === undefined) {
    return out;
  }
  const nested = asLoose((rec['data'] ?? rec['result']) as Object | undefined);
  if (nested !== undefined && (nested['list'] !== undefined || nested['count'] !== undefined)) {
    rec = nested;
  }
  const groups: RepeatPhotoGroup[] = [];
  const rawList = readObjectArray(rec, ['list', 'items', 'groups']);
  for (let i = 0; i < rawList.length; i++) {
    const group = parseRepeatPhotoGroup(rawList[i]);
    if (group !== undefined) {
      groups.push(group);
    }
  }
  out.list = groups;
  out.count = Math.max(groups.length, Math.floor(readNumber(rec, ['count', 'total'])));
  out.strategy = readText(rec, ['strategy']);
  return out;
}

export function parseRepeatPhotoMergeData(payload: Object | undefined): RepeatPhotoMergeData {
  const out = new RepeatPhotoMergeData();
  const rec = asLoose(payload);
  if (rec === undefined) {
    return out;
  }
  out.recycledCount = Math.max(0, Math.floor(readNumber(rec, ['recycledCount', 'recycled_count'])));
  return out;
}

function parseTaskSubItem(payload: Object | undefined): TaskPanelItem {
  const out = new TaskPanelItem();
  const rec = asLoose(payload);
  if (rec === undefined) {
    return out;
  }
  out.name = readText(rec, ['name', 'taskName']);
  out.successCount = Math.max(0, Math.floor(readNumber(rec, ['successCount', 'success_count', 'completed'])));
  out.total = Math.max(0, Math.floor(readNumber(rec, ['total', 'itemCount', 'item_count'])));
  const failCount = Math.max(0, Math.floor(readNumber(rec, ['failCount', 'fail_count'])));
  const errCode = Math.floor(readNumber(rec, ['errCode', 'err_code']));
  out.error = readText(rec, ['errMsg', 'error', 'msg']);
  const doneRaw = rec['done'];
  const done = doneRaw === true || doneRaw === 1 || doneRaw === 'true';
  const state = readText(rec, ['state', 'status']).toLowerCase();
  out.running = !done && state !== 'done' && state !== 'finished' && state !== 'success' && state !== 'failed';
  if (state === 'failed' || state === 'error') {
    out.running = false;
  }
  if (out.total > 0) {
    out.percent = Math.min(100, Math.floor((out.successCount * 100) / out.total));
  } else if (done) {
    out.percent = 100;
  }
  if (errCode !== 0 && failCount > 0 && out.error.length === 0) {
    out.error = '任务失败';
  }
  return out;
}

function taskPanelItemFromRow(row: Object, typeHint: string, idHint: string): TaskPanelItem {
  const item = asLoose(row);
  const sub = parseTaskSubItem(row);
  sub.taskType = typeHint;
  sub.taskId = idHint;
  if (item !== undefined) {
    if (sub.taskType.length === 0) {
      sub.taskType = readText(item, ['type', 'taskType']);
    }
    if (sub.taskId.length === 0) {
      sub.taskId = readText(item, ['id', 'taskId']);
    }
    if (sub.name.length === 0) {
      sub.name = readText(item, ['name']);
    }
    const itemDone = item['done'];
    if (itemDone === true || itemDone === 1) {
      sub.running = false;
    }
  }
  return sub;
}

/** 解析 task-panel 全部任务类型（不只 repeat-photo）。 */
export function parseTaskPanelList(payload: Object | undefined): TaskPanelItem[] {
  const out: TaskPanelItem[] = [];
  let rec = asLoose(payload);
  if (rec === undefined) {
    return out;
  }
  const nested = asLoose((rec['data'] ?? rec['result']) as Object | undefined);
  if (nested !== undefined && nested['list'] !== undefined) {
    rec = nested;
  }
  const rawList = readObjectArray(rec, ['list', 'items', 'tasks']);
  for (let i = 0; i < rawList.length; i++) {
    const item = asLoose(rawList[i]);
    if (item === undefined) {
      continue;
    }
    const type = readText(item, ['type', 'taskType']);
    const taskId = readText(item, ['id', 'taskId']);
    const subList = readObjectArray(item, ['list', 'items']);
    if (subList.length > 0) {
      for (let j = 0; j < subList.length; j++) {
        const subId = taskId.length > 0 ? `${taskId}_${j}` : `${type}_${j}`;
        out.push(taskPanelItemFromRow(subList[j], type, subId));
      }
    } else {
      const id = taskId.length > 0 ? taskId : `${type}_${i}`;
      out.push(taskPanelItemFromRow(rawList[i], type, id));
    }
  }
  return out;
}

function repeatPhotoFromPanelItem(item: TaskPanelItem): RepeatPhotoTaskProgress {
  const out = new RepeatPhotoTaskProgress();
  out.taskId = item.taskId;
  out.name = item.name;
  out.successCount = item.successCount;
  out.total = item.total;
  out.percent = item.percent;
  out.running = item.running;
  out.error = item.error;
  return out;
}

export function parseRepeatPhotoTaskProgress(payload: Object | undefined): RepeatPhotoTaskProgress {
  const empty = new RepeatPhotoTaskProgress();
  const all = parseTaskPanelList(payload);
  for (let i = 0; i < all.length; i++) {
    const item = all[i];
    const type = item.taskType.trim().toLowerCase();
    if (type.length > 0 && type !== 'repeat-photo' && type !== 'repeat_photo') {
      continue;
    }
    return repeatPhotoFromPanelItem(item);
  }
  return empty;
}
