/**
 * 赞赏页。自愿付款，不解锁功能。收银台由华为应用内支付弹出。
 */
import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { FnHdsSimpleChrome } from '../common/FnHdsSimpleChrome';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import {
  FN_NAV_INDICATOR_INSET_VP_KEY,
  FN_SYSTEM_TOP_INSET_VP_KEY
} from '../common/FnSystemAvoidArea';
import {
  fnResolvedCardFill,
  fnResolvedTextPrimary,
  fnResolvedTextSecondary,
  fnThemeOnColor,
  FN_RESOLVED_ACCENT_KEY,
  FN_RESOLVED_CARD_BG_KEY,
  FN_RESOLVED_PAGE_BG_KEY,
  FN_RESOLVED_TEXT_PRIMARY_KEY,
  FN_RESOLVED_TEXT_SECONDARY_KEY
} from '../common/FnThemeColors';
import { fnLiquidGlassGradient, fnSoftCardGlassGradient } from '../common/FnUiCommon';
import {
  APP_GALLERY_RATE_ALREADY,
  APP_GALLERY_RATE_FAILED,
  APP_GALLERY_RATE_NEED_ID,
  APP_GALLERY_RATE_SHOWN,
  fnShowAppGalleryComment
} from '../common/AppGalleryRate';
import {
  fallbackTipOffers,
  loadTipOffers,
  purchaseTip,
  settleUnfinishedTips,
  TIP_COFFEE,
  TIP_DINNER,
  TIP_LUNCH,
  tipErrorMessage,
  TipOffer
} from '../iap/TipPurchase';

const TIP_CARD_RADIUS_VP: number = 22;

export function openTipPage(uiContext: UIContext): void {
  uiContext.getRouter().pushUrl({ url: 'pages/TipPage' }).catch((): void => {
    try {
      uiContext.getPromptAction().showToast({
        message: '赞赏页打不开',
        duration: 1800
      });
    } catch (_e) {
    }
  });
}

@Entry
@Component
struct TipPage {
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @StorageProp(FN_RESOLVED_TEXT_SECONDARY_KEY) private themeTextSecondary: string = '';
  @StorageProp(FN_RESOLVED_PAGE_BG_KEY) private pageBg: string = '#FFF4F7FB';
  @StorageProp(FN_RESOLVED_CARD_BG_KEY) private cardBg: string = '';
  @StorageProp(FN_RESOLVED_ACCENT_KEY) private accent: string = '#FF4A8BFF';
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(FN_NAV_INDICATOR_INSET_VP_KEY) private navIndicatorInsetVp: number = 0;
  @State private offers: TipOffer[] = fallbackTipOffers();
  @State private buyingId: string = '';
  @State private pressedId: string = '';
  @State private rateOpening: boolean = false;
  private rateLabelTimer: number = -1;

  aboutToAppear(): void {
    void this.reload();
  }

  aboutToDisappear(): void {
    if (this.rateLabelTimer >= 0) {
      clearTimeout(this.rateLabelTimer);
      this.rateLabelTimer = -1;
    }
  }

