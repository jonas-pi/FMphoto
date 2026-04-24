import {
  AiPersonItem,
  GalleryListItem,
  MediaCategoryItem,
  SmartCategoryItem
} from '../../model/FnApiTypes';

export interface GalleryAlbumDaySectionState {
  year: number;
  month: number;
  day: number;
  itemCount: number;
  slotByOffset: Map<number, GalleryListItem>;
  nextOffset: number;
}

@Observed
export class GalleryAlbumDaySectionModel implements GalleryAlbumDaySectionState {
  year: number = 0;
  month: number = 0;
  day: number = 0;
  itemCount: number = 0;
  slotByOffset: Map<number, GalleryListItem> = new Map<number, GalleryListItem>();
  nextOffset: number = 0;
}

export interface GalleryAlbumModeState {
  inSearchMode: boolean;
  inCategoryMode: boolean;
  inSmartCategoryMode: boolean;
  inPersonMode: boolean;
}

export interface GalleryAlbumSelectionState {
  gallerySelectionMode: boolean;
  gallerySelectedIds: string[];
}

export interface GalleryAlbumTimelineChromeState {
  timelineSidebarDragging: boolean;
  timelineLongPressExpanded: boolean;
  timelineBarVisible: boolean;
}

export interface GalleryAlbumSearchState {
  searchQuery: string;
  searchResults: GalleryListItem[];
  searchLoading: boolean;
  searchError: string;
}

export interface GalleryAlbumCategoryState {
  categoryLoading: boolean;
  categoryOpening: boolean;
  categoryError: string;
  categoryItems: MediaCategoryItem[];
}

export interface GalleryAlbumSmartCategoryState {
  smartCategoryLoading: boolean;
  smartCategoryError: string;
  smartSceneItems: SmartCategoryItem[];
  smartInfoItems: SmartCategoryItem[];
}

export interface GalleryAlbumPersonState {
  personLoading: boolean;
  personOpening: boolean;
  personError: string;
  personItems: AiPersonItem[];
  personStatVersion: number;
}

export function isGalleryAlbumMainMode(state: GalleryAlbumModeState): boolean {
  return !state.inSearchMode && !state.inCategoryMode && !state.inSmartCategoryMode && !state.inPersonMode;
}

export function hasGalleryAlbumSubMode(state: GalleryAlbumModeState): boolean {
  return !isGalleryAlbumMainMode(state);
}

export function galleryAlbumSelectedCount(state: GalleryAlbumSelectionState): number {
  return state.gallerySelectedIds.length;
}

export function timelineScrubExpandedChrome(state: GalleryAlbumTimelineChromeState): boolean {
  return state.timelineSidebarDragging || state.timelineLongPressExpanded;
}

export function timelineScrubScrollRailOnly(state: GalleryAlbumTimelineChromeState): boolean {
  return state.timelineBarVisible && !timelineScrubExpandedChrome(state);
}

export function shouldShowGalleryAlbumTimelineSidebar(sectionCount: number, orderedDayCount: number): boolean {
  return sectionCount > 0 || orderedDayCount > 0;
}
