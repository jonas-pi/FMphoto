import { GalleryListItem, AiPersonItem } from '../../model/FnApiTypes';
import { GalleryHomeTimelineSnapshot } from '../GalleryHomeTimelineCache';
import { DayGlobalResolveResult, TimelineDayModel, TimelineYearMonthPair } from './GalleryAlbumTabTypes';

/**
 * 跨领域命令。Controller / Host 不得再互相 asXxxHost()。
 * 不暴露 Session 字段或通用 getter/setter。
 */
export interface GalleryAlbumCommands {
  exitSelection(): void;
  rebuildFlow(): void;
  flatItems(): GalleryListItem[];
  requestVisibleLoadImmediate(): void;
  requestVisibleLoadThrottled(forceImmediate?: boolean, aggressive?: boolean): void;
  requestVisibleLoadInteractivePriority(): void;
  pumpLoad(singleBatch?: boolean): void;
  loadOneBatch(): Promise<number>;
  bootstrap(showFullBleedSkeleton?: boolean): Promise<void>;
  applyDeleteSyncIfNeeded(): void;
  enrichPersonStats(items: AiPersonItem[], gen: number): Promise<void>;
  upsertSection(day: TimelineDayModel, list: GalleryListItem[], newOffset: number): void;
  mergeSectionSilent(day: TimelineDayModel, list: GalleryListItem[], startOffset: number): void;
  notifyDayRowsChanged(year: number, month: number, day: number): void;
  playModeSwitchMotion(direction?: number): void;
  backToMain(animate: boolean): void;
  loadMediaCategories(): Promise<void>;
  triggerAutoSync(timelineItems: GalleryListItem[]): void;
  refreshLastKnownGlobalSlotsFromListIndices(firstIdx: number, lastIdx: number): void;
  captureListScrollIndexAnchor(): void;
  refreshVisibleRangeIfAvailable(): boolean;
  forceRefreshVisibleRange(): boolean;
  flushPendingFlowRebuild(): void;
  syncGalleryTimelineAtTopForPull(): void;
  resolveYearMonthByTimelineRatio(ratio: number): TimelineYearMonthPair | null;
  resolveDayByGlobalIndex(globalIndex: number): DayGlobalResolveResult | null;
  isInScrollInteractiveLogWindow(): boolean;
  logScrollDebug(msg: string): void;
  cancelListSettledTimer(): void;
  refreshVisualPlaceholderMode(): void;
  applyMainTimelineCacheSnapshot(snap: GalleryHomeTimelineSnapshot): void;
  buildMainTimelineCacheSnapshot(): GalleryHomeTimelineSnapshot | null;
  onTabVisibleAgain(): void;
  setGallerySelectedIds(ids: string[]): void;
}
