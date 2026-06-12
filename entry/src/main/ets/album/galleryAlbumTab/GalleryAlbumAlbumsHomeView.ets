import { AiPersonItem, GalleryListItem, MediaCategoryItem, SmartCategoryItem } from '../../model/FnApiTypes';
import {
  FnInlineLoading,
  FnStateText
} from '../../common/FnUiCommon';
import { FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { AppSession } from '../../auth/AppSession';
import { GalleryNetworkThumb, loadThumbPix, nasUrl, pickThumb, trimThumbPixCacheForList } from '../GalleryAlbumCommon';
import { loadFirstRecentAddedItem } from '../RecentAddedOpenHelper';
import { loadFirstCollectGalleryItem } from './GalleryAlbumModeLoaders';
import { hilog } from '@kit.PerformanceAnalysisKit';

const ALBUMS_HOME_SECTION_SIDE_PAD_VP: number = 14;
const ALBUMS_HOME_MEDIA_GRID_GAP_VP: number = 10;
const ALBUMS_HOME_MEDIA_CARD_RADIUS_VP: number = 22;
const ALBUMS_HOME_MEDIA_CARD_BOTTOM_PAD_VP: number = 10;
const ALBUMS_HOME_SECTION_TITLE_FONT_VP: number = 14;
const ALBUMS_HOME_SHORTCUT_ROW_HEIGHT_VP: number = 74;
const ALBUMS_HOME_SHORTCUT_GROUP_RADIUS_VP: number = 26;
const ALBUMS_HOME_SHORTCUT_ICON_SIZE_VP: number = 52;
const ALBUMS_HOME_SHORTCUT_DIVIDER_LEFT_VP: number = 78;
const ALBUMS_HOME_SMART_RING_GAP_VP: number = 6;
const ALBUMS_HOME_SMART_GRID_GAP_VP: number = 4;
const ALBUMS_HOME_SMART_GRID_TILE_RADIUS_VP: number = 10;
const DOMAIN = 0xFF00;
const TAG = 'GalleryDiag';

@Component
export struct GalleryAlbumAlbumsHomeView {
  @Prop @Watch('onBaseUrlChanged') baseUrl: string = '';
  @Prop @Watch('onPageVisibleChanged') pageVisible: boolean = false;
  @Prop @Watch('onPageShowSignalChanged') pageShowSignal: number = 0;
  @Prop contentInsetTopVp: number = 0;
  @Prop contentInsetBottomVp: number = 0;
  @Prop mediaLoading: boolean = false;
  @Prop mediaError: string = '';
  @Prop mediaOpening: boolean = false;
  @Prop mediaItems: MediaCategoryItem[] = [];
  @Prop personLoading: boolean = false;
  @Prop personError: string = '';
  @Prop @Watch('onPersonItemsChanged') personItems: AiPersonItem[] = [];
  @Prop smartLoading: boolean = false;
  @Prop smartError: string = '';
  @Prop @Watch('onSmartSceneItemsChanged') smartSceneItems: SmartCategoryItem[] = [];
  @Prop @Watch('onSmartInfoItemsChanged') smartInfoItems: SmartCategoryItem[] = [];
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
  @State private personPreviewPix: Array<PixelMap | undefined> = [];
  @State private smartPreviewPix: Array<PixelMap | undefined> = [];
  @State private recentShortcutThumbUri: string = '';
  @State private collectShortcutThumbUri: string = '';
  @State private shortcutPreviewPix: Array<PixelMap | undefined> = [];
  @State private shortcutPreviewLoaded: boolean = false;
  private thumbResumeTimer: number = -1;
  private previewRefreshTimer: number = -1;
  private previewWarmupGen: number = 0;
  private shortcutPreviewGen: number = 0;
  private shortcutRetryTimer: number = -1;
  private shortcutRetryCount: number = 0;

  aboutToAppear(): void {
    this.thumbLoadingPaused = false;
    if (this.personPreviewPix.length <= 0 && this.smartPreviewPix.length <= 0) {
      this.queuePreviewRefresh();
    }
    this.queueShortcutPreviewRefresh(false);
  }

  aboutToDisappear(): void {
    this.clearThumbResumeTimer();
    this.clearPreviewRefreshTimer();
    this.clearShortcutRetryTimer();
    this.shortcutPreviewGen++;
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

  private clearPreviewRefreshTimer(): void {
    if (this.previewRefreshTimer >= 0) {
      clearTimeout(this.previewRefreshTimer);
      this.previewRefreshTimer = -1;
    }
  }

  private clearShortcutRetryTimer(): void {
    if (this.shortcutRetryTimer >= 0) {
      clearTimeout(this.shortcutRetryTimer);
      this.shortcutRetryTimer = -1;
    }
  }

  private queuePreviewRefresh(): void {
    this.clearPreviewRefreshTimer();
    hilog.warn(
      DOMAIN,
      TAG,
      'queuePreviewRefresh personCount=%{public}d smartSceneCount=%{public}d smartInfoCount=%{public}d firstPersonUri=%{public}s firstSmartUri=%{public}s',
      this.personItems.length,
      this.smartSceneItems.length,
      this.smartInfoItems.length,
      this.previewPersonFaceUri(this.previewPersonAt(0)),
      this.previewSmartCoverUri(this.previewSmartAt(0))
    );
    this.previewRefreshTimer = setTimeout((): void => {
      this.previewRefreshTimer = -1;
      const warmupGen = ++this.previewWarmupGen;
      void this.warmPreviewPix(warmupGen);
    }, 220);
  }

  private shortcutThumbUri(item: GalleryListItem | undefined): string {
    if (item === undefined) {
      return '';
    }
    const thumb = pickThumb(item);
    return thumb.length > 0 ? nasUrl(this.baseUrl, thumb) : '';
  }

  private resetShortcutPreviewCache(): void {
    this.clearShortcutRetryTimer();
    this.shortcutRetryCount = 0;
    this.shortcutPreviewLoaded = false;
    this.recentShortcutThumbUri = '';
    this.collectShortcutThumbUri = '';
    this.shortcutPreviewPix = [];
  }

  private scheduleShortcutPreviewRetry(gen: number, delayMs: number = 420, countFailure: boolean = true): void {
    if (gen !== this.shortcutPreviewGen || this.shortcutPreviewLoaded || !this.pageVisible) {
      return;
    }
    if (countFailure) {
      if (this.shortcutRetryCount >= 4) {
        return;
      }
      this.shortcutRetryCount++;
    }
    this.clearShortcutRetryTimer();
    this.shortcutRetryTimer = setTimeout((): void => {
      this.shortcutRetryTimer = -1;
      if (gen !== this.shortcutPreviewGen || this.shortcutPreviewLoaded || !this.pageVisible) {
        return;
      }
      void this.refreshShortcutPreviews(gen);
    }, delayMs);
  }

  private queueShortcutPreviewRefresh(force: boolean): void {
    if (!force && this.shortcutPreviewLoaded) {
      return;
    }
    this.clearShortcutRetryTimer();
    this.shortcutRetryCount = 0;
    const gen = ++this.shortcutPreviewGen;
    void this.refreshShortcutPreviews(gen);
  }

  private async refreshShortcutPreviews(gen: number): Promise<void> {
    const client = AppSession.getClient();
    if (client === null) {
      this.scheduleShortcutPreviewRetry(gen, 420, false);
      return;
    }
    const shouldContinue = (): boolean => gen === this.shortcutPreviewGen;
    const pair = await Promise.all([
      loadFirstRecentAddedItem(client, shouldContinue),
      loadFirstCollectGalleryItem(client, shouldContinue)
    ]);
    if (!shouldContinue()) {
      return;
    }
    const recentUri = this.shortcutThumbUri(pair[0].items.length > 0 ? pair[0].items[0] : undefined);
    const collectUri = this.shortcutThumbUri(pair[1].items.length > 0 ? pair[1].items[0] : undefined);
    hilog.warn(
      DOMAIN,
      TAG,
      'shortcutPreviews items recent=%{public}d collect=%{public}d recentUri=%{public}s collectUri=%{public}s',
      pair[0].items.length,
      pair[1].items.length,
      recentUri,
      collectUri
    );
    this.recentShortcutThumbUri = recentUri;
    this.collectShortcutThumbUri = collectUri;
    const pixPair = await Promise.all([
      recentUri.length > 0 ? loadThumbPix(recentUri, false) : Promise.resolve(undefined),
      collectUri.length > 0 ? loadThumbPix(collectUri, false) : Promise.resolve(undefined)
    ]);
    if (!shouldContinue()) {
      return;
    }
    this.shortcutPreviewPix = [pixPair[0], pixPair[1]];
    const recentReady = recentUri.length <= 0 || pixPair[0] !== undefined;
    const collectReady = collectUri.length <= 0 || pixPair[1] !== undefined;
    this.shortcutPreviewLoaded = recentReady && collectReady;
    hilog.warn(
      DOMAIN,
      TAG,
      'shortcutPreviews pix recent=%{public}s recentInfo=%{public}s collect=%{public}s collectInfo=%{public}s loaded=%{public}s',
      pixPair[0] !== undefined ? 'yes' : 'no',
      this.shortcutPixInfo(pixPair[0]),
      pixPair[1] !== undefined ? 'yes' : 'no',
      this.shortcutPixInfo(pixPair[1]),
      this.shortcutPreviewLoaded ? 'true' : 'false'
    );
    this.logShortcutState('after-pix');
    const stateGen = gen;
    setTimeout((): void => {
      if (stateGen === this.shortcutPreviewGen) {
        this.logShortcutState('after-pix-tick');
      }
    }, 120);
    if (this.shortcutPreviewLoaded) {
      this.shortcutRetryCount = 0;
    } else {
      this.scheduleShortcutPreviewRetry(gen, 1700, true);
    }
  }

  private async warmPreviewPix(gen: number): Promise<void> {
    const personUris: string[] = [];
    const smartUris: string[] = [];
    for (let i = 0; i < 4; i++) {
      personUris.push(this.previewPersonFaceUri(this.previewPersonAt(i)));
      smartUris.push(this.previewSmartCoverUri(this.previewSmartAt(i)));
    }
    hilog.warn(
      DOMAIN,
      TAG,
      'warmPreviewPix start gen=%{public}d personUris=%{public}s|%{public}s|%{public}s|%{public}s smartUris=%{public}s|%{public}s|%{public}s|%{public}s',
      gen,
      personUris[0] ?? '',
      personUris[1] ?? '',
      personUris[2] ?? '',
      personUris[3] ?? '',
      smartUris[0] ?? '',
      smartUris[1] ?? '',
      smartUris[2] ?? '',
      smartUris[3] ?? ''
    );
    const personPix = await Promise.all(personUris.map(async (uri: string): Promise<PixelMap | undefined> => {
      if (uri.length <= 0) {
        return undefined;
      }
      return await loadThumbPix(uri, false);
    }));
    const smartPix = await Promise.all(smartUris.map(async (uri: string): Promise<PixelMap | undefined> => {
      if (uri.length <= 0) {
        return undefined;
      }
      return await loadThumbPix(uri, false);
    }));
    if (gen !== this.previewWarmupGen) {
      hilog.warn(DOMAIN, TAG, 'warmPreviewPix stale gen=%{public}d active=%{public}d', gen, this.previewWarmupGen);
      return;
    }
    this.personPreviewPix = personPix;
    this.smartPreviewPix = smartPix;
    let personLoaded = 0;
    let smartLoaded = 0;
    for (let i = 0; i < personPix.length; i++) {
      if (personPix[i] !== undefined) {
        personLoaded++;
      }
    }
    for (let i = 0; i < smartPix.length; i++) {
      if (smartPix[i] !== undefined) {
        smartLoaded++;
      }
    }
    hilog.warn(
      DOMAIN,
      TAG,
      'warmPreviewPix done gen=%{public}d personLoaded=%{public}d/%{public}d smartLoaded=%{public}d/%{public}d',
      gen,
      personLoaded,
      personPix.length,
      smartLoaded,
      smartPix.length
    );
  }

  private onBaseUrlChanged(): void {
    this.queuePreviewRefresh();
    this.shortcutPreviewGen++;
    this.resetShortcutPreviewCache();
    if (this.pageVisible) {
      this.queueShortcutPreviewRefresh(true);
    }
  }

  private onPageVisibleChanged(): void {
    if (!this.pageVisible) {
      this.clearShortcutRetryTimer();
      return;
    }
    this.queueShortcutPreviewRefresh(true);
  }

  private onPageShowSignalChanged(): void {
    if (this.pageVisible) {
      this.queueShortcutPreviewRefresh(true);
    }
  }

  private onPersonItemsChanged(): void {
    this.queuePreviewRefresh();
  }

  private onSmartSceneItemsChanged(): void {
    this.queuePreviewRefresh();
  }

  private onSmartInfoItemsChanged(): void {
    this.queuePreviewRefresh();
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

  @Builder
  private mediaPlaceholderCell() {
    Column({ space: 8 }) {
      Stack()
        .width('100%')
        .aspectRatio(1)
        .borderRadius(ALBUMS_HOME_MEDIA_CARD_RADIUS_VP)
        .backgroundColor($r('app.color.gallery_material_surface_bg'))
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })

      Blank()
        .width('56%')
        .height(13)
        .borderRadius(7)
        .backgroundColor('#14001A33')

      Blank()
        .width('26%')
        .height(11)
        .borderRadius(6)
        .backgroundColor('#10001A33')
    }
    .layoutWeight(1)
    .padding({ bottom: ALBUMS_HOME_MEDIA_CARD_BOTTOM_PAD_VP })
  }

  @Builder
  private mediaLoadingPlaceholder() {
    Column({ space: ALBUMS_HOME_MEDIA_GRID_GAP_VP }) {
      Row({ space: ALBUMS_HOME_MEDIA_GRID_GAP_VP }) {
        this.mediaPlaceholderCell()
        this.mediaPlaceholderCell()
        this.mediaPlaceholderCell()
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Row({ space: ALBUMS_HOME_MEDIA_GRID_GAP_VP }) {
        this.mediaPlaceholderCell()
        this.mediaPlaceholderCell()
        this.mediaPlaceholderCell()
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding({ left: ALBUMS_HOME_SECTION_SIDE_PAD_VP, right: ALBUMS_HOME_SECTION_SIDE_PAD_VP })
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

  private previewUriToken(uri: string): string {
    if (uri.length <= 0) {
      return 'empty';
    }
    let hash = 0;
    for (let i = 0; i < uri.length; i++) {
      hash = (hash * 131 + uri.charCodeAt(i)) % 2147483647;
    }
    return `${uri.length}_${hash}`;
  }

  private shortcutPixInfo(pix: PixelMap | undefined): string {
    if (pix === undefined) {
      return 'none';
    }
    try {
      const info = pix.getImageInfoSync();
      return `${info.size.width}x${info.size.height}`;
    } catch (_e) {
      return 'info-error';
    }
  }

  private shortcutIconBranch(thumbUri: string, thumbPix: PixelMap | undefined, recycle: boolean): string {
    if (thumbUri.length > 0) {
      return thumbPix !== undefined ? 'network-cache-ready' : 'network-wait-cache';
    }
    return recycle ? 'recycle-symbol' : 'monogram';
  }

  private shortcutIndexOf(kind: string): number {
    if (kind === 'recent') {
      return 0;
    }
    if (kind === 'collect') {
      return 1;
    }
    return -1;
  }

  private shortcutThumbUriForKind(kind: string): string {
    if (kind === 'recent') {
      return this.recentShortcutThumbUri;
    }
    if (kind === 'collect') {
      return this.collectShortcutThumbUri;
    }
    return '';
  }

  private shortcutPreviewPixForKind(kind: string): PixelMap | undefined {
    return this.shortcutPreviewPixAt(this.shortcutIndexOf(kind));
  }

  private shortcutDebugLabel(kind: string): string {
    return `shortcut_${kind}_${this.shortcutPreviewPixForKind(kind) !== undefined ? 'pix' : 'nopix'}`;
  }

  private shortcutThumbId(kind: string): string {
    return `album_shortcut_${kind}_${this.previewUriToken(this.shortcutThumbUriForKind(kind))}`;
  }

  private shortcutPreviewPixAt(idx: number): PixelMap | undefined {
    if (idx < 0 || idx >= this.shortcutPreviewPix.length) {
      return undefined;
    }
    return this.shortcutPreviewPix[idx];
  }

  private logShortcutIconSnapshot(
    stage: string,
    kind: string,
    recycle: boolean,
    widthText: string,
    heightText: string
  ): void {
    const thumbUri = this.shortcutThumbUriForKind(kind);
    const thumbPix = this.shortcutPreviewPixForKind(kind);
    hilog.warn(
      DOMAIN,
      TAG,
      'shortcutRender stage=%{public}s kind=%{public}s branch=%{public}s uriToken=%{public}s pix=%{public}s area=%{public}s/%{public}s pageVisible=%{public}s',
      stage,
      kind,
      this.shortcutIconBranch(thumbUri, thumbPix, recycle),
      this.previewUriToken(thumbUri),
      this.shortcutPixInfo(thumbPix),
      widthText,
      heightText,
      this.pageVisible ? 'true' : 'false'
    );
  }

  private logShortcutState(stage: string): void {
    hilog.warn(
      DOMAIN,
      TAG,
      'shortcutState stage=%{public}s recentBranch=%{public}s recentUriToken=%{public}s recentPix=%{public}s collectBranch=%{public}s collectUriToken=%{public}s collectPix=%{public}s loaded=%{public}s pageVisible=%{public}s',
      stage,
      this.shortcutIconBranch(this.recentShortcutThumbUri, this.shortcutPreviewPixAt(0), false),
      this.previewUriToken(this.recentShortcutThumbUri),
      this.shortcutPixInfo(this.shortcutPreviewPixAt(0)),
      this.shortcutIconBranch(this.collectShortcutThumbUri, this.shortcutPreviewPixAt(1), false),
      this.previewUriToken(this.collectShortcutThumbUri),
      this.shortcutPixInfo(this.shortcutPreviewPixAt(1)),
      this.shortcutPreviewLoaded ? 'true' : 'false',
      this.pageVisible ? 'true' : 'false'
    );
  }

  private previewThumbId(kind: string, idx: number, uri: string): string {
    return `${kind}_${idx}_${this.previewUriToken(uri)}`;
  }

  private previewPersonThumbId(item: AiPersonItem | undefined, idx: number): string {
    return this.previewThumbId('album_person_preview', idx, this.previewPersonFaceUri(item));
  }

  private previewSmartThumbId(item: SmartCategoryItem | undefined, idx: number): string {
    return this.previewThumbId('album_smart_preview', idx, this.previewSmartCoverUri(item));
  }

  private personPreviewPixAt(idx: number): PixelMap | undefined {
    if (idx < 0 || idx >= this.personPreviewPix.length) {
      return undefined;
    }
    return this.personPreviewPix[idx];
  }

  private smartPreviewPixAt(idx: number): PixelMap | undefined {
    if (idx < 0 || idx >= this.smartPreviewPix.length) {
      return undefined;
    }
    return this.smartPreviewPix[idx];
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
          paused: !this.pageVisible || this.thumbLoadingPaused
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
  private previewFace(item: AiPersonItem | undefined, idx: number) {
    if (this.personPreviewPixAt(idx) !== undefined) {
      Image(this.personPreviewPixAt(idx) as PixelMap)
        .id(this.previewPersonThumbId(item, idx))
        .layoutWeight(1)
        .width('100%')
        .aspectRatio(1)
        .objectFit(ImageFit.Cover)
        .borderRadius(999)
        .clip(true)
        .backgroundColor($r('app.color.gallery_material_surface_bg'))
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })
        .draggable(false)
    } else if (this.previewPersonFaceUri(item).length > 0) {
      GalleryNetworkThumb({
        uri: this.previewPersonFaceUri(item),
        isVideo: false,
        isGif: false,
        paused: false,
        debugLabel: `home_person_${idx}`
      })
        .id(this.previewPersonThumbId(item, idx))
        .layoutWeight(1)
        .width('100%')
        .aspectRatio(1)
        .borderRadius(999)
        .clip(true)
        .backgroundColor($r('app.color.gallery_material_surface_bg'))
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })
    } else {
      Stack()
        .layoutWeight(1)
        .width('100%')
        .aspectRatio(1)
        .borderRadius(999)
        .clip(true)
        .backgroundColor($r('app.color.gallery_material_surface_bg'))
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })
    }
  }

  @Builder
  private personModulePreview() {
    Column({ space: ALBUMS_HOME_SMART_RING_GAP_VP }) {
      Row({ space: ALBUMS_HOME_SMART_RING_GAP_VP }) {
        this.previewFace(this.previewPersonAt(0), 0)
        this.previewFace(this.previewPersonAt(1), 1)
      }
      .width('100%')
      Row({ space: ALBUMS_HOME_SMART_RING_GAP_VP }) {
        this.previewFace(this.previewPersonAt(2), 2)
        this.previewFace(this.previewPersonAt(3), 3)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private smartPreviewTile(item: SmartCategoryItem | undefined, idx: number) {
    if (this.smartPreviewPixAt(idx) !== undefined) {
      Image(this.smartPreviewPixAt(idx) as PixelMap)
        .id(this.previewSmartThumbId(item, idx))
        .layoutWeight(1)
        .width('100%')
        .aspectRatio(1)
        .objectFit(ImageFit.Cover)
        .borderRadius(ALBUMS_HOME_SMART_GRID_TILE_RADIUS_VP)
        .clip(true)
        .backgroundColor($r('app.color.gallery_material_surface_bg'))
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })
        .draggable(false)
    } else if (this.previewSmartCoverUri(item).length > 0) {
      GalleryNetworkThumb({
        uri: this.previewSmartCoverUri(item),
        isVideo: false,
        isGif: false,
        paused: false,
        debugLabel: `home_smart_${idx}`
      })
        .id(this.previewSmartThumbId(item, idx))
        .layoutWeight(1)
        .width('100%')
        .aspectRatio(1)
        .borderRadius(ALBUMS_HOME_SMART_GRID_TILE_RADIUS_VP)
        .clip(true)
        .backgroundColor($r('app.color.gallery_material_surface_bg'))
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })
    } else {
      Stack()
        .layoutWeight(1)
        .width('100%')
        .aspectRatio(1)
        .borderRadius(ALBUMS_HOME_SMART_GRID_TILE_RADIUS_VP)
        .clip(true)
        .backgroundColor($r('app.color.gallery_material_surface_bg'))
        .border({ width: 1, color: $r('app.color.immersive_panel_border') })
    }
  }

  @Builder
  private smartModulePreview() {
    Column({ space: ALBUMS_HOME_SMART_GRID_GAP_VP }) {
      Row({ space: ALBUMS_HOME_SMART_GRID_GAP_VP }) {
        this.smartPreviewTile(this.previewSmartAt(0), 0)
        this.smartPreviewTile(this.previewSmartAt(1), 1)
      }
      .width('100%')
      Row({ space: ALBUMS_HOME_SMART_GRID_GAP_VP }) {
        this.smartPreviewTile(this.previewSmartAt(2), 2)
        this.smartPreviewTile(this.previewSmartAt(3), 3)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private placeModulePreview() {
    Image($r('app.media.map_entry_cover'))
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Cover)
      .borderRadius(ALBUMS_HOME_SMART_GRID_TILE_RADIUS_VP)
      .clip(true)
      .backgroundColor($r('app.color.gallery_material_surface_bg'))
      .border({ width: 1, color: $r('app.color.immersive_panel_border') })
      .draggable(false)
  }

  @Builder
  private personModuleCard() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.personModulePreview()
      }
      .width('100%')
      .aspectRatio(1)

      Text('人物')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.personModuleSubtitle())
        .fontSize(13)
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

      Text('地图')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text('照片足迹')
        .fontSize(13)
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

      Text('分类')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.smartModuleSubtitle())
        .fontSize(13)
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
  private shortcutIcon(
    kind: string,
    monogram: string,
    recycle: boolean = false
  ) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shortcutPreviewPixForKind(kind) !== undefined) {
        Image(this.shortcutPreviewPixForKind(kind) as PixelMap)
          .id(this.shortcutThumbId(kind))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      } else if (this.shortcutThumbUriForKind(kind).length > 0) {
        GalleryNetworkThumb({
          uri: this.shortcutThumbUriForKind(kind),
          isVideo: false,
          isGif: false,
          paused: false,
          fadeInEnabled: false,
          debugLabel: this.shortcutDebugLabel(kind),
          cacheIdentity: `shortcut_${kind}`
        })
          .id(this.shortcutThumbId(kind))
          .width('100%')
          .height('100%')
      } else if (recycle) {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(24)
          .fontColor([$r('app.color.text_secondary')])
      } else {
        Text(monogram)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width(ALBUMS_HOME_SHORTCUT_ICON_SIZE_VP)
    .height(ALBUMS_HOME_SHORTCUT_ICON_SIZE_VP)
    .borderRadius(16)
    .backgroundColor('#12001A33')
    .clip(true)
    .onAppear((): void => {
      this.logShortcutIconSnapshot('appear', kind, recycle, 'n/a', 'n/a');
    })
  }

  @Builder
  private shortcutRow(
    kind: string,
    monogram: string,
    title: string,
    action: () => void,
    recycle: boolean = false
  ) {
    Row({ space: 14 }) {
      this.shortcutIcon(kind, monogram, recycle)

      Text(title)
        .layoutWeight(1)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .height(ALBUMS_HOME_SHORTCUT_ROW_HEIGHT_VP)
    .padding({ left: 14, right: 18 })
    .alignItems(VerticalAlign.Center)
    .onClick(action)
  }

  @Builder
  private shortcutDivider() {
    Divider()
      .strokeWidth(1)
      .color($r('app.color.gallery_material_shell_border'))
      .margin({ left: ALBUMS_HOME_SHORTCUT_DIVIDER_LEFT_VP })
  }

  @Builder
  private shortcutGroup() {
    Column() {
      this.shortcutRow('recent', '近', '最近添加', this.onOpenRecentAdded)
      this.shortcutDivider()
      this.shortcutRow('collect', '藏', '收藏夹', this.onOpenCollect)
    }
    .width('100%')
    .borderRadius(ALBUMS_HOME_SHORTCUT_GROUP_RADIUS_VP)
    .backgroundColor($r('app.color.album_shortcut_group_bg'))
    .clip(true)
  }

  @Builder
  private recycleShortcutGroup() {
    Column() {
      this.shortcutRow('recycle', '回', '回收站', this.onOpenRecycleBin, true)
    }
    .width('100%')
    .borderRadius(ALBUMS_HOME_SHORTCUT_GROUP_RADIUS_VP)
    .backgroundColor($r('app.color.album_shortcut_group_bg'))
    .clip(true)
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
          Column() {
            this.mediaLoadingPlaceholder()
          }
          .width('100%')
          .padding({ top: 8 })
        }
      } else if (false && this.mediaLoading && this.mediaItems.length <= 0) {
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

          Column({ space: 12 }) {
            this.shortcutGroup()
            this.recycleShortcutGroup()
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
    .translate({ x: this.modeSwitchOffsetY, y: 0 })
    .animation({ duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE })
  }
}
