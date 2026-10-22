/**
 * 按站点记录「信任自签证书」的内存策略；持久化由 SessionPreferences 加载/保存
 */
export class CertPolicy {
  private static trusted: Set<string> = new Set();

  /** 与 SessionPreferences 中存储的 baseUrl 一致比较 */
  static isTrusted(baseUrl: string): boolean {
    return CertPolicy.trusted.has(CertPolicy.normalize(baseUrl));
  }

  static addTrusted(baseUrl: string): void {
    CertPolicy.trusted.add(CertPolicy.normalize(baseUrl));
  }

  static removeTrusted(baseUrl: string): void {
    CertPolicy.trusted.delete(CertPolicy.normalize(baseUrl));
  }

  static clear(): void {
    CertPolicy.trusted.clear();
  }

  static loadAll(urls: string[]): void {
    CertPolicy.clear();
    for (let i = 0; i < urls.length; i++) {
      CertPolicy.trusted.add(CertPolicy.normalize(urls[i]));
    }
  }

  static dumpAll(): string[] {
    const out: string[] = [];
    CertPolicy.trusted.forEach((u: string) => {
      out.push(u);
    });
    return out;
  }

  /**
   * 归一化信任键：scheme + 主机（默认端口视同省略）。
   * `https://host` 与 `https://host:443` 必须算同一项，否则登录地址写法不同
   * 就会“丢信任”，进而走不了 IP 直连回退（IPv6 不可用时的兜底）。
   */
  private static normalize(url: string): string {
    let s = url.trim();
    if (s.endsWith('/')) {
      s = s.slice(0, -1);
    }
    const pe = s.indexOf('://');
    if (pe < 0) {
      return s;
    }
    const scheme = s.substring(0, pe + 3).toLowerCase();
    const rest = s.substring(pe + 3);
    const slash = rest.indexOf('/');
    const authority = slash >= 0 ? rest.substring(0, slash) : rest;
    const at = authority.lastIndexOf('@');
    const hostPort = (at >= 0 ? authority.substring(at + 1) : authority).toLowerCase();
    const bracket = hostPort.indexOf(']');
    let host = hostPort;
    let port = '';
    if (bracket >= 0) {
      host = hostPort.substring(0, bracket + 1);
      const after = hostPort.substring(bracket + 1);
      if (after.startsWith(':')) {
        port = after.substring(1);
      }
    } else {
      const colon = hostPort.lastIndexOf(':');
      if (colon > 0) {
        host = hostPort.substring(0, colon);
        port = hostPort.substring(colon + 1);
      }
    }
    const isDefault = (scheme === 'https://' && port === '443') ||
      (scheme === 'http://' && port === '80');
    if (port.length === 0 || isDefault) {
      return `${scheme}${host}`;
    }
    return `${scheme}${host}:${port}`;
  }
}
