/**
 * 配置同步：二维码导出/导入 + WebDAV 上传/下载智能分类。
 */
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  BlurStrategy,
  HdsNavigation,
  HdsNavigationBackButtonItemOptions,
  HdsNavigationTitleBarStyle,
  HdsNavigationTitleMode,
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import { fnRestoreAppSystemBars } from '../common/FnSplashTheme';
import { FN_SYSTEM_TOP_INSET_VP_KEY, fnPublishSystemAvoidArea } from '../common/FnSystemAvoidArea';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import {
  fnHdsImmersiveSystemMaterialEffect,
  fnHdsChromeButtonBackgroundColor,
  fnHdsChromeButtonFallbackBackgroundColor,
  fnHdsChromeButtonForegroundColor,
  fnHdsNavChromeBackgroundStyle,
  fnHdsNavChromeScrolledBackgroundStyle,
  fnHdsNavChromeScrollEffectOpts,
  fnHdsNavTitleBarPadding,
  FnPrimaryButton,
  FnSecondaryButton,
  FN_HDS_NAV_CHROME_HEIGHT_VP
} from '../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../common/FnImmersiveSettings';
import { SessionPreferences } from '../auth/SessionPreferences';
import {
  smartCategoryCurrentAccount,
  smartCategoryLoadLayout,
  smartCategorySaveLayout,
  SmartCategoryLayout
} from '../album/SmartCategoryLayoutPreferences';
import {
  AppSettingsEnvelope,
  applyEnvelopeToAccount,
  envelopeFromLayout,
  layoutLocalUpdatedAt,
  parseEnvelopeJson,
  parseQrPayload,
  serializeEnvelope
} from '../sync/AppSettingsEnvelope';
import {
  canScanSettingsQr,
  createSettingsQrImage,
  isScanUserCancel
} from '../sync/AppSettingsQr';
import { webDavGetJson, webDavPutJson } from '../sync/AppSettingsWebDav';
import {
  APP_SETTINGS_WEBDAV_DEFAULT_PATH,
  AppSettingsWebDavConfig,
  loadWebDavConfig,
  saveWebDavConfig
} from '../sync/AppSettingsWebDavPrefs';

@Entry
@Component
struct ConfigSyncPage {
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  @State private qrPixelMap: image.PixelMap | undefined = undefined;
  @State private qrHint: string = '正在生成二维码…';
  @State private davUrl: string = '';
  @State private davUser: string = '';
  @State private davPassword: string = '';
  @State private davPath: string = APP_SETTINGS_WEBDAV_DEFAULT_PATH;
  @State private davSkipCert: boolean = true;
  @State private davBusy: boolean = false;
  @State private qrBusy: boolean = false;

  aboutToAppear(): void {
    void this.bootstrap();
  }

  aboutToDisappear(): void {
    void this.persistWebDavForm();
    this.releaseQrPixelMap();
  }

  onPageShow(): void {
    this.applySystemBarTheme();
  }

