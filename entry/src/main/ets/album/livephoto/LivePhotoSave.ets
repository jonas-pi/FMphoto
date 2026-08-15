/**
 * 动态照片保存安全控件。须在用户点击 SaveButton 的回调里执行落盘。
 */
import { common } from '@kit.AbilityKit';
import { LivePhotoPairFiles } from './LivePhotoSandbox';
import { createMovingPhotoAsset } from './LivePhotoSaveOps';

@Component
export struct LivePhotoSaveSheet {
  @Prop imageUri: string = '';
  @Prop videoUri: string = '';
  @Prop imagePath: string = '';
  @Prop videoPath: string = '';
  @Prop saveTitle: string = '';
  @Prop isDark: boolean = false;
  onSaved: () => void = () => {};
  onFailed: () => void = () => {};

  private saveButtonOptions: SaveButtonOptions = {
    icon: SaveIconStyle.FULL_FILLED,
    text: SaveDescription.SAVE_IMAGE,
    buttonType: ButtonType.Capsule
  };

  build() {
    Column({ space: 16 }) {
      Text('将保存为系统动态照片')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDark ? '#FFF2F2F7' : '#FF1C1C1E')
      Text('写入图库后可长按播放。若系统拒绝写入，将仅保留静帧封面。')
        .fontSize(13)
        .fontColor(this.isDark ? '#FF8E8E93' : '#FF6E6E73')
      SaveButton(this.saveButtonOptions)
        .onClick(async (_event, result: SaveButtonOnClickResult) => {
          if (result !== SaveButtonOnClickResult.SUCCESS) {
            this.onFailed();
            return;
          }
          const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
          const pair = new LivePhotoPairFiles();
          pair.imageUri = this.imageUri;
          pair.videoUri = this.videoUri;
          pair.imagePath = this.imagePath;
          pair.videoPath = this.videoPath;
          const ok = await createMovingPhotoAsset(ctx, pair, this.saveTitle);
          if (ok) {
            this.onSaved();
          } else {
            this.onFailed();
          }
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }
}
