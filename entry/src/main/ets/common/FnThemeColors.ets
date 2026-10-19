import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { window } from '@kit.ArkUI';

const PREF_NAME: string = 'fnos_client_prefs';
const K_FOLLOW_SYSTEM_COLORS: string = 'ui_follow_system_colors';
const K_CUSTOM_PAGE_BG: string = 'ui_custom_page_bg';
const K_CUSTOM_ACCENT: string = 'ui_custom_accent';

export const FN_FOLLOW_SYSTEM_COLORS_KEY: string = 'fnFollowSystemColors';
export const FN_SYS_BACKGROUND_HEX_KEY: string = 'fnSysBackgroundHex';
export const FN_SYS_EMPHASIZE_HEX_KEY: string = 'fnSysEmphasizeHex';
export const FN_CUSTOM_BG_KEY: string = 'fnCustomPageBg';
export const FN_CUSTOM_ACCENT_KEY: string = 'fnCustomAccent';
export const FN_RESOLVED_PAGE_BG_KEY: string = 'fnResolvedPageBg';
export const FN_RESOLVED_ACCENT_KEY: string = 'fnResolvedAccent';
export const FN_RESOLVED_CARD_BG_KEY: string = 'fnResolvedCardBg';

const APP_WINDOW_BG_LIGHT: string = '#FFF4F7FB';
const APP_WINDOW_BG_DARK: string = '#FF000000';
const APP_ACCENT_LIGHT: string = '#FF4A8BFF';
const APP_ACCENT_DARK: string = '#FF7DB0FF';

export const FN_PAGE_BACKGROUND_PRESETS: string[] = [
  '#FFF4F7FB', '#FFD4E4F2', '#FFD3E4E3', '#FFD6E9DC', '#FFE4DFF2',
  '#FFF3E2E6', '#FF1C2430', '#FFFFFFFF', '#FF000000'
];
export const FN_ACCENT_PRESETS: string[] = [
  '#FF4A8BFF', '#FF1C4D8D', '#FF09637E', '#FF26667F', '#FF4E56C0',
  '#FF6155A6', '#FF8FABD4', '#FF7C3AED'
];

/** 一套可一键套用的底色 + 强调色。默认方案两个颜色都留空，表示回到应用自己的浅色/深色。 */
export class FnThemeScheme {
  name: string = '';
  background: string = '';
  accent: string = '';

  constructor(name: string, background: string, accent: string) {
    this.name = name;
    this.background = background;
    this.accent = accent;
  }
}

/**
 * 照片墙的底色用低饱和的偏色灰，色相还在，但不跟照片抢。
 * 做法接近 Material 3 的浅色表面和 Google 相册：大面积压低彩度，强调色只留给选中状态。
 * 晴、海、薄荷、紫、桃仍沿用原来那几套 Color Hunt 的色相，只是把页面收到灰调。
 */
export const FN_THEME_SCHEMES: FnThemeScheme[] = [
  new FnThemeScheme('默认', '', ''),
  new FnThemeScheme('晴', '#FFD4E4F2', '#FF1C4D8D'),
  new FnThemeScheme('海', '#FFD3E4E3', '#FF09637E'),
  new FnThemeScheme('薄荷', '#FFD6E9DC', '#FF26667F'),
  new FnThemeScheme('紫', '#FFE4DFF2', '#FF4E56C0'),
  new FnThemeScheme('桃', '#FFF3E2E6', '#FF6155A6'),
  new FnThemeScheme('夜', '#FF1C2430', '#FF8FABD4')
];

function putStorage<T>(key: string, value: T): void {
  try {
    if (AppStorage.has(key)) {
      AppStorage.set<T>(key, value);
      return;
    }
    AppStorage.setOrCreate<T>(key, value);
  } catch (_e) {
  }
}

export function fnFollowsSystemColors(): boolean {
  const stored = AppStorage.get<boolean>(FN_FOLLOW_SYSTEM_COLORS_KEY);
  return stored !== false;
}

/** 把 #RGB / #RRGGBB / #AARRGGBB 收成 #AARRGGBB。非法输入返回空串。 */
export function fnNormalizeThemeHex(raw: string): string {
  let text = raw.trim().toUpperCase();
  if (text.startsWith('#')) {
    text = text.substring(1);
  }
  if (text.length === 3) {
    text = text.charAt(0) + text.charAt(0) + text.charAt(1) + text.charAt(1) + text.charAt(2) + text.charAt(2);
  }
  if (text.length === 6) {
    text = 'FF' + text;
  }
  if (text.length !== 8) {
    return '';
  }
  for (let i = 0; i < text.length; i++) {
    const c = text.charAt(i);
    const digit = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F');
    if (!digit) {
      return '';
    }
  }
  return '#' + text;
}

/** 浅色返回黑字，深色返回白字。 */
export function fnThemeOnColor(hex: string): string {
  const normalized = fnNormalizeThemeHex(hex);
  if (normalized.length !== 9) {
    return '#FFFFFFFF';
  }
  const r = Number.parseInt(normalized.substring(3, 5), 16);
  const g = Number.parseInt(normalized.substring(5, 7), 16);
  const b = Number.parseInt(normalized.substring(7, 9), 16);
  const luma = (r * 299 + g * 587 + b * 114) / 1000;
  return luma > 160 ? '#FF000000' : '#FFFFFFFF';
}