  onColorModeChanged(): void {
    this.applySystemBarTheme();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_e) {
    }
  }

  private canUseHds(): boolean {
    return fnCanUseHdsImmersive(this.immersiveLightEnabled);
  }

  private applySystemBarTheme(): void {
    try {
      const dark = this.colorMode === 1;
      const bg = dark ? '#FF1C1C1E' : '#FFF5F5F5';
      const content = dark ? '#FFFFFFFF' : '#FF000000';
      const ctx = this.hostContext();
      window.getLastWindow(ctx).then((win: window.Window): void => {
        fnRestoreAppSystemBars(win);
        fnPublishSystemAvoidArea(win, this.getUIContext());
        win.setWindowSystemBarProperties({
          statusBarColor: bg,
          navigationBarColor: bg,
          statusBarContentColor: content,
          navigationBarContentColor: content
        }).catch((_e: Error): void => {});
      }).catch((_e: Error): void => {});
    } catch (_e) {
    }
  }

  private currentWebDavConfig(): AppSettingsWebDavConfig {
    return {
      serverUrl: this.davUrl,
      username: this.davUser,
      password: this.davPassword,
      remotePath: this.davPath,
      skipCert: this.davSkipCert
    };
  }

  private async persistWebDavForm(): Promise<void> {
    await saveWebDavConfig(this.hostContext(), this.currentWebDavConfig());
  }

  private releaseQrPixelMap(): void {
    const prev = this.qrPixelMap;
    this.qrPixelMap = undefined;
    if (prev !== undefined) {
      try {
        prev.release();
      } catch (_e) {
      }
    }
  }

  private async bootstrap(): Promise<void> {
    const ctx = this.hostContext();
    const dav = await loadWebDavConfig(ctx);
    this.davUrl = dav.serverUrl;
    this.davUser = dav.username;
    this.davPassword = dav.password;
    this.davPath = dav.remotePath;
    this.davSkipCert = dav.skipCert;
    await this.refreshQr();
  }

  private async loadCurrentLayout(): Promise<SmartCategoryLayout> {
    return await smartCategoryLoadLayout(this.hostContext(), smartCategoryCurrentAccount());
  }

  private async refreshQr(): Promise<void> {
    if (this.qrBusy) {
      return;
    }
    this.qrBusy = true;
    try {
      const account = smartCategoryCurrentAccount();
      if (account.length === 0) {
        this.releaseQrPixelMap();
        this.qrHint = '当前未登录，无法生成配置码';
        return;
      }
      const layout = await this.loadCurrentLayout();
      const deviceId = await SessionPreferences.ensureWsDeviceId(this.hostContext());
      const updatedAt = layoutLocalUpdatedAt(layout) > 0 ? layoutLocalUpdatedAt(layout) : Date.now();
      const envelope = envelopeFromLayout(layout, deviceId, updatedAt);
      const created = await createSettingsQrImage(envelope);
      if (!created.ok || created.pixelMap === undefined) {
        this.releaseQrPixelMap();
        this.qrHint = created.message;
        return;
      }
      const prev = this.qrPixelMap;
      this.qrPixelMap = created.pixelMap;
      if (prev !== undefined) {
        try {
          prev.release();
        } catch (_e) {
        }
      }
      this.qrHint = '另一台设备打开本页，用扫一扫导入。分类较多时请改用 WebDAV。';
    } finally {
      this.qrBusy = false;
    }
  }

  private async onScanImport(): Promise<void> {
    if (!canScanSettingsQr()) {
      this.toast('当前设备不支持扫码');
      return;
    }
    const ctx = this.hostContext();
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      enableAlbum: true
    };
    try {
      const result = await scanBarcode.startScanForResult(ctx, options);
      const parsed = parseQrPayload(result.originalValue);
      if (!parsed.ok || parsed.envelope === undefined) {
        this.toast(parsed.message);
        return;
      }
      await this.applyImportedEnvelope(parsed.envelope, true);
    } catch (e) {
      const err = e as BusinessError;
      if (isScanUserCancel(err)) {
        return;
      }
      this.toast(`扫码失败：${err.message}`);
    }
  }

  private async applyImportedEnvelope(envelope: AppSettingsEnvelope, force: boolean): Promise<void> {
    const account = smartCategoryCurrentAccount();
    const local = await this.loadCurrentLayout();
    const applied = applyEnvelopeToAccount(envelope, account, layoutLocalUpdatedAt(local), force);
    if (!applied.ok || applied.layout === undefined) {
      this.toast(applied.message);
      return;
    }
    const saved = await smartCategorySaveLayout(this.hostContext(), applied.layout);
    if (!saved) {
      this.toast('保存失败');
      return;
    }
    this.toast(applied.message);
    await this.refreshQr();
  }

  private async onUpload(): Promise<void> {
    if (this.davBusy) {
      return;
    }
    this.davBusy = true;
    try {
      await this.persistWebDavForm();
      const account = smartCategoryCurrentAccount();
      if (account.length === 0) {
        this.toast('当前未登录');
        return;
      }
      const ctx = this.hostContext();
      const loaded = await this.loadCurrentLayout();
      const updatedAt = Date.now();
      const layout: SmartCategoryLayout = {
        account: loaded.account,
        custom: loaded.custom,
        sceneOrder: loaded.sceneOrder,
        infoOrder: loaded.infoOrder,
        customOrder: loaded.customOrder,
        updatedAt: updatedAt
      };
      const saved = await smartCategorySaveLayout(ctx, layout);
      if (!saved) {
        this.toast('保存本机时间戳失败');
        return;
      }
      const deviceId = await SessionPreferences.ensureWsDeviceId(ctx);
      const envelope = envelopeFromLayout(layout, deviceId, updatedAt);
      const res = await webDavPutJson(this.currentWebDavConfig(), serializeEnvelope(envelope));
      this.toast(res.ok ? '已上传到 WebDAV' : res.message);
      if (res.ok) {
        await this.refreshQr();
      }
    } finally {
      this.davBusy = false;
    }
  }

  private async onDownload(): Promise<void> {
    if (this.davBusy) {
      return;
    }
    this.davBusy = true;
    try {
      await this.persistWebDavForm();
      const res = await webDavGetJson(this.currentWebDavConfig());
      if (!res.ok) {
        this.toast(res.message);
        return;
      }
      const parsed = parseEnvelopeJson(res.body);
      if (!parsed.ok || parsed.envelope === undefined) {
        this.toast(parsed.message);
        return;
      }
      await this.applyImportedEnvelope(parsed.envelope, false);
    } finally {
      this.davBusy = false;
    }
  }

  private titleBarOriginalStyle(): HdsNavigationTitleBarStyle {
    const buttonBg: ResourceColor = this.canUseHds()
      ? fnHdsChromeButtonBackgroundColor()
      : fnHdsChromeButtonFallbackBackgroundColor();
    const buttonFg: ResourceColor = this.canUseHds()
      ? fnHdsChromeButtonForegroundColor()
      : $r('app.color.icon_primary');
    const textFg: ResourceColor = this.canUseHds()
      ? $r('app.color.text_primary')
      : $r('app.color.button_secondary_fg');
    return {
      backgroundStyle: fnHdsNavChromeBackgroundStyle(),
      contentStyle: {
        titleStyle: {
          mainTitleColor: $r('app.color.text_primary'),
          subTitleColor: $r('app.color.text_secondary')
        },
        menuStyle: {
          backgroundColor: buttonBg,
          iconColor: buttonFg,
          textColor: textFg
        },
        backIconStyle: {
          backgroundColor: buttonBg,
          iconColor: buttonFg
        }
      }
    };
  }

  private titleBarContent(): TitleBarContentOptions {
    const backIcon: HdsNavigationBackButtonItemOptions = {
      label: $r('app.string.cancel'),
      isEnabled: true,
      action: (): void => {
        this.getUIContext().getRouter().back();
      }
    };
    return {
      title: { mainTitle: $r('app.string.config_sync_title') },
      backIcon: backIcon
    };
  }

  @Builder
  private navigationContent() {
    Column()
      .width('100%')
      .height(0)
  }

  build() {
    Column() {
      Column() {
        HdsNavigation() {
          this.navigationContent()
        }
        .width('100%')
        .height(FN_HDS_NAV_CHROME_HEIGHT_VP)
        .mode(NavigationMode.Stack)
        .titleMode(HdsNavigationTitleMode.MINI)
        .hideBackButton(false)
        .titleBar(this.canUseHds() ? {
          padding: fnHdsNavTitleBarPadding(),
          avoidLayoutSafeArea: false,
          enableComponentSafeArea: false,
          style: {
            blurStrategy: BlurStrategy.ADAPTIVE,
            scrollEffectOpts: fnHdsNavChromeScrollEffectOpts(),
            // @SuppressWarnings compatibility
            systemMaterialEffect: fnHdsImmersiveSystemMaterialEffect(),
            originalStyle: this.titleBarOriginalStyle(),
            scrollEffectStyle: {
              backgroundStyle: fnHdsNavChromeScrolledBackgroundStyle()
            }
          },
          content: this.titleBarContent()
        } : {
          padding: fnHdsNavTitleBarPadding(),
          avoidLayoutSafeArea: false,
          enableComponentSafeArea: false,
          style: {
            blurStrategy: BlurStrategy.ADAPTIVE,
            scrollEffectOpts: fnHdsNavChromeScrollEffectOpts(),
            originalStyle: this.titleBarOriginalStyle(),
            scrollEffectStyle: {
              backgroundStyle: fnHdsNavChromeScrolledBackgroundStyle()
            }
          },
          content: this.titleBarContent()
        })
      }
      .width('100%')
      .padding({ top: this.systemTopInsetVp })

      Scroll() {
        Column({ space: 16 }) {
          Text($r('app.string.config_sync_qr_section'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Column({ space: 12 }) {
            if (this.qrPixelMap !== undefined) {
              Image(this.qrPixelMap)
                .width(220)
                .height(220)
                .objectFit(ImageFit.Contain)
                .borderRadius($r('app.float.radius_small'))
                .backgroundColor(Color.White)
            }

            Text(this.qrHint)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')

            FnPrimaryButton({
              text: $r('app.string.config_sync_scan'),
              action: (): void => {
                void this.onScanImport();
              }
            })
            .width('100%')
            .enabled(!this.qrBusy && !this.davBusy)
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.radius_medium'))
          .alignItems(HorizontalAlign.Center)

          Text($r('app.string.config_sync_webdav_section'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Column({ space: 12 }) {
            TextInput({ text: this.davUrl, placeholder: $r('app.string.config_sync_webdav_url_hint') })
              .enableAutoFill(false)
              .enableKeyboardOnFocus(false)
              .onChange((v: string) => {
                this.davUrl = v;
              })
              .width('100%')
              .height(44)
              .backgroundColor($r('app.color.page_background'))
              .borderRadius($r('app.float.radius_small'))
              .padding({ left: 12, right: 12 })

            TextInput({ text: this.davUser, placeholder: $r('app.string.config_sync_webdav_user') })
              .type(InputType.USER_NAME)
              .enableAutoFill(false)
              .enableKeyboardOnFocus(false)
              .onChange((v: string) => {
                this.davUser = v;
              })
              .width('100%')
              .height(44)
              .backgroundColor($r('app.color.page_background'))
              .borderRadius($r('app.float.radius_small'))
              .padding({ left: 12, right: 12 })

            TextInput({ text: this.davPassword, placeholder: $r('app.string.config_sync_webdav_password') })
              .type(InputType.Password)
              .enableAutoFill(false)
              .enableKeyboardOnFocus(false)
              .onChange((v: string) => {
                this.davPassword = v;
              })
              .width('100%')
              .height(44)
              .backgroundColor($r('app.color.page_background'))
              .borderRadius($r('app.float.radius_small'))
              .padding({ left: 12, right: 12 })

            TextInput({ text: this.davPath, placeholder: $r('app.string.config_sync_webdav_path_hint') })
              .enableAutoFill(false)
              .enableKeyboardOnFocus(false)
              .onChange((v: string) => {
                this.davPath = v;
              })
              .width('100%')
              .height(44)
              .backgroundColor($r('app.color.page_background'))
              .borderRadius($r('app.float.radius_small'))
              .padding({ left: 12, right: 12 })

            Row() {
              Text($r('app.string.config_sync_skip_cert'))
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.davSkipCert })
                .selectedColor($r('app.color.brand_primary'))
                .onChange((on: boolean) => {
                  this.davSkipCert = on;
                })
            }
            .width('100%')
            .height(44)
            .alignItems(VerticalAlign.Center)

            FnPrimaryButton({
              text: $r('app.string.config_sync_upload'),
              action: (): void => {
                void this.onUpload();
              }
            })
            .width('100%')
            .enabled(!this.davBusy)

            FnSecondaryButton({
              text: $r('app.string.config_sync_download'),
              action: (): void => {
                void this.onDownload();
              }
            })
            .width('100%')
            .enabled(!this.davBusy)
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius($r('app.float.radius_medium'))
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 12, y: 0 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: -8, y: 0 });
  }
}
