/**
 * fnOS WebSocket 鉴权加密：
 * - 登录：随机 32 字节 AES-256 密钥 + 16 字节 IV；AES-CBC PKCS7 加密紧凑 JSON；RSA2048 PKCS1 加密 AES 密钥字节
 * - secret：AES-CBC 解密后为 HMAC 密钥原始字节（PKCS7 已由框架去除）
 * - 后续帧：RFC2104 HMAC-SHA256（createMd SHA256 组合，避免 Mac convertKey 失败）+ base64 + json 直连无 '='
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

/** UTF-8 编码 */
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

function uint8ArrayToBase64(data: Uint8Array): string {
  const helper = new util.Base64Helper();
  return helper.encodeToStringSync(data);
}

/** 持久化 HMAC 密钥字节（与 Python 中 hmac_key 一致，仅存 Base64 便于 preferences） */
export function fnWsHmacKeyBytesToB64(key: Uint8Array): string {
  return uint8ArrayToBase64(key);
}

function base64ToUint8(str: string): Uint8Array {
  const helper = new util.Base64Helper();
  return helper.decodeSync(str);
}

let reqSeq = 1;

/**
 * reqid：8 位时间戳(hex) + backId(16) + 序号(hex 4 位)
 */
export function fnWsMakeReqId(backId: string): string {
  const t = Date.now();
  let hx = t.toString(16);
  while (hx.length < 8) {
    hx = '0' + hx;
  }
  const e = reqSeq.toString(16);
  reqSeq++;
  let ez = e;
  while (ez.length < 4) {
    ez = '0' + ez;
  }
  const bid = backId.length >= 16 ? backId.substring(0, 16) : backId.padStart(16, '0');
  return `${hx}${bid}${ez}`;
}

export function fnWsResetReqIdCounter(): void {
  reqSeq = 1;
}

/** 32 字节随机 AES-256 密钥 */
export async function fnWsRandomAesKey32(): Promise<Uint8Array> {
  const rand = cryptoFramework.createRandom();
  const blob = await rand.generateRandom(32);
  return blob.data;
}

async function importRsaPubKeyFromPem(pem: string): Promise<cryptoFramework.PubKey> {
  const generator = cryptoFramework.createAsyKeyGenerator('RSA2048');
  const keyPair = await generator.convertPemKey(pem, null);
  return keyPair.pubKey;
}

/** RSA PKCS1_v1_5 加密 32 字节 AES 密钥，输出 Base64 */
export async function fnWsRsaPkcs1EncryptKeyBytes(pemPub: string, key32: Uint8Array): Promise<string> {
  const pubKey = await importRsaPubKeyFromPem(pemPub);
  const cipher = cryptoFramework.createCipher('RSA2048|PKCS1');
  await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, pubKey, null);
  const out = await cipher.doFinal({ data: key32 });
  return uint8ArrayToBase64(out.data);
}

/** AES-256-CBC + PKCS7，密钥为 32 字节 */
export async function fnWsAesCbcEncryptB64(plainUtf8: string, key32: Uint8Array, iv: Uint8Array): Promise<string> {
  const symGen = cryptoFramework.createSymKeyGenerator('AES256');
  const keyBlob: cryptoFramework.DataBlob = { data: key32 };
  const symKey = await symGen.convertKey(keyBlob);
  const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
  const ivSpec: cryptoFramework.IvParamsSpec = {
    algName: 'IvParamsSpec',
    iv: { data: iv }
  };
  await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivSpec);
  const out = await cipher.doFinal({ data: utf8Encode(plainUtf8) });
  return uint8ArrayToBase64(out.data);
}

/**
 * 解密服务端 secret（Base64 密文），得到 HMAC 密钥原始字节
 * 对齐 Python：AES.new(...).decrypt + unpad，此处 PKCS7 由 AES256|CBC|PKCS7 解密端去除
 */
