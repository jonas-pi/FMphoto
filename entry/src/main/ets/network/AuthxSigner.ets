/**
 * Authx 签名：与 fntv-electron/src/modules/fn_api/request.ts 算法一致
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FnJsonValue } from '../model/FnApiTypes';

const API_KEY = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
const API_SECRET = '16CCEB3D-AB42-077D-36A1-F355324E4237';
const MD5_TAG = 'AuthxMD5';

export function generateRandomDigits(start: number = 100000, end: number = 1000000): string {
  return Math.floor(Math.random() * (end - start) + start).toString();
}

function uint8ArrayToHex(data: Uint8Array): string {
  let s = '';
  for (let i = 0; i < data.length; i++) {
    const v = data[i] as number;
    s += (v < 16 ? '0' : '') + v.toString(16);
  }
  return s;
}

/** UTF-8 编码（与 JSON.stringify + Node crypto 的 utf8 一致，避免 TextEncoder API 版本差异） */
function utf8Encode(str: string): Uint8Array {
  const utf8: number[] = [];
  for (let i = 0; i < str.length; i++) {
    let c = str.charCodeAt(i);
    if (c < 0x80) {
      utf8.push(c);
    } else if (c < 0x800) {
      utf8.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c < 0xd800 || c >= 0xe000) {
      utf8.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    } else {
      i++;
      c = 0x10000 + (((c & 0x3ff) << 10) | (str.charCodeAt(i) & 0x3ff));
      utf8.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(utf8);
}

// ─── 纯 JS MD5 实现（RFC 1321，当 cryptoFramework 在模拟器不可用时回退） ───

function md5AddU32(a: number, b: number): number {
  return (a + b) | 0;
}

const MD5_S: number[] = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
];

const MD5_K: number[] = (() => {
  const t: number[] = [];
  for (let i = 0; i < 64; i++) {
    t.push((Math.floor(Math.abs(Math.sin(i + 1)) * 0x100000000)) | 0);
  }
  return t;
})();

function md5LeftRotate(x: number, c: number): number {
  return (x << c) | (x >>> (32 - c));
}

function md5Core(bytes: Uint8Array): string {
  const origLen = bytes.length;
  const bitLen = origLen * 8;

  let padLen = origLen + 1;
  while (padLen % 64 !== 56) {
    padLen++;
  }
  const buf = new Uint8Array(padLen + 8);
  buf.set(bytes);
  buf[origLen] = 0x80;
  // little-endian 64-bit length（仅低 32 位有效即可满足签名串长度）
  buf[padLen] = bitLen & 0xff;
  buf[padLen + 1] = (bitLen >>> 8) & 0xff;
  buf[padLen + 2] = (bitLen >>> 16) & 0xff;
  buf[padLen + 3] = (bitLen >>> 24) & 0xff;
  // 高 32 位保持 0（文本长度不会超过 2^32 字节）

  let a0 = 0x67452301;
  let b0 = 0xefcdab89 | 0;
  let c0 = 0x98badcfe | 0;
  let d0 = 0x10325476;

  const totalLen = padLen + 8;
  for (let offset = 0; offset < totalLen; offset += 64) {
    const M: number[] = [];
    for (let j = 0; j < 16; j++) {
      const base = offset + j * 4;
      M.push(
        (buf[base] as number) |
        ((buf[base + 1] as number) << 8) |
        ((buf[base + 2] as number) << 16) |
        ((buf[base + 3] as number) << 24)
      );
    }

    let A = a0;
    let B = b0;
    let C = c0;
    let D = d0;

    for (let i = 0; i < 64; i++) {
      let F: number;
      let g: number;
      if (i < 16) {
        F = (B & C) | ((~B) & D);
        g = i;
      } else if (i < 32) {
        F = (D & B) | ((~D) & C);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        F = B ^ C ^ D;
        g = (3 * i + 5) % 16;
      } else {
        F = C ^ (B | (~D));
        g = (7 * i) % 16;
      }
      F = md5AddU32(F, A);
      F = md5AddU32(F, MD5_K[i]);
      F = md5AddU32(F, M[g]);
      A = D;
      D = C;
      C = B;
      B = md5AddU32(B, md5LeftRotate(F, MD5_S[i]));
    }

    a0 = md5AddU32(a0, A);
    b0 = md5AddU32(b0, B);
    c0 = md5AddU32(c0, C);
    d0 = md5AddU32(d0, D);
  }

  return md5Le32Hex(a0) + md5Le32Hex(b0) + md5Le32Hex(c0) + md5Le32Hex(d0);
}

function md5Le32Hex(v: number): string {
  const b0v = v & 0xff;
  const b1v = (v >>> 8) & 0xff;
  const b2v = (v >>> 16) & 0xff;
  const b3v = (v >>> 24) & 0xff;
  return (b0v < 16 ? '0' : '') + b0v.toString(16) +
    (b1v < 16 ? '0' : '') + b1v.toString(16) +
    (b2v < 16 ? '0' : '') + b2v.toString(16) +
    (b3v < 16 ? '0' : '') + b3v.toString(16);
}

/** 纯 JS MD5：输入 UTF-8 字符串，输出 32 字符 hex */
function md5Js(text: string): string {
  return md5Core(utf8Encode(text));
}

/** 是否已检测过 cryptoFramework 可用 */
let cryptoChecked = false;
let cryptoAvailable = true;

/**
 * MD5 hex（UTF-8）：优先 cryptoFramework，首次失败后永久降级到纯 JS 实现。
 * 模拟器上 HCF Update 常返回 NULL 导致 "update failed"，回退后不再尝试。
 */
export async function md5HexUtf8(text: string): Promise<string> {
  if (cryptoChecked && !cryptoAvailable) {
    return md5Js(text);
  }
  try {
    const md = cryptoFramework.createMd('MD5');
    const input: Uint8Array = utf8Encode(text);
    await md.update({ data: input });
    const out = await md.digest();
    if (!cryptoChecked) {
      cryptoChecked = true;
      cryptoAvailable = true;
    }
    return uint8ArrayToHex(out.data);
  } catch (e) {
    if (!cryptoChecked || cryptoAvailable) {
      cryptoChecked = true;
      cryptoAvailable = false;
      hilog.warn(0xFF00, MD5_TAG, 'cryptoFramework MD5 failed, falling back to JS impl: %{public}s', String(e));
    }
    return md5Js(text);
  }
}

/**
 * @param path 仅路径，须与请求 URL 路径一致，如 / 或 /v/api/v1/user/info
 * @param bodyForSign 已与请求体一致的 JSON 对象（含 nonce）
 */
export async function genFnAuthx(path: string, bodyForSign: Record<string, FnJsonValue> | null): Promise<string> {
  const nonce = generateRandomDigits();
  const timestamp = Date.now();
  const dataJson = bodyForSign !== null ? JSON.stringify(bodyForSign) : '';
  const dataJsonMd5 = await md5HexUtf8(dataJson);
  const signStr =
    `${API_KEY}_${path}_${nonce}_${timestamp}_${dataJsonMd5}_${API_SECRET}`;
  const sign = await md5HexUtf8(signStr);
  return `nonce=${nonce}&timestamp=${timestamp}&sign=${sign}`;
}
