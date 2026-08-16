/**
 * 厂商单文件动图拆分：Motion Photo / Micro Video / livp(ZIP STORE 或 DEFLATE)。
 * 仅在已判定为实况但缺少独立 videoUrl 时调用。
 */
import { zlib } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';

const FTYP_0: number = 0x66;
const FTYP_1: number = 0x74;
const FTYP_2: number = 0x79;
const FTYP_3: number = 0x70;
const JPEG_SOI_0: number = 0xFF;
const JPEG_SOI_1: number = 0xD8;
const ZIP_LOCAL_0: number = 0x50;
const ZIP_LOCAL_1: number = 0x4B;
const ZIP_LOCAL_2: number = 0x03;
const ZIP_LOCAL_3: number = 0x04;
const MPVD_0: number = 0x6D;
const MPVD_1: number = 0x70;
const MPVD_2: number = 0x76;
const MPVD_3: number = 0x64;

export class SplitLivePhotoResult {
  imageBytes: ArrayBuffer = new ArrayBuffer(0);
  videoBytes: ArrayBuffer = new ArrayBuffer(0);
  imageExt: string = 'jpg';
  videoExt: string = 'mp4';
}

function readAscii(bytes: Uint8Array, start: number, len: number): string {
  const end = Math.min(bytes.length, start + len);
  let out = '';
  for (let i = start; i < end; i++) {
    out += String.fromCharCode(bytes[i]);
  }
  return out;
}

function indexOfAscii(bytes: Uint8Array, needle: string, from: number, to: number): number {
  if (needle.length === 0 || from >= to) {
    return -1;
  }
  const n0 = needle.charCodeAt(0);
  const max = to - needle.length;
  for (let i = from; i <= max; i++) {
    if (bytes[i] !== n0) {
      continue;
    }
    let ok = true;
    for (let k = 1; k < needle.length; k++) {
      if (bytes[i + k] !== needle.charCodeAt(k)) {
        ok = false;
        break;
      }
    }
    if (ok) {
      return i;
    }
  }
  return -1;
}

function parseUintAfterKey(text: string, key: string): number {
  const idx = text.indexOf(key);
  if (idx < 0) {
    return 0;
  }
  let i = idx + key.length;
  while (i < text.length) {
    const c = text.charAt(i);
    if (c === '"' || c === '=' || c === '>' || c === ' ' || c === '\t' || c === '\n' || c === '\r') {
      i++;
      continue;
    }
    break;
  }
  let digits = '';
  while (i < text.length) {
    const c = text.charAt(i);
    if (c < '0' || c > '9') {
      break;
    }
    digits += c;
    i++;
  }
  if (digits.length === 0) {
    return 0;
  }
  const n = Number(digits);
  return Number.isFinite(n) ? Math.floor(n) : 0;
}

function findLastFtypBoxStart(bytes: Uint8Array): number {
  const minScan = Math.max(4, bytes.length - 32 * 1024 * 1024);
  for (let i = bytes.length - 8; i >= minScan; i--) {
    if (bytes[i] === FTYP_0 && bytes[i + 1] === FTYP_1 && bytes[i + 2] === FTYP_2 && bytes[i + 3] === FTYP_3) {
      const boxStart = i - 4;
      if (boxStart >= 0) {
        return boxStart;
      }
    }
  }
  return -1;
}

function findMpvdPayloadStart(bytes: Uint8Array): number {
  const idx = indexOfAscii(bytes, 'mpvd', 0, Math.min(bytes.length, 8 * 1024 * 1024));
  if (idx < 4) {
    return -1;
  }
  // mpvd box: size(4) + 'mpvd'(4) + payload
  return idx + 4;
}

function sliceBuffer(bytes: Uint8Array, start: number, end: number): ArrayBuffer {
  const len = Math.max(0, end - start);
  const out = new ArrayBuffer(len);
  const dst = new Uint8Array(out);
  dst.set(bytes.subarray(start, start + len));
  return out;
}

function looksLikeJpeg(bytes: Uint8Array): boolean {
  return bytes.length >= 2 && bytes[0] === JPEG_SOI_0 && bytes[1] === JPEG_SOI_1;
}

function looksLikeZip(bytes: Uint8Array): boolean {
  return bytes.length >= 4 &&
    bytes[0] === ZIP_LOCAL_0 && bytes[1] === ZIP_LOCAL_1 &&
    bytes[2] === ZIP_LOCAL_2 && bytes[3] === ZIP_LOCAL_3;
}

function extFromZipName(name: string): string {
  const lower = name.toLowerCase();
  const dot = lower.lastIndexOf('.');
  return dot >= 0 ? lower.substring(dot + 1) : '';
}

