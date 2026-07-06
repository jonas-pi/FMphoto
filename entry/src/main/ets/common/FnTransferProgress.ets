/**
 * 通用传输进度（上传 / 下载 / 同步）。
 * 供批量上传、本地同步、后续批量下载等场景复用。
 */

/** 传输方向，便于后续下载场景扩展文案 */
export enum FnTransferDirection {
  UPLOAD = 'upload',
  DOWNLOAD = 'download',
  SYNC = 'sync'
}

/** 宿主需暴露的进度状态字段 */
export interface FnTransferProgressHost {
  transferActive: boolean;
  transferLabel: string;
  transferCurrent: number;
  transferTotal: number;
}

export function fnTransferDirectionLabel(direction: FnTransferDirection): string {
  if (direction === FnTransferDirection.DOWNLOAD) {
    return '下载中';
  }
  if (direction === FnTransferDirection.SYNC) {
    return '同步中';
  }
  return '上传中';
}

export function fnTransferBegin(
  host: FnTransferProgressHost,
  label: string,
  total: number
): void {
  host.transferActive = true;
  host.transferLabel = label;
  host.transferCurrent = 0;
  host.transferTotal = total;
}

export function fnTransferUpdate(host: FnTransferProgressHost, current: number): void {
  host.transferCurrent = current;
}

export function fnTransferEnd(host: FnTransferProgressHost): void {
  host.transferActive = false;
  host.transferLabel = '';
  host.transferCurrent = 0;
  host.transferTotal = 0;
}

export function fnTransferProgressText(host: FnTransferProgressHost): string {
  if (host.transferTotal > 0) {
    return `${host.transferLabel} ${host.transferCurrent}/${host.transferTotal}`;
  }
  if (host.transferLabel.length > 0) {
    return host.transferLabel;
  }
  return '传输中…';
}

export function fnTransferProgressValue(host: FnTransferProgressHost): number {
  if (host.transferTotal <= 0) {
    return 0;
  }
  return Math.max(0, Math.min(100, Math.round((host.transferCurrent / host.transferTotal) * 100)));
}

@Component
export struct FnTransferProgressMask {
  @Prop visible: boolean = false;
  @Prop label: string = '';
  @Prop current: number = 0;
  @Prop total: number = 0;
  @Prop topOffsetVp: number = 0;

  private progressText(): string {
    if (this.total > 0) {
      return `${this.label} ${this.current}/${this.total}`;
    }
    if (this.label.length > 0) {
      return this.label;
    }
    return '传输中…';
  }

  private progressValue(): number {
    if (this.total <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(100, Math.round((this.current / this.total) * 100)));
  }

  build() {
    if (!this.visible) {
      Blank()
    } else {
      Column({ space: 16 }) {
        LoadingProgress().width(48).height(48).color(Color.White)
        Text(this.progressText())
          .fontSize(14)
          .fontColor(Color.White)
        if (this.total > 0) {
          Progress({ value: this.progressValue(), total: 100, type: ProgressType.Linear })
            .width(220)
            .height(6)
            .color(Color.White)
            .backgroundColor('#66FFFFFF')
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: this.topOffsetVp })
      .backgroundColor($r('app.color.overlay_mask'))
      .hitTestBehavior(HitTestMode.Block)
    }
  }
}
