/**
 * 相册备份/同步设置（官方备份客户端 API + 本地策略）。
 * 子页用栈内切换，避免在大 Sheet 里再叠 bindSheet（目录偏好等会打不开）。
 */
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { AppSession } from '../auth/AppSession';
import { SessionPreferences } from '../auth/SessionPreferences';
import { fnDiagRecord } from '../common/FnDiagLog';
import { GalleryAutoSyncStore } from '../album/GalleryAutoSyncStore';
import { FnHdsSimpleChrome } from '../common/FnHdsSimpleChrome';
import { fnRequestReadImageVideoAccess, FnReadImageVideoAuth } from '../common/FnMediaPermission';
import {
  fnResolvedCardFill,
  FN_RESOLVED_ACCENT_KEY,
  FN_RESOLVED_CARD_BG_KEY,
  FN_RESOLVED_PAGE_BG_KEY,
  fnResolvedTextPrimary,
  FN_RESOLVED_TEXT_PRIMARY_KEY,
  fnResolvedTextSecondary,
  FN_RESOLVED_TEXT_SECONDARY_KEY
} from '../common/FnThemeColors';
import { PhotoBackupPathInfo, PhotoFolderListItem } from '../model/FnApiTypes';
import { ALBUM_BACKUP_FOLDER_MODE_OPTIONS, AlbumBackupFolderModeOption } from './AlbumBackupFolderModeCopy';
import { AlbumBackupSourcePicker } from './AlbumBackupSourcePicker';
import {
  AlbumBackupSettings,
  applyAlbumBackupSettings,
  cloneAlbumBackupSettings,
  FOLDER_MANAGE_MODE_LABELS,
  getAlbumBackupSettingsCached,
  loadAlbumBackupSettings,
  saveAlbumBackupSettings
} from './AlbumBackupSettings';

/** 页面打开后稍等再拉 NAS，避免和转场抢同一帧。 */
const SHEET_OPEN_DEFER_MS: number = 380;

/** 系统返回键交给页面：栈内先回上一级，栈底再关页面。 */
export class AlbumBackupPageBack {
  static pop: () => void = (): void => {};
}

type BackupSettingsSubPage = 'main' | 'folder' | 'mode' | 'source';

/** 设置行的副标题来源：@Builder 内按值传参不会刷新，这里用枚举在 Builder 体内读对应状态。 */
enum BackupRowSubtitle {
  SOURCE = 0,
  MODE = 1
}

function folderItemPath(item: PhotoFolderListItem): string {
  const rec = item as Record<string, Object | string | number | undefined | null>;
  const keys: string[] = [
    'folderPath', 'folder_path', 'path', 'filePath', 'file_path', 'fullPath', 'dirPath', 'dir', 'key'
  ];
  for (let i = 0; i < keys.length; i++) {
    const value = rec[keys[i]];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }
  return '';
}

function folderItemLabel(item: PhotoFolderListItem): string {
  const rec = item as Record<string, Object | string | number | undefined | null>;
  const nameKeys: string[] = ['name', 'dirName', 'fileName', 'title', 'label'];
  let name = '';
  for (let i = 0; i < nameKeys.length; i++) {
    const value = rec[nameKeys[i]];
    if (typeof value === 'string' && value.trim().length > 0) {
      name = value.trim();
      break;
    }
  }
  if (name.length > 0) {
    return name;
  }
  const path = folderItemPath(item);
  if (path.length === 0) {
    return '(未命名)';
  }
  const slash = path.lastIndexOf('/');
  if (slash >= 0 && slash < path.length - 1) {
    return path.substring(slash + 1);
  }
  return path;
}

@Component
export struct AlbumBackupSyncSheet {
  onCloseSheet: () => void = (): void => {};
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @StorageProp(FN_RESOLVED_TEXT_SECONDARY_KEY) private themeTextSecondary: string = '';
  @StorageProp(FN_RESOLVED_PAGE_BG_KEY) private pageBg: string = '#FFF4F7FB';
  @StorageProp(FN_RESOLVED_ACCENT_KEY) private accent: string = '#FF4A8BFF';
  @StorageProp(FN_RESOLVED_CARD_BG_KEY) private cardBg: string = '';
  @State private settings: AlbumBackupSettings = new AlbumBackupSettings();
  @State private busy: boolean = false;

