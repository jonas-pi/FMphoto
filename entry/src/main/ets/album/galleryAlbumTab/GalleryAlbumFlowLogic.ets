import { GalleryListItem } from '../../model/FnApiTypes';
import { GalleryFlowNode } from '../GalleryFlowDataSource';
import { GalleryAlbumDaySectionModel, GalleryAlbumDaySectionState } from './GalleryAlbumState';
import { dayKey, TimelineDayModel, ymKey } from './GalleryAlbumTabTypes';
import { GalleryAlbumVisibleLoadHost } from './GalleryAlbumVisibleLoadController';

export function galleryAlbumItemIdOf(item: GalleryListItem): string {
  if (item.id === undefined || item.id === null) {
    return '';
  }
  return String(item.id).trim();
}

export function galleryAlbumFlatItems(host: GalleryAlbumVisibleLoadHost): GalleryListItem[] {
  const out: GalleryListItem[] = [];
  const secByDay = new Map<string, GalleryAlbumDaySectionState>();
  for (let i = 0; i < host.sections.length; i++) {
    const section = host.sections[i];
    secByDay.set(dayKey(section.year, section.month, section.day), section);
  }
  if (host.orderedDays.length > 0) {
    for (let di = 0; di < host.orderedDays.length; di++) {
      const day = host.orderedDays[di];
      const section = secByDay.get(dayKey(day.year, day.month, day.day));
      if (section === undefined) {
        continue;
      }
      const count = Math.max(0, day.itemCount);
      for (let off = 0; off < count; off++) {
        const item = section.slotByOffset.get(off);
        if (item !== undefined) {
          out.push(item);
        }
      }
    }
    return out;
  }
  for (let i = 0; i < host.sections.length; i++) {
    const section = host.sections[i];
    const keys = Array.from(section.slotByOffset.keys()).sort((a: number, b: number): number => a - b);
    for (let j = 0; j < keys.length; j++) {
      const item = section.slotByOffset.get(keys[j]);
      if (item !== undefined) {
        out.push(item);
      }
    }
  }
  return out;
}

export function galleryAlbumGalleryFlowLazyKey(node: GalleryFlowNode): string {
  if (node.kind !== 'row') {
    return node.key;
  }
  let slotSig = '';
  for (let i = 0; i < node.rowSlotItems.length; i++) {
    if (i > 0) {
      slotSig += 'x';
    }
    const slot = node.rowSlotItems[i];
    if (slot === null || slot === undefined) {
      slotSig += `sk${i}`;
      continue;
    }
    const id = galleryAlbumItemIdOf(slot);
    slotSig += id.length > 0 ? `id${id}` : `it${i}`;
  }
  return `${node.key}_s${slotSig}`;
}

