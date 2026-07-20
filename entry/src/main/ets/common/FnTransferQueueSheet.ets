import { FnTransferDirection } from './FnTransferProgress';
import {
  FnTransferQueueStore,
  FnTransferTaskSnapshot,
  FnTransferTaskStatus
} from './FnTransferQueueStore';

/**
 * 传输队列半屏内容区。
 * 标题与关闭按钮由 bindSheet 的 title / showClose 官方能力提供。
 */
@Component
export struct FnTransferQueueSheet {
  @Prop tasks: FnTransferTaskSnapshot[] = [];

  private directionColor(direction: FnTransferDirection): ResourceColor {
    if (direction === FnTransferDirection.DOWNLOAD) {
      return '#FF2563EB';
    }
    if (direction === FnTransferDirection.SYNC) {
      return '#FF059669';
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
    return $r('app.color.brand_primary');
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
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (task.detail.length > 0) {
            Text(task.detail)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          } else if (task.message.length > 0 && task.status !== FnTransferTaskStatus.RUNNING) {
            Text(task.message)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
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
              .fontColor($r('app.color.text_secondary'))
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
            Text(task.message.length > 0 ? task.message : '处理中…')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
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
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(14)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
  }

  build() {
    Column({ space: 0 }) {
      if (this.tasks.length === 0) {
        Column({ space: 8 }) {
          Text('暂无传输任务')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
          Text('上传、下载或同步会在后台进行，可在此查看进度')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
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
        .padding({ left: 16, right: 16, bottom: 12 })
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }
}
