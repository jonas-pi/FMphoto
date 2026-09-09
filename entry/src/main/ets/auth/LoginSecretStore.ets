/**
 * 登录「记住密码」落盘：HUKS AES-256-GCM，密钥不出应用沙箱。
 * Preferences 只存 v1 包装密文，内存中的 LoginSavedUser.password 仍是明文。
 */
import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0xFF00;
const TAG: string = 'LoginSecret';
const KEY_ALIAS: string = 'fmphoto_login_secret_aes256';
const WRAP_PREFIX: string = 'v1.';
const GCM_NONCE_LEN: number = 12;
const GCM_TAG_LEN: number = 16;

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

function utf8Decode(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const b0 = bytes[i];
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i++;
    } else if ((b0 & 0xe0) === 0xc0 && i + 1 < bytes.length) {
      out += String.fromCharCode(((b0 & 0x1f) << 6) | (bytes[i + 1] & 0x3f));
      i += 2;
    } else if ((b0 & 0xf0) === 0xe0 && i + 2 < bytes.length) {
      out += String.fromCharCode(((b0 & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f));
      i += 3;
    } else if ((b0 & 0xf8) === 0xf0 && i + 3 < bytes.length) {
      const cp = ((b0 & 0x07) << 18) | ((bytes[i + 1] & 0x3f) << 12) |
        ((bytes[i + 2] & 0x3f) << 6) | (bytes[i + 3] & 0x3f);
      const adj = cp - 0x10000;
      out += String.fromCharCode(0xd800 + (adj >> 10), 0xdc00 + (adj & 0x3ff));
      i += 4;
    } else {
      out += '\uFFFD';
      i++;
    }
  }
  return out;
}

function bytesToB64(data: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(data);
}

function b64ToBytes(raw: string): Uint8Array {
  return new util.Base64Helper().decodeSync(raw);
}

function emptyHuksOptions(): huks.HuksOptions {
  const properties: huks.HuksParam[] = [];
  return { properties: properties };
}

function aesKeyProperties(): huks.HuksParam[] {
  const properties: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    },
    { tag: huks.HuksTag.HUKS_TAG_AUTH_STORAGE_LEVEL, value: huks.HuksAuthStorageLevel.HUKS_AUTH_STORAGE_LEVEL_CE }
  ];
  return properties;
}

function gcmProperties(purpose: huks.HuksKeyPurpose, nonce: Uint8Array): huks.HuksParam[] {
  const properties: huks.HuksParam[] = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
    { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce }
  ];
  return properties;
}

async function ensureAesKey(): Promise<void> {
  try {
    const exists = await huks.isKeyItemExist(KEY_ALIAS, emptyHuksOptions());
    if (exists) {
      return;
    }
  } catch (_e) {
  }
  const options: huks.HuksOptions = { properties: aesKeyProperties() };
  await huks.generateKeyItem(KEY_ALIAS, options);
}

async function abortQuiet(handle: number): Promise<void> {
  try {
    await huks.abortSession(handle, emptyHuksOptions());
  } catch (_e) {
  }
}

function findAeTag(result: huks.HuksReturnResult): Uint8Array | null {
  const props = result.properties;
  if (props === undefined) {
    return null;
  }
  for (let i = 0; i < props.length; i++) {
    if (props[i].tag === huks.HuksTag.HUKS_TAG_AE_TAG) {
      const v = props[i].value;
      if (typeof v !== 'number' && typeof v !== 'boolean' && v !== undefined) {
        const bytes = v as Uint8Array;
        if (bytes.byteLength > 0) {
          return bytes;
        }
      }
    }
  }
  return null;
}

function splitCipherAndTag(outData: Uint8Array): [Uint8Array, Uint8Array] {
  if (outData.length <= GCM_TAG_LEN) {
    return [new Uint8Array(0), outData];
  }
  const cut = outData.length - GCM_TAG_LEN;
  return [outData.slice(0, cut), outData.slice(cut)];
}

function formatHuksErr(e: Object): string {
  const be = e as BusinessError;
  if (be.code !== undefined) {
    return `code=${be.code}`;
  }
  return 'huks-error';
}

export function loginSecretLooksWrapped(raw: string): boolean {
  if (!raw.startsWith(WRAP_PREFIX)) {
    return false;
  }
  const rest = raw.substring(WRAP_PREFIX.length);
  const parts = rest.split('.');
  return parts.length === 3 && parts[0].length > 0 && parts[1].length > 0 && parts[2].length > 0;
}

export async function loginSecretSeal(plain: string): Promise<string> {
  if (plain.length === 0) {
    return '';
  }
  await ensureAesKey();
  let nonce: Uint8Array;
  try {
    nonce = cryptoFramework.createRandom().generateRandomSync(GCM_NONCE_LEN).data;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'nonce failed %{public}s', formatHuksErr(e));
    throw new Error('login-secret-nonce-failed');
  }
  const options: huks.HuksOptions = {
    properties: gcmProperties(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, nonce),
    inData: utf8Encode(plain)
  };
  let handle: number = 0;
  try {
    const init = await huks.initSession(KEY_ALIAS, options);
    handle = init.handle;
    const finished = await huks.finishSession(handle, options);
    const out = finished.outData;
    if (out === undefined || out.length === 0) {
      throw new Error('empty-cipher');
    }
    let cipher = out;
    let tag = findAeTag(finished);
    if (tag === null) {
      const split = splitCipherAndTag(out);
      cipher = split[0];
      tag = split[1];
    }
    if (cipher.length === 0 || tag.length === 0) {
      throw new Error('missing-tag');
    }
    return `${WRAP_PREFIX}${bytesToB64(nonce)}.${bytesToB64(cipher)}.${bytesToB64(tag)}`;
  } catch (e) {
    if (handle !== 0) {
      await abortQuiet(handle);
    }
    hilog.error(DOMAIN, TAG, 'seal failed %{public}s', formatHuksErr(e));
    throw new Error('login-secret-seal-failed');
  }
}

export async function loginSecretOpen(blob: string): Promise<string> {
  if (blob.length === 0) {
    return '';
  }
  if (!loginSecretLooksWrapped(blob)) {
    return blob;
  }
  const rest = blob.substring(WRAP_PREFIX.length);
  const parts = rest.split('.');
  if (parts.length !== 3) {
    return '';
  }
  let nonce: Uint8Array;
  let cipher: Uint8Array;
  let tag: Uint8Array;
  try {
    nonce = b64ToBytes(parts[0]);
    cipher = b64ToBytes(parts[1]);
    tag = b64ToBytes(parts[2]);
  } catch (_e) {
    return '';
  }
  if (nonce.length !== GCM_NONCE_LEN || cipher.length === 0 || tag.length === 0) {
    return '';
  }
  try {
    await ensureAesKey();
    const props = gcmProperties(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, nonce);
    props.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag });
    const options: huks.HuksOptions = { properties: props, inData: cipher };
    const init = await huks.initSession(KEY_ALIAS, options);
    const handle = init.handle;
    try {
      const finished = await huks.finishSession(handle, options);
      const out = finished.outData;
      if (out === undefined) {
        return '';
      }
      return utf8Decode(out);
    } catch (e) {
      await abortQuiet(handle);
      hilog.error(DOMAIN, TAG, 'open failed %{public}s', formatHuksErr(e));
      return '';
    }
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'open failed %{public}s', formatHuksErr(e));
    return '';
  }
}
