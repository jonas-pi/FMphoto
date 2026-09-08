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
import { GalleryAlbumNavigation } from '../album/GalleryAlbumNavigation';
import { GalleryPreviewNavStore } from '../album/GalleryPreviewNavStore';
import { GALLERY_PREVIEW_OPENING_KEY } from '../album/GalleryPreviewEntryGate';
import {
  GALLERY_PREVIEW_HERO_ACTIVE_KEY,
  GALLERY_PREVIEW_SOURCE_FOLDER_ID,
  gallerySharedSourceDomId
} from '../album/GallerySharedTransition';
import { GalleryPreviewOpeningMask } from '../album/GalleryPreviewOpeningMask';
import { FnListDataSource } from '../common/FnListDataSource';
import { FN_WINDOW_WIDTH_BP_KEY, fnAdaptiveGridColumns, fnRepeatFrTemplate } from '../common/FnWindowBreakpoint';
import { FnInlineLoading, FnStateText, FnTopBar } from '../common/FnUiCommon';
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
  folderBrowseFoldersFromList,
  folderBrowseLabelOf,
  folderBrowsePermissionMessage
} from './folderBrowsePage/FolderBrowseLogic';

@Entry
@Component
struct FolderBrowsePage {
  private albumNavigationMode: boolean = false;
  @StorageProp(FN_MEDIA_BASE_URL) private baseUrl: string = '';
  @StorageProp(FN_WINDOW_WIDTH_BP_KEY) private windowWidthBp: number = WidthBreakpoint.WIDTH_SM;
  @StorageProp(GALLERY_PREVIEW_OPENING_KEY) private previewOpening: boolean = false;
  @StorageProp(GALLERY_PREVIEW_HERO_ACTIVE_KEY) private previewHeroActive: boolean = false;
  @State private loading: boolean = false;
  @State private loadingMore: boolean = false;
  @State private error: string = '';
  @State private title: string = '文件夹';
  @State private thumbLoadingPaused: boolean = false;
  @State private gridItems: FolderBrowseGridItem[] = [];
  private readonly gridSource: FnListDataSource<FolderBrowseGridItem> = new FnListDataSource<FolderBrowseGridItem>();
  private pathStack: string[] = [];
  private folders: FolderBrowseFolderItem[] = [];
  private mediaItems: GalleryListItem[] = [];
  private mediaOffset: number = 0;
  private mediaHasMore: boolean = false;
  private loadGen: number = 0;
  private albumBackHandlerToken: number = 0;
  private thumbResumeTimer: number = -1;

  onBackPress(): boolean {
    this.handleBack();
    return true;
  }

  private handleBack(): void {
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

  private async loadCovers(gen: number, currentPath: string): Promise<void> {
    if (this.folders.length === 0) {
      return;
    }
    const client = AppSession.getClient();
    if (client === null) {
      return;
    }
    const names: string[] = [];
    for (let i = 0; i < this.folders.length; i++) {
      names.push(this.folders[i].name);
    }
    const allCovers: FolderViewCoverItem[] = [];
    let offset = 0;
    while (offset < names.length) {
      const end = Math.min(offset + FOLDER_BROWSE_COVER_BATCH, names.length);
      const batch: string[] = [];
      for (let i = offset; i < end; i++) {
        batch.push(names[i]);
      }
      const res = await client.getFolderViewCover(currentPath, batch, 20000);
      if (gen !== this.loadGen) {
        return;
      }
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
    if (gen !== this.loadGen || allCovers.length === 0) {
      return;
    }
    folderBrowseApplyCoverUris(this.folders, allCovers);
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
      this.enterFolder(item.folderPath);
      return;
    }
    this.openMedia(item.mediaIndex);
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

  @Builder
  private folderTile(item: FolderBrowseGridItem) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        if (item.coverUri.length > 0) {
          GalleryNetworkThumb({
            uri: nasUrl(this.baseUrl, item.coverUri),
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
    Column() {
      FnTopBar({
        title: this.title,
        onBack: (): void => {
          this.handleBack();
        }
      })

      if (this.loading) {
        FnInlineLoading({ text: '加载中…' })
          .layoutWeight(1)
      } else if (this.error.length > 0 && this.gridItems.length === 0) {
        FnStateText({ text: this.error })
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Grid() {
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
            }, (item: FolderBrowseGridItem) => item.key)
          }
          .columnsTemplate(fnRepeatFrTemplate(fnAdaptiveGridColumns(FOLDER_BROWSE_BASE_COLUMNS, this.windowWidthBp)))
          .columnsGap(8)
          .rowsGap(8)
          .cachedCount(8)
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 10 })
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
    .backgroundColor($r('app.color.page_background'))
    .id(GALLERY_PREVIEW_SOURCE_FOLDER_ID)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
