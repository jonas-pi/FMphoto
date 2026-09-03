import { common } from '@kit.AbilityKit';
import { AppSession, FN_MEDIA_BASE_URL } from '../auth/AppSession';
import { CategoryGalleryNavStore } from '../album/CategoryGalleryNavStore';
import { SmartCategoryItem } from '../model/FnApiTypes';
import { loadSmartCategoryGalleryItems, fetchMissingCustomSmartCategoryCovers, smartCategoryCoverPatchFromItems } from '../album/SmartCategoryMagicSearch';
import { loadSmartCategories } from '../album/galleryAlbumTab/GalleryAlbumModeLoaders';
import { GalleryNetworkThumb, nasUrl, trimThumbPixCacheForList } from '../album/GalleryAlbumCommon';
import { smartCategoryCover, smartCategoryCount, smartCategoryName } from '../album/GalleryAlbumEntityData';
import {
  smartCategoryApplyCoverPatches,
  smartCategoryCurrentAccount,
  smartCategoryCustomIdOf,
  smartCategoryIsCustom,
  smartCategoryLayoutFromDisplay,
  smartCategoryMonogram,
  smartCategoryMoveItems,
  smartCategoryNewCustomId,
  smartCategorySaveLayout,
  smartCategoryValidateNewKeyword,
  SMART_CATEGORY_KEYWORD_MAX_LEN
} from '../album/SmartCategoryLayoutPreferences';
import { FnFullLoadingMask, FnInlineLoading, FnPrimaryButton, FnStateText, FnTopBar } from '../common/FnUiCommon';
import { fnHdsFitContentSheetOptions } from '../common/FnHdsOverlay';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';

@Entry
@Component
struct SmartCategoryPage {
  @StorageProp(FN_MEDIA_BASE_URL) private baseUrl: string = '';
  @State private loading: boolean = false;
  @State private opening: boolean = false;
  @State private error: string = '';
  @State private sceneItems: SmartCategoryItem[] = [];
  @State private infoItems: SmartCategoryItem[] = [];
  @State private customItems: SmartCategoryItem[] = [];
  @State private editing: boolean = false;
  @State private addSheetVisible: boolean = false;
  @State private addKeywordDraft: string = '';
  @State private thumbLoadingPaused: boolean = false;
  private thumbResumeTimer: number = -1;
  private persistSeq: number = 0;
  private coverEnrichGen: number = 0;

