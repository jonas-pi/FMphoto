import { AppSession } from '../../auth/AppSession';
import {
  FnClientResult,
  FolderViewCoverItem,
  GalleryListItem,
  PhotoFolderListData,
  PhotoFolderListItem
} from '../../model/FnApiTypes';
import {
  FOLDER_BROWSE_COVER_BATCH,
  FOLDER_BROWSE_PAGE_SIZE,
  FolderBrowseFolderItem
} from './FolderBrowseTypes';
import {
  folderBrowseAuthorizedRoot,
  folderBrowseFoldersFromList,
  folderBrowseIsOsRootPath,
  folderBrowsePathAllowed,
  folderBrowsePermissionMessage,
  folderBrowseStackWithinRoot
} from './FolderBrowseLogic';

export interface FolderBrowseDataLoaderHost {
  loadGen: number;
  loading: boolean;
  loadingMore: boolean;
  error: string;
  selectionMode: boolean;
  folders: FolderBrowseFolderItem[];
  mediaItems: GalleryListItem[];
  mediaOffset: number;
  mediaHasMore: boolean;
  lockToEntry: boolean;
  entryFloorResolved: boolean;
  allowedRootPaths: string[];
  entryFloorPath: string;
  pathStack: string[];
  currentPath(): string;
  syncTitle(): void;
  exitSelection(): void;
  publishGrid(): void;
  navigateOut(): void;
  syncFolderHierarchyState(): void;
  loadCovers(gen: number, currentPath: string): void;
}

export async function folderBrowseFetchCoverBatch(
  currentPath: string,
  names: string[]
): Promise<FolderViewCoverItem[]> {
  const allCovers: FolderViewCoverItem[] = [];
  const client = AppSession.getClient();
  if (client === null || names.length === 0) {
    return allCovers;
  }
  let offset = 0;
  while (offset < names.length) {
    const end = Math.min(offset + FOLDER_BROWSE_COVER_BATCH, names.length);
    const batch: string[] = [];
    for (let i = offset; i < end; i++) {
      batch.push(names[i]);
    }
    const res = await client.getFolderViewCover(currentPath, batch, 20000);
    if (res.success && res.data !== undefined) {
      const coverList: FolderViewCoverItem[] = res.data.list !== undefined
        ? res.data.list
        : (res.data.items !== undefined ? res.data.items : []);
      for (let i = 0; i < coverList.length; i++) {
        allCovers.push(coverList[i]);
      }
    }
    offset = end;
  }
  return allCovers;
}

