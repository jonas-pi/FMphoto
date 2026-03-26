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

  private static normalize(url: string): string {
    let s = url.trim();
    if (s.endsWith('/')) {
      s = s.slice(0, -1);
    }
    return s;
  }
}
