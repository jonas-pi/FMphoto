# 侧边栏菜单样式

- 页面标题: 侧边栏菜单样式
- slug: `ui-design-side-menu`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-side-menu
- 文档ID: `99d094094b8e49b79ed42cf4d119b53d`
- 更新时间: 2026-04-22 06:36:54

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553198741"></a><a name="ZH-CN_TOPIC_0000002553198741"></a>   <h1>侧边栏菜单样式</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553198741__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持设置侧边栏菜单样式。</p>     <p><a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdssidemenu" target="_blank">HdsSideMenu</a>提供一种菜单栏样式组件。设置侧边栏对应的一级菜单和二级菜单，并显示其新消息数量。</p>     <p><span><img originheight="533" originwidth="251" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/d8/v3/uLUaOv7UQH2E_AsUzh6ZqA/zh-cn_image_0000002552958340.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083914Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=4F55B26A790FEAE939B557F51D767DA80D92BF11ADEA4829F39F3FAFC55D648F"></span></p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553198741__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">import { HdsSideMenu, HdsSideMenuMainItem, HdsSideMenuSubItem, HdsSideMenuBadgeParam, HdsSideBar } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';</pre></li>      <li>       <p>设置对应的一级菜单和二级菜单，并显示其新消息数量。</p>       <pre class="typescript">@Entry
@ComponentV2
struct Index {
  @Local showControlButton: boolean = true;
  @Local sideBarMask: boolean = false;
  @Local autoHide: boolean = true;
  @Local barStateTypeText: string = "Select BarState";
  @Local widthIndex: number = 0;
  @Local badgeNumber: HdsSideMenuBadgeParam = { count: 50 };
  @Local useTheme: boolean = false;
  @Local selectedIndex: number = 2;
  @Local selectedTransparency: number = 0.6;
  @Local str: string = "短信";
  @Local isShowSidebar: boolean = true;
  listOptionsDefault?: HdsSideMenuMainItem[] = [
    new HdsSideMenuMainItem(
      {
        symbol: new SymbolGlyphModifier($r('sys.symbol.ohos_folder_badge_plus')).fontSize(14),
        label: $r('sys.string.TextView_engr_phone'),
      }),
    new HdsSideMenuMainItem({
      icon: $r('sys.symbol.person_wave_3'),
      label: 'Tuesday',
      hdsSideMenuSubItem: [
        new HdsSideMenuSubItem({ label: this.str, badge: this.badgeNumber })],
    }),
    new HdsSideMenuMainItem({
      symbol: new SymbolGlyphModifier($r('sys.symbol.person_crop_circle_fill_1')),
      label: 'Wednesday',
    }),
  ]
  @Builder
  SideBarPanelBuilder() {
    Column() {
      HdsSideMenu({
        items: this.listOptionsDefault,
        selectedIndex: this.selectedIndex,
        $selectedIndex: (selectedIndex: number) =&gt; {
          this.selectedIndex = selectedIndex;
        },
      })
    }
    .height('100%')
  }
  //右侧内容区
  @Builder
  ContentPanelBuilder() {
    Column() {
      Column() {
        Button() {
          SymbolGlyph(this.isShowSidebar ? $r('sys.symbol.open_sidebar') : $r('sys.symbol.close_sidebar'))
            .fontWeight(FontWeight.Normal)
            .fontSize($r('sys.float.ohos_id_text_size_headline7'))
            .fontColor([$r('sys.color.ohos_id_color_titlebar_icon')])
            .hitTestBehavior(HitTestMode.None)
        }
        .backgroundColor($r('sys.color.ohos_id_color_button_normal'))
        .height(24)
        .width(24)
        .animation({ curve: Curve.Sharp, duration: 100 })
        .onClick(() =&gt; {
          this.isShowSidebar = !this.isShowSidebar;
        })
      }
    }
    .height('100%')
    .width('100%')
  }
  @BuilderParam sideBarBuilder: () =&gt; void = this.SideBarPanelBuilder
  @BuilderParam contentBuilder: () =&gt; void = this.ContentPanelBuilder
  @Builder
  build() {
    Column() {
      HdsSideBar({
        sideBarPanelBuilder: (): void =&gt; {
          this.sideBarBuilder()
        },
        contentPanelBuilder: (): void =&gt; {
          this.contentBuilder()
        },
        isShowSideBar: this.isShowSidebar,
        $isShowSideBar: (isShowSidebar: boolean) =&gt; {
          this.isShowSidebar = !isShowSidebar
        },
      })
    }
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
