/**
 * 实况文件的同步读写。由 TaskPool 里的并发函数调用，不在界面线程执行。
 */
import { fileIo } from '@kit.CoreFileKit';
import { fnDiagError } from '../common/FnDiagLog';
import { splitEmbeddedLivePhoto } from './livephoto/MotionPhotoSplit';

const TAG: string = 'LiveSyncIo';
const HEAD_BYTES: number = 512 * 1024;
const TAIL_BYTES: number = 32 * 1024 * 1024;
const COPY_CHUNK: number = 256 * 1024;

function asciiOf(bytes: Uint8Array): string {
  let out = '';
  const end = Math.min(bytes.length, HEAD_BYTES);
  for (let i = 0; i < end; i++) {
    out += String.fromCharCode(bytes[i]);
  }
  return out;
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
  const n = Number(digits);
  return Number.isFinite(n) ? Math.floor(n) : 0;
}

function hasFtyp(bytes: Uint8Array): boolean {
  for (let i = 4; i + 8 <= bytes.length; i++) {
    if (bytes[i] !== 0x66 || bytes[i + 1] !== 0x74 || bytes[i + 2] !== 0x79 || bytes[i + 3] !== 0x70) {
      continue;
    }
    const size = ((bytes[i - 4] << 24) | (bytes[i - 3] << 16) | (bytes[i - 2] << 8) | bytes[i - 1]) >>> 0;
    if (size >= 16 && size <= 256) {
      return true;
    }
  }
  return false;
}

function readAt(fdNum: number, position: number, length: number): Uint8Array | null {
  if (length <= 0) {
    return null;
  }
  const buffer = new ArrayBuffer(length);
  try {
    fileIo.lseek(fdNum, position, fileIo.WhenceType.SEEK_SET);
    const n = fileIo.readSync(fdNum, buffer, { length: length });
    if (n <= 0) {
      return null;
    }
    return new Uint8Array(buffer, 0, n);
  } catch (e) {
    fnDiagError(TAG, 'live file io failed op=read', e);
    return null;
  }
}

function fileSizeOf(fdNum: number): number {
  try {
    const size = Number(fileIo.statSync(fdNum).size);
    if (!Number.isFinite(size) || size <= 0) {
      return 0;
    }
    return Math.floor(size);
  } catch (e) {
    fnDiagError(TAG, 'live file io failed op=stat', e);
    return 0;
  }
}

/** 文件尾（或 MicroVideoOffset 指向的位置）能看到短视频，才算飞牛可识别的实况原文件。 */
export function fileHasEmbeddedLiveVideo(pathOrUri: string): boolean {
  let fdNum = -1;
  try {
    const file = fileIo.openSync(pathOrUri, fileIo.OpenMode.READ_ONLY);
    fdNum = file.fd;
    const size = fileSizeOf(fdNum);
    if (size < 128) {
      return false;
    }
    const headLen = Math.min(size, HEAD_BYTES);
    const head = readAt(fdNum, 0, headLen);
    if (head === null || head.length < 2) {
      return false;
    }
    const startsAsVideo = head[4] === 0x66 && head[5] === 0x74 && head[6] === 0x79 && head[7] === 0x70;
    if (startsAsVideo) {
      return false;
    }
    const headText = asciiOf(head);
    const micro = parseUintAfterKey(headText, 'MicroVideoOffset');
    if (micro > 32 && micro < size) {
      const at = readAt(fdNum, size - micro, Math.min(64, micro));
      if (at !== null && hasFtyp(at)) {
        return true;
      }
    }
    const tailLen = Math.min(size, TAIL_BYTES);
    const tail = readAt(fdNum, size - tailLen, tailLen);
    return tail !== null && hasFtyp(tail);
  } catch (e) {
    fnDiagError(TAG, 'live file io failed op=probe', e);
    return false;
  } finally {
    if (fdNum >= 0) {
      try {
        fileIo.closeSync(fdNum);
      } catch (_e) {
      }
    }
  }
}

function xmpApp1(videoSize: number): ArrayBuffer {
  const xml =
    '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>' +
    '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">' +
    '<rdf:Description xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" ' +
    `GCamera:MicroVideo="1" GCamera:MicroVideoVersion="1" GCamera:MicroVideoOffset="${videoSize}" ` +
    `Item:Length="${videoSize}"/></rdf:RDF></x:xmpmeta>`;
  const ns = 'http://ns.adobe.com/xap/1.0/';
  const payloadLen = ns.length + 1 + xml.length;
  const segLen = payloadLen + 2;
  const out = new Uint8Array(2 + segLen);
  out[0] = 0xff;
  out[1] = 0xe1;
  out[2] = (segLen >> 8) & 0xff;
  out[3] = segLen & 0xff;
  for (let i = 0; i < ns.length; i++) {
    out[4 + i] = ns.charCodeAt(i) & 0xff;
  }
  out[4 + ns.length] = 0;
  for (let i = 0; i < xml.length; i++) {
    out[4 + ns.length + 1 + i] = xml.charCodeAt(i) & 0xff;
  }
  return out.buffer;
}

