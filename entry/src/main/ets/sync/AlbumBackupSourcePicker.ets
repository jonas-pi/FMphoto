/**
 * 备份源选择页（本机相册目录 + 缩略图网格）。
 */
import { common } from '@kit.AbilityKit';
import { FnPrimaryButton, FnSecondaryButton } from '../common/FnUiCommon';
import { fnOpenReadImageVideoSettings, FnReadImageVideoAuth } from '../common/FnMediaPermission';
import {
  fnResolvedCardFill,
  FN_RESOLVED_CARD_BG_KEY,
  FN_RESOLVED_PAGE_BG_KEY,
  fnResolvedTextPrimary,
  FN_RESOLVED_TEXT_PRIMARY_KEY,
  fnResolvedTextSecondary,
  FN_RESOLVED_TEXT_SECONDARY_KEY
} from '../common/FnThemeColors';
import {
  albumBackupMergeKey,
  displayAlbumFolderName,
  LocalAlbumSummary,
  scanLocalBackupSourceAlbums
} from './AlbumBackupLocalSources';

@Component
struct AlbumBackupAlbumTile {
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @Prop album: LocalAlbumSummary = new LocalAlbumSummary();
  @Prop large: boolean = false;
  @Prop mergeKey: string = '';
  @Prop selected: boolean = false;
  @Prop accentColor: string = '#FF4A8BFF';
  onToggle: (key: string) => void = (_: string): void => {};

  private thumbHeight(): number {
    return this.large ? 112 : 104;
  }

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.album.coverAssetUri.length > 0) {
          Image(this.album.coverAssetUri)
            .width('100%')
            .height(this.thumbHeight())
            .objectFit(ImageFit.Cover)
            .borderRadius(12)
            .backgroundColor('#FFE8ECF0')
        } else {
          Column()
            .width('100%')
            .height(this.thumbHeight())
            .borderRadius(12)
            .backgroundColor('#FFE8ECF0')
        }

        Column() {
          Row() {
            if (this.selected) {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                .fontSize(22)
                .fontColor([this.accentColor])
            } else {
              SymbolGlyph($r('sys.symbol.circle'))
                .fontSize(22)
                .fontColor([Color.White])
            }
            Blank()
          }
          .width('100%')

          Blank()
            .layoutWeight(1)

          Row() {
            Blank()
            Text(String(this.album.totalCount))
              .fontSize(11)
              .fontColor(Color.White)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .backgroundColor('#99000000')
              .borderRadius(10)
          }
          .width('100%')
        }
        .width('100%')
        .height(this.thumbHeight())
        .padding(6)
      }
      .width('100%')
      .height(this.thumbHeight())

      Text(displayAlbumFolderName(this.album))
        .fontSize(13)
        .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(18)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .constraintSize({ maxHeight: this.large ? 148 : 140 })
    .onClick((): void => {
      this.onToggle(this.mergeKey);
    })
  }
}

@Component
export struct AlbumBackupSourcePicker {
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @StorageProp(FN_RESOLVED_TEXT_SECONDARY_KEY) private themeTextSecondary: string = '';
  @StorageProp(FN_RESOLVED_PAGE_BG_KEY) private pageBg: string = '#FFF4F7FB';
  @StorageProp(FN_RESOLVED_CARD_BG_KEY) private cardBg: string = '';
  @Prop accentColor: string = '#FF4A8BFF';
  @Prop initialSelectedKeys: string[] = [];
  /** false 表示原配置读取失败：不能把空列表当成「全选」，要求用户重新确认。 */
  @Prop initialSelectionKnown: boolean = true;
  /** 原配置损坏时从影子副本恢复出的「上一次选择」，用来预勾选，避免用户全部重选。 */
  @Prop recoverableKeys: string[] = [];
  /** 影子副本是否存在；true 且列表为空表示上次就是「备份所有文件夹」。 */
  @Prop recoverablePresent: boolean = false;
  /** 父级顶栏点「全选/全不选」时递增，触发本组件切换 */
  @Prop @Watch('onSelectAllPulseChanged') selectAllPulse: number = 0;
  onConfirm: (keys: string[]) => void = (_: string[]): void => {};
  onSelectAllLabelChange: (label: string) => void = (_: string): void => {};

