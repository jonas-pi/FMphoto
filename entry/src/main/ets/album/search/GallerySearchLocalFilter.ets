/**
 * 用 AI 搜索已返回的完整列表在本地套筛选。
 * 日期 / 类型 / 收藏可直接判；人物、相册、文件夹等仍走 search/results。
 */
import { GalleryListItem } from '../../model/FnApiTypes';
import { isGifItem, isVideoItem, itemFileExt } from '../GalleryAlbumCommon';
import { isLivePhotoItem } from '../livephoto/LivePhotoDetect';
import { GallerySearchFilterSnapshot } from './GallerySearchFilterTypes';

function pathSelected(path: string[]): boolean {
  return path.length > 0 && path[0].length > 0;
}

function pad2(raw: string): string {
  const t = raw.trim();
  if (t.length === 1) {
    return `0${t}`;
  }
  return t;
}

function itemDateKey(item: GalleryListItem): string {
  const raw = item.dateTime !== undefined && item.dateTime.trim().length > 0 ?
    item.dateTime.trim() : (item.createdAt !== undefined ? item.createdAt.trim() : '');
  if (raw.length < 7) {
    return '';
  }
  let datePart = raw;
  const spaceIdx = raw.indexOf(' ');
  if (spaceIdx > 0) {
    datePart = raw.substring(0, spaceIdx);
  }
  const tIdx = datePart.indexOf('T');
  if (tIdx > 0) {
    datePart = datePart.substring(0, tIdx);
  }
  let norm = '';
  for (let i = 0; i < datePart.length; i++) {
    const ch = datePart.charAt(i);
    norm += ch === '-' ? ':' : ch;
  }
  return norm;
}

function matchDatePath(item: GalleryListItem, path: string[]): boolean {
  const key = itemDateKey(item);
  if (key.length < 7) {
    return false;
  }
  const year = path.length > 0 ? path[0].trim() : '';
  const month = path.length > 1 ? pad2(path[1]) : '';
  const day = path.length > 2 ? pad2(path[2]) : '';
  if (year.length > 0 && key.substring(0, year.length) !== year) {
    return false;
  }
  if (month.length > 0) {
    const gotMonth = key.length >= 7 ? key.substring(5, 7) : '';
    if (gotMonth !== month) {
      return false;
    }
  }
  if (day.length > 0) {
    const gotDay = key.length >= 10 ? key.substring(8, 10) : '';
    if (gotDay !== day) {
      return false;
    }
  }
  return true;
}

function isRawItem(item: GalleryListItem): boolean {
  const cat = item.category !== undefined ? item.category.trim().toLowerCase() : '';
  if (cat === 'raw') {
    return true;
  }
  const ext = itemFileExt(item);
  return ext === 'dng' || ext === 'cr2' || ext === 'cr3' || ext === 'nef' || ext === 'arw' ||
    ext === 'raf' || ext === 'orf' || ext === 'rw2' || ext === 'pef' || ext === 'srw' || ext === 'raw';
}

function isScreenshotItem(item: GalleryListItem): boolean {
  if (item.specialType === 3) {
    return true;
  }
  const cat = item.category !== undefined ? item.category.trim().toLowerCase() : '';
  const ft = item.fileType !== undefined ? item.fileType.trim().toLowerCase() : '';
  return cat === 'screenshot' || ft === 'screenshot';
}

function matchFileType(item: GalleryListItem, fileType: string): boolean {
  const slug = fileType.trim().toLowerCase();
  if (slug.length === 0) {
    return true;
  }
  if (slug === 'live_photo') {
    return isLivePhotoItem(item);
  }
  if (slug === 'gif') {
    return isGifItem(item);
  }
  if (slug === 'video') {
    return isVideoItem(item) && !isLivePhotoItem(item);
  }
  if (slug === 'raw') {
    return isRawItem(item);
  }
  if (slug === 'screenshot') {
    return isScreenshotItem(item);
  }
  if (slug === 'photo') {
    return !isVideoItem(item) && !isGifItem(item) && !isLivePhotoItem(item) && !isRawItem(item);
  }
  const cat = item.category !== undefined ? item.category.trim().toLowerCase() : '';
  const ft = item.fileType !== undefined ? item.fileType.trim().toLowerCase() : '';
  return cat === slug || ft === slug;
}

/** 人物 / 地点 / 相册 / 文件夹 / 拍摄参数必须走服务端筛选结果 */
export function gallerySearchNeedsRemoteFilterIds(s: GallerySearchFilterSnapshot): boolean {
  if (s.personId.length > 0) {
    return true;
  }
  if (pathSelected(s.locationPath) || pathSelected(s.albumPath) || pathSelected(s.folderPath)) {
    return true;
  }
  if (!s.showShootingInfo) {
    return false;
  }
  return pathSelected(s.makeModelPath) || pathSelected(s.focalLengthPath) ||
    pathSelected(s.exposurePath) || pathSelected(s.aperturePath) || pathSelected(s.isoPath);
}

/** 在 AI 全量结果上套日期 / 类型 / 收藏 */
export function gallerySearchApplyLocalFilters(
  items: GalleryListItem[],
  s: GallerySearchFilterSnapshot
): GalleryListItem[] {
  const out: GalleryListItem[] = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (s.isCollect && item.isCollect !== 1) {
      continue;
    }
    if (s.fileType.length > 0 && !matchFileType(item, s.fileType)) {
      continue;
    }
    if (pathSelected(s.datePath) && !matchDatePath(item, s.datePath)) {
      continue;
    }
    out.push(item);
  }
  return out;
}
