import { common } from '@kit.AbilityKit';
import { AppSession } from '../auth/AppSession';
import { SessionPreferences } from '../auth/SessionPreferences';
import {
  LOGIN_ENDPOINT_PREF_AUTO,
  LOGIN_ENDPOINT_PREF_LAN,
  LOGIN_ENDPOINT_PREF_PUBLIC,
  LOGIN_ENDPOINT_PREF_RELAY,
  selectAmongEndpointPool
} from '../network/LoginEndpointSelector';
import {
  completeStoredEndpointSwitchWith2fa,
  EndpointConnectionInfo,
  EndpointSwitchResult,
  endpointPoolFromStored,
  resolveEndpointConnectionInfo,
  switchStoredLoginEndpoint
} from '../network/LoginEndpointSwitch';
import {
  FN_ENDPOINT_SWITCH_MESSAGE,
  FN_ENDPOINT_SWITCH_VERSION
} from '../network/LoginEndpointAutoSwitch';
import { FnTransferQueueSheet } from '../common/FnTransferQueueSheet';
import {
  fnHdsFitContentSheetOptions,
  fnHdsMediumDetentSheetOptions
} from '../common/FnHdsOverlay';
import {
  buildEndpointProbeDisplay,
  FnEndpointProbeLineItem,
  FnEndpointProbeView
} from '../common/FnEndpointProbeView';
import {
  FN_TRANSFER_QUEUE_VERSION,
  FnTransferQueueStore,
  FnTransferTaskSnapshot
} from '../common/FnTransferQueueStore';
import { CertPolicy } from '../network/CertPolicy';
import { fnWebViewBaseUrl } from '../network/ServerUrl';
import {
  fnImmersiveBackgroundEffect,
  fnLiquidGlassGradient,
  FnHdsPillButton,
  FnPrimaryButton
} from '../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  fnCurrentSdkApiVersion,
  fnDeviceSupportsHdsImmersive,
  fnLoadImmersiveLightPreference,
  fnSaveImmersiveLightPreference,
  FN_HDS_MIN_SDK_API_VERSION,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../common/FnImmersiveSettings';
