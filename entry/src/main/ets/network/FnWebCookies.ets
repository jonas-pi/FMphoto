/**
 * 飞牛 H5 会话：与浏览器访问首页时携带的 Cookie 对齐（见 DevTools：fnos-token、fnos-long-token 等）。
 * OpenAPI 仍可用 Authorization + mode=relay；Web 侧需写入 fnos-token，否则易在 H5 再登一次。
 * 相册 Web 常用根路径 /album；另有 /p、/p/album、/p/v1 等以兼容不同版本。
 */
import { webview } from '@kit.ArkWeb';
import { fnPhotoCookieUrls } from './FnPhotoRoutes';

function trimTrailingSlashLocal(s: string): string {
  if (s.length > 1 && s.endsWith('/')) {
    return s.substring(0, s.length - 1);
  }
  return s;
}

/** 解析 "a=b; c=d" 到 Map（同名后者覆盖） */
function parseCookieHeaderIntoMap(header: string, into: Map<string, string>): void {
  const parts = header.split(';');
  for (let i = 0; i < parts.length; i++) {
    const seg = parts[i].trim();
    if (seg.length === 0) {
      continue;
    }
    const eq = seg.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const k = seg.substring(0, eq).trim();
    const v = seg.substring(eq + 1).trim();
    if (k.length === 0) {
      continue;
    }
    into.set(k, v);
  }
}

/** 先写入 web 侧键值，再用 native 覆盖同名键，序列化为 Cookie 请求头 */
function mergeSemicolonCookiesWebFirstNativeWins(webPart: string, nativePart: string): string {
  const m = new Map<string, string>();
  parseCookieHeaderIntoMap(webPart, m);
  parseCookieHeaderIntoMap(nativePart, m);
  const keys: string[] = [];
  m.forEach((_v: string, k: string) => {
    keys.push(k);
  });
  keys.sort();
  const out: string[] = [];
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    const v = m.get(k);
    if (v !== undefined) {
      out.push(`${k}=${v}`);
    }
  }
  return out.join('; ');
}

/**
 * 读取 Web 内核已为相册同源（/p/）存储的 Cookie，与原生构造的 Cookie 合并；同名键以 native 为准。
 * 图库 GET 仅靠 OpenAPI token 时，若 H5 另下发了 HttpOnly 等字段，易出现服务端返回 update failed。
 */
export function mergeGalleryWebCookieIntoNativeHeader(nativeCookie: string, webViewBaseNoTrailingSlash: string): string {
  const base = trimTrailingSlashLocal(webViewBaseNoTrailingSlash.trim());
  if (base.length === 0) {
    return nativeCookie;
  }
  const probeUrl = `${base}/p/`;
  let webRaw = '';
  try {
    webRaw = webview.WebCookieManager.fetchCookieSync(probeUrl);
  } catch (_e) {
    return nativeCookie;
  }
  if (webRaw === undefined || webRaw === null) {
    return nativeCookie;
  }
  const w = String(webRaw).trim();
  if (w.length === 0) {
    return nativeCookie;
  }
  return mergeSemicolonCookiesWebFirstNativeWins(w, nativeCookie);
}

/**
 * 登录接口返回的 token 与浏览器里 fnos-token 一般为同一套会话，可直接写入 Web。
 * fnos-long-token 多为 Set-Cookie 下发，当前客户端若未解析响应头则无法伪造，仅在有值时注入。
 */
export function buildFnWebCookieHeader(sessionToken: string, longToken?: string): string {
  let s = `fnos-token=${sessionToken}; language=zh-CN`;
  if (longToken !== undefined && longToken.length > 0) {
    s += `; fnos-long-token=${longToken}`;
  }
  // 部分接口/旧版页面仍认 Trim-MC-token，与 token 同值时一并带上
  s += `; Trim-MC-token=${sessionToken}; mode=relay`;
  return s;
}

/** 从 baseUrl（无尾斜杠，如 http://host:5666）解析 Set-Cookie 用的 Domain（不含端口；IPv6 无方括号） */
function cookieDomainFromBase(base: string): string {
  const idx = base.indexOf('://');
  const rest = idx >= 0 ? base.substring(idx + 3) : base;
  const slash = rest.indexOf('/');
  const auth = slash >= 0 ? rest.substring(0, slash) : rest;
  if (auth.startsWith('[')) {
    const close = auth.indexOf(']');
    if (close > 1) {
      return auth.substring(1, close);
    }
  }
  const lastColon = auth.lastIndexOf(':');
  if (lastColon > 0) {
    const tail = auth.substring(lastColon + 1);
    if (/^\d+$/.test(tail)) {
      return auth.substring(0, lastColon);
    }
  }
  return auth;
}

/**
 * Cookie Domain 属性不能是 IP/IPv6 字面量（RFC6265），否则整段 Set-Cookie 常被内核丢弃。
 * 此类主机只能写「与 URL 绑定」的不带 Domain 的 Cookie。
 */
function isIpLiteralHost(hostForDomain: string): boolean {
  if (hostForDomain.length === 0) {
    return false;
  }
  if (hostForDomain.indexOf(':') >= 0) {
    return true;
  }
  const ipv4 = /^(\d{1,3}\.){3}\d{1,3}$/;
  return ipv4.test(hostForDomain);
}

