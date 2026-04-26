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

@Component
export struct FnTopBar {
  @Prop title: string = '';
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
        Button(this.backText, { type: ButtonType.Capsule, stateEffect: true })
          .fontSize(GALLERY_TOP_BAR_BUTTON_FONT_VP)
          .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
          .backgroundColor($r('app.color.button_secondary_bg'))
          .fontColor($r('app.color.button_secondary_fg'))
          .borderWidth(1)
          .borderColor($r('app.color.immersive_panel_border'))
          .shadow({ radius: 14, color: '#14001A33', offsetX: 0, offsetY: 6 })
          .onClick((): void => {
            this.getUIContext().getRouter().back();
          })
      }
      .layoutWeight(1)
      .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
      .justifyContent(FlexAlign.Start)

      Text(this.title)
        .layoutWeight(2)
        .fontSize(GALLERY_TOP_BAR_TITLE_FONT_VP)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor($r('app.color.text_primary'))

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
      .height(GALLERY_TOP_BAR_ROW_HEIGHT_VP)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: GALLERY_TOP_BAR_PAD_LEFT_VP,
      right: GALLERY_TOP_BAR_PAD_RIGHT_VP,
      top: GALLERY_TOP_BAR_PAD_TOP_VP + this.systemTopInsetVp,
      bottom: GALLERY_TOP_BAR_PAD_BOTTOM_VP
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
