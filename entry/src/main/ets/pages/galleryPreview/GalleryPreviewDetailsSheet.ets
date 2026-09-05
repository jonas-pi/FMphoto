import {
  FnInlineLoading,
  FnStateText
} from '../../common/FnUiCommon';
import { GalleryPhotoDetailData, PersonInPhotoItem } from '../../model/FnApiTypes';
import {
  galleryPreviewDetailText,
  galleryPreviewFormatBytes,
  galleryPreviewJoinPair,
  galleryPreviewMediaKindLabel,
  galleryPreviewPersonInPhotoLineText
} from './GalleryPreviewDetailsLogic';

/**
 * 照片详情内容区。
 * 外层标题、拖动条和进退场由预览页内联面板负责，本组件只维护可滚动详情内容。
 */
@Component
export struct GalleryPreviewDetailsSheet {
  @Prop detailsLoading: boolean = false;
  @Prop detailsError: string = '';
  @Prop detailsData: GalleryPhotoDetailData | undefined = undefined;
  @Prop personsInPhoto: PersonInPhotoItem[] = [];
  @Prop folderOpening: boolean = false;
  @Prop personOpening: boolean = false;

  onPersonClick: (p: PersonInPhotoItem) => void = (_: PersonInPhotoItem) => {};
  onFolderClick: () => void = () => {};

  private hasMoreInfo(): boolean {
    return galleryPreviewDetailText(this.detailsData?.make).length > 0 ||
      galleryPreviewDetailText(this.detailsData?.model).length > 0 ||
      galleryPreviewDetailText(this.detailsData?.fumber).length > 0 ||
      galleryPreviewDetailText(this.detailsData?.exposureTime).length > 0 ||
      galleryPreviewDetailText(this.detailsData?.isoSpeedRatings).length > 0 ||
      galleryPreviewDetailText(this.detailsData?.focalLength).length > 0 ||
      galleryPreviewDetailText(this.detailsData?.mp).length > 0 ||
      galleryPreviewDetailText(this.detailsData?.exposureProgram).length > 0 ||
      galleryPreviewDetailText(this.detailsData?.meteringMode).length > 0 ||
      galleryPreviewDetailText(this.detailsData?.geo).length > 0 ||
      galleryPreviewDetailText(this.detailsData?.latitude).length > 0 ||
      galleryPreviewDetailText(this.detailsData?.longitude).length > 0;
  }

  private hasRelatedInfo(): boolean {
    const path = galleryPreviewDetailText(this.detailsData?.filePath ?? this.detailsData?.showFilePath);
    return this.personsInPhoto.length > 0 || path.length > 0;
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .margin({ top: 10, bottom: 4 })
  }