  private holdRateLabel(startedAt: number): void {
    const wait = 1200 - (Date.now() - startedAt);
    if (wait <= 0) {
      this.rateOpening = false;
      return;
    }
    this.rateLabelTimer = setTimeout((): void => {
      this.rateLabelTimer = -1;
      this.rateOpening = false;
    }, wait);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 先把提示画出来，再去拉评分窗。评分窗的连接会占住界面线程。 */
  private letToastShow(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => {
        resolve();
      }, 50);
    });
  }

  private async openRate(): Promise<void> {
    if (this.rateOpening) {
      this.toast('正在打开评分');
      return;
    }
    this.rateOpening = true;
    this.toast('正在打开评分');
    await this.letToastShow();
    const startedAt = Date.now();
    try {
      const result = await fnShowAppGalleryComment(this.hostContext());
      const elapsed = Date.now() - startedAt;
      if (result.kind === APP_GALLERY_RATE_SHOWN) {
        if (elapsed < 800) {
          this.toast('评分窗口没有留住');
        }
        return;
      }
      if (result.kind === APP_GALLERY_RATE_ALREADY) {
        this.toast('这个版本已经评过了');
        return;
      }
      if (result.kind === APP_GALLERY_RATE_NEED_ID) {
        this.toastResource($r('app.string.rate_app_need_huawei_id'));
        return;
      }
      const detail = result.detail.length > 0 ? result.detail : '暂时无法打开评分';
      this.toast(detail);
    } catch (_e) {
      this.toast('评分没有打开');
    } finally {
      this.holdRateLabel(startedAt);
    }
  }

  private toastResource(message: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800
      });
    } catch (_e) {
    }
  }

  private toast(message: string): void {
    if (message.length === 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200
      });
    } catch (_e) {
    }
  }

  private async reload(): Promise<void> {
    const ctx = this.hostContext();
    try {
      await settleUnfinishedTips(ctx);
    } catch (_e) {
    }
    try {
      this.offers = await loadTipOffers(ctx);
    } catch (_e) {
      this.offers = fallbackTipOffers();
    }
  }

  private async onBuy(offer: TipOffer): Promise<void> {
    if (this.buyingId.length > 0) {
      return;
    }
    this.buyingId = offer.productId;
    try {
      await purchaseTip(this.hostContext(), offer.productId);
      this.toast('谢谢，已收到赞赏');
    } catch (err) {
      this.toast(tipErrorMessage(err as Object));
    } finally {
      this.buyingId = '';
    }
  }

  private accentWash(alphaHex: string): string {
    const raw = this.accent.trim();
    if (raw.length === 9 && raw.charAt(0) === '#') {
      return '#' + alphaHex + raw.substring(3);
    }
    return '#334A8BFF';
  }

  private priceInk(): string {
    return fnThemeOnColor(this.accent);
  }

  private detailOf(offer: TipOffer): string {
    const text = offer.description.trim();
    if (text.length === 0 || text === '自愿赞赏，不解锁功能') {
      return '';
    }
    return text;
  }

  private cardGlass(): LinearGradientOptions {
    if (this.cardBg.length > 0) {
      return fnSoftCardGlassGradient();
    }
    return fnLiquidGlassGradient();
  }

  @Builder
  private offerGlyph(productId: string) {
    if (productId === TIP_COFFEE) {
      SymbolGlyph($r('sys.symbol.cup_fill'))
        .fontSize(22)
        .fontColor([this.accent])
    } else if (productId === TIP_LUNCH) {
      SymbolGlyph($r('sys.symbol.fork_knife'))
        .fontSize(22)
        .fontColor([this.accent])
    } else if (productId === TIP_DINNER) {
      SymbolGlyph($r('sys.symbol.moon_fill'))
        .fontSize(22)
        .fontColor([this.accent])
    } else {
      SymbolGlyph($r('sys.symbol.heart_fill'))
        .fontSize(22)
        .fontColor([this.accent])
    }
  }

  @Builder
  private pricePill(offer: TipOffer) {
    Row({ space: 6 }) {
      if (this.buyingId === offer.productId) {
        LoadingProgress()
          .width(16)
          .height(16)
          .color(this.priceInk())
        Text($r('app.string.tip_paying'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.priceInk())
      } else {
        Text(offer.priceLabel)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.priceInk())
      }
    }
    .constraintSize({ minWidth: 84, minHeight: 36 })
    .padding({ left: 14, right: 14 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.accent)
    .borderRadius(18)
  }

  @Builder
  private offerRow(offer: TipOffer) {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(44)
          .height(44)
          .borderRadius(22)
          .backgroundColor(this.accentWash('24'))
        this.offerGlyph(offer.productId)
      }
      .width(44)
      .height(44)

      Column({ space: 4 }) {
        Text(offer.name)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        if (this.detailOf(offer).length > 0) {
          Text(this.detailOf(offer))
            .fontSize(12)
            .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.pricePill(offer)
    }
    .width('100%')
    .padding({ left: 16, right: 14, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.pressedId === offer.productId ? this.accentWash('14') : '#00000000')
    .opacity(this.buyingId.length > 0 && this.buyingId !== offer.productId ? 0.4 : 1)
    .animation({ duration: 160, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent): void => {
      if (this.buyingId.length > 0) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.pressedId = offer.productId;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedId = '';
      }
    })
    .onClick((): void => {
      void this.onBuy(offer);
    })
  }

  @Builder
  private offerBlock(offer: TipOffer, index: number) {
    Column() {
      if (index > 0) {
        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.immersive_panel_border'))
          .margin({ left: 74 })
      }
      this.offerRow(offer)
    }
    .width('100%')
  }

  build() {
    Column() {
      FnHdsSimpleChrome({
        title: '赞赏',
        showBack: true,
        topSafeInsetVp: this.systemTopInsetVp,
        onBack: (): void => {
          this.getUIContext().getRouter().back();
        }
      })

      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 10 }) {
            Stack({ alignContent: Alignment.Center }) {
              Column()
                .width(72)
                .height(72)
                .borderRadius(36)
                .backgroundColor(this.accentWash('22'))
              SymbolGlyph($r('sys.symbol.heart_fill'))
                .fontSize(32)
                .fontColor([this.accent])
            }
            .width(72)
            .height(72)
            .margin({ top: 8 })

            Text($r('app.string.tip_hero_title'))
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
              .textAlign(TextAlign.Center)

            Text($r('app.string.tip_hero_body'))
              .fontSize(14)
              .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
              .textAlign(TextAlign.Center)
              .lineHeight(24)
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 12, right: 12 })

          Column() {
            ForEach(this.offers, (offer: TipOffer, index: number) => {
              this.offerBlock(offer, index)
            }, (offer: TipOffer): string => offer.productId)
          }
          .width('100%')
          .backgroundColor(fnResolvedCardFill(this.cardBg))
          .backgroundBlurStyle(this.cardBg.length > 0 ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THICK)
          .linearGradient(this.cardGlass())
          .borderRadius(TIP_CARD_RADIUS_VP)
          .borderWidth(1)
          .borderColor($r('app.color.immersive_panel_border'))
          .clip(true)

          Text($r('app.string.tip_page_hint'))
            .fontSize(12)
            .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
            .lineHeight(18)
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ left: 12, right: 12 })

          Blank()
            .layoutWeight(1)

          Button({ type: ButtonType.Normal, stateEffect: false }) {
            Text(this.rateOpening ? '正在打开评分…' : '或者，给个好评吧！')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accent)
          }
          .width('100%')
          .height(44)
          .backgroundColor(Color.Transparent)
          .opacity(this.rateOpening ? 0.45 : 1)
          .onClick((): void => {
            void this.openRate();
          })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 24 + this.navIndicatorInsetVp
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 0, y: 28 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: 0, y: -16 });
  }
}