  @State private albums: LocalAlbumSummary[] = [];
  @State private selectedKeys: string[] = [];
  @State private loading: boolean = true;
  @State private loadHint: string = '';
  @State private sourceWarn: string = '';
  @State private lastAuth: FnReadImageVideoAuth = FnReadImageVideoAuth.DENIED;

  aboutToAppear(): void {
    void this.loadAlbums();
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

  private rightSelectLabel(): string {
    return this.allSelected() ? '全不选' : '全选';
  }

  private emitSelectAllLabel(): void {
    this.onSelectAllLabelChange(this.rightSelectLabel());
  }

  private onSelectAllPulseChanged(): void {
    if (this.selectAllPulse <= 0) {
      return;
    }
    this.onToggleSelectAll();
    this.emitSelectAllLabel();
  }

  private allMergeKeys(): string[] {
    const keys: string[] = [];
    for (let i = 0; i < this.albums.length; i++) {
      keys.push(albumBackupMergeKey(this.albums[i]));
    }
    return keys;
  }

  /**
   * 是否允许确认。原列表不可读时必须显式选过文件夹：
   * 空选会被当成「备份所有文件夹」，既会覆盖本地配置，也会把空列表同步到 NAS。
   */
  private canConfirm(): boolean {
    if (this.loading || this.albums.length === 0) {
      return false;
    }
    if (!this.initialSelectionKnown && this.selectedKeys.length === 0) {
      return false;
    }
    return true;
  }

  private async loadAlbums(): Promise<void> {
    this.loading = true;
    this.loadHint = '正在读取本机相册目录…';
    const scan = await scanLocalBackupSourceAlbums(this.hostContext(), true);
    this.lastAuth = scan.auth;
    this.albums = scan.albums;
    this.sourceWarn = '';
    if (scan.auth !== FnReadImageVideoAuth.GRANTED) {
      this.loadHint = '需要「图片和视频」访问权限，才能列出相机、微信等文件夹';
      this.selectedKeys = [];
    } else if (scan.albums.length === 0) {
      this.loadHint = '未找到含照片或视频的文件夹，请确认系统相册里是否有内容';
      this.selectedKeys = [];
    } else {
      if (!this.initialSelectionKnown) {
        // 原列表不可读时不能默认全选：否则会把读取失败当成「备份全部」并覆盖原配置。
        const recovered = this.recoveredKeys();
        if (this.recoverablePresent && this.recoverableKeys.length === 0) {
          // 影子是空数组：上次确实就是「备份所有文件夹」，按全选恢复。
          this.selectedKeys = this.allMergeKeys();
          this.sourceWarn = '已恢复上次的选择（备份所有文件夹），可直接确认或重新选择';
        } else if (this.recoverablePresent && recovered.length > 0) {
          // 影子有记录且能对上本机目录：预勾选它，用户确认即可修复配置。
          this.selectedKeys = recovered;
          this.sourceWarn = `已恢复上次选择的 ${recovered.length} 个文件夹，可直接确认或重新选择`;
        } else if (this.recoverablePresent) {
          // 影子有记录但一个都对不上当前相册：不能默认全选（那等于把用户排除过的目录又放回来），
          // 也不该谎称「已恢复」，交给用户重新选择。
          this.selectedKeys = [];
          this.sourceWarn = '上次选择的文件夹在当前设备上找不到，请重新选择要备份的文件夹（不选择无法确认）';
        } else {
          this.selectedKeys = [];
          this.sourceWarn = '原备份源读取失败，请重新选择要备份的文件夹（不选择无法确认）';
        }
        this.loadHint = '';
      } else {
        this.loadHint = '';
        if (this.initialSelectedKeys.length > 0) {
          this.selectedKeys = this.initialSelectedKeys.slice();
        } else {
          this.selectedKeys = this.allMergeKeys();
        }
      }
    }
    this.loading = false;
    this.emitSelectAllLabel();
  }

  /** 影子副本里能对上本机目录的上一次选择。 */
  private recoveredKeys(): string[] {
    if (this.recoverableKeys.length === 0) {
      return [];
    }
    const available = this.allMergeKeys();
    const out: string[] = [];
    for (let i = 0; i < this.recoverableKeys.length; i++) {
      const key = this.recoverableKeys[i];
      if (available.indexOf(key) >= 0 && out.indexOf(key) < 0) {
        out.push(key);
      }
    }
    return out;
  }

  private async onRequestPermission(): Promise<void> {
    await this.loadAlbums();
    if (this.lastAuth === FnReadImageVideoAuth.GRANTED && this.albums.length > 0) {
      this.toast('已获取相册访问权限');
    }
  }

  private async onOpenSettings(): Promise<void> {
    const ok = await fnOpenReadImageVideoSettings(this.hostContext());
    if (ok) {
      await this.loadAlbums();
    }
  }

  private isSelected(key: string): boolean {
    return this.selectedKeys.indexOf(key) >= 0;
  }

  private toggleKey(key: string): void {
    if (this.isSelected(key)) {
      this.selectedKeys = this.selectedKeys.filter((k: string): boolean => k !== key);
    } else {
      this.selectedKeys = this.selectedKeys.concat([key]);
    }
    this.emitSelectAllLabel();
  }

  private allSelected(): boolean {
    const all = this.allMergeKeys();
    if (all.length === 0) {
      return true;
    }
    for (let i = 0; i < all.length; i++) {
      if (!this.isSelected(all[i])) {
        return false;
      }
    }
    return true;
  }

  private onToggleSelectAll(): void {
    if (this.allSelected()) {
      this.selectedKeys = [];
    } else {
      this.selectedKeys = this.allMergeKeys().slice();
    }
    this.emitSelectAllLabel();
  }

  private selectCameraOnly(): void {
    const keys: string[] = [];
    for (let i = 0; i < this.albums.length; i++) {
      if (this.albums[i].isCameraAlbum) {
        keys.push(albumBackupMergeKey(this.albums[i]));
      }
    }
    this.selectedKeys = keys;
    this.emitSelectAllLabel();
  }

  private cameraAlbums(): LocalAlbumSummary[] {
    return this.albums.filter((a: LocalAlbumSummary): boolean => a.isCameraAlbum);
  }

  private otherAlbums(): LocalAlbumSummary[] {
    return this.albums.filter((a: LocalAlbumSummary): boolean => !a.isCameraAlbum);
  }

  private keysOf(albums: LocalAlbumSummary[]): string[] {
    const keys: string[] = [];
    for (let i = 0; i < albums.length; i++) {
      keys.push(albumBackupMergeKey(albums[i]));
    }
    return keys;
  }

  private sectionAllSelected(albums: LocalAlbumSummary[]): boolean {
    if (albums.length === 0) {
      return false;
    }
    const keys = this.keysOf(albums);
    for (let i = 0; i < keys.length; i++) {
      if (!this.isSelected(keys[i])) {
        return false;
      }
    }
    return true;
  }

  private toggleSection(albums: LocalAlbumSummary[]): void {
    const keys = this.keysOf(albums);
    if (this.sectionAllSelected(albums)) {
      const drop = new Set<string>(keys);
      this.selectedKeys = this.selectedKeys.filter((k: string): boolean => !drop.has(k));
    } else {
      const next = this.selectedKeys.slice();
      for (let i = 0; i < keys.length; i++) {
        if (next.indexOf(keys[i]) < 0) {
          next.push(keys[i]);
        }
      }
      this.selectedKeys = next;
    }
    this.emitSelectAllLabel();
  }

  @Builder
  private permissionEmptyBody() {
    Column({ space: 12 }) {
      Text(this.loadHint)
        .fontSize(14)
        .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
        .width('100%')
        .padding({ left: 20, right: 20, top: 12 })
      if (this.lastAuth !== FnReadImageVideoAuth.GRANTED) {
        FnPrimaryButton({
          text: $r('app.string.album_backup_grant_permission'),
          action: (): void => {
            void this.onRequestPermission();
          }
        })
          .width('100%')
        FnSecondaryButton({
          text: $r('app.string.album_backup_open_settings'),
          action: (): void => {
            void this.onOpenSettings();
          }
        })
          .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Text($r('app.string.album_backup_source_hint'))
        .fontSize(13)
        .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

      if (this.sourceWarn.length > 0) {
        Text(this.sourceWarn)
          .fontSize(13)
          .fontColor('#E11D48')
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
      }

      if (this.loading) {
        Text(this.loadHint.length > 0 ? this.loadHint : '加载中…')
          .fontSize(14)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
      } else if (this.albums.length === 0) {
        this.permissionEmptyBody()
      } else {
        Scroll() {
          Column({ space: 16 }) {
            if (this.cameraAlbums().length > 0) {
              Row({ space: 8 }) {
                SymbolGlyph(this.sectionAllSelected(this.cameraAlbums())
                  ? $r('sys.symbol.checkmark_circle_fill')
                  : $r('sys.symbol.circle'))
                  .fontSize(22)
                  .fontColor([this.accentColor])
                Text($r('app.string.album_backup_camera_section'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
                  .layoutWeight(1)
                  .onClick((): void => {
                    this.toggleSection(this.cameraAlbums());
                  })
                Text($r('app.string.album_backup_camera_only'))
                  .fontSize(14)
                  .fontColor(this.accentColor)
                  .onClick((): void => {
                    this.selectCameraOnly();
                  })
              }
              .width('100%')
              .padding({ left: 4, right: 4 })
              .alignItems(VerticalAlign.Center)

              Flex({
                wrap: FlexWrap.Wrap,
                justifyContent: FlexAlign.Start,
                alignItems: ItemAlign.Start
              }) {
                ForEach(this.cameraAlbums(), (album: LocalAlbumSummary) => {
                  Column() {
                    AlbumBackupAlbumTile({
                      album: album,
                      large: true,
                      mergeKey: albumBackupMergeKey(album),
                      selected: this.isSelected(albumBackupMergeKey(album)),
                      accentColor: this.accentColor,
                      onToggle: (key: string): void => {
                        this.toggleKey(key);
                      }
                    })
                  }
                  .width('31%')
                  .margin({ right: '2%', bottom: 12 })
                  .alignSelf(ItemAlign.Start)
                }, (album: LocalAlbumSummary) => {
                  const mk = albumBackupMergeKey(album);
                  return `cam_${mk}_${this.isSelected(mk)}`;
                })
              }
              .width('100%')
            }

            if (this.otherAlbums().length > 0) {
              Row({ space: 8 }) {
                SymbolGlyph(this.sectionAllSelected(this.otherAlbums())
                  ? $r('sys.symbol.checkmark_circle_fill')
                  : $r('sys.symbol.circle'))
                  .fontSize(22)
                  .fontColor([this.accentColor])
                Text($r('app.string.album_backup_other_folders_section'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 4, right: 4 })
              .alignItems(VerticalAlign.Center)
              .onClick((): void => {
                this.toggleSection(this.otherAlbums());
              })

              Flex({
                wrap: FlexWrap.Wrap,
                justifyContent: FlexAlign.Start,
                alignItems: ItemAlign.Start
              }) {
                ForEach(this.otherAlbums(), (album: LocalAlbumSummary) => {
                  Column() {
                    AlbumBackupAlbumTile({
                      album: album,
                      large: false,
                      mergeKey: albumBackupMergeKey(album),
                      selected: this.isSelected(albumBackupMergeKey(album)),
                      accentColor: this.accentColor,
                      onToggle: (key: string): void => {
                        this.toggleKey(key);
                      }
                    })
                  }
                  .width('31%')
                  .margin({ right: '2%', bottom: 12 })
                  .alignSelf(ItemAlign.Start)
                }, (album: LocalAlbumSummary) => {
                  const mk = albumBackupMergeKey(album);
                  return `oth_${mk}_${this.isSelected(mk)}`;
                })
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 100 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.TopStart)
      }

      Column() {
        FnPrimaryButton({
          text: $r('app.string.album_backup_confirm'),
          action: (): void => {
            // 二次校验：原列表不可读时不允许空选确认。
            if (!this.canConfirm()) {
              return;
            }
            this.onConfirm(this.selectedKeys.slice());
          }
        })
          .width('100%')
          // 原列表不可读时必须显式选过文件夹：空选会被当成「备份所有文件夹」并同步到 NAS。
          .enabled(this.canConfirm())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(fnResolvedCardFill(this.pageBg))
  }
}
