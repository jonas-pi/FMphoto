import {
  HdsNavigation,
  HdsNavigationBackButtonItemOptions,
  HdsNavigationIconOptions,
  HdsNavigationMenuItemOptions,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode,
  IconStyleMode,
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import { FN_HDS_NAV_CHROME_HEIGHT_VP, fnHdsMiniTitleBarOptions } from './FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from './FnImmersiveSettings';
import { FnTransferDirection } from './FnTransferProgress';
import { fnResolvedCardFill, FN_RESOLVED_ACCENT_KEY, FN_RESOLVED_CARD_BG_KEY,
  fnResolvedTextPrimary,
  FN_RESOLVED_TEXT_PRIMARY_KEY,
  fnResolvedTextSecondary,
  FN_RESOLVED_TEXT_SECONDARY_KEY} from './FnThemeColors';
import { AppSession } from '../auth/AppSession';
import { invalidateNasTaskPanelPoll, refreshNasTaskPanelNow } from '../network/FnNasTaskPanelSync';
import {
  FnTransferQueueStore,
  FnTransferTaskSnapshot,
  FnTransferTaskStatus
} from './FnTransferQueueStore';

/**
 * 任务队列半屏。顶栏按钮与设置 / 图库同一套 HdsNavigation 圆形菜单。
 */
@Component
export struct FnTransferQueueSheet {
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @StorageProp(FN_RESOLVED_TEXT_SECONDARY_KEY) private themeTextSecondary: string = '';
  @StorageProp(FN_RESOLVED_ACCENT_KEY) private accent: string = '#FF4A8BFF';
  @StorageProp(FN_RESOLVED_CARD_BG_KEY) private cardBg: string = '';
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  @Prop tasks: FnTransferTaskSnapshot[] = [];
  @State private clearingDone: boolean = false;
  onClose: () => void = (): void => {};

  private completedTaskCount(): number {
    let n = 0;
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].status === FnTransferTaskStatus.COMPLETED) {
        n++;
      }
    }
    return n;
  }

  private canClearCompleted(): boolean {
    return this.completedTaskCount() > 0;
  }

  private toast(message: string): void {
    if (message.length === 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200
      });
    } catch (_e) {
    }
  }

  private onClearCompleted(): void {
    if (!this.canClearCompleted() || this.clearingDone) {
      return;
    }
    const nasIds = FnTransferQueueStore.completedNasIds();
    FnTransferQueueStore.suppressNasIds(nasIds);
    invalidateNasTaskPanelPoll();
    FnTransferQueueStore.clearCompleted();
    if (nasIds.length === 0) {
      return;
    }
    this.clearingDone = true;
    void this.clearNasDone(nasIds);
  }

  private async clearNasDone(nasIds: string[]): Promise<void> {
    const client = AppSession.getClient();
    if (client === null) {
      FnTransferQueueStore.releaseNasIds(nasIds);
      this.clearingDone = false;
      this.toast('未连接，已完成任务会再出现');
      refreshNasTaskPanelNow();
      return;
    }
    try {
      const res = await client.clearTaskPanelDone();
      if (!res.success) {
        FnTransferQueueStore.releaseNasIds(nasIds);
        const message = res.message !== undefined && res.message.length > 0 ? res.message : '清除已完成失败';
        this.toast(message);
      }
    } catch (_e) {
      FnTransferQueueStore.releaseNasIds(nasIds);
      this.toast('清除已完成失败');
    } finally {
      this.clearingDone = false;
      refreshNasTaskPanelNow();
    }
  }

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private menuItem(content: HdsNavigationIconOptions): HdsNavigationMenuItemOptions {
    const item: HdsNavigationMenuItemOptions = { content: content };
    return item;
  }

  private titleBarContent(): TitleBarContentOptions {
    const clearContent: HdsNavigationIconOptions = {
      label: '清除已完成',
      icon: $r('sys.symbol.trash'),
      type: IconStyleMode.NORMAL,
      isEnabled: this.canClearCompleted(),
      action: (): void => {
        this.onClearCompleted();
      }
    };
    const closeContent: HdsNavigationIconOptions = {
      label: '关闭',
      icon: $r('sys.symbol.xmark'),
      type: IconStyleMode.NORMAL,
      isEnabled: true,
      action: (): void => {
        this.onClose();
      }
    };
    const backIcon: HdsNavigationBackButtonItemOptions = {
      label: '返回',
      isEnabled: false,
      action: (): void => {
      }
    };
    return {
      title: { mainTitle: '任务队列' },
      menu: { value: [this.menuItem(clearContent), this.menuItem(closeContent)] },
      backIcon: backIcon
    };
  }

  private titleBarOptions(): HdsNavigationTitleBarOptions {
    return fnHdsMiniTitleBarOptions(this.canUseHds(), this.titleBarContent(), false,
      fnResolvedTextPrimary(this.themeTextPrimary), fnResolvedTextSecondary(this.themeTextSecondary));
  }

  @Builder
  private titleBarNavigationBody() {
    Column()
      .width('100%')
      .height(0)
  }

  private directionColor(direction: FnTransferDirection): ResourceColor {
    if (direction === FnTransferDirection.DOWNLOAD) {
      return '#FF2563EB';
    }
    if (direction === FnTransferDirection.SYNC) {
      return '#FF059669';
    }
    if (direction === FnTransferDirection.SCAN) {
      return '#FF4A8BFF';
    }
    if (direction === FnTransferDirection.NAS) {
      return '#FF7C3AED';
    }
    return '#FFD97706';
  }

  private statusColor(task: FnTransferTaskSnapshot): ResourceColor {
    if (task.status === FnTransferTaskStatus.FAILED) {
      return '#E11D48';
    }
    if (task.status === FnTransferTaskStatus.COMPLETED) {
      return '#059669';
    }
    return this.accent;
  }

  private progressText(task: FnTransferTaskSnapshot): string {
    if (task.total > 0) {
      return `${task.current}/${task.total} · ${FnTransferQueueStore.progressPercent(task)}%`;
    }
    return FnTransferQueueStore.statusLabel(task.status);
  }

  @Builder
  private taskRow(task: FnTransferTaskSnapshot) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text(FnTransferQueueStore.directionLabel(task.direction))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(this.directionColor(task.direction))
          .borderRadius(6)

        Column({ space: 4 }) {
          Text(task.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (task.detail.length > 0) {
            Text(task.detail)
              .fontSize(12)
              .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          } else if (task.message.length > 0 && task.status !== FnTransferTaskStatus.RUNNING) {
            Text(task.message)
              .fontSize(12)
              .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(FnTransferQueueStore.statusLabel(task.status))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.statusColor(task))
          .constraintSize({ minWidth: 44 })
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (task.status === FnTransferTaskStatus.RUNNING) {
        if (task.total > 0) {
          Row({ space: 10 }) {
            Progress({
              value: FnTransferQueueStore.progressPercent(task),
              total: 100,
              type: ProgressType.Linear
            })
              .layoutWeight(1)
              .height(4)
              .color(this.directionColor(task.direction))
              .backgroundColor($r('app.color.immersive_panel_border'))

            Text(this.progressText(task))
              .fontSize(11)
              .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
              .constraintSize({ minWidth: 72 })
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        } else {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(this.directionColor(task.direction))
            Text(task.detail.length > 0 ? task.detail : (task.message.length > 0 ? task.message : '处理中…'))
              .fontSize(12)
              .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
      } else if (task.message.length > 0) {
        Text(task.message)
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(fnResolvedCardFill(this.cardBg))
    .borderRadius(14)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
  }

  build() {
    Column({ space: 0 }) {
      HdsNavigation() {
        this.titleBarNavigationBody()
      }
      .width('100%')
      .height(FN_HDS_NAV_CHROME_HEIGHT_VP)
      .mode(NavigationMode.Stack)
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .titleBar(this.titleBarOptions())
      .hitTestBehavior(HitTestMode.Default)

      if (this.tasks.length === 0) {
        Column({ space: 8 }) {
          Text('暂无任务')
            .fontSize(14)
            .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          Text('扫描、上传、下载或同步会在这里显示进度')
            .fontSize(12)
            .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
            .lineHeight(18)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.tasks, (task: FnTransferTaskSnapshot) => {
            ListItem() {
              this.taskRow(task)
            }
          }, (task: FnTransferTaskSnapshot): string => `${task.id}_${task.updatedAt}`)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 4, bottom: 8 })
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
