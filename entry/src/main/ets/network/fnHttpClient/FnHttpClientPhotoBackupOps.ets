/**
 * 官方备份客户端相册接口：folder/add、backup/path、backup/device/* 等。
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagError } from '../../common/FnDiagLog';
import { CertPolicy } from '../CertPolicy';
import { genFnGalleryAuthxPostRaw } from '../FnGalleryAuthx';
import { FN_PHOTO_API_PREFIX, FN_PHOTO_API_V2_PREFIX } from '../FnPhotoRoutes';
import { mergeGalleryWebCookieIntoNativeHeader } from '../FnWebCookies';
import { fnWebViewBaseUrl } from '../ServerUrl';
import { buildFnApiCookieHeader } from './FnHttpClientCookie';
import { escapeJsonString, TAG } from './FnHttpClientCommon';
import { FnHttpClientGalleryHost } from './FnHttpClientTypes';
import { FnHttpClientGalleryRequest } from './FnHttpClientGalleryRequest';
import { FnClientResult, PhotoBackupPathInfo, PhotoFolderListData } from '../../model/FnApiTypes';

const PHOTO_BACKUP_DOMAIN = 0xFF00;
const PHOTO_BACKUP_TAG = 'PhotoBackup';

function isIllegalParameters(message: string | undefined): boolean {
  return (message ?? '').indexOf('illegalParameters') >= 0;
}

function backupIdentityBodies(deviceId: string, deviceName: string, folderPath: string): string[] {
  const id = escapeJsonString(deviceId.trim());
  const name = escapeJsonString(deviceName.trim().length > 0 ? deviceName.trim() : 'Harmony');
  const folder = escapeJsonString(folderPath.trim());
  const withFolder = folder.length > 0;
  const bodies: string[] = [];
  if (withFolder) {
    bodies.push(
      `{"deviceId":"${id}","deviceName":"${name}","folderPath":"${folder}"}`,
      `{"device_id":"${id}","device_name":"${name}","folder_path":"${folder}"}`,
      `{"oem_device_id":"${id}","device_name":"${name}","folder_path":"${folder}"}`
    );
  } else {
    bodies.push(
      `{"deviceId":"${id}","deviceName":"${name}"}`,
      `{"device_id":"${id}","device_name":"${name}"}`,
      `{"oem_device_id":"${id}","device_name":"${name}"}`
    );
  }
  return bodies;
}

function pathKey(key: string): boolean {
  const lo = key.toLowerCase();
  return lo.indexOf('path') >= 0 || lo.indexOf('dir') >= 0 || lo.indexOf('folder') >= 0;
}

function collectBackupPathStrings(
  payload: Object | string | number | undefined | null,
  depth: number
): string[] {
  const out: string[] = [];
  if (depth > 4 || payload === undefined || payload === null) {
    return out;
  }
  if (typeof payload === 'string') {
    return out;
  }
  if (typeof payload !== 'object') {
    return out;
  }
  if (Array.isArray(payload)) {
    const arr = payload as Object[];
    for (let i = 0; i < arr.length; i++) {
      const nested = collectBackupPathStrings(arr[i], depth + 1);
      for (let j = 0; j < nested.length; j++) {
        out.push(nested[j]);
      }
    }
    return out;
  }
  const rec = payload as Record<string, Object | string | number | undefined | null>;
  const keys = Object.keys(rec);
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    const val = rec[key];
    if (typeof val === 'string' && pathKey(key)) {
      const text = val.trim();
      if (text.length > 1 && text !== 'null' && text.indexOf('/') >= 0 && text.indexOf('http') !== 0) {
        out.push(text);
      }
      continue;
    }
    if (val !== undefined && val !== null && typeof val === 'object') {
      const nested = collectBackupPathStrings(val, depth + 1);
      for (let j = 0; j < nested.length; j++) {
        out.push(nested[j]);
      }
    }
  }
  return out;
}

function readTextField(rec: Record<string, Object | string | number | undefined | null>, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const raw = rec[keys[i]];
    if (raw === undefined || raw === null) {
      continue;
    }
    const text = String(raw).trim();
    if (text.length > 0 && text !== 'null' && text !== 'undefined') {
      return text;
    }
  }
  return '';
}

export class FnHttpClientPhotoBackupOps extends FnHttpClientGalleryRequest {
  constructor(host: FnHttpClientGalleryHost) {
    super(host);
  }

  private async postGalleryJson(
    path: string,
    bodyStr: string,
    timeoutMs: number
  ): Promise<FnClientResult<Object>> {
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const authx = await genFnGalleryAuthxPostRaw(path, bodyStr);
      const headers = this.buildGalleryFetchHeaders(authx, cookie);
      headers['Content-Type'] = 'application/json';
      const raw = await this.rawRequest(
        `${activeBase}${path}`,
        http.RequestMethod.POST,
        headers,
        bodyStr,
        timeoutMs,
        CertPolicy.isTrusted(activeBase)
      );
      if (raw.code < 200 || raw.code >= 300) {
        const preview = raw.body.length > 240 ? raw.body.substring(0, 240) : raw.body;
        hilog.warn(PHOTO_BACKUP_DOMAIN, PHOTO_BACKUP_TAG, 'http %{public}d %{public}s %{public}s',
          raw.code, path, preview);
        return { success: false, message: `HTTP ${raw.code}` };
      }
      let parsed: Record<string, string | number | Object | undefined>;
      try {
        parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
      } catch (_e) {
        return { success: false, message: '响应解析失败' };
      }
      if (!FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
        const errLine = FnHttpClientGalleryRequest.envelopeErrorLine(parsed);
        const message = errLine.length > 0 ? errLine : '请求失败';
        const preview = raw.body.length > 240 ? raw.body.substring(0, 240) : raw.body;
        hilog.warn(PHOTO_BACKUP_DOMAIN, PHOTO_BACKUP_TAG, 'biz fail %{public}s %{public}s %{public}s',
          path, message, preview);
        return { success: false, message: message };
      }
      const data = parsed['data'];
      if (data !== undefined && data !== null) {
        return { success: true, data: data as Object };
      }
      return { success: true, data: parsed as Object };
    } catch (e) {
      hilog.warn(PHOTO_BACKUP_DOMAIN, PHOTO_BACKUP_TAG, 'request %{public}s %{public}s', path, String(e));
      fnDiagError(TAG, 'photoBackupApi exception', e);
      return { success: false, message: String(e) || '请求异常' };
    }
  }

  static parseBackupPathInfo(payload: Object | undefined): PhotoBackupPathInfo {
    const out = new PhotoBackupPathInfo();
    if (payload === undefined || payload === null) {
      return out;
    }
    if (typeof payload === 'string') {
      const text = payload.trim();
      if (text.length > 0 && text !== 'null') {
        out.displayPath = text;
        out.deviceBackupPath = text;
      }
      return out;
    }
    if (typeof payload !== 'object' || Array.isArray(payload)) {
      return out;
    }
    const rec = payload as Record<string, Object | string | number | undefined | null>;
    const displayKeys: string[] = [
      'displayPath', 'display_path', 'showPath', 'show_path', 'displayName', 'showName'
    ];
    const deviceKeys: string[] = [
      'deviceBackupPath', 'device_backup_path', 'backupPath', 'backup_path',
      'folderPath', 'folder_path', 'filePath', 'file_path', 'fullPath', 'dirPath', 'dir', 'path'
    ];
    let source = rec;
    if (readTextField(rec, displayKeys).length === 0 && readTextField(rec, deviceKeys).length === 0) {
      const nestedKeys: string[] = ['backup', 'pathInfo', 'info', 'result', 'data'];
      for (let i = 0; i < nestedKeys.length; i++) {
        const child = rec[nestedKeys[i]];
        if (child !== undefined && child !== null && typeof child === 'object' && !Array.isArray(child)) {
          source = child as Record<string, Object | string | number | undefined | null>;
          break;
        }
      }
    }
    out.displayPath = readTextField(source, displayKeys);
    out.deviceBackupPath = readTextField(source, deviceKeys);
    out.folderPath = readTextField(source, ['folderPath', 'folder_path', 'dirPath', 'dir']);
    if (out.deviceBackupPath.length === 0 || out.displayPath.length === 0) {
      const found = collectBackupPathStrings(source, 0);
      if (out.deviceBackupPath.length === 0 && found.length > 0) {
        out.deviceBackupPath = found[0];
      }
      if (out.folderPath.length === 0 && found.length > 0) {
        out.folderPath = found[0];
      }
    }
    if (out.deviceBackupPath.length === 0) {
      out.deviceBackupPath = out.folderPath;
    }
    if (out.displayPath.length === 0) {
      out.displayPath = out.deviceBackupPath;
    }
    return out;
  }

  /**
   * 目录列表与网页相册同一套参数。空 body `{}` 会被 fnOS 判成 illegalParameters。
   */
  async postPhotoFolderList(timeoutMs: number = 20000): Promise<FnClientResult<PhotoFolderListData>> {
    const path = `${FN_PHOTO_API_PREFIX}/photo/folder/list`;
    const res = await this.postGalleryJson(path, '{"desc":false,"orderBy":2}', timeoutMs);
    if (!res.success || res.data === undefined) {
      return { success: false, message: res.message ?? '目录列表失败' };
    }
    const data: PhotoFolderListData = {
      list: FnHttpClientGalleryRequest.parseFolderListPayload(res.data)
    };
    return { success: true, data: data };
  }

  async addPhotoFolder(
    deviceId: string,
    folderPath: string,
    timeoutMs: number = 20000,
    deviceName: string = ''
  ): Promise<FnClientResult<Object>> {
    const path = `${FN_PHOTO_API_PREFIX}/photo/folder/add`;
    const bodies = backupIdentityBodies(deviceId, deviceName, folderPath.trim());
    return await this.postFirstAccepted(path, bodies, timeoutMs);
  }

  async initDefaultPhotoFolder(
    deviceId: string,
    timeoutMs: number = 20000,
    deviceName: string = ''
  ): Promise<FnClientResult<Object>> {
    const path = `${FN_PHOTO_API_PREFIX}/photo/folder/defaultInit`;
    const bodies = backupIdentityBodies(deviceId, deviceName, '');
    return await this.postFirstAccepted(path, bodies, timeoutMs);
  }

  async fetchBackupPathV1(
    deviceId: string,
    deviceName: string,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<PhotoBackupPathInfo>> {
    return await this.fetchBackupPath(`${FN_PHOTO_API_PREFIX}/photo/backup/path`, deviceId, deviceName, timeoutMs);
  }

  async fetchBackupPathV2(
    deviceId: string,
    timeoutMs: number = 20000,
    deviceName: string = ''
  ): Promise<FnClientResult<PhotoBackupPathInfo>> {
    return await this.fetchBackupPath(`${FN_PHOTO_API_V2_PREFIX}/photo/backup/path`, deviceId, deviceName, timeoutMs);
  }

  private async fetchBackupPath(
    path: string,
    deviceId: string,
    deviceName: string,
    timeoutMs: number
  ): Promise<FnClientResult<PhotoBackupPathInfo>> {
    const bodies = backupIdentityBodies(deviceId, deviceName, '');
    let lastMessage = '备份路径获取失败';
    for (let i = 0; i < bodies.length; i++) {
      const res = await this.postGalleryJson(path, bodies[i], timeoutMs);
      if (!res.success) {
        lastMessage = res.message ?? lastMessage;
        if (!isIllegalParameters(res.message)) {
          break;
        }
        continue;
      }
      const info = FnHttpClientPhotoBackupOps.parseBackupPathInfo(res.data);
      hilog.info(PHOTO_BACKUP_DOMAIN, PHOTO_BACKUP_TAG, 'path ok %{public}s body %{public}d display %{public}s',
        path, i, info.displayPath);
      return { success: true, data: info };
    }
    return { success: false, message: lastMessage };
  }

  private async postFirstAccepted(path: string, bodies: string[], timeoutMs: number): Promise<FnClientResult<Object>> {
    let last: FnClientResult<Object> = { success: false, message: '请求失败' };
    for (let i = 0; i < bodies.length; i++) {
      const res = await this.postGalleryJson(path, bodies[i], timeoutMs);
      if (res.success) {
        return res;
      }
      last = res;
      if (!isIllegalParameters(res.message)) {
        break;
      }
    }
    return last;
  }

  async listBackupDeviceFolders(deviceId: string, timeoutMs: number = 20000): Promise<FnClientResult<string[]>> {
    const body = `{"deviceId":"${escapeJsonString(deviceId)}"}`;
    const res = await this.postGalleryJson(`${FN_PHOTO_API_PREFIX}/photo/backup/device/list`, body, timeoutMs);
    if (!res.success || res.data === undefined) {
      return { success: false, message: res.message ?? '备份源列表失败' };
    }
    const folders: string[] = [];
    const payload = res.data;
    if (Array.isArray(payload)) {
      const payloadArr = payload as Object[];
      for (let i = 0; i < payloadArr.length; i++) {
        const el: Object = payloadArr[i];
        if (typeof el === 'string' && el.trim().length > 0) {
          folders.push(el.trim());
        }
      }
    } else if (typeof payload === 'object' && payload !== null) {
      const rec = payload as Record<string, Object | undefined>;
      const raw = rec['list'] ?? rec['items'] ?? rec['folders'];
      if (Array.isArray(raw)) {
        const rawArr = raw as Object[];
        for (let i = 0; i < rawArr.length; i++) {
          const el: Object = rawArr[i];
          if (typeof el === 'string' && el.trim().length > 0) {
            folders.push(el.trim());
            continue;
          }
          if (typeof el === 'object' && el !== null) {
            const row = el as Record<string, Object | string | undefined>;
            const p = readTextField(row as Record<string, Object | string | number | undefined | null>,
              ['path', 'folderPath', 'name', 'dir']);
            if (p.length > 0) {
              folders.push(p);
            }
          }
        }
      }
    }
    return { success: true, data: folders };
  }

  async mergeBackupDeviceFolders(
    deviceId: string,
    deviceName: string,
    deviceBackupPath: string,
    folders: string[],
    timeoutMs: number = 30000
  ): Promise<FnClientResult<Object>> {
    const quoted: string[] = [];
    for (let i = 0; i < folders.length; i++) {
      const f = folders[i].trim();
      if (f.length > 0) {
        quoted.push(`"${escapeJsonString(f)}"`);
      }
    }
    const body =
      `{"deviceId":"${escapeJsonString(deviceId)}","deviceName":"${escapeJsonString(deviceName)}",` +
      `"deviceBackupPath":"${escapeJsonString(deviceBackupPath)}","folders":[${quoted.join(',')}]}`;
    return await this.postGalleryJson(`${FN_PHOTO_API_PREFIX}/photo/backup/device/merge`, body, timeoutMs);
  }
}
