import { FN_PHOTO_API_PREFIX } from '../../network/FnPhotoRoutes';
import { FolderViewCoverItem, GalleryListItem, PhotoFolderListItem } from '../../model/FnApiTypes';
import {
  FOLDER_BROWSE_KIND_FOLDER,
  FOLDER_BROWSE_KIND_MEDIA,
  FolderBrowseFolderItem,
  FolderBrowseGridItem
} from './FolderBrowseTypes';

export function folderBrowseNormalizePath(path: string): string {
  let normalized = path.trim().replace(/\\/g, '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

export function folderBrowseLabelOf(path: string, name: string = ''): string {
  const explicit = name.trim();
  if (explicit.length > 0) {
    return explicit;
  }
  const trimmed = folderBrowseNormalizePath(path);
  const idx = trimmed.lastIndexOf('/');
  if (idx < 0 || idx >= trimmed.length - 1) {
    return trimmed;
  }
  return trimmed.substring(idx + 1);
}

export function folderBrowsePathOf(item: PhotoFolderListItem): string {
  const rec = item as Record<string, Object | string | number | boolean | undefined | null>;
  const keys: string[] = ['folderPath', 'folder_path', 'path', 'filePath', 'file_path', 'fullPath', 'dir', 'key'];
  for (let i = 0; i < keys.length; i++) {
    const v = rec[keys[i]];
    if (typeof v === 'string') {
      const t = folderBrowseNormalizePath(v);
      if (t.length > 0) {
        return t;
      }
    }
  }
  return '';
}

export function folderBrowseCoverRel(id: string, uuid: string): string {
  if (id.length === 0 || uuid.length === 0) {
    return '';
  }
  return `${FN_PHOTO_API_PREFIX}/stream/p/t/${id}/xs/${uuid}`;
}

export function folderBrowseCoverRelFromItem(item: FolderViewCoverItem): string {
  const idVal = item.id;
  let id = '';
  if (typeof idVal === 'string') {
    id = idVal.trim();
  } else if (typeof idVal === 'number' && Number.isFinite(idVal)) {
    id = `${Math.floor(idVal)}`;
  }
  if (id.length === 0) {
    return '';
  }
  let uuid = '';
  const uuidA = item.uuid;
  const uuidB = item.photoUUID;
  if (uuidA !== undefined && uuidA.length > 0) {
    uuid = uuidA.trim();
  } else if (uuidB !== undefined && uuidB.length > 0) {
    uuid = uuidB.trim();
  }
  return folderBrowseCoverRel(id, uuid);
}

export function folderBrowseFoldersFromList(raw: PhotoFolderListItem[]): FolderBrowseFolderItem[] {
  const out: FolderBrowseFolderItem[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < raw.length; i++) {
    const src = raw[i];
    const path = folderBrowsePathOf(src);
    if (path.length === 0 || seen.has(path)) {
      continue;
    }
    seen.add(path);
    const item = new FolderBrowseFolderItem();
    item.path = path;
    item.name = folderBrowseLabelOf(path, src.name ?? src.dirName ?? '');
    out.push(item);
  }
  return out;
}

export function folderBrowseApplyCoverUris(
  folders: FolderBrowseFolderItem[],
  covers: FolderViewCoverItem[]
): void {
  const byName = new Map<string, string>();
  const byPath = new Map<string, string>();
  for (let i = 0; i < covers.length; i++) {
    const uri = folderBrowseCoverRelFromItem(covers[i]);
    if (uri.length === 0) {
      continue;
    }
    const cover = covers[i];
    const name = folderBrowseLabelOf(
      cover.path ?? cover.folderPath ?? '',
      cover.dirName ?? cover.name ?? ''
    );
    if (name.length > 0 && !byName.has(name)) {
      byName.set(name, uri);
    }
    const p = folderBrowseNormalizePath(cover.path ?? cover.folderPath ?? '');
    if (p.length > 0 && !byPath.has(p)) {
      byPath.set(p, uri);
    }
  }
  for (let i = 0; i < folders.length; i++) {
    const folder = folders[i];
    let uri = byPath.get(folder.path);
    if (uri === undefined || uri.length === 0) {
      uri = byName.get(folder.name);
    }
    if ((uri === undefined || uri.length === 0) && i < covers.length) {
      uri = folderBrowseCoverRelFromItem(covers[i]);
    }
    if (uri !== undefined && uri.length > 0) {
      folder.coverUri = uri;
    }
  }
}

function mediaItemKey(item: GalleryListItem, index: number): string {
  const id = item.id;
  if (id !== undefined && String(id).trim().length > 0) {
    return `file_${String(id).trim()}`;
  }
  const uuid = item.photoUUID;
  if (uuid !== undefined && uuid.trim().length > 0) {
    return `file_${uuid.trim()}`;
  }
  return `file_idx_${index}`;
}

function mediaItemTitle(item: GalleryListItem): string {
  const name = item.fileName ?? item.filename ?? item.name ?? item.title;
  if (name !== undefined && name.trim().length > 0) {
    return name.trim();
  }
  return '未命名';
}

export function folderBrowseBuildGrid(
  folders: FolderBrowseFolderItem[],
  media: GalleryListItem[]
): FolderBrowseGridItem[] {
  const out: FolderBrowseGridItem[] = [];
  for (let i = 0; i < folders.length; i++) {
    const folder = folders[i];
    const item = new FolderBrowseGridItem();
    item.kind = FOLDER_BROWSE_KIND_FOLDER;
    item.key = `dir_${folder.path}`;
    item.title = folder.name;
    item.folderPath = folder.path;
    item.coverUri = folder.coverUri;
    out.push(item);
  }
  for (let i = 0; i < media.length; i++) {
    const src = media[i];
    const item = new FolderBrowseGridItem();
    item.kind = FOLDER_BROWSE_KIND_MEDIA;
    item.key = mediaItemKey(src, i);
    item.title = mediaItemTitle(src);
    item.media = src;
    item.mediaIndex = i;
    out.push(item);
  }
  return out;
}

export function folderBrowsePermissionMessage(message: string): string {
  const t = message.trim();
  if (t.indexOf('权限') >= 0 || t.indexOf('找不到') >= 0 || t.indexOf('not found') >= 0) {
    return '文件夹找不到或无读取权限';
  }
  return t;
}
