/**
 * 配置同步：二维码导出/导入 + WebDAV 上传/下载智能分类与相册布局。
 */
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  HdsNavigation,
  HdsNavigationBackButtonItemOptions,
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
  fnHdsMiniTitleBarOptions,
  FnPrimaryButton,
  FnSecondaryButton,
  FN_HDS_NAV_CHROME_HEIGHT_VP
} from '../common/FnUiCommon';
import {
  fnCanUseHdsImmersive,
  FN_IMMERSIVE_LIGHT_STORAGE_KEY
} from '../common/FnImmersiveSettings';
import { SessionPreferences, LoginFormDefaults, StoredSession, upsertSavedUser } from '../auth/SessionPreferences';
import { AppSession } from '../auth/AppSession';
import { extractFnId } from '../network/FnConnectApi';
import { wsDeviceDisplayCode } from '../network/FnWsDeviceId';
import {
  smartCategoryCurrentAccount,
  smartCategoryEmptyLayout,
  smartCategoryLoadLayout,
  smartCategorySaveLayout,
  SmartCategoryLayout
} from '../album/SmartCategoryLayoutPreferences';
import {
  AppSettingsAlbumsHome,
  AppSettingsEnvelope,
  AppSettingsLogin,
  applyEnvelopeToAccount,
  emptyAlbumsHomeConfig,
  envelopeFromLayout,
  layoutLocalUpdatedAt,
  loginConfigHasContent,
  parseEnvelopeJson,
  parseQrPayload,
  serializeEnvelope,
  settingsNasMismatchMessage,
  settingsNasTokensFromLogin
} from '../sync/AppSettingsEnvelope';
import { albumsHomeApplyLayoutFromCtx, albumsHomeSnapshotFromCtx } from '../album/AlbumsHomeTileOrderPreferences';
import { mediaCategoryApplyOrderKeys, mediaCategorySavedOrder } from '../album/MediaCategoryOrderPreferences';
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

/** TextInput.text 只在创建时生效；父级异步回填要用本地 @State + $$。 */
@Component
struct ConfigDavTextField {
  @Prop @Watch('onSeedChanged') seedText: string = '';
  @Prop placeholder: Resource = $r('app.string.config_sync_webdav_url_hint');
  @Prop inputType: InputType = InputType.Normal;
  onChange: (value: string) => void = (_: string) => {};
  @State private inputText: string = '';

  aboutToAppear(): void {
    this.inputText = this.seedText;
  }

  private onSeedChanged(): void {
    if (this.inputText !== this.seedText) {
      this.inputText = this.seedText;
    }
  }

  build() {
    TextInput({ text: $$this.inputText, placeholder: this.placeholder })
      .type(this.inputType)
      .enableAutoFill(false)
      .enableKeyboardOnFocus(false)
      .onChange((value: string): void => {
        this.inputText = value;
        this.onChange(value);
      })
      .width('100%')
      .height(44)
      .backgroundColor($r('app.color.page_background'))
      .borderRadius($r('app.float.radius_small'))
      .padding({ left: 12, right: 12 })
  }
}