  onBackPress(): boolean {
    if (this.addSheetVisible) {
      this.addSheetVisible = false;
      return true;
    }
    if (this.editing) {
      this.editing = false;
      return true;
    }
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
    return this.sceneItems.length + this.infoItems.length + this.customItems.length;
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

  private hostContext(): common.UIAbilityContext | undefined {
    try {
      const ctx = this.getUIContext().getHostContext();
      if (ctx === undefined || ctx === null) {
        return undefined;
      }
      return ctx as common.UIAbilityContext;
    } catch (_e) {
      return undefined;
    }
  }

  private nameOf(item: SmartCategoryItem): string {
    return smartCategoryName(item);
  }

  private coverOf(item: SmartCategoryItem): string {
    return smartCategoryCover(item);
  }

  private countLabelOf(item: SmartCategoryItem): string {
    const n = smartCategoryCount(item);
    if (n > 0) {
      return `${n} 项`;
    }
    return smartCategoryIsCustom(item) ? '自定义' : '0 项';
  }

  private smartCategoryGridKey(item: SmartCategoryItem, index: number, prefix: string): string {
    const customId = smartCategoryCustomIdOf(item);
    if (customId.length > 0) {
      return `${prefix}_c_${customId}_${this.coverOf(item)}`;
    }
    return `${prefix}_${index}_${this.nameOf(item)}_${this.coverOf(item)}`;
  }

  private async loadData(): Promise<void> {
    this.loading = true;
    this.error = '';
    this.sceneItems = [];
    this.infoItems = [];
    this.customItems = [];
    const client = AppSession.getClient();
    if (client === null) {
      this.loading = false;
      this.error = '未登录';
      return;
    }
    try {
      const result = await loadSmartCategories(client, this.hostContext());
      this.sceneItems = result.sceneItems;
      this.infoItems = result.infoItems;
      this.customItems = result.customItems;
      this.error = result.error;
      void this.enrichCustomCovers();
    } catch (e) {
      this.error = String(e) || '智能分类加载异常';
    }
    this.loading = false;
  }

  private async persistLayout(): Promise<boolean> {
    const ctx = this.hostContext();
    const account = smartCategoryCurrentAccount();
    if (ctx === undefined || account.length === 0) {
      this.toast('保存失败');
      return false;
    }
    const seq = ++this.persistSeq;
    const layout = smartCategoryLayoutFromDisplay(account, this.sceneItems, this.infoItems, this.customItems);
    const ok = await smartCategorySaveLayout(ctx, layout);
    if (seq !== this.persistSeq) {
      return ok;
    }
    if (!ok) {
      this.toast('保存失败');
    }
    return ok;
  }

  private async enrichCustomCovers(): Promise<void> {
    const client = AppSession.getClient();
    if (client === null || this.customItems.length === 0) {
      return;
    }
    const gen = ++this.coverEnrichGen;
    const patches = await fetchMissingCustomSmartCategoryCovers(client, this.customItems);
    if (gen !== this.coverEnrichGen || patches.length === 0) {
      return;
    }
    this.customItems = smartCategoryApplyCoverPatches(this.customItems, patches);
    await this.persistLayout();
  }

  private handleBack(): void {
    if (this.addSheetVisible) {
      this.addSheetVisible = false;
      return;
    }
    if (this.editing) {
      this.editing = false;
      return;
    }
    this.getUIContext().getRouter().back();
  }

  private toggleEditing(): void {
    if (this.loading) {
      return;
    }
    this.editing = !this.editing;
    if (this.editing) {
      this.addSheetVisible = false;
    }
  }

  private openAddSheet(): void {
    this.addKeywordDraft = '';
    this.addSheetVisible = true;
  }

  private async confirmAddKeyword(): Promise<void> {
    const err = smartCategoryValidateNewKeyword(
      this.addKeywordDraft,
      this.sceneItems,
      this.infoItems,
      this.customItems
    );
    if (err.length > 0) {
      this.toast(err);
      return;
    }
    const keyword = this.addKeywordDraft.trim();
    const prev = this.customItems.slice();
    const next: SmartCategoryItem[] = this.customItems.slice();
    const item: SmartCategoryItem = {
      name: keyword,
      customId: smartCategoryNewCustomId(),
      count: 0
    };
    next.push(item);
    this.customItems = next;
    this.addKeywordDraft = '';
    this.addSheetVisible = false;
    this.error = '';
    const ok = await this.persistLayout();
    if (!ok) {
      this.customItems = prev;
      return;
    }
    void this.enrichCustomCovers();
  }

  private async deleteCustomItem(item: SmartCategoryItem): Promise<void> {
    const id = smartCategoryCustomIdOf(item);
    if (id.length === 0) {
      return;
    }
    const prev = this.customItems.slice();
    const next: SmartCategoryItem[] = [];
    for (let i = 0; i < this.customItems.length; i++) {
      if (smartCategoryCustomIdOf(this.customItems[i]) !== id) {
        next.push(this.customItems[i]);
      }
    }
    this.customItems = next;
    const ok = await this.persistLayout();
    if (!ok) {
      this.customItems = prev;
    }
  }

  private onSceneMove(from: number, to: number): void {
    smartCategoryMoveItems(this.sceneItems, from, to);
    void this.persistLayout();
  }

  private onInfoMove(from: number, to: number): void {
    smartCategoryMoveItems(this.infoItems, from, to);
    void this.persistLayout();
  }

  private onCustomMove(from: number, to: number): void {
    smartCategoryMoveItems(this.customItems, from, to);
    void this.persistLayout();
  }

  private async openSmartCategory(item: SmartCategoryItem): Promise<void> {
    if (this.editing || this.opening) {
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
      const mapped = await loadSmartCategoryGalleryItems(client, keyword);
      if (mapped.errorMessage.length > 0) {
        this.toast(mapped.errorMessage);
        return;
      }
      if (mapped.items.length === 0) {
        this.toast('该分类暂无可预览媒体');
        return;
      }
      const ok = await CategoryGalleryNavStore.open(
        this.baseUrl,
        keyword,
        mapped.items,
        this.getUIContext(),
        false,
        {
          sourceKind: 'smart-category',
          smartCategoryKeyword: keyword,
          expectedTotalCount: mapped.items.length
        }
      );
      if (!ok) {
        this.toast('打开分类失败');
        return;
      }
      const customId = smartCategoryCustomIdOf(item);
      const patch = smartCategoryCoverPatchFromItems(customId, mapped.items);
      if (patch !== undefined) {
        this.customItems = smartCategoryApplyCoverPatches(this.customItems, [patch]);
        void this.persistLayout();
      }
    } finally {
      this.opening = false;
    }
  }

  @Builder
  private categoryThumb(item: SmartCategoryItem) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.coverOf(item).length > 0) {
        GalleryNetworkThumb({
          uri: nasUrl(this.baseUrl, this.coverOf(item)),
          isVideo: false,
          isGif: false,
          paused: this.thumbLoadingPaused,
        })
          .width('100%')
          .height('100%')
      } else {
        Text(smartCategoryMonogram(item))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .aspectRatio(1)
    .borderRadius(22)
    .clip(true)
    .backgroundColor($r('app.color.gallery_material_surface_bg'))
  }

