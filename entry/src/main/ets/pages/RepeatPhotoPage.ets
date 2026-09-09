/**
 * 相册「检查重复」：调用 NAS repeat-photo/check，轮询 task-panel，展示并合并结果。
 */
import { common } from '@kit.AbilityKit';
import { UIContext, window } from '@kit.ArkUI';
import { AppSession, FN_MEDIA_BASE_URL } from '../auth/AppSession';
import { GalleryListItem, RepeatPhotoGroup, RepeatPhotoTaskProgress } from '../model/FnApiTypes';
import { GalleryNetworkThumb, isGifItem, isVideoItem, nasUrl, pickThumb } from '../album/GalleryAlbumCommon';
import { GalleryAlbumNavigation } from '../album/GalleryAlbumNavigation';
import { fnApplyImmersiveSystemBarColors } from '../common/FnSplashTheme';
import { FN_SYSTEM_TOP_INSET_VP_KEY, fnPublishSystemAvoidArea } from '../common/FnSystemAvoidArea';
import { FnHdsSimpleChrome } from '../common/FnHdsSimpleChrome';
import { FnFullLoadingMask, FnHdsPillButton, FnInlineLoading } from '../common/FnUiCommon';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import { galleryListPopOrRouterBack } from '../album/galleryList/GalleryListBack';
import {
  RepeatPhotoStep,
  repeatPhotoGroupDateText,
  repeatPhotoGroupKey,
  repeatPhotoPageTitle
} from './repeatPhotoPage/RepeatPhotoLogic';
import {
  RepeatPhotoActionsHost,
  repeatPhotoBootstrap,
  repeatPhotoConfirmMergeAll,
  repeatPhotoConfirmMergeGroup,
  repeatPhotoKeepGroup,
  repeatPhotoOpenPreview,
  repeatPhotoPollTask,
  repeatPhotoStartCheck,
  repeatPhotoThumbId
} from './repeatPhotoPage/RepeatPhotoActions';

const REPEAT_CARD_RADIUS_VP: number = 22;
const REPEAT_THUMB_SIZE_VP: number = 96;
const REPEAT_POLL_MS: number = 2000;

@Entry
@Component
struct RepeatPhotoPage {
  private albumNavigationMode: boolean = false;
  @StorageProp(FN_MEDIA_BASE_URL) private baseUrl: string = '';
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @State private loading: boolean = false;
  @State private starting: boolean = false;
  @State private merging: boolean = false;
  @State private error: string = '';
  @State private step: RepeatPhotoStep = 'start';
  @State private groups: RepeatPhotoGroup[] = [];
  @State private totalCount: number = 0;
  @State private strategy: string = '';
  @State private progress: RepeatPhotoTaskProgress = new RepeatPhotoTaskProgress();
  private listScroller: Scroller = new Scroller();
  private pollTimer: number = -1;
  private albumBackHandlerToken: number = 0;
  private actionsHostCache: RepeatPhotoActionsHost | undefined = undefined;

  onBackPress(): boolean {
    this.navigateBack();
    return true;
  }

  private navigateBack(): void {
    galleryListPopOrRouterBack(this.albumNavigationMode, (): void => {
      this.getUIContext().getRouter().back();
    });
  }

