/**
 * 通用 UI 组件。
 * - FnTopBar: 统一子页面顶栏，与图库首页 1-2-1 布局和 36vp 按钮对齐
 * - FnPrimaryButton/FnSecondaryButton: 统一主次按钮样式
 * - FnFullLoadingMask: 统一全屏阻断式加载遮罩
 */

import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

import {
  GALLERY_TOP_BAR_BUTTON_FONT_VP,
  GALLERY_TOP_BAR_PAD_BOTTOM_VP,
  GALLERY_TOP_BAR_PAD_LEFT_VP,
  GALLERY_TOP_BAR_PAD_RIGHT_VP,
  GALLERY_TOP_BAR_PAD_TOP_VP,
  GALLERY_TOP_BAR_ROW_HEIGHT_VP,
  GALLERY_TOP_BAR_TITLE_FONT_VP
} from './GalleryTopBarLayout';

export const FN_FLOATING_TOP_MARGIN_VP: number = 8;
export const FN_FLOATING_TOP_BOTTOM_GAP_VP: number = 6;
export const FN_FLOATING_TOP_CONTROL_SIZE_VP: number = 40;
export const FN_FLOATING_TOP_CONTROL_RADIUS_VP: number = FN_FLOATING_TOP_CONTROL_SIZE_VP / 2;
export const FN_FLOATING_TOP_PILL_MIN_WIDTH_VP: number = 62;
export const FN_FLOATING_TOP_META_FONT_VP: number = 11;
export const FN_FLOATING_TOP_TITLE_STACK_GAP_VP: number = 1;
export const FN_FLOATING_TOP_TOTAL_HEIGHT_VP: number =
  FN_FLOATING_TOP_MARGIN_VP + FN_FLOATING_TOP_CONTROL_SIZE_VP + FN_FLOATING_TOP_BOTTOM_GAP_VP;
export const FN_BOTTOM_DOCK_SIDE_PADDING_VP: number = 14;
export const FN_BOTTOM_DOCK_SIDE_GAP_VP: number = 10;
export const FN_BOTTOM_DOCK_SIDE_BUTTON_SIZE_VP: number = 54;
export const FN_BOTTOM_DOCK_CENTER_HEIGHT_VP: number = 54;
export const FN_BOTTOM_DOCK_CENTER_RADIUS_VP: number = 27;
export const FN_BOTTOM_DOCK_ITEM_RADIUS_VP: number = 16;
export const FN_BOTTOM_DOCK_ICON_SIZE_VP: number = 19;
export const FN_BOTTOM_DOCK_LABEL_SIZE_VP: number = 11;
export const FN_BOTTOM_DOCK_INNER_PADDING_H_VP: number = 5;
export const FN_BOTTOM_DOCK_INNER_SPACE_VP: number = 6;
export const FN_BOTTOM_DOCK_ITEM_HEIGHT_VP: number = FN_BOTTOM_DOCK_CENTER_HEIGHT_VP - 8;
export const FN_BOTTOM_DOCK_BASE_GAP_VP: number = 16;

export function fnBottomDockBottomGap(bottomSafeInsetVp: number): number {
  const liftedGap = FN_BOTTOM_DOCK_BASE_GAP_VP + (FN_BOTTOM_DOCK_CENTER_HEIGHT_VP / 4);
  return Math.max(liftedGap, bottomSafeInsetVp + liftedGap);
}

@Component
export struct FnFloatingTopPillButton {
  @Prop text: ResourceStr = '';
  @Prop prominent: boolean = false;
  action: () => void = () => {};

