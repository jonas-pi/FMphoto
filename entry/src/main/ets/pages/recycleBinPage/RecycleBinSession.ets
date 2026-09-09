import { LivePhotoSaveChoice } from '../../album/livephoto/LivePhotoSaveActionSheet';
import { GalleryGridSlideTouchSession } from '../../album/GalleryGridSlideTouch';
import { FnListDataSource } from '../../common/FnListDataSource';
import { RecycleBinRowBlock } from './RecycleBinListModel';
import { RbThumbHitRect } from './RecycleBinTypes';

export class RecycleBinSelectionRuntime {
  selectedIds: number[] = [];
  rbThumbHitBounds: Map<string, RbThumbHitRect> = new Map<string, RbThumbHitRect>();
  rbSlideRefX: number = 0;
  rbSlideRefY: number = 0;
  rbSlideHasRef: boolean = false;
  rbSlideAnchorFlat: number = -1;
  rbSlideUnionBase: number[] = [];
  rbSlideLastEndFlat: number = -1;
  rbSlideLastAppliedEndFlat: number = -99999;
  rbLongPressIgnoreUntil: number = 0;
}

export class RecycleBinListRuntime {
  rbRowBlocks: RecycleBinRowBlock[] = [];
  rbRowSource: FnListDataSource<RecycleBinRowBlock> = new FnListDataSource<RecycleBinRowBlock>();
  slideTouch: GalleryGridSlideTouchSession = new GalleryGridSlideTouchSession();
  listScroller: Scroller = new Scroller();
}

export class RecycleBinOverlayRuntime {
  choiceSheetResolver: ((index: number) => void) | undefined = undefined;
  liveSaveResolver: ((choice: LivePhotoSaveChoice) => void) | undefined = undefined;
  rbThumbResumeTimer: number = -1;
}

/**
 * 回收站非响应式运行态。@State/@Prop/@Watch 仍留在 RecycleBinPage shell。
 */
export class RecycleBinSession {
  selection: RecycleBinSelectionRuntime = new RecycleBinSelectionRuntime();
  list: RecycleBinListRuntime = new RecycleBinListRuntime();
  overlay: RecycleBinOverlayRuntime = new RecycleBinOverlayRuntime();
}
