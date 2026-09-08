/**
 * 打开文件夹浏览页时的起始路径。
 * Home 的 NavDestination 不把 param 传进页面，因此用中转站，避免只能从根目录进。
 */
export class FolderBrowseNavStore {
  static pendingFolderPath: string = '';

  static setPendingPath(path: string): void {
    FolderBrowseNavStore.pendingFolderPath = path.trim();
  }

  static consumePendingPath(): string {
    const path = FolderBrowseNavStore.pendingFolderPath.trim();
    FolderBrowseNavStore.pendingFolderPath = '';
    return path;
  }
}
