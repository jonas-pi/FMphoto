/**
 * 实况保存中间层：外观对齐「选择下载质量」动作菜单。
 * 官方 SaveButton 必须可见且不被遮挡，才能写入 PhotoSubtype.MOVING_PHOTO。
 */
import { GalleryListItem } from '../../model/FnApiTypes';
import { gallerySelectionContainsLive } from './LivePhotoDetect';
import { PrivilegeDownloadButton } from './PrivilegeDownloadButton';

export type LivePhotoSaveChoice = 'privilege' | 'pair' | 'cancel';

/** 含实况时弹出中间层；取消返回 undefined。 */
export async function resolveLivePhotoWriteAuthorized(
  items: GalleryListItem[],
  askSheet: () => Promise<LivePhotoSaveChoice>
): Promise<boolean | undefined> {
  if (!gallerySelectionContainsLive(items)) {
    return false;
  }
  const choice = await askSheet();
  if (choice === 'cancel') {
    return undefined;
  }
  return choice === 'privilege';
}

@Component
export struct LivePhotoSaveActionSheet {
  onSelect: (choice: LivePhotoSaveChoice) => void = (_: LivePhotoSaveChoice): void => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.onSelect('cancel');
        })

      Column({ space: 8 }) {
        Column() {
          Text('保存实况照片')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 16, left: 16, right: 16, bottom: 4 })

          Text('保存为系统动态照片后，可在图库长按播放')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ left: 20, right: 20, bottom: 12 })

          PrivilegeDownloadButton({
            allowAuthorize: true,
            onAuthorized: (): void => {
              this.onSelect('privilege');
            }
          })
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })

          Divider()
            .color($r('app.color.immersive_panel_border'))
            .margin({ left: 16, right: 16 })

          Button('保存封面和视频')
            .fontSize(17)
            .fontColor('#007AFF')
            .backgroundColor(Color.Transparent)
            .width('100%')
            .height(52)
            .onClick((): void => {
              this.onSelect('pair');
            })
        }
        .width('100%')
        .backgroundColor($r('app.color.page_background'))
        .borderRadius(14)

        Button('取消')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#007AFF')
          .backgroundColor($r('app.color.page_background'))
          .width('100%')
          .height(56)
          .borderRadius(14)
          .onClick((): void => {
            this.onSelect('cancel');
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 24 })
    }
    .width('100%')
    .height('100%')
  }
}
