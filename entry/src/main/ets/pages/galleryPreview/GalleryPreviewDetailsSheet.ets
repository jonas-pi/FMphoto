import {
  fnLiquidGlassGradient,
  FnInlineLoading,
  FnStateText
} from '../../common/FnUiCommon';
import { GalleryPhotoDetailData, PersonInPhotoItem } from '../../model/FnApiTypes';
import {
  galleryPreviewCompactDisplayPath,
  galleryPreviewDetailText,
  galleryPreviewFormatBytes,
  galleryPreviewJoinPair,
  galleryPreviewPersonInPhotoLineText
} from './GalleryPreviewDetailsLogic';

@Component
export struct GalleryPreviewDetailsSheet {
  @Prop isDark: boolean = false;
  @Prop detailsLoading: boolean = false;
  @Prop detailsError: string = '';
  @Prop detailsData: GalleryPhotoDetailData | undefined = undefined;
  @Prop personsInPhoto: PersonInPhotoItem[] = [];
  @Prop folderOpening: boolean = false;
  @Prop personOpening: boolean = false;

  onPersonClick: (p: PersonInPhotoItem) => void = (_: PersonInPhotoItem) => {};
  onFolderClick: () => void = () => {};
  onClose: () => void = () => {};

  @Builder
  private headerRow() {
    Row() {
      Text('照片详情')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDark ? '#FFF2F2F7' : '#FF1C1C1E')

      Blank()
        .layoutWeight(1)

      this.closeButton()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 4, bottom: 8 })
    .border({
      width: { bottom: 1 },
      color: this.isDark ? '#1FFFFFFF' : '#12001A33'
    })
  }

  @Builder
  private closeButton() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(17)
        .fontColor([this.isDark ? '#FFF2F2F7' : '#FF1C1C1E'])
        .hitTestBehavior(HitTestMode.None)
    }
    .width(32)
    .height(32)
    .borderRadius(16)
    .backgroundColor($r('app.color.gallery_material_surface_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .linearGradient(fnLiquidGlassGradient())
    .borderWidth(1)
    .borderColor(this.isDark ? '#1FFFFFFF' : '#12001A33')
    .clip(true)
    .onClick((): void => {
      this.onClose();
    })
  }

  @Builder
  private detailRow(label: string, value: string) {
    if (value.length > 0) {
      Row({ space: 10 }) {
        Text(label)
          .fontSize(13)
          .fontColor(this.isDark ? '#FF8E8E93' : '#FF6E6E73')
          .width(92)
        Text(value)
          .fontSize(13)
          .fontColor(this.isDark ? '#FFF2F2F7' : '#FF1C1C1E')
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
        .fontColor(this.isDark ? '#FF8E8E93' : '#FF6E6E73')
        .width(92)
      Column({ space: 4 }) {
        if (this.personsInPhoto.length === 0) {
          Text('未识别到人物')
            .fontSize(13)
            .fontColor(this.isDark ? '#FFF2F2F7' : '#FF1C1C1E')
        } else {
          ForEach(this.personsInPhoto, (p: PersonInPhotoItem, idx: number) => {
            Text(galleryPreviewPersonInPhotoLineText(p))
              .fontSize(13)
              .fontColor(this.isDark ? '#FF78A6FF' : '#FF0A63D8')
              .maxLines(3)
              .width('100%')
              .textAlign(TextAlign.Start)
              .onClick((): void => {
                this.onPersonClick(p);
              })
          }, (p: PersonInPhotoItem, idx: number) => `pip_${idx}_${p.personId ?? 0}_${p.faceId ?? 0}`)
          Text(this.personOpening ? '正在打开人物相册…' : '点击姓名打开该人物相册')
            .fontSize(11)
            .fontColor(this.isDark ? '#FF8E8E93' : '#FF6E6E73')
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
          .fontColor(this.isDark ? '#FF8E8E93' : '#FF6E6E73')
          .width(92)
        Column({ space: 4 }) {
          Text(galleryPreviewCompactDisplayPath(fullPath))
            .fontSize(13)
            .fontColor(this.isDark ? '#FF78A6FF' : '#FF0A63D8')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.folderOpening ? '正在打开同目录媒体...' : '点击打开同目录媒体')
            .fontSize(11)
            .fontColor(this.isDark ? '#FF8E8E93' : '#FF6E6E73')
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
      this.headerRow()
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
            this.detailRow('文件名', galleryPreviewDetailText(this.detailsData?.fileName))
            this.detailRow('拍摄时间', galleryPreviewDetailText(this.detailsData?.photoDateTime ?? this.detailsData?.dateTime))
            this.detailRow('文件类型', galleryPreviewDetailText(this.detailsData?.fileType))
            this.detailRow('文件大小', galleryPreviewFormatBytes(this.detailsData?.fileSize))
            this.detailRow(
              '分辨率',
              galleryPreviewJoinPair(
                galleryPreviewDetailText(this.detailsData?.width),
                galleryPreviewDetailText(this.detailsData?.height),
                ' x '
              )
            )
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
            this.detailPersonsSection()
            this.detailPathRow('文件路径', galleryPreviewDetailText(this.detailsData?.filePath ?? this.detailsData?.showFilePath))
          }
          .width('100%')
          .padding({ bottom: 10 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }
}
