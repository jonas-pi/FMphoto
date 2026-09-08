import { UIContext } from '@kit.ArkUI';
import { AppSession, FN_MEDIA_BASE_URL } from '../auth/AppSession';
import {
  FnClientResult,
  FolderViewCoverItem,
  GalleryListItem,
  PhotoFolderListData,
  PhotoFolderListItem
} from '../model/FnApiTypes';
import {
  GalleryNetworkThumb,
  isGifItem,
  isVideoItem,
  nasUrl,
  pickThumb,
  trimThumbPixCacheForList
} from '../album/GalleryAlbumCommon';
import { isLivePhotoItem } from '../album/livephoto/LivePhotoDetect';
import {
  askLivePhotoSaveChoice,
  LivePhotoSaveActionSheet,
  LivePhotoSaveChoice,
  LIVE_PHOTO_PRIVILEGE_SHEET_TITLE
} from '../album/livephoto/LivePhotoSaveActionSheet';
import { FnHdsChoiceSheet, fnHdsFitContentSheetOptions, fnHdsSaveButtonSheetOptions } from '../common/FnHdsOverlay';
import { GalleryAlbumNavigation } from '../album/GalleryAlbumNavigation';
import { GalleryPreviewNavStore } from '../album/GalleryPreviewNavStore';
import { GALLERY_PREVIEW_OPENING_KEY } from '../album/GalleryPreviewEntryGate';
import {
  GALLERY_PREVIEW_HERO_ACTIVE_KEY,
  GALLERY_PREVIEW_SOURCE_FOLDER_ID,
  gallerySharedSourceDomId
} from '../album/GallerySharedTransition';
import { GalleryPreviewOpeningMask } from '../album/GalleryPreviewOpeningMask';
import { GalleryAlbumBatchActionBar } from '../album/GalleryAlbumBatchActionBar';
import {
  GALLERY_SELECTION_SCOPE_FOLDER,
  GalleryAlbumSelectionOverlay,
  galleryAlbumSyncSelectionVisualState
} from '../album/galleryAlbumTab/GalleryAlbumSelectionOverlay';
import { gallerySlideshowLaunchForItems } from '../album/slideshow/GallerySlideshowLauncher';
import {
  GallerySlideshowConfig,
  GallerySlideshowScope,
  GallerySlideshowScopeKind,
  gallerySlideshowScopeLabel
} from '../album/slideshow/GallerySlideshowTypes';
import { GallerySlideshowSettingsSheet } from '../album/slideshow/GallerySlideshowSettingsSheet';
import { FnListDataSource } from '../common/FnListDataSource';
import { FN_SYSTEM_TOP_INSET_VP_KEY } from '../common/FnSystemAvoidArea';
import { FN_WINDOW_WIDTH_BP_KEY, fnAdaptiveGridColumns, fnRepeatFrTemplate } from '../common/FnWindowBreakpoint';
import { FnFullLoadingMask, FnInlineLoading, FnStateText } from '../common/FnUiCommon';
import { GALLERY_BATCH_BAR_TOTAL_HEIGHT_VP } from '../common/GalleryButtonStyles';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import {
  FOLDER_BROWSE_BASE_COLUMNS,
  FOLDER_BROWSE_COVER_BATCH,
  FOLDER_BROWSE_KIND_FOLDER,
  FOLDER_BROWSE_KIND_MEDIA,
  FOLDER_BROWSE_PAGE_SIZE,
  FolderBrowseFolderItem,
  FolderBrowseGridItem
} from './folderBrowsePage/FolderBrowseTypes';
import {
  folderBrowseApplyCoverUris,
  folderBrowseBuildGrid,
  folderBrowseCoverDirNames,
  folderBrowseCoverDirNamesFallback,
  folderBrowseFoldersFromList,
  folderBrowseLabelOf,
  folderBrowseMediaId,
  folderBrowsePathStackFromPath,
  folderBrowsePermissionMessage
} from './folderBrowsePage/FolderBrowseLogic';
import { FolderBrowseChrome } from './folderBrowsePage/FolderBrowseChrome';
import { FolderBrowseNavStore } from './folderBrowsePage/FolderBrowseNavStore';
import {
  folderBrowseConfirmBatchDelete,
  folderBrowseConfirmBatchDownload,
  FolderBrowseBatchActionsHost
} from './folderBrowsePage/FolderBrowseBatchActions';

