import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { AppSession } from '../auth/AppSession';
import {
  openCollectedInfoListPage,
  openPrivacyPolicyPage,
  openThirdPartyShareListPage
} from '../auth/PrivacyConsentNav';
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
  fnHdsLargeSheetOptions,
  fnHdsMediumDetentSheetOptions
} from '../common/FnHdsOverlay';
import { ConfigSyncSheet } from './ConfigSyncPage';
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
import { fnDiagShare } from '../common/FnDiagLog';
import {
  APP_GALLERY_RATE_ALREADY,
  APP_GALLERY_RATE_FAILED,
  APP_GALLERY_RATE_NEED_ID,
  fnAppGalleryCommentAvailable,
  fnIsAppGalleryCommentDone,
  fnShowAppGalleryComment
} from '../common/AppGalleryRate';
import { CertPolicy } from '../network/CertPolicy';
import { fnWebViewBaseUrl } from '../network/ServerUrl';
import {
  HdsNavigation,
  HdsNavigationTitleBarOptions,
  HdsNavigationTitleMode
} from '@kit.UIDesignKit';
import {
  FN_HDS_NAV_CHROME_HEIGHT_VP,
  fnHdsMiniTitleBarOptions,
  fnImmersiveBackgroundEffect,
  fnLiquidGlassGradient,
  fnSoftCardGlassGradient,
  FnHdsPillButton,
  FnPrimaryButton
} from '../common/FnUiCommon';
import { fnCanUseHdsImmersive } from '../common/FnImmersiveSettings';
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
  fnApplyThemeWindowBackground,
  fnNormalizeThemeHex,
  fnRefreshSystemColorPreview,
  fnSaveCustomColor,
  fnSaveThemeScheme,
  fnThemeOnColor,
  FnThemeScheme,
  FN_ACCENT_PRESETS,
  FN_CUSTOM_ACCENT_KEY,
  FN_CUSTOM_BG_KEY,
  FN_PAGE_BACKGROUND_PRESETS,
  fnResolvedCardFill,
  FN_RESOLVED_ACCENT_KEY,
  FN_RESOLVED_CARD_BG_KEY,
  FN_RESOLVED_PAGE_BG_KEY,
  FN_THEME_SCHEMES
} from '../common/FnThemeColors';

const ME_LAN_BURST_SWITCH_ROW_HEIGHT_VP: number = 80;
const ME_IMMERSIVE_SWITCH_ROW_RADIUS_VP: number = 22;
const ME_ACTION_GAP_VP: number = 18;
const ME_CONNECTION_ROW_RADIUS_VP: number = 22;

/** 色块只靠 @Prop 改颜色和选中圈，不销毁重建。 */
@Component
struct ThemeColorSwatch {
  @Prop color: string = '#FF4A8BFF';
  @Prop selected: boolean = false;
  @Prop swatchSize: number = 36;
  @Prop passClick: boolean = false;
  onPick: () => void = () => {};

  build() {
    Column()
      .width(this.swatchSize)
      .height(this.swatchSize)
      .borderRadius(this.swatchSize / 2)
      .backgroundColor(this.color)
      .borderWidth(this.selected ? 3 : 1)
      .borderColor(this.selected ? fnThemeOnColor(this.color) : $r('app.color.card_border'))
      .hitTestBehavior(this.passClick ? HitTestMode.None : HitTestMode.Default)
      .onClick((): void => {
        this.onPick();
      })
  }
}

/** 底色/强调色那一行自己订阅当前颜色，避免 @Builder 参数只在创建时传一次。 */
@Component
struct ThemeColorSummaryRow {
  @Prop label: string = '';
  @Prop isPageBackground: boolean = true;
  @StorageProp(FN_CUSTOM_BG_KEY) private customPageBg: string = '';
  @StorageProp(FN_CUSTOM_ACCENT_KEY) private customAccent: string = '';
  @StorageProp(FN_RESOLVED_ACCENT_KEY) private accent: string = '#FF4A8BFF';
  @StorageProp('colorMode') private colorMode: number = 0;
  onOpen: () => void = () => {};

  private shownHex(): string {
    if (this.isPageBackground) {
      if (this.customPageBg.length > 0) {
        return this.customPageBg;
      }
      return this.colorMode === 1 ? '#FF000000' : '#FFF4F7FB';
    }
    if (this.customAccent.length > 0) {
      return this.customAccent;
    }
    return this.colorMode === 1 ? '#FF7DB0FF' : '#FF4A8BFF';
  }

