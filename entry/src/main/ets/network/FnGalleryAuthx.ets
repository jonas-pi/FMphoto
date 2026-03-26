/**
 * 图库 /p/api/v1 下 GET 的 authx：与 PyCharmMiscProject/fnos_gallery_mobile.py 中 build_p_api_authx 一致。
 * OpenAPI `/v/api/v1` 使用 AuthxSigner.genFnAuthx（另一套 UUID）；相册须用本模块，否则 invalid sign。
 */
import { md5HexUtf8 } from './AuthxSigner';
import { FnJsonValue } from '../model/FnApiTypes';

/** 与前端 bundle galleryApi.baseQuery 一致 */
const GALLERY_AUTHX_KEY = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
/** 图库专用 UUID（非 OpenAPI 的 16CCEB3D-…） */
const GALLERY_AUTHX_UUID = 'EAECCF25-80A6-4666-A7C2-A76904A74AB6';

/** 供 GET 签名：path 无 query，如 /p/api/v1/gallery/getList */
export interface FnGalleryGetSignSpec {
  signPathOnly: string;
  queryParams: Record<string, string | number | boolean>;
}

/** 将非法「%」转义为 %25，再 decodeURIComponent（失败则退回原串） */
function percentDecodeForInnerMd5(paramBlock: string): string {
  const fixed = paramBlock.replace(/%(?![0-9A-Fa-f]{2})/gi, '%25');
  try {
    return decodeURIComponent(fixed);
  } catch (_e) {
    return paramBlock;
  }
}

/** 与 Python _i_ge：键排序、urlencode、空格为 %20 */
export function buildGallerySortedQuery(params: Record<string, string | number | boolean>): string {
  const keys = Object.keys(params).filter((k: string) => params[k] !== undefined).sort();
  const parts: string[] = [];
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    const v = params[k] as string | number | boolean;
    const vs = typeof v === 'boolean' ? (v ? 'true' : 'false') : String(v);
    parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(vs)}`);
  }
  return parts.join('&');
}

/** 与 Python _a_ge(inner)：对 query 串 decode 后 UTF-8 MD5 hex */
export async function galleryInnerMd5FromQuery(paramBlock: string): Promise<string> {
  const decoded = percentDecodeForInnerMd5(paramBlock);
  return md5HexUtf8(decoded);
}

/** 与 Py `nonce = str(int(round(random.random() * 900_000 + 100_000)))` + 过短 zfill(6) */
function galleryNonceLikePython(): string {
  const n = Math.round(Math.random() * 900000 + 100000);
  let s = `${n}`;
  if (s.length < 6) {
    s = s.padStart(6, '0');
  }
  return s;
}

/**
 * 生成图库 GET 的 Authx 头值（nonce/timestamp/sign）。
 * signPathOnly 须与前端 prepareHeaders 一致，无 query。
 */
export async function genFnGalleryAuthxGet(
  signPathOnly: string,
  params: Record<string, string | number | boolean>
): Promise<string> {
  const pathOnly = signPathOnly.split('?')[0];
  const raw = buildGallerySortedQuery(params);
  const inner = await galleryInnerMd5FromQuery(raw);
  const nonce = galleryNonceLikePython();
  const timestamp = Date.now();
  const chain = `${GALLERY_AUTHX_KEY}_${pathOnly}_${nonce}_${timestamp}_${inner}_${GALLERY_AUTHX_UUID}`;
  const sign = await md5HexUtf8(chain);
  return `nonce=${nonce}&timestamp=${timestamp}&sign=${sign}`;
}

/**
 * 生成图库 POST 的 Authx 头值。
 * 与 GET 的差异：inner 取请求 body 的 JSON 字符串 MD5（而非 query）。
 */
export async function genFnGalleryAuthxPost(
  signPathOnly: string,
  bodyForSign: Record<string, FnJsonValue>
): Promise<string> {
  const pathOnly = signPathOnly.split('?')[0];
  const dataJson = JSON.stringify(bodyForSign);
  const inner = await md5HexUtf8(dataJson);
  const nonce = galleryNonceLikePython();
  const timestamp = Date.now();
  const chain = `${GALLERY_AUTHX_KEY}_${pathOnly}_${nonce}_${timestamp}_${inner}_${GALLERY_AUTHX_UUID}`;
  const sign = await md5HexUtf8(chain);
  return `nonce=${nonce}&timestamp=${timestamp}&sign=${sign}`;
}

/**
 * 生成图库 POST 的 Authx 头值（原始 JSON 字符串版本）。
 * 用于 body 包含嵌套对象/数组时，直接对已序列化的 JSON 字符串签名，
 * 确保签名内容与实际发送 body 完全一致。
 */
export async function genFnGalleryAuthxPostRaw(
  signPathOnly: string,
  bodyJson: string
): Promise<string> {
  const pathOnly = signPathOnly.split('?')[0];
  const inner = await md5HexUtf8(bodyJson);
  const nonce = galleryNonceLikePython();
  const timestamp = Date.now();
  const chain = `${GALLERY_AUTHX_KEY}_${pathOnly}_${nonce}_${timestamp}_${inner}_${GALLERY_AUTHX_UUID}`;
  const sign = await md5HexUtf8(chain);
  return `nonce=${nonce}&timestamp=${timestamp}&sign=${sign}`;
}