function copyRange(srcFd: number, start: number, length: number, outFd: number): boolean {
  let left = length;
  let pos = start;
  const chunk = new ArrayBuffer(COPY_CHUNK);
  while (left > 0) {
    const take = Math.min(COPY_CHUNK, left);
    let n = 0;
    try {
      fileIo.lseek(srcFd, pos, fileIo.WhenceType.SEEK_SET);
      n = fileIo.readSync(srcFd, chunk, { length: take });
    } catch (e) {
      fnDiagError(TAG, 'live file io failed op=copy-read', e);
      return false;
    }
    if (n <= 0) {
      return false;
    }
    const slice = n === chunk.byteLength ? chunk : chunk.slice(0, n);
    try {
      fileIo.writeSync(outFd, slice);
    } catch (e) {
      fnDiagError(TAG, 'live file io failed op=copy-write', e);
      return false;
    }
    pos += n;
    left -= n;
  }
  return true;
}

function copyRangeOfPath(path: string, outFd: number): boolean {
  let fdNum = -1;
  try {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    fdNum = file.fd;
    const size = fileSizeOf(fdNum);
    if (size <= 0) {
      return false;
    }
    return copyRange(fdNum, 0, size, outFd);
  } catch (e) {
    fnDiagError(TAG, 'live file io failed op=copy-open', e);
    return false;
  } finally {
    if (fdNum >= 0) {
      try {
        fileIo.closeSync(fdNum);
      } catch (_e) {
      }
    }
  }
}

function readWholeFileSync(path: string): ArrayBuffer | undefined {
  let fdNum = -1;
  try {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    fdNum = file.fd;
    const size = fileSizeOf(fdNum);
    if (size <= 0) {
      return undefined;
    }
    const buffer = new ArrayBuffer(size);
    fileIo.lseek(fdNum, 0, fileIo.WhenceType.SEEK_SET);
    const n = fileIo.readSync(fdNum, buffer);
    if (n <= 0) {
      return undefined;
    }
    if (n === size) {
      return buffer;
    }
    const trimmed = new ArrayBuffer(n);
    new Uint8Array(trimmed).set(new Uint8Array(buffer, 0, n));
    return trimmed;
  } catch (e) {
    fnDiagError(TAG, 'live file io failed op=read-whole', e);
    return undefined;
  } finally {
    if (fdNum >= 0) {
      try {
        fileIo.closeSync(fdNum);
      } catch (_e) {
      }
    }
  }
}

