# 开发实例

- 页面标题: 开发实例
- slug: `ui-design-navigation-dynamic-blur-demo`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-navigation-dynamic-blur-demo
- 文档ID: `ee71f617eb704c0abe7efb58f4ebb63e`
- 更新时间: 2026-04-22 06:37:22

## 锚点目录

- 无

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553198739"></a><a name="ZH-CN_TOPIC_0000002553198739"></a>  <h1>开发实例</h1> <div><ol><li><p>在首页创建一级导航，适用于需要构建具有导航结构的主界面，支持动态标题栏样式切换与页面跳转功能。通过titleBar接口设置导航栏的内容和样式，包括标题、菜单项、返回按钮等元素。通过pushPath路由方法跳转至二级导航页面。</p>  <pre class="typescript">// 模块导入
// 从6.0.2(22)版本开始，无需手动导入HdsNavigationAttribute。具体请参考HdsNavigation的导入模块说明。
import { HdsNavigation, ScrollEffectType, HdsNavigationTitleMode, HdsNavigationAttribute } from '@kit.UIDesignKit';

@Entry
@Component
struct Index {
  private arr: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
  @Provide('pageInfos') pageInfos: NavPathStack = new NavPathStack();
  scroller: Scroller = new Scroller();

  build() {
    HdsNavigation(this.pageInfos) { // 创建HdsNavigation组件
      Stack() {
        Button('pushPath', { stateEffect: true, type: ButtonType.Capsule })
          .width('80%')
          .height(40)
          .margin({ top: '5%', right: '50vp', left: '50vp' })
          .onClick(() =&gt; {
            this.pageInfos.pushPath({ name: 'pageOne' });
          })
      }
      .zIndex(5)

      List({ space: 12, initialIndex: 0, scroller: this.scroller }) {
        ForEach(this.arr, (item: number) =&gt; {
          ListItem() {
            Column() {
              Row({ space: 8 }) {
                Button() {
                  SymbolGlyph($r('sys.symbol.wifi'))
                    .fontColor([$r('sys.color.icon_on_primary')])
                    .fontSize(24)
                }
                .width(35)
                .height(35)

                Text('list_' + item)
                  .width('100%')
                  .height(72)
                  .fontSize(16)
                  .fontWeight(500)
              }

              Divider().margin({ left: 40 })
            }
          }
          .height(56)
        }, (item: number) =&gt; item.toString())
      }
      .margin({ left: 16, right: 16 })
      .clip(false) // 设置不对子组件超出当前组件范围外的区域进行裁剪，使内容区可以穿透到标题栏下方
      .cachedCount(3, true) // 设置列表中ListItem/ListItemGroup的预加载数量，列表穿透到标题栏下方不会消失
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .titleBar({
      // HdsNavigation标题栏设置
      enableComponentSafeArea: true, // 将标题栏设置为组件级安全区，内容区可避让标题栏
      style: {
        // HdsNavigation标题栏样式设置
        // 标题栏动态模糊样式：通用模糊
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
        },
      },
      content: {
        // HdsNavigation标题栏内容区设置
        title: {
          // HdsNavigation标题栏标题设置
          mainTitle: 'MainTitle',
        },
        menu: {
          // HdsNavigation标题栏菜单项设置
          value: [{
            // 第一个菜单项内容设置
            content: {
              label: 'menu1',
              icon: $r('sys.symbol.ohos_wifi'),
              isEnabled: true,
            },
            badge: {
              count: 1,
            }
          }, {
            // 第二个菜单项内容设置
            content: {
              label: 'menu2',
              icon: $r('sys.symbol.ohos_lock'),
              isEnabled: true,
              action: () =&gt; {
                console.info(`HDS_NAV HELLO 2`);
              }
            }
          }, {
            // 第三个菜单项内容设置
            content: {
              label: 'menu3',
              icon: $r('sys.symbol.speaker_plus'),
            }
          }, {
            content: {
              // 第三个菜单项内容设置
              label: 'menu4',
              icon: $r('sys.symbol.ohos_star'),
            }
          }]
        },
      }
    })
    .titleMode(HdsNavigationTitleMode.MINI)
    .hideBackButton(true)
    .bindToScrollable([this.scroller]) // 绑定导航组件和可滚动容器组件
  }
}</pre>  </li><li><p>在PageOne页面创建二级导航组件。通过titleBar接口设置HdsNavDestination标题栏HarmonyOS风格化样式及内容设置。展示NavPathStack路由使用示例。</p>  <pre class="typescript">// PageOne.ets
// 模块导入
// 从6.0.2(22)版本开始，无需手动导入HdsNavDestinationAttribute。具体请参考HdsNavDestination的导入模块说明。
import { HdsNavDestination, HdsNavDestinationAttribute } from '@kit.UIDesignKit';

