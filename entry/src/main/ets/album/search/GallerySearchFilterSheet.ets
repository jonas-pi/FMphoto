/**
 * 搜索选项半模态：对齐飞牛官方「整理 + 下拉筛选 + 拍摄信息」。
 * 下拉在页内切到选项列表，避免再套一层 bindSheet。
 * 内容顶对齐、两列均分；人物选项展示头像。
 */
import { FN_MEDIA_BASE_URL, AppSession } from '../../auth/AppSession';
import { GalleryNetworkThumb, nasUrl } from '../GalleryAlbumCommon';
import { FN_WINDOW_WIDTH_BP_KEY, fnAdaptiveGridColumns, fnRepeatFrTemplate } from '../../common/FnWindowBreakpoint';
import {
  gallerySearchFlattenTree,
  gallerySearchLoadCatalog
} from './GallerySearchFilterLogic';
import {
  GallerySearchFilterCatalog,
  GallerySearchFilterSnapshot,
  GallerySearchFilterTreeNode,
  GallerySearchPickerOption,
  SEARCH_FILTER_FIELD_ALBUM,
  SEARCH_FILTER_FIELD_APERTURE,
  SEARCH_FILTER_FIELD_DATE,
  SEARCH_FILTER_FIELD_EXPOSURE,
  SEARCH_FILTER_FIELD_FILE_TYPE,
  SEARCH_FILTER_FIELD_FOCAL,
  SEARCH_FILTER_FIELD_FOLDER,
  SEARCH_FILTER_FIELD_ISO,
  SEARCH_FILTER_FIELD_LOCATION,
  SEARCH_FILTER_FIELD_MAKE,
  SEARCH_FILTER_FIELD_PERSON
} from './GallerySearchFilterTypes';

@Component
export struct GallerySearchFilterSheet {
  applied: GallerySearchFilterSnapshot = new GallerySearchFilterSnapshot();
  onSearch: (snapshot: GallerySearchFilterSnapshot) => void = (_: GallerySearchFilterSnapshot): void => {};

  @State private loading: boolean = true;
  @State private loadError: string = '';
  @State private pickerField: string = '';
  @State private pickerTitle: string = '';
  @State private pickerOptions: GallerySearchPickerOption[] = [];
  @State private isCollect: boolean = false;
  @State private notAlbum: boolean = false;
  @State private notTag: boolean = false;
  @State private notGeo: boolean = false;
  @State private fileType: string = '';
  @State private fileTypeLabel: string = '';
  @State private personId: string = '';
  @State private personLabel: string = '';
  @State private personAvatar: string = '';
  @StorageProp(FN_MEDIA_BASE_URL) private baseUrl: string = '';
  @StorageProp(FN_WINDOW_WIDTH_BP_KEY) private windowWidthBp: number = WidthBreakpoint.WIDTH_SM;
  @State private dateLabel: string = '';
  @State private locationLabel: string = '';
  @State private albumLabel: string = '';
  @State private folderLabel: string = '';
  @State private showShootingInfo: boolean = false;
  @State private makeModelLabel: string = '';
  @State private focalLengthLabel: string = '';
  @State private exposureLabel: string = '';
  @State private apertureLabel: string = '';
  @State private isoLabel: string = '';

  private datePath: string[] = [];
  private locationPath: string[] = [];
  private albumPath: string[] = [];
  private folderPath: string[] = [];
  private makeModelPath: string[] = [];
  private focalLengthPath: string[] = [];
  private exposurePath: string[] = [];
  private aperturePath: string[] = [];
  private isoPath: string[] = [];
  private catalog: GallerySearchFilterCatalog = new GallerySearchFilterCatalog();

  aboutToAppear(): void {
    this.hydrateFromApplied();
    void this.loadCatalog();
  }

