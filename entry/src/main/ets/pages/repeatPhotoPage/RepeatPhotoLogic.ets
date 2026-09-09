/**
 * 重复/相似检查页的展示文案。
 */
import { RepeatPhotoGroup } from '../../model/FnApiTypes';

export type RepeatPhotoStep = 'start' | 'checking' | 'list' | 'empty' | 'error';

export const REPEAT_PHOTO_PAGE_SIZE: number = 30;

export function repeatPhotoPageTitle(strategy: string, fallback: string): string {
  if (strategy === 'repeat') {
    return '重复照片';
  }
  if (strategy === 'similar') {
    return '相似照片';
  }
  return fallback;
}

export function repeatPhotoGroupDateText(group: RepeatPhotoGroup): string {
  const dates = group.datetimes;
  if (dates.length === 1) {
    return dates[0];
  }
  if (dates.length === 2) {
    return `${dates[0]} 和 ${dates[1]}`;
  }
  if (dates.length > 2) {
    return `${dates[0]} 和 多个日期`;
  }
  return `${group.photos.length} 项`;
}

export function repeatPhotoGroupKey(group: RepeatPhotoGroup, index: number): string {
  return group.id.length > 0 ? group.id : `g-${index}`;
}
