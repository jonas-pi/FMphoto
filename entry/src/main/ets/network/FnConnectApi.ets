/**
 * FN Connect：用 FN ID 向飞牛云端解析 NAS 可达地址（对齐官方 App / 社区 FnConnectApi）。
 * POST https://fnos.net/api/v1/fn/con → ipv4 / 中继 / 公网等，再交给登录测速选路。
 */
import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { generateRandomDigits, md5HexUtf8, sha256DigestSafe } from './AuthxSigner';
import { FN_DEFAULT_PORT_HTTP, FN_DEFAULT_PORT_HTTPS, normalizeServerUrl } from './ServerUrl';

const DOMAIN = 0xFF00;
const TAG = 'FnConnect';

/** FN Connect 云端解析接口（客户端签名常量，与官方 App 请求头一致） */
const FN_CONNECT_URL = 'https://fnos.net/api/v1/fn/con';
const FN_CONNECT_PATH = '/api/v1/fn/con';
const FN_SIGN_SECRET = 'anna';
const AUTHX_PREFIX = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
const AUTHX_API_KEY = 'zIGtkc3dqZnJpd29qZXJqa2w7c';

export interface FnConnectAddr {
  /** 主机（可含历史端口片段，已拆到 port） */
  host: string;
  type: string;
  port: number;
}

export interface FnConnectLookupResult {
  ok: boolean;
  message: string;
  /** 公网域名（DDNS 等） */
  publicDomainServer: string;
  /** 公网 IP（兼容：IPv4 优先，否则 IPv6） */
  publicIpServer: string;
  /** 公网 IPv4 */
  publicIpv4Server: string;
  /** 公网 IPv6 */
  publicIpv6Server: string;
  /** 局域网地址（兼容：IPv4 优先，否则 IPv6） */
  lanServer: string;
  /** 内网 IPv4 */
  lanIpv4Server: string;
  /** 内网 IPv6（不含链路本地） */
  lanIpv6Server: string;
  /** FN Connect 中继（暂不使用，固定空串） */
  relayServer: string;
  summary: string;
}

/** 链路本地 / 回环 / 组播 IPv6 不能作为可达候选 */
export function isUnusableIpv6Host(host: string): boolean {
  const h = host.trim().toLowerCase();
  if (h.length === 0) {
    return true;
  }
  if (h.startsWith('[')) {
    const close = h.indexOf(']');
    return isUnusableIpv6Host(close > 1 ? h.substring(1, close) : h.substring(1));
  }
  if (h === '::1' || h === '::' || h === '0:0:0:0:0:0:0:1') {
    return true;
  }
  if (h.startsWith('fe80:')) {
    return true;
  }
  if (h.startsWith('ff')) {
    return true;
  }
  return false;
}

function emptyLookup(message: string): FnConnectLookupResult {
  return {
    ok: false,
    message,
    publicDomainServer: '',
    publicIpServer: '',
    publicIpv4Server: '',
    publicIpv6Server: '',
    lanServer: '',
    lanIpv4Server: '',
    lanIpv6Server: '',
    relayServer: '',
    summary: ''
  };
}

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

function uint8ArrayToHex(data: Uint8Array): string {
  let s = '';
  for (let i = 0; i < data.length; i++) {
    const v = data[i] as number;
    s += (v < 16 ? '0' : '') + v.toString(16);
  }
  return s;
}

async function sha256HexUtf8(text: string): Promise<string> {
  const digest = await sha256DigestSafe(utf8Encode(text));
  return uint8ArrayToHex(digest);
}

/** 纯 FN ID：字母开头、5–32 位字母数字与连字符，不以 - 结尾 */
export function isFnId(input: string): boolean {
  const t = input.trim();
  if (t.length === 0) {
    return false;
  }
  if (t.indexOf('.') >= 0 || t.indexOf(':') >= 0 || t.indexOf('/') >= 0) {
    return false;
  }
  if (t.toLowerCase() === 'localhost') {
    return false;
  }
  return /^[a-zA-Z][a-zA-Z0-9-]{4,31}$/.test(t) && !t.endsWith('-');
}

/** 是否为 FN Connect 中继域名（*.fnos.net / fnos.net/...） */
export function isFnRelayBaseUrl(baseUrl: string): boolean {
  const u = baseUrl.trim().toLowerCase();
  if (u.length === 0) {
    return false;
  }
  return u.indexOf('.fnos.net') >= 0 || u.indexOf('://fnos.net/') >= 0 ||
    u.indexOf('://www.fnos.net/') >= 0;
}

/**
 * 从用户输入提取 FN ID。
 * 支持：纯 FN ID、`xxx.fnos.net`、`https://fnos.net/xxx`、`https://xxx.fnos.net`
 */
