# 设置附带横滑的列表样式

- 页面标题: 设置附带横滑的列表样式
- slug: `ui-design-set-hds-slide-horizon-listitem`
- 原始地址: https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-set-hds-slide-horizon-listitem
- 文档ID: `dd84f26250d34d97a960bbc442122108`
- 更新时间: 2026-04-22 06:37:02

## 锚点目录

- 场景介绍
- 开发步骤

## 正文

<!-- 华为接口返回为 HTML，这里原样保留，便于后续继续转换或抽取。 -->

<html><head></head><body><a name="ZH-CN_TOPIC_0000002553358711"></a><a name="ZH-CN_TOPIC_0000002553358711"></a>   <h1>设置附带横滑的列表样式</h1>   <div>    <div class="section" id="场景介绍">     <a name="ZH-CN_TOPIC_0000002553358711__%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a><a name="%E5%9C%BA%E6%99%AF%E4%BB%8B%E7%BB%8D"></a>     <h4>场景介绍</h4>     <p>从6.0.0(20) Beta1版本开始，新增支持设置附带横滑的列表样式。</p>     <p>应用使用<a href="https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ui-design-hdslistitem" target="_blank">HdsListItem</a>组件实现多设备上的系统列表的横滑动效按钮的内容和样式。</p>     <p><span><img originheight="168" originwidth="437" src="https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_scene_100_1/7f/v3/A2bcB-zuSmOoTxkbPNz1Zw/zh-cn_image_0000002583478349.gif?HW-CC-KV=V1&amp;HW-CC-Date=20260426T083916Z&amp;HW-CC-Expire=86400&amp;HW-CC-Sign=BF99D8CA07CEB66BFD4828B445C2E949A0E10C96C01891314C1C12CF9015825E"></span></p>    </div>    <div class="section" id="开发步骤">     <a name="ZH-CN_TOPIC_0000002553358711__%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a><a name="%E5%BC%80%E5%8F%91%E6%AD%A5%E9%AA%A4"></a>     <h4>开发步骤</h4>     <ol>      <li>       <p>导入相关模块。</p>       <pre class="typescript">import { promptAction, SymbolGlyphModifier, TextModifier } from '@kit.ArkUI';
import { HdsListItem } from '@kit.UIDesignKit';</pre></li>      <li>       <p>简单配置页面的布局，调用HdsListItem的接口绘制列表的横滑动效按钮的内容和样式。</p>       <pre class="typescript">@Entry
@Component
struct HdsListItemExample {
  @State dataSource: LazyDataSource&lt;Item&gt; = new LazyDataSource();
  @State dataArr: Array&lt;Item&gt; = [];
  @State EndOffset: number = 0;
  private scroller: Scroller = new Scroller();

  build() {
    Column() {
      List({ space: 10, scroller: this.scroller }) {
        LazyForEach(this.dataSource, (item: Item) =&gt; {
          HdsListItem({
            hdsListItemCard: {
              textItem: {
                primaryText: {
                  text: 'Primary Text',
                  modifier: new TextModifier().fontColor(Color.Orange).fontSize(16),
                }
              }
            },
            swipeActionOptions: {
              icons: [
                {
                  icon: new SymbolGlyphModifier($r('sys.symbol.share')).fontColor([Color.Red]).fontSize(16),
                  backgroundColor: Color.Green,
                  onAction: () =&gt; {
                    promptAction.openToast({ message: '点击share按钮', duration: 100 });
                  },
                },
                {
                  icon: new SymbolGlyphModifier($r('sys.symbol.plus_square_on_square')),
                  backgroundColor: Color.Orange,
                  onAction: () =&gt; {
                    promptAction.openToast({ message: '点击copy按钮', duration: 100 });
                  },
                },
                {
                  icon: new SymbolGlyphModifier($r('sys.symbol.plus_square_dashed_on_square'))
                          .symbolEffect(new BounceSymbolEffect(), true),
                  onAction: () =&gt; {
                    promptAction.openToast({ message: '点击paste按钮', duration: 100 });
                  },
                },
              ],
              deleteIconOptions: {
                backgroundColor: Color.Red, //  ---修改背景色
                iconColor: Color.Gray, //  ---- 修改垃圾桶的颜色
                onAction: () =&gt; {
                  promptAction.openToast({ message: '点击删除按钮', duration: 100 });
                }, //   --点击回调
              },
              fullDeleteOptions: {
                isFullDelete: true, // --- 划动距离超过划出组件大小后自动触发删除，默认是false
                onFullDeleteAction: () =&gt; {
                  promptAction.openToast({ message: '触发自动删除', duration: 100 });
                  this.getUIContext()?.animateTo({
                    duration: 350,
                  }, () =&gt; {
                    this.dataSource.deleteItem(item)
                  });
                }, //   -- 触发删除时的回调
              },
            }
          })
        }, (item: Item) =&gt; item.data)
      }
      .scrollBar(BarState.Off)
      .onDidScroll((scrollOffset: number) =&gt; {
        this.EndOffset = scrollOffset
      })
      .margin(10)
      .width('100%')
      .height('100%')
    }
    .backgroundColor('#0D182431')
    .width('100%')
    .height('100%')
  }

  aboutToAppear() {
    for (let i = 0; i &lt; 2; i++) {
      this.dataSource.pushItem(new Item(i + ''));
      this.dataArr.push(new Item(i + ''));
    }
  }
}

class Item {
  constructor(data: string) {
    this.data = data;
  }

  public data: string = '';
}

export class LazyDataSource&lt;T&gt; implements IDataSource {
  private elements: T[];
  private listeners: Set&lt;DataChangeListener&gt;;

  constructor(elements: T[] = []) {
    this.elements = elements;
    this.listeners = new Set();
  }

  public totalCount(): number {
    return this.elements.length;
  }

  public getData(index: number): T {
    return this.elements[index];
  }

  public indexOf(item: T): number {
    return this.elements.indexOf(item);
  }

  public pinItem(item: T, index: number): void {
    this.elements.splice(index, 1);
    this.elements.unshift(item);
    this.listeners.forEach(listener =&gt; listener.onDataReloaded());
  }

  public pushItem(item: T) {
    this.elements.push(item);
    this.listeners.forEach(listener =&gt; listener.onDataAdd(this.elements.length - 1));
  }

  public deleteItem(item: T): void {
    const index = this.elements.indexOf(item);
    if (index &lt; 0) {
      return;
    }
    this.elements.splice(index, 1);
    this.listeners.forEach(listener =&gt; listener.onDataDelete(index));
  }

  public deleteItemByIndex(index: number): void {
    this.elements.splice(index, 1);
    this.listeners.forEach(listener =&gt; listener.onDataDelete(index));
  }

  public registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.add(listener);
  }

  public unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners.delete(listener);
  }
}</pre></li>     </ol>    </div>   </div>   <div></div></body></html>
