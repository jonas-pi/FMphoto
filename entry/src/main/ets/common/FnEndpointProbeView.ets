/**
 * 登录页与「我的」共用的路径探测结果展示。
 */
import { LoginEndpointProbeLine, LoginEndpointSelectionResult } from '../network/LoginEndpointSelector';

@Observed
export class FnEndpointProbeLineItem {
  key: string = '';
  label: string = '';
  address: string = '';
  latencyText: string = '';
}

export function formatEndpointProbeLatency(ok: boolean, latencyMs: number): string {
  if (ok) {
    return latencyMs > 0 ? `${latencyMs}ms` : '可达';
  }
  return '不可用';
}

function urlsMatch(a: string, b: string): boolean {
  const na = a.trim().replace(/\/$/, '');
  const nb = b.trim().replace(/\/$/, '');
  return na.length > 0 && na === nb;
}

export class FnEndpointProbeDisplay {
  hintText: string = '';
  selectedLabel: string = '';
  selectedAddress: string = '';
  selectedLatencyText: string = '';
  otherItems: FnEndpointProbeLineItem[] = [];
}

/**
 * 将选路结果转为展示数据；preferBaseUrl 非空时优先把该地址标为当前连接。
 */
export function buildEndpointProbeDisplay(
  selected: LoginEndpointSelectionResult,
  preferBaseUrl: string,
  hintText: string
): FnEndpointProbeDisplay {
  const display = new FnEndpointProbeDisplay();
  display.hintText = hintText;
  let header: LoginEndpointProbeLine | null = null;
  if (preferBaseUrl.length > 0) {
    for (let i = 0; i < selected.probeLines.length; i++) {
      if (urlsMatch(selected.probeLines[i].baseUrl, preferBaseUrl)) {
        header = selected.probeLines[i];
        break;
      }
    }
  }
  if (header === null) {
    for (let j = 0; j < selected.probeLines.length; j++) {
      if (selected.probeLines[j].selected) {
        header = selected.probeLines[j];
        break;
      }
    }
  }
  if (header !== null) {
    display.selectedLabel = header.label;
    display.selectedAddress = header.address;
    display.selectedLatencyText = formatEndpointProbeLatency(header.ok, header.latencyMs);
  } else {
    display.selectedLabel = selected.selectedLabel;
    display.selectedAddress = selected.selectedAddress;
    display.selectedLatencyText = formatEndpointProbeLatency(selected.selectedOk, selected.selectedLatencyMs);
  }
  const others: FnEndpointProbeLineItem[] = [];
  for (let k = 0; k < selected.probeLines.length; k++) {
    const line = selected.probeLines[k];
    if (header !== null && urlsMatch(line.baseUrl, header.baseUrl) && line.label === header.label) {
      continue;
    }
    const item = new FnEndpointProbeLineItem();
    item.key = `${k}_${line.label}_${line.address}`;
    item.label = line.label;
    item.address = line.address;
    item.latencyText = formatEndpointProbeLatency(line.ok, line.latencyMs);
    others.push(item);
  }
  display.otherItems = others;
  return display;
}

@Component
export struct FnEndpointProbeView {
  @Prop probing: boolean = false;
  @Prop hintText: string = '';
  @Prop selectedTitle: Resource = $r('app.string.login_probe_selected');
  @Prop selectedLabel: string = '';
  @Prop selectedAddress: string = '';
  @Prop selectedLatencyText: string = '';
  @Prop otherItems: FnEndpointProbeLineItem[] = [];
  @Prop useCardStyle: boolean = false;

  build() {
    Column({ space: 8 }) {
      if (this.probing) {
        Text($r('app.string.login_probe_status'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }

      if (this.selectedLabel.length > 0) {
        if (this.hintText.length > 0) {
          Text(this.hintText)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }

        Row() {
          Text(this.selectedTitle)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(this.selectedLabel)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand_primary'))
            .margin({ left: 6 })
          Blank()
          if (this.selectedLatencyText.length > 0) {
            Text(this.selectedLatencyText)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.brand_primary'))
          }
        }
        .width('100%')

        if (this.selectedAddress.length > 0) {
          Text(this.selectedAddress)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }

        ForEach(this.otherItems, (item: FnEndpointProbeLineItem) => {
          Row() {
            Text(item.label)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .constraintSize({ minWidth: 80 })
            Text(item.address)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: 8, right: 8 })
            Text(item.latencyText)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
        }, (item: FnEndpointProbeLineItem) => item.key)
      } else if (!this.probing) {
        Text('暂无探测结果')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding(this.useCardStyle ? 12 : 20)
    .borderRadius(this.useCardStyle ? $r('app.float.radius_medium') : 0)
    .backgroundColor(this.useCardStyle ? $r('app.color.card_background') : Color.Transparent)
    .alignItems(HorizontalAlign.Start)
  }
}
