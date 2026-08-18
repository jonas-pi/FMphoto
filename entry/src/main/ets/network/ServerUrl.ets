/**
 * 将用户输入规范为 API baseUrl（无末尾 /）
 * - 飞牛默认端口：HTTP 5666，HTTPS 5667（未写端口时自动补上）
 * - IPv6：裸地址会加 []；含端口时请使用 [addr]:port 形式，避免歧义
 */

/** 飞牛 Web/开放 API 常用端口 */
export const FN_DEFAULT_PORT_HTTP = 5666;
export const FN_DEFAULT_PORT_HTTPS = 5667;
const WEB_DEFAULT_PORT_HTTP = 80;
const WEB_DEFAULT_PORT_HTTPS = 443;

function trimTrailingSlash(s: string): string {
  if (s.length > 1 && s.endsWith('/')) {
    return s.substring(0, s.length - 1);
  }
  return s;
}

function countColons(s: string): number {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    if (s.charAt(i) === ':') {
      n++;
    }
  }
  return n;
}

/** 裸地址（无 []）是否按 IPv6 处理：含 :: 或多段冒号分隔 */
function isBareIpv6Shape(s: string): boolean {
  if (s.indexOf('::') >= 0) {
    return true;
  }
  return countColons(s) >= 2;
}

/** 是否为 a.b.c.d 或 a.b.c.d:port */
function isIpv4WithOptionalPort(s: string): boolean {
  const lastColon = s.lastIndexOf(':');
  let host = s;
  if (lastColon > 0) {
    const tail = s.substring(lastColon + 1);
    if (/^\d+$/.test(tail)) {
      host = s.substring(0, lastColon);
    }
  }
  const parts = host.split('.');
  if (parts.length !== 4) {
    return false;
  }
  for (let i = 0; i < 4; i++) {
    const n = parseInt(parts[i], 10);
    if (isNaN(n) || n < 0 || n > 255) {
      return false;
    }
  }
  return true;
}

function isIpv4Literal(s: string): boolean {
  const parts = s.split('.');
  if (parts.length !== 4) {
    return false;
  }
  for (let i = 0; i < 4; i++) {
    if (!/^\d+$/.test(parts[i])) {
      return false;
    }
    const n = parseInt(parts[i], 10);
    if (isNaN(n) || n < 0 || n > 255) {
      return false;
    }
  }
  return true;
}

function defaultPort(useHttps: boolean, directHost: boolean): number {
  if (directHost) {
    return useHttps ? FN_DEFAULT_PORT_HTTPS : FN_DEFAULT_PORT_HTTP;
  }
  return useHttps ? WEB_DEFAULT_PORT_HTTPS : WEB_DEFAULT_PORT_HTTP;
}

function isDirectHostInput(s: string): boolean {
  if (s.startsWith('[') || isBareIpv6Shape(s)) {
    return true;
  }
  return isIpv4WithOptionalPort(s);
}

/**
 * 用户未写协议时的主机部分，输出 authority（含端口；IPv6 为 [addr]:port）
 */
function normalizeBareAuthority(input: string, useHttps: boolean): string {
  const def = defaultPort(useHttps, isDirectHostInput(input.trim()));
  const t = input.trim();
  if (t.startsWith('[')) {
    const close = t.indexOf(']');
    if (close < 1) {
      return `[${t.substring(1)}]:${def}`;
    }
    const inside = t.substring(1, close);
    const after = t.substring(close + 1);
    if (after.startsWith(':')) {
      const portStr = after.substring(1);
      if (/^\d+$/.test(portStr)) {
        return `[${inside}]:${portStr}`;
      }
    }
    return `[${inside}]:${def}`;
  }
  const lastColon = t.lastIndexOf(':');
  if (lastColon > 0) {
    const tail = t.substring(lastColon + 1);
    if (/^\d+$/.test(tail)) {
      const hostPart = t.substring(0, lastColon);
      const p = parseInt(tail, 10);
      if (isBareIpv6Shape(hostPart)) {
        return `[${hostPart}]:${p}`;
      }
      return `${hostPart}:${p}`;
    }
  }
  if (isBareIpv6Shape(t)) {
    return `[${t}]:${def}`;
  }
  if (isIpv4WithOptionalPort(t)) {
    if (lastColon > 0 && /^\d+$/.test(t.substring(lastColon + 1))) {
      return t;
    }
    return `${t}:${def}`;
  }
  return `${t}:${def}`;
}

