import { AppSession } from '../auth/AppSession';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import { GalleryListItem, MagicSearchItem, SmartCategoryItem } from '../model/FnApiTypes';
import { GalleryNetworkThumb, nasUrl, trimThumbPixCacheForList } from '../album/GalleryAlbumCommon';
import { smartCategoryCover } from '../album/galleryAlbumTab/GalleryAlbumModeData';
import { FnFullLoadingMask, FnInlineLoading, FnStateText, FnTopBar } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';

@Entry
@Component
struct SmartCategoryPage {
  @State private baseUrl: string = '';
  @State private loading: boolean = false;
  @State private opening: boolean = false;
  @State private error: string = '';
  @State private sceneItems: SmartCategoryItem[] = [];
  @State private infoItems: SmartCategoryItem[] = [];
  @State private thumbLoadingPaused: boolean = false;
  private thumbResumeTimer: number = -1;

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  aboutToAppear(): void {
    this.thumbLoadingPaused = false;
    const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
    if (rp !== undefined && rp['baseUrl'] !== undefined) {
      this.baseUrl = String(rp['baseUrl']);
    }
    void this.loadData();
  }

  aboutToDisappear(): void {
    this.clearThumbResumeTimer();
    this.recycleThumbCache(true);
    const client = AppSession.getClient();
    if (client !== null) {
      client.cancelPendingRequests();
    }
  }

  private totalSmartItemCount(): number {
    return this.sceneItems.length + this.infoItems.length;
  }

  private combinedItems(): SmartCategoryItem[] {
    return this.sceneItems.concat(this.infoItems);
  }

  private recycleThumbCache(aggressive: boolean = false): void {
    trimThumbPixCacheForList(this.totalSmartItemCount(), aggressive);
  }

  private clearThumbResumeTimer(): void {
    if (this.thumbResumeTimer >= 0) {
      clearTimeout(this.thumbResumeTimer);
      this.thumbResumeTimer = -1;
    }
  }

  private onContentScrolling(): void {
    this.clearThumbResumeTimer();
    if (!this.thumbLoadingPaused) {
      this.thumbLoadingPaused = true;
    }
    this.recycleThumbCache(false);
  }

  private onContentScrollStop(): void {
    this.clearThumbResumeTimer();
    this.thumbResumeTimer = setTimeout((): void => {
      this.thumbResumeTimer = -1;
      this.thumbLoadingPaused = false;
    }, 96);
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {}
  }

  private nameOf(item: SmartCategoryItem): string {
    const n = item.name;
    return n !== undefined && n.length > 0 ? n : '未命名分类';
  }

  private coverOf(item: SmartCategoryItem): string {
    return smartCategoryCover(item);
  }

  private async loadData(): Promise<void> {
    this.loading = true;
    this.error = '';
    this.sceneItems = [];
    this.infoItems = [];
    const client = AppSession.getClient();
    if (client === null) {
      this.loading = false;
      this.error = '未登录';
      return;
    }
    try {
      const pair = await Promise.all([
        client.getSmartRecCategories('scene', -1),
        client.getSmartRecCategories('information', -1)
      ]);
      const sceneRes = pair[0];
      const infoRes = pair[1];
      const sceneRaw = sceneRes.success && sceneRes.data !== undefined ? (sceneRes.data.list ?? sceneRes.data.items ?? []) : [];
      const infoRaw = infoRes.success && infoRes.data !== undefined ? (infoRes.data.list ?? infoRes.data.items ?? []) : [];
      const sceneOut: SmartCategoryItem[] = [];
      const infoOut: SmartCategoryItem[] = [];
      for (let i = 0; i < sceneRaw.length; i++) {
        const el = sceneRaw[i];
        if (typeof el === 'object' && el !== null) {
          sceneOut.push(el as SmartCategoryItem);
        }
      }
      for (let i = 0; i < infoRaw.length; i++) {
        const el = infoRaw[i];
        if (typeof el === 'object' && el !== null) {
          infoOut.push(el as SmartCategoryItem);
        }
      }
      this.sceneItems = sceneOut;
      this.infoItems = infoOut;
      if (sceneOut.length === 0 && infoOut.length === 0) {
        this.error = '暂无智能分类';
      }
    } catch (e) {
      this.error = String(e) || '智能分类加载异常';
    }
    this.loading = false;
  }

  private async openSmartCategory(item: SmartCategoryItem): Promise<void> {
    if (this.opening) {
      return;
    }
    this.opening = true;
    const keyword = this.nameOf(item);
    try {
      const client = AppSession.getClient();
      if (client === null) {
        this.toast('未登录');
        return;
      }
      const res = await client.doMagicSearch(keyword);
      if (!res.success || res.data === undefined) {
        this.toast(res.message ?? '加载失败');
        return;
      }
      const rawList = res.data.list ?? [];
      const mapped: GalleryListItem[] = rawList.map((x: MagicSearchItem): GalleryListItem => {
        const rich = x.additional !== undefined || x.thumbnail !== undefined || x.category !== undefined || x.fileType !== undefined;
        if (rich) {
          return x as GalleryListItem;
        }
        const id = x.id !== undefined ? String(x.id) : '';
        const session = x.session !== undefined ? x.session : '';
        if (id.length > 0 && session.length > 0) {
          return { id: id, thumb: `/p/api/v1/stream/p/t/${id}/s/${session}` };
        }
        return x as GalleryListItem;
      });
      if (mapped.length === 0) {
        this.toast('该分类暂无可预览媒体');
        return;
      }
      const ok = await CategoryGalleryNavStore.open(this.baseUrl, keyword, mapped, this.getUIContext());
      if (!ok) {
        this.toast('打开分类失败');
      }
    } finally {
      this.opening = false;
    }
  }

  @Builder
  private categoryGrid(list: SmartCategoryItem[]) {
    Grid() {
      ForEach(list, (item: SmartCategoryItem, idx: number) => {
        GridItem() {
          Column({ space: 8 }) {
            GalleryNetworkThumb({
              uri: nasUrl(this.baseUrl, this.coverOf(item)),
              isVideo: false,
              isGif: false,
              paused: this.thumbLoadingPaused,
            })
              .width('100%')
              .aspectRatio(1)
              .borderRadius(22)
              .clip(true)

            Text(this.nameOf(item))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 2, right: 2, bottom: 10 })
          .onClick((): void => {
            void this.openSmartCategory(item);
          })
        }
      }, (_item: SmartCategoryItem, i: number) => `sc_${i}`)
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(10)
    .rowsGap(10)
    .cachedCount(6)
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }

  build() {
    Column() {
      FnTopBar({
        title: '智能分类'
      })

      if (this.loading) {
        FnInlineLoading({ text: '加载中...' }).layoutWeight(1)
      } else if (this.error.length > 0) {
        FnStateText({ text: this.error })
      } else if (this.combinedItems().length <= 0) {
        FnStateText({ text: '暂无智能分类' })
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Scroll() {
            Column() {
              this.categoryGrid(this.combinedItems())
              Blank().height(16)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .onDidScroll((_xOffset: number, _yOffset: number, _scrollState: ScrollState): void => {
            this.onContentScrolling();
          })
          .onScrollStop((): void => {
            this.onContentScrollStop();
          })

          if (this.opening) {
            FnFullLoadingMask({ text: '打开中...' })
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 12, y: 0 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: -8, y: 0 });
  }
}
