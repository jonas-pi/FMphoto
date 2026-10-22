/**
 * 反馈：内嵌飞书表单，由用户自己填写并上传截图。
 * 诊断日志只写在本机。点表单上传时先选图片或这份日志。
 */
import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { webview } from '@kit.ArkWeb';
import { UIContext } from '@kit.ArkUI';
import { fnDiagPreparePhoneFile, fnDiagRecord, fnDiagShare } from '../common/FnDiagLog';
import { FN_FEEDBACK_FORM_URL } from '../common/FnFeedbackForm';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';
import {
  FN_NAV_INDICATOR_INSET_VP_KEY,
  FN_SYSTEM_BOTTOM_INSET_VP_KEY,
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

const LOG_FILE_NAME: string = 'fmphoto-diag.txt';
const FORM_LOAD_FAIL: string = '表单打不开，请检查网络后再试';
/** 导出的诊断日志包含哪几段，告诉用户上传的是什么。 */
const LOG_SECTIONS_HINT: string = '日志内含错误摘要、关键状态、网络环境、崩溃记录与会话记录几段。';

export function openFeedbackPage(uiContext: UIContext): void {
  uiContext.getRouter().pushUrl({ url: 'pages/FeedbackPage' }).catch((): void => {
    try {
      uiContext.getPromptAction().showToast({
        message: '反馈页打不开',
        duration: 1800
      });
    } catch (_e) {
    }
  });
}

@Entry
@Component
struct FeedbackPage {
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @StorageProp(FN_RESOLVED_TEXT_SECONDARY_KEY) private themeTextSecondary: string = '';
  @StorageProp(FN_RESOLVED_PAGE_BG_KEY) private pageBg: string = '#FFF4F7FB';
  @StorageProp(FN_RESOLVED_CARD_BG_KEY) private cardBg: string = '';
  @StorageProp(FN_RESOLVED_ACCENT_KEY) private accent: string = '#FF4A8BFF';
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(FN_NAV_INDICATOR_INSET_VP_KEY) private navIndicatorInsetVp: number = 0;
  @StorageProp(FN_SYSTEM_BOTTOM_INSET_VP_KEY) private systemBottomInsetVp: number = 0;
  @State private logHint: string = '正在把诊断日志保存到设备…';
  @State private logReady: boolean = false;
  @State private formError: string = '';
  @State private webLoading: boolean = false;
  private webController: webview.WebviewController = new webview.WebviewController();
  private logPath: string = '';
  private picking: boolean = false;
  private preparing: boolean = false;
  private sharing: boolean = false;

  aboutToAppear(): void {
    void this.prepareLog();
  }

  private formUrl(): string {
    return FN_FEEDBACK_FORM_URL.trim();
  }

  private paintWebBackground(): void {
    try {
      this.webController.runJavaScript(
        "document.documentElement.style.background='#fff';if(document.body){document.body.style.background='#fff';}"
      ).catch((): void => {
      });
    } catch (_e) {
    }
  }

  private async prepareLog(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let path: string = '';
    try {
      path = await fnDiagPreparePhoneFile(ctx);
    } catch (e) {
      fnDiagRecord('E', 'Feedback', `prepare log failed ${String(e)}`);
      this.logPath = '';
      this.logReady = false;
      this.logHint = '诊断日志没能保存到设备，请返回后重试';
      return;
    }
    if (path.length === 0) {
      fnDiagRecord('E', 'Feedback', 'prepare log failed: empty path');
      this.logPath = '';
      this.logReady = false;
      this.logHint = '诊断日志没能保存到设备，请返回后重试';
      return;
    }
    fnDiagRecord('I', 'Feedback', 'prepare log ok');
    this.logPath = path;
    this.logReady = true;
    this.logHint = `诊断日志已在设备里：${LOG_FILE_NAME}。点表单的上传后，选「图片」或「诊断日志」。${LOG_SECTIONS_HINT}`;
  }

  private goBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (_e) {
    }
  }

  /** 复现问题后重新生成，保证附件里是最新的一次会话记录。 */
  private regenerateLog(): void {
    if (this.preparing) {
      return;
    }
    this.preparing = true;
    this.logReady = false;
    this.logHint = '正在重新生成诊断日志…';
    void this.prepareLog().finally((): void => {
      this.preparing = false;
    });
  }

  /** 直接把诊断日志分享出去（不用经过表单附件选择）。 */
  private shareLog(): void {
    if (this.sharing) {
      return;
    }
    this.sharing = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    void fnDiagShare(ctx).then((ok: boolean): void => {
      this.sharing = false;
      if (!ok) {
        fnDiagRecord('E', 'Feedback', 'share log failed');
        this.logHint = '诊断日志分享失败，请改用表单附件上传';
      }
    }).catch((e: Error): void => {
      this.sharing = false;
      fnDiagRecord('E', 'Feedback', `share log error ${String(e)}`);
      this.logHint = '诊断日志分享失败，请改用表单附件上传';
    });
  }

  private acceptLooksLikeImage(types: Array<string>): boolean {
    let sawImage = false;
    for (let i = 0; i < types.length; i++) {
      const item = types[i].toLowerCase();
      if (item.indexOf('*/*') >= 0 || item === '*') {
        return false;
      }
      if (item.indexOf('image') >= 0) {
        sawImage = true;
      }
    }
    return sawImage;
  }

  private async deliverLog(result: FileSelectorResult): Promise<void> {
    if (this.logPath.length === 0) {
      fnDiagRecord('W', 'Feedback', 'log not ready');
      result.handleFileList([]);
      this.logHint = '诊断日志还没保存好，请稍后再点附件';
      return;
    }
    const uri = fileUri.getUriFromPath(this.logPath);
    result.handleFileList([uri]);
  }

  private async deliverImages(result: FileSelectorResult, multiple: boolean): Promise<void> {
    try {
      const opt = new photoAccessHelper.PhotoSelectOptions();
      opt.maxSelectNumber = multiple ? 9 : 1;
      opt.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      const out = await new photoAccessHelper.PhotoViewPicker().select(opt);
      const uris = out.photoUris;
      if (uris.length === 0) {
        result.handleFileList([]);
        return;
      }
      const picked: string[] = [];
      const limit = uris.length > 9 ? 9 : uris.length;
      for (let i = 0; i < limit; i++) {
        picked.push(uris[i]);
      }
      result.handleFileList(picked);
    } catch (e) {
      fnDiagRecord('W', 'Feedback', `pick images failed ${String(e)}`);
      result.handleFileList([]);
    }
  }

  private async chooseUpload(result: FileSelectorResult, accept: Array<string>, multiple: boolean): Promise<void> {
    if (this.acceptLooksLikeImage(accept)) {
      await this.deliverImages(result, multiple);
      return;
    }
    try {
      const choice = await this.getUIContext().getPromptAction().showActionMenu({
        title: '上传到表单',
        buttons: [
          { text: '选择图片', color: '#FF4A8BFF' },
          { text: '上传诊断日志', color: '#FF4A8BFF' }
        ]
      });
      if (choice.index === 0) {
        await this.deliverImages(result, true);
        return;
      }
      if (choice.index === 1) {
        await this.deliverLog(result);
        return;
      }
      result.handleFileList([]);
    } catch (e) {
      fnDiagRecord('W', 'Feedback', `choose upload failed ${String(e)}`);
      result.handleFileList([]);
    }
  }

  private onFileSelector(result: FileSelectorResult, accept: Array<string>, mode: FileSelectorMode): void {
    if (this.picking) {
      result.handleFileList([]);
      return;
    }
    this.picking = true;
    const multiple = mode === FileSelectorMode.FileOpenMultipleMode;
    void this.chooseUpload(result, accept, multiple).finally((): void => {
      this.picking = false;
    });
  }

  @Builder
  private topBar() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22)
          .fontColor([fnResolvedTextPrimary(this.themeTextPrimary)])
      }
      .width(40)
      .height(40)
      .backgroundColor(fnResolvedCardFill(this.cardBg))
      .onClick((): void => {
        this.goBack();
      })

      Text('反馈')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        .layoutWeight(1)

      Blank().width(40).height(40)
    }
    .width('100%')
    .height(56 + this.systemTopInsetVp)
    .padding({ left: 14, right: 14, top: this.systemTopInsetVp })
    .backgroundColor(this.pageBg)
  }

  @Builder
  private hintBar() {
    Column() {
      Text(this.logHint)
        .fontSize(13)
        .fontColor(this.logReady ? fnResolvedTextSecondary(this.themeTextSecondary) : Color.Red)
        .lineHeight(18)
        .width('100%')

      Row({ space: 18 }) {
        Text('重新生成')
          .fontSize(13)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
          .onClick((): void => {
            this.regenerateLog();
          })

        Text('分享诊断日志')
          .fontSize(13)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
          .onClick((): void => {
            this.shareLog();
          })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(fnResolvedCardFill(this.cardBg))
  }

  @Builder
  private formBody() {
    if (this.formUrl().length === 0) {
      Text('飞书表单链接还没配上。配好后，这里会打开表单。')
        .fontSize(15)
        .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
        .lineHeight(22)
        .width('100%')
        .padding(20)
    } else if (this.formError.length > 0) {
      Column({ space: 12 }) {
        Text(this.formError)
          .fontSize(15)
          .fontColor(Color.Red)
          .lineHeight(22)
          .width('100%')
        Text('重试')
          .fontSize(15)
          .fontColor(this.accent)
          .onClick((): void => {
            this.formError = '';
            this.webLoading = true;
            try {
              this.webController.loadUrl(this.formUrl());
            } catch (_e) {
              this.webLoading = false;
              this.formError = FORM_LOAD_FAIL;
            }
          })
      }
      .width('100%')
      .padding(20)
      .alignItems(HorizontalAlign.Start)
    } else {
      Stack() {
        Web({ src: this.formUrl(), controller: this.webController })
          .width('100%')
          .height('100%')
          .backgroundColor(Color.White)
          .darkMode(WebDarkMode.Off)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .databaseAccess(true)
          .imageAccess(true)
          .onlineImageAccess(true)
          .fileAccess(true)
          .zoomAccess(true)
          .mixedMode(MixedMode.All)
          .cacheMode(CacheMode.Online)
          .onPageBegin((): void => {
            this.webLoading = true;
          })
          .onPageEnd((): void => {
            this.webLoading = false;
            this.paintWebBackground();
          })
          .onErrorReceive((event: OnErrorReceiveEvent): void => {
            try {
              if (!event.request.isMainFrame()) {
                return;
              }
            } catch (_e) {
            }
            this.webLoading = false;
            this.formError = FORM_LOAD_FAIL;
          })
          .onHttpErrorReceive((event: OnHttpErrorReceiveEvent): void => {
            try {
              if (!event.request.isMainFrame() || event.response.getResponseCode() < 400) {
                return;
              }
            } catch (_e) {
              return;
            }
            this.webLoading = false;
            this.formError = FORM_LOAD_FAIL;
          })
          .onShowFileSelector((event: OnShowFileSelectorEvent): boolean => {
            let accept: Array<string> = [];
            let mode: FileSelectorMode = FileSelectorMode.FileOpenMode;
            try {
              accept = event.fileSelector.getAcceptType();
              mode = event.fileSelector.getMode();
            } catch (_e) {
            }
            this.onFileSelector(event.result, accept, mode);
            return true;
          })

        if (this.webLoading) {
          Column() {
            LoadingProgress().width(28).height(28).color(this.accent)
            Text('正在打开表单…')
              .fontSize(13)
              .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
              .margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.pageBg)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Color.White)
      .padding({ bottom: Math.max(this.navIndicatorInsetVp, this.systemBottomInsetVp) })
    }
  }

  build() {
    Column() {
      this.topBar()
      this.hintBar()
      this.formBody()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: FN_PAGE_ENTER_DURATION, curve: FN_PAGE_ENTER_CURVE })
      .opacity(0)
      .translate({ x: 0, y: 16 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: 0, y: -8 });
  }
}
