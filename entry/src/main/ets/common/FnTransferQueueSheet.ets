import { FnTransferDirection } from './FnTransferProgress';
import {
  FnTransferQueueStore,
  FnTransferTaskSnapshot,
  FnTransferTaskStatus
} from './FnTransferQueueStore';

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

  @Builder
  private taskRow(task: FnTransferTaskSnapshot) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(FnTransferQueueStore.directionLabel(task.direction))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(this.directionColor(task.direction))
          .borderRadius(8)

        Text(task.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(FnTransferQueueStore.statusLabel(task.status))
          .fontSize(12)
          .fontColor(
            task.status === FnTransferTaskStatus.FAILED
              ? '#E11D48'
              : $r('app.color.text_secondary')
          )
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (task.detail.length > 0) {
        Text(task.detail)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (task.status === FnTransferTaskStatus.RUNNING && task.total > 0) {
        Progress({
          value: FnTransferQueueStore.progressPercent(task),
          total: 100,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(6)
          .color($r('app.color.brand_primary'))
          .backgroundColor($r('app.color.immersive_panel_border'))

        Text(`${task.current}/${task.total}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      } else if (task.message.length > 0) {
        Text(task.message)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  build() {
    Column({ space: 0 }) {
      Text('传输队列')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 12 })

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
        .padding({ left: 20, right: 20, top: 24, bottom: 24 })
        .alignItems(HorizontalAlign.Start)
      } else {
        List({ space: 0 }) {
          ForEach(this.tasks, (task: FnTransferTaskSnapshot) => {
            ListItem() {
              this.taskRow(task)
            }
            .padding({ left: 20, right: 20 })
          }, (task: FnTransferTaskSnapshot): string => `${task.id}_${task.updatedAt}`)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
  }
}
