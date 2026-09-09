import { GalleryListItem } from '../../model/FnApiTypes';
import { fnClampGridColumns } from '../../common/FnWindowBreakpoint';
import { DayGroup, RowModel } from './CategoryGalleryTypes';
import { categoryGalleryItemIdOf } from './CategoryGallerySelectionController';

export interface CategoryGalleryListBlock {
  key: string;
  isHeader: boolean;
  groupIdx: number;
  label?: string;
  row?: RowModel;
}

function categoryGalleryRowCellAt(row: RowModel, col: number): GalleryListItem | undefined {
  return col >= 0 && col < row.cells.length ? row.cells[col] : undefined;
}

function categoryGalleryFlatPosOf(groupOffsets: number[], groupIdx: number, idxInGroup: number): number {
  const base = groupIdx >= 0 && groupIdx < groupOffsets.length ? groupOffsets[groupIdx] : 0;
  return base + idxInGroup;
}

export function categoryGalleryBuildListBlocks(
  groups: DayGroup[],
  columnsPerRow: number,
  groupOffsets: number[]
): Array<CategoryGalleryListBlock> {
  const blocks: Array<CategoryGalleryListBlock> = [];
  for (let groupIdx = 0; groupIdx < groups.length; groupIdx++) {
    const group = groups[groupIdx];
    if (group.label.length > 0) {
      blocks.push({
        key: `h_${group.sortKey}`,
        isHeader: true,
        groupIdx: groupIdx,
        label: group.label
      });
    }
    for (let rowIdx = 0; rowIdx < group.rows.length; rowIdx++) {
      const row = group.rows[rowIdx];
      const cellKeys: string[] = [];
      const cols = fnClampGridColumns(columnsPerRow);
      for (let col = 0; col < cols; col++) {
        const item = categoryGalleryRowCellAt(row, col);
        if (item === undefined) {
          cellKeys.push(`empty_${col}`);
          continue;
        }
        const id = categoryGalleryItemIdOf(item);
        if (id.length > 0) {
          cellKeys.push(`id_${id}`);
          continue;
        }
        cellKeys.push(`flat_${categoryGalleryFlatPosOf(groupOffsets, groupIdx, row.startIdx + col)}`);
      }
      blocks.push({
        key: `r_${group.sortKey}_${row.startIdx}_${cellKeys.join('__')}`,
        isHeader: false,
        groupIdx: groupIdx,
        row: row
      });
    }
  }
  return blocks;
}