  private applySystemBar(relayout: boolean): void {
    try {
      const dark = this.colorMode === 1;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window): void => {
        if (relayout) {
          win.setWindowLayoutFullScreen(true).catch((_e: Error): void => {});
        }
        fnApplyImmersiveSystemBarColors(win, dark);
        fnPublishSystemAvoidArea(win, this.getUIContext());
      }).catch((_e: Error): void => {});
    } catch (_e) {
    }
  }

  private onColorModeChanged(): void {
    this.applySystemBar(false);
  }

  aboutToAppear(): void {
    this.albumNavigationMode = GalleryAlbumNavigation.isAvailable();
    this.applySystemBar(true);
    if (this.albumNavigationMode) {
      this.albumBackHandlerToken = GalleryAlbumNavigation.registerBackHandler((): boolean => {
        this.onBackPress();
        return true;
      });
    } else {
      const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
      if (rp !== undefined && rp['baseUrl'] !== undefined) {
        this.baseUrl = String(rp['baseUrl']);
      }
    }
    void repeatPhotoBootstrap(this.asActionsHost());
  }

  aboutToDisappear(): void {
    GalleryAlbumNavigation.unregisterBackHandler(this.albumBackHandlerToken);
    this.stopTaskPolling();
    const client = AppSession.getClient();
    if (client !== null) {
      client.cancelPendingRequests();
    }
  }

  private asActionsHost(): RepeatPhotoActionsHost {
    if (this.actionsHostCache !== undefined) {
      return this.actionsHostCache;
    }
    const self = this;
    class RepeatPhotoActionsHostBridge implements RepeatPhotoActionsHost {
      getUIContext(): UIContext {
        return self.getUIContext();
      }

      get baseUrl(): string {
        return self.baseUrl;
      }

      set baseUrl(v: string) {
        self.baseUrl = v;
      }

      get loading(): boolean {
        return self.loading;
      }

      set loading(v: boolean) {
        self.loading = v;
      }

      get starting(): boolean {
        return self.starting;
      }

      set starting(v: boolean) {
        self.starting = v;
      }

      get merging(): boolean {
        return self.merging;
      }

      set merging(v: boolean) {
        self.merging = v;
      }

      get error(): string {
        return self.error;
      }

      set error(v: string) {
        self.error = v;
      }

      get step(): RepeatPhotoStep {
        return self.step;
      }

      set step(v: RepeatPhotoStep) {
        self.step = v;
      }

      get groups(): RepeatPhotoGroup[] {
        return self.groups;
      }

      set groups(v: RepeatPhotoGroup[]) {
        self.groups = v;
      }

      get totalCount(): number {
        return self.totalCount;
      }

      set totalCount(v: number) {
        self.totalCount = v;
      }

      get strategy(): string {
        return self.strategy;
      }

      set strategy(v: string) {
        self.strategy = v;
      }

      get progress(): RepeatPhotoTaskProgress {
        return self.progress;
      }

      set progress(v: RepeatPhotoTaskProgress) {
        self.progress = v;
      }

      toast(msg: string): void {
        self.toast(msg);
      }

      startTaskPolling(): void {
        self.startTaskPolling();
      }

      stopTaskPolling(): void {
        self.stopTaskPolling();
      }
    }
    this.actionsHostCache = new RepeatPhotoActionsHostBridge();
    return this.actionsHostCache;
  }

  toast(msg: string): void {
    if (msg.length === 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    } catch (_e) {
    }
  }

  startTaskPolling(): void {
    this.stopTaskPolling();
    this.pollTimer = setInterval((): void => {
      void repeatPhotoPollTask(this.asActionsHost());
    }, REPEAT_POLL_MS);
  }

  stopTaskPolling(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private chromeTitle(): string {
    if (this.step === 'checking') {
      return '检查中';
    }
    return repeatPhotoPageTitle(this.strategy, '检查重复');
  }

  private chromeSubtitle(): string {
    if (this.step === 'list' && this.totalCount > 0) {
      return `${this.totalCount}组`;
    }
    return '';
  }

  private chromeRightText(): string {
    if (this.step === 'list' && this.groups.length > 0 && !this.merging) {
      return '合并所有';
    }
    return '';
  }

  private progressText(): string {
    if (this.progress.total > 0) {
      return `正在检查 ${this.progress.successCount} / ${this.progress.total} 项`;
    }
    return '正在检查相册中的重复照片';
  }

  @Builder
  private startCard(title: string, desc: string, similar: boolean) {
    Column({ space: 10 }) {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(desc)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(20)
      FnHdsPillButton({
        text: this.starting ? '启动中…' : '立即检查',
        widthValue: 120,
        heightValue: 40,
        fontSizeValue: 15,
        fontColorValue: $r('app.color.brand_primary'),
        action: (): void => {
          void repeatPhotoStartCheck(this.asActionsHost(), similar);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(20)
    .borderRadius(REPEAT_CARD_RADIUS_VP)
    .backgroundColor($r('app.color.album_shortcut_group_bg'))
  }

  @Builder
  private startPane() {
    Scroll(this.listScroller) {
      Column({ space: 14 }) {
        this.startCard(
          '检查重复照片',
          '检查相册中完全一致的重复照片和视频',
          false
        )
        this.startCard(
          '检查相似照片',
          '完成智能识别后，检查相册中相似的照片或视频',
          true
        )
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 32 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  @Builder
  private checkingPane() {
    Column({ space: 16 }) {
      Text(this.progressText())
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      Progress({ value: this.progress.percent, total: 100, type: ProgressType.Linear })
        .width('72%')
        .color($r('app.color.brand_primary'))
      if (this.progress.total > 0) {
        Text(`${this.progress.percent}%`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private groupPhotoCell(group: RepeatPhotoGroup, item: GalleryListItem, index: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      GalleryNetworkThumb({
        uri: nasUrl(this.baseUrl, pickThumb(item)),
        isVideo: isVideoItem(item),
        isGif: isGifItem(item),
        isLive: item.isLive === 1,
        clipRadius: 8
      })
        .width(REPEAT_THUMB_SIZE_VP)
        .height(REPEAT_THUMB_SIZE_VP)

      if (index === group.recommendedIndex) {
        Text('保留')
          .fontSize(11)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius({ topLeft: 8, bottomRight: 8 })
      }
    }
    .width(REPEAT_THUMB_SIZE_VP)
    .height(REPEAT_THUMB_SIZE_VP)
    .clip(true)
    .onClick((): void => {
      repeatPhotoOpenPreview(this.asActionsHost(), group, index);
    })
  }

  @Builder
  private groupCard(group: RepeatPhotoGroup, _index: number) {
    Column({ space: 12 }) {
      Row() {
        Text(repeatPhotoGroupDateText(group))
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${group.photos.length}项`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')

      Scroll() {
        Row({ space: 8 }) {
          ForEach(group.photos, (item: GalleryListItem, photoIndex: number) => {
            this.groupPhotoCell(group, item, photoIndex)
          }, (item: GalleryListItem, photoIndex: number) => `${group.id}-${repeatPhotoThumbId(item, `${photoIndex}`)}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      Row({ space: 10 }) {
        FnHdsPillButton({
          text: '保留此组',
          widthValue: 96,
          heightValue: 36,
          fontSizeValue: 14,
          action: (): void => {
            void repeatPhotoKeepGroup(this.asActionsHost(), group);
          }
        })
        FnHdsPillButton({
          text: '合并此组',
          widthValue: 96,
          heightValue: 36,
          fontSizeValue: 14,
          fontColorValue: '#E5484D',
          action: (): void => {
            void repeatPhotoConfirmMergeGroup(this.asActionsHost(), group);
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(REPEAT_CARD_RADIUS_VP)
    .backgroundColor($r('app.color.album_shortcut_group_bg'))
  }

  @Builder
  private listPane() {
    List({ scroller: this.listScroller }) {
      ForEach(this.groups, (group: RepeatPhotoGroup, index: number) => {
        ListItem() {
          Column() {
            this.groupCard(group, index)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        }
      }, (group: RepeatPhotoGroup, index: number) => repeatPhotoGroupKey(group, index))
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private emptyPane(text: string, actionText: string) {
    Column({ space: 14 }) {
      Text(text)
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
      FnHdsPillButton({
        text: actionText,
        widthValue: 120,
        heightValue: 40,
        fontSizeValue: 15,
        fontColorValue: $r('app.color.brand_primary'),
        action: (): void => {
          this.step = 'start';
          this.error = '';
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        FnHdsSimpleChrome({
          title: this.chromeTitle(),
          subtitle: this.chromeSubtitle(),
          rightText: this.chromeRightText(),
          topSafeInsetVp: this.systemTopInsetVp,
          scrollerList: [this.listScroller],
          onBack: (): void => {
            this.onBackPress();
          },
          onRightClick: (): void => {
            void repeatPhotoConfirmMergeAll(this.asActionsHost());
          }
        })
          .width('100%')

        if (this.loading && this.step !== 'checking') {
          FnInlineLoading({ text: '加载中…', topOffsetVp: 24 }).layoutWeight(1)
        } else if (this.step === 'error') {
          this.emptyPane(this.error.length > 0 ? this.error : '检查失败', '返回')
        } else if (this.step === 'checking') {
          this.checkingPane()
        } else if (this.step === 'list') {
          this.listPane()
        } else if (this.step === 'empty') {
          this.emptyPane(
            this.strategy === 'similar' ? '暂未发现相似或重复照片' : '暂未发现重复照片',
            '重新检查'
          )
        } else {
          this.startPane()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      if (this.merging) {
        FnFullLoadingMask({ text: '合并中…', topOffsetVp: this.systemTopInsetVp })
      }
    }
    .width('100%')
    .height('100%')
  }

  pageTransition() {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 12, y: 0 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: -8, y: 0 });
  }
}

@Builder
export function RepeatPhotoPageNavigationContent() {
  RepeatPhotoPage()
}