export function extractFnId(input: string): string {
  let t = input.trim();
  if (t.length === 0) {
    return '';
  }
  if (t.startsWith('http://')) {
    t = t.substring('http://'.length);
  } else if (t.startsWith('https://')) {
    t = t.substring('https://'.length);
  }
  const slash = t.indexOf('/');
  const q = t.indexOf('?');
  let cut = t.length;
  if (slash >= 0 && slash < cut) {
    cut = slash;
  }
  if (q >= 0 && q < cut) {
    cut = q;
  }
  const authority = t.substring(0, cut);
  const pathPart = slash >= 0 ? t.substring(slash + 1) : '';
  const pathSeg = pathPart.split('/')[0].split('?')[0].trim();

  // fnos.net/{fnId} 或 www.fnos.net/{fnId}
  const authLower = authority.toLowerCase();
  if (authLower === 'fnos.net' || authLower === 'www.fnos.net' ||
    authLower.startsWith('fnos.net:') || authLower.startsWith('www.fnos.net:')) {
    if (isFnId(pathSeg)) {
      return pathSeg;
    }
  }

  // {fnId}.fnos.net[:port]
  const hostOnly = authority.indexOf(':') > 0 && !authority.startsWith('[')
    ? authority.substring(0, authority.lastIndexOf(':'))
    : authority;
  const m = hostOnly.match(/^([a-zA-Z][a-zA-Z0-9-]{4,31})\.fnos\.net$/i);
  if (m !== null && m[1] !== undefined && isFnId(m[1])) {
    return m[1];
  }

  if (isFnId(t)) {
    return t;
  }
  return '';
}

function parseHostPort(raw: string, defaultPort: number): FnConnectAddr {
  let address = raw.trim();
  let port = defaultPort;
  // IPv6 原样（不含端口拆分）
  if (address.indexOf(':') >= 0 && address.indexOf('.') < 0 && !/^\[[^\]]+\]:\d+$/.test(address)) {
    if (address.startsWith('[') && address.indexOf(']:') > 0) {
      const close = address.indexOf(']');
      const after = address.substring(close + 1);
      if (after.startsWith(':')) {
        const ps = after.substring(1);
        if (/^\d+$/.test(ps)) {
          port = parseInt(ps, 10);
          address = address.substring(1, close);
        }
      }
    }
    return { host: address, type: '', port: port };
  }
  if (address.indexOf(':') > 0 && !address.startsWith('[')) {
    const colonIdx = address.lastIndexOf(':');
    const tail = address.substring(colonIdx + 1);
    if (/^\d+$/.test(tail)) {
      port = parseInt(tail, 10);
      address = address.substring(0, colonIdx);
    }
  }
  return { host: address, type: '', port: port };
}

function isPrivateIpv4(host: string): boolean {
  if (host.startsWith('192.168.') || host.startsWith('10.')) {
    return true;
  }
  if (host.startsWith('172.')) {
    const parts = host.split('.');
    if (parts.length >= 2) {
      const second = parseInt(parts[1], 10);
      return !isNaN(second) && second >= 16 && second <= 31;
    }
  }
  return false;
}

function addrPriority(a: FnConnectAddr): number {
  if (a.type === 'ipv4' || a.type === 'ipv6') {
    if (a.type === 'ipv4' && a.host.startsWith('192.168.')) {
      return 0;
    }
    if (a.type === 'ipv4' && a.host.startsWith('10.')) {
      return 1;
    }
    if (a.type === 'ipv4' && isPrivateIpv4(a.host)) {
      return 2;
    }
    if (a.type === 'ipv4') {
      return 3;
    }
    return 4;
  }
  if (a.type === 'ddns') {
    return 5;
  }
  if (a.type === 'relay') {
    return 6;
  }
  if (a.type === 'publicIpv4') {
    return 7;
  }
  if (a.type === 'publicIpv6') {
    return 8;
  }
  return 9;
}

function toBaseUrl(addr: FnConnectAddr, useHttps: boolean): string {
  const host = addr.host.indexOf(':') >= 0 && addr.host.indexOf('.') < 0
    ? `[${addr.host}]`
    : addr.host;
  const hostLower = addr.host.toLowerCase();
  // FN Connect 中继：官方入口为 https://fnos.net/{fnId}（443），绝不能带 NAS 本地 5666/5667
  if (addr.type === 'relay' || hostLower.endsWith('.fnos.net')) {
    const relay = normalizeFnRelayBaseUrl(addr.host);
    return relay.length > 0 ? relay : `https://${host}`;
  }
  if (addr.port === 443) {
    return `https://${host}`;
  }
  if (addr.port === 80) {
    return useHttps ? `https://${host}` : `http://${host}`;
  }
  if (useHttps) {
    let port = addr.port;
    if (port === FN_DEFAULT_PORT_HTTP || port === 8000) {
      port = FN_DEFAULT_PORT_HTTPS;
    }
    return `https://${host}:${port}`;
  }
  let httpPort = addr.port;
  if (httpPort === FN_DEFAULT_PORT_HTTPS) {
    httpPort = FN_DEFAULT_PORT_HTTP;
  }
  return `http://${host}:${httpPort}`;
}