function writeWholeFileSync(path: string, data: ArrayBuffer): boolean {
  if (data.byteLength <= 0) {
    return false;
  }
  let fdNum = -1;
  try {
    const file = fileIo.openSync(
      path,
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    fdNum = file.fd;
    fileIo.writeSync(fdNum, data);
    return true;
  } catch (e) {
    fnDiagError(TAG, 'live file io failed op=write', e);
    return false;
  } finally {
    if (fdNum >= 0) {
      try {
        fileIo.closeSync(fdNum);
      } catch (_e) {
      }
    }
  }
}

function unlinkQuiet(path: string): void {
  if (path.length === 0) {
    return;
  }
  try {
    fileIo.unlinkSync(path);
  } catch (_e) {
  }
}

/** HQ 导出时封面可能是内嵌实况单文件，需拆出纯 JPEG 再与独立 MP4 拼接。 */
function resolveCoverForConcat(imagePath: string, videoPath: string, outPath: string): string {
  const videoSize = fileSizeOfPath(videoPath);
  if (videoSize <= 32 || !fileHasEmbeddedLiveVideo(imagePath)) {
    return imagePath;
  }
  const raw = readWholeFileSync(imagePath);
  if (raw === undefined) {
    return imagePath;
  }
  const lower = imagePath.toLowerCase();
  const ext = lower.endsWith('.heic') || lower.endsWith('.heif') ? 'heic' : 'jpg';
  const split = splitEmbeddedLivePhoto(raw, ext);
  if (split === undefined || split.imageBytes.byteLength < 64) {
    return imagePath;
  }
  const slash = Math.max(outPath.lastIndexOf('/'), outPath.lastIndexOf('\\'));
  const dir = slash > 0 ? outPath.substring(0, slash) : outPath;
  const purePath = `${dir}/.live_pure_cover.jpg`;
  if (!writeWholeFileSync(purePath, split.imageBytes)) {
    return imagePath;
  }
  return purePath;
}

export function copyFileSync(src: string, dst: string): boolean {
  let inFd = -1;
  let outFd = -1;
  try {
    const inf = fileIo.openSync(src, fileIo.OpenMode.READ_ONLY);
    inFd = inf.fd;
    const size = fileSizeOf(inFd);
    if (size <= 0) {
      return false;
    }
    const outf = fileIo.openSync(
      dst,
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    outFd = outf.fd;
    return copyRange(inFd, 0, size, outFd);
  } catch (e) {
    fnDiagError(TAG, 'live file io failed op=copy-file', e);
    return false;
  } finally {
    if (inFd >= 0) {
      try {
        fileIo.closeSync(inFd);
      } catch (_e) {
      }
    }
    if (outFd >= 0) {
      try {
        fileIo.closeSync(outFd);
      } catch (_e) {
      }
    }
  }
}

function fileSizeOfPath(path: string): number {
  let fdNum = -1;
  try {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    fdNum = file.fd;
    return fileSizeOf(fdNum);
  } catch (e) {
    fnDiagError(TAG, 'live file io failed op=stat-path', e);
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

/** 鸿蒙 HQ 导出：封面已是内嵌实况单文件，再追加独立 MP4，体积≈相册 SIZE。 */
function concatRawAppend(imagePath: string, videoPath: string, outPath: string): boolean {
  if (!copyFileSync(imagePath, outPath)) {
    return false;
  }
  let outFd = -1;
  try {
    const out = fileIo.openSync(outPath, fileIo.OpenMode.READ_WRITE);
    outFd = out.fd;
    const end = fileSizeOf(outFd);
    fileIo.lseek(outFd, end, fileIo.WhenceType.SEEK_SET);
    return copyRangeOfPath(videoPath, outFd);
  } catch (e) {
    fnDiagError(TAG, 'live file io failed op=concat-append', e);
    return false;
  } finally {
    if (outFd >= 0) {
      try {
        fileIo.closeSync(outFd);
      } catch (_e) {
      }
    }
  }
}

function assembledSizeOk(outPath: string, minBytes: number): boolean {
  const outSize = fileSizeOfPath(outPath);
  return outSize > 0 && outSize >= minBytes;
}

function concatFiles(imagePath: string, videoPath: string, outPath: string, videoSize: number): boolean {
  let imageFd = -1;
  let outFd = -1;
  try {
    const image = fileIo.openSync(imagePath, fileIo.OpenMode.READ_ONLY);
    imageFd = image.fd;
    const imageSize = fileSizeOf(imageFd);
    if (imageSize < 2) {
      return false;
    }
    const magic = readAt(imageFd, 0, 2);
    const jpeg = magic !== null && magic.length >= 2 && magic[0] === 0xff && magic[1] === 0xd8;
    const out = fileIo.openSync(
      outPath,
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    outFd = out.fd;
    if (jpeg) {
      const soi = new Uint8Array([0xff, 0xd8]);
      fileIo.writeSync(outFd, soi.buffer);
      fileIo.writeSync(outFd, xmpApp1(videoSize));
      // 原样拼接系统导出的 JPEG 主体（仅替换 SOI 并插入 XMP），不做二次编码。
      if (!copyRange(imageFd, 2, imageSize - 2, outFd)) {
        return false;
      }
    } else if (!copyRange(imageFd, 0, imageSize, outFd)) {
      return false;
    }
    return copyRangeOfPath(videoPath, outFd);
  } catch (e) {
    fnDiagError(TAG, 'live file io failed op=concat', e);
    return false;
  } finally {
    if (imageFd >= 0) {
      try {
        fileIo.closeSync(imageFd);
      } catch (_e) {
      }
    }
    if (outFd >= 0) {
      try {
        fileIo.closeSync(outFd);
      } catch (_e) {
      }
    }
  }
}

/**
 * 封面接上短视频。
 * 以输出体积是否盖住封面+短视频为准。尾部 ftyp 扫描会漏掉 64 位 box 的 MP4，不能拿来否决。
 */
export function assembleLiveFile(imagePath: string, videoPath: string, outPath: string): boolean {
  const imageSize = fileSizeOfPath(imagePath);
  const videoSize = fileSizeOfPath(videoPath);
  if (videoSize <= 32 || imageSize < 64) {
    return false;
  }
  const slack = 2048;
  const minCombined = imageSize + videoSize - slack;

  if (fileHasEmbeddedLiveVideo(imagePath)) {
    if (concatRawAppend(imagePath, videoPath, outPath) && assembledSizeOk(outPath, minCombined)) {
      return true;
    }
    unlinkQuiet(outPath);
  }

  const coverPath = resolveCoverForConcat(imagePath, videoPath, outPath);
  const tempCover = coverPath !== imagePath;
  const coverSize = fileSizeOfPath(coverPath);
  let ok = false;
  try {
    ok = concatFiles(coverPath, videoPath, outPath, videoSize);
  } finally {
    if (tempCover) {
      unlinkQuiet(coverPath);
    }
  }
  if (!ok) {
    return false;
  }
  const minXmp = coverSize + videoSize - slack;
  if (!assembledSizeOk(outPath, minXmp)) {
    unlinkQuiet(outPath);
    return false;
  }
  return true;
}

/** 合成后文件大小（与 concat 规则一致，供账本/去重记录）。 */
export function assembledLiveFileSize(imagePath: string, videoPath: string): number {
  const videoSize = fileSizeOfPath(videoPath);
  if (videoSize <= 32) {
    return 0;
  }
  const probeOut = `${imagePath}.size_probe`;
  if (!assembleLiveFile(imagePath, videoPath, probeOut)) {
    return 0;
  }
  const size = fileSizeOfPath(probeOut);
  unlinkQuiet(probeOut);
  return size;
}
