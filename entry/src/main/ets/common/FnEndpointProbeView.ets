/**
 * 登录页与「我的」共用的路径探测结果展示。
 * 当前连接做成独立卡片，其他路径两行排布，避免地址和延迟挤在一行。
 * 同类条目用 List + ListItem（arkts-layout-development-create-list）；
 * 半模态内 List 配 nestedScroll PARENT_FIRST / SELF_FIRST（arkts-sheet-page）；
 * 滚动条用 BarState.Off（官方默认 Auto，半模态/系统相册同类面板关掉常驻条）。
 */
import { LoginEndpointProbeLine, LoginEndpointSelectionResult } from '../network/LoginEndpointSelector';

@Observed
export class FnEndpointProbeLineItem {
  key: string = '';
  label: string = '';
  address: string = '';
  latencyText: string = '';
  /** 该路径探测是否可达，用于延迟着色 */
  ok: boolean = false;
}

export function formatEndpointProbeLatency(ok: boolean, latencyMs: number): string {
  if (ok) {
    return latencyMs > 0 ? `${latencyMs}ms` : '可达';
  }
  return '不可用';
}

function probeUrlsEqual(a: string, b: string): boolean {
  const na = a.trim().replace(/\/$/, '');
  const nb = b.trim().replace(/\/$/, '');
  return na.length > 0 && na === nb;
}

export class FnEndpointProbeDisplay {
  hintText: string = '';
  selectedLabel: string = '';
  selectedAddress: string = '';
  selectedLatencyText: string = '';
  selectedOk: boolean = false;
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
      if (probeUrlsEqual(selected.probeLines[i].baseUrl, preferBaseUrl)) {
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
    display.selectedOk = header.ok;
  } else {
    display.selectedLabel = selected.selectedLabel;
    display.selectedAddress = selected.selectedAddress;
    display.selectedLatencyText = formatEndpointProbeLatency(selected.selectedOk, selected.selectedLatencyMs);
    display.selectedOk = selected.selectedOk;
  }
  const others: FnEndpointProbeLineItem[] = [];
  for (let k = 0; k < selected.probeLines.length; k++) {
    const line = selected.probeLines[k];
    if (header !== null && probeUrlsEqual(line.baseUrl, header.baseUrl) && line.label === header.label) {
      continue;
    }
    const item = new FnEndpointProbeLineItem();
    item.key = `${k}_${line.label}_${line.address}`;
    item.label = line.label;
    item.address = line.address;
    item.latencyText = formatEndpointProbeLatency(line.ok, line.latencyMs);
    item.ok = line.ok;
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
  @Prop selectedOk: boolean = true;
  @Prop otherItems: FnEndpointProbeLineItem[] = [];
  @Prop useCardStyle: boolean = false;
  /** 半模态内铺满并滚动；登录页卡片内按内容撑开 */
  @Prop fillSheet: boolean = false;
  /** 「我的」连通性页展示当前满载是否真正生效 */
  @Prop showBurstStatus: boolean = false;
  @Prop burstEnabled: boolean = false;
  @Prop burstForce: boolean = false;
  @Prop burstAuto: boolean = false;

  private hasProbeContent(): boolean {
    return this.probing || this.selectedLabel.length > 0;
  }

  private burstBadgeText(): Resource {
    if (!this.burstEnabled) {
      return $r('app.string.probe_burst_off');
    }
    if (this.burstForce) {
      return $r('app.string.probe_burst_on_force');
    }
    if (this.burstAuto) {
      return $r('app.string.probe_burst_on_auto');
    }
    return $r('app.string.probe_burst_off');
  }

  private latencyColor(ok: boolean): ResourceColor {
    return ok ? $r('app.color.brand_primary') : $r('app.color.text_secondary');
  }

  private sheetContentPadding(): Padding {
    if (this.useCardStyle) {
      return { left: 12, right: 12, top: 12, bottom: 12 };
    }
    if (this.fillSheet) {
      return { left: 0, right: 0, top: 8, bottom: 16 };
    }
    return { left: 16, right: 16, top: 8, bottom: 16 };
  }

  @Builder
  private burstBadge() {
    Text(this.burstBadgeText())
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.burstEnabled ? $r('app.color.lan_burst_accent') : $r('app.color.text_secondary'))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(this.burstEnabled ? $r('app.color.lan_burst_badge_bg') : $r('app.color.immersive_panel_border'))
      .borderRadius(8)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private probingBanner() {
    Row({ space: 10 }) {
      LoadingProgress()
        .width(18)
        .height(18)
        .color($r('app.color.brand_primary'))
      Text($r('app.string.login_probe_status'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 4, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private selectedCard() {
    Column({ space: 10 }) {
      Row() {
        Text(this.selectedTitle)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        if (this.showBurstStatus) {
          this.burstBadge()
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text(this.selectedLabel)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.selectedLatencyText.length > 0) {
          Text(this.selectedLatencyText)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.latencyColor(this.selectedOk))
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.selectedAddress.length > 0) {
        Text(this.selectedAddress)
          .fontSize(13)
          .lineHeight(18)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.hintText.length > 0) {
        Text(this.hintText)
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private otherRow(item: FnEndpointProbeLineItem) {
    Column({ space: 4 }) {
      Row() {
        Text(item.label)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(item.latencyText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.latencyColor(item.ok))
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (item.address.length > 0) {
        Text(item.address)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    if (!this.hasProbeContent()) {
      Column()
        .width('100%')
        .height(0)
    } else {
      Column({ space: 12 }) {
        if (this.probing) {
          this.probingBanner()
        }

        if (this.selectedLabel.length > 0) {
          this.selectedCard()
        }

        if (this.otherItems.length > 0) {
          Text($r('app.string.login_probe_others'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ top: 4, left: 2 })

          List() {
            ForEach(this.otherItems, (item: FnEndpointProbeLineItem) => {
              ListItem() {
                this.otherRow(item)
              }
            }, (item: FnEndpointProbeLineItem) => item.key)
          }
          .width('100%')
          .layoutWeight(this.fillSheet ? 1 : 0)
          .alignListItem(ListItemAlign.Start)
          .divider({
            strokeWidth: 0.5,
            color: $r('app.color.immersive_panel_border'),
            startMargin: 0,
            endMargin: 0
          })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .nestedScroll({
            scrollForward: NestedScrollMode.PARENT_FIRST,
            scrollBackward: NestedScrollMode.SELF_FIRST
          })
        }
      }
      .width('100%')
      .layoutWeight(this.fillSheet ? 1 : 0)
      .padding(this.sheetContentPadding())
      .borderRadius(this.useCardStyle ? $r('app.float.radius_medium') : 0)
      .backgroundColor(this.useCardStyle ? $r('app.color.card_background') : Color.Transparent)
      .alignItems(HorizontalAlign.Start)
    }
  }
}