  @Builder
  private categoryGrid(list: SmartCategoryItem[], keyPrefix: string) {
    Grid() {
      ForEach(list, (item: SmartCategoryItem, idx: number) => {
        GridItem() {
          Column({ space: 8 }) {
            this.categoryThumb(item)

            Text(this.nameOf(item))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Text(this.countLabelOf(item))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 2, right: 2, bottom: 10 })
          .onClick((): void => {
            void this.openSmartCategory(item);
          })
        }
      }, (item: SmartCategoryItem, i: number) => this.smartCategoryGridKey(item, i, keyPrefix))
    }
    .columnsTemplate('1fr 1fr 1fr')
    .columnsGap(10)
    .rowsGap(10)
    .cachedCount(6)
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 10 })
  }

  @Builder
  private browseSection(title: string, list: SmartCategoryItem[], keyPrefix: string) {
    if (list.length > 0) {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 14, right: 14, top: 8, bottom: 4 })
      this.categoryGrid(list, keyPrefix)
    }
  }

  @Builder
  private editSectionTitle(title: string, showAdd: boolean) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      if (showAdd) {
        Text('添加关键词')
          .fontSize(13)
          .fontColor($r('app.color.brand_primary'))
          .onClick((): void => {
            this.openAddSheet();
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 4 })
  }

  @Builder
  private editRow(item: SmartCategoryItem, allowDelete: boolean) {
    Row() {
      SymbolGlyph($r('sys.symbol.line_3_horizontal'))
        .fontSize(18)
        .fontColor([$r('app.color.text_secondary')])
        .margin({ right: 12 })
      Text(this.nameOf(item))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (allowDelete) {
        SymbolGlyph($r('sys.symbol.minus_circle_fill'))
          .fontSize(22)
          .fontColor([$r('sys.color.ohos_id_color_warning')])
          .onClick((): void => {
            void this.deleteCustomItem(item);
          })
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  private addKeywordSheetBuilder() {
    Column({ space: 12 }) {
      Text('输入后将作为 AI 语义搜索关键词')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ text: this.addKeywordDraft, placeholder: '例如：海边、宠物' })
        .maxLength(SMART_CATEGORY_KEYWORD_MAX_LEN)
        .enableKeyboardOnFocus(true)
        .onChange((v: string): void => {
          this.addKeywordDraft = v;
        })
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius($r('app.float.radius_medium'))
        .padding({ left: 12, right: 12 })

      FnPrimaryButton({
        text: '添加',
        action: (): void => {
          void this.confirmAddKeyword();
        }
      })
        .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 24, top: 8 })
    .backgroundColor(Color.Transparent)
  }

  build() {
    Column() {
      FnTopBar({
        title: '智能分类',
        rightText: this.loading ? '' : (this.editing ? '完成' : '编辑'),
        onBack: (): void => {
          this.handleBack();
        },
        onRightClick: (): void => {
          this.toggleEditing();
        }
      })

      if (this.loading) {
        FnInlineLoading({ text: '加载中...' }).layoutWeight(1)
      } else if (this.error.length > 0 && this.totalSmartItemCount() <= 0) {
        FnStateText({ text: this.error })
      } else if (this.totalSmartItemCount() <= 0 && !this.editing) {
        FnStateText({ text: '暂无智能分类' })
      } else if (this.editing) {
        List() {
          ListItem() {
            this.editSectionTitle('场景事物', false)
          }
          ForEach(this.sceneItems, (item: SmartCategoryItem, idx: number) => {
            ListItem() {
              this.editRow(item, false)
            }
          }, (item: SmartCategoryItem, i: number) => this.smartCategoryGridKey(item, i, 'edit_scene'))
            .onMove((from: number, to: number): void => {
              this.onSceneMove(from, to);
            })

          ListItem() {
            this.editSectionTitle('资料记录', false)
          }
          ForEach(this.infoItems, (item: SmartCategoryItem, idx: number) => {
            ListItem() {
              this.editRow(item, false)
            }
          }, (item: SmartCategoryItem, i: number) => this.smartCategoryGridKey(item, i, 'edit_info'))
            .onMove((from: number, to: number): void => {
              this.onInfoMove(from, to);
            })

          ListItem() {
            this.editSectionTitle('我的分类', true)
          }
          ForEach(this.customItems, (item: SmartCategoryItem, idx: number) => {
            ListItem() {
              this.editRow(item, true)
            }
          }, (item: SmartCategoryItem, i: number) => this.smartCategoryGridKey(item, i, 'edit_custom'))
            .onMove((from: number, to: number): void => {
              this.onCustomMove(from, to);
            })

          if (this.customItems.length <= 0) {
            ListItem() {
              Text('还没有自定义关键词，点上方「添加关键词」')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
                .padding({ left: 16, right: 16, top: 8, bottom: 16 })
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .divider({ strokeWidth: 0 })
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Scroll() {
            Column() {
              this.browseSection('我的分类', this.customItems, 'sc_custom')
              this.browseSection('场景事物', this.sceneItems, 'sc_scene')
              this.browseSection('资料记录', this.infoItems, 'sc_info')
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
    .bindSheet(this.addSheetVisible, this.addKeywordSheetBuilder, fnHdsFitContentSheetOptions(
      '添加关键词',
      (): void => {
        this.addSheetVisible = false;
      }
    ))
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