  @State private folderChoices: PhotoFolderListItem[] = [];
  @State private locationLoading: boolean = false;
  @State private locationError: string = '';
  @State private navStack: BackupSettingsSubPage[] = ['main'];
  @State private sourceNavRight: string = '';
  @State private sourceSelectAllPulse: number = 0;
  private bootstrapTimerId: number = -1;
  private bootstrapGeneration: number = 0;
  /** 备份源 / 目录偏好的副标题。用 @State 承载：普通方法里读 settings 不会被 ArkUI 追踪到。 */
  @State private sourceSubtitle: string = '';
  @State private modeSubtitle: string = '';
  /** 是否已从磁盘读到真实设置。未读到之前不允许回写，避免用默认空列表覆盖磁盘。 */
  @State private settingsHydrated: boolean = false;
  /** 正在把整机现有照片记成已处理。避免连点两次各扫一遍。 */
  @State private ignoringExisting: boolean = false;

  aboutToAppear(): void {
    AlbumBackupPageBack.pop = (): void => {
      this.popNav();
    };
    this.bootstrapGeneration++;
    const gen = this.bootstrapGeneration;
    this.navStack = ['main'];
    this.sourceNavRight = '';
    this.sourceSelectAllPulse = 0;
    this.busy = false;

    this.settingsHydrated = false;
    applyAlbumBackupSettings(this.settings, getAlbumBackupSettingsCached());
    this.refreshSubtitles();
    fnDiagRecord('I', 'AlbumBackup', 'sheet open cached valid=' + String(this.settings.backupSourceFoldersValid));
    this.scheduleDeferredBootstrap(gen);
  }

  aboutToDisappear(): void {
    AlbumBackupPageBack.pop = (): void => {};
    this.bootstrapGeneration++;
    if (this.bootstrapTimerId >= 0) {
      clearTimeout(this.bootstrapTimerId);
      this.bootstrapTimerId = -1;
    }
    this.navStack = ['main'];
  }

  private currentNavPage(): BackupSettingsSubPage {
    return this.navStack[this.navStack.length - 1];
  }

  private pushNav(page: BackupSettingsSubPage): void {
    this.navStack = this.navStack.concat([page]);
  }

  private popNav(): void {
    if (this.navStack.length <= 1) {
      this.onCloseSheet();
      return;
    }
    this.navStack = this.navStack.slice(0, this.navStack.length - 1);
  }

  private popNavToMain(): void {
    if (this.navStack.length <= 1) {
      return;
    }
    this.navStack = ['main'];
  }

  private navBarTitle(): string {
    const page = this.currentNavPage();
    if (page === 'folder') {
      return '选择备份位置';
    }
    if (page === 'mode') {
      return '备份目录偏好';
    }
    if (page === 'source') {
      return '备份源';
    }
    return '备份设置';
  }

  private navBarRightLabel(): string {
    if (this.currentNavPage() === 'source') {
      return this.sourceNavRight;
    }
    return '';
  }

  private onNavBarRightTap(): void {
    if (this.currentNavPage() === 'source') {
      this.sourceSelectAllPulse++;
    }
  }