  private hydrateFromApplied(): void {
    const src = this.applied;
    this.isCollect = src.isCollect;
    this.notAlbum = src.notAlbum;
    this.notTag = src.notTag;
    this.notGeo = src.notGeo;
    this.fileType = src.fileType;
    this.fileTypeLabel = src.fileTypeLabel;
    this.personId = src.personId;
    this.personLabel = src.personLabel;
    this.personAvatar = src.personAvatar;
    this.datePath = src.datePath.slice();
    this.dateLabel = src.dateLabel;
    this.locationPath = src.locationPath.slice();
    this.locationLabel = src.locationLabel;
    this.albumPath = src.albumPath.slice();
    this.albumLabel = src.albumLabel;
    this.folderPath = src.folderPath.slice();
    this.folderLabel = src.folderLabel;
    this.showShootingInfo = src.showShootingInfo;
    this.makeModelPath = src.makeModelPath.slice();
    this.makeModelLabel = src.makeModelLabel;
    this.focalLengthPath = src.focalLengthPath.slice();
    this.focalLengthLabel = src.focalLengthLabel;
    this.exposurePath = src.exposurePath.slice();
    this.exposureLabel = src.exposureLabel;
    this.aperturePath = src.aperturePath.slice();
    this.apertureLabel = src.apertureLabel;
    this.isoPath = src.isoPath.slice();
    this.isoLabel = src.isoLabel;
  }

  private async loadCatalog(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    const client = AppSession.getClient();
    if (client === null) {
      this.loadError = '未登录';
      this.loading = false;
      return;
    }
    try {
      this.catalog = await gallerySearchLoadCatalog(client);
    } catch (e) {
      this.loadError = String(e) || '筛选项加载失败';
    }
    this.loading = false;
  }

  private currentSnapshot(): GallerySearchFilterSnapshot {
    const out = new GallerySearchFilterSnapshot();
    out.isCollect = this.isCollect;
    out.notAlbum = this.notAlbum;
    out.notTag = this.notTag;
    out.notGeo = this.notGeo;
    out.fileType = this.fileType;
    out.fileTypeLabel = this.fileTypeLabel;
    out.personId = this.personId;
    out.personLabel = this.personLabel;
    out.personAvatar = this.personAvatar;
    out.datePath = this.datePath.slice();
    out.dateLabel = this.dateLabel;
    out.locationPath = this.locationPath.slice();
    out.locationLabel = this.locationLabel;
    out.albumPath = this.albumPath.slice();
    out.albumLabel = this.albumLabel;
    out.folderPath = this.folderPath.slice();
    out.folderLabel = this.folderLabel;
    out.showShootingInfo = this.showShootingInfo;
    out.makeModelPath = this.makeModelPath.slice();
    out.makeModelLabel = this.makeModelLabel;
    out.focalLengthPath = this.focalLengthPath.slice();
    out.focalLengthLabel = this.focalLengthLabel;
    out.exposurePath = this.exposurePath.slice();
    out.exposureLabel = this.exposureLabel;
    out.aperturePath = this.aperturePath.slice();
    out.apertureLabel = this.apertureLabel;
    out.isoPath = this.isoPath.slice();
    out.isoLabel = this.isoLabel;
    return out;
  }

  private resetDraft(): void {
    this.isCollect = false;
    this.notAlbum = false;
    this.notTag = false;
    this.notGeo = false;
    this.fileType = '';
    this.fileTypeLabel = '';
    this.personId = '';
    this.personLabel = '';
    this.personAvatar = '';
    this.datePath = [];
    this.dateLabel = '';
    this.locationPath = [];
    this.locationLabel = '';
    this.albumPath = [];
    this.albumLabel = '';
    this.folderPath = [];
    this.folderLabel = '';
    this.showShootingInfo = false;
    this.makeModelPath = [];
    this.makeModelLabel = '';
    this.focalLengthPath = [];
    this.focalLengthLabel = '';
    this.exposurePath = [];
    this.exposureLabel = '';
    this.aperturePath = [];
    this.apertureLabel = '';
    this.isoPath = [];
    this.isoLabel = '';
    this.pickerField = '';
  }

  private submit(): void {
    this.onSearch(this.currentSnapshot());
  }

  private openSimplePicker(field: string, title: string, options: GallerySearchPickerOption[]): void {
    if (this.loading) {
      return;
    }
    this.pickerTitle = title;
    this.pickerOptions = options;
    this.pickerField = field;
  }

  private openTreePicker(field: string, title: string, tree: GallerySearchFilterTreeNode[]): void {
    this.openSimplePicker(field, title, gallerySearchFlattenTree(tree));
  }

  private closePicker(): void {
    this.pickerField = '';
  }

