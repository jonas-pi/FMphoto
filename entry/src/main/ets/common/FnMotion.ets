/**
 * 全局动效参数：统一页面转场与交互动效节奏。
 * 后续如需统一提速/减速，只需调整本文件常量。
 */

export const FN_PAGE_ENTER_DURATION = 240;
export const FN_PAGE_EXIT_DURATION = 200;
export const FN_PAGE_ENTER_CURVE = Curve.EaseOut;
export const FN_PAGE_EXIT_CURVE = Curve.EaseIn;

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

export const FN_SWIPER_DURATION = 280;
export const FN_SWIPER_CURVE = Curve.EaseInOut;

export const FN_PREVIEW_PAGE_ENTER_DURATION = 260;
export const FN_PREVIEW_PAGE_EXIT_DURATION = 220;
export const FN_PREVIEW_PAGE_ENTER_CURVE = Curve.EaseOut;
export const FN_PREVIEW_PAGE_EXIT_CURVE = Curve.EaseIn;
