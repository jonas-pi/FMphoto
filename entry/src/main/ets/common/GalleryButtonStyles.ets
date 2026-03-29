/**
 * 图库系页面共用按钮尺寸与色值常量（vp / 色串）。
 * 顶栏胶囊的推荐链式修饰（与分类页、回收站一致）：
 *   次要：fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP) + height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
 *        + backgroundColor($r('app.color.button_secondary_bg'))
 *        + fontColor($r('app.color.button_secondary_fg'))
 *   主要：将 secondary 换为 button_primary_bg / button_primary_fg
 * 以上字号与行高见 `GalleryTopBarLayout.ets`。
 */

/** 底栏「批量下载 / 删除」等胶囊高度 */
export const GALLERY_BATCH_ACTION_HEIGHT_VP: number = 48;
export const GALLERY_BATCH_BAR_SPACE_VP: number = 10;
export const GALLERY_BATCH_BAR_PAD_LEFT_VP: number = 16;
export const GALLERY_BATCH_BAR_PAD_RIGHT_VP: number = 16;
export const GALLERY_BATCH_BAR_PAD_TOP_VP: number = 8;
export const GALLERY_BATCH_BAR_PAD_BOTTOM_VP: number = 16;
/** 批量删除等危险操作背景 */
export const GALLERY_BATCH_DESTRUCTIVE_BG: string = '#E11D48';

/** 图库首页右下角上传 FAB */
export const GALLERY_HOME_UPLOAD_FAB_SIZE_VP: number = 56;
export const GALLERY_HOME_UPLOAD_FAB_MARGIN_RIGHT_VP: number = 18;
/** 相对原先 88vp 下移一个 FAB 高度（56vp） */
export const GALLERY_HOME_UPLOAD_FAB_MARGIN_BOTTOM_VP: number = 32;

/** 首页「媒体分类 / 智能分类」等横向入口 chip */
export const GALLERY_HOME_NAV_CHIP_HEIGHT_VP: number = 40;
export const GALLERY_HOME_NAV_CHIP_FONT_VP: number = 13;
export const GALLERY_HOME_NAV_CHIP_PAD_H_VP: number = 12;
export const GALLERY_HOME_NAV_CHIP_RADIUS_VP: number = 20;
export const GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_LEFT_VP: number = 16;
export const GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_RIGHT_VP: number = 16;
export const GALLERY_HOME_CATEGORY_ENTRY_ROW_PAD_BOTTOM_VP: number = 8;