/** 从绝对 URL 的 authority 解析主机与端口（不含默认端口补全） */
interface ParsedAuthority {
  useBracket: boolean;
  hostRaw: string;
  port: number | null;
}

function parseAuthority(authority: string): ParsedAuthority {
  const out: ParsedAuthority = { useBracket: false, hostRaw: '', port: null };
  if (authority.length === 0) {
    return out;
  }
  if (authority.startsWith('[')) {
    const close = authority.indexOf(']');
    if (close < 1) {
      out.useBracket = true;
      out.hostRaw = authority.substring(1);
      return out;
    }
    out.useBracket = true;
    out.hostRaw = authority.substring(1, close);
    const after = authority.substring(close + 1);
    if (after.startsWith(':')) {
      const ps = after.substring(1);
      if (/^\d+$/.test(ps)) {
        out.port = parseInt(ps, 10);
      }
    }
    return out;
  }
  const lastColon = authority.lastIndexOf(':');
  if (lastColon > 0) {
    const tail = authority.substring(lastColon + 1);
    if (/^\d+$/.test(tail)) {
      const hostPart = authority.substring(0, lastColon);
      if (!isBareIpv6Shape(hostPart)) {
        out.useBracket = false;
        out.hostRaw = hostPart;
        out.port = parseInt(tail, 10);
        return out;
      }
    }
  }
  if (isBareIpv6Shape(authority)) {
    out.useBracket = true;
    out.hostRaw = authority;
    return out;
  }
  out.hostRaw = authority;
  return out;
}

function buildAuthority(p: ParsedAuthority, defaultP: number): string {
  const port = p.port !== null ? p.port : defaultP;
  if (p.useBracket) {
    return `[${p.hostRaw}]:${port}`;
  }
  return `${p.hostRaw}:${port}`;
}

function isDirectParsedAuthority(p: ParsedAuthority): boolean {
  if (p.useBracket) {
    return true;
  }
  return isIpv4Literal(p.hostRaw);
}

/** 是否为 FN Connect 官方中继域名（*.5ddd.com / *.fnos.net），勿改写为 5666/5667 */
function isFnConnectRelayAuthority(authority: string): boolean {
  const a = authority.trim().toLowerCase();
  const colon = a.lastIndexOf(':');
  const host = colon > 0 && /^\d+$/.test(a.substring(colon + 1)) ? a.substring(0, colon) : a;
  return host === 'fnos.net' || host === 'www.fnos.net' || host.endsWith('.fnos.net') ||
    host === '5ddd.com' || host === 'www.5ddd.com' || host.endsWith('.5ddd.com');
}

/** 去掉中继域名上误带的常见端口，保留主机名 */
function stripFnConnectRelayPort(authority: string): string {
  const colon = authority.lastIndexOf(':');
  if (colon <= 0 || authority.startsWith('[')) {
    return authority;
  }
  const portStr = authority.substring(colon + 1);
  if (portStr !== '80' && portStr !== '443' && portStr !== '5666' && portStr !== '5667' &&
    portStr !== '8000' && portStr !== '8001') {
    return authority;
  }
  return authority.substring(0, colon);
}

/**
 * 已为 http(s):// 的 URL：补默认端口（若未写端口）；保留 path（如 fnos.net/{fnId}）
 */
