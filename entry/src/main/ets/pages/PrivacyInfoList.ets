/**
 * 「我的」二级菜单：已收集个人信息清单 / 第三方共享个人信息清单。
 */
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
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
import { fnResolvedCardFill, FN_RESOLVED_CARD_BG_KEY, FN_RESOLVED_PAGE_BG_KEY,
  fnResolvedTextPrimary,
  FN_RESOLVED_TEXT_PRIMARY_KEY,
  fnResolvedTextSecondary,
  FN_RESOLVED_TEXT_SECONDARY_KEY} from '../common/FnThemeColors';

const KIND_THIRD_PARTY = 'thirdParty';

@Entry
@Component
struct PrivacyInfoList {
  @StorageProp(FN_RESOLVED_TEXT_PRIMARY_KEY) private themeTextPrimary: string = '';
  @StorageProp(FN_RESOLVED_TEXT_SECONDARY_KEY) private themeTextSecondary: string = '';
  @StorageProp(FN_RESOLVED_PAGE_BG_KEY) private pageBg: string = '#FFF4F7FB';
  @StorageProp(FN_RESOLVED_CARD_BG_KEY) private cardBg: string = '';
  @StorageProp('colorMode') @Watch('onColorModeChanged') private colorMode: number = 0;
  @StorageProp(FN_SYSTEM_TOP_INSET_VP_KEY) private systemTopInsetVp: number = 0;
  @StorageProp(FN_NAV_INDICATOR_INSET_VP_KEY) private navIndicatorInsetVp: number = 0;
  @State private kind: string = 'collected';

  aboutToAppear(): void {
    const rp = this.getUIContext().getRouter().getParams() as Record<string, Object> | undefined;
    if (rp !== undefined && rp['kind'] !== undefined) {
      this.kind = String(rp['kind']);
    }
    this.applySystemBar();
  }

  onPageShow(): void {
    this.applySystemBar();
  }

  private onColorModeChanged(): void {
    this.applySystemBar();
  }

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

  private isThirdParty(): boolean {
    return this.kind === KIND_THIRD_PARTY;
  }

  private pageTitle(): Resource {
    return this.isThirdParty() ?
      $r('app.string.privacy_third_party_entry_title') :
      $r('app.string.privacy_collected_entry_title');
  }

  private goBack(): void {
    this.getUIContext().getRouter().back();
  }

  @Builder
  private sectionTitle(text: string) {
    Text(text)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
      .width('100%')
      .margin({ top: 18, bottom: 2 })
  }

  @Builder
  private paragraph(text: string) {
    Text(text)
      .fontSize(14)
      .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
      .lineHeight(22)
      .width('100%')
  }

