/**
 * 飞牛相册内容指纹。对即将上传的那一份字节计算：
 * - 小于 64 KiB：整文件 SHA-256，小写十六进制。
 * - 大于等于 64 KiB：文件头 64 KiB 与文件尾 64 KiB 按小端 uint64 相加，再加文件大小，
 *   对 2^64 取模。64 KiB 到 128 KiB 的重叠部分按两段各加一次。
 *   结果是不补零的小写十六进制。
 */
import { fileIo } from '@kit.CoreFileKit';
import { taskpool } from '@kit.ArkTS';
import { sha256Bytes } from '../network/AuthxSigner';

/**
 * 在 TaskPool 线程里读文件头尾。同步 IO 若留在界面线程，滑动和点击会卡住。
 * 函数体必须自包含：TaskPool 不允许调用同文件里的普通函数。
 * 读失败返回空串。调用方不得把空串当成「服务器没有这份内容」。
 */
@Concurrent
function contentFingerprintConcurrent(pathOrUri: string): string {
  const blockBytes: number = 64 * 1024;
  const mask: bigint = (1n << 64n) - 1n;
  let fdNum: number = -1;
  try {
    const file = fileIo.openSync(pathOrUri, fileIo.OpenMode.READ_ONLY);
    fdNum = file.fd;
    let size: number = 0;
    try {
      const raw = Number(fileIo.statSync(fdNum).size);
      if (Number.isFinite(raw) && raw > 0) {
        size = Math.floor(raw);
      }
    } catch (_e) {
      size = 0;
    }
    if (size <= 0) {
      return '';
    }
    if (size < blockBytes) {
      const buffer = new ArrayBuffer(size);
      fileIo.lseek(fdNum, 0, fileIo.WhenceType.SEEK_SET);
      const readLen = fileIo.readSync(fdNum, buffer, { length: size });
      if (readLen !== size) {
        return '';
      }
      const digest = sha256Bytes(new Uint8Array(buffer));
      let hex = '';
      for (let i = 0; i < digest.length; i++) {
        const v = digest[i] as number;
        hex += (v < 16 ? '0' : '') + v.toString(16);
      }
      return hex;
    }
    const headBuf = new ArrayBuffer(blockBytes);
    fileIo.lseek(fdNum, 0, fileIo.WhenceType.SEEK_SET);
    const headLen = fileIo.readSync(fdNum, headBuf, { length: blockBytes });
    if (headLen !== blockBytes) {
      return '';
    }
    const tailBuf = new ArrayBuffer(blockBytes);
    fileIo.lseek(fdNum, size - blockBytes, fileIo.WhenceType.SEEK_SET);
    const tailLen = fileIo.readSync(fdNum, tailBuf, { length: blockBytes });
    if (tailLen !== blockBytes) {
      return '';
    }
    const head = new Uint8Array(headBuf);
    const tail = new Uint8Array(tailBuf);
    let sum: bigint = 0n;
    for (let offset = 0; offset + 8 <= head.length; offset += 8) {
      let value: bigint = 0n;
      for (let i = 0; i < 8; i++) {
        value |= BigInt(head[offset + i] as number) << BigInt(i * 8);
      }
      sum = (sum + value) & mask;
    }
    for (let offset = 0; offset + 8 <= tail.length; offset += 8) {
      let value: bigint = 0n;
      for (let i = 0; i < 8; i++) {
        value |= BigInt(tail[offset + i] as number) << BigInt(i * 8);
      }
      sum = (sum + value) & mask;
    }
    sum = (sum + BigInt(size)) & mask;
    return sum.toString(16);
  } catch (_e) {
    return '';
  } finally {
    if (fdNum >= 0) {
      try {
        fileIo.closeSync(fdNum);
      } catch (_e) {
      }
    }
  }
}

/** 读失败返回空串。调用方不得把空串当成「服务器没有这份内容」。 */
export async function contentFingerprintOf(pathOrUri: string): Promise<string> {
  try {
    const hash = await taskpool.execute(contentFingerprintConcurrent, pathOrUri) as string;
    return typeof hash === 'string' ? hash : '';
  } catch (_e) {
    return '';
  }
}