  build() {
    Row({ space: 10 }) {
      Column()
        .width(28)
        .height(28)
        .borderRadius(14)
        .backgroundColor(this.shownHex())
        .borderWidth(1)
        .borderColor($r('app.color.card_border'))
        .hitTestBehavior(HitTestMode.None)

      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        Text(this.shownHex().toUpperCase())
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('修改')
        .fontSize(13)
        .fontColor(this.accent)
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.onOpen();
    })
  }
}

@Component
struct ThemeSchemeChip {
  @Prop name: string = '';
  @Prop pageBackground: string = '';
  @Prop accentColor: string = '';
  @Prop selected: boolean = false;
  @Prop fallbackBackground: string = '#FFF4F7FB';
  @Prop fallbackAccent: string = '#FF4A8BFF';
  onPick: () => void = () => {};

  private shownBackground(): string {
    return this.pageBackground.length > 0 ? this.pageBackground : this.fallbackBackground;
  }

  private shownAccent(): string {
    return this.accentColor.length > 0 ? this.accentColor : this.fallbackAccent;
  }

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column()
          .width(52)
          .height(36)
          .borderRadius(10)
          .backgroundColor(this.shownBackground())
          .borderWidth(this.selected ? 2 : 1)
          .borderColor(this.selected ? this.shownAccent() : $r('app.color.card_border'))
        Column()
          .width(14)
          .height(14)
          .borderRadius(7)
          .backgroundColor(this.shownAccent())
          .borderWidth(1)
          .borderColor($r('app.color.card_border'))
          .margin({ right: 4, bottom: 4 })
      }
      Text(this.name)
        .fontSize(11)
        .fontColor(this.selected ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
    }
    .onClick((): void => {
      this.onPick();
    })
  }
}

