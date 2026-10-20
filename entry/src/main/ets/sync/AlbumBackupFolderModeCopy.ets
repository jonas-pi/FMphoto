/** 备份目录偏好文案（对齐官方备份客户端界面，mode 数值 1–4 以 NAS 为准）。 */
export class AlbumBackupFolderModeOption {
  mode: number = 1;
  title: string = '';
  description: string = '';
  example: string = '';
}

export const ALBUM_BACKUP_FOLDER_MODE_OPTIONS: AlbumBackupFolderModeOption[] = [
  {
    mode: 1,
    title: '默认',
    description: '鸿蒙图库文件夹默认按拍摄日期保存；其他可识别的设备目录按原目录保存。',
    example: '日期目录：备份位置/年/月/；设备目录：备份位置/设备目录/'
  },
  {
    mode: 2,
    title: '按拍摄日期',
    description: '按照片拍摄日期创建子文件夹并保存。',
    example: '备份位置/年/月/'
  },
  {
    mode: 3,
    title: '按设备文件夹',
    description: '按当前设备的文件夹目录结构直接保存。',
    example: '备份位置/设备目录/'
  },
  {
    mode: 4,
    title: '保存在一个文件夹下',
    description: '所有照片保存在一个文件夹下，不创建子文件夹。',
    example: '备份位置/'
  }
];
