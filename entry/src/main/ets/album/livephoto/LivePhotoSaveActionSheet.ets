/**
 * 实况保存：二级菜单与通用下载同一套 bindSheet + FnHdsChoiceSheet。
 * 选「保存为动态照片」后，再弹出实底 SaveButton（安全控件不能进模糊半模态）。
 */
import { GalleryListItem } from '../../model/FnApiTypes';
import { gallerySelectionContainsLive } from './LivePhotoDetect';
import { PrivilegeDownloadButton } from './PrivilegeDownloadButton';

export type LivePhotoSaveChoice = 'privilege' | 'pair' | 'cancel';

export const LIVE_PHOTO_SAVE_SHEET_TITLE: string = '保存实况照片';
export const LIVE_PHOTO_SAVE_CHOICE_BUTTONS: string[] = ['保存为动态照片', '保存封面和视频'];
export const LIVE_PHOTO_PRIVILEGE_SHEET_TITLE: string = '保存为动态照片';

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

/** 先走通用选项半模态，再按需拉起实底 SaveButton。 */
export async function askLivePhotoSaveChoice(
  askChoice: (title: string, buttons: string[]) => Promise<number>,
  askPrivilege: () => Promise<boolean>
): Promise<LivePhotoSaveChoice> {
  const idx = await askChoice(LIVE_PHOTO_SAVE_SHEET_TITLE, LIVE_PHOTO_SAVE_CHOICE_BUTTONS);
  if (idx === 1) {
    return 'pair';
  }
  if (idx < 0) {
    return 'cancel';
  }
  await new Promise<void>((resolve: () => void) => {
    setTimeout((): void => {
      resolve();
    }, 280);
  });
  const granted = await askPrivilege();
  return granted ? 'privilege' : 'cancel';
}

/**
 * 官方 SaveButton 实底内容区。
 * 必须落在不带模糊/材质的半模态里，才能写入 PhotoSubtype.MOVING_PHOTO。
 */
@Component
export struct LivePhotoSaveActionSheet {
  onSelect: (choice: LivePhotoSaveChoice) => void = (_: LivePhotoSaveChoice): void => {};

  build() {
    Column() {
      PrivilegeDownloadButton({
        allowAuthorize: true,
        onAuthorized: (): void => {
          this.onSelect('privilege');
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    .backgroundColor($r('app.color.page_background'))
  }
}
