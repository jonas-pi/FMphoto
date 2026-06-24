/**
 * 随机幻灯片：作用域与配置类型。
 * scope 预留人物相册等后续入口，launcher 按 kind 分发拉取逻辑。
 */
import { GalleryListItem } from '../../model/FnApiTypes';

export enum GallerySlideshowScopeKind {
  /** 全库时间轴 */
  ALL_GALLERY = 'all_gallery',
  /** 单人物相册 */
  PERSON_ALBUM = 'person_album',
  /** 智能分类（AI 语义搜索扁平结果） */
  SMART_CATEGORY = 'smart_category'
}

export interface GallerySlideshowScope {
  kind: GallerySlideshowScopeKind;
  /** PERSON_ALBUM 时必填 */
  personId?: string;
  personName?: string;
  /** SMART_CATEGORY 时必填 */
  smartCategoryKeyword?: string;
}

export interface GallerySlideshowConfig {
  /** 每张停留秒数 */
  intervalSec: number;
  includeVideo: boolean;
  includeGif: boolean;
}

export const GALLERY_SLIDESHOW_DEFAULT_INTERVAL_SEC: number = 5;

/** 可选切换间隔（秒） */
export const GALLERY_SLIDESHOW_INTERVAL_SEC_OPTIONS: number[] = [3, 5, 8, 10, 15, 30];

export function gallerySlideshowDefaultConfig(): GallerySlideshowConfig {
  return {
    intervalSec: GALLERY_SLIDESHOW_DEFAULT_INTERVAL_SEC,
    includeVideo: true,
    includeGif: true
  };
}

export function gallerySlideshowScopeLabel(scope: GallerySlideshowScope): string {
  if (scope.kind === GallerySlideshowScopeKind.PERSON_ALBUM) {
    const name = scope.personName !== undefined ? scope.personName.trim() : '';
    return name.length > 0 ? `${name} 的幻灯片` : '人物幻灯片';
  }
  if (scope.kind === GallerySlideshowScopeKind.SMART_CATEGORY) {
    const kw = scope.smartCategoryKeyword !== undefined ? scope.smartCategoryKeyword.trim() : '';
    return kw.length > 0 ? `${kw} 的幻灯片` : '智能分类幻灯片';
  }
  return '幻灯片';
}

/** 播放队列条目：媒体 + 其在时间轴全局序列中的下标（0-based） */
export class GallerySlideshowPlaylistEntry {
  item: GalleryListItem;
  globalIndex: number;

  constructor(item: GalleryListItem, globalIndex: number) {
    this.item = item;
    this.globalIndex = globalIndex;
  }
}
