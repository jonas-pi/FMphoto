import { FN_PHOTO_API_PREFIX } from '../../network/FnPhotoRoutes';
import { FolderViewCoverItem, GalleryListItem, PhotoFolderListItem } from '../../model/FnApiTypes';
import {
  FOLDER_BROWSE_DIR_ID_PREFIX,
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

type FolderBrowseLooseRec = Record<string, Object | string | number | boolean | undefined | null>;

function folderBrowseAsRec(
  value: Object | string | number | boolean | undefined | null
): FolderBrowseLooseRec | null {
  if (value === undefined || value === null || typeof value !== 'object') {
    return null;
  }
  if (Array.isArray(value)) {
    return null;
  }
  return value as FolderBrowseLooseRec;
}

function folderBrowseFirstRec(
  value: Object | string | number | boolean | undefined | null
): FolderBrowseLooseRec | null {
  if (Array.isArray(value)) {
    const arr = value as Object[];
    for (let i = 0; i < arr.length; i++) {
      const rec = folderBrowseAsRec(arr[i]);
      if (rec !== null) {
        return rec;
      }
    }
    return null;
  }
  return folderBrowseAsRec(value);
}

function folderBrowseReadId(rec: FolderBrowseLooseRec): string {
  const idVal = rec['id'] ?? rec['photoId'] ?? rec['photo_id'];
  if (typeof idVal === 'string') {
    return idVal.trim();
  }
  if (typeof idVal === 'number' && Number.isFinite(idVal)) {
    return `${Math.floor(idVal)}`;
  }
  return '';
}

function folderBrowseReadUuid(rec: FolderBrowseLooseRec): string {
  const keys: string[] = ['uuid', 'photoUUID', 'photo_uuid', 'session'];
  for (let i = 0; i < keys.length; i++) {
    const v = rec[keys[i]];
    if (typeof v === 'string' && v.trim().length > 0) {
      return v.trim();
    }
  }
  return '';
}

function folderBrowseReadThumbUrl(rec: FolderBrowseLooseRec): string {
  const keys: string[] = ['xsUrl', 'sUrl', 'mUrl', 'xxsUrl', 'cover', 'thumb', 'url'];
  for (let i = 0; i < keys.length; i++) {
    const v = rec[keys[i]];
    if (typeof v === 'string' && v.trim().length > 0 && v.indexOf('/stream/') >= 0) {
      return v.trim();
    }
  }
  const additional = folderBrowseAsRec(rec['additional']);
  if (additional !== null) {
    const th = folderBrowseAsRec(additional['thumbnail']);
    if (th !== null) {
      const nested = folderBrowseReadThumbUrl(th);
      if (nested.length > 0) {
        return nested;
      }
    }
  }
  return '';
}

function folderBrowseCoverRelFromPhoto(rec: FolderBrowseLooseRec): string {
  const nested = folderBrowseAsRec(rec['photo'] ?? rec['media'] ?? rec['item']);
  if (nested !== null) {
    const nestedRel = folderBrowseCoverRelFromPhoto(nested);
    if (nestedRel.length > 0) {
      return nestedRel;
    }
  }
  const direct = folderBrowseReadThumbUrl(rec);
  if (direct.length > 0) {
    return direct;
  }
  return folderBrowseCoverRel(folderBrowseReadId(rec), folderBrowseReadUuid(rec));
}

/** 官方封面项是 {dirPath, cover[], defaultCover[]}，getPosters 取 cover[0].id + uuid。 */
export function folderBrowseCoverRelFromItem(item: FolderViewCoverItem): string {
  const rec = item as FolderBrowseLooseRec;
  const fromCover = folderBrowseFirstRec(rec['cover']);
  if (fromCover !== null) {
    const uri = folderBrowseCoverRelFromPhoto(fromCover);
    if (uri.length > 0) {
      return uri;
    }
  }
  const fromDefault = folderBrowseFirstRec(rec['defaultCover'] ?? rec['default_cover']);
  if (fromDefault !== null) {
    const uri = folderBrowseCoverRelFromPhoto(fromDefault);
    if (uri.length > 0) {
      return uri;
    }
  }
  return folderBrowseCoverRelFromPhoto(rec);
}

function folderBrowseCoverItemPath(item: FolderViewCoverItem): string {
  const rec = item as FolderBrowseLooseRec;
  const dirVal = rec['dirPath'];
  const dir = typeof dirVal === 'string' ? dirVal : '';
  return folderBrowseNormalizePath(dir.length > 0 ? dir : (item.path ?? item.folderPath ?? ''));
}

function folderBrowseCoverItemName(item: FolderViewCoverItem): string {
  const rec = item as FolderBrowseLooseRec;
  const dirVal = rec['dirPath'];
  const dir = typeof dirVal === 'string' ? dirVal : '';
  const nameVal = rec['dirName'] ?? rec['name'];
  const explicit = typeof nameVal === 'string' ? nameVal : '';
  return folderBrowseLabelOf(dir.length > 0 ? dir : (item.path ?? item.folderPath ?? ''), explicit);
}

export function folderBrowseFoldersFromList(raw: PhotoFolderListItem[]): FolderBrowseFolderItem[] {
  const out: FolderBrowseFolderItem[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < raw.length; i++) {
    const src = raw[i];
    const path = folderBrowsePathOf(src);
    if (path.length === 0 || folderBrowseIsOsRootPath(path) || seen.has(path)) {
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
  covers: FolderViewCoverItem[],
  requestedNames: string[]
): void {
  const byName = new Map<string, string>();
  const byPath = new Map<string, string>();
  for (let i = 0; i < covers.length; i++) {
    const uri = folderBrowseCoverRelFromItem(covers[i]);
    if (uri.length === 0) {
      continue;
    }
    const name = folderBrowseCoverItemName(covers[i]);
    if (name.length > 0 && !byName.has(name)) {
      byName.set(name, uri);
    }
    const p = folderBrowseCoverItemPath(covers[i]);
    if (p.length > 0 && !byPath.has(p)) {
      byPath.set(p, uri);
    }
    if (i < requestedNames.length) {
      const req = requestedNames[i].trim();
      if (req.length > 0) {
        const reqPath = folderBrowseNormalizePath(req);
        if (reqPath.length > 0 && !byPath.has(reqPath)) {
          byPath.set(reqPath, uri);
        }
        const reqName = folderBrowseLabelOf(req);
        if (reqName.length > 0 && !byName.has(reqName)) {
          byName.set(reqName, uri);
        }
      }
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

/** 根目录封面要用完整路径当 dirNames；子目录用文件夹名，与 Web setPosters 一致。 */
export function folderBrowseCoverDirNames(folders: FolderBrowseFolderItem[], currentPath: string): string[] {
  const atRoot = currentPath.trim().length === 0;
  const names: string[] = [];
  for (let i = 0; i < folders.length; i++) {
    const folder = folders[i];
    const value = atRoot ? folder.path : folder.name;
    if (value.length > 0) {
      names.push(value);
    }
  }
  return names;
}

/** 子目录封面请求失败时，改用另一种命名再试一次。 */
export function folderBrowseCoverDirNamesFallback(folders: FolderBrowseFolderItem[], currentPath: string): string[] {
  const atRoot = currentPath.trim().length === 0;
  const names: string[] = [];
  for (let i = 0; i < folders.length; i++) {
    const folder = folders[i];
    const value = atRoot ? folder.name : folder.path;
    if (value.length > 0) {
      names.push(value);
    }
  }
  return names;
}

/** NAS/系统根路径，禁止作为浏览目标。 */
export function folderBrowseIsOsRootPath(path: string): boolean {
  const normalized = folderBrowseNormalizePath(path);
  return normalized === '/' || normalized === '\\';
}

/**
 * 进入文件夹浏览页时的路径栈：只放目标目录自己。
 * 禁止按 `/` 拆出祖先，否则返回会一路退到存储根。
 */
export function folderBrowseLandingStack(path: string): string[] {
  const normalized = folderBrowseNormalizePath(path);
  if (normalized.length === 0 || folderBrowseIsOsRootPath(normalized)) {
    return [];
  }
  return [normalized];
}

/** child 是否就是 floor，或位于 floor 之下。空 floor 表示相册文件夹根。 */
export function folderBrowsePathAllowed(path: string, floor: string): boolean {
  const target = folderBrowseNormalizePath(path);
  if (folderBrowseIsOsRootPath(target)) {
    return false;
  }
  const root = folderBrowseNormalizePath(floor);
  if (root.length === 0) {
    return target.length > 0;
  }
  return target === root || target.indexOf(`${root}/`) === 0;
}

/** 从相册已配置根目录中找出包含目标路径的最外层授权根。 */
export function folderBrowseAuthorizedRoot(
  targetPath: string,
  roots: FolderBrowseFolderItem[]
): string {
  const target = folderBrowseNormalizePath(targetPath);
  let matched = '';
  for (let i = 0; i < roots.length; i++) {
    const root = folderBrowseNormalizePath(roots[i].path);
    if (root.length === 0 || folderBrowseIsOsRootPath(root) ||
      !folderBrowsePathAllowed(target, root)) {
      continue;
    }
    if (matched.length === 0 || root.length < matched.length) {
      matched = root;
    }
  }
  return matched;
}

/** 仅在授权根内构造可返回路径栈，不生成授权根以上的任何祖先。 */
export function folderBrowseStackWithinRoot(targetPath: string, rootPath: string): string[] {
  const target = folderBrowseNormalizePath(targetPath);
  const root = folderBrowseNormalizePath(rootPath);
  if (root.length === 0 || !folderBrowsePathAllowed(target, root)) {
    return [];
  }
  const stack: string[] = [root];
  if (target === root) {
    return stack;
  }
  const suffix = target.substring(root.length + 1);
  const segments = suffix.split('/');
  let current = root;
  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i];
    if (segment.length === 0) {
      continue;
    }
    current = `${current}/${segment}`;
    stack.push(current);
  }
  return stack;
}

export function folderBrowseMediaId(item: GalleryListItem): string {
  const id = item.id;
  if (id === undefined) {
    return '';
  }
  return String(id).trim();
}

export function folderBrowseDirSelectionId(path: string): string {
  const trimmed = path.trim();
  if (trimmed.length === 0) {
    return '';
  }
  return `${FOLDER_BROWSE_DIR_ID_PREFIX}${trimmed}`;
}

export function folderBrowseIsDirSelectionId(id: string): boolean {
  return id.indexOf(FOLDER_BROWSE_DIR_ID_PREFIX) === 0 &&
    id.length > FOLDER_BROWSE_DIR_ID_PREFIX.length;
}

export function folderBrowseDirPathFromSelectionId(id: string): string {
  if (!folderBrowseIsDirSelectionId(id)) {
    return '';
  }
  return id.substring(FOLDER_BROWSE_DIR_ID_PREFIX.length);
}

export function folderBrowseSelectionIdOf(item: FolderBrowseGridItem): string {
  if (item.kind === FOLDER_BROWSE_KIND_FOLDER) {
    return folderBrowseDirSelectionId(item.folderPath);
  }
  if (item.media !== undefined) {
    return folderBrowseMediaId(item.media);
  }
  return '';
}

export function folderBrowseSelectionHasFolder(ids: string[]): boolean {
  for (let i = 0; i < ids.length; i++) {
    if (folderBrowseIsDirSelectionId(ids[i])) {
      return true;
    }
  }
  return false;
}

export function folderBrowseMergeMediaUnique(
  acc: GalleryListItem[],
  incoming: GalleryListItem[]
): GalleryListItem[] {
  const seen = new Set<string>();
  const out: GalleryListItem[] = [];
  for (let i = 0; i < acc.length; i++) {
    const id = folderBrowseMediaId(acc[i]);
    if (id.length > 0) {
      seen.add(id);
    }
    out.push(acc[i]);
  }
  for (let i = 0; i < incoming.length; i++) {
    const id = folderBrowseMediaId(incoming[i]);
    if (id.length > 0 && seen.has(id)) {
      continue;
    }
    if (id.length > 0) {
      seen.add(id);
    }
    out.push(incoming[i]);
  }
  return out;
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
