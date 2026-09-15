import { UIContext } from '@kit.ArkUI';

function toastOpenFailed(uiContext: UIContext): void {
  try {
    uiContext.getPromptAction().showToast({
      message: $r('app.string.privacy_consent_open_failed'),
      duration: 2500
    });
  } catch (_e) {
  }
}

/** 打开隐私政策页。已同意则可查看并返回；未同意时必须重新决断。 */
export function openPrivacyPolicyPage(uiContext: UIContext): void {
  uiContext.getRouter().pushUrl({ url: 'pages/PrivacyPolicy' }).catch((): void => {
    toastOpenFailed(uiContext);
  });
}

export function openCollectedInfoListPage(uiContext: UIContext): void {
  uiContext.getRouter().pushUrl({
    url: 'pages/PrivacyInfoList',
    params: { kind: 'collected' }
  }).catch((): void => {
    toastOpenFailed(uiContext);
  });
}

export function openThirdPartyShareListPage(uiContext: UIContext): void {
  uiContext.getRouter().pushUrl({
    url: 'pages/PrivacyInfoList',
    params: { kind: 'thirdParty' }
  }).catch((): void => {
    toastOpenFailed(uiContext);
  });
}