@Entry
@Component
struct ConfigSyncPage {
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(FN_IMMERSIVE_LIGHT_STORAGE_KEY) private immersiveLightEnabled: boolean = true;
  @State private qrPixelMap: image.PixelMap | undefined = undefined;
  @State private qrHint: string = '正在生成二维码…';
  @State private deviceCode: string = '';
  @State private davUrl: string = '';
  @State private davUser: string = '';
  @State private davPassword: string = '';
  @State private davPath: string = APP_SETTINGS_WEBDAV_DEFAULT_PATH;
  @State private davSkipCert: boolean = true;
  @State private davHydrated: boolean = false;
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
    if (!this.davHydrated) {
      return;
    }
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
    this.davHydrated = true;
    await this.refreshQr();
  }

  private async loadCurrentLayout(): Promise<SmartCategoryLayout> {
    return await smartCategoryLoadLayout(this.hostContext(), smartCategoryCurrentAccount());
  }

  private async loadAlbumsHomeSlice(): Promise<AppSettingsAlbumsHome> {
    const ctx = this.hostContext();
    const snap = await albumsHomeSnapshotFromCtx(ctx);
    const mediaOrder = await mediaCategorySavedOrder(ctx);
    const slice = emptyAlbumsHomeConfig();
    slice.tileOrder = snap.order;
    slice.hidden = snap.hidden;
    slice.mediaOrder = mediaOrder;
    return slice;
  }

  private async loadLoginConfig(): Promise<AppSettingsLogin> {
    const ctx = this.hostContext();
    const d: LoginFormDefaults = await SessionPreferences.loadLoginFormDefaults(ctx);
    const stored = await SessionPreferences.load(ctx);
    let fnId = d.fnIdInput.trim();
    let domain = d.domainInput.trim();
    let lan = d.lanInput.trim();
    let publicIp = d.publicIpInput.trim();
    let publicIpv6 = d.publicIpv6Input.trim();
    let username = d.username.trim();
    let endpointPref = d.loginEndpointPreference.trim().length > 0 ? d.loginEndpointPreference : 'auto';
    let useHttps = d.useHttps;
    if (stored !== null) {
      if (stored.fnIdInput.trim().length > 0) {
        fnId = stored.fnIdInput.trim();
      }
      if (stored.domainInput.trim().length > 0) {
        domain = stored.domainInput.trim();
      }
      if (stored.lanInput.trim().length > 0) {
        lan = stored.lanInput.trim();
      }
      if (stored.publicIpInput.trim().length > 0) {
        publicIp = stored.publicIpInput.trim();
      }
      if (stored.publicIpv6Input.trim().length > 0) {
        publicIpv6 = stored.publicIpv6Input.trim();
      }
      if (stored.account.trim().length > 0) {
        username = stored.account.trim();
      }
      if (stored.loginEndpointPreference.trim().length > 0) {
        endpointPref = stored.loginEndpointPreference.trim();
      }
      useHttps = stored.useHttps;
      if (fnId.length === 0) {
        const fromRelay = extractFnId(stored.endpointRelayUrl);
        const fromBase = extractFnId(stored.baseUrl);
        fnId = fromRelay.length > 0 ? fromRelay : fromBase;
      }
    }
    return {
      fnId: fnId,
      domain: domain,
      lan: lan,
      publicIp: publicIp,
      publicIpv6: publicIpv6,
      username: username,
      endpointPref: endpointPref,
      useHttps: useHttps,
      rememberPassword: d.rememberPassword,
      password: d.rememberPassword ? d.password : '',
      users: d.savedUsers
    };
  }

  private async persistImportedLogin(login: AppSettingsLogin): Promise<boolean> {
    if (!loginConfigHasContent(login)) {
      return false;
    }
    const existing = await SessionPreferences.loadLoginFormDefaults(this.hostContext());
    let users = login.users.length > 0 ? login.users : existing.savedUsers;
    if (login.username.length > 0) {
      users = upsertSavedUser(users, login.username, login.rememberPassword ? login.password : '', login.rememberPassword);
    }
    await SessionPreferences.saveLoginFormDefaults(this.hostContext(), {
      fnIdInput: login.fnId,
      domainInput: login.domain,
      lanInput: login.lan,
      publicIpInput: login.publicIp,
      publicIpv6Input: login.publicIpv6,
      loginEndpointPreference: login.endpointPref.length > 0 ? login.endpointPref : 'auto',
      username: login.username,
      password: login.rememberPassword ? login.password : '',
      useHttps: login.useHttps,
      rememberPassword: login.rememberPassword,
      savedUsers: users
    });
    return true;
  }

  private async refreshQr(): Promise<void> {
    if (this.qrBusy) {
      return;
    }
    this.qrBusy = true;
    try {
      const account = smartCategoryCurrentAccount();
      const layout = account.length > 0 ? await this.loadCurrentLayout() : smartCategoryEmptyLayout('');
      const deviceId = await SessionPreferences.ensureWsDeviceId(this.hostContext());
      this.deviceCode = wsDeviceDisplayCode(deviceId);
      const updatedAt = layoutLocalUpdatedAt(layout) > 0 ? layoutLocalUpdatedAt(layout) : Date.now();
      const login = await this.loadLoginConfig();
      const albumsHome = await this.loadAlbumsHomeSlice();
      const envelope = envelopeFromLayout(layout, deviceId, updatedAt, login, albumsHome);
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

  private nasExtraUrlsFromStored(stored: StoredSession | null): string[] {
    if (stored === null) {
      return [];
    }
    return [
      stored.baseUrl,
      stored.fnIdInput,
      stored.domainInput,
      stored.lanInput,
      stored.publicIpInput,
      stored.publicIpv6Input,
      stored.endpointPublicUrl,
      stored.endpointPublicDomainUrl,
      stored.endpointPublicIpUrl,
      stored.endpointLanUrl,
      stored.endpointLanIpv6Url,
      stored.endpointPublicIpv6Url,
      stored.endpointRelayUrl
    ];
  }

  private async currentNasStored(): Promise<StoredSession | null> {
    const live = AppSession.getStored();
    if (live !== null) {
      return live;
    }
    return await SessionPreferences.load(this.hostContext());
  }

  private async applyImportedEnvelope(envelope: AppSettingsEnvelope, force: boolean): Promise<void> {
    const stored = await this.currentNasStored();
    const localLogin = await this.loadLoginConfig();
    const mismatch = settingsNasMismatchMessage(
      settingsNasTokensFromLogin(localLogin, this.nasExtraUrlsFromStored(stored)),
      settingsNasTokensFromLogin(envelope.login)
    );
    if (mismatch.length > 0) {
      this.toast(mismatch);
      return;
    }
    const loginApplied = await this.persistImportedLogin(envelope.login);
    const account = smartCategoryCurrentAccount();
    if (account.length === 0) {
      this.toast(loginApplied ? '已导入登录配置' : '当前未登录，无法导入分类');
      return;
    }
    const local = await this.loadCurrentLayout();
    const applied = applyEnvelopeToAccount(envelope, account, layoutLocalUpdatedAt(local), force);
    if (!applied.ok || applied.layout === undefined) {
      this.toast(loginApplied ? `登录配置已导入。${applied.message}` : applied.message);
      return;
    }
    const saved = await smartCategorySaveLayout(this.hostContext(), applied.layout);
    if (!saved) {
      this.toast(loginApplied ? '登录配置已导入，分类保存失败' : '保存失败');
      return;
    }
    if (applied.albumsHomePresent) {
      await albumsHomeApplyLayoutFromCtx(
        this.hostContext(),
        applied.albumsHome.tileOrder,
        applied.albumsHome.hidden
      );
      await mediaCategoryApplyOrderKeys(this.hostContext(), applied.albumsHome.mediaOrder);
    }
    this.toast(loginApplied ? `${applied.message}；登录配置已同步` : applied.message);
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
      const login = await this.loadLoginConfig();
      const albumsHome = await this.loadAlbumsHomeSlice();
      const envelope = envelopeFromLayout(layout, deviceId, updatedAt, login, albumsHome);
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
        .titleBar(fnHdsMiniTitleBarOptions(this.canUseHds(), this.titleBarContent(), false))
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

            if (this.deviceCode.length > 0) {
              Column({ space: 4 }) {
                Text($r('app.string.config_sync_device_code_label'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                Text(this.deviceCode)
                  .fontSize(22)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .letterSpacing(2)
              }
              .alignItems(HorizontalAlign.Center)
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
            ConfigDavTextField({
              seedText: this.davUrl,
              placeholder: $r('app.string.config_sync_webdav_url_hint'),
              inputType: InputType.Normal,
              onChange: (v: string): void => {
                this.davUrl = v;
              }
            })
            ConfigDavTextField({
              seedText: this.davUser,
              placeholder: $r('app.string.config_sync_webdav_user'),
              inputType: InputType.USER_NAME,
              onChange: (v: string): void => {
                this.davUser = v;
              }
            })
            ConfigDavTextField({
              seedText: this.davPassword,
              placeholder: $r('app.string.config_sync_webdav_password'),
              inputType: InputType.Password,
              onChange: (v: string): void => {
                this.davPassword = v;
              }
            })
            ConfigDavTextField({
              seedText: this.davPath,
              placeholder: $r('app.string.config_sync_webdav_path_hint'),
              inputType: InputType.Normal,
              onChange: (v: string): void => {
                this.davPath = v;
              }
            })

            Row() {
              Text($r('app.string.config_sync_skip_cert'))
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: $$this.davSkipCert })
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
