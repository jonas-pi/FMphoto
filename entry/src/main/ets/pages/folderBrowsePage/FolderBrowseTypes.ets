import { GalleryListItem } from '../../model/FnApiTypes';

export const FOLDER_BROWSE_PAGE_SIZE: number = 100;
export const FOLDER_BROWSE_COVER_BATCH: number = 50;
export const FOLDER_BROWSE_BASE_COLUMNS: number = 4;
export const FOLDER_BROWSE_KIND_FOLDER: string = 'folder';
export const FOLDER_BROWSE_KIND_MEDIA: string = 'media';

/** 当前目录下的子文件夹（含封面相对路径） */
export class FolderBrowseFolderItem {
  path: string = '';
  name: string = '';
  coverUri: string = '';
}

/** 图标宫格混合项：文件夹在前，媒体在后 */
export class FolderBrowseGridItem {
  kind: string = FOLDER_BROWSE_KIND_FOLDER;
  key: string = '';
  title: string = '';
  folderPath: string = '';
  coverUri: string = '';
  media: GalleryListItem | undefined = undefined;
  mediaIndex: number = -1;
}