@Builder
export function PageOneBuilder() {
  PageOne()
}

@Component
export struct PageOne {
  @Consume('pageInfos') pageInfos: NavPathStack;
  private arr: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
  scroller: Scroller = new Scroller();
  listScroller: Scroller = new Scroller();

  build() {
    HdsNavDestination() { // 创建HdsNavDestination组件
      Scroll(this.scroller) { // HdsNavDestination内容区设置可滚动容器组件，用于实现内容区滚动联动标题栏动态模糊样式
        Column() {
          Button('pushPath', { stateEffect: true, type: ButtonType.Capsule })
            .width('80%')
            .height(40)
            .margin({
              top: '5%',
              right: '50vp',
              left: '50vp',
              bottom: '5%'
            })
            .onClick(() =&gt; {
              this.pageInfos.pushPath({ name: 'pageTwo' }); // 将name指定的HdsNavDestination页面信息入栈
            })
          Button('popToName', { stateEffect: true, type: ButtonType.Capsule })
            .width('80%')
            .height(40)
            .margin(20)
            .onClick(() =&gt; {
              this.pageInfos.popToName('pageTwo'); // 回退路由栈到首个名为name的HdsNavDestination页面
            })
          Button('popToIndex', { stateEffect: true, type: ButtonType.Capsule })
            .width('80%')
            .height(40)
            .margin(20)
            .onClick(() =&gt; {
              this.pageInfos.popToIndex(1); // 回退路由栈到index指定的HdsNavDestination页面
            })
          Button('moveIndexToTop', { stateEffect: true, type: ButtonType.Capsule })
            .width('80%')
            .height(40)
            .margin(20)
            .onClick(() =&gt; {
              this.pageInfos.moveIndexToTop(1); // 将index指定的HdsNavDestination页面移到栈顶
            })
          Button('clear', { stateEffect: true, type: ButtonType.Capsule })
            .width('80%')
            .height(40)
            .margin(20)
            .onClick(() =&gt; {
              this.pageInfos.clear(); // 清除栈中所有页面
            })
          List({ space: 12, initialIndex: 0 }) {
            ForEach(this.arr, (item: number) =&gt; {
              ListItem() {
                Column() {
                  Row({ space: 8 }) {
                    Button() {
                      SymbolGlyph($r('sys.symbol.wifi'))
                        .fontColor([$r('sys.color.icon_on_primary')])
                        .fontSize(24)
                    }
                    .width(35)
                    .height(35)

                    Text('list_' + item)
                      .width('100%')
                      .height(72)
                      .fontSize(16)
                      .fontWeight(500)
                  }

                  Divider().margin({ left: 40 })
                }
              }
              .height(56)
              .borderRadius(24)
            }, (item: number) =&gt; item.toString())
          }
          .edgeEffect(EdgeEffect.None)
          .scrollBar(BarState.Off)
          .width('100%')
          .height('100%')
          .cachedCount(3, true) // 设置列表中ListItem/ListItemGroup的预加载数量，列表穿透到标题栏下方不会消失
          .clip(false) // 设置不对子组件超出当前组件范围外的区域进行裁剪，使内容区可以穿透到标题栏下方
          .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.PARENT_FIRST })
        }
      }
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off)
      .margin({ left: 16, right: 16 })
      .clip(false) // 设置不对子组件超出当前组件范围外的区域进行裁剪，使内容区可以穿透到标题栏下方
    }
    .titleBar({
      enableComponentSafeArea: true, // 将标题栏设置为组件级安全区，内容区可避让标题栏
      content: {
        // HdsNavigation标题栏内容区设置
        title: {
          // HdsNavigation标题栏标题设置
          mainTitle: 'PageOne',
        },
        // HdsNavigation标题栏返回按钮设置
        backIcon: {
          label: 'backIcon', // 无障碍播报内容
          componentId: 'backIconId', // 返回按钮id
        },
        menu: {
          // HdsNavigation标题栏菜单设置
          value: [{
            // 第一个菜单项内容设置
            content: {
              label: 'menu1',
              icon: $r('sys.symbol.ohos_star'),
            }
          }, {
            // 第二个菜单项内容设置
            content: {
              label: 'menu2',
              icon: $r('sys.symbol.ohos_circle'),
            },
            badge: {
              value: '66'
            }
          }]
        },
      }
    })
    .bindToNestedScrollable([{ parent: this.scroller, child: this.listScroller }]) // 绑定导航组件和可滚动容器组件
  }
}</pre>  </li><li><p>在PageTwo页面创建二级导航组件。</p>  <pre class="typescript">// PageTwo.ets
// 模块导入
// 从6.0.2(22)版本开始，无需手动导入HdsNavDestinationAttribute。具体请参考HdsNavDestination的导入模块说明。
import { HdsNavDestination, HdsNavDestinationAttribute } from '@kit.UIDesignKit';

