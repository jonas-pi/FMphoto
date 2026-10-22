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
  fnHdsQueueSheetOptions,
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
import { kickNasTaskPanelSync } from '../network/FnNasTaskPanelSync';
import { openFeedbackPage } from './FeedbackPage';
import { openTipPage } from './TipPage';
import { fnPresentAppGalleryComment } from '../common/AppGalleryRate';
import { fnApplyImmersiveSystemBarColors } from '../common/FnSplashTheme';
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
  fnScrollToTopAnimated,
  fnSoftCardGlassGradient,
  FnHdsPillButton,
  FnPrimaryButton
} from '../common/FnUiCommon';
import { fnCanUseHdsImmersive } from '../common/FnImmersiveSettings';
import { fnDiagMaskUrl, fnDiagRecord, fnDiagSetState } from '../common/FnDiagLog';
import {
  isGalleryLanBurstAutoEnabled,
  isGalleryLanBurstEnabled,
  isGalleryLanBurstForceEnabled,
  setGalleryLanBurstForceEnabled
} from '../album/GalleryPerfProfile';
import { invalidateAutoSync } from '../album/GalleryAutoSyncBadge';
import { GalleryTimelineRefreshStore } from '../album/GalleryTimelineRefreshStore';
import { GalleryThumbDiskCache } from '../album/GalleryThumbDiskCache';
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
  FN_THEME_SCHEMES,
  fnResolvedTextPrimary,
  FN_RESOLVED_TEXT_PRIMARY_KEY,
  fnResolvedTextSecondary,
  FN_RESOLVED_TEXT_SECONDARY_KEY
} from '../common/FnThemeColors';

/** 华为暂不允许应用内支付。恢复赞赏入口时改为 true。 */
const ME_SHOW_TIP_ENTRY: boolean = false;
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
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @StorageProp(FN_RESOLVED_TEXT_SECONDARY_KEY) private themeTextSecondary: string = '';
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
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Text(this.shownHex().toUpperCase())
          .fontSize(11)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
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
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @StorageProp(FN_RESOLVED_TEXT_SECONDARY_KEY) private themeTextSecondary: string = '';
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
        .fontColor(this.selected ? fnResolvedTextPrimary(this.themeTextPrimary) : fnResolvedTextSecondary(this.themeTextSecondary))
    }
    .onClick((): void => {
      this.onPick();
    })
  }
}

