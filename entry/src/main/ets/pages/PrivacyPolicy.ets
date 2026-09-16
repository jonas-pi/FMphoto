import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { SessionPreferences } from '../auth/SessionPreferences';
import { FnHdsSimpleChrome } from '../common/FnHdsSimpleChrome';
import { fnApplyImmersiveSystemBarColors } from '../common/FnSplashTheme';
import {
  FN_NAV_INDICATOR_INSET_VP_KEY,
  FN_SYSTEM_TOP_INSET_VP_KEY,
  fnPublishSystemAvoidArea
} from '../common/FnSystemAvoidArea';
import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';

@Entry
@Component
struct PrivacyPolicy {
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(FN_NAV_INDICATOR_INSET_VP_KEY) private navIndicatorInsetVp: number = 0;
  /** 本地已持久化同意。已同意后再次打开只是查看，不重新拦截。 */
  @State private accepted: boolean = false;
  /** 未同意时必须决断，系统返回无效。 */
  @State private decisionRequired: boolean = false;
  @State private submitting: boolean = false;

  aboutToAppear(): void {
    this.applySystemBar();
    void this.loadConsentState();
  }

  onPageShow(): void {
    this.applySystemBar();
  }

  onBackPress(): boolean {
    return this.decisionRequired;
  }

  private onColorModeChanged(): void {
    this.applySystemBar();
  }