@Builder
export function PageTwoBuilder() {
  PageTwo()
}

@Component
export struct PageTwo {
  @Consume('pageInfos') pageInfos: NavPathStack;
  private stack: NavPathStack | null = null;
  private name: string = '';
  scroller: Scroller = new Scroller();

  build() {
    HdsNavDestination() { // 创建HdsNavDestination组件
      Scroll(this.scroller) { // HdsNavDestination组件内容区设置
        Button('pushPathByName', { stateEffect: true, type: ButtonType.Capsule })
          .width('80%')
          .height(40)
          .margin(20)
          .onClick(() =&gt; {
            this.pageInfos.pushPathByName('pageOne', null); // 将name指定的HdsNavDestination页面信息入栈
          })
      }
      .align(Alignment.Top)
      .clip(false) // 设置不对子组件超出当前组件范围外的区域进行裁剪，使内容区可以穿透到标题栏下方
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .titleBar({
      enableComponentSafeArea: true, // 将标题栏设置为组件级安全区，内容区可避让标题栏
      // HdsNavDestination组件标题栏设置
      content: {
        title: {
          mainTitle: 'PageTwo'
        },
        menu: {
          value: [{
            content: {
              label: 'menu1',
              icon: $r('sys.symbol.trunk'),
            }
          }]
        },
      },
    })
    .bindToScrollable([this.scroller]) // 绑定导航组件和可滚动容器组件
    .onReady((ctx: NavDestinationContext) =&gt; {
      // 在NavDestination中能够拿到传来的NavPathInfo和当前所处的NavPathStack
      try {
        this.name = ctx?.pathInfo?.name;
        this.stack = ctx.pathStack;
      } catch (e) {
        console.error(`testTag onReady catch exception code:
         ${JSON.stringify(e.code)}, message: ${JSON.stringify(e.message)}`);
      }
    })
  }
}</pre>  </li><li><p>工程entry/src/main/module.json5文件中的“module”下新增如下配置，用于页面跳转。</p>  <pre class="typescript">"routerMap": "$profile:route_map"</pre>  </li><li><p>工程entry/src/main/resources/base/profile目录下增加route_map.json文件。</p>  <pre class="typescript">{
  "routerMap": [
    {
      "name": "pageOne",
      "pageSourceFile": "src/main/ets/pages/PageOne.ets",
      "buildFunction": "PageOneBuilder",
      "data": {
        "description": "this is pageOne"
      }
    },
    {
      "name": "pageTwo",
      "pageSourceFile": "src/main/ets/pages/PageTwo.ets",
      "buildFunction": "PageTwoBuilder"
    }
  ]
}</pre>  </li></ol> <p><span><img height="626.8202220000001" originheight="664" originwidth="317" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/2e/v3/lbJgI-rvTSOsUbBm4AwonA/zh-cn_image_0000002583438383.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083914Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=65E423D2825D5864C771BA93C4C001A6A40EA7D87035883FDC0D91307280DEDF" title="点击放大" width="299.25"></span></p> </div> <div></div></body></html>