@Entry
@Component
struct FolderBrowsePage {
  private albumNavigationMode: boolean = false;
  @StorageProp(FN_MEDIA_BASE_URL) private baseUrl: string = '';
  @StorageProp(FN_WINDOW_WIDTH_BP_KEY) private windowWidthBp: number = WidthBreakpoint.WIDTH_SM;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(GALLERY_PREVIEW_OPENING_KEY) private previewOpening: boolean = false;
  @StorageProp(GALLERY_PREVIEW_HERO_ACTIVE_KEY) private previewHeroActive: boolean = false;
  @State private loading: boolean = false;
  @State private loadingMore: boolean = false;
  @State private error: string = '';
  @State private title: string = '文件夹';
  @State private thumbLoadingPaused: boolean = false;
  @State private gridItems: FolderBrowseGridItem[] = [];
  @State private selectionMode: boolean = false;
  @State private selectedCount: number = 0;
  @State private moreMenuExpanded: boolean = false;
  @State private slideshowSettingsVisible: boolean = false;
  @State private slideshowPreparing: boolean = false;
  @State private batchDeleting: boolean = false;
  @State private batchDownloading: boolean = false;
  @State private liveSaveSheetVisible: boolean = false;
  @State private choiceSheetVisible: boolean = false;
  @State private choiceSheetTitle: string = '';
  @State private choiceSheetButtons: string[] = [];
  private readonly gridSource: FnListDataSource<FolderBrowseGridItem> = new FnListDataSource<FolderBrowseGridItem>();
  private readonly gridScroller: Scroller = new Scroller();
  private pathStack: string[] = [];
  private folders: FolderBrowseFolderItem[] = [];
  private mediaItems: GalleryListItem[] = [];
  private selectedIds: string[] = [];
  private mediaOffset: number = 0;
  private mediaHasMore: boolean = false;
  private loadGen: number = 0;
  private albumBackHandlerToken: number = 0;
  private thumbResumeTimer: number = -1;
  private slideshowRequestSeq: number = 0;
  private liveSaveResolver: ((choice: LivePhotoSaveChoice) => void) | undefined = undefined;
  private choiceSheetResolver: ((index: number) => void) | undefined = undefined;

  onBackPress(): boolean {
    this.handleBack();
    return true;
  }

  private handleBack(): void {
    if (this.liveSaveSheetVisible) {
      this.completeLivePhotoSave('cancel');
      return;
    }
    if (this.choiceSheetVisible) {
      this.completeChoice(-1);
      return;
    }
    if (this.slideshowSettingsVisible) {
      this.dismissSlideshowSettings();
      return;
    }
    if (this.moreMenuExpanded) {
      this.dismissMoreMenu();
      return;
    }
    if (this.selectionMode) {
      this.exitSelection();
      return;
    }
    if (this.pathStack.length > 0) {
      this.pathStack.pop();
      void this.loadCurrent(true);
      return;
    }
    this.navigateOut();
  }

  private navigateOut(): void {
    if (!this.albumNavigationMode || !GalleryAlbumNavigation.pop()) {
      this.getUIContext().getRouter().back();
    }
  }

  aboutToAppear(): void {
    this.albumNavigationMode = GalleryAlbumNavigation.isAvailable();
    this.thumbLoadingPaused = false;
    this.applyIncomingFolderPath();
    if (this.albumNavigationMode) {
      this.albumBackHandlerToken = GalleryAlbumNavigation.registerBackHandler((): boolean => {
        this.handleBack();
        return true;
      });
    } else {
      const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
      if (rp !== undefined && rp['baseUrl'] !== undefined) {
        this.baseUrl = String(rp['baseUrl']);
      }
    }
    void this.loadCurrent(true);
  }

  aboutToDisappear(): void {
    GalleryAlbumNavigation.unregisterBackHandler(this.albumBackHandlerToken);
    this.clearThumbResumeTimer();
    trimThumbPixCacheForList(this.gridItems.length, false);
    galleryAlbumSyncSelectionVisualState(false, [], GALLERY_SELECTION_SCOPE_FOLDER);
  }

