import { LivePhotoSaveChoice } from '../../album/livephoto/LivePhotoSaveActionSheet';
import { GalleryGridSlideTouchSession } from '../../album/GalleryGridSlideTouch';
import { FnListDataSource } from '../../common/FnListDataSource';
import { GalleryListItem } from '../../model/FnApiTypes';
import { CategoryGalleryListBlock } from './CategoryGalleryListModel';
import { CgThumbHitRect } from './CategoryGalleryTypes';

export class CategoryGallerySelectionRuntime {
  selectedIds: string[] = [];
  cgThumbHitBounds: Map<string, CgThumbHitRect> = new Map<string, CgThumbHitRect>();
  cgSlideRefX: number = 0;
  cgSlideRefY: number = 0;
  cgSlideHasRef: boolean = false;
  cgSlideAnchorFlat: number = -1;
  cgSlideUnionBase: string[] = [];
  cgSlideLastEndFlat: number = -1;
  cgSlideLastAppliedEndFlat: number = -99999;
  cgLongPressIgnoreUntil: number = 0;
}

export class CategoryGallerySyncRuntime {
  flatItems: GalleryListItem[] = [];
  groupOffsets: number[] = [];
  listBlocks: Array<CategoryGalleryListBlock> = [];
  listBlockSource: FnListDataSource<CategoryGalleryListBlock> = new FnListDataSource<CategoryGalleryListBlock>();
  pageSessionToken: number = -1;
  pageSourceKind: string = '';
  pageCategoryKey: string = '';
  pageFolderPath: string = '';
  pageUseCreatedAtGrouping: boolean = false;
  cgObservedStoreVersion: number = -1;
  cgPendingStoreSync: boolean = false;
  cgStorePollTimer: number = -1;
  cgDeferredBackgroundLoadTimer: number = -1;
  cgDeferredSnapshotApplyTimer: number = -1;
  cgLastSnapshotApplyAtMs: number = 0;
}

export class CategoryGalleryGuardRuntime {
  /**
   * 页面活动标记必须使用普通字段，不能使用 @State。
   * 只用于阻止已排入事件队列的定时器/网络回调在组件销毁后继续修改响应式状态。
   */
  cgPageActive: boolean = false;
  handledDeleteSyncVersion: number = 0;
  slideshowRequestSeq: number = 0;
}

export class CategoryGalleryOverlayRuntime {
  choiceSheetResolver: ((index: number) => void) | undefined = undefined;
  liveSaveResolver: ((choice: LivePhotoSaveChoice) => void) | undefined = undefined;
  cgThumbResumeTimer: number = -1;
  slideTouch: GalleryGridSlideTouchSession = new GalleryGridSlideTouchSession();
  listScroller: Scroller = new Scroller();
}

/**
 * 分类宫格非响应式运行态。@State/@Prop/@Watch 仍留在 CategoryGallery shell。
 */
export class CategoryGallerySession {
  selection: CategoryGallerySelectionRuntime = new CategoryGallerySelectionRuntime();
  sync: CategoryGallerySyncRuntime = new CategoryGallerySyncRuntime();
  guard: CategoryGalleryGuardRuntime = new CategoryGalleryGuardRuntime();
  overlay: CategoryGalleryOverlayRuntime = new CategoryGalleryOverlayRuntime();
}