function ensurePortForAbsoluteUrl(url: string, scheme: 'http' | 'https'): string {
  const prefix = scheme === 'https' ? 'https://' : 'http://';
  const afterScheme = url.substring(prefix.length);
  let cut = afterScheme.length;
  const slash = afterScheme.indexOf('/');
  if (slash >= 0 && slash < cut) {
    cut = slash;
  }
  const query = afterScheme.indexOf('?');
  if (query >= 0 && query < cut) {
    cut = query;
  }
  const hash = afterScheme.indexOf('#');
  if (hash >= 0 && hash < cut) {
    cut = hash;
  }
  let authority = afterScheme.substring(0, cut);
  const pathSuffix = afterScheme.substring(cut);
  if (authority.endsWith('/')) {
    authority = authority.substring(0, authority.length - 1);
  }
  if (authority.length === 0) {
    return trimTrailingSlash(url);
  }
  // FN Connect 门户 / 中继域名固定 443，不补 NAS 默认端口，并保留 /{fnId}
  if (isFnConnectRelayAuthority(authority)) {
    const hostOnly = stripFnConnectRelayPort(authority);
    return trimTrailingSlash(`${prefix}${hostOnly}${pathSuffix}`);
  }
  const parsed = parseAuthority(authority);
  const def = defaultPort(scheme === 'https', isDirectParsedAuthority(parsed));
  const newAuth = buildAuthority(parsed, def);
  return trimTrailingSlash(`${prefix}${newAuth}${pathSuffix}`);
}

/**
 * 将用户输入的域名或完整 URL 规范为 API baseUrl（无末尾 /）
 */
/**
 * 由 HTTP(S) baseUrl（无尾 /）生成 fnOS 主 WebSocket URL（type=main）
 */