function oneCookieLine(nameValue: string, domain: string, useHttps: boolean, withDomain: boolean): string {
  const secure = useHttps ? '; Secure' : '';
  /** Lax 在文档导航场景足够；SameSite=None 在部分 WebView 与 IP 站点上易异常 */
  const sameSite = '; SameSite=Lax';
  const dom = withDomain ? `; Domain=${domain}` : '';
  return `${nameValue}; Path=/${dom}${secure}${sameSite}`;
}

/**
 * 在加载页面前写入内核 Cookie（多 URL 尝试，兼容 IPv6 与路径）
 */
export function injectFnWebCookies(
  baseNoSlash: string,
  sessionToken: string,
  useHttps: boolean,
  longToken?: string
): void {
  const domain = cookieDomainFromBase(baseNoSlash);
  const hostIsIp = isIpLiteralHost(domain);
  const urls: string[] = fnPhotoCookieUrls(baseNoSlash);
  const pairs: string[] = [
    `fnos-token=${sessionToken}`,
    'language=zh-CN',
    `Trim-MC-token=${sessionToken}`,
    'mode=relay'
  ];
  if (longToken !== undefined && longToken.length > 0) {
    pairs.push(`fnos-long-token=${longToken}`);
  }
  for (let u = 0; u < urls.length; u++) {
    const url = urls[u];
    for (let p = 0; p < pairs.length; p++) {
      const lineSimple = oneCookieLine(pairs[p], domain, useHttps, false);
      if (!hostIsIp) {
        const lineWithDom = oneCookieLine(pairs[p], domain, useHttps, true);
        try {
          webview.WebCookieManager.configCookieSync(url, lineWithDom);
        } catch (_e) {
          try {
            webview.WebCookieManager.configCookieSync(url, lineSimple);
          } catch (_e2) {
          }
        }
      } else {
        try {
          webview.WebCookieManager.configCookieSync(url, lineSimple);
        } catch (_e3) {
        }
      }
    }
  }
  try {
    webview.WebCookieManager.saveCookieSync();
  } catch (_e) {
  }
}

/** 与 WebviewController.loadUrl 第二参数元素结构一致 */
export interface FnWebLoadHeader {
  headerKey: string;
  headerValue: string;
}

/** 与探测 long-token、Chrome 移动版一致；通过 setCustomUserAgent / 必要时再用于请求头 */
const FN_WEB_USER_AGENT: string =
  'Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

export function fnWebDefaultUserAgent(): string {
  return FN_WEB_USER_AGENT;
}

/**
 * 与 sample `FnosClient.LOCAL_STORAGE_SECRET_KEY` / 前端一致：仅 Cookie 不够，须写入该键。
 * 值为 Base64(K)，K 为 secret AES 解密后的字节；与本应用持久化的 wsSignKeyB64 相同。
 */
export const FN_WEB_LOCALSTORAGE_SECRET_KEY: string = 'fnos-Secret';

/** 尽早执行：localStorage.setItem('fnos-Secret', secretB64) */
export function fnWebLocalStorageSecretInjectScript(secretB64: string): string {
  const keyLit = JSON.stringify(FN_WEB_LOCALSTORAGE_SECRET_KEY);
  const valLit = JSON.stringify(secretB64);
  return `(function(){try{localStorage.setItem(${keyLit},${valLit});}catch(e){}})();`;
}

/**
 * 仅当必须给 loadUrl 附加头时使用（易引发白屏/卡死，优先用 WebCookieManager + 仅 URL 的 loadUrl）。
 */
export function fnWebLoadHeaders(sessionToken: string, longToken?: string): FnWebLoadHeader[] {
  const out: FnWebLoadHeader[] = [
    { headerKey: 'Cookie', headerValue: buildFnWebCookieHeader(sessionToken, longToken) },
    { headerKey: 'User-Agent', headerValue: FN_WEB_USER_AGENT }
  ];
  return out;
}

/**
 * 页面加载完成后注入 document.cookie（兜底 WebCookieManager 与 H5 读 Cookie 时机不一致）
 * token 经 JSON.stringify 转义，避免引号破坏脚本
 */
export function fnWebDocumentCookieBootstrapScript(sessionToken: string, longToken?: string): string {
  const tLit = JSON.stringify(sessionToken);
  let inner = `(function(){function sc(n,v){var p=';path=/;max-age=5184000;SameSite=Lax';` +
    `if(location.protocol==='https:'){p+=';Secure';}` +
    `document.cookie=n+'='+encodeURIComponent(v)+p;}` +
    `var t=${tLit};sc('fnos-token',t);sc('Trim-MC-token',t);sc('language','zh-CN');` +
    `document.cookie='mode=relay;path=/;max-age=5184000;SameSite=Lax'+(location.protocol==='https:'?';Secure':'');`;
  if (longToken !== undefined && longToken.length > 0) {
    inner += `sc('fnos-long-token',${JSON.stringify(longToken)});`;
  }
  inner += `})();`;
  return `try{${inner}}catch(e){}`;
}
