/**
 * 公网域名 → 解析 A 记录得到同端口 IP baseUrl，供登录时「域名 + 公网 IP」双探测。
 */
import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
      return '';
    }
    const rebuilt = replaceBaseUrlHost(base, chosen);
    hilog.info(DOMAIN, TAG, 'dns %{public}s -> %{public}s', parts.host, chosen);
    return rebuilt;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'dns failed %{public}s: %{public}s', parts.host, String(e));
    return '';
  }
}

/** 公网切换地址：有域名用域名，否则用 IP */
export function preferPublicEndpointUrl(domainUrl: string, ipUrl: string): string {
  const d = domainUrl.trim();
  if (d.length > 0) {
    return d;
  }
  return ipUrl.trim();
}