  private applyPicker(option: GallerySearchPickerOption): void {
    const field = this.pickerField;
    if (field === SEARCH_FILTER_FIELD_FILE_TYPE) {
      this.fileType = option.value;
      this.fileTypeLabel = option.label;
    } else if (field === SEARCH_FILTER_FIELD_PERSON) {
      this.personId = option.value;
      this.personLabel = option.label;
      this.personAvatar = option.avatarUrl;
    } else if (field === SEARCH_FILTER_FIELD_DATE) {
      this.datePath = option.path.slice();
      this.dateLabel = option.label;
    } else if (field === SEARCH_FILTER_FIELD_LOCATION) {
      this.locationPath = option.path.slice();
      this.locationLabel = option.label;
    } else if (field === SEARCH_FILTER_FIELD_ALBUM) {
      this.albumPath = option.path.slice();
      this.albumLabel = option.label;
    } else if (field === SEARCH_FILTER_FIELD_FOLDER) {
      this.folderPath = option.path.slice();
      this.folderLabel = option.label;
    } else if (field === SEARCH_FILTER_FIELD_MAKE) {
      this.makeModelPath = option.path.slice();
      this.makeModelLabel = option.label;
    } else if (field === SEARCH_FILTER_FIELD_FOCAL) {
      this.focalLengthPath = option.path.slice();
      this.focalLengthLabel = option.label;
    } else if (field === SEARCH_FILTER_FIELD_EXPOSURE) {
      this.exposurePath = option.path.slice();
      this.exposureLabel = option.label;
    } else if (field === SEARCH_FILTER_FIELD_APERTURE) {
      this.aperturePath = option.path.slice();
      this.apertureLabel = option.label;
    } else if (field === SEARCH_FILTER_FIELD_ISO) {
      this.isoPath = option.path.slice();
      this.isoLabel = option.label;
    }
    this.closePicker();
  }

  private clearCurrentPicker(): void {
    const field = this.pickerField;
    if (field === SEARCH_FILTER_FIELD_FILE_TYPE) {
      this.fileType = '';
      this.fileTypeLabel = '';
    } else if (field === SEARCH_FILTER_FIELD_PERSON) {
      this.personId = '';
      this.personLabel = '';
      this.personAvatar = '';
    } else if (field === SEARCH_FILTER_FIELD_DATE) {
      this.datePath = [];
      this.dateLabel = '';
    } else if (field === SEARCH_FILTER_FIELD_LOCATION) {
      this.locationPath = [];
      this.locationLabel = '';
    } else if (field === SEARCH_FILTER_FIELD_ALBUM) {
      this.albumPath = [];
      this.albumLabel = '';
    } else if (field === SEARCH_FILTER_FIELD_FOLDER) {
      this.folderPath = [];
      this.folderLabel = '';
    } else if (field === SEARCH_FILTER_FIELD_MAKE) {
      this.makeModelPath = [];
      this.makeModelLabel = '';
    } else if (field === SEARCH_FILTER_FIELD_FOCAL) {
      this.focalLengthPath = [];
      this.focalLengthLabel = '';
    } else if (field === SEARCH_FILTER_FIELD_EXPOSURE) {
      this.exposurePath = [];
      this.exposureLabel = '';
    } else if (field === SEARCH_FILTER_FIELD_APERTURE) {
      this.aperturePath = [];
      this.apertureLabel = '';
    } else if (field === SEARCH_FILTER_FIELD_ISO) {
      this.isoPath = [];
      this.isoLabel = '';
    }
    this.closePicker();
  }

  private displayOrPlaceholder(label: string, placeholder: string): string {
    return label.length > 0 ? label : placeholder;
  }

  private isPersonPicker(): boolean {
    return this.pickerField === SEARCH_FILTER_FIELD_PERSON;
  }

  private personPickerColumns(): number {
    return fnAdaptiveGridColumns(4, this.windowWidthBp);
  }

  private personFaceUri(avatarUrl: string): string {
    return nasUrl(this.baseUrl, avatarUrl);
  }

  @Builder
  private personAvatarView(avatarUrl: string, cacheKey: string) {
    if (avatarUrl.length > 0) {
      GalleryNetworkThumb({
        uri: this.personFaceUri(avatarUrl),
        paused: false,
        fadeInEnabled: false,
        cacheIdentity: cacheKey,
        cacheRank: 3
      })
        .width('100%')
        .height('100%')
        .borderRadius(999)
        .clip(true)
    } else {
      SymbolGlyph($r('sys.symbol.person_crop_circle_fill'))
        .fontSize(22)
        .fontColor([$r('app.color.text_secondary')])
    }
  }

