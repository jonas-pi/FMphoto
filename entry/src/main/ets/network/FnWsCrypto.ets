import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { sha256DigestSafe } from './AuthxSigner';

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

export function fnWsHmacKeyBytesToB64(key: Uint8Array): string {
  return uint8ArrayToBase64(key);
}

function base64ToUint8(str: string): Uint8Array {
  const helper = new util.Base64Helper();
  return helper.decodeSync(str);
}

let reqSeq = 1;

function rethrowCryptoError(scope: string, e: Object): never {
  throw new Error(`${scope} failed: ${String(e)}`);
}

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

export async function fnWsRandomAesKey32(): Promise<Uint8Array> {
  try {
    const rand = cryptoFramework.createRandom();
    const blob = await rand.generateRandom(32);
    return blob.data;
  } catch (e) {
    return rethrowCryptoError('random aes key', e);
  }
}

async function importRsaPubKeyFromPem(pem: string): Promise<cryptoFramework.PubKey> {
  try {
    const generator = cryptoFramework.createAsyKeyGenerator('RSA2048');
    const keyPair = await generator.convertPemKey(pem, null);
    return keyPair.pubKey;
  } catch (e) {
    return rethrowCryptoError('import rsa public key', e);
  }
}

export async function fnWsRsaPkcs1EncryptKeyBytes(pemPub: string, key32: Uint8Array): Promise<string> {
  try {
    const pubKey = await importRsaPubKeyFromPem(pemPub);
    const cipher = cryptoFramework.createCipher('RSA2048|PKCS1');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, pubKey, null);
    const out = await cipher.doFinal({ data: key32 });
    return uint8ArrayToBase64(out.data);
  } catch (e) {
    return rethrowCryptoError('rsa encrypt aes key', e);
  }
}

export async function fnWsAesCbcEncryptB64(plainUtf8: string, key32: Uint8Array, iv: Uint8Array): Promise<string> {
  try {
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
  } catch (e) {
    return rethrowCryptoError('aes encrypt login payload', e);
  }
}

export async function fnWsAesCbcDecryptSecretToHmacKey(
  cipherB64: string,
  key32: Uint8Array,
  iv: Uint8Array
): Promise<Uint8Array> {
  try {
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
  } catch (e) {
    return rethrowCryptoError('aes decrypt secret', e);
  }
}

export async function fnWsRandomIv16(): Promise<Uint8Array> {
  try {
    const rand = cryptoFramework.createRandom();
    const blob = await rand.generateRandom(16);
    return blob.data;
  } catch (e) {
    return rethrowCryptoError('random iv', e);
  }
}

export interface FnWsEncryptedFrame {
  req: string;
  iv: string;
  rsa: string;
  aes: string;
}

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

export function fnWsStringifyEncryptedFrame(enc: FnWsEncryptedFrame): string {
  return `{"req":"encrypted","iv":${JSON.stringify(enc.iv)},"rsa":${JSON.stringify(enc.rsa)},"aes":${JSON.stringify(enc.aes)}}`;
}

async function sha256Digest(data: Uint8Array): Promise<Uint8Array> {
  return sha256DigestSafe(data);
}

function concatUint8(a: Uint8Array, b: Uint8Array): Uint8Array {
  const r = new Uint8Array(a.length + b.length);
  r.set(a, 0);
  r.set(b, a.length);
  return r;
}

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

export async function fnWsHmacSha256SignConcatJson(hmacKey: Uint8Array, jsonCompact: string): Promise<string> {
  const macOut = await fnWsHmacSha256Digest(hmacKey, utf8Encode(jsonCompact));
  return `${uint8ArrayToBase64(macOut)}${jsonCompact}`;
}

export async function fnWsHmacSha256SignConcatJsonFromStoredB64(
  hmacKeyMaterialB64: string,
  jsonCompact: string
): Promise<string> {
  return fnWsHmacSha256SignConcatJson(base64ToUint8(hmacKeyMaterialB64), jsonCompact);
}
