import {
  FN_PAGE_ENTER_CURVE,
  FN_PAGE_ENTER_DURATION,
  FN_PAGE_EXIT_CURVE,
  FN_PAGE_EXIT_DURATION
} from '../common/FnMotion';

@Entry
@Component
struct PrivacyPolicy {
  private goBack(): void {
    this.getUIContext().getRouter().back();
  }

  @Builder
  private sectionTitle(text: string) {
    Text(text)
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.text_primary'))
      .width('100%')
      .margin({ top: 18, bottom: 2 })
  }

  @Builder
  private paragraph(text: string) {
    Text(text)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .lineHeight(22)
      .width('100%')
  }

  @Builder
  private bullet(text: string) {
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
      Row({ space: 10 }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.card_background'))
        .onClick((): void => {
          this.goBack();
        })

        Text($r('app.string.privacy_policy_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Blank()
          .width(40)
          .height(40)
      }
      .width('100%')
      .height(56)
      .padding({ left: 14, right: 14 })
      .backgroundColor($r('app.color.page_background'))

      Scroll() {
        Column({ space: 10 }) {
          Text('FMphoto 隐私政策')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Text('生效日期：2026 年 6 月 10 日')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: 10 })

          this.paragraph('FMphoto 是一个面向飞牛 NAS 相册的非官方 HarmonyOS 客户端。应用的核心用途是在用户指定的 NAS 服务之间登录、浏览、搜索、预览、上传、下载和管理相册内容。除用户自行配置的 NAS 地址外，应用本身不运营开发者云端服务，不包含广告、第三方统计或第三方崩溃上报 SDK，也不会主动把用户数据发送给开发者服务器。')

          this.sectionTitle('我们处理哪些信息')
          this.paragraph('为实现相册客户端功能，应用会在设备本地和用户配置的 NAS 之间处理以下信息：')
          this.bullet('NAS 连接信息：用户输入的服务器地址、协议选择、账号名、相册父目录等配置。')
          this.bullet('登录凭据和会话信息：用户输入的 NAS 密码、登录后获得的 token、长 token、WebSocket 签名密钥、OpenAPI Authx key/secret、受信任证书主机列表等。当前实现会把这些信息保存在应用私有偏好设置中，用于会话保持、冷启动恢复和登录表单回填。')
          this.bullet('相册数据：从 NAS 返回的照片、视频、缩略图、原图地址、文件名、文件大小、拍摄时间、收藏状态、回收站状态、人物/分类/智能搜索结果等。')
          this.bullet('媒体元数据：查看详情或地图功能时，应用可能展示 NAS 返回的相机型号、曝光信息、文件路径、经纬度、地点聚合等照片元数据。')
          this.bullet('用户选择的本地媒体：当用户主动上传照片时，应用会通过系统图片选择器读取所选文件内容，并发送到用户配置的 NAS。')
          this.bullet('本地临时文件：下载、预览 GIF/视频、保存到系统相册等操作可能在应用缓存目录创建临时文件，操作完成后应用会尽量清理。')
          this.bullet('运行日志：应用可能记录连接状态、请求结果、错误摘要、主机地址或文件名等诊断信息。应用不以收集隐私为目的记录密码或完整 cookie，但用户分享日志前仍应自行检查其中是否包含 NAS 地址或错误响应内容。')

          this.sectionTitle('信息如何使用')
          this.bullet('连接用户指定的 NAS，并完成登录、会话恢复和接口签名。')
          this.bullet('展示相册首页、时间线、分类、人物、搜索结果、地图、照片详情和预览内容。')
          this.bullet('执行用户主动发起的上传、下载、保存、收藏、删除、恢复等相册操作。')
          this.bullet('在下载或上传过程中维持短时间后台数据传输，减少任务被系统中断的概率。')
          this.bullet('记住用户的登录表单和证书信任选择，减少重复输入。')

          this.sectionTitle('数据发送到哪里')
          this.paragraph('应用的数据传输目标是用户在登录页填写并确认的 NAS 地址，以及该 NAS 提供的相册 Web/API 接口。开发者不会通过本应用接收、存储或转售用户的照片、视频、账号、密码、token、日志或其他个人信息。')
          this.paragraph('如果用户填写的是公网域名、远程访问地址、反向代理地址或第三方网络服务地址，相关数据会按用户的配置发送到该地址。该地址及其服务器的安全性、日志策略和数据处理方式由用户或对应服务提供方负责。')

          this.sectionTitle('系统权限说明')
          this.bullet('网络访问：用于连接用户配置的 NAS，加载相册、缩略图、原图、视频和执行接口请求。')
          this.bullet('获取网络状态：用于判断网络连接状态，辅助相册请求和错误提示。')
          this.bullet('后台运行/数据传输：用于用户主动上传或下载媒体时维持短时间后台任务。')
          this.bullet('振动：用于长按、多选等交互反馈。')
          this.bullet('系统图片选择器和相册保存入口：用于用户主动选择本地照片上传，或把从 NAS 下载的图片/视频保存到系统相册。应用不会在未经过用户操作的情况下扫描本地媒体库。')

          this.sectionTitle('定位和地图')
          this.paragraph('应用不申请设备定位权限，也不读取设备实时位置。地图和地点相关功能使用的是 NAS 相册接口返回的照片地理元数据，例如照片 EXIF 或 NAS 聚合出的经纬度、地点名称。内置 Web 地图页面已关闭网页地理定位访问。')

          this.sectionTitle('保存与删除')
          this.paragraph('会话 token、签名密钥、账号、最后一次输入的密码、服务器地址、证书信任列表和部分设置保存在设备本地应用私有存储中。退出登录会清除主要会话 token 和签名凭据，但为便于下次登录，账号、登录表单信息和最后一次密码可能仍保留在本地。若要彻底删除本地保存信息，请在系统设置中清除应用数据或卸载应用。')
          this.paragraph('存放在 NAS 上的照片、视频、人物分类、智能分类、回收站和相册元数据由用户的 NAS 管理。应用中的删除、恢复、上传、收藏等操作会直接作用于用户配置的 NAS，具体保留时间以 NAS 的设置和回收站策略为准。')

          this.sectionTitle('安全说明')
          this.paragraph('应用支持使用 HTTPS 连接 NAS。对于自签名证书或无法校验的证书，只有在用户明确选择信任后，应用才会将对应主机加入本地受信任列表并继续连接。用户应确认 NAS 地址、证书和网络环境可信后再输入账号密码。')

          this.sectionTitle('儿童隐私')
          this.paragraph('本应用不是面向儿童的服务，也不会主动识别、收集或分析儿童个人信息。相册中是否包含儿童照片或相关信息，取决于用户自己的 NAS 内容和使用方式。')

          this.sectionTitle('政策更新')
          this.paragraph('如果应用的数据处理方式、权限范围或第三方依赖发生变化，本页面会随版本更新。继续使用更新后的应用即表示用户了解更新后的说明。')

          this.sectionTitle('联系方式')
          this.paragraph('如对本隐私政策或应用的数据处理方式有疑问，可以通过 GitHub 仓库联系开发者：')
          Text('https://github.com/jonas-pi/FMphoto')
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
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
