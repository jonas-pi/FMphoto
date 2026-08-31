/**
 * 离中 HdsTabs 胶囊：容器比栏身大一圈，果冻可向外膨胀。
 * 点击走栏身 onTabBarClick，不要再叠一层全尺寸 Row，否则会挡住高光和果冻。
 */
import { DividerMode, hdsEffect, HdsTabs } from '@kit.UIDesignKit';
import {
  FN_HDS_CAPSULE_JELLY_VP,
  fnHdsCapsuleOverlayHeight,
  fnHdsCapsuleOverlayWidth,
  fnHdsDockTabsFloatingStyle
} from './FnUiCommon';

@Component
export struct FnHdsOverlayCapsule {
  @Prop barWidth: number = 54;
  @Prop barHeight: number = 54;
  @Prop text: string = '';
  @Prop symbol: Resource = $r('sys.symbol.play_fill');
  @Prop useSymbol: boolean = false;
  @Prop fontSizeValue: number = 16;
  @Prop fontColorValue: ResourceColor = $r('app.color.icon_primary');
  @Prop enableLongPress: boolean = false;
  onBarClick: () => void = () => {};
  onBarLongPress: () => void = () => {};
  @State private pressShadowType: hdsEffect.PressShadowType = hdsEffect.PressShadowType.NONE;
  private skipNextBarClick: boolean = false;
  private pressActive: boolean = false;
  private longPressTimerId: number = -1;
  private lastLongPressAt: number = 0;

  aboutToDisappear(): void {
    this.pressActive = false;
    this.clearLongPressTimer();
  }

  private overlayWidth(): number {
    return fnHdsCapsuleOverlayWidth(this.barWidth);
  }

  private overlayHeight(): number {
    return fnHdsCapsuleOverlayHeight(this.barHeight);
  }

  private clearLongPressTimer(): void {
    if (this.longPressTimerId < 0) {
      return;
    }
    clearTimeout(this.longPressTimerId);
    this.longPressTimerId = -1;
  }

  private fireLongPress(): void {
    if (!this.enableLongPress) {
      return;
    }
    const now = Date.now();
    if (now - this.lastLongPressAt < 400) {
      return;
    }
    this.lastLongPressAt = now;
    this.skipNextBarClick = true;
    this.onBarLongPress();
  }

  private onPressTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.pressShadowType = hdsEffect.PressShadowType.BLEND_WHITE;
      this.pressActive = true;
      this.clearLongPressTimer();
      if (this.enableLongPress) {
        this.longPressTimerId = setTimeout((): void => {
          this.longPressTimerId = -1;
          if (!this.pressActive) {
            return;
          }
          this.fireLongPress();
        }, 500);
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.pressShadowType = hdsEffect.PressShadowType.NONE;
      this.pressActive = false;
      this.clearLongPressTimer();
    }
  }

  private handleBarClick(): void {
    if (this.skipNextBarClick) {
      this.skipNextBarClick = false;
      return;
    }
    this.onBarClick();
  }

  @Builder
  private chromeBar() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.useSymbol) {
        SymbolGlyph(this.symbol)
          .fontSize(this.fontSizeValue)
          .fontColor([this.fontColorValue])
          .width(this.fontSizeValue)
          .height(this.fontSizeValue)
      } else {
        Text(this.text)
          .fontSize(this.fontSizeValue)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.fontColorValue)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .onTouch((event: TouchEvent): void => {
      this.onPressTouch(event);
    })
    .visualEffect(new hdsEffect.HdsEffectBuilder()
      .pressShadow(this.pressShadowType)
      .buildEffect())
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      HdsTabs({ index: 0 }) {
        TabContent() {
          Column()
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.None)
        }
        .tabBar(this.chromeBar)
      }
      .width(this.overlayWidth())
      .height(this.overlayHeight())
      .barHeight(this.barHeight)
      .barOverlap(true)
      .vertical(false)
      .barPosition(BarPosition.End)
      .barWidth(this.barWidth)
      // @SuppressWarnings compatibility
      .barFloatingStyle(fnHdsDockTabsFloatingStyle(
        this.barWidth,
        FN_HDS_CAPSULE_JELLY_VP,
        FN_HDS_CAPSULE_JELLY_VP
      ))
      .scrollable(false)
      .divider({ mode: DividerMode.NONE })
      .backgroundColor(Color.Transparent)
      .barBackgroundColor(Color.Transparent)
      .clip(false)
      .shadow({ radius: 0, color: Color.Transparent })
      .hitTestBehavior(HitTestMode.Transparent)
      .onContentWillChange((_currentIndex: number, _comingIndex: number): boolean => {
        return false;
      })
      .onTabBarClick((_index: number): void => {
        this.handleBarClick();
      })
    }
    .width(this.overlayWidth())
    .height(this.overlayHeight())
    .clip(false)
    .shadow({ radius: 0, color: Color.Transparent })
    .onTouch((event: TouchEvent): void => {
      this.onPressTouch(event);
    })
    .parallelGesture(
      LongPressGesture({ repeat: false })
        .onAction((): void => {
          this.fireLongPress();
        })
    )
  }
}
