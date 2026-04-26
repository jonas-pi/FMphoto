import { AiPersonItem, MediaCategoryItem, SmartCategoryItem } from '../../model/FnApiTypes';
import { FnInlineLoading, FnStateText } from '../../common/FnUiCommon';
import { FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { GalleryNetworkThumb, nasUrl, trimThumbPixCacheForList } from '../GalleryAlbumCommon';

const ALBUMS_HOME_SECTION_SIDE_PAD_VP: number = 14;
const ALBUMS_HOME_MEDIA_GRID_GAP_VP: number = 10;
const ALBUMS_HOME_MEDIA_CARD_RADIUS_VP: number = 22;
const ALBUMS_HOME_MEDIA_CARD_BOTTOM_PAD_VP: number = 10;
const ALBUMS_HOME_SECTION_TITLE_FONT_VP: number = 14;
const ALBUMS_HOME_SHORTCUT_CARD_HEIGHT_VP: number = 82;
const ALBUMS_HOME_SHORTCUT_TILE_SIZE_VP: number = 52;
const ALBUMS_HOME_SHORTCUT_CARD_RADIUS_VP: number = 26;
const ALBUMS_HOME_SMART_RING_GAP_VP: number = 6;
const ALBUMS_HOME_SMART_GRID_GAP_VP: number = 4;
const ALBUMS_HOME_SMART_GRID_TILE_RADIUS_VP: number = 10;

@Component
export struct GalleryAlbumAlbumsHomeView {
  @Prop baseUrl: string = '';
  @Prop contentInsetTopVp: number = 0;
  @Prop contentInsetBottomVp: number = 0;
  @Prop mediaLoading: boolean = false;
  @Prop mediaError: string = '';
  @Prop mediaOpening: boolean = false;
  @Prop mediaItems: MediaCategoryItem[] = [];
  @Prop personLoading: boolean = false;
  @Prop personError: string = '';
  @Prop personItems: AiPersonItem[] = [];
  @Prop smartLoading: boolean = false;
  @Prop smartError: string = '';
  @Prop smartSceneItems: SmartCategoryItem[] = [];
  @Prop smartInfoItems: SmartCategoryItem[] = [];
  @Prop modeSwitchOpacity: number = 1;
  @Prop modeSwitchOffsetY: number = 0;

  getMediaCategoryTitle: (item: MediaCategoryItem) => string = (_: MediaCategoryItem) => '';
  getMediaCategoryCount: (item: MediaCategoryItem) => number = (_: MediaCategoryItem) => 0;
  getMediaCategoryCover: (item: MediaCategoryItem) => string = (_: MediaCategoryItem) => '';
  getPersonName: (item: AiPersonItem) => string = (_: AiPersonItem) => '';
  getPersonFace: (item: AiPersonItem) => string = (_: AiPersonItem) => '';
  getSmartCategoryCover: (item: SmartCategoryItem) => string = (_: SmartCategoryItem) => '';
  onOpenMediaCategory: (item: MediaCategoryItem) => void = (_: MediaCategoryItem) => {};
  onOpenPersonPage: () => void = () => {};
  onOpenSmartCategoryPage: () => void = () => {};
  onOpenPlacePlaceholder: () => void = () => {};
  onOpenRecentAdded: () => void = () => {};
  onOpenCollect: () => void = () => {};
  onOpenRecycleBin: () => void = () => {};

  @State private thumbLoadingPaused: boolean = false;
  private thumbResumeTimer: number = -1;

  aboutToAppear(): void {
    this.thumbLoadingPaused = false;
  }

  aboutToDisappear(): void {
    this.clearThumbResumeTimer();
    this.recycleThumbCache(true);
  }

  private recycleThumbCache(aggressive: boolean = false): void {
    trimThumbPixCacheForList(
      this.mediaItems.length + this.personItems.length + this.combinedSmartItems().length,
      aggressive
    );
  }

  private clearThumbResumeTimer(): void {
    if (this.thumbResumeTimer >= 0) {
      clearTimeout(this.thumbResumeTimer);
      this.thumbResumeTimer = -1;
    }
  }

  private onThumbScrollActivity(): void {
    this.clearThumbResumeTimer();
    if (!this.thumbLoadingPaused) {
      this.thumbLoadingPaused = true;
    }
    this.recycleThumbCache(false);
  }

  private onThumbScrollSettled(): void {
    this.clearThumbResumeTimer();
    this.thumbResumeTimer = setTimeout((): void => {
      this.thumbResumeTimer = -1;
      this.thumbLoadingPaused = false;
    }, 96);
  }

  private combinedSmartItems(): SmartCategoryItem[] {
    return this.smartSceneItems.concat(this.smartInfoItems);
  }

  private mediaRowIndexes(): number[] {
    const totalRows = Math.ceil(this.mediaItems.length / 3);
    const out: number[] = [];
    for (let i = 0; i < totalRows; i++) {
      out.push(i);
    }
    return out;
  }

  private mediaCategoryAt(rowIdx: number, colIdx: number): MediaCategoryItem | undefined {
    const idx = rowIdx * 3 + colIdx;
    if (idx < 0 || idx >= this.mediaItems.length) {
      return undefined;
    }
    return this.mediaItems[idx];
  }

  private previewPersonAt(idx: number): AiPersonItem | undefined {
    if (idx < 0 || idx >= this.personItems.length || idx >= 4) {
      return undefined;
    }
    return this.personItems[idx];
  }

  private previewPersonFaceUri(item?: AiPersonItem): string {
    if (item === undefined) {
      return '';
    }
    return nasUrl(this.baseUrl, this.getPersonFace(item));
  }

  private previewSmartAt(idx: number): SmartCategoryItem | undefined {
    const list = this.combinedSmartItems();
    if (idx < 0 || idx >= list.length || idx >= 4) {
      return undefined;
    }
    return list[idx];
  }

  private previewSmartCoverUri(item?: SmartCategoryItem): string {
    if (item === undefined) {
      return '';
    }
    return nasUrl(this.baseUrl, this.getSmartCategoryCover(item));
  }

  private personModuleSubtitle(): string {
    if (this.personLoading && this.personItems.length <= 0) {
      return '加载中';
    }
    if (this.personError.length > 0 && this.personItems.length <= 0) {
      return '加载失败';
    }
    return `${this.personItems.length}`;
  }

  private smartModuleSubtitle(): string {
    const total = this.combinedSmartItems().length;
    if (this.smartLoading && total <= 0) {
      return '加载中';
    }
    if (this.smartError.length > 0 && total <= 0) {
      return '加载失败';
    }
    return `${total}`;
  }

  @Builder
  private mediaThumb(uri: string, placeholder: string) {
    Stack({ alignContent: Alignment.Center }) {
      if (uri.length > 0) {
        GalleryNetworkThumb({
          uri: uri,
          isVideo: false,
          isGif: false,
          paused: this.thumbLoadingPaused
        })
          .width('100%')
          .aspectRatio(1)
      } else {
        Column() {
          Text(placeholder)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
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
    .borderRadius(ALBUMS_HOME_MEDIA_CARD_RADIUS_VP)
    .clip(true)
    .backgroundColor($r('app.color.gallery_material_surface_bg'))
    .border({ width: 1, color: $r('app.color.immersive_panel_border') })
  }

  @Builder
  private mediaCategoryCell(item?: MediaCategoryItem) {
    if (item === undefined) {
      Blank().layoutWeight(1)
    } else {
      Column({ space: 8 }) {
        this.mediaThumb(
          nasUrl(this.baseUrl, this.getMediaCategoryCover(item)),
          this.getMediaCategoryTitle(item).slice(0, 1)
        )

        Text(this.getMediaCategoryTitle(item))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(`${this.getMediaCategoryCount(item)}`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .layoutWeight(1)
      .padding({ bottom: ALBUMS_HOME_MEDIA_CARD_BOTTOM_PAD_VP })
      .onClick((): void => {
        this.onOpenMediaCategory(item);
      })
    }
  }

  @Builder
  private previewFace(item?: AiPersonItem) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.previewPersonFaceUri(item).length > 0) {
        GalleryNetworkThumb({
          uri: this.previewPersonFaceUri(item),
          isVideo: false,
          isGif: false,
          paused: this.thumbLoadingPaused
        })
          .width('100%')
          .height('100%')
          .borderRadius(999)
          .clip(true)
      } else {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.gallery_material_surface_bg'))
          .borderRadius(999)
          .border({ width: 1, color: $r('app.color.immersive_panel_border') })
      }
    }
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  private personModulePreview() {
    Column({ space: ALBUMS_HOME_SMART_RING_GAP_VP }) {
      Row({ space: ALBUMS_HOME_SMART_RING_GAP_VP }) {
        this.previewFace(this.previewPersonAt(0))
        this.previewFace(this.previewPersonAt(1))
      }
      .width('100%')
      .layoutWeight(1)
      Row({ space: ALBUMS_HOME_SMART_RING_GAP_VP }) {
        this.previewFace(this.previewPersonAt(2))
        this.previewFace(this.previewPersonAt(3))
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private smartPreviewTile(item?: SmartCategoryItem) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.previewSmartCoverUri(item).length > 0) {
        GalleryNetworkThumb({
          uri: this.previewSmartCoverUri(item),
          isVideo: false,
          isGif: false,
          paused: this.thumbLoadingPaused
        })
          .width('100%')
          .height('100%')
          .borderRadius(ALBUMS_HOME_SMART_GRID_TILE_RADIUS_VP)
          .clip(true)
      } else {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.gallery_material_surface_bg'))
          .borderRadius(ALBUMS_HOME_SMART_GRID_TILE_RADIUS_VP)
          .border({ width: 1, color: $r('app.color.immersive_panel_border') })
      }
    }
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  private smartModulePreview() {
    Column({ space: ALBUMS_HOME_SMART_GRID_GAP_VP }) {
      Row({ space: ALBUMS_HOME_SMART_GRID_GAP_VP }) {
        this.smartPreviewTile(this.previewSmartAt(0))
        this.smartPreviewTile(this.previewSmartAt(1))
      }
      .width('100%')
      .layoutWeight(1)
      Row({ space: ALBUMS_HOME_SMART_GRID_GAP_VP }) {
        this.smartPreviewTile(this.previewSmartAt(2))
        this.smartPreviewTile(this.previewSmartAt(3))
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private placeModulePreview() {
    Column({ space: 6 }) {
      Text('地')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('预留')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private personModuleCard() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.personModulePreview()
      }
      .width('100%')
      .aspectRatio(1)
      .padding(10)
      .backgroundColor($r('app.color.gallery_material_surface_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .borderRadius(ALBUMS_HOME_MEDIA_CARD_RADIUS_VP)
      .border({ width: 1, color: $r('app.color.immersive_panel_border') })
      .shadow({ radius: 10, color: '#14001A33', offsetX: 0, offsetY: 4 })

      Text('人物')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.personModuleSubtitle())
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .layoutWeight(1)
    .padding({ bottom: ALBUMS_HOME_MEDIA_CARD_BOTTOM_PAD_VP })
    .onClick(this.onOpenPersonPage)
  }

  @Builder
  private placeModuleCard() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.placeModulePreview()
      }
      .width('100%')
      .aspectRatio(1)
      .padding(10)
      .backgroundColor($r('app.color.gallery_material_surface_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .borderRadius(ALBUMS_HOME_MEDIA_CARD_RADIUS_VP)
      .border({ width: 1, color: $r('app.color.immersive_panel_border') })
      .shadow({ radius: 10, color: '#14001A33', offsetX: 0, offsetY: 4 })

      Text('地点')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text('预留')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .layoutWeight(1)
    .padding({ bottom: ALBUMS_HOME_MEDIA_CARD_BOTTOM_PAD_VP })
    .onClick(this.onOpenPlacePlaceholder)
  }

  @Builder
  private smartCategoryModuleCard() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.smartModulePreview()
      }
      .width('100%')
      .aspectRatio(1)
      .padding(10)
      .backgroundColor($r('app.color.gallery_material_surface_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .borderRadius(ALBUMS_HOME_MEDIA_CARD_RADIUS_VP)
      .border({ width: 1, color: $r('app.color.immersive_panel_border') })
      .shadow({ radius: 10, color: '#14001A33', offsetX: 0, offsetY: 4 })

      Text('分类')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.smartModuleSubtitle())
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .layoutWeight(1)
    .padding({ bottom: ALBUMS_HOME_MEDIA_CARD_BOTTOM_PAD_VP })
    .onClick(this.onOpenSmartCategoryPage)
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize(ALBUMS_HOME_SECTION_TITLE_FONT_VP)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .padding({ left: ALBUMS_HOME_SECTION_SIDE_PAD_VP, right: ALBUMS_HOME_SECTION_SIDE_PAD_VP, bottom: 10 })
  }

  @Builder
  private shortcutCard(monogram: string, title: string, subtitle: string, action: () => void) {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Text(monogram)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width(ALBUMS_HOME_SHORTCUT_TILE_SIZE_VP)
      .height(ALBUMS_HOME_SHORTCUT_TILE_SIZE_VP)
      .backgroundColor($r('app.color.gallery_material_surface_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .borderRadius(18)
      .border({ width: 1, color: $r('app.color.immersive_panel_border') })

      Column({ space: 4 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(subtitle)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('>')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height(ALBUMS_HOME_SHORTCUT_CARD_HEIGHT_VP)
    .padding({ left: 14, right: 16 })
    .backgroundColor($r('app.color.gallery_material_surface_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .borderRadius(ALBUMS_HOME_SHORTCUT_CARD_RADIUS_VP)
    .border({ width: 1, color: $r('app.color.immersive_panel_border') })
    .shadow({ radius: 16, color: '#14001A33', offsetX: 0, offsetY: 6 })
    .onClick(action)
  }

  build() {
    List() {
      if (this.contentInsetTopVp > 0) {
        ListItem() {
          Column() {
            Blank().height(this.contentInsetTopVp + 8)
          }
          .width('100%')
        }
      }

      if (this.mediaLoading && this.mediaItems.length <= 0) {
        ListItem() {
          FnInlineLoading({ text: '加载媒体分类中...' })
            .width('100%')
            .padding({ top: 28, bottom: 8 })
        }
      } else if (this.mediaError.length > 0 && this.mediaItems.length <= 0) {
        ListItem() {
          FnStateText({ text: this.mediaError })
        }
      } else if (this.mediaItems.length > 0) {
        ListItem() {
          Column({ space: ALBUMS_HOME_MEDIA_GRID_GAP_VP }) {
            ForEach(this.mediaRowIndexes(), (rowIdx: number) => {
              Row({ space: ALBUMS_HOME_MEDIA_GRID_GAP_VP }) {
                this.mediaCategoryCell(this.mediaCategoryAt(rowIdx, 0))
                this.mediaCategoryCell(this.mediaCategoryAt(rowIdx, 1))
                this.mediaCategoryCell(this.mediaCategoryAt(rowIdx, 2))
              }
              .width('100%')
              .alignItems(VerticalAlign.Top)
            }, (rowIdx: number) => `album_media_row_${rowIdx}`)
          }
          .width('100%')
          .padding({ left: ALBUMS_HOME_SECTION_SIDE_PAD_VP, right: ALBUMS_HOME_SECTION_SIDE_PAD_VP })
        }
      }

      ListItem() {
        Column() {
          this.sectionTitle('智能相册')

          Row({ space: ALBUMS_HOME_MEDIA_GRID_GAP_VP }) {
            this.personModuleCard()
            this.placeModuleCard()
            this.smartCategoryModuleCard()
          }
          .width('100%')
          .padding({ left: ALBUMS_HOME_SECTION_SIDE_PAD_VP, right: ALBUMS_HOME_SECTION_SIDE_PAD_VP })
        }
        .width('100%')
        .padding({ top: 12 })
      }

      ListItem() {
        Column({ space: 10 }) {
          this.sectionTitle('常用入口')

          Column({ space: 10 }) {
            this.shortcutCard('最', '最近添加', '查看最近新增的照片与视频', this.onOpenRecentAdded)
            this.shortcutCard('藏', '收藏', '查看已收藏的媒体内容', this.onOpenCollect)
            this.shortcutCard('回', '回收站', '查看已删除但仍可恢复的项目', this.onOpenRecycleBin)
          }
          .width('100%')
          .padding({ left: ALBUMS_HOME_SECTION_SIDE_PAD_VP, right: ALBUMS_HOME_SECTION_SIDE_PAD_VP })
        }
        .width('100%')
        .padding({ top: 16 })
      }

      ListItem() {
        Column() {
          Blank().height(this.contentInsetBottomVp + 20)
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .divider({ strokeWidth: 0 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onDidScroll((_offset: number, scrollState: ScrollState): void => {
      if (scrollState !== ScrollState.Idle) {
        this.onThumbScrollActivity();
        return;
      }
      this.onThumbScrollSettled();
    })
    .opacity(this.modeSwitchOpacity)
    .translate({ x: 0, y: this.modeSwitchOffsetY })
    .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
  }
}
