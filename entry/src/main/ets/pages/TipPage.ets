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
  FN_RESOLVED_ACCENT_KEY,
  FN_RESOLVED_CARD_BG_KEY,
  FN_RESOLVED_PAGE_BG_KEY,
  FN_RESOLVED_TEXT_PRIMARY_KEY,
  FN_RESOLVED_TEXT_SECONDARY_KEY
} from '../common/FnThemeColors';
import {
  fallbackTipOffers,
  loadTipOffers,
  purchaseTip,
  settleUnfinishedTips,
  tipErrorMessage,
  TipOffer
} from '../iap/TipPurchase';

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

  aboutToAppear(): void {
    void this.reload();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
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

  @Builder
  private offerRow(offer: TipOffer) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(offer.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        Text(offer.description)
          .fontSize(12)
          .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.buyingId === offer.productId ? '支付中' : offer.priceLabel)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accent)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(fnResolvedCardFill(this.cardBg))
    .borderRadius($r('app.float.radius_medium'))
    .alignItems(VerticalAlign.Center)
    .opacity(this.buyingId.length > 0 && this.buyingId !== offer.productId ? 0.45 : 1)
    .onClick((): void => {
      void this.onBuy(offer);
    })
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
        Column({ space: 12 }) {
          Text($r('app.string.tip_page_hint'))
            .fontSize(14)
            .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
            .lineHeight(22)
            .width('100%')

          ForEach(this.offers, (offer: TipOffer) => {
            this.offerRow(offer)
          }, (offer: TipOffer): string => offer.productId)
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 12,
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