export async function fnWsAesCbcDecryptSecretToHmacKey(
  cipherB64: string,
  key32: Uint8Array,
  iv: Uint8Array
): Promise<Uint8Array> {
  const symGen = cryptoFramework.createSymKeyGenerator('AES256');
  const keyBlob: cryptoFramework.DataBlob = { data: key32 };
  const symKey = await symGen.convertKey(keyBlob);
  const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS7');
  const ivSpec: cryptoFramework.IvParamsSpec = {
    algName: 'IvParamsSpec',
    iv: { data: iv }
  };
  await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, ivSpec);
  const raw = base64ToUint8(cipherB64);
  const out = await cipher.doFinal({ data: raw });
  return out.data;
}

export async function fnWsRandomIv16(): Promise<Uint8Array> {
  const rand = cryptoFramework.createRandom();
  const blob = await rand.generateRandom(16);
  return blob.data;
}

export interface FnWsEncryptedFrame {
  req: string;
  iv: string;
  rsa: string;
  aes: string;
}

/**
 * 构造 encrypted 帧（紧凑 JSON 由调用方序列化字段顺序）
 */
export async function fnWsBuildEncryptedLogin(
  loginJsonCompact: string,
  pemPub: string,
  aesKey32: Uint8Array,
  iv: Uint8Array
): Promise<FnWsEncryptedFrame> {
  const rsa = await fnWsRsaPkcs1EncryptKeyBytes(pemPub, aesKey32);
  const aes = await fnWsAesCbcEncryptB64(loginJsonCompact, aesKey32, iv);
  return {
    req: 'encrypted',
    iv: uint8ArrayToBase64(iv),
    rsa: rsa,
    aes: aes
  };
}

/** encrypted 帧单行 JSON，键序：req, iv, rsa, aes */
export function fnWsStringifyEncryptedFrame(enc: FnWsEncryptedFrame): string {
  return `{"req":"encrypted","iv":${JSON.stringify(enc.iv)},"rsa":${JSON.stringify(enc.rsa)},"aes":${JSON.stringify(enc.aes)}}`;
}

async function sha256Digest(data: Uint8Array): Promise<Uint8Array> {
  const md = cryptoFramework.createMd('SHA256');
  await md.update({ data: data });
  const out = await md.digest();
  return out.data;
}

function concatUint8(a: Uint8Array, b: Uint8Array): Uint8Array {
  const r = new Uint8Array(a.length + b.length);
  r.set(a, 0);
  r.set(b, a.length);
  return r;
}

/**
 * RFC 2104 HMAC-SHA256，与 Python hmac / 前端一致。
 * 不用 createSymKeyGenerator('HMAC|SHA256').convertKey：解密得到的密钥长度不固定时部分设备报 convert sym key failed。
 */
export async function fnWsHmacSha256Digest(hmacKey: Uint8Array, message: Uint8Array): Promise<Uint8Array> {
  const block = 64;
  let k = hmacKey;
  if (k.length > block) {
    k = await sha256Digest(k);
  }
  const kb = new Uint8Array(block);
  kb.set(k, 0);
  const ipad = new Uint8Array(block);
  const opad = new Uint8Array(block);
  for (let i = 0; i < block; i++) {
    const x = kb[i] as number;
    ipad[i] = x ^ 0x36;
    opad[i] = x ^ 0x5c;
  }
  const inner = await sha256Digest(concatUint8(ipad, message));
  return sha256Digest(concatUint8(opad, inner));
}

/**
 * 与前端 gg / Python：base64(HMAC-SHA256(hmacKey, utf8(json))) + json（无 '='）
 */
export async function fnWsHmacSha256SignConcatJson(hmacKey: Uint8Array, jsonCompact: string): Promise<string> {
  const macOut = await fnWsHmacSha256Digest(hmacKey, utf8Encode(jsonCompact));
  return `${uint8ArrayToBase64(macOut)}${jsonCompact}`;
}

/** 冷启动：preferences 中存的是 fnWsHmacKeyBytesToB64 的结果 */
export async function fnWsHmacSha256SignConcatJsonFromStoredB64(
  hmacKeyMaterialB64: string,
  jsonCompact: string
): Promise<string> {
  return fnWsHmacSha256SignConcatJson(base64ToUint8(hmacKeyMaterialB64), jsonCompact);
}