  private applyIncomingFolderPath(): void {
    let incoming = FolderBrowseNavStore.consumePendingPath();
    if (incoming.length === 0) {
      const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
      if (rp !== undefined && rp['folderPath'] !== undefined) {
        incoming = String(rp['folderPath']);
      }
    }
    this.pathStack = folderBrowsePathStackFromPath(incoming);
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {
    }
  }

  private currentPath(): string {
    if (this.pathStack.length === 0) {
      return '';
    }
    return this.pathStack[this.pathStack.length - 1];
  }

  private syncTitle(): void {
    const path = this.currentPath();
    this.title = path.length === 0 ? '文件夹' : folderBrowseLabelOf(path);
  }

  private publishGrid(): void {
    const next = folderBrowseBuildGrid(this.folders, this.mediaItems);
    this.gridItems = next;
    this.gridSource.reloadAll(next);
  }

  private totalCount(): number {
    return this.gridItems.length;
  }

  private clearThumbResumeTimer(): void {
    if (this.thumbResumeTimer >= 0) {
      clearTimeout(this.thumbResumeTimer);
      this.thumbResumeTimer = -1;
    }
  }

  private onGridScrollStateChange(scrollState: ScrollState): void {
    if (scrollState !== ScrollState.Idle) {
      this.clearThumbResumeTimer();
      if (!this.thumbLoadingPaused) {
        this.thumbLoadingPaused = true;
      }
      trimThumbPixCacheForList(this.gridItems.length, false);
      return;
    }
    this.clearThumbResumeTimer();
    this.thumbResumeTimer = setTimeout((): void => {
      this.thumbResumeTimer = -1;
      this.thumbLoadingPaused = false;
    }, 96);
  }

  private async loadCurrent(reset: boolean): Promise<void> {
    const gen = ++this.loadGen;
    this.syncTitle();
    this.error = '';
    if (reset) {
      if (this.selectionMode) {
        this.exitSelection();
      }
      this.loading = true;
      this.folders = [];
      this.mediaItems = [];
      this.mediaOffset = 0;
      this.mediaHasMore = false;
      this.publishGrid();
    }
    const client = AppSession.getClient();
    if (client === null) {
      this.loading = false;
      this.error = '未登录';
      return;
    }
    const path = this.currentPath();
    try {
      let folderRes: FnClientResult<PhotoFolderListData>;
      if (path.length === 0) {
        folderRes = await client.getPhotoFolderList(20000);
      } else {
        folderRes = await client.getFolderViewFolderList(path, false, 2, 20000);
      }
      if (gen !== this.loadGen) {
        return;
      }
      if (!folderRes.success || folderRes.data === undefined) {
        this.error = folderBrowsePermissionMessage(folderRes.message ?? '文件夹列表加载失败');
        this.loading = false;
        return;
      }
      const rawFolders: PhotoFolderListItem[] = folderRes.data.list ?? folderRes.data.items ?? [];
      this.folders = folderBrowseFoldersFromList(rawFolders);

      if (path.length > 0) {
        const fileRes = await client.getFolderViewFileList(path, FOLDER_BROWSE_PAGE_SIZE, 0, false, 2, 20000);
        if (gen !== this.loadGen) {
          return;
        }
        if (!fileRes.success || fileRes.data === undefined) {
          this.error = folderBrowsePermissionMessage(fileRes.message ?? '文件夹媒体加载失败');
          this.loading = false;
          this.publishGrid();
          void this.loadCovers(gen, path);
          return;
        }
        this.mediaItems = fileRes.data.slice();
        this.mediaOffset = this.mediaItems.length;
        this.mediaHasMore = fileRes.data.length >= FOLDER_BROWSE_PAGE_SIZE;
      } else {
        this.mediaItems = [];
        this.mediaOffset = 0;
        this.mediaHasMore = false;
      }

      if (this.folders.length === 0 && this.mediaItems.length === 0) {
        this.error = path.length === 0 ? '文件夹列表为空' : '文件夹为空';
      }
      this.publishGrid();
      this.loading = false;
      void this.loadCovers(gen, path);
    } catch (e) {
      if (gen !== this.loadGen) {
        return;
      }
      this.error = String(e) || '文件夹加载异常';
      this.loading = false;
    }
  }

