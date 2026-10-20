import { FnTransferDirection } from './FnTransferProgress';
import { fnResolvedCardFill, FN_RESOLVED_ACCENT_KEY, FN_RESOLVED_CARD_BG_KEY,
  fnResolvedTextPrimary,
  FN_RESOLVED_TEXT_PRIMARY_KEY,
  fnResolvedTextSecondary,
  FN_RESOLVED_TEXT_SECONDARY_KEY} from './FnThemeColors';
import {
  FnTransferQueueStore,
  FnTransferTaskSnapshot,
  FnTransferTaskStatus
} from './FnTransferQueueStore';

/**
 * 任务队列半屏内容区。
 * 标题与关闭按钮由 bindSheet 的 title / showClose 官方能力提供。
 */
@Component
export struct FnTransferQueueSheet {
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @StorageProp(FN_RESOLVED_TEXT_SECONDARY_KEY) private themeTextSecondary: string = '';
  @StorageProp(FN_RESOLVED_ACCENT_KEY) private accent: string = '#FF4A8BFF';
  @StorageProp(FN_RESOLVED_CARD_BG_KEY) private cardBg: string = '';
  @Prop tasks: FnTransferTaskSnapshot[] = [];

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

  private onClearCompleted(): void {
    if (!this.canClearCompleted()) {
      return;
    }
    FnTransferQueueStore.clearCompleted();
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

        Row() {
          Text('清除已完成')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.canClearCompleted() ? this.accent : fnResolvedTextSecondary(this.themeTextSecondary))
            .opacity(this.canClearCompleted() ? 1 : 0.45)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 12, bottom: 16 })
            .onClick((): void => {
              this.onClearCompleted();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
