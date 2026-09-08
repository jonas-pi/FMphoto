/**
 * 打开文件夹浏览页时的起始路径。
 * Home 的 NavDestination 不把 param 传进页面，因此用中转站，避免只能从根目录进。
 *
 * lockToEntry：从媒体目录「跳转到文件夹视图」时为 true。
 * 此时返回不得越过进入时的目标文件夹，更不能走到 NAS/系统根。
 *
 * forceRouter：当前页已是独立 Router 时，禁止把文件夹页压进 Home 内部栈。
 */
export class FolderBrowseNavStore {
  static pendingFolderPath: string = '';
  static pendingLockToEntry: boolean = false;
  static pendingForceRouter: boolean = false;

  static setPending(path: string, lockToEntry: boolean, forceRouter: boolean = false): void {
    FolderBrowseNavStore.pendingFolderPath = path.trim();
    FolderBrowseNavStore.pendingLockToEntry = lockToEntry;
    FolderBrowseNavStore.pendingForceRouter = forceRouter;
  }

  static setPendingPath(path: string): void {
    FolderBrowseNavStore.setPending(path, path.trim().length > 0);
  }

  static consumePendingPath(): string {
    const path = FolderBrowseNavStore.pendingFolderPath.trim();
    FolderBrowseNavStore.pendingFolderPath = '';
    return path;
  }

  static consumeLockToEntry(): boolean {
    const lock = FolderBrowseNavStore.pendingLockToEntry;
    FolderBrowseNavStore.pendingLockToEntry = false;
    return lock;
  }

  static consumeForceRouter(): boolean {
    const force = FolderBrowseNavStore.pendingForceRouter;
    FolderBrowseNavStore.pendingForceRouter = false;
    return force;
  }
}
