/**
 * Authx 签名：与 fntv-electron/src/modules/fn_api/request.ts 算法一致
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FnJsonValue } from '../model/FnApiTypes';

const MD5_TAG = 'AuthxMD5';
const SHA256_TAG = 'AuthxSHA256';
/**
 * OpenAPI Authx 凭据（运行时注入）：
 * - 不再在源码硬编码，避免凭据泄露风险。
 * - 由登录流程在拿到服务端会话后调用 setOpenApiAuthxCredentials 注入。
 */
let runtimeApiKey: string = '';
let runtimeApiSecret: string = '';

/**
 * 设置 OpenAPI Authx 签名凭据。
 * 说明：调用方应在登录成功后立即注入；空值将导致后续签名失败并提示重新登录。
 */
export function setOpenApiAuthxCredentials(apiKey: string, apiSecret: string): void {
  runtimeApiKey = apiKey.trim();
  runtimeApiSecret = apiSecret.trim();
}

/** 清理 OpenAPI Authx 签名凭据（退出登录或会话失效时调用）。 */
export function clearOpenApiAuthxCredentials(): void {
  runtimeApiKey = '';
  runtimeApiSecret = '';
}

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

// ─── 纯 JS SHA-256（当 HCF createMd('SHA256').update 抛 Error: update failed 时回退，与上传 trim-sign / WS HMAC 一致） ───

function rotr32(n: number, x: number): number {
  return ((x >>> n) | (x << (32 - n))) >>> 0;
}

const SHA256_K: Uint32Array = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]);

/** RFC 6234 风格 SHA-256，输入任意字节长度（图库签名/HMAC 消息远小于 2^32 位，长度编码用 64 位高位补 0） */
function sha256Js(data: Uint8Array): Uint8Array {
  const len = data.length;
  const totalBits = len * 8;
  const bitHi = Math.floor(totalBits / 4294967296);
  const bitLo = (totalBits - bitHi * 4294967296) >>> 0;
  const padLen = ((len + 9 + 63) >> 6) << 6;
  const buf = new Uint8Array(padLen);
  buf.set(data);
  buf[len] = 0x80;
  const dv = new DataView(buf.buffer);
  dv.setUint32(padLen - 8, bitHi, false);
  dv.setUint32(padLen - 4, bitLo, false);

  const H = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  ]);
  const w = new Uint32Array(64);

  for (let off = 0; off < padLen; off += 64) {
    for (let i = 0; i < 16; i++) {
      w[i] = dv.getUint32(off + i * 4, false);
    }
    for (let t = 16; t < 64; t++) {
      const s0 = rotr32(7, w[t - 15]) ^ rotr32(18, w[t - 15]) ^ (w[t - 15] >>> 3);
      const s1 = rotr32(17, w[t - 2]) ^ rotr32(19, w[t - 2]) ^ (w[t - 2] >>> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) >>> 0;
    }
    let a = H[0];
    let b = H[1];
    let c = H[2];
    let d = H[3];
    let e = H[4];
    let f = H[5];
    let g = H[6];
    let h = H[7];
    for (let t = 0; t < 64; t++) {
      const S1 = rotr32(6, e) ^ rotr32(11, e) ^ rotr32(25, e);
      const ch = (e & f) ^ (~e & g);
      const t1 = (h + S1 + ch + SHA256_K[t] + w[t]) >>> 0;
      const S0 = rotr32(2, a) ^ rotr32(13, a) ^ rotr32(22, a);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + maj) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    H[0] = (H[0] + a) >>> 0;
    H[1] = (H[1] + b) >>> 0;
    H[2] = (H[2] + c) >>> 0;
    H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0;
    H[5] = (H[5] + f) >>> 0;
    H[6] = (H[6] + g) >>> 0;
    H[7] = (H[7] + h) >>> 0;
  }

  const out = new Uint8Array(32);
  const odv = new DataView(out.buffer);
  for (let i = 0; i < 8; i++) {
    odv.setUint32(i * 4, H[i], false);
  }
  return out;
}

/** SHA256 与 MD5 独立探测：部分鸿蒙设备上 MD5 正常而 SHA256.update 抛「update failed」 */
let sha256CryptoChecked = false;
let sha256CryptoAvailable = true;

/**
 * SHA-256 摘要（字节进、32 字节出）：优先 cryptoFramework，失败则纯 JS（与上传 trim-sign、WS HMAC 一致）。
 */
export async function sha256DigestSafe(data: Uint8Array): Promise<Uint8Array> {
  if (sha256CryptoChecked && !sha256CryptoAvailable) {
    return sha256Js(data);
  }
  try {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: data });
    const out = await md.digest();
    if (!sha256CryptoChecked) {
      sha256CryptoChecked = true;
      sha256CryptoAvailable = true;
    }
    return out.data;
  } catch (e) {
    if (!sha256CryptoChecked || sha256CryptoAvailable) {
      sha256CryptoChecked = true;
      sha256CryptoAvailable = false;
      hilog.warn(0xFF00, SHA256_TAG, 'cryptoFramework SHA256 failed, JS fallback: %{public}s', String(e));
    }
    return sha256Js(data);
  }
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
  if (runtimeApiKey.length === 0 || runtimeApiSecret.length === 0) {
    throw new Error('Authx 凭据缺失，请先登录以获取签名凭据');
  }
  const nonce = generateRandomDigits();
  const timestamp = Date.now();
  const dataJson = bodyForSign !== null ? JSON.stringify(bodyForSign) : '';
  const dataJsonMd5 = await md5HexUtf8(dataJson);
  const signStr =
    `${runtimeApiKey}_${path}_${nonce}_${timestamp}_${dataJsonMd5}_${runtimeApiSecret}`;
  const sign = await md5HexUtf8(signStr);
  return `nonce=${nonce}&timestamp=${timestamp}&sign=${sign}`;
}