  @Builder
  private organizeCheck(label: string, checked: boolean, onToggle: (v: boolean) => void) {
    Row({ space: 6 }) {
      Checkbox({ name: label })
        .select(checked)
        .selectedColor($r('sys.color.ohos_id_color_activated'))
        .shape(CheckBoxShape.ROUNDED_SQUARE)
        .width(20)
        .height(20)
        .onChange((v: boolean): void => {
          onToggle(v);
        })
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .onClick((): void => {
          onToggle(!checked);
        })
    }
    .width('100%')
    .height(32)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private dropdownCell(title: string, valueText: string, placeholder: string, avatarUrl: string, onOpen: () => void) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Row({ space: 8 }) {
        if (avatarUrl.length > 0) {
          Stack({ alignContent: Alignment.Center }) {
            this.personAvatarView(avatarUrl, `filter_person_${valueText}`)
          }
          .width(24)
          .height(24)
          .borderRadius(12)
          .clip(true)
        }
        Text(this.displayOrPlaceholder(valueText, placeholder))
          .fontSize(14)
          .fontColor(valueText.length > 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 10 })
      .borderRadius(8)
      .borderWidth(1)
      .borderColor($r('app.color.immersive_panel_border'))
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .onClick((): void => {
      onOpen();
    })
  }