  private scheduleDeferredBootstrap(gen: number): void {
    if (this.bootstrapTimerId >= 0) {
      clearTimeout(this.bootstrapTimerId);
    }
    this.bootstrapTimerId = setTimeout((): void => {
      this.bootstrapTimerId = -1;
      if (gen !== this.bootstrapGeneration) {
        return;
      }
      void this.bootstrapFromDiskAndNas();
    }, SHEET_OPEN_DEFER_MS);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /**
   * 把当前手机上的照片记成已处理。确认后再扫整机。
   * 只影响现在登录的账号和 NAS，新拍或改过的照片仍会上传。
   */
  private async confirmIgnoreExisting(): Promise<void> {
    if (this.ignoringExisting) {
      return;
    }
    let proceed = false;
    try {
      const dlg = await this.getUIContext().getPromptAction().showDialog({
        title: '忽略现有照片',
        message: '当前手机上的照片会记成已处理，不再上传到现在登录的账号。之后只有新拍或改过的照片会上传。还没传到这个账号的旧照片也不会补传。',
        buttons: [
          { text: '取消', color: '#99000000' },
          { text: '忽略现有照片', color: '#FF2563EB' }
        ]
      });
      proceed = dlg.index === 1;
    } catch (_e) {
      return;
    }
    if (!proceed) {
      return;
    }
    const auth = await fnRequestReadImageVideoAccess(this.hostContext());
    if (auth !== FnReadImageVideoAuth.GRANTED) {
      this.toast('请允许访问相册后再忽略');
      return;
    }
    this.ignoringExisting = true;
    try {
      const total = await GalleryAutoSyncStore.ignoreExistingLibrary(this.hostContext());
      if (total === 0) {
        this.toast('没有读到本机照片，没有忽略');
        return;
      }
      this.toast('已忽略现有照片，之后只上传新拍或改过的');
    } catch (e) {
      const msg = String(e);
      fnDiagRecord('W', 'AlbumBackup', `ignore existing failed ${msg.substring(0, 80)}`);
      if (msg.indexOf('正在扫描') >= 0) {
        this.toast('正在扫描，请稍后再忽略');
      } else {
        this.toast('忽略失败，现有照片仍可能被上传');
      }
    } finally {
      this.ignoringExisting = false;
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (_e) {
    }
  }

  private async persistLocal(): Promise<void> {
    if (!this.settingsHydrated) {
      // 磁盘值还没读出来时先不回写，避免用默认空列表（=备份所有文件夹）覆盖磁盘上的备份源。
      return;
    }
    await saveAlbumBackupSettings(this.hostContext(), this.settings);
  }

  private backupSourceSubtitle(): string {
    if (this.settingsHydrated && !this.settings.backupSourceFoldersValid) {
      if (this.settings.backupSourceFoldersRecoverablePresent) {
        return '读取失败，可恢复上次选择';
      }
      return '读取失败，请重新选择';
    }
    if (this.settings.backupSourceFolders.length === 0) {
      return '备份所有文件夹';
    }
    return `已选 ${this.settings.backupSourceFolders.length} 个文件夹`;
  }

  private folderModeSubtitle(): string {
    const idx = this.settings.folderManageMode - 1;
    if (idx >= 0 && idx < FOLDER_MANAGE_MODE_LABELS.length) {
      return FOLDER_MANAGE_MODE_LABELS[idx];
    }
    return FOLDER_MANAGE_MODE_LABELS[3];
  }

  /** settings 变化后同步两行副标题。 */
  private refreshSubtitles(): void {
    this.sourceSubtitle = this.backupSourceSubtitle();
    this.modeSubtitle = this.folderModeSubtitle();
  }

  private async bootstrapFromDiskAndNas(): Promise<void> {
    const ctx = this.hostContext();
    const loaded = await loadAlbumBackupSettings(ctx);
    const merged = cloneAlbumBackupSettings(loaded);
    merged.deviceName = this.resolveDeviceNameFrom(merged);
    // 先置 hydrated 再写字段：ArkUI 可能同步重建，此时必须已经知道「已读到磁盘值」。
    this.settingsHydrated = true;
    applyAlbumBackupSettings(this.settings, merged);
    this.refreshSubtitles();
    fnDiagRecord('I', 'AlbumBackup', 'sheet hydrated valid=' + String(merged.backupSourceFoldersValid) +
      ' count=' + String(merged.backupSourceFolders.length));
    await this.refreshFromNas();
  }

  private resolveDeviceNameFrom(base: AlbumBackupSettings): string {
    const cached = base.deviceName.trim();
    if (cached.length > 0 && cached !== 'FMphoto') {
      return cached;
    }
    try {
      const m = deviceInfo.marketName?.trim() ?? '';
      if (m.length > 0) {
        return m;
      }
      const p = deviceInfo.productModel?.trim() ?? '';
      if (p.length > 0) {
        return p;
      }
    } catch (_e) {
    }
    return 'FMphoto';
  }

  private absorbBackupPath(target: AlbumBackupSettings, info: PhotoBackupPathInfo | undefined): boolean {
    if (info === undefined) {
      return false;
    }
    let wrote = false;
    const display = info.displayPath.trim();
    const device = info.deviceBackupPath.trim().length > 0 ? info.deviceBackupPath.trim() : info.folderPath.trim();
    if (display.length > 0) {
      target.displayPath = display;
      wrote = true;
    }
    if (device.length > 0) {
      target.deviceBackupPath = device;
      wrote = true;
    }
    if (target.displayPath.trim().length === 0 && target.deviceBackupPath.trim().length > 0) {
      target.displayPath = target.deviceBackupPath;
    }
    return wrote;
  }

  /**
   * 打开设置页后自动拉一次 NAS 备份信息（官方应用也是登录后自动拉一次，之后不再手动刷新）。
   * 失败信息统一走 locationError（显示在备份位置下方），不在顶部加状态行，避免把控件整体下推。
   */
  private async refreshFromNas(): Promise<void> {
    const client = AppSession.getClient();
    if (client === null) {
      this.locationError = '未登录';
      return;
    }
    this.locationLoading = true;
    try {
      const ctx = this.hostContext();
      const deviceId = await SessionPreferences.ensureWsDeviceId(ctx);
      const deviceName = this.resolveDeviceNameFrom(this.settings);
      // 请求期间用户可能改开关/目录偏好：这里只留一份请求开始时的快照用于判断，
      // 结果写回时只碰 NAS 相关字段，绝不整份覆盖用户的新选择。
      const snapshot = cloneAlbumBackupSettings(this.settings);

      let folderChoices: PhotoFolderListItem[] = [];
      let folderMessage = '';
      const got = await client.getPhotoFolderList();
      if (got.success && got.data !== undefined && got.data.list !== undefined && got.data.list.length > 0) {
        folderChoices = got.data.list;
      } else {
        const posted = await client.postPhotoFolderList();
        if (posted.success && posted.data !== undefined && posted.data.list !== undefined &&
          posted.data.list.length > 0) {
          folderChoices = posted.data.list;
        } else if (!got.success && !posted.success) {
          folderMessage = got.message ?? posted.message ?? '备份位置获取失败';
        }
      }

      const pathHolder = new AlbumBackupSettings();
      const v2 = await client.fetchPhotoBackupPathV2(deviceId, 20000, deviceName);
      this.absorbBackupPath(pathHolder, v2.success ? v2.data : undefined);
      const v1 = await client.fetchPhotoBackupPathV1(deviceId, deviceName);
      this.absorbBackupPath(pathHolder, v1.success ? v1.data : undefined);
      let pathMessage = '';
      if (!v2.success && (v2.message ?? '').length > 0) {
        pathMessage = v2.message ?? '';
      }
      if (!v1.success && (v1.message ?? '').length > 0) {
        pathMessage = v1.message ?? pathMessage;
      }
      const keepLocal = snapshot.displayPath.trim().length > 0 || snapshot.deviceBackupPath.trim().length > 0;
      if (!keepLocal && pathHolder.displayPath.trim().length === 0 && snapshot.deviceBackupPath.trim().length === 0) {
        // 还没有备份位置时，在 NAS 上创建默认备份目录（官方应用登录后自动完成这一步）。
        const initRes = await client.initDefaultPhotoBackupFolder(deviceId, 20000, deviceName);
        if (initRes.success) {
          const againV2 = await client.fetchPhotoBackupPathV2(deviceId, 20000, deviceName);
          this.absorbBackupPath(pathHolder, againV2.success ? againV2.data : undefined);
          const againV1 = await client.fetchPhotoBackupPathV1(deviceId, deviceName);
          this.absorbBackupPath(pathHolder, againV1.success ? againV1.data : undefined);
          if (pathHolder.displayPath.trim().length > 0 || pathHolder.deviceBackupPath.trim().length > 0) {
            pathMessage = '';
          }
        } else {
          pathMessage = initRes.message ?? pathMessage;
        }
      } else {
        pathMessage = '';
      }
      // 只回写 NAS 决定的字段，其余字段保持用户当前值（请求期间改过的不能被盖掉）
      if (pathHolder.displayPath.trim().length > 0) {
        this.settings.displayPath = pathHolder.displayPath.trim();
      }
      if (pathHolder.deviceBackupPath.trim().length > 0) {
        this.settings.deviceBackupPath = pathHolder.deviceBackupPath.trim();
      }
      if (this.settings.displayPath.trim().length === 0 && this.settings.deviceBackupPath.trim().length > 0) {
        this.settings.displayPath = this.settings.deviceBackupPath;
      }
      if (deviceName.trim().length > 0) {
        this.settings.deviceName = deviceName;
      }

      this.folderChoices = folderChoices.length > 0 ? folderChoices : this.folderChoices;
      this.refreshSubtitles();
      const stillEmpty = this.settings.displayPath.trim().length === 0 && this.folderChoices.length === 0;
      if (stillEmpty) {
        const reason = pathMessage.length > 0 ? pathMessage : folderMessage;
        this.locationError = reason.length > 0 ? `备份位置获取失败：${reason}` : '备份位置获取失败';
      } else {
        this.locationError = '';
      }
      await this.persistLocal();
    } catch (e) {
      this.locationError = `备份位置获取失败：${String(e)}`;
    } finally {
      this.locationLoading = false;
    }
  }

  private async onPickStorageFolder(item: PhotoFolderListItem): Promise<void> {
    const path = folderItemPath(item);
    if (path.length === 0) {
      this.toast('无效目录');
      return;
    }
    const client = AppSession.getClient();
    if (client === null) {
      return;
    }
    this.busy = true;
    try {
      const ctx = this.hostContext();
      const deviceId = await SessionPreferences.ensureWsDeviceId(ctx);
      const deviceName = this.resolveDeviceNameFrom(this.settings);
      const addRes = await client.addPhotoBackupFolder(deviceId, path, 20000, deviceName);
      if (!addRes.success) {
        this.toast(addRes.message ?? '设置目录失败');
        return;
      }
      const picked = cloneAlbumBackupSettings(this.settings);
      picked.deviceBackupPath = path;
      picked.displayPath = path;
      applyAlbumBackupSettings(this.settings, picked);
      this.refreshSubtitles();
      await this.persistLocal();
      this.popNavToMain();
      await this.refreshFromNas();
      if (this.settings.displayPath.trim().length === 0) {
        const again = cloneAlbumBackupSettings(this.settings);
        again.deviceBackupPath = path;
        again.displayPath = path;
        applyAlbumBackupSettings(this.settings, again);
        this.refreshSubtitles();
        await this.persistLocal();
      }
      this.toast('备份位置已更新');
    } finally {
      this.busy = false;
    }
  }

  private async onConfirmBackupSources(keys: string[]): Promise<void> {
    const client = AppSession.getClient();
    if (client === null) {
      return;
    }
    if (!this.settingsHydrated) {
      // 先把磁盘设置读出来再操作，避免在默认空列表上做同步。
      await this.bootstrapFromDiskAndNas();
    }
    if (!this.settings.backupSourceFoldersValid && keys.length === 0) {
      // 原列表不可读时不允许空选确认：空列表会被当成「备份所有文件夹」并同步到 NAS。
      this.toast('请至少选择一个要备份的文件夹');
      return;
    }
    const ctx = this.hostContext();
    const deviceId = await SessionPreferences.ensureWsDeviceId(ctx);
    const deviceName = this.resolveDeviceNameFrom(this.settings);
    const backupPath = this.settings.deviceBackupPath.trim();
    if (backupPath.length === 0) {
      this.toast('请先选择备份位置');
      return;
    }
    this.busy = true;
    try {
      // 先写本机：备份源首先是本机「哪些相册需要备份」的记录，必须落盘。
      this.settings.backupSourceFolders = keys.slice();
      this.settings.backupSourceFoldersValid = true;
      this.refreshSubtitles();
      await this.persistLocal();
      // 再尽力登记到 NAS。部分 NAS 版本没有实现 /photo/backup/device/merge（会回 501），
      // 这时不能因为 NAS 拒绝就丢弃用户刚选的内容。
      const res = await client.mergePhotoBackupDeviceFolders(deviceId, deviceName, backupPath, keys);
      this.popNavToMain();
      if (res.success) {
        this.toast('备份源已保存');
      } else {
        this.toast('已保存到本机；NAS 未接受备份源登记');
      }
    } finally {
      this.busy = false;
    }
  }

  private async openBackupSourcePage(): Promise<void> {
    const auth = await fnRequestReadImageVideoAccess(this.hostContext());
    if (auth !== FnReadImageVideoAuth.GRANTED) {
      this.toast('请选择允许访问相册，或在下一步中授权');
    }
    this.pushNav('source');
  }

  @Builder
  private settingsToggle(title: Resource, subtitle: Resource, isOn: boolean, onChange: (v: boolean) => void) {
    Row() {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(16)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Text(subtitle)
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(this.accent)
        .onChange((on: boolean): void => {
          onChange(on);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 设置行。副标题不能用参数传进来：@Builder 默认按值传参，状态变量变化不会刷新
   * Builder 内的 UI（见 arkts-builder「按值传递参数」）。所以按 kind 在 Builder 体内
   * 直接读 @State。
   */
  @Builder
  private ignoreExistingRow() {
    Row() {
      Column({ space: 4 }) {
        Text($r('app.string.album_backup_ignore_existing_title'))
          .fontSize(16)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Text(this.ignoringExisting ? '正在读取本机照片…' : $r('app.string.album_backup_ignore_existing_sub'))
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      void this.confirmIgnoreExisting();
    })
  }

  @Builder
  private navRow(title: Resource, kind: BackupRowSubtitle, onTap: () => void) {
    Row() {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(16)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Text(kind === BackupRowSubtitle.SOURCE ? this.sourceSubtitle : this.modeSubtitle)
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
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick((): void => {
      onTap();
    })
  }

  @Builder
  private mainSettingsBody() {
    Scroll() {
        Column({ space: 12 }) {
        Column() {
          Text(this.settings.displayPath.length > 0 ? this.settings.displayPath : '未设置备份位置')
            .fontSize(15)
            .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.locationError.length > 0 ? this.locationError : $r('app.string.album_backup_location_hint'))
            .fontSize(12)
            .fontColor(this.locationError.length > 0 ? '#E11D48' : this.accent)
            .margin({ top: 6 })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(fnResolvedCardFill(this.cardBg))
        .borderRadius($r('app.float.radius_medium'))
        .onClick((): void => {
          this.pushNav('folder');
        })

        Column() {
          this.navRow($r('app.string.album_backup_source_title'), BackupRowSubtitle.SOURCE, (): void => {
            void this.openBackupSourcePage();
          })
          Divider().strokeWidth(0.5).opacity(0.2)
          this.navRow($r('app.string.album_backup_folder_mode_title'), BackupRowSubtitle.MODE, (): void => {
            this.pushNav('mode');
          })
        }
        .width('100%')
        .backgroundColor(fnResolvedCardFill(this.cardBg))
        .borderRadius($r('app.float.radius_medium'))
        .clip(true)

        Text($r('app.string.album_backup_other_section'))
          .fontSize(13)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .width('100%')
          .padding({ left: 4 })

        Column() {
          this.settingsToggle(
            $r('app.string.album_backup_photos_only_title'),
            $r('app.string.album_backup_photos_only_sub'),
            this.settings.photosOnly,
            (on: boolean): void => {
              this.settings.photosOnly = on;
              void this.persistLocal();
            }
          )
          Divider().strokeWidth(0.5).opacity(0.2)
          this.settingsToggle(
            $r('app.string.album_backup_cellular_title'),
            $r('app.string.album_backup_cellular_sub'),
            this.settings.useCellularData,
            (on: boolean): void => {
              this.settings.useCellularData = on;
              void this.persistLocal();
            }
          )
          Divider().strokeWidth(0.5).opacity(0.2)
          this.settingsToggle(
            $r('app.string.album_backup_low_battery_title'),
            $r('app.string.album_backup_low_battery_sub'),
            this.settings.stopWhenBatteryLow,
            (on: boolean): void => {
              this.settings.stopWhenBatteryLow = on;
              void this.persistLocal();
            }
          )
          Divider().strokeWidth(0.5).opacity(0.2)
          this.settingsToggle(
            $r('app.string.album_backup_sync_album_title'),
            $r('app.string.album_backup_sync_album_sub'),
            this.settings.syncCreateAlbum,
            (on: boolean): void => {
              this.settings.syncCreateAlbum = on;
              void this.persistLocal();
            }
          )
          Divider().strokeWidth(0.5).opacity(0.2)
          this.settingsToggle(
            $r('app.string.album_backup_rename_title'),
            $r('app.string.album_backup_rename_sub'),
            this.settings.renameStrategy > 0,
            (on: boolean): void => {
              this.settings.renameStrategy = on ? 1 : 0;
              void this.persistLocal();
            }
          )
          Divider().strokeWidth(0.5).opacity(0.2)
          this.ignoreExistingRow()
        }
        .width('100%')
        .backgroundColor(fnResolvedCardFill(this.cardBg))
        .borderRadius($r('app.float.radius_medium'))
        .clip(true)
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 32 })
        .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  @Builder
  private folderPickerBody() {
    Column() {
      if (this.locationLoading && this.folderChoices.length === 0) {
        Text('正在读取备份位置…')
          .fontSize(14)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .padding(20)
      } else if (this.folderChoices.length === 0) {
        Text(this.locationError.length > 0 ? this.locationError : '暂无可选目录')
          .fontSize(14)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .padding(20)
      } else {
        List() {
          ForEach(this.folderChoices, (item: PhotoFolderListItem, index: number) => {
            ListItem() {
              Column({ space: 4 }) {
                Text(folderItemLabel(item))
                  .fontSize(16)
                  .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
                Text(folderItemPath(item))
                  .fontSize(12)
                  .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .onClick((): void => {
                void this.onPickStorageFolder(item);
              })
            }
          }, (item: PhotoFolderListItem, index: number) => `${index}_${folderItemPath(item)}`)
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private modeOptionRow(opt: AlbumBackupFolderModeOption) {
    Column({ space: 8 }) {
      Row() {
        Text(opt.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
          .layoutWeight(1)
        if (this.settings.folderManageMode === opt.mode) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(20)
            .fontColor([this.accent])
        }
      }
      .width('100%')
      Text(opt.description)
        .fontSize(13)
        .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
        .width('100%')
      Text(opt.example)
        .fontSize(12)
        .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
        .opacity(0.85)
        .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .onClick((): void => {
      this.settings.folderManageMode = opt.mode;
      this.refreshSubtitles();
      void this.persistLocal();
      this.popNav();
    })
  }

  @Builder
  private modePickerBody() {
    Column() {
      Scroll() {
        Column() {
          ForEach(ALBUM_BACKUP_FOLDER_MODE_OPTIONS, (opt: AlbumBackupFolderModeOption) => {
            this.modeOptionRow(opt)
            Divider().strokeWidth(0.5).opacity(0.15)
          }, (opt: AlbumBackupFolderModeOption) => `mode_${opt.mode}`)
        }
        .width('100%')
        .padding({ bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private navBody() {
    if (this.currentNavPage() === 'source') {
      AlbumBackupSourcePicker({
        initialSelectedKeys: this.settings.backupSourceFolders,
        initialSelectionKnown: this.settings.backupSourceFoldersValid,
        recoverableKeys: this.settings.backupSourceFoldersRecoverable,
        recoverablePresent: this.settings.backupSourceFoldersRecoverablePresent,
        accentColor: this.accent,
        selectAllPulse: this.sourceSelectAllPulse,
        onSelectAllLabelChange: (label: string): void => {
          this.sourceNavRight = label;
        },
        onConfirm: (keys: string[]): void => {
          void this.onConfirmBackupSources(keys);
        }
      })
        .layoutWeight(1)
        .width('100%')
    } else if (this.currentNavPage() === 'mode') {
      Column() {
        this.modePickerBody()
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    } else if (this.currentNavPage() === 'folder') {
      Column() {
        this.folderPickerBody()
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    } else {
      Column() {
        this.mainSettingsBody()
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
  }

  build() {
    Column() {
      FnHdsSimpleChrome({
        title: this.navBarTitle(),
        rightText: this.navBarRightLabel(),
        rightIcon: $r('sys.symbol.checkmark_circle'),
        topSafeInsetVp: 0,
        onBack: (): void => {
          this.popNav();
        },
        onRightClick: (): void => {
          this.onNavBarRightTap();
        }
      })
      this.navBody()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }
}
