/**
 * 飞牛搜索选项（与官方 Web 搜索面板字段对齐）。
 * 正向条件走 filters，整理里的「无 xxx」走 antiFilters。
 */

/** 级联树节点（拍摄时间 / 地点 / 相册 / 文件夹 / 拍摄信息） */
export class GallerySearchFilterTreeNode {
  label: string = '';
  value: string = '';
  children: GallerySearchFilterTreeNode[] = [];
}

/** 下拉/列表选项 */
export class GallerySearchPickerOption {
  label: string = '';
  value: string = '';
  path: string[] = [];
  /** 人物选项头像相对路径；其它字段为空 */
  avatarUrl: string = '';
  /** 当前层是否还有子级，用于级联下钻 */
  hasChildren: boolean = false;
}

/** 已选筛选快照：提交 search/results 或 magic-search 时使用 */
export class GallerySearchFilterSnapshot {
  isCollect: boolean = false;
  notAlbum: boolean = false;
  notTag: boolean = false;
  notGeo: boolean = false;
  fileType: string = '';
  fileTypeLabel: string = '';
  personId: string = '';
  personLabel: string = '';
  personAvatar: string = '';
  datePath: string[] = [];
  dateLabel: string = '';
  locationPath: string[] = [];
  locationLabel: string = '';
  albumPath: string[] = [];
  albumLabel: string = '';
  folderPath: string[] = [];
  folderLabel: string = '';
  showShootingInfo: boolean = false;
  makeModelPath: string[] = [];
  makeModelLabel: string = '';
  focalLengthPath: string[] = [];
  focalLengthLabel: string = '';
  exposurePath: string[] = [];
  exposureLabel: string = '';
  aperturePath: string[] = [];
  apertureLabel: string = '';
  isoPath: string[] = [];
  isoLabel: string = '';
}

/** 面板打开时加载的选项目录 */
export class GallerySearchFilterCatalog {
  fileTypes: GallerySearchPickerOption[] = [];
  persons: GallerySearchPickerOption[] = [];
  dates: GallerySearchFilterTreeNode[] = [];
  locations: GallerySearchFilterTreeNode[] = [];
  albums: GallerySearchFilterTreeNode[] = [];
  folders: GallerySearchFilterTreeNode[] = [];
  makeModels: GallerySearchFilterTreeNode[] = [];
  focalLengths: GallerySearchFilterTreeNode[] = [];
  exposures: GallerySearchFilterTreeNode[] = [];
  apertures: GallerySearchFilterTreeNode[] = [];
  isos: GallerySearchFilterTreeNode[] = [];
}

export const SEARCH_FILTER_FIELD_FILE_TYPE: string = 'file_type';
export const SEARCH_FILTER_FIELD_PERSON: string = 'person';
export const SEARCH_FILTER_FIELD_DATE: string = 'photo_date';
export const SEARCH_FILTER_FIELD_LOCATION: string = 'photo_location';
export const SEARCH_FILTER_FIELD_ALBUM: string = 'album_name';
export const SEARCH_FILTER_FIELD_FOLDER: string = 'file_dir';
export const SEARCH_FILTER_FIELD_MAKE: string = 'make_model';
export const SEARCH_FILTER_FIELD_FOCAL: string = 'focal_length';
export const SEARCH_FILTER_FIELD_EXPOSURE: string = 'exposure_time';
export const SEARCH_FILTER_FIELD_APERTURE: string = 'fumber';
export const SEARCH_FILTER_FIELD_ISO: string = 'ISO_speed_ratings';
