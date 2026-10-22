/**
 * 公网域名 → 解析 A 记录得到同端口 IP baseUrl，供登录时「域名 + 公网 IP」双探测。
 */
import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fnDiagError, fnDiagMaskHost, fnDiagRecord } from '../common/FnDiagLog';
import { isIpLiteralHost, parseNormalizedBaseUrl, replaceBaseUrlHost } from './ServerUrl';

const DOMAIN = 0xFF00;
const TAG = 'PublicDns';

function looksLikeIpv4(addr: string): boolean {
  const parts = addr.split('.');
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

/**
 * 将公网域名 baseUrl 解析为公网 IP baseUrl（同协议/端口）。
 * 已是 IP、或解析失败时返回空串。
 */
export async function resolvePublicDomainToIpBaseUrl(domainBaseUrl: string): Promise<string> {
  const base = domainBaseUrl.trim();
  if (base.length === 0) {
    return '';
  }
  const parts = parseNormalizedBaseUrl(base);
  if (parts === null || parts.host.length === 0) {
    return '';
  }
  if (isIpLiteralHost(parts.host)) {
    return '';
  }
  try {
    const addrs = await connection.getAddressesByName(parts.host);
    let ipv4 = '';
    let ipv6 = '';
    for (let i = 0; i < addrs.length; i++) {
      const ip = addrs[i].address !== undefined ? String(addrs[i].address).trim() : '';
      if (ip.length === 0) {
        continue;
      }
      if (looksLikeIpv4(ip)) {
        ipv4 = ip;
        break;
      }
      if (ipv6.length === 0 && ip.indexOf(':') >= 0) {
        ipv6 = ip;
      }
    }
    const chosen = ipv4.length > 0 ? ipv4 : ipv6;
    if (chosen.length === 0) {
      fnDiagRecord('W', TAG, `dns no usable record host=${fnDiagMaskHost(parts.host)}`);
      return '';
    }
    const rebuilt = replaceBaseUrlHost(base, chosen);
    hilog.info(DOMAIN, TAG, 'dns %{public}s -> %{public}s', fnDiagMaskHost(parts.host), fnDiagMaskHost(chosen));
    return rebuilt;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'dns failed %{public}s', fnDiagMaskHost(parts.host));
    fnDiagError(TAG, `dns failed ${fnDiagMaskHost(parts.host)}`, e);
    return '';
  }
}

function stripIpv6Brackets(ip: string): string {
  let h = ip.trim();
  if (h.startsWith('[')) {
    const close = h.indexOf(']');
    if (close > 1) {
      h = h.substring(1, close);
    }
  }
  return h;
}

function firstGlobalIpv6(addrs: Array<connection.NetAddress>): string {
  for (let i = 0; i < addrs.length; i++) {
    const raw = addrs[i].address !== undefined ? String(addrs[i].address).trim() : '';
    const ip = stripIpv6Brackets(raw);
    if (ip.indexOf(':') < 0 || ip.indexOf('%') >= 0) {
      continue;
    }
    if (ip.toLowerCase().startsWith('fe80:')) {
      continue;
    }
    return ip;
  }
  return '';
}

async function lookupGlobalIpv6(host: string): Promise<string> {
  try {
    const addrs = await connection.getAddressesByName(host);
    return firstGlobalIpv6(addrs);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'dns v6 failed %{public}s', fnDiagMaskHost(host));
    fnDiagError(TAG, `dns v6 failed ${fnDiagMaskHost(host)}`, e);
    return '';
  }
}

/**
 * 域名探测只有 IPv6 走通时，换成同端口的 IPv6 字面量。
 * WebSocket 不能指定地址族，继续用主机名会再次撞上「只有 AAAA 被当成解析失败」。
 */
export async function resolvePublicHostnameToIpv6BaseUrl(domainBaseUrl: string): Promise<string> {
  const base = domainBaseUrl.trim();
  if (base.length === 0) {
    return '';
  }
  const parts = parseNormalizedBaseUrl(base);
  if (parts === null || parts.host.length === 0 || isIpLiteralHost(parts.host)) {
    return '';
  }
  const ipv6 = await lookupGlobalIpv6(parts.host);
  if (ipv6.length === 0) {
    return '';
  }
  const rebuilt = replaceBaseUrlHost(base, ipv6);
  hilog.info(DOMAIN, TAG, 'aaaa %{public}s -> %{public}s', fnDiagMaskHost(parts.host), fnDiagMaskHost(ipv6));
  return rebuilt;
}

/** 公网切换地址：有域名用域名，否则用 IP */
export function preferPublicEndpointUrl(domainUrl: string, ipUrl: string): string {
  const d = domainUrl.trim();
  if (d.length > 0) {
    return d;
  }
  return ipUrl.trim();
}
