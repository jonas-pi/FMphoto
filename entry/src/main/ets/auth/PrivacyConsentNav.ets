import { UIContext } from '@kit.ArkUI';

/** 打开隐私政策页。已同意则可查看并返回；未同意时必须重新决断。 */
export function openPrivacyPolicyPage(uiContext: UIContext): void {
  uiContext.getRouter().pushUrl({ url: 'pages/PrivacyPolicy' }).catch((): void => {
    try {
      uiContext.getPromptAction().showToast({
        message: $r('app.string.privacy_consent_open_failed'),
        duration: 2500
      });
    } catch (_e) {
    }
  });
}