  @Builder
  private detailRow(label: string, value: string) {
    if (value.length > 0) {
      Row({ space: 10 }) {
        Text(label)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width(92)
        Text(value)
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 6, bottom: 6 })
    }
  }

  @Builder
  private detailPersonsSection() {
    Row({ space: 10 }) {
      Text('人物')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width(92)
      Column({ space: 4 }) {
        if (this.personsInPhoto.length === 0) {
          Text('未识别到人物')
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
        } else {
          ForEach(this.personsInPhoto, (p: PersonInPhotoItem, idx: number) => {
            Text(galleryPreviewPersonInPhotoLineText(p))
              .fontSize(13)
              .fontColor($r('app.color.brand_primary'))
              .maxLines(3)
              .width('100%')
              .textAlign(TextAlign.Start)
              .onClick((): void => {
                this.onPersonClick(p);
              })
          }, (p: PersonInPhotoItem, idx: number) => `pip_${idx}_${p.personId ?? 0}_${p.faceId ?? 0}`)
          Text(this.personOpening ? '正在打开人物相册…' : '点击姓名打开该人物相册')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  private detailPathRow(label: string, fullPath: string) {
    if (fullPath.length > 0) {
      Row({ space: 10 }) {
        Text(label)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width(92)
        Column({ space: 4 }) {
          // 详情区已支持滚动，路径不再截断层级或限制行数，直接完整展示原始路径。
          Text(fullPath)
            .fontSize(13)
            .fontColor($r('app.color.brand_primary'))
          Text(this.folderOpening ? '正在打开同目录媒体...' : '点击打开同目录媒体')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 6, bottom: 6 })
      .onClick((): void => {
        this.onFolderClick();
      })
    }
  }

  build() {
    Column() {
      if (this.detailsLoading) {
        FnInlineLoading({ text: '详情加载中…' })
          .padding({ top: 18, bottom: 20 })
      } else if (this.detailsError.length > 0) {
        FnStateText({ text: this.detailsError, isError: true })
          .layoutWeight(0)
          .padding({ left: 0, right: 0, top: 12, bottom: 16 })
      } else {
        Scroll() {
          Column() {
            this.sectionTitle('基本信息')
            this.detailRow('文件名', galleryPreviewDetailText(this.detailsData?.fileName))
            this.detailRow('拍摄时间', galleryPreviewDetailText(this.detailsData?.photoDateTime ?? this.detailsData?.dateTime))
            this.detailRow('文件类型', galleryPreviewMediaKindLabel(this.detailsData))
            this.detailRow('文件大小', galleryPreviewFormatBytes(this.detailsData?.fileSize))
            this.detailRow(
              '分辨率',
              galleryPreviewJoinPair(
                galleryPreviewDetailText(this.detailsData?.width),
                galleryPreviewDetailText(this.detailsData?.height),
                ' x '
              )
            )

            if (this.hasMoreInfo()) {
              this.sectionTitle('更多信息')
              this.detailRow('设备厂商', galleryPreviewDetailText(this.detailsData?.make))
              this.detailRow('设备型号', galleryPreviewDetailText(this.detailsData?.model))
              this.detailRow('光圈', galleryPreviewDetailText(this.detailsData?.fumber))
              this.detailRow('快门', galleryPreviewDetailText(this.detailsData?.exposureTime))
              this.detailRow('ISO', galleryPreviewDetailText(this.detailsData?.isoSpeedRatings))
              this.detailRow('焦距', galleryPreviewDetailText(this.detailsData?.focalLength))
              this.detailRow('像素', galleryPreviewDetailText(this.detailsData?.mp))
              this.detailRow('曝光程序', galleryPreviewDetailText(this.detailsData?.exposureProgram))
              this.detailRow('测光模式', galleryPreviewDetailText(this.detailsData?.meteringMode))
              this.detailRow('地理位置', galleryPreviewDetailText(this.detailsData?.geo))
              this.detailRow(
                '经纬度',
                galleryPreviewJoinPair(
                  galleryPreviewDetailText(this.detailsData?.latitude),
                  galleryPreviewDetailText(this.detailsData?.longitude),
                  ', '
                )
              )
            }

            if (this.hasRelatedInfo()) {
              this.sectionTitle('相关内容')
              if (this.personsInPhoto.length > 0) {
                this.detailPersonsSection()
              }
              this.detailPathRow(
                '文件路径',
                galleryPreviewDetailText(this.detailsData?.filePath ?? this.detailsData?.showFilePath)
              )
            }
          }
          .width('100%')
          .padding({ bottom: 10 })
          .alignItems(HorizontalAlign.Start)
          // Scroll 占满剩余高度时，显式从顶部开始排布；信息少时只在底部留下稳定空白。
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        // HarmonyOS Scroll 在受 layoutWeight 限高且内容较少时默认居中；
        // 必须把 align 设置在 Scroll 自身，内部 Column 的 justifyContent 无法改变该行为。
        .align(Alignment.Top)
        // 信息较多时保持完整滚动能力，但像系统相册一样不显示常驻滚动条。
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(Color.Transparent)
  }
}