function isImageExt(ext: string): boolean {
  return ext === 'jpg' || ext === 'jpeg' || ext === 'png' || ext === 'heic' || ext === 'heif' || ext === 'webp';
}

function isVideoExt(ext: string): boolean {
  return ext === 'mp4' || ext === 'mov' || ext === 'm4v';
}

function readU16le(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function readU32le(bytes: Uint8Array, offset: number): number {
  return bytes[offset] + bytes[offset + 1] * 256 + bytes[offset + 2] * 65536 + bytes[offset + 3] * 16777216;
}

function splitZipStoredLivp(bytes: Uint8Array): SplitLivePhotoResult | undefined {
  let offset = 0;
  let imageBytes: ArrayBuffer | undefined = undefined;
  let videoBytes: ArrayBuffer | undefined = undefined;
  let imageExt = 'jpg';
  let videoExt = 'mp4';
  while (offset + 30 <= bytes.length) {
    if (!(bytes[offset] === ZIP_LOCAL_0 && bytes[offset + 1] === ZIP_LOCAL_1 &&
      bytes[offset + 2] === ZIP_LOCAL_2 && bytes[offset + 3] === ZIP_LOCAL_3)) {
      break;
    }
    const method = readU16le(bytes, offset + 8);
    const compSize = readU32le(bytes, offset + 18);
    const nameLen = readU16le(bytes, offset + 26);
    const extraLen = readU16le(bytes, offset + 28);
    const nameStart = offset + 30;
    const dataStart = nameStart + nameLen + extraLen;
    if (dataStart + compSize > bytes.length) {
      break;
    }
    const name = readAscii(bytes, nameStart, nameLen);
    const ext = extFromZipName(name);
    if (method === 0) {
      const payload = sliceBuffer(bytes, dataStart, dataStart + compSize);
      if (isImageExt(ext) && imageBytes === undefined) {
        imageBytes = payload;
        imageExt = ext === 'jpeg' ? 'jpg' : ext;
      } else if (isVideoExt(ext) && videoBytes === undefined) {
        videoBytes = payload;
        videoExt = ext;
      }
    }
    offset = dataStart + compSize;
    if (imageBytes !== undefined && videoBytes !== undefined) {
      break;
    }
  }
  if (imageBytes === undefined || videoBytes === undefined) {
    return undefined;
  }
  if (imageBytes.byteLength < 32 || videoBytes.byteLength < 32) {
    return undefined;
  }
  const out = new SplitLivePhotoResult();
  out.imageBytes = imageBytes;
  out.videoBytes = videoBytes;
  out.imageExt = imageExt;
  out.videoExt = videoExt;
  return out;
}

function splitAppendedVideo(bytes: Uint8Array): SplitLivePhotoResult | undefined {
  const xmpEnd = Math.min(bytes.length, 512 * 1024);
  const xmpText = readAscii(bytes, 0, xmpEnd);
  let videoStart = -1;
  const microOffset = parseUintAfterKey(xmpText, 'MicroVideoOffset');
  if (microOffset > 0 && microOffset < bytes.length - 32) {
    const fromEnd = bytes.length - microOffset;
    if (fromEnd > 32) {
      videoStart = fromEnd;
    }
  }
  if (videoStart < 0) {
    const itemLength = parseUintAfterKey(xmpText, 'Item:Length');
    const videoLength = parseUintAfterKey(xmpText, 'VideoLength');
    const len = videoLength > 0 ? videoLength : itemLength;
    if (len > 32 && len < bytes.length - 32) {
      videoStart = bytes.length - len;
    }
  }
  if (videoStart < 0) {
    const mpvd = findMpvdPayloadStart(bytes);
    if (mpvd > 32 && mpvd < bytes.length - 32) {
      videoStart = mpvd;
    }
  }
  if (videoStart < 0) {
    videoStart = findLastFtypBoxStart(bytes);
  }
  if (videoStart < 64 || videoStart >= bytes.length - 32) {
    return undefined;
  }
  const imageBytes = sliceBuffer(bytes, 0, videoStart);
  const videoBytes = sliceBuffer(bytes, videoStart, bytes.length);
  if (imageBytes.byteLength < 64 || videoBytes.byteLength < 32) {
    return undefined;
  }
  const out = new SplitLivePhotoResult();
  out.imageBytes = imageBytes;
  out.videoBytes = videoBytes;
  out.imageExt = looksLikeJpeg(bytes) ? 'jpg' : 'heic';
  out.videoExt = 'mp4';
  return out;
}

/**
 * 是否为 ZIP 容器（含 .livp）。压缩条目需走 zlib，不可当拼接 MP4 扫。
 */
export function isZipLiveContainer(buffer: ArrayBuffer, fileExt: string): boolean {
  if (buffer.byteLength < 4) {
    return false;
  }
  if (fileExt.toLowerCase() === 'livp') {
    return true;
  }
  return looksLikeZip(new Uint8Array(buffer));
}

/**
 * 从单文件 buffer 拆出静帧 + 短视频。ZIP 仅处理 STORE；DEFLATE 返回 undefined。
 */
export function splitEmbeddedLivePhoto(buffer: ArrayBuffer, fileExt: string): SplitLivePhotoResult | undefined {
  if (buffer.byteLength < 128) {
    return undefined;
  }
  const bytes = new Uint8Array(buffer);
  if (isZipLiveContainer(buffer, fileExt)) {
    return splitZipStoredLivp(bytes);
  }
  return splitAppendedVideo(bytes);
}

function extOfName(name: string): string {
  const base = name.replace(/\\/g, '/');
  const slash = base.lastIndexOf('/');
  const file = slash >= 0 ? base.substring(slash + 1) : base;
  return extFromZipName(file);
}

async function removeDirTree(dirPath: string): Promise<void> {
  if (dirPath.length === 0) {
    return;
  }
  try {
    const names = await fileIo.listFile(dirPath);
    for (let i = 0; i < names.length; i++) {
      const child = `${dirPath}/${names[i]}`;
      try {
        const st = await fileIo.stat(child);
        if (st.isDirectory()) {
          await removeDirTree(child);
        } else {
          await fileIo.unlink(child);
        }
      } catch (_e) {
      }
    }
    await fileIo.rmdir(dirPath);
  } catch (_e) {
  }
}

export class UnzippedLivePaths {
  imagePath: string = '';
  videoPath: string = '';
}

async function collectUnzippedFiles(dirPath: string, into: string[], depth: number): Promise<void> {
  let names: string[] = [];
  try {
    names = await fileIo.listFile(dirPath);
  } catch (_e) {
    return;
  }
  for (let i = 0; i < names.length; i++) {
    const full = `${dirPath}/${names[i]}`;
    try {
      const st = await fileIo.stat(full);
      if (st.isDirectory()) {
        if (depth < 2) {
          await collectUnzippedFiles(full, into, depth + 1);
        }
      } else {
        into.push(full);
      }
    } catch (_e) {
    }
  }
}

async function findUnzippedLivePaths(outDir: string): Promise<UnzippedLivePaths | undefined> {
  const files: string[] = [];
  await collectUnzippedFiles(outDir, files, 0);
  let imagePath = '';
  let videoPath = '';
  for (let i = 0; i < files.length; i++) {
    const ext = extOfName(files[i]);
    if (imagePath.length === 0 && isImageExt(ext)) {
      imagePath = files[i];
    } else if (videoPath.length === 0 && isVideoExt(ext)) {
      videoPath = files[i];
    }
    if (imagePath.length > 0 && videoPath.length > 0) {
      break;
    }
  }
  if (imagePath.length === 0 || videoPath.length === 0) {
    return undefined;
  }
  const found = new UnzippedLivePaths();
  found.imagePath = imagePath;
  found.videoPath = videoPath;
  return found;
}

/**
 * 用系统 zlib 解压 .livp/.zip（含 DEFLATE），返回解压目录中的图/视频路径。
 * zipPath 必须以 .zip 结尾。
 */
export async function unzipLivpArchive(zipPath: string, outDir: string): Promise<UnzippedLivePaths | undefined> {
  if (zipPath.length === 0 || outDir.length === 0) {
    return undefined;
  }
  try {
    try {
      await fileIo.mkdir(outDir);
    } catch (_e) {
    }
    await zlib.decompressFile(zipPath, outDir);
    const found = await findUnzippedLivePaths(outDir);
    if (found === undefined) {
      await removeDirTree(outDir);
      return undefined;
    }
    return found;
  } catch (_e) {
    await removeDirTree(outDir);
    return undefined;
  }
}

export async function removeLiveUnzipDir(dirPath: string): Promise<void> {
  await removeDirTree(dirPath);
}

export function extFromFilePath(path: string): string {
  const norm = path.replace(/\\/g, '/');
  const slash = norm.lastIndexOf('/');
  const name = slash >= 0 ? norm.substring(slash + 1) : norm;
  const dot = name.lastIndexOf('.');
  if (dot <= 0 || dot >= name.length - 1) {
    return '';
  }
  return name.substring(dot + 1).toLowerCase();
}

export async function writeBufferToFile(path: string, buffer: ArrayBuffer): Promise<boolean> {
  if (buffer.byteLength <= 0 || path.length === 0) {
    return false;
  }
  try {
    const f = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(f.fd, buffer);
    } finally {
      await fileIo.close(f.fd);
    }
    return true;
  } catch (_e) {
    return false;
  }
}