  /** 沉浸式窗口下背景可延伸，标题栏与正文用动态避让区垫开。 */
  private applySystemBar(): void {
    try {
      const dark = this.colorMode === 1;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window): void => {
        fnApplyImmersiveSystemBarColors(win, dark);
        fnPublishSystemAvoidArea(win, this.getUIContext());
      }).catch((_e: Error): void => {});
    } catch (_e) {
    }
  }

  private async loadConsentState(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const ok = await SessionPreferences.isPrivacyPolicyAccepted(ctx);
      this.accepted = ok;
      this.decisionRequired = !ok;
    } catch (_e) {
      this.accepted = false;
      this.decisionRequired = true;
    }
  }

  private goBack(): void {
    if (this.decisionRequired) {
      return;
    }
    this.getUIContext().getRouter().back();
  }

  private async agreeConsent(): Promise<void> {
    if (this.submitting) {
      return;
    }
    this.submitting = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await SessionPreferences.setPrivacyPolicyAccepted(ctx, true);
      this.accepted = true;
      this.decisionRequired = false;
      this.getUIContext().getRouter().back();
    } catch (_e) {
      try {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.privacy_consent_save_failed'),
          duration: 2500
        });
      } catch (_ignored) {
      }
    } finally {
      this.submitting = false;
    }
  }

  private async rejectConsent(): Promise<void> {
    if (this.submitting) {
      return;
    }
    if (this.accepted) {
      try {
        const dlg = await this.getUIContext().getPromptAction().showDialog({
          title: $r('app.string.privacy_consent_withdraw_title'),
          message: $r('app.string.privacy_consent_withdraw_message'),
          buttons: [
            { text: $r('app.string.cancel'), color: '#99000000' },
            { text: $r('app.string.privacy_consent_withdraw'), color: '#E5484D' }
          ]
        });
        if (dlg.index !== 1) {
          return;
        }
      } catch (_e) {
        return;
      }
    }
    this.submitting = true;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await SessionPreferences.setPrivacyPolicyAccepted(ctx, false);
    } catch (_e) {
    }
    try {
      await ctx.terminateSelf();
    } catch (_e) {
    }
    this.submitting = false;
  }

  @Builder
  private sectionTitle(text: ResourceStr) {
    Text(text)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .margin({ top: 18, bottom: 2 })
  }

  @Builder
  private paragraph(text: ResourceStr) {
    Text(text)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .lineHeight(22)
      .width('100%')
  }

  @Builder
  private bullet(text: ResourceStr) {
    Row({ space: 8 }) {
      Text('•')
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(22)

      Text(text)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(22)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Column() {
      FnHdsSimpleChrome({
        title: '隐私政策',
        showBack: !this.decisionRequired,
        topSafeInsetVp: this.systemTopInsetVp,
        onBack: (): void => {
          this.goBack();
        }
      })

      Scroll() {
        Column({ space: 10 }) {
          Text($r('app.string.privacy_policy_heading'))
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Text($r('app.string.privacy_policy_updated'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: 10 })

          if (this.decisionRequired) {
            Text($r('app.string.privacy_consent_locked_hint'))
              .fontSize(14)
              .fontColor($r('app.color.brand_primary'))
              .lineHeight(22)
              .width('100%')
          }

          this.paragraph($r('app.string.privacy_policy_intro'))

          this.sectionTitle('开发者与应用信息')
          this.bullet('开发者：皮朝猛（个人开发者）。')
          this.bullet('应用名称：飞马相册。')
          this.bullet('应用包名：com.jonas.fmphoto。')
          this.bullet('本应用与飞牛（广州铁刃智造技术有限公司）无官方从属关系。')

          this.sectionTitle('我们处理哪些信息')
          this.paragraph('为实现相册客户端功能，应用会在设备本地、用户配置的 NAS，以及（仅当使用 FN ID / 官方中继时）飞牛 FN Connect 之间处理以下信息：')
          this.bullet('NAS 连接信息：你输入的服务器地址、协议、账号名、FN ID、公网域名、选路偏好、相册父目录等。')
          this.bullet('登录凭据和会话信息：NAS 密码、登录后获得的 token / 长 token、WebSocket 签名密钥、OpenAPI Authx key/secret、受信任证书主机列表。上述信息保存在应用私有存储中，用于会话保持、冷启动恢复和登录表单回填。')
          this.bullet('记住密码（可选）：若你开启「记住密码」，密码会经系统 HUKS（AES-256-GCM）加密后仅保存在本机，密钥不出应用沙箱。退出登录时，若仍开启该选项，加密后的密码会保留以便下次回填；关闭该选项或清除应用数据后即删除。')
          this.bullet('本机设备标识：应用会生成并保存一个 WebSocket 设备标识（did），用于飞牛登录和两步验证「信任本设备」。该标识不是 IMEI、OAID 或硬件序列号，退出登录时默认保留。')
          this.bullet('相册数据：从 NAS 返回的照片、视频、缩略图、原图地址、文件名、大小、拍摄时间、收藏、回收站、人物 / 分类 / 搜索结果等。')
          this.bullet('媒体元数据：详情或地图可能展示 NAS 返回的相机型号、曝光、文件路径、经纬度、地点聚合等。')
          this.bullet('用户选择的本地媒体：你主动上传时，应用通过系统图片选择器读取所选文件并发送到你的 NAS。公开发布包不申请读取本机相册权限，也不会在未经你操作时扫描媒体库。')
          this.bullet('配置同步（可选）：二维码在本机展示或扫描；若你填写 WebDAV 地址，相关配置（可能含登录信息）会发往该地址。')
          this.bullet('本地临时文件：下载、预览、保存到系统相册等可能在缓存目录创建临时文件，完成后会尽量清理。')
          this.bullet('运行日志：可能记录连接状态、请求结果、错误摘要、主机地址或文件名。不以收集隐私为目的记录密码或完整 cookie；分享日志前请自行检查。')

          this.sectionTitle('信息如何使用')
          this.bullet('连接你指定的 NAS，完成登录、会话恢复和接口签名。')
          this.bullet('展示相册首页、时间线、分类、人物、搜索、地图、详情和预览。')
          this.bullet('执行你主动发起的上传、下载、保存、收藏、删除、恢复等操作。')
          this.bullet('在上传或下载时维持短时间后台传输。')
          this.bullet('记住登录表单、证书信任和可选的加密密码，减少重复输入。')

          this.sectionTitle('数据发送到哪里')
          this.paragraph('默认传输目标是你在登录页确认的 NAS 及其相册接口。开发者不会通过本应用接收、存储或转售你的照片、视频、账号、密码、token 或其他个人信息。')
          this.paragraph('若你填写 FN ID 或使用飞牛官方中继，应用会向 https://fnos.net/api/v1/fn/con 提交 FN ID 以解析公网 / 内网 / 中继地址；此后登录和相册请求可能经 *.fnos.net 或 *.5ddd.com 加密转发到你的 NAS。该服务由广州铁刃智造技术有限公司运营，详见「我的」中的第三方共享清单及飞牛官方政策。仅填写局域网或公网直连地址时，不会请求飞牛云解析。')
          this.paragraph('若你填写公网域名、反代或自行配置的 WebDAV 地址，相关数据会发往该地址，其安全与日志策略由你或对应服务方负责。')

          this.sectionTitle('系统权限说明')
          this.bullet('网络访问：连接 NAS、加载媒体和接口请求；使用 FN ID 时访问飞牛云。')
          this.bullet('获取网络状态：判断连接状态，辅助请求和错误提示。')
          this.bullet('后台运行 / 数据传输：你主动上传或下载时维持短时间后台任务。')
          this.bullet('振动：长按、多选等交互反馈。')
          this.bullet('系统图片选择器和保存到相册：由你主动选图上传，或把 NAS 中的内容保存到系统相册。不申请读取本机相册权限。')

          this.sectionTitle('定位和地图')
          this.paragraph('应用不申请设备定位权限，也不读取设备实时位置。地图使用 NAS 返回的照片地理元数据。内置网页地图已关闭网页地理定位。')

          this.sectionTitle('保存、查阅与删除')
          this.paragraph('会话 token、签名密钥、账号、服务器地址、证书信任列表、设备标识和部分设置保存在本机应用私有存储。退出登录会清除主要会话 token 和签名凭据；账号、FN ID、域名和选路等表单会保留。记住密码开启时，加密密码也会保留。')
          this.paragraph('NAS 上的照片、分类、回收站等由你的 NAS 管理，应用内删除 / 恢复 / 上传会直接作用于该 NAS。')
          this.paragraph('你可在本页和「我的」中的两份清单查阅处理情况；可在登录页更正连接信息；可关闭记住密码、退出登录、在系统设置中清除应用数据或卸载以删除本机信息。撤回同意后将退出应用，再次打开需重新同意。')

          this.sectionTitle('安全说明')
          this.paragraph('应用支持 HTTPS 连接 NAS。自签名或无法校验的证书，仅在你明确选择信任后才会加入本机受信任列表。请确认 NAS 地址、证书和网络环境可信后再输入账号密码。')

          this.sectionTitle('儿童隐私')
          this.paragraph('本应用不是面向不满十四周岁儿童的服务，也不会主动识别或分析儿童个人信息。相册中是否包含相关内容，取决于你自己的 NAS 使用方式。')

          this.sectionTitle('政策更新')
          this.paragraph('数据处理方式、权限或第三方依赖发生变化时，本页会随版本更新，并可能要求重新同意。不同意请停止使用并卸载。')

          this.sectionTitle('联系方式')
          this.paragraph('开发者：皮朝猛。如对隐私政策或数据处理有疑问、投诉或行使查阅 / 复制 / 更正 / 删除 / 撤回同意等权利，请通过客服邮箱或 GitHub 联系，我们将在验证后十五个工作日内答复：')
          Text('pichaomeng@gmail.com')
            .fontSize(14)
            .fontColor($r('app.color.brand_primary'))
            .lineHeight(22)
            .width('100%')
          Text('https://github.com/jonas-pi/FMphoto')
            .fontSize(14)
            .fontColor($r('app.color.brand_primary'))
            .lineHeight(22)
            .width('100%')
          Text('https://jonas-pi.github.io/FMphoto/privacy.html')
            .fontSize(14)
            .fontColor($r('app.color.brand_primary'))
            .lineHeight(22)
            .width('100%')

          Blank()
            .height(18)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 18, bottom: 18 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

      Row({ space: 12 }) {
        Button(this.accepted ? $r('app.string.privacy_consent_withdraw') : $r('app.string.privacy_consent_disagree'))
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor('#FFFF3B30')
          .backgroundColor('#1AFF3B30')
          .borderRadius(14)
          .enabled(!this.submitting)
          .onClick((): void => {
            void this.rejectConsent();
          })

        Button($r('app.string.privacy_consent_agree'))
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(14)
          .enabled(!this.submitting)
          .onClick((): void => {
            void this.agreeConsent();
          })
      }
      .width('100%')
      .padding({
        left: 20,
        right: 20,
        top: 10,
        bottom: 12 + this.navIndicatorInsetVp
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
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