export async function folderBrowseLoadCurrent(host: FolderBrowseDataLoaderHost, reset: boolean): Promise<void> {
  const gen = ++host.loadGen;
  host.syncTitle();
  host.error = '';
  if (reset) {
    if (host.selectionMode) {
      host.exitSelection();
    }
    host.loading = true;
    host.folders = [];
    host.mediaItems = [];
    host.mediaOffset = 0;
    host.mediaHasMore = false;
    host.publishGrid();
  }
  const client = AppSession.getClient();
  if (client === null) {
    host.loading = false;
    host.error = '未登录';
    return;
  }
  const path = host.currentPath();
  if (host.lockToEntry && !host.entryFloorResolved) {
    const rootRes = await client.getPhotoFolderList(20000);
    if (gen !== host.loadGen) {
      return;
    }
    if (!rootRes.success || rootRes.data === undefined) {
      host.loading = false;
      host.error = folderBrowsePermissionMessage(rootRes.message ?? '无法确认文件夹访问范围');
      return;
    }
    const rootRaw: PhotoFolderListItem[] = rootRes.data.list ?? rootRes.data.items ?? [];
    const rootFolders = folderBrowseFoldersFromList(rootRaw);
    host.allowedRootPaths = rootFolders.map((item: FolderBrowseFolderItem): string => item.path);
    const authorizedRoot = folderBrowseAuthorizedRoot(path, rootFolders);
    const safeStack = folderBrowseStackWithinRoot(path, authorizedRoot);
    if (authorizedRoot.length === 0 || safeStack.length === 0) {
      host.loading = false;
      host.error = '该路径不在已授权的相册文件夹内';
      return;
    }
    host.entryFloorPath = authorizedRoot;
    host.entryFloorResolved = true;
    // '' 是安全的虚拟根层，展示 photo/folder/list 返回的 Document、照片等已配置目录。
    host.pathStack = [''].concat(safeStack);
    host.syncFolderHierarchyState();
  }
  if (folderBrowseIsOsRootPath(path) ||
    (host.lockToEntry && path.length > 0 && !folderBrowsePathAllowed(path, host.entryFloorPath))) {
    host.loading = false;
    host.navigateOut();
    return;
  }
  try {
    let folderRes: FnClientResult<PhotoFolderListData>;
    if (path.length === 0) {
      folderRes = await client.getPhotoFolderList(20000);
    } else {
      folderRes = await client.getFolderViewFolderList(path, false, 2, 20000);
    }
    if (gen !== host.loadGen) {
      return;
    }
    if (!folderRes.success || folderRes.data === undefined) {
      host.error = folderBrowsePermissionMessage(folderRes.message ?? '文件夹列表加载失败');
      host.loading = false;
      return;
    }
    const rawFolders: PhotoFolderListItem[] = folderRes.data.list ?? folderRes.data.items ?? [];
    const listed = folderBrowseFoldersFromList(rawFolders);
    if (path.length === 0) {
      host.allowedRootPaths = listed.map((item: FolderBrowseFolderItem): string => item.path);
      host.folders = listed;
    } else if (host.lockToEntry) {
      const kept: FolderBrowseFolderItem[] = [];
      for (let i = 0; i < listed.length; i++) {
        const folder = listed[i];
        if (folder.path !== host.entryFloorPath &&
          folderBrowsePathAllowed(folder.path, host.entryFloorPath)) {
          kept.push(folder);
        }
      }
      host.folders = kept;
    } else {
      host.folders = listed;
    }

    if (path.length > 0) {
      const fileRes = await client.getFolderViewFileList(path, FOLDER_BROWSE_PAGE_SIZE, 0, false, 2, 20000);
      if (gen !== host.loadGen) {
        return;
      }
      if (!fileRes.success || fileRes.data === undefined) {
        host.error = folderBrowsePermissionMessage(fileRes.message ?? '文件夹媒体加载失败');
        host.loading = false;
        host.publishGrid();
        host.loadCovers(gen, path);
        return;
      }
      host.mediaItems = fileRes.data.slice();
      host.mediaOffset = host.mediaItems.length;
      host.mediaHasMore = fileRes.data.length >= FOLDER_BROWSE_PAGE_SIZE;
    } else {
      host.mediaItems = [];
      host.mediaOffset = 0;
      host.mediaHasMore = false;
    }

    if (host.folders.length === 0 && host.mediaItems.length === 0) {
      host.error = path.length === 0 ? '文件夹列表为空' : '文件夹为空';
    }
    host.publishGrid();
    host.loading = false;
    host.loadCovers(gen, path);
  } catch (e) {
    if (gen !== host.loadGen) {
      return;
    }
    host.error = String(e) || '文件夹加载异常';
    host.loading = false;
  }
}

export async function folderBrowseLoadMoreMedia(host: FolderBrowseDataLoaderHost): Promise<void> {
  const path = host.currentPath();
  if (host.loading || host.loadingMore || !host.mediaHasMore || path.length === 0) {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    return;
  }
  const gen = host.loadGen;
  host.loadingMore = true;
  try {
    const res = await client.getFolderViewFileList(
      path,
      FOLDER_BROWSE_PAGE_SIZE,
      host.mediaOffset,
      false,
      2,
      20000
    );
    if (gen !== host.loadGen) {
      return;
    }
    if (!res.success || res.data === undefined) {
      return;
    }
    const next = res.data;
    if (next.length === 0) {
      host.mediaHasMore = false;
      return;
    }
    const merged: GalleryListItem[] = [];
    for (let i = 0; i < host.mediaItems.length; i++) {
      merged.push(host.mediaItems[i]);
    }
    for (let i = 0; i < next.length; i++) {
      merged.push(next[i]);
    }
    host.mediaItems = merged;
    host.mediaOffset = host.mediaItems.length;
    host.mediaHasMore = next.length >= FOLDER_BROWSE_PAGE_SIZE;
    host.publishGrid();
  } finally {
    if (gen === host.loadGen) {
      host.loadingMore = false;
    }
  }
}
