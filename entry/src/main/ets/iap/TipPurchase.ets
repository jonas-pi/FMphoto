/**
 * 赞赏：三档消耗型商品。付款走华为应用内支付，不解锁功能。
 * 支付成功后立刻 finishPurchase，同一档才能再次购买。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { iap } from '@kit.IAPKit';

export class TipOffer {
  productId: string = '';
  name: string = '';
  description: string = '';
  priceLabel: string = '';
}

export const TIP_COFFEE: string = 'tip_coffee';
export const TIP_LUNCH: string = 'tip_lunch';
export const TIP_DINNER: string = 'tip_dinner';

export function fallbackTipOffers(): TipOffer[] {
  const coffee = new TipOffer();
  coffee.productId = TIP_COFFEE;
  coffee.name = '请喝杯咖啡';
  coffee.description = '自愿赞赏，不解锁功能';
  coffee.priceLabel = '¥6.00';
  const lunch = new TipOffer();
  lunch.productId = TIP_LUNCH;
  lunch.name = '请吃顿午饭';
  lunch.description = '自愿赞赏，不解锁功能';
  lunch.priceLabel = '¥18.00';
  const dinner = new TipOffer();
  dinner.productId = TIP_DINNER;
  dinner.name = '请吃顿晚饭';
  dinner.description = '自愿赞赏，不解锁功能';
  dinner.priceLabel = '¥30.00';
  const offers: TipOffer[] = [];
  offers.push(coffee);
  offers.push(lunch);
  offers.push(dinner);
  return offers;
}

function offerRank(productId: string): number {
  if (productId === TIP_COFFEE) {
    return 0;
  }
  if (productId === TIP_LUNCH) {
    return 1;
  }
  if (productId === TIP_DINNER) {
    return 2;
  }
  return 9;
}

function priceLabelOf(product: iap.Product, fallback: string): string {
  const local = product.localPrice !== undefined ? product.localPrice : '';
  if (local.length > 0) {
    return local;
  }
  if (product.originalLocalPrice.length > 0) {
    return product.originalLocalPrice;
  }
  return fallback;
}

export async function loadTipOffers(ctx: common.UIAbilityContext): Promise<TipOffer[]> {
  const fallback = fallbackTipOffers();
  const param: iap.QueryProductsParameter = {
    productType: iap.ProductType.CONSUMABLE,
    productIds: [TIP_COFFEE, TIP_LUNCH, TIP_DINNER]
  };
  const products = await iap.queryProducts(ctx, param);
  if (products.length === 0) {
    return fallback;
  }
  const merged: TipOffer[] = [];
  for (let i = 0; i < fallback.length; i++) {
    const base = fallback[i];
    let found: iap.Product | undefined = undefined;
    for (let j = 0; j < products.length; j++) {
      if (products[j].id === base.productId) {
        found = products[j];
        break;
      }
    }
    const offer = new TipOffer();
    offer.productId = base.productId;
    offer.name = found !== undefined && found.name.length > 0 ? found.name : base.name;
    offer.description = found !== undefined && found.description.length > 0 ? found.description : base.description;
    offer.priceLabel = found !== undefined ? priceLabelOf(found, base.priceLabel) : base.priceLabel;
    merged.push(offer);
  }
  merged.sort((a: TipOffer, b: TipOffer): number => offerRank(a.productId) - offerRank(b.productId));
  return merged;
}

function readStringField(parsed: Record<string, string | number | Object | undefined>, key: string): string {
  const value = parsed[key];
  if (typeof value === 'string') {
    return value;
  }
  return '';
}

async function finishPayload(ctx: common.UIAbilityContext, raw: string): Promise<void> {
  const parsed = JSON.parse(raw) as Record<string, string | number | Object | undefined>;
  const token = readStringField(parsed, 'purchaseToken');
  const orderId = readStringField(parsed, 'purchaseOrderId');
  if (token.length === 0 || orderId.length === 0) {
    throw new Error('missing purchase token');
  }
  const finish: iap.FinishPurchaseParameter = {
    productType: iap.ProductType.CONSUMABLE,
    purchaseToken: token,
    purchaseOrderId: orderId
  };
  await iap.finishPurchase(ctx, finish);
}

/** 把上次付完但没消耗的订单消耗掉，避免同一档无法再买。 */
export async function settleUnfinishedTips(ctx: common.UIAbilityContext): Promise<void> {
  const query: iap.QueryPurchasesParameter = {
    productType: iap.ProductType.CONSUMABLE,
    queryType: iap.PurchaseQueryType.UNFINISHED
  };
  const result = await iap.queryPurchases(ctx, query);
  for (let i = 0; i < result.purchaseDataList.length; i++) {
    await finishPayload(ctx, result.purchaseDataList[i]);
  }
}

export async function purchaseTip(ctx: common.UIAbilityContext, productId: string): Promise<void> {
  const param: iap.PurchaseParameter = {
    productId: productId,
    productType: iap.ProductType.CONSUMABLE
  };
  const created = await iap.createPurchase(ctx, param);
  await finishPayload(ctx, created.purchaseData);
}

export function tipErrorMessage(err: Object): string {
  const be = err as BusinessError;
  if (be.code === iap.IAPErrorCode.USER_CANCELED) {
    return '';
  }
  if (be.code === iap.IAPErrorCode.ACCOUNT_NOT_LOGGED_IN) {
    return '请先登录华为账号';
  }
  if (be.code === iap.IAPErrorCode.INVALID_PRODUCT) {
    return '商品还不可购买。草稿需先激活，调试账号需加入沙盒测试';
  }
  if (be.code === iap.IAPErrorCode.APP_NOT_AUTHORIZED) {
    return '应用还没有支付授权';
  }
  if (be.code === iap.IAPErrorCode.NETWORK_ERROR) {
    return '网络异常，请稍后再试';
  }
  if (be.code === iap.IAPErrorCode.PRODUCT_OWNED) {
    return '上一笔还没消耗完，请重新打开本页后再试';
  }
  const msg = be.message !== undefined ? be.message : '';
  return msg.length > 0 ? msg : '暂时无法完成赞赏';
}