  private async fetchCoverBatch(
    currentPath: string,
    names: string[]
  ): Promise<FolderViewCoverItem[]> {
    const allCovers: FolderViewCoverItem[] = [];
    const client = AppSession.getClient();
    if (client === null || names.length === 0) {
      return allCovers;
    }
    let offset = 0;
    while (offset < names.length) {
      const end = Math.min(offset + FOLDER_BROWSE_COVER_BATCH, names.length);
      const batch: string[] = [];
      for (let i = offset; i < end; i++) {
        batch.push(names[i]);
      }
      const res = await client.getFolderViewCover(currentPath, batch, 20000);
      if (res.success && res.data !== undefined) {
        const coverList: FolderViewCoverItem[] = res.data.list !== undefined
          ? res.data.list
          : (res.data.items !== undefined ? res.data.items : []);
        for (let i = 0; i < coverList.length; i++) {
          allCovers.push(coverList[i]);
        }
      }
      offset = end;
    }
    return allCovers;
  }

  private async loadCovers(gen: number, currentPath: string): Promise<void> {
    if (this.folders.length === 0) {
      return;
    }
    let names: string[] = folderBrowseCoverDirNames(this.folders, currentPath);
    let allCovers: FolderViewCoverItem[] = await this.fetchCoverBatch(currentPath, names);
    if (gen !== this.loadGen) {
      return;
    }
    if (allCovers.length === 0) {
      names = folderBrowseCoverDirNamesFallback(this.folders, currentPath);
      allCovers = await this.fetchCoverBatch(currentPath, names);
      if (gen !== this.loadGen) {
        return;
      }
    }
    if (allCovers.length === 0) {
      return;
    }
    folderBrowseApplyCoverUris(this.folders, allCovers, names);
    this.publishGrid();
  }

  private async loadMoreMedia(): Promise<void> {
    const path = this.currentPath();
    if (this.loading || this.loadingMore || !this.mediaHasMore || path.length === 0) {
      return;
    }
    const client = AppSession.getClient();
    if (client === null) {
      return;
    }
    const gen = this.loadGen;
    this.loadingMore = true;
    try {
      const res = await client.getFolderViewFileList(
        path,
        FOLDER_BROWSE_PAGE_SIZE,
        this.mediaOffset,
        false,
        2,
        20000
      );
      if (gen !== this.loadGen) {
        return;
      }
      if (!res.success || res.data === undefined) {
        return;
      }
      const next = res.data;
      if (next.length === 0) {
        this.mediaHasMore = false;
        return;
      }
      const merged: GalleryListItem[] = [];
      for (let i = 0; i < this.mediaItems.length; i++) {
        merged.push(this.mediaItems[i]);
      }
      for (let i = 0; i < next.length; i++) {
        merged.push(next[i]);
      }
      this.mediaItems = merged;
      this.mediaOffset = this.mediaItems.length;
      this.mediaHasMore = next.length >= FOLDER_BROWSE_PAGE_SIZE;
      this.publishGrid();
    } finally {
      if (gen === this.loadGen) {
        this.loadingMore = false;
      }
    }
  }

  private enterFolder(path: string): void {
    const next = path.trim();
    if (next.length === 0) {
      this.toast('无法打开该文件夹');
      return;
    }
    this.pathStack.push(next);
    void this.loadCurrent(true);
  }

  private onGridItemClick(key: string): void {
    const list = this.gridItems;
    for (let i = 0; i < list.length; i++) {
      if (list[i].key === key) {
        this.onItemClick(list[i]);
        return;
      }
    }
  }

  private openMedia(index: number): void {
    if (index < 0 || index >= this.mediaItems.length) {
      this.toast('无法预览该项');
      return;
    }
    GalleryPreviewNavStore.openPreview(
      this.getUIContext(),
      this.baseUrl,
      this.mediaItems,
      index,
      GALLERY_PREVIEW_SOURCE_FOLDER_ID
    );
  }

