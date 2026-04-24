import {
  GalleryHomeDayPlain,
  GalleryHomeSectionPlain,
  GalleryHomeStringNumMapArrays,
  GalleryHomeTimelineSnapshot
} from '../GalleryHomeTimelineCache';
import { GalleryTimelineRefreshStore } from '../GalleryTimelineRefreshStore';
import { GalleryListItem } from '../../model/FnApiTypes';
import { GalleryAlbumLoadOrchestratorHost } from './GalleryAlbumLoadOrchestrator';
import { GalleryAlbumDaySectionModel } from './GalleryAlbumState';
import { TimelineDayModel } from './GalleryAlbumTabTypes';

function mapStringNumToArrays(map: Map<string, number>): GalleryHomeStringNumMapArrays {
  const keys: string[] = [];
  const vals: number[] = [];
  map.forEach((value: number, key: string): void => {
    keys.push(key);
    vals.push(value);
  });
  return { keys: keys, vals: vals };
}

function fillMapFromArrays(map: Map<string, number>, keys: string[], vals: number[]): void {
  map.clear();
  for (let i = 0; i < keys.length; i++) {
    if (i < vals.length) {
      map.set(keys[i], vals[i]);
    }
  }
}

export function galleryAlbumBuildMainTimelineCacheSnapshot(
  host: GalleryAlbumLoadOrchestratorHost
): GalleryHomeTimelineSnapshot | null {
  if (host.inSearchMode || host.inCategoryMode || host.inSmartCategoryMode || host.inPersonMode) {
    return null;
  }
  if (host.bootLoading) {
    return null;
  }
  if (host.loadError.length > 0 && host.sections.length === 0) {
    return null;
  }
  const emptyNoFoot = host.orderedDays.length === 0 && host.sections.length === 0 && host.footText !== '时间轴暂无数据';
  if (emptyNoFoot) {
    return null;
  }
  const sectionsPlain: GalleryHomeSectionPlain[] = [];
  for (let i = 0; i < host.sections.length; i++) {
    const section = host.sections[i];
    const offs: number[] = [];
    const imgs: GalleryListItem[] = [];
    const keys = Array.from(section.slotByOffset.keys()).sort((a: number, b: number): number => a - b);
    for (let j = 0; j < keys.length; j++) {
      const key = keys[j];
      const item = section.slotByOffset.get(key);
      if (item !== undefined) {
        offs.push(key);
        imgs.push(item);
      }
    }
    sectionsPlain.push({
      year: section.year,
      month: section.month,
      day: section.day,
      itemCount: section.itemCount,
      nextOffset: section.nextOffset,
      slotOffsets: offs,
      slotItems: imgs
    });
  }
  const orderedPlain: GalleryHomeDayPlain[] = [];
  for (let i = 0; i < host.orderedDays.length; i++) {
    const day = host.orderedDays[i];
    orderedPlain.push({ year: day.year, month: day.month, day: day.day, itemCount: day.itemCount });
  }
  const offsets = mapStringNumToArrays(host.dayOffsets);
  const rounds = mapStringNumToArrays(host.dayRounds);
  const emptyRounds = mapStringNumToArrays(host.dayEmptyRounds);
  return {
    orderedDays: orderedPlain,
    sections: sectionsPlain,
    dayOffsetsKeys: offsets.keys,
    dayOffsetsVals: offsets.vals,
    dayRoundsKeys: rounds.keys,
    dayRoundsVals: rounds.vals,
    dayEmptyKeys: emptyRounds.keys,
    dayEmptyVals: emptyRounds.vals,
    dayIndex: host.dayIndex,
    exhausted: host.exhausted,
    footText: host.footText,
    refreshVersionAtSave: GalleryTimelineRefreshStore.version
  };
}

export function galleryAlbumApplyMainTimelineCacheSnapshot(
  host: GalleryAlbumLoadOrchestratorHost,
  snap: GalleryHomeTimelineSnapshot
): void {
  const orderedDays: TimelineDayModel[] = [];
  for (let i = 0; i < snap.orderedDays.length; i++) {
    const day = snap.orderedDays[i];
    orderedDays.push({ year: day.year, month: day.month, day: day.day, itemCount: day.itemCount });
  }
  host.orderedDays = orderedDays;
  const sections: GalleryAlbumDaySectionModel[] = [];
  for (let i = 0; i < snap.sections.length; i++) {
    const plain = snap.sections[i];
    const section = new GalleryAlbumDaySectionModel();
    section.year = plain.year;
    section.month = plain.month;
    section.day = plain.day;
    section.itemCount = plain.itemCount;
    section.nextOffset = plain.nextOffset;
    section.slotByOffset.clear();
    if (plain.slotOffsets !== undefined && plain.slotItems !== undefined && plain.slotOffsets.length === plain.slotItems.length) {
      for (let j = 0; j < plain.slotOffsets.length; j++) {
        section.slotByOffset.set(plain.slotOffsets[j], plain.slotItems[j]);
      }
    } else if (plain.items !== undefined) {
      for (let j = 0; j < plain.items.length; j++) {
        section.slotByOffset.set(j, plain.items[j]);
      }
    }
    sections.push(section);
  }
  host.sections = sections;
  fillMapFromArrays(host.dayOffsets, snap.dayOffsetsKeys, snap.dayOffsetsVals);
  fillMapFromArrays(host.dayRounds, snap.dayRoundsKeys, snap.dayRoundsVals);
  fillMapFromArrays(host.dayEmptyRounds, snap.dayEmptyKeys, snap.dayEmptyVals);
  host.dayIndex = snap.dayIndex;
  host.exhausted = snap.exhausted;
  host.footText = snap.footText;
  host.loadError = '';
  host.bootLoading = false;
  host.loadingMore = false;
  host.lastBootstrapSatisfiedRefreshVersion = snap.refreshVersionAtSave;
}