  @Builder
  private pickerNavBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(20)
        .fontColor([$r('app.color.text_primary')])
        .onClick((): void => {
          this.closePicker();
        })
      Text(this.pickerTitle)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text('清除')
        .fontSize(14)
        .fontColor($r('sys.color.ohos_id_color_activated'))
        .onClick((): void => {
          this.clearCurrentPicker();
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  private personPickerGrid() {
    Grid() {
      ForEach(this.pickerOptions, (opt: GallerySearchPickerOption) => {
        GridItem() {
          Column({ space: 6 }) {
            Stack({ alignContent: Alignment.Center }) {
              this.personAvatarView(opt.avatarUrl, `filter_pick_${opt.value}`)
            }
            .width('100%')
            .aspectRatio(1)
            .borderRadius(999)
            .clip(true)
            .backgroundColor($r('app.color.immersive_panel_border'))
            Text(opt.label)
              .fontSize(12)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .width('100%')
          }
          .width('100%')
          .onClick((): void => {
            this.applyPicker(opt);
          })
        }
      }, (opt: GallerySearchPickerOption) => `person_${opt.value}`)
    }
    .columnsTemplate(fnRepeatFrTemplate(this.personPickerColumns()))
    .columnsGap(12)
    .rowsGap(12)
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16, top: 4, bottom: 12 })
    .scrollBar(BarState.Off)
    .nestedScroll({
      scrollForward: NestedScrollMode.SELF_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
  }

  @Builder
  private textPickerList() {
    List() {
      ForEach(this.pickerOptions, (opt: GallerySearchPickerOption) => {
        ListItem() {
          Text(opt.label)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
        .onClick((): void => {
          this.applyPicker(opt);
        })
      }, (opt: GallerySearchPickerOption) => `picker_${opt.value}_${opt.label}`)
    }
    .width('100%')
    .height('100%')
    .layoutWeight(1)
    .nestedScroll({
      scrollForward: NestedScrollMode.SELF_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
  }

  @Builder
  private pickerPage() {
    Column() {
      this.pickerNavBar()
      if (this.isPersonPicker()) {
        this.personPickerGrid()
      } else {
        this.textPickerList()
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private formPage() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.loading) {
          Row() {
            LoadingProgress()
              .width(28)
              .height(28)
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.Center)
        } else if (this.loadError.length > 0) {
          Text(this.loadError)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }

        Text('整理')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Grid() {
          GridItem() {
            this.organizeCheck('已收藏', this.isCollect, (v: boolean): void => {
              this.isCollect = v;
            })
          }
          GridItem() {
            this.organizeCheck('不在相册内', this.notAlbum, (v: boolean): void => {
              this.notAlbum = v;
            })
          }
          GridItem() {
            this.organizeCheck('无标签', this.notTag, (v: boolean): void => {
              this.notTag = v;
            })
          }
          GridItem() {
            this.organizeCheck('无位置信息', this.notGeo, (v: boolean): void => {
              this.notGeo = v;
            })
          }
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(8)
        .rowsGap(4)
        .width('100%')
        .height(68)
        .scrollBar(BarState.Off)

        Grid() {
          GridItem() {
            this.dropdownCell('媒体类型', this.fileTypeLabel, '选择媒体类型', '', (): void => {
              this.openSimplePicker(SEARCH_FILTER_FIELD_FILE_TYPE, '媒体类型', this.catalog.fileTypes);
            })
          }
          GridItem() {
            this.dropdownCell('拍摄时间', this.dateLabel, '选择拍摄时间', '', (): void => {
              this.openTreePicker(SEARCH_FILTER_FIELD_DATE, '拍摄时间', this.catalog.dates);
            })
          }
          GridItem() {
            this.dropdownCell('人物', this.personLabel, '选择人物', this.personAvatar, (): void => {
              this.openSimplePicker(SEARCH_FILTER_FIELD_PERSON, '人物', this.catalog.persons);
            })
          }
          GridItem() {
            this.dropdownCell('地点', this.locationLabel, '选择国家城市', '', (): void => {
              this.openTreePicker(SEARCH_FILTER_FIELD_LOCATION, '地点', this.catalog.locations);
            })
          }
          GridItem() {
            this.dropdownCell('相册', this.albumLabel, '选择所在相册', '', (): void => {
              this.openTreePicker(SEARCH_FILTER_FIELD_ALBUM, '相册', this.catalog.albums);
            })
          }
          GridItem() {
            this.dropdownCell('文件夹', this.folderLabel, '选择文件夹', '', (): void => {
              this.openTreePicker(SEARCH_FILTER_FIELD_FOLDER, '文件夹', this.catalog.folders);
            })
          }
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(12)
        .width('100%')
        .height(192)
        .scrollBar(BarState.Off)

        if (this.showShootingInfo) {
          Grid() {
            GridItem() {
              this.dropdownCell('相机品牌', this.makeModelLabel, '选择相机品牌', '', (): void => {
                this.openTreePicker(SEARCH_FILTER_FIELD_MAKE, '相机品牌', this.catalog.makeModels);
              })
            }
            GridItem() {
              this.dropdownCell('焦距', this.focalLengthLabel, '选择焦距', '', (): void => {
                this.openTreePicker(SEARCH_FILTER_FIELD_FOCAL, '焦距', this.catalog.focalLengths);
              })
            }
            GridItem() {
              this.dropdownCell('曝光时间', this.exposureLabel, '选择曝光时间', '', (): void => {
                this.openTreePicker(SEARCH_FILTER_FIELD_EXPOSURE, '曝光时间', this.catalog.exposures);
              })
            }
            GridItem() {
              this.dropdownCell('光圈', this.apertureLabel, '选择光圈', '', (): void => {
                this.openTreePicker(SEARCH_FILTER_FIELD_APERTURE, '光圈', this.catalog.apertures);
              })
            }
            GridItem() {
              this.dropdownCell('ISO', this.isoLabel, '选择 ISO', '', (): void => {
                this.openTreePicker(SEARCH_FILTER_FIELD_ISO, 'ISO', this.catalog.isos);
              })
            }
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(12)
          .rowsGap(12)
          .width('100%')
          .height(192)
          .scrollBar(BarState.Off)
        }

        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.camera'))
            .fontSize(18)
            .fontColor([$r('app.color.text_primary')])
          Text('拍摄信息')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showShootingInfo })
            .selectedColor($r('sys.color.ohos_id_color_activated'))
            .onChange((v: boolean): void => {
              this.showShootingInfo = v;
            })
        }
        .width('100%')
        .height(40)
        .alignItems(VerticalAlign.Center)

        Row({ space: 12 }) {
          Button('重置', { type: ButtonType.ROUNDED_RECTANGLE, buttonStyle: ButtonStyleMode.NORMAL })
            .fontSize(14)
            .height(40)
            .layoutWeight(1)
            .onClick((): void => {
              this.resetDraft();
            })
          Button('搜索', { type: ButtonType.ROUNDED_RECTANGLE, buttonStyle: ButtonStyleMode.EMPHASIZED })
            .fontSize(14)
            .height(40)
            .layoutWeight(1)
            .onClick((): void => {
              this.submit();
            })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 4, bottom: 16 })
    }
    .width('100%')
    .align(Alignment.TopStart)
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .nestedScroll({
      scrollForward: NestedScrollMode.SELF_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
  }

  build() {
    Column() {
      if (this.pickerField.length > 0) {
        this.pickerPage()
      } else {
        this.formPage()
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Color.Transparent)
  }
}