  private onItemClick(item: FolderBrowseGridItem): void {
    if (item.kind === FOLDER_BROWSE_KIND_FOLDER) {
      if (this.selectionMode) {
        return;
      }
      this.enterFolder(item.folderPath);
      return;
    }
    if (this.selectionMode) {
      const media = item.media;
      if (media === undefined) {
        return;
      }
      this.toggleMediaSelected(folderBrowseMediaId(media));
      return;
    }
    this.openMedia(item.mediaIndex);
  }

  private setSelectedIds(ids: string[]): void {
    this.selectedIds = ids;
    this.selectedCount = ids.length;
    galleryAlbumSyncSelectionVisualState(this.selectionMode, ids, GALLERY_SELECTION_SCOPE_FOLDER);
  }

  private toggleMediaSelected(id: string): void {
    if (id.length === 0) {
      return;
    }
    const next: string[] = [];
    let found = false;
    for (let i = 0; i < this.selectedIds.length; i++) {
      if (this.selectedIds[i] === id) {
        found = true;
      } else {
        next.push(this.selectedIds[i]);
      }
    }
    if (!found) {
      next.push(id);
    }
    this.setSelectedIds(next);
  }

  private enterSelection(): void {
    if (this.selectionMode) {
      return;
    }
    this.selectionMode = true;
    this.setSelectedIds(this.selectedIds);
  }

  private exitSelection(): void {
    if (!this.selectionMode && this.selectedIds.length === 0) {
      return;
    }
    this.selectionMode = false;
    this.setSelectedIds([]);
  }

  private toggleToolbarMode(): void {
    if (this.selectionMode) {
      this.exitSelection();
      return;
    }
    this.enterSelection();
  }

  private dismissMoreMenu(): void {
    if (!this.moreMenuExpanded) {
      return;
    }
    this.moreMenuExpanded = false;
  }

  private toggleMoreMenu(): void {
    this.moreMenuExpanded = !this.moreMenuExpanded;
  }

  private enterMultiselectFromMoreMenu(): void {
    this.dismissMoreMenu();
    this.enterSelection();
  }

  private canStartSlideshow(): boolean {
    return this.mediaItems.length > 0 || this.mediaHasMore;
  }

  private openSlideshowSettings(): void {
    this.dismissMoreMenu();
    if (!this.canStartSlideshow()) {
      this.toast('暂无可播放媒体');
      return;
    }
    this.slideshowSettingsVisible = true;
  }

  private dismissSlideshowSettings(): void {
    this.slideshowSettingsVisible = false;
  }

  private slideshowScope(): GallerySlideshowScope {
    const scope: GallerySlideshowScope = {
      kind: GallerySlideshowScopeKind.FLAT_ITEMS,
      scopeLabel: this.title
    };
    return scope;
  }

  private async waitForAllMedia(isActive: () => boolean): Promise<void> {
    let guard = 0;
    while (this.mediaHasMore && isActive() && guard < 40) {
      const before = this.mediaOffset;
      await this.loadMoreMedia();
      if (this.mediaOffset <= before) {
        break;
      }
      guard++;
    }
  }

  private async startFolderSlideshow(config: GallerySlideshowConfig): Promise<void> {
    if (this.slideshowPreparing || !this.canStartSlideshow()) {
      return;
    }
    this.slideshowPreparing = true;
    const seq = ++this.slideshowRequestSeq;
    const isActive = (): boolean => seq === this.slideshowRequestSeq;
    try {
      await this.waitForAllMedia(isActive);
      if (!isActive()) {
        return;
      }
      await gallerySlideshowLaunchForItems(
        this.getUIContext(),
        this.baseUrl,
        this.mediaItems,
        config,
        (msg: string): void => {
          this.toast(msg);
        },
        isActive,
        this.title
      );
      if (isActive()) {
        this.slideshowSettingsVisible = false;
      }
    } finally {
      if (isActive()) {
        this.slideshowPreparing = false;
      }
    }
  }

  private removeMediaByIds(ids: string[]): void {
    const next: GalleryListItem[] = [];
    for (let i = 0; i < this.mediaItems.length; i++) {
      const id: string = folderBrowseMediaId(this.mediaItems[i]);
      let drop = false;
      for (let j = 0; j < ids.length; j++) {
        if (ids[j] === id) {
          drop = true;
          break;
        }
      }
      if (drop) {
        continue;
      }
      next.push(this.mediaItems[i]);
    }
    this.mediaItems = next;
    this.mediaOffset = this.mediaItems.length;
    this.publishGrid();
  }

