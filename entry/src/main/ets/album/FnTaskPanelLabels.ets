/**
 * NAS task-panel 任务类型 → 用户可见标题。
 */
import { TaskPanelItem } from '../model/FnApiTypes';

function typeTitle(taskType: string): string {
  const t = taskType.trim().toLowerCase();
  if (t.length === 0) {
    return '服务端任务';
  }
  if (t === 'repeat-photo' || t === 'repeat_photo') {
    return '检查重复照片';
  }
  if (t.includes('thumb') || t === 'regen-thumb' || t === 'thumbnail') {
    return '重新生成缩略图';
  }
  if (t.includes('face') || t === 'person' || t === 'face-cluster') {
    return '人脸识别';
  }
  if (t.includes('smart') || t.includes('classif') || t === 'ai-smart-rec') {
    return '智能分类';
  }
  if (t.includes('index') || t === 'reindex') {
    return '重建索引';
  }
  return taskType;
}

/** 展示用标题：优先服务端 name，再按 type 映射。 */
export function taskPanelDisplayTitle(item: TaskPanelItem): string {
  const name = item.name.trim();
  if (name === 'check-similar') {
    return '检查相似照片';
  }
  if (name === 'check-repeat') {
    return '检查重复照片';
  }
  if (name.length > 0 && !name.includes('/')) {
    const lower = name.toLowerCase();
    if (lower !== item.taskType.trim().toLowerCase()) {
      return name;
    }
  }
  const fromType = typeTitle(item.taskType);
  if (fromType !== item.taskType || item.taskType.length === 0) {
    return fromType;
  }
  if (name.length > 0) {
    return name;
  }
  return fromType;
}

export function taskPanelItemActive(item: TaskPanelItem): boolean {
  if (item.running) {
    return true;
  }
  if (item.total > 0) {
    return true;
  }
  if (item.error.length > 0) {
    return true;
  }
  return false;
}
