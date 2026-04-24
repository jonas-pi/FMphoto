/**
 * FnHttpClient Cookie helpers.
 * Keep request cookie shapes identical to the existing implementation.
 */
export function buildFnApiCookieHeader(token: string, longToken: string = ''): string {
  if (token.length === 0) {
    return longToken.length > 0 ? `fnos-long-token=${longToken}; mode=relay` : 'mode=relay';
  }
  let s = `fnos-token=${token}; language=zh-CN`;
  if (longToken.length > 0) {
    s += `; fnos-long-token=${longToken}`;
  }
  s += `; Trim-MC-token=${token}; mode=relay`;
  return s;
}

/**
 * /upload 专用 Cookie：只保留与官方 Web 一致的三项，
 * 不含 Trim-MC-token 和 mode=relay，防止 nginx 将上传路由到中继服务。
 */
export function buildUploadCookieHeader(token: string, longToken: string = ''): string {
  let s = '';
  if (longToken.length > 0) {
    s = `fnos-long-token=${longToken}`;
  }
  s += (s.length > 0 ? '; ' : '') + 'language=zh-CN';
  if (token.length > 0) {
    s += `; fnos-token=${token}`;
  }
  return s;
}

/**
 * 先合并 WebView 同源 Cookie（可能含仅 H5 下发的键），再剔除上传禁止项。
 * 全精简 Cookie 时部分 NAS 返回 HTTP 403；带 mode=relay / Trim-MC-token 又易 HTTP 400。
 */
export function stripUploadForbiddenCookieKeys(cookie: string): string {
  if (cookie.length === 0) {
    return '';
  }
  const parts = cookie.split(';');
  const kept: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const seg = parts[i].trim();
    if (seg.length === 0) {
      continue;
    }
    const eq = seg.indexOf('=');
    const nameRaw = eq > 0 ? seg.substring(0, eq).trim() : seg;
    const nameLow = nameRaw.toLowerCase();
    if (nameLow === 'mode' || nameLow === 'trim-mc-token') {
      continue;
    }
    kept.push(seg);
  }
  return kept.join('; ');
}


/** 与 fnos_gallery_mobile._GALLERY_TIMELINE_SIGN_PATH / 双路径候选一致 */