  @Builder
  private bullet(text: string) {
    Row({ space: 8 }) {
      Text('•')
        .fontSize(15)
        .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
        .lineHeight(22)

      Text(text)
        .fontSize(14)
        .fontColor(fnResolvedTextSecondary(this.themeTextSecondary))
        .lineHeight(22)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private collectedBody() {
    Column({ space: 10 }) {
      this.paragraph('本清单列出飞马相册已经或可能处理的个人信息。开发者皮朝猛不运营云端相册，也不会把下列信息发到开发者服务器。')

      this.sectionTitle('登录与连接 NAS')
      this.bullet('信息种类：NAS 地址、协议、账号、密码、FN ID、公网域名、选路偏好、证书信任记录。')
      this.bullet('使用目的：连接并登录你指定的 NAS。')
      this.bullet('使用场景：登录、冷启动恢复、切换连接通道。')
      this.bullet('是否必要：连接功能必要。登录期间保存口令用于切网；记住密码为可选项。')
      this.bullet('处理方式：保存在本机应用沙箱。登录期间口令优先经 HUKS AES-256-GCM 加密，无法封存时明文落盘。勾选记住密码时，退出后仍保留以便回填。账号密码会发往你的 NAS（直连或经 FN Connect 中继）。')

      this.sectionTitle('会话与设备标识')
      this.bullet('信息种类：token、长 token、签名密钥、OpenAPI Authx、应用生成的 WebSocket 设备标识（did）。')
      this.bullet('使用目的：保持登录、接口签名、两步验证「信任本设备」。')
      this.bullet('使用场景：登录成功后的相册访问、冷启动恢复、2FA。')
      this.bullet('是否必要：必要。')
      this.bullet('处理方式：本机保存；did 随登录请求发往 NAS。did 不是硬件序列号，退出登录默认保留。')

      this.sectionTitle('相册内容与元数据')
      this.bullet('信息种类：照片 / 视频 / 缩略图、文件名、大小、拍摄时间、收藏、回收站、人物 / 分类 / 搜索、EXIF、经纬度等 NAS 返回数据。')
      this.bullet('使用目的：浏览和管理相册。')
      this.bullet('使用场景：图库、预览、搜索、地图、详情。')
      this.bullet('是否必要：使用相册功能时必要。')
      this.bullet('处理方式：来自你的 NAS，在本机展示和缓存；不发往开发者服务器。')

      this.sectionTitle('本机媒体（系统选图上传）')
      this.bullet('信息种类：你通过系统图片选择器选出的照片 / 视频文件。')
      this.bullet('使用目的：上传到 NAS。')
      this.bullet('使用场景：你主动点击上传或同步。')
      this.bullet('是否必要：可选。')
      this.bullet('处理方式：经系统选择器读取，发送到你的 NAS。公开发布包不扫描本机相册。')

      this.sectionTitle('配置同步（可选）')
      this.bullet('信息种类：登录配置、备份路径与策略、相册布局、智能分类、主题和幻灯片。记住密码开启时含登录口令。不含 token、签名密钥、WebDAV 账号密码、本机设备名和自动同步账本。')
      this.bullet('使用目的：在设备间同步这些应用设置。')
      this.bullet('使用场景：二维码导出 / 导入、你填写的 WebDAV，或华为云空间。')
      this.bullet('是否必要：可选。')
      this.bullet('处理方式：二维码在本机处理。WebDAV 发往你填写的服务器。华为云空间在端侧加密后写入你的华为账号，开关在系统「设置 - 云空间」。')

      this.sectionTitle('赞赏（可选）')
      this.bullet('信息种类：你选择的赞赏档位和华为应用内支付返回的订单结果。不含银行卡号或支付密码。')
      this.bullet('使用目的：自愿支持开发。')
      this.bullet('使用场景：你在「我的」里打开赞赏并完成支付时。')
      this.bullet('是否必要：可选。')
      this.bullet('处理方式：由华为应用内支付收款。应用只确认订单已消耗，不解锁功能。')

      this.sectionTitle('临时文件与运行日志')
      this.bullet('信息种类：缓存文件；崩溃快照、播放失败等诊断摘要、主机或文件名。')
      this.bullet('使用目的：预览、下载、排障。')
      this.bullet('是否必要：功能运行需要；日志不以收集隐私为目的。')
      this.bullet('处理方式：仅本机保存。不主动记录密码或完整 cookie。反馈页可打开飞书表单，由你自行填写并选择是否上传本机日志，应用不会把日志发到开发者的服务器。')

      this.sectionTitle('不收集的信息')
      this.paragraph('不申请设备定位、通讯录、短信、麦克风或通话记录；无广告、统计或崩溃上报 SDK；不读取 IMEI / OAID。')
    }
    .width('100%')
  }

  @Builder
  private thirdPartyBody() {
    Column({ space: 10 }) {
      this.paragraph('除下列情形外，飞马相册不向广告、统计、推送、地图商等 SDK 共享个人信息。')

      this.sectionTitle('飞牛 FN Connect')
      this.bullet('第三方名称：广州铁刃智造技术有限公司（飞牛）。')
      this.bullet('产品类型：FN Connect 地址解析与中继（fnos.net、5ddd.com）。')
      this.bullet('共享信息：你填写的 FN ID；若走官方中继，登录凭据和相册请求会经其中继加密转发到你的 NAS。')
      this.bullet('使用目的：解析 NAS 可达地址，提供远程访问。')
      this.bullet('使用场景：你选择以 FN ID 或官方中继登录时。仅填写局域网 / 公网直连则不请求飞牛云。')
      this.bullet('共享方式：HTTPS 接口提交 FN ID；随后可能经 HTTPS 反代转发。')
      this.bullet('第三方政策：https://fnnas.com/privacy')
      this.bullet('FN Connect 协议：https://fnnas.com/terms-of-fn-connect')

      this.sectionTitle('华为云空间')
      this.bullet('第三方名称：华为云空间（随你的华为账号提供）。')
      this.bullet('产品类型：结构化数据同步。')
      this.bullet('共享信息：你选择同步的应用配置。记住密码开启时含登录口令。照片、视频、token 和签名密钥不会写入。')
      this.bullet('使用目的：在登录同一华为账号的设备之间同步这些设置。')
      this.bullet('使用场景：你在配置同步页上传或下载，或在系统「设置 - 云空间」打开飞马相册同步之后。')
      this.bullet('共享方式：配置在端侧加密后保存到你本人的云空间。开发者不能在控制台查看加密内容，也不能查看其他用户的记录。')
      this.bullet('管理方式：系统「设置 - 云空间」关闭本应用同步，或在云空间中删除数据。')
      this.bullet('第三方政策：https://consumer.huawei.com/cn/privacy/privacy-policy/')

      this.sectionTitle('你自行指定的 NAS / WebDAV / 反代')
      this.bullet('第三方名称：由你填写的服务器运营方，不是本应用预置的 SDK 合作方。')
      this.bullet('共享信息：为完成登录、相册或配置同步所必需的账号、媒体和配置。')
      this.bullet('使用目的：按你的配置提供相册或同步服务。')
      this.bullet('使用场景：登录、浏览、上传下载、可选的 WebDAV 配置同步。')
      this.bullet('共享方式：你确认的 HTTP / HTTPS 请求。')
      this.bullet('隐私政策：请查阅该服务器运营方自行公布的规则。')

      this.sectionTitle('意见反馈（可选）')
      this.bullet('第三方名称：北京飞书科技有限公司（飞书多维表格表单）。')
      this.bullet('共享信息：你在表单里填写的内容、自行选择的截图，以及你选择上传的本机诊断日志。')
      this.bullet('使用目的：把问题或建议交给开发者。')
      this.bullet('使用场景：你主动打开「反馈」并提交表单时。不打开则不会发送。')
      this.bullet('共享方式：表单页面由飞书提供，提交发往飞书。诊断日志先写在本机，不经应用服务器转发。')

      this.sectionTitle('华为应用内支付')
      this.bullet('第三方名称：华为应用内支付。')
      this.bullet('共享信息：商品 ID、订单结果。不含相册内容和 NAS 密码。')
      this.bullet('使用目的：完成自愿赞赏。')
      this.bullet('使用场景：你主动购买「请喝杯咖啡」「请吃顿午饭」或「请吃顿晚饭」时。')
      this.bullet('共享方式：系统收银台。不打开则不会发生。')
      this.bullet('第三方政策：https://consumer.huawei.com/cn/privacy/privacy-policy/')

      this.sectionTitle('HarmonyOS 系统能力')
      this.paragraph('系统图片选择器、保存到相册、HUKS 密钥、网络和扫码属于操作系统能力，按系统接口在本机处理，不视为向开发者合作的第三方 SDK 共享。')

      this.sectionTitle('未集成的服务')
      this.paragraph('未集成广告、统计分析、推送、第三方登录或商业地图 SDK。地图使用 NAS 网页或本机绘制，并已关闭网页地理定位。')
    }
    .width('100%')
  }

  build() {
    Column() {
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

        Text(this.pageTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(fnResolvedTextPrimary(this.themeTextPrimary))
          .layoutWeight(1)

        Blank()
          .width(40)
          .height(40)
      }
      .width('100%')
      .height(56 + this.systemTopInsetVp)
      .padding({ left: 14, right: 14, top: this.systemTopInsetVp })
      .backgroundColor(this.pageBg)

      Scroll() {
        Column() {
          if (this.isThirdParty()) {
            this.thirdPartyBody()
          } else {
            this.collectedBody()
          }
          Blank()
            .height(18 + this.navIndicatorInsetVp)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 18, bottom: 18 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
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
      .translate({ x: 0, y: 16 });
    PageTransitionExit({ duration: FN_PAGE_EXIT_DURATION, curve: FN_PAGE_EXIT_CURVE })
      .opacity(0)
      .translate({ x: 0, y: -8 });
  }
}