  private asBatchActionsHost(): FolderBrowseBatchActionsHost {
    const self = this;
    class FolderBrowseBatchActionsHostBridge implements FolderBrowseBatchActionsHost {
      getUIContext(): UIContext { return self.getUIContext(); }

      get baseUrl(): string { return self.baseUrl; }
      set baseUrl(v: string) { self.baseUrl = v; }

      get mediaItems(): GalleryListItem[] { return self.mediaItems; }
      set mediaItems(v: GalleryListItem[]) { self.mediaItems = v; }

      get selectedIds(): string[] { return self.selectedIds; }
      set selectedIds(v: string[]) { self.setSelectedIds(v); }

      get batchDeleting(): boolean { return self.batchDeleting; }
      set batchDeleting(v: boolean) { self.batchDeleting = v; }

      get batchDownloading(): boolean { return self.batchDownloading; }
      set batchDownloading(v: boolean) { self.batchDownloading = v; }

      toast(msg: string): void { self.toast(msg); }
      exitSelection(): void { self.exitSelection(); }
      removeMediaByIds(ids: string[]): void { self.removeMediaByIds(ids); }
      askLivePhotoSave(): Promise<LivePhotoSaveChoice> { return self.askLivePhotoSave(); }
      askChoice(title: string, buttons: string[]): Promise<number> { return self.askChoice(title, buttons); }
    }
    return new FolderBrowseBatchActionsHostBridge();
  }

  private askLivePhotoSave(): Promise<LivePhotoSaveChoice> {
    return askLivePhotoSaveChoice(
      (title: string, buttons: string[]): Promise<number> => this.askChoice(title, buttons),
      (): Promise<boolean> => this.askLivePhotoPrivilege()
    );
  }

