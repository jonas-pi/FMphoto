import { AppSession, FN_MEDIA_BASE_URL } from '../auth/AppSession';
import { AiPersonItem } from '../model/FnApiTypes';
import { openPersonAlbumById } from '../album/PersonAlbumOpenHelper';
import { GalleryNetworkThumb, nasUrl, trimThumbPixCacheForList } from '../album/GalleryAlbumCommon';
import { FN_WINDOW_WIDTH_BP_KEY, fnAdaptiveGridColumns, fnRepeatFrTemplate } from '../common/FnWindowBreakpoint';
import { FnListDataSource } from '../common/FnListDataSource';
import { personCacheIdentity, personFace as resolvePersonFace } from '../album/GalleryAlbumEntityData';
import { FnFullLoadingMask, FnInlineLoading, FnStateText, FnTopBar } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';

@Entry
@Component
struct PersonPage {
  @StorageProp(FN_MEDIA_BASE_URL) private baseUrl: string = '';
  @StorageProp(FN_WINDOW_WIDTH_BP_KEY) private windowWidthBp: number = WidthBreakpoint.WIDTH_SM;
  @State private loading: boolean = false;
  @State private opening: boolean = false;
  @State private error: string = '';
  @State private items: AiPersonItem[] = [];
  private readonly personSource: FnListDataSource<AiPersonItem> = new FnListDataSource<AiPersonItem>();

  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  aboutToAppear(): void {
    // 返回到该页时确保遮罩状态被清理
    this.opening = false;
    const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
    if (rp !== undefined && rp['baseUrl'] !== undefined) {
      this.baseUrl = String(rp['baseUrl']);
    }
    void this.loadData();
  }

  aboutToDisappear(): void {
    trimThumbPixCacheForList(this.items.length, false);
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {}
  }

  private personName(item: AiPersonItem): string {
    const n = item.name ?? item.nickName;
    return n !== undefined && n.length > 0 ? n : '未命名人物';
  }

  private personFace(item: AiPersonItem): string {
    return resolvePersonFace(item);
  }

  private personId(item: AiPersonItem): string {
    if (item.id === undefined || item.id === null) {
      return '';
    }
    return String(item.id);
  }

  private personStatText(item: AiPersonItem): string {
    const p = Number(item.photoCount);
    const v = Number(item.videoCount);
    if (Number.isFinite(p) || Number.isFinite(v)) {
      return `${Number.isFinite(p) ? Math.max(0, Math.floor(p)) : 0} 张照片 · ${Number.isFinite(v) ? Math.max(0, Math.floor(v)) : 0} 个视频`;
    }
    const total = Number(item.itemCount ?? item.count ?? item.total);
    return Number.isFinite(total) ? `共 ${Math.max(0, Math.floor(total))} 项` : '点击查看';
  }

  private async loadData(): Promise<void> {
    const firstOpen = this.items.length <= 0;
    this.loading = firstOpen;
    this.error = '';
    const client = AppSession.getClient();
    if (client === null) {
      this.loading = false;
      this.error = '未登录';
      return;
    }
    try {
      const res = await client.getAiPersonList(true, -1, 0);
      if (!res.success || res.data === undefined) {
        this.error = res.message ?? '人物列表加载失败';
        this.loading = false;
        return;
      }
      const raw = res.data.list ?? res.data.items ?? res.data.records ?? [];
      const out: AiPersonItem[] = [];
      for (let i = 0; i < raw.length; i++) {
        const el = raw[i];
        if (typeof el === 'object' && el !== null) {
          out.push(el as AiPersonItem);
        }
      }
      this.items = out;
      this.personSource.reloadAll(out);
      if (out.length === 0) {
        this.error = '暂无人物';
      }
    } catch (e) {
      this.error = String(e) || '人物列表加载异常';
    }
    this.loading = false;
  }

  /** 打开人物图库：逻辑见 PersonAlbumOpenHelper */
  private async openPerson(item: AiPersonItem): Promise<void> {
    if (this.opening) {
      return;
    }
    const pid = this.personId(item);
    if (pid.length === 0) {
      this.toast('人物 ID 无效');
      return;
    }
    this.opening = true;
    let keepOpening = false;
    try {
      const r = await openPersonAlbumById(
        this.baseUrl,
        pid,
        this.personName(item),
        this.getUIContext()
      );
      if (!r.ok) {
        if (r.errorMessage.length > 0) {
          this.toast(r.errorMessage);
        }
        return;
      }
      keepOpening = true;
      setTimeout((): void => {
        this.opening = false;
      }, 280);
    } finally {
      if (!keepOpening) {
        this.opening = false;
      }
    }
  }

  build() {
    Column() {
      FnTopBar({
        title: '人物'
      })

      if (this.loading) {
        FnInlineLoading({ text: '人物加载中…' }).layoutWeight(1)
      } else if (this.error.length > 0) {
        FnStateText({ text: this.error })
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Grid() {
            LazyForEach(this.personSource, (item: AiPersonItem) => {
              GridItem() {
                Column({ space: 8 }) {
                GalleryNetworkThumb({
                  uri: nasUrl(this.baseUrl, this.personFace(item)),
                  paused: false,
                  fadeInEnabled: false,
                  cacheIdentity: personCacheIdentity(item),
                  cacheRank: 3
                })
                    .width('100%')
                    .aspectRatio(1)
                    .borderRadius(999)
                    .clip(true)
                  Text(this.personName(item))
                    .fontSize(13)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(this.personStatText(item))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .width('100%')
                }
                .width('100%')
                .padding({ left: 2, right: 2, bottom: 8 })
                .onClick((): void => { void this.openPerson(item); })
              }
            }, (item: AiPersonItem) => {
              const identity = personCacheIdentity(item);
              return identity.length > 0 ? `person_${identity}` : this.personName(item);
            })
          }
          .columnsTemplate(fnRepeatFrTemplate(fnAdaptiveGridColumns(3, this.windowWidthBp)))
          .columnsGap(8)
          .rowsGap(8)
          .cachedCount(4)
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 10 })

          if (this.opening && !this.loading) {
            FnFullLoadingMask({ text: '加载人物媒体中…' })
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
