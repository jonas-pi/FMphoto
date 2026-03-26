import { router } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import { GalleryListItem, MediaCategoryItem } from '../model/FnApiTypes';
import { GalleryNetworkThumb, nasUrl } from '../album/GalleryAlbumCommon';

@Entry
@Component
struct MediaCategoryPage {
  @State private baseUrl: string = '';
  @State private loading: boolean = false;
  @State private opening: boolean = false;
  @State private error: string = '';
  @State private items: MediaCategoryItem[] = [];

  onBackPress(): boolean {
    router.back();
    return true;
  }

  aboutToAppear(): void {
    const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
    if (rp !== undefined && rp['baseUrl'] !== undefined) {
      this.baseUrl = String(rp['baseUrl']);
    }
    void this.loadData();
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

  private parseMedia(item: MediaCategoryItem): GalleryListItem[] {
    const raw = item.list ?? item.items;
    if (!Array.isArray(raw)) {
      return [];
    }
    const out: GalleryListItem[] = [];
    for (let i = 0; i < raw.length; i++) {
      const it = raw[i];
      if (typeof it === 'object' && it !== null) {
        out.push(it as GalleryListItem);
      }
    }
    return out;
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
      const local = this.parseMedia(item);
      if (local.length > 0) {
        const ok = await CategoryGalleryNavStore.open(this.baseUrl, title, local, this.getUIContext());
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
      const ok = await CategoryGalleryNavStore.open(this.baseUrl, title, fetched.data, this.getUIContext());
      if (!ok) { this.toast('打开分类失败'); }
    } finally {
      this.opening = false;
    }
  }

  build() {
    Column() {
      Row() {
        Button('返回')
          .height(34)
          .onClick((): void => { router.back(); })
        Text('媒体分类')
          .layoutWeight(1)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
        Blank().width(56)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 8 })

      if (this.loading) {
        Row({ space: 10 }) {
          LoadingProgress().width(28).height(28)
          Text('加载中…').fontSize(14).fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.error.length > 0) {
        Text(this.error)
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 24, right: 24, top: 40 })
          .textAlign(TextAlign.Center)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
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
                    .backgroundColor('#90000000')
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
          .padding({ left: 12, right: 12, top: 8, bottom: 10 })

          if (this.opening) {
            Column({ space: 10 }) {
              LoadingProgress().width(48).height(48).color(Color.White)
              Text('打开中…').fontSize(14).fontColor(Color.White)
            }
            .width('100%').height('100%')
            .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
            .backgroundColor('#80000000')
            .hitTestBehavior(HitTestMode.Block)
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
}