export function buildFnMainWebSocketUrl(httpBaseNoSlash: string): string {
  let u = httpBaseNoSlash.trim();
  if (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  if (u.startsWith('https://')) {
    return `wss://${u.substring('https://'.length)}/websocket?type=main`;
  }
  if (u.startsWith('http://')) {
    return `ws://${u.substring('http://'.length)}/websocket?type=main`;
  }
  return `wss://${u}/websocket?type=main`;
}

/**
 * 内置 Web（首页/相册）专用站点根：与登录 API 同主机，端口强制为飞牛约定
 * HTTP → :5666，HTTPS → :5667（避免误用其它端口导致白屏或 H5 不可用）
 */
export function fnWebUiBaseUrl(apiBaseNoSlash: string, sessionUseHttps: boolean): string {
  let rest = apiBaseNoSlash.trim();
  if (rest.endsWith('/')) {
    rest = rest.substring(0, rest.length - 1);
  }
  if (rest.startsWith('https://')) {
    rest = rest.substring('https://'.length);
  } else if (rest.startsWith('http://')) {
    rest = rest.substring('http://'.length);
  }
  const slash = rest.indexOf('/');
  const authority = slash >= 0 ? rest.substring(0, slash) : rest;
  // FN Connect：保持 https://{fnId}.5ddd.com 或路径门户，勿改写为 :5666/:5667
  if (isFnConnectRelayAuthority(authority)) {
    const path = slash >= 0 ? rest.substring(slash) : '';
    return trimTrailingSlash(`https://${stripFnConnectRelayPort(authority)}${path}`);
  }
  const parsed = parseAuthority(authority);
  const defPort = sessionUseHttps ? FN_DEFAULT_PORT_HTTPS : FN_DEFAULT_PORT_HTTP;
  const newAuth = buildAuthority(parsed, defPort);
  const prefix = sessionUseHttps ? 'https://' : 'http://';
  return trimTrailingSlash(`${prefix}${newAuth}`);
}

/**
 * 内置 Web 管理端根地址（与 sample/fnos_window.py、fnos-third-party-login.md 一致）：
 * 固定 **https://主机:5667**，与 wss 同端口；不因登录勾选 HTTP 而改走 5666。
 */
export function fnWebViewBaseUrl(apiBaseNoSlash: string): string {
  let rest = apiBaseNoSlash.trim();
  if (rest.endsWith('/')) {
    rest = rest.substring(0, rest.length - 1);
  }
  if (rest.startsWith('https://')) {
    rest = rest.substring('https://'.length);
  } else if (rest.startsWith('http://')) {
    rest = rest.substring('http://'.length);
  }
  const slash = rest.indexOf('/');
  const authority = slash >= 0 ? rest.substring(0, slash) : rest;
  // FN Connect 门户保留 path，勿改写为 :5667
  if (isFnConnectRelayAuthority(authority)) {
    const path = slash >= 0 ? rest.substring(slash) : '';
    return trimTrailingSlash(`https://${stripFnConnectRelayPort(authority)}${path}`);
  }
  const parsed = parseAuthority(authority);
  const parsedForBuild: ParsedAuthority = isDirectParsedAuthority(parsed)
    ? { useBracket: parsed.useBracket, hostRaw: parsed.hostRaw, port: null }
    : parsed;
  const newAuth = buildAuthority(parsedForBuild, defaultPort(true, isDirectParsedAuthority(parsed)));
  return trimTrailingSlash(`https://${newAuth}`);
}

export function normalizeServerUrl(domainInput: string, useHttps: boolean): string {
  const t = domainInput.trim();
  if (t.length === 0) {
    return '';
  }
  if (t.startsWith('http://')) {
    return ensurePortForAbsoluteUrl(t, 'http');
  }
  if (t.startsWith('https://')) {
    return ensurePortForAbsoluteUrl(t, 'https');
  }
  const prefix = useHttps ? 'https://' : 'http://';
  const auth = normalizeBareAuthority(t, useHttps);
  return trimTrailingSlash(`${prefix}${auth}`);
}

export interface ParsedBaseUrlParts {
  scheme: 'http' | 'https';
  host: string;
  port: number | null;
  useBracket: boolean;
}

/** 解析已规范化的 baseUrl，取出 scheme / host / port */
export function parseNormalizedBaseUrl(baseUrl: string): ParsedBaseUrlParts | null {
  let u = baseUrl.trim();
  if (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  let scheme: 'http' | 'https' = 'https';
  let rest = u;
  if (u.startsWith('https://')) {
    scheme = 'https';
    rest = u.substring('https://'.length);
  } else if (u.startsWith('http://')) {
    scheme = 'http';
    rest = u.substring('http://'.length);
  } else {
    return null;
  }
  const slash = rest.indexOf('/');
  const authority = slash >= 0 ? rest.substring(0, slash) : rest;
  if (authority.length === 0) {
    return null;
  }
  const parsed = parseAuthority(authority);
  return {
    scheme,
    host: parsed.hostRaw,
    port: parsed.port,
    useBracket: parsed.useBracket
  };
}

/** 主机是否为 IPv4 / IPv6 字面量 */
export function isIpLiteralHost(host: string): boolean {
  const h = host.trim();
  if (h.length === 0) {
    return false;
  }
  if (isIpv4Literal(h)) {
    return true;
  }
  if (h.indexOf(':') >= 0 || h.indexOf('::') >= 0) {
    return true;
  }
  return false;
}

/** 用新主机替换 baseUrl 中的 host（保留协议与端口） */
export function replaceBaseUrlHost(baseUrl: string, newHost: string): string {
  const parts = parseNormalizedBaseUrl(baseUrl);
  if (parts === null || newHost.trim().length === 0) {
    return '';
  }
  const host = newHost.trim();
  const useBracket = host.indexOf(':') >= 0 && !isIpv4Literal(host);
  const auth: ParsedAuthority = {
    useBracket: useBracket,
    hostRaw: host,
    port: parts.port
  };
  const def = defaultPort(parts.scheme === 'https', isDirectParsedAuthority(auth));
  return trimTrailingSlash(`${parts.scheme}://${buildAuthority(auth, def)}`);
}

