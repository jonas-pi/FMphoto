/**
 * 本地相册同步：通过系统 PhotoViewPicker 选取照片，无需 READ_IMAGEVIDEO 受限权限。
 * 与 NAS 官方指纹（original_name + size + mtime）及本机账本比对。
 */
import { fileIo } from '@kit.CoreFileKit';
import { GalleryListItem } from '../model/FnApiTypes';
import {
  buildNasDedupeIndex,
  NasDedupeIndex,
  nasDedupeIndexHasLocal,
  officialUploadFingerprint
} from './GalleryAutoSyncOfficialFingerprint';
import { GalleryAutoSyncLedger } from './GalleryAutoSyncLedger';
import { LocalPhotoEntry } from './GalleryAutoSyncService';

/** 从 Picker 返回的 URI 解析文件名 */
export function fileNameFromPickerUri(uri: string): string {
  try {
    const decoded = decodeURIComponent(uri);
    const slash = decoded.lastIndexOf('/');
    if (slash >= 0 && slash < decoded.length - 1) {
      return decoded.substring(slash + 1);
    }
    return decoded;
  } catch (_e) {
    return uri;
  }
}

function statMtimeToUnixSec(st: object): number {
  const o = st as Record<string, number | bigint | string | undefined>;
  const rawVal = o['mtime'];
  if (rawVal === undefined || rawVal === null) {
    return 0;
  }
  const raw = typeof rawVal === 'bigint' ? Number(rawVal) : Number(String(rawVal));
  if (!Number.isFinite(raw) || raw <= 0) {
    return 0;
  }
  if (raw > 1e15) {
    return Math.floor(raw / 1e9);
  }
  if (raw > 1e12) {
    return Math.floor(raw / 1e3);
  }
  return Math.floor(raw);
}

function statMtimeSecFromFd(fdNum: number): number {
  try {
    const st = fileIo.statSync(fdNum);
    return statMtimeToUnixSec(st);
  } catch (_e) {
    return 0;
  }
}

/** 读取 Picker 授权 URI 的文件大小 */
export function fileSizeFromPickerUri(uri: string): number {
  let fdNum = -1;
  try {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    fdNum = file.fd;
    const stat = fileIo.statSync(fdNum);
    const size = Number(stat.size);
    if (Number.isFinite(size) && size >= 0) {
      return size;
    }
    return 0;
  } catch (_e) {
    return 0;
  } finally {
    if (fdNum >= 0) {
      try {
        fileIo.closeSync(fdNum);
      } catch (_e) {
      }
    }
  }
}

/** 读取 Picker URI 的文件修改时间（Unix 秒） */
export function mtimeSecFromPickerUri(uri: string): number {
  let fdNum = -1;
  try {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    fdNum = file.fd;
    return statMtimeSecFromFd(fdNum);
  } catch (_e) {
    return 0;
  } finally {
    if (fdNum >= 0) {
      try {
        fileIo.closeSync(fdNum);
      } catch (_e) {
      }
    }
  }
}

export function pickerUriOfficialFingerprint(uri: string): string {
  const name = fileNameFromPickerUri(uri);
  const size = fileSizeFromPickerUri(uri);
  const mt = mtimeSecFromPickerUri(uri);
  return officialUploadFingerprint(name, size, mt);
}

/** 将 Picker URI 转为账本条目（与 Trim-Mtim 同源的 fileIo.mtime） */
export function localPhotoEntryFromPickerUri(uri: string): LocalPhotoEntry {
  const mtimeSec = mtimeSecFromPickerUri(uri);
  return {
    uri: uri,
    fileName: fileNameFromPickerUri(uri),
    fileSize: fileSizeFromPickerUri(uri),
    dateModifiedMs: mtimeSec > 0 ? mtimeSec * 1000 : 0,
    mimeType: ''
  };
}

/** 过滤 NAS 与账本中尚不存在的本地照片 URI（官方指纹 + name/size 软匹配）。 */
export function filterUnsyncedPickerUrisWithIndex(
  uris: string[],
  nasIndex: NasDedupeIndex,
  ledger: Set<string>
): string[] {
  const unsynced: string[] = [];
  for (let i = 0; i < uris.length; i++) {
    const uri = uris[i];
    const name = fileNameFromPickerUri(uri);
    const size = fileSizeFromPickerUri(uri);
    if (name.length === 0 || size <= 0) {
      continue;
    }
    const mt = mtimeSecFromPickerUri(uri);
    if (nasDedupeIndexHasLocal(nasIndex, name, size, mt)) {
      continue;
    }
    const entry = localPhotoEntryFromPickerUri(uri);
    if (GalleryAutoSyncLedger.hasEntry(ledger, entry)) {
      continue;
    }
    unsynced.push(uri);
  }
  return unsynced;
}

/** @deprecated 使用 filterUnsyncedPickerUrisWithIndex */
export function filterUnsyncedPickerUrisWithFingerprints(
  uris: string[],
  nasFingerprints: Set<string>,
  ledger: Set<string>
): string[] {
  const index: NasDedupeIndex = {
    fingerprints: nasFingerprints,
    sizeMtimeKeys: new Set<string>(),
    nameSizeKeys: new Set<string>()
  };
  return filterUnsyncedPickerUrisWithIndex(uris, index, ledger);
}

/** @deprecated 使用 filterUnsyncedPickerUrisWithIndex */
export function filterUnsyncedPickerUris(uris: string[], nasTimeline: GalleryListItem[]): string[] {
  return filterUnsyncedPickerUrisWithIndex(uris, buildNasDedupeIndex(nasTimeline), new Set<string>());
}
