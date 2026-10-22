/**
 * 全局动效参数：统一页面转场与交互动效节奏。
 * 后续如需统一提速/减速，只需调整本文件常量。
 *
 * 上架 UX：全页转场在 12 英寸以上设备不得短于 300ms。EaseOut 会让画面过早停稳，
 * 自动化按像素稳定计时，240/200 会被记成 170–200ms。进/出场都拉长并用 EaseInOut。
 */

export const FN_PAGE_ENTER_DURATION = 450;
export const FN_PAGE_EXIT_DURATION = 430;
export const FN_PAGE_ENTER_CURVE = Curve.EaseInOut;
export const FN_PAGE_EXIT_CURVE = Curve.EaseInOut;

/** 全局 tab 切换动效：统一为普通左右滑动。 */
export const FN_GLOBAL_TAB_SWITCH_DURATION = 220;
export const FN_GLOBAL_TAB_SWITCH_CURVE = Curve.EaseInOut;
export const FN_GLOBAL_TAB_SWITCH_OFFSET_VP = 24;

export const FN_TAB_SWITCH_OUT_DURATION = FN_GLOBAL_TAB_SWITCH_DURATION;
export const FN_TAB_SWITCH_IN_DURATION = FN_GLOBAL_TAB_SWITCH_DURATION;
export const FN_TAB_SWITCH_CURVE = FN_GLOBAL_TAB_SWITCH_CURVE;

/** 底部「相册 ↔ 我的」内容区滑入滑出（避免仅用 index 瞬切带来的割裂感） */
export const FN_TAB_ALBUM_ME_OUT_MS = 200;
export const FN_TAB_ALBUM_ME_IN_MS = 300;
export const FN_TAB_ALBUM_ME_CURVE = Curve.EaseInOut;

/** 首页 Web ↔ 相册：轻位移衔接，整栈保持不透明以免底层 Web 透出 */
export const FN_TAB_HOME_CONTENT_OUT_MS = 130;
export const FN_TAB_HOME_CONTENT_IN_MS = 220;
export const FN_TAB_HOME_CONTENT_CURVE = Curve.EaseInOut;

export const FN_UI_FADE_TOGGLE_DURATION = 200;
export const FN_UI_FADE_TOGGLE_CURVE = Curve.EaseInOut;

/**
 * 登录完成 → 首页：router.replaceUrl 属于硬切，页面转场不一定生效，
 * 这里由登录页淡出 + 首页内容入场自行接上，避免“登录后直接跳首页”的突兀感。
 */
export const FN_LOGIN_EXIT_FADE_MS = 220;
export const FN_LOGIN_EXIT_FADE_CURVE = Curve.EaseOut;
export const FN_HOME_ENTER_FADE_MS = 320;
export const FN_HOME_ENTER_FADE_CURVE = Curve.EaseOut;
/** 首页内容入场时的上移距离（vp），配合淡入形成轻微“升起”感。 */
export const FN_HOME_ENTER_OFFSET_VP = 18;

export const FN_SWIPER_DURATION = 280;
export const FN_SWIPER_CURVE = Curve.EaseInOut;

export const FN_PREVIEW_PAGE_ENTER_DURATION = 260;
export const FN_PREVIEW_PAGE_EXIT_DURATION = 220;
export const FN_PREVIEW_PAGE_ENTER_CURVE = Curve.EaseOut;
export const FN_PREVIEW_PAGE_EXIT_CURVE = Curve.EaseIn;