function fnSysColorHex(ctx: common.Context, resource: Resource): string {
  try {
    const color = ctx.resourceManager.getColorSync(resource.id);
    let hex = (color >>> 0).toString(16);
    while (hex.length < 8) {
      hex = '0' + hex;
    }
    return '#' + hex.toUpperCase();
  } catch (_e) {
    return '';
  }
}

function fnDarkNow(): boolean {
  return AppStorage.get<number>('colorMode') === 1;
}

export function fnResolvedPageBackground(): string {
  const stored = AppStorage.get<string>(FN_RESOLVED_PAGE_BG_KEY);
  if (stored !== undefined && stored.length > 0) {
    return stored;
  }
  return fnDarkNow() ? APP_WINDOW_BG_DARK : APP_WINDOW_BG_LIGHT;
}

export function fnResolvedAccent(): string {
  const stored = AppStorage.get<string>(FN_RESOLVED_ACCENT_KEY);
  if (stored !== undefined && stored.length > 0) {
    return stored;
  }
  return fnDarkNow() ? APP_ACCENT_DARK : APP_ACCENT_LIGHT;
}

/** 按当前来源算出实际底色和强调色，界面通过 StorageProp 跟着刷新。 */
export function fnPublishResolvedThemeColors(): void {
  const dark = fnDarkNow();
  let background = dark ? APP_WINDOW_BG_DARK : APP_WINDOW_BG_LIGHT;
  let accent = dark ? APP_ACCENT_DARK : APP_ACCENT_LIGHT;
  const customBackground = AppStorage.get<string>(FN_CUSTOM_BG_KEY) ?? '';
  const customAccent = AppStorage.get<string>(FN_CUSTOM_ACCENT_KEY) ?? '';
  if (customBackground.length > 0) {
    background = customBackground;
  }
  if (customAccent.length > 0) {
    accent = customAccent;
  }
  putStorage<string>(FN_RESOLVED_PAGE_BG_KEY, background);
  putStorage<string>(FN_RESOLVED_ACCENT_KEY, accent);
  const usingCustom = customBackground.length > 0 || customAccent.length > 0;
  putStorage<string>(FN_RESOLVED_CARD_BG_KEY, usingCustom ? fnCardSurfaceForPage(background, accent) : '');
}

function fnChannel(hex: string, start: number): number {
  return Number.parseInt(hex.substring(start, start + 2), 16);
}

function fnHexByte(value: number): string {
  const clamped = Math.max(0, Math.min(255, Math.round(value)));
  const text = clamped.toString(16).toUpperCase();
  return text.length < 2 ? '0' + text : text;
}

function fnLuma(hex: string): number {
  const normalized = fnNormalizeThemeHex(hex);
  if (normalized.length !== 9) {
    return 255;
  }
  return (fnChannel(normalized, 3) * 299 + fnChannel(normalized, 5) * 587 + fnChannel(normalized, 7) * 114) / 1000;
}

function fnMixTowardWhite(hex: string, whiteAmount: number): string {
  const normalized = fnNormalizeThemeHex(hex);
  if (normalized.length !== 9) {
    return '#FFFFFFFF';
  }
  const keep = 1 - whiteAmount;
  const r = fnChannel(normalized, 3) * keep + 255 * whiteAmount;
  const g = fnChannel(normalized, 5) * keep + 255 * whiteAmount;
  const b = fnChannel(normalized, 7) * keep + 255 * whiteAmount;
  return '#FF' + fnHexByte(r) + fnHexByte(g) + fnHexByte(b);
}

function fnMixColors(base: string, toward: string, towardAmount: number): string {
  const from = fnNormalizeThemeHex(base);
  const to = fnNormalizeThemeHex(toward);
  if (from.length !== 9 || to.length !== 9) {
    return from.length === 9 ? from : '#FFFFFFFF';
  }
  const keep = 1 - towardAmount;
  const r = fnChannel(from, 3) * keep + fnChannel(to, 3) * towardAmount;
  const g = fnChannel(from, 5) * keep + fnChannel(to, 5) * towardAmount;
  const b = fnChannel(from, 7) * keep + fnChannel(to, 7) * towardAmount;
  return '#FF' + fnHexByte(r) + fnHexByte(g) + fnHexByte(b);
}

/**
 * 卡片和页面同一色相，但明暗要差得出来。
 * 浅底把卡片朝白提亮；底色已经近白时，改用强调色把卡片染深一点。
 * 深底把卡片朝白抬亮，避免和页面糊成一块。
 */
export function fnCardSurfaceForPage(page: string, accent: string): string {
  const luma = fnLuma(page);
  if (luma >= 232) {
    const tint = fnNormalizeThemeHex(accent).length === 9 ? accent : '#FF4A8BFF';
    return fnMixColors(page, tint, 0.28);
  }
  if (luma >= 176) {
    return fnMixTowardWhite(page, 0.4);
  }
  return fnMixTowardWhite(page, 0.36);
}

