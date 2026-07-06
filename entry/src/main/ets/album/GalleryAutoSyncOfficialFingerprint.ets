/**
 * 飞牛相册官方上传去重指纹（对齐 upload/notice 与移动端备份逻辑）：
 * - original_name：本地原始文件名
 * - file_size：字节大小
 * - file_create_time / mtime：文件修改时间（Unix 秒，与 Trim-Mtim 一致）
 *
 * 参考：飞牛社区说明「重复判断依据文件大小与修改日期」；Web 上传 notice 携带 original_name + file_create_time。
 */
import { GalleryListItem } from '../model/FnApiTypes';
import { LocalPhotoEntry } from './GalleryAutoSyncService';

const MTIME_TOLERANCE_SEC: number = 2;

interface OfficialFingerprintParts {
  name: string;
  size: number;
  mtimeSec: number;
}

function readRecordString(rec: Record<string, string | number | Object | undefined>, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const raw = rec[keys[i]];
    if (raw === undefined || raw === null) {
      continue;
    }
    const text = String(raw).trim();
    if (text.length > 0 && text !== 'null' && text !== 'undefined') {
      return text;
    }
  }
  return '';
}

function readRecordSize(rec: Record<string, string | number | Object | undefined>): number {
  const keys = ['fileSize', 'filesize', 'originalSize', 'original_size', 'size'];
  for (let i = 0; i < keys.length; i++) {
    const raw = rec[keys[i]];
    if (raw === undefined || raw === null) {
      continue;
    }
    const n = typeof raw === 'number' ? raw : Number(String(raw));
    if (Number.isFinite(n) && n > 0) {
      return Math.floor(n);
    }
  }
  return 0;
}

/** 解析飞牛日期串为 Unix 秒（YYYY:MM:DD HH:mm:ss 或 ISO） */
export function parseFnDateTimeToUnixSec(text: string): number {
  const t = text.trim();
  if (t.length === 0) {
    return 0;
  }
  const colonDate = /^(\d{4}):(\d{1,2}):(\d{1,2})\s+(\d{1,2}):(\d{1,2}):(\d{1,2})$/;
  const m = colonDate.exec(t);
  if (m !== null) {
    const d = new Date(
      Number(m[1]),
      Number(m[2]) - 1,
      Number(m[3]),
      Number(m[4]),
      Number(m[5]),
      Number(m[6])
    );
    const ms = d.getTime();
    if (Number.isFinite(ms) && ms > 0) {
      return Math.floor(ms / 1000);
    }
  }
  const parsed = Date.parse(t.replace(/:/g, '-').replace(' ', 'T'));
  if (Number.isFinite(parsed) && parsed > 0) {
    return Math.floor(parsed / 1000);
  }
  return 0;
}

export function mtimeSecFromMillis(ms: number): number {
  if (!Number.isFinite(ms) || ms <= 0) {
    return 0;
  }
  return Math.floor(ms / 1000);
}

export function officialUploadFingerprint(originalName: string, fileSize: number, mtimeSec: number): string {
  const name = originalName.trim();
  const size = Number.isFinite(fileSize) && fileSize > 0 ? Math.floor(fileSize) : 0;
  const mt = Number.isFinite(mtimeSec) && mtimeSec > 0 ? Math.floor(mtimeSec) : 0;
  return `${name}:${size}:${mt}`;
}

export function nasItemOriginalName(item: GalleryListItem): string {
  const rec = item as Record<string, string | number | Object | undefined>;
  return readRecordString(rec, ['originalName', 'original_name', 'fileName', 'filename', 'name', 'title']);
}

export function nasItemFileSize(item: GalleryListItem): number {
  const rec = item as Record<string, string | number | Object | undefined>;
  return readRecordSize(rec);
}

export function nasItemMtimeSec(item: GalleryListItem): number {
  const rec = item as Record<string, string | number | Object | undefined>;
  const directKeys = ['fileCreateTime', 'file_create_time', 'mtime', 'modifyTime', 'modifiedTime'];
  for (let i = 0; i < directKeys.length; i++) {
    const raw = rec[directKeys[i]];
    if (raw === undefined || raw === null) {
      continue;
    }
    if (typeof raw === 'number' && Number.isFinite(raw) && raw > 0) {
      return raw > 1e12 ? Math.floor(raw / 1000) : Math.floor(raw);
    }
    const parsed = parseFnDateTimeToUnixSec(String(raw));
    if (parsed > 0) {
      return parsed;
    }
  }
  const dateText = readRecordString(rec, ['dateTime', 'photoDateTime', 'createdAt', 'createTime']);
  return parseFnDateTimeToUnixSec(dateText);
}

export function localPhotoOfficialFingerprint(entry: LocalPhotoEntry): string {
  return officialUploadFingerprint(
    entry.fileName,
    entry.fileSize,
    mtimeSecFromMillis(entry.dateModifiedMs)
  );
}

export function nasItemOfficialFingerprint(item: GalleryListItem): string {
  const name = nasItemOriginalName(item);
  const size = nasItemFileSize(item);
  if (name.length === 0 || size <= 0) {
    return '';
  }
  return officialUploadFingerprint(name, size, nasItemMtimeSec(item));
}

export function buildNasOfficialFingerprints(items: GalleryListItem[]): Set<string> {
  const fingerprints = new Set<string>();
  for (let i = 0; i < items.length; i++) {
    const fp = nasItemOfficialFingerprint(items[i]);
    if (fp.length > 0) {
      fingerprints.add(fp);
    }
  }
  return fingerprints;
}

function parseFingerprintParts(fp: string): OfficialFingerprintParts | null {
  const lastColon = fp.lastIndexOf(':');
  if (lastColon <= 0) {
    return null;
  }
  const secondColon = fp.lastIndexOf(':', lastColon - 1);
  if (secondColon <= 0) {
    return null;
  }
  const name = fp.substring(0, secondColon);
  const size = Number(fp.substring(secondColon + 1, lastColon));
  const mtimeSec = Number(fp.substring(lastColon + 1));
  if (name.length === 0 || !Number.isFinite(size) || !Number.isFinite(mtimeSec)) {
    return null;
  }
  const parts: OfficialFingerprintParts = {
    name: name,
    size: Math.floor(size),
    mtimeSec: Math.floor(mtimeSec)
  };
  return parts;
}

/** 官方指纹匹配（mtime 允许 ±2 秒容差） */
export function officialFingerprintSetHas(set: Set<string>, fingerprint: string): boolean {
  if (set.has(fingerprint)) {
    return true;
  }
  const parts = parseFingerprintParts(fingerprint);
  if (parts === null || parts.mtimeSec <= 0) {
    return false;
  }
  for (let delta = -MTIME_TOLERANCE_SEC; delta <= MTIME_TOLERANCE_SEC; delta++) {
    if (delta === 0) {
      continue;
    }
    const alt = officialUploadFingerprint(parts.name, parts.size, parts.mtimeSec + delta);
    if (set.has(alt)) {
      return true;
    }
  }
  return false;
}