  private askLivePhotoPrivilege(): Promise<boolean> {
    if (this.liveSaveSheetVisible) {
      return Promise.resolve(false);
    }
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      this.liveSaveResolver = (choice: LivePhotoSaveChoice): void => {
        resolve(choice === 'privilege');
      };
      this.liveSaveSheetVisible = true;
    });
  }

  private completeLivePhotoSave(choice: LivePhotoSaveChoice): void {
    const resolver = this.liveSaveResolver;
    this.liveSaveResolver = undefined;
    this.liveSaveSheetVisible = false;
    if (resolver !== undefined) {
      resolver(choice);
    }
  }

  private askChoice(title: string, buttons: string[]): Promise<number> {
    if (this.choiceSheetVisible) {
      return Promise.resolve(-1);
    }
    return new Promise<number>((resolve: (index: number) => void) => {
      this.choiceSheetTitle = title;
      this.choiceSheetButtons = buttons;
      this.choiceSheetResolver = resolve;
      this.choiceSheetVisible = true;
    });
  }

  private completeChoice(index: number): void {
    const resolver = this.choiceSheetResolver;
    this.choiceSheetResolver = undefined;
    this.choiceSheetVisible = false;
    if (resolver !== undefined) {
      resolver(index);
    }
  }

  private liveFolderCoverUri(key: string): string {
    const list = this.gridItems;
    for (let i = 0; i < list.length; i++) {
      if (list[i].key === key) {
        return list[i].coverUri;
      }
    }
    return '';
  }

  private gridVisualKey(item: FolderBrowseGridItem): string {
    if (item.kind === FOLDER_BROWSE_KIND_FOLDER) {
      return `${item.key}|${item.coverUri}`;
    }
    return item.key;
  }

  private itemIsVideo(item: FolderBrowseGridItem): boolean {
    return item.media !== undefined && isVideoItem(item.media);
  }

  private itemIsGif(item: FolderBrowseGridItem): boolean {
    return item.media !== undefined && isGifItem(item.media);
  }

  private itemIsLive(item: FolderBrowseGridItem): boolean {
    return item.media !== undefined && isLivePhotoItem(item.media);
  }

  private mediaThumbUri(item: FolderBrowseGridItem): string {
    const media = item.media;
    if (media === undefined) {
      return '';
    }
    return nasUrl(this.baseUrl, pickThumb(media));
  }

  private mediaSharedId(item: FolderBrowseGridItem): string {
    const media = item.media;
    if (media === undefined) {
      return '';
    }
    const id = media.id;
    if (id === undefined || String(id).trim().length === 0) {
      return '';
    }
    return gallerySharedSourceDomId(String(id).trim());
  }

  private mediaSelectionId(item: FolderBrowseGridItem): string {
    if (item.media === undefined) {
      return '';
    }
    return folderBrowseMediaId(item.media);
  }

  @Builder
  private liveSaveSheetBuilder() {
    LivePhotoSaveActionSheet({
      onSelect: (choice: LivePhotoSaveChoice): void => {
        this.completeLivePhotoSave(choice);
      }
    })
  }

  @Builder
  private choiceSheetBuilder() {
    FnHdsChoiceSheet({
      buttons: this.choiceSheetButtons,
      onSelect: (index: number): void => {
        this.completeChoice(index);
      }
    })
  }

  @Builder
  private slideshowSettingsBuilder() {
    GallerySlideshowSettingsSheet({
      preparing: this.slideshowPreparing,
      onStart: (config: GallerySlideshowConfig): void => {
        void this.startFolderSlideshow(config);
      }
    })
  }

  @Builder
  private folderTile(item: FolderBrowseGridItem) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (this.liveFolderCoverUri(item.key).length > 0) {
          GalleryNetworkThumb({
            uri: nasUrl(this.baseUrl, this.liveFolderCoverUri(item.key)),
            isVideo: false,
            isGif: false,
            paused: this.thumbLoadingPaused,
            fadeInEnabled: false,
            cacheIdentity: item.key,
            cacheRank: 2
          })
            .width('100%')
            .aspectRatio(1)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.folder_fill'))
              .fontSize(36)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width('100%')
          .aspectRatio(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor($r('app.color.gallery_material_surface_bg'))
        }
      }
      .width('100%')
      .aspectRatio(1)
      .borderRadius(12)
      .clip(true)

      Text(item.title)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .padding({ left: 2, right: 2, bottom: 8 })
  }

  @Builder
  private mediaTile(item: FolderBrowseGridItem) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        GalleryNetworkThumb({
          uri: this.mediaThumbUri(item),
          isVideo: this.itemIsVideo(item),
          isGif: this.itemIsGif(item),
          isLive: this.itemIsLive(item),
          paused: this.thumbLoadingPaused,
          fadeInEnabled: false,
          cacheIdentity: item.key,
          cacheRank: 1
        })
          .width('100%')
          .aspectRatio(1)
        GalleryAlbumSelectionOverlay({
          itemId: this.mediaSelectionId(item),
          visualScope: GALLERY_SELECTION_SCOPE_FOLDER,
          selectionMode: this.selectionMode
        })
      }
      .width('100%')
      .aspectRatio(1)
      .borderRadius(12)
      .clip(true)
      .id(this.mediaSharedId(item))

      Text(item.title)
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .padding({ left: 2, right: 2, bottom: 8 })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        FolderBrowseChrome({
          selectionMode: this.selectionMode,
          selectedCount: this.selectedCount,
          title: this.title,
          totalCount: this.totalCount(),
          topSafeInsetVp: this.systemTopInsetVp,
          moreMenuExpanded: this.moreMenuExpanded,
          scrollerList: [this.gridScroller],
          onCancelSelection: (): void => {
            this.exitSelection();
          },
          onBack: (): void => {
            this.handleBack();
          },
          onToggleMode: (): void => {
            this.toggleToolbarMode();
          },
          onShowMoreMenu: (): void => {
            this.toggleMoreMenu();
          },
          onDismissMoreMenu: (): void => {
            this.dismissMoreMenu();
          },
          onEnterMultiselectFromMore: (): void => {
            this.enterMultiselectFromMoreMenu();
          },
          onOpenSlideshowFromMore: (): void => {
            this.openSlideshowSettings();
          }
        })
          .width('100%')

        if (this.loading) {
          FnInlineLoading({ text: '加载中…' })
            .layoutWeight(1)
        } else if (this.error.length > 0 && this.gridItems.length === 0) {
          FnStateText({ text: this.error })
            .layoutWeight(1)
        } else {
          Stack({ alignContent: Alignment.Bottom }) {
            Grid(this.gridScroller) {
              LazyForEach(this.gridSource, (item: FolderBrowseGridItem) => {
                GridItem() {
                  Column() {
                    if (item.kind === FOLDER_BROWSE_KIND_MEDIA) {
                      this.mediaTile(item)
                    } else {
                      this.folderTile(item)
                    }
                  }
                  .width('100%')
                  .onClick((): void => {
                    this.onGridItemClick(item.key);
                  })
                }
              }, (item: FolderBrowseGridItem) => this.gridVisualKey(item))
            }
            .columnsTemplate(fnRepeatFrTemplate(fnAdaptiveGridColumns(FOLDER_BROWSE_BASE_COLUMNS, this.windowWidthBp)))
            .columnsGap(8)
            .rowsGap(8)
            .cachedCount(8)
            .width('100%')
            .height('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: this.selectionMode && this.selectedCount > 0 ? 88 : 10 })
            .onReachEnd((): void => {
              void this.loadMoreMedia();
            })
            .onScrollIndex((_first: number, last: number): void => {
              if (last >= this.gridItems.length - 6) {
                void this.loadMoreMedia();
              }
            })
            .onDidScroll((_offset: number, scrollState: ScrollState): void => {
              this.onGridScrollStateChange(scrollState);
            })

            if (this.selectionMode && this.selectedCount > 0) {
              GalleryAlbumBatchActionBar({
                downloading: this.batchDownloading,
                deleting: this.batchDeleting,
                onDownload: (): void => {
                  void folderBrowseConfirmBatchDownload(this.asBatchActionsHost());
                },
                onDelete: (): void => {
                  void folderBrowseConfirmBatchDelete(this.asBatchActionsHost());
                }
              })
                .width('100%')
                .height(GALLERY_BATCH_BAR_TOTAL_HEIGHT_VP)
            }

            if (this.batchDeleting || this.batchDownloading) {
              FnFullLoadingMask({
                text: this.batchDeleting ? '移入回收站中…' : '下载中…',
                topOffsetVp: 0
              })
            }

            if (this.previewOpening) {
              GalleryPreviewOpeningMask({ topOffsetVp: 0 })
            }
          }
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')

      if (this.slideshowPreparing) {
        FnFullLoadingMask({
          text: '正在准备幻灯片...',
          topOffsetVp: 0
        })
          .width('100%')
          .height('100%')
          .zIndex(30)
      }

      Column()
        .width(1)
        .height(1)
        .bindSheet(this.liveSaveSheetVisible, this.liveSaveSheetBuilder, fnHdsSaveButtonSheetOptions(
          LIVE_PHOTO_PRIVILEGE_SHEET_TITLE,
          (): void => {
            this.completeLivePhotoSave('cancel');
          }
        ))
      Column()
        .width(1)
        .height(1)
        .bindSheet(this.slideshowSettingsVisible, this.slideshowSettingsBuilder, fnHdsFitContentSheetOptions(
          gallerySlideshowScopeLabel(this.slideshowScope()),
          (): void => {
            this.dismissSlideshowSettings();
          }
        ))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .id(GALLERY_PREVIEW_SOURCE_FOLDER_ID)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.choiceSheetVisible, this.choiceSheetBuilder, fnHdsFitContentSheetOptions(
      this.choiceSheetTitle,
      (): void => {
        this.completeChoice(-1);
      }
    ))
  }

  pageTransition(): void {
    if (this.previewHeroActive) {
      PageTransitionEnter({ type: RouteType.None, duration: 0 })
      PageTransitionExit({ type: RouteType.None, duration: 0 })
    } else {
      PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
        .opacity(0)
        .translate({ x: 12, y: 0 });
      PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
        .opacity(0)
        .translate({ x: -8, y: 0 });
    }
  }
}

@Builder
export function FolderBrowsePageNavigationContent() {
  FolderBrowsePage()
}