/**
 * 规范中继 baseUrl：官方 FN Connect 入口 `https://fnos.net/{fnId}`（443，无本地端口）。
 * 兼容旧写法 `{fnId}.fnos.net` / `https://{fnId}.fnos.net`。
 */
export function normalizeFnRelayBaseUrl(fnIdOrUrl: string): string {
  const id = extractFnId(fnIdOrUrl);
  if (id.length > 0) {
    return `https://fnos.net/${id}`;
  }
  const bare = fnIdOrUrl.trim();
  if (isFnId(bare)) {
    return `https://fnos.net/${bare}`;
  }
  return '';
}

function readStringArray(obj: Record<string, Object | undefined>, key: string): string[] {
  const raw = obj[key];
  if (raw === undefined || raw === null || !Array.isArray(raw)) {
    return [];
  }
  const arr = raw as Array<string | number | boolean | Object | null | undefined>;
  const out: string[] = [];
  for (let i = 0; i < arr.length; i++) {
    const v = arr[i];
    if (typeof v === 'string' && v.trim().length > 0) {
      out.push(v.trim());
    }
  }
  return out;
}

function collectAddrs(
  data: Record<string, Object | undefined>,
  httpPort: number
): FnConnectAddr[] {
  const specs: string[][] = [
    ['ipv4', 'ipv4'],
    ['ipv6', 'ipv6'],
    ['ddns', 'ddns'],
    ['fn', 'relay'],
    ['publicIpv4', 'publicIpv4'],
    ['publicIpv6', 'publicIpv6']
  ];
  const list: FnConnectAddr[] = [];
  for (let i = 0; i < specs.length; i++) {
    const key = specs[i][0];
    const type = specs[i][1];
    const arr = readStringArray(data, key);
    for (let j = 0; j < arr.length; j++) {
      const parsed = parseHostPort(arr[j], httpPort);
      parsed.type = type;
      list.push(parsed);
    }
  }
  list.sort((a: FnConnectAddr, b: FnConnectAddr): number => addrPriority(a) - addrPriority(b));
  return list;
}

async function buildFnSign(fnId: string, timestamp: number): Promise<string> {
  // 分隔符为反引号，与官方客户端一致：trim_connect`fnId`ts`anna
  const raw = `trim_connect\`${fnId}\`${timestamp}\`${FN_SIGN_SECRET}`;
  return sha256HexUtf8(raw);
}

async function buildConnectAuthx(bodyStr: string, timestamp: number): Promise<string> {
  const nonce = generateRandomDigits();
  const bodyMd5 = await md5HexUtf8(bodyStr);
  const signStr =
    `${AUTHX_PREFIX}_${FN_CONNECT_PATH}_${nonce}_${timestamp}_${bodyMd5}_${AUTHX_API_KEY}`;
  const sign = await md5HexUtf8(signStr);
  return `nonce=${nonce}&timestamp=${timestamp}&sign=${sign}`;
}

/**
 * 向 FN Connect 云端解析 FN ID，拆成公网 / 内网 / 中继三类地址。
 */
