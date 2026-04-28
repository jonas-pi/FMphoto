import { AppSession } from '../auth/AppSession';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import {
  CATEGORY_GALLERY_PHOTO_INITIAL_RENDER_CAP,
  categoryLocalMediaCount,
  parseCategoryMedia
} from '../album/GalleryAlbumEntityData';
import { GalleryListItem, MediaCategoryItem } from '../model/FnApiTypes';
import { GalleryNetworkThumb, nasUrl, trimThumbPixCacheForList } from '../album/GalleryAlbumCommon';
import { FnFullLoadingMask, FnInlineLoading, FnStateText, FnTopBar } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';

@Entry
@Component
struct MediaCategoryPage {
  @State private baseUrl: string = '';
  @State private loading: boolean = false;
  @State private opening: boolean = false;
  @State private openingText: string = '打开中…';
  @State private error: string = '';
  @State private items: MediaCategoryItem[] = [];
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

  private recycleThumbCache(aggressive: boolean = false): void {
    trimThumbPixCacheForList(this.items.length, aggressive);
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
      this.recycleThumbCache(false);
      return;
    }
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

  private titleOf(item: MediaCategoryItem): string {
    const t = item.name ?? item.title ?? item.label;
    return t !== undefined && t.length > 0 ? t : '未命名分类';
  }

  private coverOf(item: MediaCategoryItem): string {
    if (item.cover !== undefined && item.cover.length > 0) {
      return item.cover;
    }
    if (item.thumb !== undefined && item.thumb.length > 0) {
      return item.thumb;
    }
    if (typeof item.thumbnail === 'string' && item.thumbnail.length > 0) {
      return item.thumbnail;
    }
    if (typeof item.thumbnail === 'object' && item.thumbnail !== null) {
      const tb = item.thumbnail;
      const u = tb.mUrl ?? tb.sUrl ?? tb.xsUrl ?? tb.xxsUrl ?? tb.originalUrl;
      return u !== undefined ? u : '';
    }
    return '';
  }

  private countOf(item: MediaCategoryItem): number {
    const c = item.count ?? item.total;
    return c !== undefined && Number.isFinite(Number(c)) ? Math.max(0, Math.floor(Number(c))) : 0;
  }

  private async loadData(): Promise<void> {
    this.loading = true;
    this.error = '';
    this.items = [];
    const client = AppSession.getClient();
    if (client === null) {
      this.loading = false;
      this.error = '未登录';
      return;
    }
    try {
      const res = await client.getMediaCategoryList();
      if (!res.success || res.data === undefined) {
        this.error = res.message ?? '媒体分类加载失败';
        this.loading = false;
        return;
      }
      const raw = res.data.list ?? res.data.items ?? [];
      const out: MediaCategoryItem[] = [];
      for (let i = 0; i < raw.length; i++) {
        const el = raw[i];
        if (typeof el === 'object' && el !== null) {
          out.push(el as MediaCategoryItem);
        }
      }
      this.items = out;
      if (out.length === 0) {
        this.error = '暂无媒体分类';
      }
    } catch (e) {
      this.error = String(e) || '媒体分类加载异常';
    }
    this.loading = false;
  }

  private async openCategory(item: MediaCategoryItem): Promise<void> {
    if (this.opening) {
      return;
    }
    this.opening = true;
    const title = this.titleOf(item);
    try {
      const categoryKey = item.key !== undefined ? item.key : '';
      this.openingText = categoryKey === 'photo' ? '加载照片中…' : `打开${title}中…`;
      const initialRenderCap = categoryKey === 'photo'
        ? CATEGORY_GALLERY_PHOTO_INITIAL_RENDER_CAP
        : -1;
      const localMediaCount = categoryLocalMediaCount(item);
      const local = parseCategoryMedia(item, initialRenderCap);
      const heroImageUri = nasUrl(this.baseUrl, this.coverOf(item));
      const expectedTotalCount = Math.max(this.countOf(item), localMediaCount, local.length);
      if (local.length > 0) {
        const ok = await CategoryGalleryNavStore.open(
          this.baseUrl,
          title,
          local,
          this.getUIContext(),
          false,
          { expectedTotalCount, categoryKey, heroImageUri }
        );
        if (!ok) { this.toast('打开分类失败'); }
        return;
      }
      const client = AppSession.getClient();
      if (client === null) {
        this.toast('未登录');
        return;
      }
      const fetched = await client.searchResultsByCategory(item);
      if (!fetched.success || fetched.data === undefined || fetched.data.length === 0) {
        this.toast(fetched.message ?? '该分类暂无可预览媒体');
        return;
      }
      const ok = await CategoryGalleryNavStore.open(
        this.baseUrl,
        title,
        fetched.data,
        this.getUIContext(),
        false,
        { expectedTotalCount, categoryKey, heroImageUri }
      );
      if (!ok) { this.toast('打开分类失败'); }
    } finally {
      this.opening = false;
    }
  }

  build() {
    Column() {
      FnTopBar({
        title: '媒体分类'
      })

      if (this.loading) {
        FnInlineLoading({ text: '加载中…' })
          .layoutWeight(1)
      } else if (this.error.length > 0) {
        FnStateText({ text: this.error })
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Grid() {
            ForEach(this.items, (cat: MediaCategoryItem, idx: number) => {
              GridItem() {
                Column({ space: 6 }) {
                  Stack({ alignContent: Alignment.Center }) {
                    GalleryNetworkThumb({
                      uri: nasUrl(this.baseUrl, this.coverOf(cat)),
                      isVideo: false,
                      isGif: false,
                      paused: this.thumbLoadingPaused,
                    })
                      .width('100%')
                      .aspectRatio(1)
                    // 全图遮罩 + 居中文字：突出“分类入口”语义
                    Column() {
                      Text(this.titleOf(cat))
                        .fontSize(50)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Color.White)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .textAlign(TextAlign.Center)
                        .width('100%')
                    }
                    .width('100%')
                    .height('100%')
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                    .padding({ left: 12, right: 12 })
                    .backgroundColor($r('app.color.overlay_mask'))
                  }
                  .width('100%')
                  .aspectRatio(1)
                  Text(`${this.countOf(cat)} 项`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }
                .width('100%')
                .padding({ left: 2, right: 2, bottom: 8 })
                .onClick((): void => { void this.openCategory(cat); })
              }
            }, (_cat: MediaCategoryItem, i: number) => `mc_${i}`)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .layoutWeight(1)
          .width('100%')
          .cachedCount(4)
          .onDidScroll((_offset: number, scrollState: ScrollState): void => {
            this.onGridScrollStateChange(scrollState);
          })
          .padding({ left: 12, right: 12, top: 8, bottom: 10 })

          if (this.opening) {
            FnFullLoadingMask({ text: this.openingText })
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
