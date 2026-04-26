# 沉浸光感

- 页面标题: 沉浸光感
- slug: `ui-design-hds-component-material`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-component-material
- 文档ID: `e483fb3bb21e4336a05a691ec9135e79`
- 更新时间: 2026-04-22 06:36:56

## 锚点目录

- 场景介绍
- 使用系统自适应的沉浸光感
-   开发步骤
- 使用自定义沉浸光感效果
-   开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002523835374"></a><a name="ZH-CN_TOPIC_0000002523835374"></a>   <h1>沉浸光感</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002523835374__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.1.0(23) 版本开始，新增支持HDS组件的沉浸光感材质能力。</p>     <ul>      <li><strong>HDS导航</strong>：通过设置<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsnavigation#titlebarstyleoptions" target="_blank">TitleBarStyleOptions</a>的systemMaterialEffect参数，可为标题栏按钮设置沉浸光感视效。</li>      <li><strong>HDS底部页签</strong>：通过设置<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdstabs#hdstabsfloatingstyle" target="_blank">HdsTabsFloatingStyle</a>的systemMaterialEffect参数，可为底部页签设置沉浸光感视效。</li>     </ul>    </div>    <div class="section" id="使用系统自适应的沉浸光感">     <a name="ZH-CN_TOPIC_0000002523835374__%E4%BD%BF%E7%94%A8%E7%B3%BB%E7%BB%9F%E8%87%AA%E9%80%82%E5%BA%94%E7%9A%84%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F"></a><a name="%E4%BD%BF%E7%94%A8%E7%B3%BB%E7%BB%9F%E8%87%AA%E9%80%82%E5%BA%94%E7%9A%84%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F"></a>     <h4>使用系统自适应的沉浸光感</h4>     <p>推荐使用系统自适应的沉浸光感效果，系统会根据当前设备的算力动态调整组件的材质效果，实现性能与显示效果的最佳平衡体验。</p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002523835374__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>[h2]开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">import { HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController, HdsNavigationMenuContentOptions, ScrollEffectType, hdsMaterial, } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from "@kit.ArkUI";</pre></li>      <li>       <p>创建HDS导航和底部页签组件。导航标题栏包含1个返回按钮和3个功能按钮，底部页签包含3个子项。</p>       <p>以下示例代码为底部页签和标题栏的4个按钮设置了沉浸光感效果，该效果将根据系统能力自适应调整。</p>       <pre class="typescript"> @Entry
 @Component
 export struct Index {
   private scrollerForScroll: Scroller = new Scroller();
   private controller: HdsTabsController = new HdsTabsController();

   private menus: HdsNavigationMenuContentOptions = {
     value: [{
       content: {
         label: 'menu1',
         icon: $r('sys.symbol.square_and_pencil'),
       }
     }, {
       content: {
         label: 'menu2',
         icon: $r('sys.symbol.star')
       },
     },{
       content: {
         label: 'menu3',
         icon: $r('sys.symbol.more')
       },
     }
     ],
   };

   build() {
     HdsNavigation() {
       HdsTabs({ controller: this.controller }) {
         ForEach(MENU_CONFIG, (item: MenuItem) =&gt; {
           TabContent() {
             Stack() {
               Scroll(this.scrollerForScroll) {
                 Column() {
                   Image($r("app.media.scenery01")).width('100%') // scenery为自定义资源，开发者需替换本地资源
                 }
               }
               .clipContent(ContentClipMode.SAFE_AREA)
               .height('100%')
             }
           }
           .tabBar(new BottomTabBarStyle({
             normal: item.symbolGlyph, selected: item.symbolGlyph1
           }, item.label))
         })
       }
       .barOverlap(true)
       .vertical(false)
       .barPosition(BarPosition.End)
       .barFloatingStyle({
         barBottomMargin: 28,
         systemMaterialEffect:  {
           materialType: hdsMaterial.MaterialType.ADAPTIVE,
           materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE // 底部悬浮页签沉浸光感效果跟随系统策略自适应
         }
       })
     }
     .mode(NavigationMode.Stack)
     .titleBar({
       content: {
         title: {
           mainTitle: 'MainTitle',
         },
         menu: this.menus,
       },
       style: {
         scrollEffectOpts: {
           enableScrollEffect: false,
           scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
         },
         systemMaterialEffect: {
           materialType: hdsMaterial.MaterialType.ADAPTIVE,
           materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE // 标题栏按钮沉浸光感效果跟随系统策略自适应
         },
       },
       avoidLayoutSafeArea: false,
       enableComponentSafeArea: false
     })
     .bindToScrollable([this.scrollerForScroll])
     .hideBackButton(false)
     .titleMode(HdsNavigationTitleMode.MINI)
     .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
   }
 }

 interface MenuItem {
   symbolGlyph: SymbolGlyphModifier,
   symbolGlyph1: SymbolGlyphModifier,
   label: string,
   defaultBgColor: ResourceColor,
   hoverBgColor: ResourceColor,
   pressBgColor: ResourceColor,
 };

 const MENU_CONFIG: MenuItem[] = [
   {
     symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.alarm_fill_1')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off'),
         $r('sys.color.ohos_id_color_bottom_tab_icon_auxcolor_off02')]),
     symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.alarm_fill_1')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_activated'), $r('sys.color.ohos_id_color_primary_contrary')]),
     label: '闹钟',
     defaultBgColor: Color.Transparent,
     hoverBgColor: $r('sys.color.ohos_id_color_hover'),
     pressBgColor: $r('sys.color.ohos_id_color_click_effect')
   },
   {
     symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.worldclock_fill_2')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off'),
         $r('sys.color.ohos_id_color_bottom_tab_icon_auxcolor_off02')]),
     symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.worldclock_fill_2')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_activated'), $r('sys.color.ohos_id_color_primary_contrary')]),
     label: '时钟',
     defaultBgColor: Color.Transparent,
     hoverBgColor: $r('sys.color.ohos_id_color_hover'),
     pressBgColor: $r('sys.color.ohos_id_color_click_effect')
   },
   {
     symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.stopwatch_2')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off'),
         $r('sys.color.ohos_id_color_bottom_tab_icon_auxcolor_off02')]),
     symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.stopwatch_2')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_activated'), $r('sys.color.ohos_id_color_primary_contrary')]),
     label: '秒表',
     defaultBgColor: Color.Transparent,
     hoverBgColor: $r('sys.color.ohos_id_color_hover'),
     pressBgColor: $r('sys.color.ohos_id_color_click_effect')
   }
 ];</pre></li>     </ol>    </div>    <div class="section" id="使用自定义沉浸光感效果">     <a name="ZH-CN_TOPIC_0000002523835374__%E4%BD%BF%E7%94%A8%E8%87%AA%E5%AE%9A%E4%B9%89%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%E6%95%88%E6%9E%9C"></a><a name="%E4%BD%BF%E7%94%A8%E8%87%AA%E5%AE%9A%E4%B9%89%E6%B2%89%E6%B5%B8%E5%85%89%E6%84%9F%E6%95%88%E6%9E%9C"></a>     <h4>使用自定义沉浸光感效果</h4>     <p>如果使用自定义沉浸光感的视觉效果，请先调用<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdsmaterial#getsystemmaterialtypes" target="_blank">getSystemMaterialTypes()</a>接口查询当前设备所支持的材质能力，再根据查询结果选用相应的材质效果枚举：</p>     <ol>      <li>如果查询结果显示当前设备支持IMMERSIVE材质类型，可选用EXQUISITE或GENTLE效果。</li>      <li>如果查询结果显示当前设备不支持IMMERSIVE材质类型，则建议使用SMOOTH效果，以降低卡顿和发热风险，保障用户体验。</li>     </ol>    </div>    <div class="section" id="开发步骤-1">     <a name="ZH-CN_TOPIC_0000002523835374__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4-1"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4-1"></a>     <h4>[h2]开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">import { HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController, HdsNavigationMenuContentOptions, ScrollEffectType, hdsMaterial, } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from "@kit.ArkUI";</pre></li>      <li>       <p>创建HDS导航和底部页签组件。导航标题栏包含1个返回按钮和3个功能按钮，底部页签包含3个子项。</p>       <p>以下示例代码为底部页签和标题栏的4个按钮设置了沉浸光感效果，根据设备所能支持的材质能力自定义动态切换显示效果。</p>       <pre class="typescript"> @Entry
 @Component
 export struct Index {
   private scrollerForScroll: Scroller = new Scroller();
   private controller: HdsTabsController = new HdsTabsController();
   @State customMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.EXQUISITE;

   private menus: HdsNavigationMenuContentOptions = {
     value: [{
       content: {
         label: 'menu1',
         icon: $r('sys.symbol.square_and_pencil'),
       }
     }, {
       content: {
         label: 'menu2',
         icon: $r('sys.symbol.star')
       },
     },{
       content: {
         label: 'menu3',
         icon: $r('sys.symbol.more')
       },
     }
     ],
   };

   aboutToAppear(): void {
     let materialTypes: Array&lt;hdsMaterial.MaterialType&gt; = hdsMaterial.getSystemMaterialTypes();
     if (materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) &lt; 0) {
       this.customMaterialLevel = hdsMaterial.MaterialLevel.SMOOTH; // 当前设备不支持IMMERSIVE材质类型，则使用SMOOTH效果
     }
   }

   build() {
     HdsNavigation() {
       HdsTabs({ controller: this.controller }) {
         ForEach(MENU_CONFIG, (item: MenuItem) =&gt; {
           TabContent() {
             Stack() {
               Scroll(this.scrollerForScroll) {
                 Column() {
                   Image($r("app.media.scenery01")).width('100%') // scenery为自定义资源，开发者需替换本地资源
                 }
               }
               .clipContent(ContentClipMode.SAFE_AREA)
               .height('100%')
             }
           }
           .tabBar(new BottomTabBarStyle({
             normal: item.symbolGlyph, selected: item.symbolGlyph1
           }, item.label))
         })
       }
       .barOverlap(true)
       .vertical(false)
       .barPosition(BarPosition.End)
       .barFloatingStyle({
         barBottomMargin: 28,
         systemMaterialEffect:  {
           materialType: hdsMaterial.MaterialType.ADAPTIVE,
           materialLevel: this.customMaterialLevel // 底部悬浮页签自定义沉浸光感材质效果
         }
       })
     }
     .mode(NavigationMode.Stack)
     .titleBar({
       content: {
         title: {
           mainTitle: 'MainTitle',
         },
         menu: this.menus,
       },
       style: {
         scrollEffectOpts: {
           enableScrollEffect: false,
           scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
         },
         systemMaterialEffect: {
           materialType: hdsMaterial.MaterialType.ADAPTIVE,
           materialLevel: this.customMaterialLevel // 标题栏按钮自定义沉浸光感材质效果
         },
       },
       avoidLayoutSafeArea: false,
       enableComponentSafeArea: false
     })
     .bindToScrollable([this.scrollerForScroll])
     .hideBackButton(false)
     .titleMode(HdsNavigationTitleMode.MINI)
     .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
   }
 }

 interface MenuItem {
   symbolGlyph: SymbolGlyphModifier,
   symbolGlyph1: SymbolGlyphModifier,
   label: string,
   defaultBgColor: ResourceColor,
   hoverBgColor: ResourceColor,
   pressBgColor: ResourceColor,
 };

 const MENU_CONFIG: MenuItem[] = [
   {
     symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.alarm_fill_1')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off'),
         $r('sys.color.ohos_id_color_bottom_tab_icon_auxcolor_off02')]),
     symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.alarm_fill_1')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_activated'), $r('sys.color.ohos_id_color_primary_contrary')]),
     label: '闹钟',
     defaultBgColor: Color.Transparent,
     hoverBgColor: $r('sys.color.ohos_id_color_hover'),
     pressBgColor: $r('sys.color.ohos_id_color_click_effect')
   },
   {
     symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.worldclock_fill_2')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off'),
         $r('sys.color.ohos_id_color_bottom_tab_icon_auxcolor_off02')]),
     symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.worldclock_fill_2')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_activated'), $r('sys.color.ohos_id_color_primary_contrary')]),
     label: '时钟',
     defaultBgColor: Color.Transparent,
     hoverBgColor: $r('sys.color.ohos_id_color_hover'),
     pressBgColor: $r('sys.color.ohos_id_color_click_effect')
   },
   {
     symbolGlyph: new SymbolGlyphModifier($r('sys.symbol.stopwatch_2')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_bottom_tab_icon_off'),
         $r('sys.color.ohos_id_color_bottom_tab_icon_auxcolor_off02')]),
     symbolGlyph1: new SymbolGlyphModifier($r('sys.symbol.stopwatch_2')).renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
       .fontColor([$r('sys.color.ohos_id_color_activated'), $r('sys.color.ohos_id_color_primary_contrary')]),
     label: '秒表',
     defaultBgColor: Color.Transparent,
     hoverBgColor: $r('sys.color.ohos_id_color_hover'),
     pressBgColor: $r('sys.color.ohos_id_color_click_effect')
   }
 ];</pre><strong>沉浸光感材质效果展示</strong>       <p><span><img originheight="587" originwidth="556" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/b6/v3/DQ_gZ8m_TYWaAx01ZAOShg/zh-cn_image_0000002552958354.png?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083917Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=AD18CC6125853011EB6DB781E764AF36AFF9B9CC09D749A01FCAB1F57C8CBC48"></span></p></li>     </ol>    </div>   </div>   <div></div></body></html>