/** 自定义配色时用算出的卡片色，默认配色继续用资源里的白/深灰。 */
export function fnResolvedCardFill(cardBg: string): ResourceColor {
  if (cardBg.length > 0) {
    return cardBg;
  }
  return $r('app.color.card_background');
}

/** 读当前系统页面底色和强调色，供设置页展示。 */
export function fnRefreshSystemColorPreview(ctx: common.Context): void {
  putStorage<string>(FN_SYS_BACKGROUND_HEX_KEY,
    fnSysColorHex(ctx, $r('sys.color.ohos_id_color_background')));
  putStorage<string>(FN_SYS_EMPHASIZE_HEX_KEY,
    fnSysColorHex(ctx, $r('sys.color.ohos_id_color_emphasize')));
  fnPublishResolvedThemeColors();
}

export function fnApplyThemeWindowBackground(mainWindow: window.Window, ctx: common.Context): void {
  fnRefreshSystemColorPreview(ctx);
  try {
    mainWindow.setWindowBackgroundColor(fnResolvedPageBackground());
  } catch (_e) {
  }
}

export async function fnLoadThemeColorPreference(ctx: common.UIAbilityContext): Promise<void> {
  let follow = true;
  let customBackground = '';
  let customAccent = '';
  try {
    const prefs = await preferences.getPreferences(ctx, PREF_NAME);
    const raw = await prefs.get(K_FOLLOW_SYSTEM_COLORS, '1') as string;
    follow = raw !== '0';
    customBackground = await prefs.get(K_CUSTOM_PAGE_BG, '') as string;
    customAccent = await prefs.get(K_CUSTOM_ACCENT, '') as string;
  } catch (_e) {
  }
  putStorage<boolean>(FN_FOLLOW_SYSTEM_COLORS_KEY, follow);
  putStorage<string>(FN_CUSTOM_BG_KEY, fnNormalizeThemeHex(customBackground));
  putStorage<string>(FN_CUSTOM_ACCENT_KEY, fnNormalizeThemeHex(customAccent));
  fnRefreshSystemColorPreview(ctx);
}

export async function fnSaveFollowSystemColors(ctx: common.UIAbilityContext, followSystem: boolean): Promise<void> {
  putStorage<boolean>(FN_FOLLOW_SYSTEM_COLORS_KEY, followSystem);
  fnRefreshSystemColorPreview(ctx);
  try {
    const prefs = await preferences.getPreferences(ctx, PREF_NAME);
    await prefs.put(K_FOLLOW_SYSTEM_COLORS, followSystem ? '1' : '0');
    await prefs.flush();
  } catch (_e) {
  }
}

async function writeCustomThemePrefs(ctx: common.UIAbilityContext, background: string, accent: string): Promise<void> {
  const prefs = await preferences.getPreferences(ctx, PREF_NAME);
  await prefs.put(K_CUSTOM_PAGE_BG, background);
  await prefs.put(K_CUSTOM_ACCENT, accent);
  await prefs.put(K_FOLLOW_SYSTEM_COLORS, '0');
  await prefs.flush();
}

/** 一键套用一整套底色和强调色。空字符串表示回到应用默认。 */
export async function fnSaveThemeScheme(ctx: common.UIAbilityContext, background: string,
  accent: string): Promise<void> {
  const normalizedBackground = background.length === 0 ? '' : fnNormalizeThemeHex(background);
  const normalizedAccent = accent.length === 0 ? '' : fnNormalizeThemeHex(accent);
  putStorage<string>(FN_CUSTOM_BG_KEY, normalizedBackground);
  putStorage<string>(FN_CUSTOM_ACCENT_KEY, normalizedAccent);
  putStorage<boolean>(FN_FOLLOW_SYSTEM_COLORS_KEY, false);
  fnPublishResolvedThemeColors();
  try {
    await writeCustomThemePrefs(ctx, normalizedBackground, normalizedAccent);
  } catch (_e) {
  }
}

/** 保存用户自定的底色或强调色，并改用自定义配色。 */
export async function fnSaveCustomColor(ctx: common.UIAbilityContext, pageBackground: boolean,
  hex: string): Promise<boolean> {
  const normalized = fnNormalizeThemeHex(hex);
  if (normalized.length === 0) {
    return false;
  }
  if (pageBackground) {
    putStorage<string>(FN_CUSTOM_BG_KEY, normalized);
  } else {
    putStorage<string>(FN_CUSTOM_ACCENT_KEY, normalized);
  }
  putStorage<boolean>(FN_FOLLOW_SYSTEM_COLORS_KEY, false);
  fnPublishResolvedThemeColors();
  try {
    const prefs = await preferences.getPreferences(ctx, PREF_NAME);
    await prefs.put(pageBackground ? K_CUSTOM_PAGE_BG : K_CUSTOM_ACCENT, normalized);
    await prefs.put(K_FOLLOW_SYSTEM_COLORS, '0');
    await prefs.flush();
  } catch (_e) {
  }
  return true;
}
