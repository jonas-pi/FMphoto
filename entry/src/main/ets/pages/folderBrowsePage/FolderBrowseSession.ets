import { LivePhotoSaveChoice } from '../../album/livephoto/LivePhotoSaveActionSheet';
import { GalleryGridSlideTouchSession } from '../../album/GalleryGridSlideTouch';
import { FnListDataSource } from '../../common/FnListDataSource';
import { GalleryListItem } from '../../model/FnApiTypes';
import {
  FolderBrowseFolderItem,
  FolderBrowseRowBlock,
  FolderBrowseThumbHitRect
} from './FolderBrowseTypes';

export class FolderBrowseSelectionRuntime {
  selectedIds: string[] = [];
  fbThumbHitBounds: Map<string, FolderBrowseThumbHitRect> = new Map<string, FolderBrowseThumbHitRect>();
  fbSlideRefX: number = 0;
  fbSlideRefY: number = 0;
  fbSlideHasRef: boolean = false;
  fbSlideAnchorFlat: number = -1;
  fbSlideUnionBase: string[] = [];
  fbSlideLastEndFlat: number = -1;
  fbSlideLastAppliedEndFlat: number = -99999;
  fbLongPressIgnoreUntil: number = 0;
}

export class FolderBrowseNavRuntime {
  pathStack: string[] = [];
  entryFloorPath: string = '';
  lockToEntry: boolean = false;
  entryFloorResolved: boolean = true;
  allowedRootPaths: string[] = [];
  /**
   * 这次打开时落点在 pathStack 里的下标。空栈（文件夹根）为 -1。
   * 用「上一级」越过它之后不再改这个值。
   */
  entryStopIndex: number = -1;
  /**
   * 系统返回停在这一层就离开页面。起初等于 entryStopIndex。
   * 用「上一级」越过入口后降到文件夹根（锁定入口时是虚拟根 ''，否则是空栈）。
   */
  backStopIndex: number = -1;
  folders: FolderBrowseFolderItem[] = [];
  mediaItems: GalleryListItem[] = [];
}

export class FolderBrowseLoadRuntime {
  loadGen: number = 0;
  mediaOffset: number = 0;
  mediaHasMore: boolean = false;
  folderChanging: boolean = false;
}

export class FolderBrowseOverlayRuntime {
  choiceSheetResolver: ((index: number) => void) | undefined = undefined;
  liveSaveResolver: ((choice: LivePhotoSaveChoice) => void) | undefined = undefined;
  slideshowRequestSeq: number = 0;
  thumbResumeTimer: number = -1;
  slideTouch: GalleryGridSlideTouchSession = new GalleryGridSlideTouchSession();
  listScroller: Scroller = new Scroller();
  rowSource: FnListDataSource<FolderBrowseRowBlock> = new FnListDataSource<FolderBrowseRowBlock>();
}

/**
 * 文件夹浏览非响应式运行态。@State/@Prop/@Watch 仍留在 FolderBrowsePage shell。
 */
export class FolderBrowseSession {
  selection: FolderBrowseSelectionRuntime = new FolderBrowseSelectionRuntime();
  nav: FolderBrowseNavRuntime = new FolderBrowseNavRuntime();
  load: FolderBrowseLoadRuntime = new FolderBrowseLoadRuntime();
  overlay: FolderBrowseOverlayRuntime = new FolderBrowseOverlayRuntime();
}
