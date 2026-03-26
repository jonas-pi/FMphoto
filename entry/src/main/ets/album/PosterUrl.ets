/** 拼接海报/缩略图完整 URL */
export function posterFullUrl(baseUrl: string, poster: string): string {
  const p = poster.trim();
  if (p.length === 0) {
    return '';
  }
  if (p.startsWith('http://') || p.startsWith('https://')) {
    return p;
  }
  const base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  if (p.startsWith('/')) {
    return `${base}${p}`;
  }
  return `${base}/${p}`;
}
