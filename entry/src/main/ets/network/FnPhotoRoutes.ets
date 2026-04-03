/**
 * 飞牛相册相关路径（与浏览器一致）。
 * 站点根为 `https://IP:5666` 或 `:5667`（端口以登录时填写为准）。
 * 相册 Tab 直接打开站点根下 **`/album`**；照片子应用内另有 `/p/album` 等。
 */

/** 相册 H5（站点根路径，Web Tab 使用） */
export const FN_WEB_ALBUM_ROOT = '/album';

/** 照片 H5 根路径（其下再接 folderview、album 等） */
export const FN_PHOTO_WEB_ENTRY = '/p';

/** 照片 HTTP API 前缀（与 H5 的 `/p/...` 页面不同，仍为 REST） */
export const FN_PHOTO_API_PREFIX = '/p/api/v1';

/** 飞牛新版部分接口（如语义筛选 search/results）在 v2，与 v1 并存 */
export const FN_PHOTO_API_V2_PREFIX = '/p/api/v2';

// —— 照片 H5 子路由（接在 FN_PHOTO_WEB_ENTRY 后，如 `/p` + `/album` => `/p/album`）——

/** 文件夹 */
export const FN_PHOTO_H5_FOLDERVIEW = '/folderview';
/** 相册 */
export const FN_PHOTO_H5_ALBUM = '/album';
/** 人物 */
export const FN_PHOTO_H5_PERSONS = '/persons';
/** 智能分类 */
export const FN_PHOTO_H5_SMART_CATEGORY = '/smart_category';

/** 单条 H5 路由说明（供后续 Tab / Web 跳转使用） */
export interface FnPhotoH5RouteItem {
  path: string;
  label: string;
}

/** 与飞牛照片 Web 侧路由一致，顺序便于做分段导航 */
export const FN_PHOTO_H5_ROUTE_LIST: FnPhotoH5RouteItem[] = [
  { path: FN_PHOTO_H5_FOLDERVIEW, label: '文件夹' },
  { path: FN_PHOTO_H5_ALBUM, label: '相册' },
  { path: FN_PHOTO_H5_PERSONS, label: '人物' },
  { path: FN_PHOTO_H5_SMART_CATEGORY, label: '智能分类' }
];

/**
 * 照片模块完整 H5 路径（不含 host），如 `/p/album`
 * @param subPath 须为 `/album`、`/folderview` 等以 `/` 开头的子路径
 */
export function fnPhotoH5Path(subPath: string): string {
  const sub = subPath.startsWith('/') ? subPath : `/${subPath}`;
  return `${FN_PHOTO_WEB_ENTRY}${sub}`;
}

/** 相册主界面（常用入口，等价于 fnPhotoH5Path(FN_PHOTO_H5_ALBUM)） */
export const FN_PHOTO_H5_ALBUM_PAGE = fnPhotoH5Path(FN_PHOTO_H5_ALBUM);

/**
 * 可交给 Web 加载的完整 URL（base 无尾斜杠，如 https://[host]:5666）
 */
export function fnPhotoH5Url(baseNoSlash: string, subPath: string): string {
  const b = baseNoSlash.endsWith('/') ? baseNoSlash.substring(0, baseNoSlash.length - 1) : baseNoSlash;
  return `${b}${fnPhotoH5Path(subPath)}`;
}

/**
 * 写入 Web Cookie 时需尝试的 path 后缀（含 `/album`、`/p/album`；部分环境仍可能用 `/p/v1`）
 * @param baseNoSlash 如 https://[2409:...]:5666
 */
export function fnPhotoCookieUrls(baseNoSlash: string): string[] {
  const b = baseNoSlash.endsWith('/') ? baseNoSlash.substring(0, baseNoSlash.length - 1) : baseNoSlash;
  const suffixes: string[] = [
    FN_WEB_ALBUM_ROOT,
    `${FN_WEB_ALBUM_ROOT}/`,
    '/p',
    '/p/',
    FN_PHOTO_H5_ALBUM_PAGE,
    `${FN_PHOTO_H5_ALBUM_PAGE}/`,
    '/p/v1',
    '/p/v1/'
  ];
  const out: string[] = [b, `${b}/`];
  for (let i = 0; i < suffixes.length; i++) {
    out.push(`${b}${suffixes[i]}`);
  }
  return out;
}

/** 探测 fnos-long-token 时的 GET 路径顺序（优先根路径相册 `/album`） */
export function fnPhotoLongTokenProbePaths(): string[] {
  return [
    '/',
    FN_WEB_ALBUM_ROOT,
    `${FN_WEB_ALBUM_ROOT}/`,
    FN_PHOTO_H5_ALBUM_PAGE,
    `${FN_PHOTO_H5_ALBUM_PAGE}/`,
    '/p',
    '/p/',
    '/p/v1',
    '/p/v1/'
  ];
}
