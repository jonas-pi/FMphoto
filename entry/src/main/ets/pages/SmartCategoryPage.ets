import { AppSession } from '../auth/AppSession';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import { GalleryListItem, MagicSearchItem, SmartCategoryItem } from '../model/FnApiTypes';
import { GalleryNetworkThumb, nasUrl } from '../album/GalleryAlbumCommon';
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

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
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

  private nameOf(item: SmartCategoryItem): string {
    const n = item.name;
    return n !== undefined && n.length > 0 ? n : '未命名分类';
  }

  private coverOf(item: SmartCategoryItem): string {
    const p = item.poster;
    if (p === undefined || p === null) {
      return '';
    }
    const id = p.photoId !== undefined ? String(p.photoId) : '';
    const uuid = p.uuid !== undefined ? p.uuid : '';
    if (id.length === 0 || uuid.length === 0) {
      return '';
    }
    return `/p/api/v1/stream/p/t/${id}/s/${uuid}`;
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
      // 并发拉取两组分类，减少总等待时长
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
        if (rich) { return x as GalleryListItem; }
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
      if (!ok) { this.toast('打开分类失败'); }
    } finally {
      this.opening = false;
    }
  }

  @Builder
  private section(title: string, list: SmartCategoryItem[]) {
    if (list.length > 0) {
      Text(title).fontSize(14).fontWeight(FontWeight.Medium).width('100%').padding({ left: 14, top: 10, bottom: 8 })
      Grid() {
        ForEach(list, (item: SmartCategoryItem, idx: number) => {
          GridItem() {
            Column({ space: 6 }) {
              Stack({ alignContent: Alignment.Center }) {
                GalleryNetworkThumb({
                  uri: nasUrl(this.baseUrl, this.coverOf(item)),
                  isVideo: false,
                  isGif: false,
                }).width('100%').aspectRatio(1)
                // 全图遮罩 + 居中文字：突出“分类入口”语义
                Column() {
                  Text(this.nameOf(item))
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
              Text('点击打开')
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .padding({ left: 2, right: 2, bottom: 8 })
            .onClick((): void => { void this.openSmartCategory(item); })
          }
        }, (_item: SmartCategoryItem, i: number) => `sc_${title}_${i}`)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .cachedCount(4)
      .width('100%')
      .padding({ left: 12, right: 12 })
    }
  }

  build() {
    Column() {
      FnTopBar({
        title: '智能分类'
      })

      if (this.loading) {
        FnInlineLoading({ text: '加载中…' }).layoutWeight(1)
      } else if (this.error.length > 0) {
        FnStateText({ text: this.error })
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Scroll() {
            Column() {
              this.section('场景事物', this.sceneItems)
              this.section('资料记录', this.infoItems)
              Blank().height(10)
            }.width('100%')
          }.layoutWeight(1).width('100%')

          if (this.opening) {
            FnFullLoadingMask({ text: '打开中…' })
          }
        }.layoutWeight(1).width('100%')
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