export async function lookupFnConnect(fnId: string, useHttps: boolean): Promise<FnConnectLookupResult> {
  const id = fnId.trim();
  if (!isFnId(id)) {
    return emptyLookup('FN ID 格式不正确');
  }

  const timestamp = Date.now();
  const bodyObj: Record<string, string> = { 'fnId': id };
  const bodyStr = JSON.stringify(bodyObj);
  const fnSign = await buildFnSign(id, timestamp);
  const authx = await buildConnectAuthx(bodyStr, timestamp);

  const req = http.createHttp();
  try {
    const opt: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'fn-sign': fnSign,
        'authx': authx
      },
      extraData: bodyStr,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 12000,
      readTimeout: 12000
    };
    const resp = await req.request(FN_CONNECT_URL, opt);
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      hilog.warn(DOMAIN, TAG, 'FN Connect HTTP %{public}d', resp.responseCode);
      return fallbackFnosNet(id, useHttps, `云端返回 HTTP ${resp.responseCode}`);
    }
    const text = typeof resp.result === 'string' ? resp.result : String(resp.result);
    let root: Record<string, Object | undefined>;
    try {
      root = JSON.parse(text) as Record<string, Object | undefined>;
    } catch (_e) {
      return fallbackFnosNet(id, useHttps, '云端响应无法解析');
    }
    const codeRaw = root['code'];
    const code = typeof codeRaw === 'number' ? codeRaw : -1;
    if (code !== 0) {
      const msgRaw = root['msg'];
      const msg = typeof msgRaw === 'string' && msgRaw.length > 0 ? msgRaw : `云端错误 code=${code}`;
      return fallbackFnosNet(id, useHttps, msg);
    }
    const dataRaw = root['data'];
    if (dataRaw === undefined || dataRaw === null || typeof dataRaw !== 'object') {
      return fallbackFnosNet(id, useHttps, '云端未返回地址列表');
    }
    const data = dataRaw as Record<string, Object | undefined>;
    let httpPort = FN_DEFAULT_PORT_HTTP;
    const portRaw = data['port'];
    if (portRaw !== undefined && portRaw !== null && typeof portRaw === 'object') {
      const portObj = portRaw as Record<string, Object | undefined>;
      const hp = portObj['httpPort'];
      if (typeof hp === 'number' && hp > 0) {
        httpPort = hp;
      }
    }
    const addrs = collectAddrs(data, httpPort);
    if (addrs.length === 0) {
      return fallbackFnosNet(id, useHttps, '未解析到可用地址');
    }

    let lanIpv4Server = '';
    let lanIpv6Server = '';
    let publicDomainServer = '';
    let publicIpv4Server = '';
    let publicIpv6Server = '';
    const labels: string[] = [];
    for (let i = 0; i < addrs.length; i++) {
      const a = addrs[i];
      const url = normalizeServerUrl(toBaseUrl(a, useHttps), useHttps);
      if (url.length === 0) {
        continue;
      }
      labels.push(`${a.type}`);
      if (a.type === 'relay') {
        // 官方中继隧道未对第三方开放：忽略 fn / *.fnos.net 门户地址
        continue;
      }
      if (a.type === 'ddns') {
        if (publicDomainServer.length === 0) {
          publicDomainServer = url;
        }
        continue;
      }
      if (a.type === 'publicIpv4') {
        if (publicIpv4Server.length === 0) {
          publicIpv4Server = url;
        }
        continue;
      }
      if (a.type === 'publicIpv6') {
        if (isUnusableIpv6Host(a.host)) {
          continue;
        }
        if (publicIpv6Server.length === 0) {
          publicIpv6Server = url;
        }
        continue;
      }
      if (a.type === 'ipv6') {
        if (isUnusableIpv6Host(a.host)) {
          continue;
        }
        if (lanIpv6Server.length === 0) {
          lanIpv6Server = url;
        }
        continue;
      }
      if (a.type === 'ipv4') {
        if (isPrivateIpv4(a.host)) {
          if (lanIpv4Server.length === 0) {
            lanIpv4Server = url;
          }
        } else if (publicIpv4Server.length === 0) {
          publicIpv4Server = url;
        }
        continue;
      }
      if (a.host.indexOf('.') >= 0 && !isPrivateIpv4(a.host) &&
        !/^\d+\.\d+\.\d+\.\d+$/.test(a.host)) {
        if (publicDomainServer.length === 0) {
          publicDomainServer = url;
        }
      } else if (publicIpv4Server.length === 0) {
        publicIpv4Server = url;
      }
    }
    const lanServer = lanIpv4Server.length > 0 ? lanIpv4Server : lanIpv6Server;
    const publicIpServer = publicIpv4Server.length > 0 ? publicIpv4Server : publicIpv6Server;
    if (publicDomainServer.length === 0 && publicIpServer.length === 0 &&
      lanServer.length === 0) {
      return emptyLookup('FN Connect 未返回可用的公网或内网地址');
    }
    const summary = `FN Connect 已解析 ${id}（${labels.join('/')}）`;
    hilog.info(DOMAIN, TAG,
      'lookup ok fnId=%{public}s domain=%{public}s v4=%{public}s v6=%{public}s lan4=%{public}s lan6=%{public}s',
      id, publicDomainServer, publicIpv4Server, publicIpv6Server, lanIpv4Server, lanIpv6Server);
    return {
      ok: true,
      message: '',
      publicDomainServer,
      publicIpServer,
      publicIpv4Server,
      publicIpv6Server,
      lanServer,
      lanIpv4Server,
      lanIpv6Server,
      relayServer: '',
      summary
    };
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'lookup failed: %{public}s', String(e));
    return fallbackFnosNet(id, useHttps, `FN Connect 请求失败：${String(e)}`);
  } finally {
    try {
      req.destroy();
    } catch (_e) {
    }
  }
}

/** 云端失败：不再回退到中继门户（第三方无法用其做 NAS 登录） */
function fallbackFnosNet(fnId: string, _useHttps: boolean, reason: string): FnConnectLookupResult {
  hilog.warn(DOMAIN, TAG, 'fallback fail fnId=%{public}s reason=%{public}s', fnId, reason);
  return emptyLookup(reason);
}