export function galleryAlbumRebuildFlow(host: GalleryAlbumVisibleLoadHost): void {
  if (host.timelineSidebarDragging || host.isDraggingOrFling) {
    host.pendingFlowRebuild = true;
    return;
  }
  const nodes: GalleryFlowNode[] = [];
  const secMap = new Map<string, GalleryAlbumDaySectionState>();
  for (let i = 0; i < host.sections.length; i++) {
    const section = host.sections[i];
    secMap.set(dayKey(section.year, section.month, section.day), section);
  }

  let flatLoaded = 0;

  if (host.orderedDays.length > 0) {
    for (let i = 0; i < host.orderedDays.length; i++) {
      const day = host.orderedDays[i];
      const prevDay = i > 0 ? host.orderedDays[i - 1] : undefined;
      const showMonth = prevDay === undefined || ymKey(day.year, day.month) !== ymKey(prevDay.year, prevDay.month);
      if (showMonth) {
        const monthNode = new GalleryFlowNode();
        monthNode.kind = 'month';
        monthNode.key = `m_${day.year}_${day.month}_od_${i}`;
        monthNode.year = day.year;
        monthNode.month = day.month;
        monthNode.globalPhotoSlotStart = flatLoaded;
        nodes.push(monthNode);
      }

      const dayNode = new GalleryFlowNode();
      dayNode.kind = 'day';
      dayNode.key = `d_${day.year}_${day.month}_${day.day}_od_${i}`;
      dayNode.year = day.year;
      dayNode.month = day.month;
      dayNode.day = day.day;
      dayNode.globalPhotoSlotStart = flatLoaded;
      nodes.push(dayNode);

      const section = secMap.get(dayKey(day.year, day.month, day.day));
      const totalCount = Math.max(0, day.itemCount);
      const totalRows = Math.ceil(totalCount / 3);
      for (let row = 0; row < totalRows; row++) {
        const rowNode = new GalleryFlowNode();
        rowNode.kind = 'row';
        rowNode.key = `r_${day.year}_${day.month}_${day.day}_row_${row}`;
        rowNode.year = day.year;
        rowNode.month = day.month;
        rowNode.day = day.day;
        rowNode.globalPhotoSlotStart = flatLoaded;

        const rowStart = row * 3;
        const totalInRow = Math.min(3, Math.max(0, totalCount - rowStart));
        for (let k = 0; k < totalInRow; k++) {
          const localOff = rowStart + k;
          const item = section !== undefined ? section.slotByOffset.get(localOff) : undefined;
          if (item !== undefined) {
            rowNode.rowSlotItems.push(item);
            rowNode.rowSlotFlatIndices.push(flatLoaded);
            flatLoaded++;
          } else {
            rowNode.rowSlotItems.push(null);
            rowNode.rowSlotFlatIndices.push(-1);
          }
        }
        nodes.push(rowNode);
      }
    }
  } else {
    for (let i = 0; i < host.sections.length; i++) {
      const section = host.sections[i];
      const prev = i > 0 ? host.sections[i - 1] : undefined;
      const showMonth = prev === undefined || ymKey(section.year, section.month) !== ymKey(prev.year, prev.month);
      if (showMonth) {
        const monthNode = new GalleryFlowNode();
        monthNode.kind = 'month';
        monthNode.key = `m_${section.year}_${section.month}_i${i}`;
        monthNode.year = section.year;
        monthNode.month = section.month;
        monthNode.globalPhotoSlotStart = flatLoaded;
        nodes.push(monthNode);
      }
      const dayNode = new GalleryFlowNode();
      dayNode.kind = 'day';
      dayNode.key = `d_${section.year}_${section.month}_${section.day}`;
      dayNode.year = section.year;
      dayNode.month = section.month;
      dayNode.day = section.day;
      dayNode.globalPhotoSlotStart = flatLoaded;
      nodes.push(dayNode);

      const keys = Array.from(section.slotByOffset.keys()).sort((a: number, b: number): number => a - b);
      if (keys.length === 0) {
        continue;
      }
      const maxOff = keys[keys.length - 1];
      const totalCount = Math.max(maxOff + 1, section.itemCount > 0 ? section.itemCount : keys.length);
      const totalRows = Math.ceil(totalCount / 3);
      for (let row = 0; row < totalRows; row++) {
        const rowNode = new GalleryFlowNode();
        rowNode.kind = 'row';
        rowNode.key = `r_${section.year}_${section.month}_${section.day}_row_${row}`;
        rowNode.year = section.year;
        rowNode.month = section.month;
        rowNode.day = section.day;
        rowNode.globalPhotoSlotStart = flatLoaded;
        const rowStart = row * 3;
        const totalInRow = Math.min(3, Math.max(0, totalCount - rowStart));
        for (let k = 0; k < totalInRow; k++) {
          const localOff = rowStart + k;
          const item = section.slotByOffset.get(localOff);
          if (item !== undefined) {
            rowNode.rowSlotItems.push(item);
            rowNode.rowSlotFlatIndices.push(flatLoaded);
            flatLoaded++;
          } else {
            rowNode.rowSlotItems.push(null);
            rowNode.rowSlotFlatIndices.push(-1);
          }
        }
        nodes.push(rowNode);
      }
    }
  }

  host.listScrollIndexAnchorHave = false;
  host.flowDataSource.reloadAll(nodes);
}

export function galleryAlbumCountGalleryListedItems(sections: GalleryAlbumDaySectionState[]): number {
  let count = 0;
  for (let i = 0; i < sections.length; i++) {
    count += sections[i].slotByOffset.size;
  }
  return count;
}

export function galleryAlbumUpsertSection(
  host: GalleryAlbumVisibleLoadHost,
  day: TimelineDayModel,
  newItems: GalleryListItem[],
  newOffset: number
): void {
  const idx = host.sections.findIndex(
    (section: GalleryAlbumDaySectionState): boolean =>
      section.year === day.year && section.month === day.month && section.day === day.day
  );
  const startOff = newOffset - newItems.length;
  if (idx < 0) {
    const section = new GalleryAlbumDaySectionModel();
    section.year = day.year;
    section.month = day.month;
    section.day = day.day;
    section.itemCount = day.itemCount;
    for (let i = 0; i < newItems.length; i++) {
      section.slotByOffset.set(startOff + i, newItems[i]);
    }
    section.nextOffset = newOffset;
    host.sections = host.sections.concat([section]);
  } else {
    const section = host.sections[idx];
    section.itemCount = day.itemCount;
    for (let i = 0; i < newItems.length; i++) {
      section.slotByOffset.set(startOff + i, newItems[i]);
    }
    section.nextOffset = newOffset;
  }
  galleryAlbumRebuildFlow(host);
}
