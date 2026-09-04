/**
 * 配置 WebDAV：PUT / GET / MKCOL。
 * 官方 NetworkKit 通过 customMethod 发起 WebDAV 动词。
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CERT_CODES, uint8ArrayToBase64Local, utf8EncodeLocal } from '../network/fnHttpClient/FnHttpClientCommon';
import { AppSettingsWebDavConfig } from './AppSettingsWebDavPrefs';

const TAG: string = 'AppSettingsWebDav';
const DOMAIN: number = 0x3200;
const TIMEOUT_MS: number = 20000;

export interface WebDavOpResult {
  ok: boolean;
  code: number;
  body: string;
  message: string;
}

function trimSlashEnd(url: string): string {
  let out = url.trim();
  while (out.endsWith('/') && out.length > 8) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

function normalizePath(path: string): string {
  let p = path.trim();
  if (p.length === 0) {
    p = '/fmphoto/settings.json';
  }
  if (!p.startsWith('/')) {
    p = `/${p}`;
  }
  return p;
}

function encodePath(path: string): string {
  const parts = path.split('/');
  const out: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].length === 0) {
      out.push('');
    } else {
      out.push(encodeURIComponent(parts[i]));
    }
  }
  return out.join('/');
}

export function joinWebDavUrl(serverUrl: string, remotePath: string): string {
  return `${trimSlashEnd(serverUrl)}${encodePath(normalizePath(remotePath))}`;
}

function parentDirs(path: string): string[] {
  const normalized = normalizePath(path);
  const parts = normalized.split('/');
  const dirs: string[] = [];
  let acc = '';
  const last = parts.length - 1;
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].length === 0) {
      continue;
    }
    if (i === last && !normalized.endsWith('/')) {
      break;
    }
    acc = `${acc}/${parts[i]}`;
    dirs.push(acc);
  }
  return dirs;
}

function basicAuthHeader(username: string, password: string): string {
  const token = uint8ArrayToBase64Local(utf8EncodeLocal(`${username}:${password}`));
  return `Basic ${token}`;
}

function buildHeaders(config: AppSettingsWebDavConfig, contentType: string, contentLength: number): Record<string, string> {
  const headers: Record<string, string> = {};
  if (contentType.length > 0) {
    headers['Content-Type'] = contentType;
  }
  if (contentLength > 0) {
    headers['Content-Length'] = `${contentLength}`;
  }
  if (config.username.trim().length > 0 || config.password.length > 0) {
    headers['Authorization'] = basicAuthHeader(config.username, config.password);
  }
  return headers;
}

function messageForCode(code: number, fallback: string): string {
  if (code === 401 || code === 403) {
    return '账号或密码不正确';
  }
  if (code === 404) {
    return '远端还没有配置文件';
  }
  if (code === 405) {
    return '服务器不支持该 WebDAV 方法';
  }
  if (CERT_CODES.indexOf(code) >= 0) {
    return '证书不可信，可打开跳过证书校验';
  }
  if (fallback.length > 0) {
    return fallback;
  }
  return `请求失败（${code}）`;
}

function isPutOk(code: number): boolean {
  return code === 200 || code === 201 || code === 204;
}

function isMkcolOk(code: number): boolean {
  return code === 200 || code === 201 || code === 405 || code === 409 || code === 301;
}

async function requestOnce(
  url: string,
  method: string,
  config: AppSettingsWebDavConfig,
  body: string,
  contentType: string
): Promise<WebDavOpResult> {
  const req = http.createHttp();
  try {
    const extra: string | undefined = body.length > 0 ? body : undefined;
    const bodyBytes = extra !== undefined ? utf8EncodeLocal(extra).length : 0;
    const opt: http.HttpRequestOptions = {
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: TIMEOUT_MS,
      readTimeout: TIMEOUT_MS,
      header: buildHeaders(config, contentType, bodyBytes),
      customMethod: method
    };
    if (extra !== undefined) {
      opt.extraData = extra;
    }
    if (config.skipCert) {
      opt.remoteValidation = 'skip';
    }
    const resp = await req.request(url, opt);
    const code = resp.responseCode as number;
    const resultRaw = resp.result;
    const text = typeof resultRaw === 'string' ? resultRaw : '';
    return { ok: true, code: code, body: text, message: '' };
  } catch (e) {
    const err = e as BusinessError;
    const code = err.code;
    hilog.error(DOMAIN, TAG, 'webdav %{public}s failed code=%{public}d %{public}s', method, code, err.message);
    return {
      ok: false,
      code: code,
      body: '',
      message: messageForCode(code, err.message)
    };
  } finally {
    try {
      req.destroy();
    } catch (_e) {
    }
  }
}

export function validateWebDavConfig(config: AppSettingsWebDavConfig): string {
  const url = config.serverUrl.trim();
  if (url.length === 0) {
    return '请填写 WebDAV 地址';
  }
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return 'WebDAV 地址需以 http:// 或 https:// 开头';
  }
  return '';
}

export async function ensureWebDavParents(config: AppSettingsWebDavConfig): Promise<WebDavOpResult> {
  const dirs = parentDirs(config.remotePath);
  for (let i = 0; i < dirs.length; i++) {
    const url = `${trimSlashEnd(config.serverUrl)}${encodePath(dirs[i])}/`;
    const res = await requestOnce(url, 'MKCOL', config, '', '');
    if (!res.ok) {
      return res;
    }
    if (!isMkcolOk(res.code) && res.code !== 405 && res.code !== 409) {
      return {
        ok: false,
        code: res.code,
        body: res.body,
        message: messageForCode(res.code, `创建目录失败（${res.code}）`)
      };
    }
  }
  return { ok: true, code: 201, body: '', message: '' };
}

export async function webDavPutJson(config: AppSettingsWebDavConfig, jsonBody: string): Promise<WebDavOpResult> {
  const invalid = validateWebDavConfig(config);
  if (invalid.length > 0) {
    return { ok: false, code: 0, body: '', message: invalid };
  }
  const mk = await ensureWebDavParents(config);
  if (!mk.ok) {
    return mk;
  }
  const url = joinWebDavUrl(config.serverUrl, config.remotePath);
  const res = await requestOnce(url, 'PUT', config, jsonBody, 'application/json; charset=utf-8');
  if (!res.ok) {
    return res;
  }
  if (!isPutOk(res.code)) {
    return {
      ok: false,
      code: res.code,
      body: res.body,
      message: messageForCode(res.code, `上传失败（${res.code}）`)
    };
  }
  return { ok: true, code: res.code, body: res.body, message: '已上传到 WebDAV' };
}

export async function webDavGetJson(config: AppSettingsWebDavConfig): Promise<WebDavOpResult> {
  const invalid = validateWebDavConfig(config);
  if (invalid.length > 0) {
    return { ok: false, code: 0, body: '', message: invalid };
  }
  const url = joinWebDavUrl(config.serverUrl, config.remotePath);
  const res = await requestOnce(url, 'GET', config, '', '');
  if (!res.ok) {
    return res;
  }
  if (res.code !== 200) {
    return {
      ok: false,
      code: res.code,
      body: res.body,
      message: messageForCode(res.code, `下载失败（${res.code}）`)
    };
  }
  if (res.body.trim().length === 0) {
    return { ok: false, code: res.code, body: '', message: '远端文件为空' };
  }
  return { ok: true, code: res.code, body: res.body, message: '' };
}