@Component
export struct MePanel {
  @StorageProp(FN_RESOLVED_PAGE_BG_KEY) private pageBg: string = '#FFF4F7FB';
  @StorageProp(FN_RESOLVED_ACCENT_KEY) private accent: string = '#FF4A8BFF';
  @StorageProp(FN_RESOLVED_CARD_BG_KEY) private cardBg: string = '';
  @StorageProp(FN_CUSTOM_BG_KEY) private customPageBg: string = '';
  @StorageProp(FN_CUSTOM_ACCENT_KEY) private customAccent: string = '';
  @StorageProp('colorMode') private colorMode: number = 0;
  @State private colorEditorVisible: boolean = false;
  @State private colorEditorIsBackground: boolean = true;
  @State private colorEditorDraft: string = '#FFF4F7FB';
  @State private colorEditorError: string = '';
  @Prop topSafeInsetVp: number = 0;
  /** 给悬浮底栏留空，滚动到底时退出登录仍露在 dock 上方。 */
  @Prop floatingDockInsetBottomVp: number = 0;
  @Prop @Watch('onPageShowSignalChanged') pageShowSignal: number = 0;
  onEndpointSwitched: () => void = () => {};
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
  @State private configSyncVisible: boolean = false;
  @State private transferQueueTasks: FnTransferTaskSnapshot[] = [];
  @State private diagExporting: boolean = false;
  @State private rateEntryVisible: boolean = false;
  @State private rateOpening: boolean = false;
  @StorageProp(FN_TRANSFER_QUEUE_VERSION) @Watch('onTransferQueueVersionChanged') private transferQueueVersion: number = 0;
  @StorageProp(FN_ENDPOINT_SWITCH_VERSION) @Watch('onEndpointSwitchVersionChanged') private endpointSwitchVersion: number = 0;
  private lastLanBurstToggleAt: number = 0;
  private meScroller: Scroller = new Scroller();
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
    this.refreshRateEntry();
    this.refreshSystemColorPreview();
  }

  private meScrollBottomPaddingVp(): number {
    return Math.max(24, this.floatingDockInsetBottomVp);
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
    this.getUIContext().getPromptAction().showToast({ message, duration: 1500 });
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

  private shouldUseHds(): boolean {
    return fnCanUseHdsImmersive();
  }

  private refreshRateEntry(): void {
    if (!fnAppGalleryCommentAvailable()) {
      this.rateEntryVisible = false;
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void fnIsAppGalleryCommentDone(ctx).then((done: boolean): void => {
      this.rateEntryVisible = !done;
    });
  }

  private async openAppGalleryRate(): Promise<void> {
    if (this.rateOpening || !this.rateEntryVisible) {
      return;
    }
    this.rateOpening = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await fnShowAppGalleryComment(ctx);
      if (result === APP_GALLERY_RATE_ALREADY) {
        this.rateEntryVisible = false;
        return;
      }
      if (result === APP_GALLERY_RATE_NEED_ID) {
        this.showRateToast($r('app.string.rate_app_need_huawei_id'));
        return;
      }
      if (result === APP_GALLERY_RATE_FAILED) {
        this.showRateToast($r('app.string.rate_app_unavailable'));
      }
    } finally {
      this.rateOpening = false;
    }
  }

  private showRateToast(message: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    } catch (_e) {
    }
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
    this.refreshEndpointInfo();
    FnTransferQueueStore.ensureStorage();
    this.refreshTransferQueueTasks();
    this.refreshLanBurstSwitch();
    this.refreshRateEntry();
    this.refreshSystemColorPreview();
  }

  private refreshSystemColorPreview(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    fnRefreshSystemColorPreview(ctx);
  }

  private cardGlass(strong: boolean = false): LinearGradientOptions {
    if (this.cardBg.length > 0) {
      return fnSoftCardGlassGradient();
    }
    return fnLiquidGlassGradient(strong);
  }

  private shownCustomBackground(): string {
    if (this.customPageBg.length > 0) {
      return this.customPageBg;
    }
    return this.colorMode === 1 ? '#FF000000' : '#FFF4F7FB';
  }

  private shownCustomAccent(): string {
    if (this.customAccent.length > 0) {
      return this.customAccent;
    }
    return this.colorMode === 1 ? '#FF7DB0FF' : '#FF4A8BFF';
  }

  private openColorEditor(pageBackground: boolean): void {
    this.colorEditorIsBackground = pageBackground;
    this.colorEditorDraft = pageBackground ? this.shownCustomBackground() : this.shownCustomAccent();
    this.colorEditorError = '';
    this.colorEditorVisible = true;
  }

  private isSchemeActive(scheme: FnThemeScheme): boolean {
    if (scheme.background.length === 0 && scheme.accent.length === 0) {
      return this.customPageBg.length === 0 && this.customAccent.length === 0;
    }
    return fnNormalizeThemeHex(this.customPageBg) === scheme.background &&
      fnNormalizeThemeHex(this.customAccent) === scheme.accent;
  }

  private applyThemeScheme(scheme: FnThemeScheme): void {
    if (this.isSchemeActive(scheme)) {
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void fnSaveThemeScheme(ctx, scheme.background, scheme.accent).then((): void => {
      window.getLastWindow(ctx).then((win: window.Window): void => {
        fnApplyThemeWindowBackground(win, ctx);
      }).catch((): void => {
      });
    });
  }

  private confirmCustomColor(): void {
    const normalized = fnNormalizeThemeHex(this.colorEditorDraft);
    if (normalized.length === 0) {
      this.colorEditorError = '请输入 #RGB、#RRGGBB 或 #AARRGGBB';
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const pageBackground = this.colorEditorIsBackground;
    void fnSaveCustomColor(ctx, pageBackground, normalized).then((ok: boolean): void => {
      if (!ok) {
        this.colorEditorError = '请输入 #RGB、#RRGGBB 或 #AARRGGBB';
        return;
      }
      this.colorEditorVisible = false;
      window.getLastWindow(ctx).then((win: window.Window): void => {
        fnApplyThemeWindowBackground(win, ctx);
      }).catch((): void => {
      });
    });
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
        .backgroundColor(fnResolvedCardFill(this.cardBg))
        .borderRadius($r('app.float.radius_medium'))
        .padding({ left: 12, right: 12 })
        .enabled(!this.twofaLoading)

      Row() {
        Text($r('app.string.trust_device'))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.twofaTrustDevice })
          .selectedColor(this.accent)
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
      .alignItems(HorizontalAlign.Start)
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
    .backgroundColor(fnResolvedCardFill(this.cardBg))
    .backgroundBlurStyle(this.cardBg.length > 0 ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(this.cardGlass())
    .borderRadius(ME_CONNECTION_ROW_RADIUS_VP)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
    .clip(true)
    .onClick((): void => {
      this.configSyncVisible = true;
    })
  }

  @Builder
  private configSyncSheetBuilder() {
    ConfigSyncSheet()
  }

  @Builder
  private diagLogEntryRow() {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text($r('app.string.diag_log_entry_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.diagExporting ? '正在导出…' : $r('app.string.diag_log_entry_subtitle'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor(fnResolvedCardFill(this.cardBg))
    .backgroundBlurStyle(this.cardBg.length > 0 ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(this.cardGlass())
    .borderRadius(ME_CONNECTION_ROW_RADIUS_VP)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
    .clip(true)
    .opacity(this.diagExporting ? 0.55 : 1)
    .onClick((): void => {
      void this.exportDiagLog();
    })
  }

  private async exportDiagLog(): Promise<void> {
    if (this.diagExporting) {
      return;
    }
    this.diagExporting = true;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const ok = await fnDiagShare(ctx);
      try {
        this.getUIContext().getPromptAction().showToast({
          message: ok ? $r('app.string.diag_log_toast_ok') : $r('app.string.diag_log_toast_fail'),
          duration: 2200
        });
      } catch (_toast) {
      }
    } catch (_e) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.diag_log_toast_fail'),
          duration: 1800
        });
      } catch (_toast) {
      }
    } finally {
      this.diagExporting = false;
    }
  }

  @Builder
  private privacyPolicyLink() {
    Column({ space: 10 }) {
      Text($r('app.string.privacy_policy_title'))
        .fontSize(13)
        .fontColor(this.accent)
        .textAlign(TextAlign.Center)
        .width('100%')
        .onClick((): void => {
          openPrivacyPolicyPage(this.getUIContext());
        })
      Text($r('app.string.privacy_collected_entry_title'))
        .fontSize(13)
        .fontColor(this.accent)
        .textAlign(TextAlign.Center)
        .width('100%')
        .onClick((): void => {
          openCollectedInfoListPage(this.getUIContext());
        })
      Text($r('app.string.privacy_third_party_entry_title'))
        .fontSize(13)
        .fontColor(this.accent)
        .textAlign(TextAlign.Center)
        .width('100%')
        .onClick((): void => {
          openThirdPartyShareListPage(this.getUIContext());
        })
    }
    .width('100%')
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
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (FnTransferQueueStore.activeCount() > 0) {
        Text(`${FnTransferQueueStore.activeCount()}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.accent)
          .borderRadius(10)
      }

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor(fnResolvedCardFill(this.cardBg))
    .backgroundBlurStyle(this.cardBg.length > 0 ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(this.cardGlass())
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
        .fontColor(this.endpointInfo.kind === kind ? this.accent :
          (available ? $r('app.color.text_primary') : $r('app.color.text_secondary')))
        .opacity(available ? 1 : 0.35)

      Row()
        .width(22)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.endpointInfo.kind === kind ? this.accent : Color.Transparent)
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
        .backgroundColor(fnResolvedCardFill(this.cardBg))
        .backgroundBlurStyle(this.cardBg.length > 0 ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THICK)
        .linearGradient(this.cardGlass())
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
  private rateEntryRow() {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text($r('app.string.rate_app_entry_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.rate_app_entry_subtitle'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor(fnResolvedCardFill(this.cardBg))
    .backgroundBlurStyle(this.cardBg.length > 0 ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(this.cardGlass(this.shouldUseHds()))
    .borderRadius(ME_CONNECTION_ROW_RADIUS_VP)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
    .clip(true)
    .opacity(this.rateOpening ? 0.55 : 1)
    .onClick((): void => {
      void this.openAppGalleryRate();
    })
  }

  @Builder
  private themeColorCard() {
    Column({ space: 12 }) {
      Text('界面配色')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Scroll() {
        Row({ space: 12 }) {
          ForEach(FN_THEME_SCHEMES, (scheme: FnThemeScheme) => {
            ThemeSchemeChip({
              name: scheme.name,
              pageBackground: scheme.background,
              accentColor: scheme.accent,
              selected: this.isSchemeActive(scheme),
              fallbackBackground: this.colorMode === 1 ? '#FF000000' : '#FFF4F7FB',
              fallbackAccent: this.colorMode === 1 ? '#FF7DB0FF' : '#FF4A8BFF',
              onPick: (): void => {
                this.applyThemeScheme(scheme);
              }
            })
          }, (scheme: FnThemeScheme): string => scheme.name)
        }
        .padding({ right: 4, bottom: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      ThemeColorSummaryRow({
        label: '底色',
        isPageBackground: true,
        onOpen: (): void => {
          this.openColorEditor(true);
        }
      })
      ThemeColorSummaryRow({
        label: '强调色',
        isPageBackground: false,
        onOpen: (): void => {
          this.openColorEditor(false);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor(fnResolvedCardFill(this.cardBg))
    .backgroundBlurStyle(this.cardBg.length > 0 ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(this.cardGlass())
    .borderRadius(ME_CONNECTION_ROW_RADIUS_VP)
    .borderWidth(1)
    .borderColor($r('app.color.immersive_panel_border'))
    .clip(true)
    .bindSheet(this.colorEditorVisible, this.colorEditorSheet, fnHdsFitContentSheetOptions(
      this.colorEditorIsBackground ? '底色' : '强调色',
      (): void => {
        this.colorEditorVisible = false;
      }
    ))
  }

  @Builder
  private colorEditorSheet() {
    Column({ space: 14 }) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.colorEditorIsBackground ? FN_PAGE_BACKGROUND_PRESETS : FN_ACCENT_PRESETS,
          (hex: string) => {
            ThemeColorSwatch({
              color: hex,
              selected: fnNormalizeThemeHex(this.colorEditorDraft) === hex,
              onPick: (): void => {
                this.colorEditorDraft = hex;
                this.colorEditorError = '';
              }
            })
              .margin({ right: 10, bottom: 10 })
          }, (hex: string): string => hex)
      }
      .width('100%')

      TextInput({ text: this.colorEditorDraft, placeholder: '#RRGGBB' })
        .width('100%')
        .height(40)
        .fontSize(15)
        .onChange((value: string): void => {
          this.colorEditorDraft = value;
          this.colorEditorError = '';
        })

      if (this.colorEditorError.length > 0) {
        Text(this.colorEditorError)
          .fontSize(12)
          .fontColor('#FFE11D48')
          .width('100%')
      }

      Text('使用这个颜色')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(fnThemeOnColor(fnNormalizeThemeHex(this.colorEditorDraft).length > 0 ?
          this.colorEditorDraft : this.accent))
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(40)
        .borderRadius(12)
        .backgroundColor(fnNormalizeThemeHex(this.colorEditorDraft).length > 0 ?
          fnNormalizeThemeHex(this.colorEditorDraft) : this.accent)
        .onClick((): void => {
          this.confirmCustomColor();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
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
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.lanBurstForceEnabled })
        .selectedColor(this.accent)
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
        .backgroundColor(fnResolvedCardFill(this.cardBg))
        .backgroundBlurStyle(this.cardBg.length > 0 ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THICK)
        .linearGradient(this.cardGlass(this.shouldUseHds()))
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

  private meTitleBarOptions(): HdsNavigationTitleBarOptions {
    return fnHdsMiniTitleBarOptions(this.shouldUseHds(), {
      title: { mainTitle: '我的' },
      backIcon: {
        label: '返回',
        isEnabled: false,
        action: (): void => {
        }
      }
    }, true);
  }

  build() {
    HdsNavigation() {
      Scroll(this.meScroller) {
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

        this.themeColorCard()

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        this.transferQueueEntryRow()

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        Column() {
          this.configSyncEntryRow()
        }
        .width('100%')
        .bindSheet(this.configSyncVisible, this.configSyncSheetBuilder, fnHdsLargeSheetOptions(
          $r('app.string.config_sync_title'),
          (): void => {
            this.configSyncVisible = false;
          }
        ))

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        this.diagLogEntryRow()

        if (this.rateEntryVisible) {
          Blank()
            .width('100%')
            .height(ME_ACTION_GAP_VP)

          this.rateEntryRow()
        }

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
              if (!existing.rememberPassword) {
                await SessionPreferences.clearSessionPassword(ctx);
              }
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

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        this.privacyPolicyLink()
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({
          left: 24,
          right: 24,
          top: this.topSafeInsetVp + FN_HDS_NAV_CHROME_HEIGHT_VP,
          bottom: this.meScrollBottomPaddingVp()
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.TopStart)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .bindToScrollable([this.meScroller])
    .titleBar(this.meTitleBarOptions())
    .backgroundColor(this.pageBg)
    .bindSheet(this.transferQueueVisible, this.transferQueueSheetBuilder, fnHdsMediumDetentSheetOptions(
      '传输队列',
      (): void => {
        this.transferQueueVisible = false;
      }
    ))
  }
}