  build() {
    Button(this.text, { type: ButtonType.Capsule, stateEffect: true })
      .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
      .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
      .constraintSize({ minWidth: FN_FLOATING_TOP_PILL_MIN_WIDTH_VP })
      .backgroundColor(this.prominent ? $r('app.color.button_primary_bg') : $r('app.color.gallery_material_surface_bg'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
      .fontColor(this.prominent ? $r('app.color.button_primary_fg') : $r('app.color.button_secondary_fg'))
      .border({ width: 1, color: $r('app.color.immersive_panel_border') })
      .shadow({
        radius: this.prominent ? 18 : 14,
        color: this.prominent ? '#334A8BFF' : '#14001A33',
        offsetX: 0,
        offsetY: this.prominent ? 8 : 6
      })
      .onClick(this.action)
  }
}

@Component
export struct FnFloatingTopCircleButton {
  @Prop symbol: Resource = $r('sys.symbol.more');
  @Prop active: boolean = false;
  @Prop fontColor: ResourceColor = $r('app.color.icon_primary');
  @Prop activeBg: ResourceColor = $r('app.color.brand_primary');
  action: () => void = () => {};

  build() {
    Button({ type: ButtonType.Circle, stateEffect: true }) {
      SymbolGlyph(this.symbol)
        .fontSize(17)
        .fontColor([this.active ? Color.White : this.fontColor])
    }
    .width(FN_FLOATING_TOP_CONTROL_SIZE_VP)
    .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
    .borderRadius(FN_FLOATING_TOP_CONTROL_RADIUS_VP)
    .backgroundColor(this.active ? this.activeBg : $r('app.color.gallery_material_surface_bg'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
    .border({ width: 1, color: $r('app.color.immersive_panel_border') })
    .shadow({ radius: 14, color: '#14001A33', offsetX: 0, offsetY: 6 })
    .padding(0)
    .clip(true)
    .onClick(this.action)
  }
}

@Component
export struct FnTopBar {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop backText: string = '返回';
  @Prop rightText: string = '';
  @State private systemTopInsetVp: number = 0;

  private pxToVp(value: number): number {
    try {
      return this.getUIContext().px2vp(value);
    } catch (_e) {
      return value;
    }
  }

  private syncSystemTopInset(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win): void => {
        try {
          const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
          this.systemTopInsetVp = Math.max(0, this.pxToVp(area.topRect.height));
        } catch (_e) {
          this.systemTopInsetVp = 0;
        }
      }).catch((_e: Error): void => {
        this.systemTopInsetVp = 0;
      });
    } catch (_e) {
      this.systemTopInsetVp = 0;
    }
  }

  aboutToAppear(): void {
    this.syncSystemTopInset();
  }

  build() {
    Row() {
      Row() {
        FnFloatingTopPillButton({
          text: this.backText,
          action: (): void => {
            this.getUIContext().getRouter().back();
          }
        })
      }
      .layoutWeight(1)
      .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
      .justifyContent(FlexAlign.Start)

      Column({ space: FN_FLOATING_TOP_TITLE_STACK_GAP_VP }) {
        Text(this.title)
          .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
          .fontWeight(FontWeight.Bold)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.text_primary'))

        Text(this.subtitle.length > 0 ? this.subtitle : ' ')
          .fontSize(FN_FLOATING_TOP_META_FONT_VP)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor($r('app.color.text_secondary'))
          .opacity(this.subtitle.length > 0 ? 1 : 0)
      }
        .layoutWeight(2)
        .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

      Row() {
        if (this.rightText.length > 0) {
          Text(this.rightText)
            .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(FN_FLOATING_TOP_CONTROL_SIZE_VP)
    .alignItems(VerticalAlign.Center)
    .padding({ left: GALLERY_TOP_BAR_PAD_LEFT_VP, right: GALLERY_TOP_BAR_PAD_RIGHT_VP })
    .margin({
      top: this.systemTopInsetVp + FN_FLOATING_TOP_MARGIN_VP,
      bottom: FN_FLOATING_TOP_BOTTOM_GAP_VP
    })
  }
}

@Component
export struct FnPrimaryButton {
  @Prop text: ResourceStr = '';

  build() {
    Button(this.text)
      .height($r('app.float.button_height'))
      .fontColor($r('app.color.button_primary_fg'))
      .backgroundColor($r('app.color.button_primary_bg'))
      .borderRadius($r('app.float.radius_medium'))
      .shadow({ radius: 18, color: '#334A8BFF', offsetX: 0, offsetY: 8 })
  }
}

@Component
export struct FnSecondaryButton {
  @Prop text: ResourceStr = '';

  build() {
    Button(this.text)
      .height($r('app.float.button_height'))
      .backgroundColor($r('app.color.button_secondary_bg'))
      .fontColor($r('app.color.button_secondary_fg'))
      .borderRadius($r('app.float.radius_medium'))
      .borderWidth(1)
      .borderColor($r('app.color.immersive_panel_border'))
      .shadow({ radius: 14, color: '#14001A33', offsetX: 0, offsetY: 6 })
  }
}

@Component
export struct FnImmersiveBackdrop {
  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.page_background'))

      Column() {
        Row() {
          Column()
            .width(240)
            .height(240)
            .borderRadius(120)
            .backgroundColor($r('app.color.immersive_glow_primary'))
            .opacity(0.55)
            .shadow({ radius: 70, color: $r('app.color.immersive_glow_primary'), offsetX: 0, offsetY: 0 })

          Row()
            .layoutWeight(1)

          Column()
            .width(180)
            .height(180)
            .borderRadius(90)
            .backgroundColor($r('app.color.immersive_glow_secondary'))
            .opacity(0.42)
            .shadow({ radius: 56, color: $r('app.color.immersive_glow_secondary'), offsetX: 0, offsetY: 0 })
        }
        .width('100%')
        .padding({ left: 24, right: 12, top: 18 })

        Row()
          .layoutWeight(1)

        Row() {
          Row()
            .layoutWeight(1)

          Column()
            .width(220)
            .height(220)
            .borderRadius(110)
            .backgroundColor($r('app.color.immersive_glow_tertiary'))
            .opacity(0.34)
            .shadow({ radius: 64, color: $r('app.color.immersive_glow_tertiary'), offsetX: 0, offsetY: 0 })
        }
        .width('100%')
        .padding({ right: 18, bottom: 72 })
      }
      .width('100%')
      .height('100%')

      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.immersive_halo_soft'))
        .opacity(0.78)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}

@Component
export struct FnFullLoadingMask {
  @Prop text: string = '加载中...';

  build() {
    Column({ space: 10 }) {
      LoadingProgress().width(48).height(48).color(Color.White)
      Text(this.text).fontSize(14).fontColor(Color.White)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor($r('app.color.overlay_mask'))
    .hitTestBehavior(HitTestMode.Block)
  }
}

@Component
export struct FnInlineLoading {
  @Prop text: string = '加载中...';

  build() {
    Row({ space: 10 }) {
      LoadingProgress().width(28).height(28)
      Text(this.text).fontSize(14).fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }
}

@Component
export struct FnStateText {
  @Prop text: string = '';
  @Prop isError: boolean = false;

  build() {
    Text(this.text)
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 24, right: 24, top: 40 })
      .textAlign(TextAlign.Center)
      .fontSize(14)
      .fontColor(this.isError ? '#FFE0483E' : $r('app.color.text_secondary'))
  }
}
