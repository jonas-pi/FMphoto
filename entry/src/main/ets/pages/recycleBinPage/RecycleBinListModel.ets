import { RecycleBinListItem } from '../../model/FnApiTypes';
import { recycleBinNumericIdOf, recycleBinThumbRelOf } from './RecycleBinSelectionController';

export interface RecycleBinRowBlockCell {
  flatIdx: number;
  item?: RecycleBinListItem;
  thumbRel: string;
  numericId: number;
}

export interface RecycleBinRowBlock {
  key: string;
  rowIdx: number;
  rowStart: number;
  cells: RecycleBinRowBlockCell[];
}

export function recycleBinBuildRowBlocks(
  items: RecycleBinListItem[],
  columnsPerRow: number
): RecycleBinRowBlock[] {
  const blocks: RecycleBinRowBlock[] = [];
  const cols = columnsPerRow;
  const rowCount = Math.ceil(items.length / cols);
  for (let rowIdx = 0; rowIdx < rowCount; rowIdx++) {
    const rowStart = rowIdx * cols;
    const cells: RecycleBinRowBlockCell[] = [];
    let cellSig = '';
    for (let col = 0; col < cols; col++) {
      const flatIdx = rowStart + col;
      if (flatIdx >= items.length) {
        cells.push({
          flatIdx: -1,
          thumbRel: '',
          numericId: -1
        });
        cellSig += `_sk${col}`;
        continue;
      }
      const item = items[flatIdx];
      const numericId = recycleBinNumericIdOf(item);
      cells.push({
        flatIdx,
        item,
        thumbRel: recycleBinThumbRelOf(item),
        numericId
      });
      cellSig += numericId >= 0 ? `_id${numericId}` : `_idx${flatIdx}`;
    }
    blocks.push({
      key: `rbrow_${rowIdx}${cellSig}`,
      rowIdx,
      rowStart,
      cells
    });
  }
  return blocks;
}
