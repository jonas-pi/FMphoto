/**
 * 配置二维码：生成码图、解析扫码文本。
 */
import { image } from '@kit.ImageKit';
import { scanCore, generateBarcode } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { utf8EncodeLocal } from '../network/fnHttpClient/FnHttpClientCommon';
import {
  APP_SETTINGS_QR_STRING_MAX,
  AppSettingsEnvelope,
  encodeQrPayload,
  qrPayloadText
} from './AppSettingsEnvelope';

export const SCAN_USER_CANCEL_CODE: number = 1000500002;

export interface CreateQrImageResult {
  ok: boolean;
  message: string;
  pixelMap?: image.PixelMap;
}

function utf8ToArrayBuffer(text: string): ArrayBuffer {
  const u8 = utf8EncodeLocal(text);
  const buf: ArrayBuffer = new ArrayBuffer(u8.length);
  const view: Uint8Array = new Uint8Array(buf);
  view.set(u8);
  return buf;
}

export function canGenerateSettingsQr(): boolean {
  return canIUse('SystemCapability.Multimedia.Scan.GenerateBarcode');
}

export function canScanSettingsQr(): boolean {
  return canIUse('SystemCapability.Multimedia.Scan.ScanBarcode');
}

export async function createSettingsQrImage(envelope: AppSettingsEnvelope): Promise<CreateQrImageResult> {
  if (!canGenerateSettingsQr()) {
    return { ok: false, message: '当前设备不支持生成二维码' };
  }
  const encoded = encodeQrPayload(envelope);
  if (!encoded.ok) {
    return { ok: false, message: encoded.message };
  }
  const content = qrPayloadText(envelope);
  if (content.length === 0) {
    return { ok: false, message: '分类数据过多，二维码放不下，请改用 WebDAV' };
  }
  const options: generateBarcode.CreateOptions = {
    scanType: scanCore.ScanType.QR_CODE,
    width: 400,
    height: 400,
    margin: 1,
    level: content.length <= APP_SETTINGS_QR_STRING_MAX
      ? generateBarcode.ErrorCorrectionLevel.LEVEL_M
      : generateBarcode.ErrorCorrectionLevel.LEVEL_L,
    backgroundColor: 0xFFFFFF,
    pixelMapColor: 0x000000
  };
  try {
    let pixelMap: image.PixelMap;
    if (content.length <= APP_SETTINGS_QR_STRING_MAX) {
      pixelMap = await generateBarcode.createBarcode(content, options);
    } else {
      pixelMap = await generateBarcode.createBarcode(utf8ToArrayBuffer(content), options);
    }
    return { ok: true, message: '', pixelMap: pixelMap };
  } catch (e) {
    const err = e as BusinessError;
    return { ok: false, message: `生成二维码失败：${err.message}` };
  }
}

export function isScanUserCancel(err: BusinessError): boolean {
  return err.code === SCAN_USER_CANCEL_CODE;
}