import {
  isGalleryLanBurstAutoEnabled,
  isGalleryLanBurstEnabled,
  isGalleryLanBurstForceEnabled,
  setGalleryLanBurstForceEnabled
} from '../album/GalleryPerfProfile';
import { invalidateAutoSync } from '../album/GalleryAutoSyncBadge';
import { GalleryAutoSyncLedger } from '../album/GalleryAutoSyncLedger';
import { GalleryTimelineRefreshStore } from '../album/GalleryTimelineRefreshStore';
import { stopGalleryVideoLanPrefetch } from '../album/GalleryVideoLanPrefetch';
import {
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_ROW_HEIGHT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from '../common/GalleryTopBarLayout';

const ME_IMMERSIVE_SWITCH_ROW_HEIGHT_VP: number = 72;
const ME_LAN_BURST_SWITCH_ROW_HEIGHT_VP: number = 80;
const ME_IMMERSIVE_SWITCH_ROW_RADIUS_VP: number = 22;
const ME_ACTION_GAP_VP: number = 18;
const ME_CONNECTION_ROW_RADIUS_VP: number = 22;
/** 系统 Toast 默认约 1500ms；切网提示未消失前不弹满载，避免盖住「当前内网连接」 */
const ENDPOINT_TOAST_DURATION_MS: number = 1600;
/** 满载 Toast 抬高，即使时间窗临界也不会和切网 Toast 叠在同一高度 */
const LAN_BURST_TOAST_BOTTOM_VP: string = '168vp';

@Component
export struct MePanel {
  @Prop topSafeInsetVp: number = 0;
  @Prop @Watch('onPageShowSignalChanged') pageShowSignal: number = 0;
  onEndpointSwitched: () => void = () => {};
  @StorageLink(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  @State private sdkApiVersion: number = 0;
  /** 用户手动满载；内网自动满载由独立状态展示，不会改写用户开关 */
  @State private lanBurstForceEnabled: boolean = false;
  @State private lanBurstAutoEnabled: boolean = false;
  @State private lanBurstEnabled: boolean = false;
  @State private endpointInfo: EndpointConnectionInfo = resolveEndpointConnectionInfo(null);
  @State private endpointSwitching: boolean = false;
  @State private probeSheetVisible: boolean = false;
  @State private probeSheetLoading: boolean = false;
  @State private probeHint: string = '';
  @State private probeSelectedLabel: string = '';
  @State private probeSelectedAddress: string = '';
  @State private probeSelectedLatencyText: string = '';
  @State private probeSelectedOk: boolean = false;
  @State private probeOtherItems: FnEndpointProbeLineItem[] = [];
  @State private twofaSheetVisible: boolean = false;
  @State private twofaLoading: boolean = false;
  @State private twofaCode: string = '';
  @State private twofaError: string = '';
  @State private twofaTrustDevice: boolean = true;
  @State private pendingTwofaAccessToken: string = '';
  @State private pendingTwofaTargetUrl: string = '';
  @State private pendingTwofaDeviceId: string = '';
  @State private transferQueueVisible: boolean = false;
  @State private transferQueueTasks: FnTransferTaskSnapshot[] = [];
  @StorageProp(FN_TRANSFER_QUEUE_VERSION) @Watch('onTransferQueueVersionChanged') private transferQueueVersion: number = 0;
  @StorageProp(FN_ENDPOINT_SWITCH_VERSION) @Watch('onEndpointSwitchVersionChanged') private endpointSwitchVersion: number = 0;
  private lastImmersiveToggleAt: number = 0;
  private lastLanBurstToggleAt: number = 0;
  private lastEndpointToastAt: number = 0;
  private burstToastTimer: number = -1;
  private probeSeq: number = 0;
  private twofaSwitchCompleted: boolean = false;

  private refreshTransferQueueTasks(): void {
    this.transferQueueTasks = FnTransferQueueStore.getTasks();
  }

  private onTransferQueueVersionChanged(): void {
    this.refreshTransferQueueTasks();
  }

  private onEndpointSwitchVersionChanged(): void {
    this.refreshEndpointInfo();
    const msg = AppStorage.get<string>(FN_ENDPOINT_SWITCH_MESSAGE);
    if (msg !== undefined && msg.length > 0) {
      this.showEndpointToast(msg);
    }
  }

  private refreshEndpointInfo(): void {
    this.endpointInfo = resolveEndpointConnectionInfo(AppSession.getStored());
    this.refreshLanBurstSwitch();
  }

  /** 切网后自动档会变，开关文案要跟着刷新 */
  private refreshLanBurstSwitch(): void {
    this.lanBurstForceEnabled = isGalleryLanBurstForceEnabled();
    this.lanBurstAutoEnabled = isGalleryLanBurstAutoEnabled();
    this.lanBurstEnabled = isGalleryLanBurstEnabled();
  }

  private onPageShowSignalChanged(): void {
    this.refreshEndpointInfo();
    this.refreshTransferQueueTasks();
  }

  private endpointKindBadgeColor(kind: string): ResourceColor {
    if (kind === LOGIN_ENDPOINT_PREF_LAN) {
      return '#FF059669';
    }
    if (kind === LOGIN_ENDPOINT_PREF_PUBLIC) {
      return '#FF2563EB';
    }
    if (kind === LOGIN_ENDPOINT_PREF_RELAY) {
      return '#FFD97706';
    }
    return $r('app.color.text_secondary');
  }

  private showEndpointToast(message: string): void {
    if (message.length === 0) {
      return;
    }
    this.lastEndpointToastAt = Date.now();
    this.getUIContext().getPromptAction().showToast({ message, duration: 1500 });
  }

  /** 取消尚未弹出的满载提示，避免离开「我的」后仍弹出 */
  private cancelLanBurstToast(): void {
    if (this.burstToastTimer >= 0) {
      clearTimeout(this.burstToastTimer);
      this.burstToastTimer = -1;
    }
  }

  /**
   * 手动打开满载时提示；内网自动满载不重复弹提示。
   * 若切网 Toast 还在，等它结束后再显示，并抬高位置避免重叠。
   */
  private showLanBurstToast(): void {
    this.cancelLanBurstToast();
    const elapsed = Date.now() - this.lastEndpointToastAt;
    const waitMs = (this.lastEndpointToastAt > 0 && elapsed < ENDPOINT_TOAST_DURATION_MS) ?
      (ENDPOINT_TOAST_DURATION_MS - elapsed) : 0;
    const fire = (): void => {
      this.burstToastTimer = -1;
      try {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.lan_burst_toast_on'),
          duration: 2000,
          bottom: LAN_BURST_TOAST_BOTTOM_VP,
          backgroundColor: $r('app.color.lan_burst_accent'),
          textColor: $r('app.color.lan_burst_toast_text'),
          backgroundBlurStyle: BlurStyle.NONE
        });
      } catch (_e) {
      }
    };
    if (waitMs > 0) {
      this.burstToastTimer = setTimeout((): void => {
        fire();
      }, waitMs);
      return;
    }
    fire();
  }

  private clearProbeDisplay(): void {
    this.probeHint = '';
    this.probeSelectedLabel = '';
    this.probeSelectedAddress = '';
    this.probeSelectedLatencyText = '';
    this.probeSelectedOk = false;
    this.probeOtherItems = [];
  }

  private openEndpointProbeSheet(): void {
    if (this.endpointInfo.addressText.length === 0) {
      return;
    }
    this.probeSheetVisible = true;
    this.refreshLanBurstSwitch();
    void this.reloadEndpointProbe();
  }

  private async reloadEndpointProbe(): Promise<void> {
    const seq = this.probeSeq + 1;
    this.probeSeq = seq;
    this.probeSheetLoading = true;
    this.clearProbeDisplay();
    const stored = AppSession.getStored();
    if (stored === null) {
      this.probeSheetLoading = false;
      return;
    }
    try {
      // 只探测会话里已有的通道：填了 FN ID 会含云端解析结果，未填则只有手填地址
      const selected = await selectAmongEndpointPool(
        endpointPoolFromStored(stored),
        LOGIN_ENDPOINT_PREF_AUTO
      );
      if (seq !== this.probeSeq) {
        return;
      }
      const display = buildEndpointProbeDisplay(selected, stored.baseUrl, selected.summary);
      this.probeHint = display.hintText;
      this.probeSelectedLabel = display.selectedLabel;
      this.probeSelectedAddress = display.selectedAddress;
      this.probeSelectedLatencyText = display.selectedLatencyText;
      this.probeSelectedOk = display.selectedOk;
      this.probeOtherItems = display.otherItems;
    } catch (_e) {
      if (seq === this.probeSeq) {
        this.clearProbeDisplay();
      }
    } finally {
      if (seq === this.probeSeq) {
        this.probeSheetLoading = false;
      }
    }
  }

  private async switchEndpoint(targetKind: string): Promise<void> {
    if (this.endpointSwitching || !this.endpointInfo.canSwitch) {
      return;
    }
    if (this.endpointInfo.kind === targetKind) {
      return;
    }
    if (targetKind === LOGIN_ENDPOINT_PREF_PUBLIC && !this.endpointInfo.hasPublic) {
      return;
    }
    if (targetKind === LOGIN_ENDPOINT_PREF_LAN && !this.endpointInfo.hasLan) {
      return;
    }
    if (targetKind === LOGIN_ENDPOINT_PREF_RELAY && !this.endpointInfo.hasRelay) {
      return;
    }
    this.endpointSwitching = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let res = await switchStoredLoginEndpoint(ctx, targetKind);
    if (res.certificateError === true && res.targetUrl !== undefined && res.targetUrl.length > 0) {
      try {
        const dlg = await this.getUIContext().getPromptAction().showDialog({
          title: '证书不可信',
          message: '切换目标地址证书未信任。是否信任并继续？',
          buttons: [
            { text: '取消', color: '#99000000' },
            { text: '信任并继续', color: '#FF2563EB' }
          ]
        });
        if (dlg.index === 1) {
          CertPolicy.addTrusted(res.targetUrl);
          CertPolicy.addTrusted(fnWebViewBaseUrl(res.targetUrl));
          res = await switchStoredLoginEndpoint(ctx, targetKind);
        } else {
          res = { ok: false, message: '已取消信任证书' };
        }
      } catch (_e) {
        res = { ok: false, message: '已取消信任证书' };
      }
    }
    if (res.requires2faSetup === true) {
      this.endpointSwitching = false;
      this.showEndpointToast(res.message);
      return;
    }
    if (res.requires2fa === true) {
      this.openSwitchTwofaSheet(res);
      return;
    }
    this.endpointSwitching = false;
    this.refreshEndpointInfo();
    this.showEndpointToast(res.message);
    if (res.ok) {
      this.onEndpointSwitched();
    }
  }

  private openSwitchTwofaSheet(res: EndpointSwitchResult): void {
    this.pendingTwofaAccessToken = res.accessToken !== undefined ? res.accessToken : '';
    this.pendingTwofaTargetUrl = res.targetUrl !== undefined ? res.targetUrl : '';
    this.pendingTwofaDeviceId = res.deviceId !== undefined ? res.deviceId : '';
    this.twofaCode = '';
    this.twofaError = '';
    this.twofaTrustDevice = true;
    this.twofaLoading = false;
    this.twofaSwitchCompleted = false;
    this.twofaSheetVisible = true;
  }

  private clearSwitchTwofaState(): void {
    this.twofaSheetVisible = false;
    this.twofaLoading = false;
    this.twofaCode = '';
    this.twofaError = '';
    this.pendingTwofaAccessToken = '';
    this.pendingTwofaTargetUrl = '';
    this.pendingTwofaDeviceId = '';
  }

  private onSwitchTwofaSheetDisappear(): void {
    if (this.twofaSwitchCompleted) {
      this.twofaSwitchCompleted = false;
      return;
    }
    this.endpointSwitching = false;
    this.clearSwitchTwofaState();
  }

  private async onSwitchTwofaVerifyClick(): Promise<void> {
    const code = this.twofaCode.trim();
    if (!/^\d{6}$/.test(code)) {
      this.twofaError = '请输入身份验证器中的 6 位动态验证码';
      return;
    }
    if (this.pendingTwofaAccessToken.length === 0 || this.pendingTwofaTargetUrl.length === 0 ||
      this.pendingTwofaDeviceId.length === 0) {
      this.twofaError = '验证会话已失效，请重新切换';
      return;
    }
    this.twofaLoading = true;
    this.twofaError = '';
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let res = await completeStoredEndpointSwitchWith2fa(
      ctx,
      this.pendingTwofaTargetUrl,
      this.pendingTwofaAccessToken,
      code,
      this.twofaTrustDevice,
      this.pendingTwofaDeviceId
    );
    if (res.certificateError === true && res.targetUrl !== undefined && res.targetUrl.length > 0) {
      try {
        const dlg = await this.getUIContext().getPromptAction().showDialog({
          title: '证书不可信',
          message: '切换目标地址证书未信任。是否信任并继续？',
          buttons: [
            { text: '取消', color: '#99000000' },
            { text: '信任并继续', color: '#FF2563EB' }
          ]
        });
        if (dlg.index === 1) {
          CertPolicy.addTrusted(res.targetUrl);
          CertPolicy.addTrusted(fnWebViewBaseUrl(res.targetUrl));
          res = await completeStoredEndpointSwitchWith2fa(
            ctx,
            this.pendingTwofaTargetUrl,
            this.pendingTwofaAccessToken,
            code,
            this.twofaTrustDevice,
            this.pendingTwofaDeviceId
          );
        } else {
          res = { ok: false, message: '已取消信任证书' };
        }
      } catch (_e) {
        res = { ok: false, message: '已取消信任证书' };
      }
    }
    this.twofaLoading = false;
    if (!res.ok) {
      this.twofaError = res.message;
      return;
    }
    this.twofaSwitchCompleted = true;
    this.endpointSwitching = false;
    this.clearSwitchTwofaState();
    this.refreshEndpointInfo();
    this.showEndpointToast(res.message);
    this.onEndpointSwitched();
  }

  private immersiveSupportText(): string {
    if (this.sdkApiVersion <= 0) {
      return `HDS 需要 API${FN_HDS_MIN_SDK_API_VERSION}+`;
    }
    if (fnDeviceSupportsHdsImmersive()) {
      return `当前 API${this.sdkApiVersion}，可实时切换 HDS`;
    }
    return `当前 API${this.sdkApiVersion}，HDS 需要 API${FN_HDS_MIN_SDK_API_VERSION}+`;
  }

  private toggleImmersiveLight(enabled: boolean): void {
    this.immersiveLightEnabled = enabled;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void fnSaveImmersiveLightPreference(ctx, enabled);
  }

  private shouldUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private triggerImmersiveLightToggle(): void {
    const now = Date.now();
    if (now - this.lastImmersiveToggleAt < 120) {
      return;
    }
    this.lastImmersiveToggleAt = now;
    this.toggleImmersiveLight(!this.immersiveLightEnabled);
  }

  private lanBurstSupportText(): string {
    if (this.lanBurstForceEnabled) {
      return '本次已拉满网络利用率，重启应用后关闭';
    }
    if (this.lanBurstAutoEnabled) {
      return '当前内网已自动满载；切到公网/中继后恢复受控利用率';
    }
    return '当前为受控利用率；可手动开启满载，所有通道均使用自定义拉取';
  }

  private toggleLanBurstForce(enabled: boolean): void {
    setGalleryLanBurstForceEnabled(enabled);
    this.refreshLanBurstSwitch();
    if (enabled) {
      this.showLanBurstToast();
    } else {
      this.cancelLanBurstToast();
    }
  }

  private triggerLanBurstForceToggle(): void {
    const now = Date.now();
    if (now - this.lastLanBurstToggleAt < 120) {
      return;
    }
    this.lastLanBurstToggleAt = now;
    this.toggleLanBurstForce(!this.lanBurstForceEnabled);
  }

  aboutToAppear(): void {
    this.sdkApiVersion = fnCurrentSdkApiVersion();
    this.refreshEndpointInfo();
    FnTransferQueueStore.ensureStorage();
    this.refreshTransferQueueTasks();
    this.refreshLanBurstSwitch();
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void fnLoadImmersiveLightPreference(ctx).then((enabled: boolean): void => {
      this.immersiveLightEnabled = enabled;
    });
  }

  aboutToDisappear(): void {
    this.cancelLanBurstToast();
  }

  @Builder
  private endpointProbeSheetBuilder() {
    Column() {
      FnEndpointProbeView({
        probing: this.probeSheetLoading,
        hintText: this.probeHint,
        selectedTitle: $r('app.string.login_probe_current'),
        selectedLabel: this.probeSelectedLabel,
        selectedAddress: this.probeSelectedAddress,
        selectedLatencyText: this.probeSelectedLatencyText,
        selectedOk: this.probeSelectedOk,
        otherItems: this.probeOtherItems,
        useCardStyle: false,
        fillSheet: true,
        showBurstStatus: true,
        burstEnabled: this.lanBurstEnabled,
        burstForce: this.lanBurstForceEnabled,
        burstAuto: this.lanBurstAutoEnabled
      })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: $r('sys.float.ohos_id_max_padding_start'),
      right: $r('sys.float.ohos_id_max_padding_end')
    })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private endpointTwofaSheetBuilder() {
    Column({ space: 12 }) {
      Text($r('app.string.twofa_step_hint'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ placeholder: $r('app.string.hint_otp'), text: this.twofaCode })
        .type(InputType.Number)
        .maxLength(6)
        .enableAutoFill(false)
        .enableKeyboardOnFocus(false)
        .onChange((v: string) => {
          this.twofaCode = v.replace(/[^\d]/g, '').substring(0, 6);
        })
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius($r('app.float.radius_medium'))
        .padding({ left: 12, right: 12 })
        .enabled(!this.twofaLoading)

      Row() {
        Text($r('app.string.trust_device'))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.twofaTrustDevice })
          .selectedColor($r('app.color.brand_primary'))
          .enabled(!this.twofaLoading)
          .onChange((on: boolean) => {
            this.twofaTrustDevice = on;
          })
      }
      .width('100%')

      if (this.twofaError.length > 0) {
        Text(this.twofaError)
          .fontColor(Color.Red)
          .fontSize(14)
          .width('100%')
      }

      FnPrimaryButton({
        text: this.twofaLoading ? $r('app.string.verifying_2fa') : $r('app.string.verify_2fa_switch'),
        action: (): void => {
          void this.onSwitchTwofaVerifyClick();
        }
      })
        .width('100%')
        .enabled(!this.twofaLoading)
    }
    .width('100%')
    .padding({ left: 20, right: 20, bottom: 24, top: 8 })
    .backgroundColor(Color.Transparent)
  }

  @Builder
  private transferQueueSheetBuilder() {
    FnTransferQueueSheet({ tasks: this.transferQueueTasks })
  }

  @Builder
  private configSyncEntryRow() {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text($r('app.string.config_sync_entry_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.config_sync_entry_subtitle'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.qrcode'))
        .fontSize(18)
        .fontColor([$r('app.color.text_secondary')])

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.card_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(fnLiquidGlassGradient())
    .borderRadius(ME_CONNECTION_ROW_RADIUS_VP)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
    .clip(true)
    .onClick((): void => {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/ConfigSyncPage' }).catch((): void => {});
    })
  }

  @Builder
  private transferQueueEntryRow() {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text('\u4f20\u8f93\u961f\u5217')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(
          FnTransferQueueStore.activeCount() > 0
            ? `${FnTransferQueueStore.activeCount()} \u4e2a\u4efb\u52a1\u8fdb\u884c\u4e2d`
            : '\u67e5\u770b\u4e0a\u4f20\u3001\u4e0b\u8f7d\u4e0e\u540c\u6b65\u8fdb\u5ea6'
        )
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)

      if (FnTransferQueueStore.activeCount() > 0) {
        Text(`${FnTransferQueueStore.activeCount()}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(10)
      }

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.card_background'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(fnLiquidGlassGradient())
    .borderRadius(ME_CONNECTION_ROW_RADIUS_VP)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
    .clip(true)
    .onClick((): void => {
      this.refreshTransferQueueTasks();
      this.transferQueueVisible = true;
    })
  }

  @Builder
  private endpointChannelTab(label: string, kind: string, available: boolean) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(15)
        .fontWeight(this.endpointInfo.kind === kind ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.endpointInfo.kind === kind ? $r('app.color.brand_primary') :
          (available ? $r('app.color.text_primary') : $r('app.color.text_secondary')))
        .opacity(available ? 1 : 0.35)

      Row()
        .width(22)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.endpointInfo.kind === kind ? $r('app.color.brand_primary') : Color.Transparent)
    }
    .layoutWeight(1)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .enabled(available && !this.endpointSwitching && this.endpointInfo.kind !== kind)
    .opacity(this.endpointSwitching ? 0.55 : 1)
    .onClick((): void => {
      if (!available) {
        return;
      }
      void this.switchEndpoint(kind);
    })
  }

  @Builder
  private connectionStatusRow() {
    // 两个 bindSheet 不能绑在同一节点；clip 也不能绑在探测半模态宿主上，否则内容被裁切。
    Column() {
      Column() {
        Column({ space: 14 }) {
          Row() {
            Text('NAS 连接')
              .fontSize(13)
              .fontWeight(FontWeight.Regular)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([$r('app.color.text_secondary')])
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            this.openEndpointProbeSheet();
          })

          Text(this.endpointSwitching ? '正在切换…' : this.endpointInfo.addressText)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .onClick((): void => {
              this.openEndpointProbeSheet();
            })

          if (this.endpointInfo.canSwitch) {
            Row() {
              if (this.endpointInfo.hasPublic) {
                this.endpointChannelTab('公网', LOGIN_ENDPOINT_PREF_PUBLIC, true)
              }
              if (this.endpointInfo.hasLan) {
                this.endpointChannelTab('内网', LOGIN_ENDPOINT_PREF_LAN, true)
              }
              if (this.endpointInfo.hasRelay) {
                this.endpointChannelTab('中继', LOGIN_ENDPOINT_PREF_RELAY, true)
              }
            }
            .width('100%')
            .borderRadius(12)
            .borderWidth(1)
            .borderColor($r('app.color.immersive_panel_border'))
          } else if (this.endpointInfo.label.length > 0) {
            Text(this.endpointInfo.label)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.endpointKindBadgeColor(this.endpointInfo.kind))
              .borderRadius(8)
              .alignSelf(ItemAlign.Start)
              .onClick((): void => {
                this.openEndpointProbeSheet();
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .backgroundColor($r('app.color.card_background'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .linearGradient(fnLiquidGlassGradient())
        .borderRadius(ME_CONNECTION_ROW_RADIUS_VP)
        .borderWidth(1)
        .borderColor($r('app.color.immersive_panel_border'))
        .clip(true)
      }
      .width('100%')
      .bindSheet(this.twofaSheetVisible, this.endpointTwofaSheetBuilder, fnHdsFitContentSheetOptions(
        $r('app.string.twofa_switch_title'),
        (): void => {
          this.onSwitchTwofaSheetDisappear();
        }
      ))
    }
    .width('100%')
    .bindSheet(this.probeSheetVisible, this.endpointProbeSheetBuilder, fnHdsMediumDetentSheetOptions(
      $r('app.string.nas_endpoint_probe_title'),
      (): void => {
        this.probeSheetVisible = false;
        this.probeSeq = this.probeSeq + 1;
        this.probeSheetLoading = false;
      }
    ))
  }

  @Builder
  private immersiveSwitchContent() {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text('\u6c89\u6d78\u5149\u611f')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.immersiveSupportText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.immersiveLightEnabled })
        .selectedColor($r('app.color.brand_primary'))
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 16, top: 0, bottom: 0 })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private immersiveSwitchRow() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.card_background'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .linearGradient(fnLiquidGlassGradient(this.shouldUseHds()))
        .borderRadius(ME_IMMERSIVE_SWITCH_ROW_RADIUS_VP)
        .borderWidth(1)
        .borderColor($r('app.color.immersive_panel_border'))
        .clip(true)

      this.immersiveSwitchContent()
    }
    .width('100%')
    .height(ME_IMMERSIVE_SWITCH_ROW_HEIGHT_VP)
    .onClick((): void => {
      this.triggerImmersiveLightToggle();
    })
  }

  @Builder
  private lanBurstSwitchContent() {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text('满载模式')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.lanBurstSupportText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.lanBurstForceEnabled })
        .selectedColor($r('app.color.lan_burst_accent'))
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 16, top: 0, bottom: 0 })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private lanBurstSwitchRow() {
    Stack() {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.card_background'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .linearGradient(fnLiquidGlassGradient(this.shouldUseHds()))
        .borderRadius(ME_IMMERSIVE_SWITCH_ROW_RADIUS_VP)
        .borderWidth(1)
        .borderColor($r('app.color.immersive_panel_border'))
        .clip(true)

      this.lanBurstSwitchContent()
    }
    .width('100%')
    .height(ME_LAN_BURST_SWITCH_ROW_HEIGHT_VP)
    .onClick((): void => {
      this.triggerLanBurstForceToggle();
    })
  }

  build() {
    Column() {
      Row() {
        Row()
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)

        Text('\u6211\u7684')
          .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(2)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row()
          .layoutWeight(1)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: GALLERY_TOP_BAR_PAD_LEFT_VP,
        right: GALLERY_TOP_BAR_PAD_RIGHT_VP,
        top: GALLERY_TOP_BAR_PAD_TOP_VP + this.topSafeInsetVp,
        bottom: GALLERY_TOP_BAR_PAD_BOTTOM_VP
      })

      Column({ space: 0 }) {
        Column({ space: 10 }) {
          Text('FNOS \u4e2a\u4eba\u4e2d\u5fc3')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          Text('\u9996\u9875\u5df2\u7ecf\u5207\u6362\u4e3a\u7eaf\u539f\u751f\u56fe\u5e93\u58f3\u4f53\uff0c\u8fd9\u91cc\u4fdd\u7559\u8d26\u53f7\u4e0e\u7cfb\u7edf\u5165\u53e3\u3002')
            .fontSize(13)
            .lineHeight(20)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding(18)
        .backgroundColor($r('app.color.immersive_panel_bg'))
        .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .backgroundEffect(fnImmersiveBackgroundEffect())
        .linearGradient(fnLiquidGlassGradient())
        .borderRadius(24)
        .borderWidth(1)
        .borderColor($r('app.color.immersive_panel_border'))
        .shadow({ radius: 24, color: '#14001A33', offsetX: 0, offsetY: 10 })
        .clip(true)
        .visibility(Visibility.None)

        Column({ space: 12 }) {
          Text('\u5f53\u524d\u72b6\u6001')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('1. \u9996\u9875 Web \u5df2\u5b8c\u5168\u79fb\u9664\u3002')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text('2. \u5e95\u90e8\u4e3b\u5bfc\u822a\u7edf\u4e00\u4e3a\u7167\u7247\u3001\u76f8\u518c\u3001\u6211\u7684\u3002')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text('3. \u56fe\u5e93\u4e3b\u9875\u4f7f\u7528\u60ac\u6d6e\u6807\u9898\u680f\u4e0e\u60ac\u6d6e\u5e95\u90e8\u5bfc\u822a\u3002')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .padding(18)
        .backgroundColor($r('app.color.immersive_panel_strong_bg'))
        .borderRadius(24)
        .borderWidth(1)
        .borderColor($r('app.color.immersive_panel_border'))
        .visibility(Visibility.None)

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        this.connectionStatusRow()

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        this.lanBurstSwitchRow()

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        this.transferQueueEntryRow()

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        this.configSyncEntryRow()

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        this.immersiveSwitchRow()

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        FnHdsPillButton({
          text: $r('app.string.logout'),
          widthValue: '100%',
          heightValue: 40,
          fontSizeValue: 16,
          fontColorValue: '#E11D48',
          action: (): void => {
            const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
            void (async (): Promise<void> => {
              const snap = AppSession.getStored();
              const existing = await SessionPreferences.loadLoginFormDefaults(ctx);
              const fromSnap = snap !== null ? SessionPreferences.loginFormFromStored(snap) : existing;
              await SessionPreferences.saveLoginFormDefaults(ctx, {
                fnIdInput: fromSnap.fnIdInput.length > 0 ? fromSnap.fnIdInput : existing.fnIdInput,
                domainInput: fromSnap.domainInput.length > 0 ? fromSnap.domainInput : existing.domainInput,
                lanInput: fromSnap.lanInput.length > 0 ? fromSnap.lanInput : existing.lanInput,
                publicIpInput: fromSnap.publicIpInput.length > 0 ? fromSnap.publicIpInput : existing.publicIpInput,
                publicIpv6Input: fromSnap.publicIpv6Input.length > 0 ? fromSnap.publicIpv6Input : existing.publicIpv6Input,
                loginEndpointPreference: fromSnap.loginEndpointPreference.length > 0 ?
                  fromSnap.loginEndpointPreference : existing.loginEndpointPreference,
                username: fromSnap.username.length > 0 ? fromSnap.username : existing.username,
                password: existing.rememberPassword ?
                  (AppSession.getLoginPassword().length > 0 ? AppSession.getLoginPassword() : existing.password) : '',
                useHttps: fromSnap.username.length > 0 || fromSnap.fnIdInput.length > 0 ||
                  fromSnap.lanInput.length > 0 || fromSnap.domainInput.length > 0 ||
                  fromSnap.publicIpInput.length > 0 || fromSnap.publicIpv6Input.length > 0 ?
                  fromSnap.useHttps : existing.useHttps,
                rememberPassword: existing.rememberPassword,
                savedUsers: existing.savedUsers
              });
              await SessionPreferences.clearSession(ctx);
              invalidateAutoSync();
              await GalleryAutoSyncLedger.clear(ctx);
              GalleryTimelineRefreshStore.bump();
              stopGalleryVideoLanPrefetch();
              AppSession.clear();
              this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch(() => {
              });
            })();
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      .padding({ left: 24, right: 24, top: 8, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .bindSheet(this.transferQueueVisible, this.transferQueueSheetBuilder, fnHdsMediumDetentSheetOptions(
      '传输队列',
      (): void => {
        this.transferQueueVisible = false;
      }
    ))
  }
}
