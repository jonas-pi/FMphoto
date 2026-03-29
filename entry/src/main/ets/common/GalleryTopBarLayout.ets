/**
 * 图库相关页顶栏：左右列 `layoutWeight(1)` + 中间 `layoutWeight(2)`，保证「返回/取消」与「多选」对称分布。
 * 以下为统一外边距与内控件尺寸（vp），一级/二级页顶栏应对齐使用。
 * 底栏批量区、上传 FAB、首页 chip 等尺寸常量见 `GalleryButtonStyles.ets`；顶栏胶囊配色与字号组合见该文件头注释。
 */
export const GALLERY_TOP_BAR_PAD_LEFT_VP: number = 16;
export const GALLERY_TOP_BAR_PAD_RIGHT_VP: number = 16;
export const GALLERY_TOP_BAR_PAD_TOP_VP: number = 12;
export const GALLERY_TOP_BAR_PAD_BOTTOM_VP: number = 8;

/** 顶栏内按钮行高度，与胶囊按钮高度一致 */
export const GALLERY_TOP_BAR_ROW_HEIGHT_VP: number = 36;
/** 顶栏胶囊按钮字号 */
export const GALLERY_TOP_BAR_BUTTON_FONT_VP: number = 14;
/** 顶栏主标题（如「图库」「媒体分类」） */
export const GALLERY_TOP_BAR_TITLE_FONT_VP: number = 22;
/** 顶栏多选态副标题（如「已选择 n 张」） */
export const GALLERY_TOP_BAR_SUBTITLE_FONT_VP: number = 15;