@Component
export struct MePanel {
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @StorageProp(FN_RESOLVED_TEXT_SECONDARY_KEY) private themeTextSecondary: string = '';
  @StorageProp(FN_RESOLVED_PAGE_BG_KEY) private pageBg: string = '#FFF4F7FB';
  @StorageProp(FN_RESOLVED_ACCENT_KEY) private accent: string = '#FF4A8BFF';
  @StorageProp(FN_RESOLVED_CARD_BG_KEY) private cardBg: string = '';
  @StorageProp(FN_CUSTOM_BG_KEY) private customPageBg: string = '';
  @StorageProp(FN_CUSTOM_ACCENT_KEY) private customAccent: string = '';
  @StorageProp('colorMode') private colorMode: number = 0;
  @State private backgroundEditorVisible: boolean = false;
  @State private accentEditorVisible: boolean = false;
  @State private colorEditorIsBackground: boolean = true;
  @State private colorEditorDraft: string = '#FFF4F7FB';
  @State private colorEditorError: string = '';
  @Prop topSafeInsetVp: number = 0;
  /** 给悬浮底栏留空，滚动到底时退出登录仍露在 dock 上方。 */
  @Prop floatingDockInsetBottomVp: number = 0;
  @Prop @Watch('onPageShowSignalChanged') pageShowSignal: number = 0;
  /** 再次点击 dock 当前 tab：面板回到顶部。 */
  @Prop @Watch('onScrollToTopSignalChanged') scrollToTopSignal: number = 0;
  onEndpointSwitched: () => void = () => {};
  /** 用户手动满载；内网自动满载由独立状态展示，不会改写用户开关 */
  @State private lanBurstForceEnabled: boolean = false;
  @State private lanBurstAutoEnabled: boolean = false;
  @State private lanBurstEnabled: boolean = false;
  @State private endpointInfo: EndpointConnectionInfo = resolveEndpointConnectionInfo(null);
  /** 隐藏 NAS 地址（域名 / FN ID / 局域网 IP）：演示、截图时避免暴露。 */
  @State private endpointAddressHidden: boolean = false;
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
  @StorageProp(FN_TRANSFER_QUEUE_VERSION) @Watch('onTransferQueueVersionChanged') private transferQueueVersion: number = 0;
  @StorageProp(FN_ENDPOINT_SWITCH_VERSION) @Watch('onEndpointSwitchVersionChanged') private endpointSwitchVersion: number = 0;
  private lastLanBurstToggleAt: number = 0;
  private backgroundSheetToken: number = 0;
  private accentSheetToken: number = 0;
  private backgroundShownToken: number = 0;
  private accentShownToken: number = 0;
  private backgroundOpenTimer: number = -1;
  private accentOpenTimer: number = -1;
  private backgroundSheetOptions: SheetOptions = fnHdsFitContentSheetOptions('底色', (): void => {});
  private accentSheetOptions: SheetOptions = fnHdsFitContentSheetOptions('强调色', (): void => {});
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
    // 「隐藏 NAS 地址」开关只挡 UI；日志里的地址一律掩码后记录
    if (this.endpointInfo.addressText.length > 0) {
      fnDiagSetState('meEndpoint', fnDiagMaskUrl(this.endpointInfo.addressText));
    }
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
    this.refreshSystemColorPreview();
  }

  private onScrollToTopSignalChanged(): void {
    fnScrollToTopAnimated(this.meScroller);
  }

  /** 地址行显示内容：隐藏时用掩码代替真实域名 / FN ID / 局域网 IP。 */
  private endpointAddressDisplay(): string {
    if (this.endpointSwitching) {
      return '正在切换…';
    }
    if (this.endpointAddressHidden) {
      return '••••••••';
    }
    return this.endpointInfo.addressText;
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
    return fnResolvedTextSecondary(this.themeTextSecondary);
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
      if (display.selectedAddress.length > 0) {
        fnDiagSetState('meProbeAddress', fnDiagMaskUrl(display.selectedAddress));
      }
    } catch (e) {
      fnDiagRecord('W', 'MePanel', `endpoint probe failed ${String(e)}`);
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
      } catch (e) {
        fnDiagRecord('W', 'MePanel', `cert dialog error ${String(e)}`);
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
    if (this.pendingTwofaTargetUrl.length > 0) {
      fnDiagSetState('me2faTarget', fnDiagMaskUrl(this.pendingTwofaTargetUrl));
    }
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
      fnDiagRecord('W', 'MePanel', '2fa invalid');
      this.twofaError = '请输入身份验证器中的 6 位动态验证码';
      return;
    }
    if (this.pendingTwofaAccessToken.length === 0 || this.pendingTwofaTargetUrl.length === 0 ||
      this.pendingTwofaDeviceId.length === 0) {
      fnDiagRecord('W', 'MePanel', '2fa expired');
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
      } catch (e) {
        fnDiagRecord('W', 'MePanel', `cert dialog error ${String(e)}`);
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

  aboutToDisappear(): void {
    if (this.backgroundOpenTimer >= 0) {
      clearTimeout(this.backgroundOpenTimer);
      this.backgroundOpenTimer = -1;
    }
    if (this.accentOpenTimer >= 0) {
      clearTimeout(this.accentOpenTimer);
      this.accentOpenTimer = -1;
    }
  }

  aboutToAppear(): void {
    this.refreshEndpointInfo();
    FnTransferQueueStore.ensureStorage();
    this.refreshTransferQueueTasks();
    this.refreshLanBurstSwitch();
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
    if (pageBackground) {
      this.presentColorEditor(true);
      return;
    }
    this.presentColorEditor(false);
  }

  /**
   * 开关如果停在 true，半模态却已经关掉，再设 true 不会重新弹出。
   * 已经开着时先关掉，下一帧再打开，保证每次点击都有一次从关到开。
   */
  private presentColorEditor(pageBackground: boolean): void {
    const token = pageBackground ? ++this.backgroundSheetToken : ++this.accentSheetToken;
    const visible = pageBackground ? this.backgroundEditorVisible : this.accentEditorVisible;
    const show = (): void => {
      if (pageBackground) {
        this.backgroundOpenTimer = -1;
        if (this.backgroundSheetToken !== token) {
          return;
        }
        this.backgroundSheetOptions = this.makeColorEditorOptions(true, token);
        this.backgroundShownToken = token;
        this.backgroundEditorVisible = true;
        return;
      }
      this.accentOpenTimer = -1;
      if (this.accentSheetToken !== token) {
        return;
      }
      this.accentSheetOptions = this.makeColorEditorOptions(false, token);
      this.accentShownToken = token;
      this.accentEditorVisible = true;
    };
    if (!visible) {
      show();
      return;
    }
    if (pageBackground) {
      this.backgroundEditorVisible = false;
      if (this.backgroundOpenTimer >= 0) {
        clearTimeout(this.backgroundOpenTimer);
      }
      this.backgroundOpenTimer = setTimeout(show, 0);
      return;
    }
    this.accentEditorVisible = false;
    if (this.accentOpenTimer >= 0) {
      clearTimeout(this.accentOpenTimer);
    }
    this.accentOpenTimer = setTimeout(show, 0);
  }

  private closeColorEditor(): void {
    if (this.colorEditorIsBackground) {
      this.backgroundEditorVisible = false;
      return;
    }
    this.accentEditorVisible = false;
  }

  private makeColorEditorOptions(pageBackground: boolean, token: number): SheetOptions {
    return fnHdsFitContentSheetOptions(pageBackground ? '底色' : '强调色', (): void => {
      if (pageBackground) {
        if (this.backgroundShownToken !== token) {
          return;
        }
        this.backgroundShownToken = 0;
        this.backgroundEditorVisible = false;
        return;
      }
      if (this.accentShownToken !== token) {
        return;
      }
      this.accentShownToken = 0;
      this.accentEditorVisible = false;
    });
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
        fnApplyImmersiveSystemBarColors(win, this.colorMode === 1);
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
      this.closeColorEditor();
      window.getLastWindow(ctx).then((win: window.Window): void => {
        fnApplyThemeWindowBackground(win, ctx);
        fnApplyImmersiveSystemBarColors(win, this.colorMode === 1);
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
        .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
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
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
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
    FnTransferQueueSheet({
      tasks: this.transferQueueTasks,
      onClose: (): void => {
        this.transferQueueVisible = false;
      }
    })
  }

  @Builder
  private configSyncEntryRow() {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text($r('app.string.config_sync_entry_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Text($r('app.string.config_sync_entry_subtitle'))
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.qrcode'))
        .fontSize(18)
        .fontColor([fnResolvedTextSecondary(this.themeTextSecondary)])

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([fnResolvedTextSecondary(this.themeTextSecondary)])
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
  private albumBackupSyncEntryRow() {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text($r('app.string.album_backup_entry_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Text($r('app.string.album_backup_entry_subtitle'))
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontSize(18)
        .fontColor([fnResolvedTextSecondary(this.themeTextSecondary)])

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([fnResolvedTextSecondary(this.themeTextSecondary)])
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
      this.getUIContext().getRouter().pushUrl({ url: 'pages/AlbumBackupSyncPage' }).catch((): void => {
        this.showEndpointToast('同步设置打不开');
      });
    })
  }

  @Builder
  private diagLogEntryRow() {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text($r('app.string.diag_log_entry_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Text($r('app.string.diag_log_entry_subtitle'))
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([fnResolvedTextSecondary(this.themeTextSecondary)])
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
      openFeedbackPage(this.getUIContext());
    })
  }

  @Builder
  private tipEntryRow() {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text($r('app.string.tip_entry_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Text($r('app.string.tip_entry_subtitle'))
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([fnResolvedTextSecondary(this.themeTextSecondary)])
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
      openTipPage(this.getUIContext());
    })
  }

  @Builder
  private rateEntryRow() {
    Row({ space: 10 }) {
      Column({ space: 6 }) {
        Text($r('app.string.rate_app_entry_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Text($r('app.string.rate_app_entry_subtitle'))
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([fnResolvedTextSecondary(this.themeTextSecondary)])
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
      void fnPresentAppGalleryComment(this.getUIContext());
    })
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
        Text('任务队列')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Text(
          FnTransferQueueStore.activeCount() > 0
            ? `${FnTransferQueueStore.activeCount()} \u4e2a\u4efb\u52a1\u8fdb\u884c\u4e2d`
            : '查看扫描、上传、下载与同步'
        )
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
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
        .fontColor([fnResolvedTextSecondary(this.themeTextSecondary)])
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
      kickNasTaskPanelSync();
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
          (available ? fnResolvedTextPrimary(this.themeTextPrimary) : fnResolvedTextSecondary(this.themeTextSecondary)))
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
              .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
              .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16)
              .fontColor([fnResolvedTextSecondary(this.themeTextSecondary)])
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            this.openEndpointProbeSheet();
          })

          Row() {
            Text(this.endpointAddressDisplay())
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .onClick((): void => {
                this.openEndpointProbeSheet();
              })

            // 隐藏 / 显示地址：防止演示或截图时暴露域名
            SymbolGlyph(this.endpointAddressHidden ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
              .fontSize(19)
              .fontColor([fnResolvedTextSecondary(this.themeTextSecondary)])
              .width(30)
              .height(30)
              .accessibilityText(this.endpointAddressHidden ? '显示地址' : '隐藏地址')
              .onClick((): void => {
                this.endpointAddressHidden = !this.endpointAddressHidden;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

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
  private themeColorCard() {
    Column({ space: 12 }) {
      Text('界面配色')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
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

      Column() {
        ThemeColorSummaryRow({
          label: '底色',
          isPageBackground: true,
          onOpen: (): void => {
            this.openColorEditor(true);
          }
        })
      }
      .width('100%')
      .bindSheet(this.backgroundEditorVisible, this.colorEditorSheet, this.backgroundSheetOptions)

      Column() {
        ThemeColorSummaryRow({
          label: '强调色',
          isPageBackground: false,
          onOpen: (): void => {
            this.openColorEditor(false);
          }
        })
      }
      .width('100%')
      .bindSheet(this.accentEditorVisible, this.colorEditorSheet, this.accentSheetOptions)
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
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.lanBurstSupportText())
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
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
    }, true, fnResolvedTextPrimary(this.themeTextPrimary), fnResolvedTextSecondary(this.themeTextSecondary));
  }

  build() {
    HdsNavigation() {
      Scroll(this.meScroller) {
        Column({ space: 0 }) {
        Column({ space: 10 }) {
          Text('FNOS \u4e2a\u4eba\u4e2d\u5fc3')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))

          Text('\u9996\u9875\u5df2\u7ecf\u5207\u6362\u4e3a\u7eaf\u539f\u751f\u56fe\u5e93\u58f3\u4f53\uff0c\u8fd9\u91cc\u4fdd\u7559\u8d26\u53f7\u4e0e\u7cfb\u7edf\u5165\u53e3\u3002')
            .fontSize(13)
            .lineHeight(20)
            .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
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
            .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
          Text('1. \u9996\u9875 Web \u5df2\u5b8c\u5168\u79fb\u9664\u3002')
            .fontSize(13)
            .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          Text('2. \u5e95\u90e8\u4e3b\u5bfc\u822a\u7edf\u4e00\u4e3a\u7167\u7247\u3001\u76f8\u518c\u3001\u6211\u7684\u3002')
            .fontSize(13)
            .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          Text('3. \u56fe\u5e93\u4e3b\u9875\u4f7f\u7528\u60ac\u6d6e\u6807\u9898\u680f\u4e0e\u60ac\u6d6e\u5e95\u90e8\u5bfc\u822a\u3002')
            .fontSize(13)
            .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
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

        this.albumBackupSyncEntryRow()

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

        if (ME_SHOW_TIP_ENTRY) {
          Blank()
            .width('100%')
            .height(ME_ACTION_GAP_VP)

          this.tipEntryRow()
        }

        Blank()
          .width('100%')
          .height(ME_ACTION_GAP_VP)

        this.rateEntryRow()

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
              invalidateAutoSync(ctx);
              GalleryTimelineRefreshStore.bump();
              stopGalleryVideoLanPrefetch();
              AppSession.clear();
              // 退出登录：账号相关的缩略图/封面全部丢弃，避免下一个账号看到上一个账号的封面
              GalleryThumbDiskCache.invalidateAll();
              this.getUIContext().getRouter().replaceUrl({ url: 'pages/Login' }).catch((e: Error): void => {
                fnDiagRecord('E', 'MePanel', `navigate failed url=Login ${String(e)}`);
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
    .bindSheet(this.transferQueueVisible, this.transferQueueSheetBuilder, fnHdsQueueSheetOptions(
      (): void => {
        this.transferQueueVisible = false;
      }
    ))
  }
}
