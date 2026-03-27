# HarmonyOS 布局与弹窗 - Cursor Rules

你正在为HarmonyOS应用开发相关功能。以下是你需要遵循的开发规则。

## 核心原则

-   **性能优先，流畅体验**: 优化布局结构，减少计算开销，确保界面渲染高效，提供流畅的用户交互。
-   **组件化与复用**: 封装通用模块，利用系统组件能力，提高开发效率和UI一致性。
-   **精确控制交互**: 针对弹窗、手势等复杂场景，精细化控制交互行为和生命周期。
-   **数据驱动视图**: 视图应随数据变化动态更新，尤其在长列表和动态内容场景。

## 推荐做法

### 代码结构
-   将复杂UI模块（如轮播指示器、瀑布流列表项）拆分为独立组件，实现高内聚低耦合。
-   长列表视图采用数据驱动，根据数据类型动态渲染不同的`ListItem`或自定义组件。

### 最佳实践
-   **布局与列表**:
    *   长列表优先使用`LazyForEach`进行懒加载和组件复用，替代`ForEach`。
    *   当`List`嵌套在`Scroll`内时，为其明确设置固定的`width`和`height`。
    *   精简UI节点数量，避免不必要的布局嵌套，优先选择扁平化布局。
    *   通过设置固定宽高创建“布局边界”，限制UI更新时的布局计算范围。
    *   `Grid`拖拽交换时启用`editMode(true)`和`supportAnimation(true)`，并绑定`LongPressGesture`和`PanGesture`。
    *   列表交互（下拉刷新、上滑加载更多、吸顶）利用`Refresh`、`onReachEnd()`和`sticky`属性实现。
-   **弹窗**:
    *   复杂评论回复弹窗优先选用`Navigation Dialog`以更好地适配软键盘切换。
    *   通用弹窗使用`DialogHub`进行统一管理，并精细控制其关闭行为（如侧滑、点击外部关闭）。
    *   弹窗应支持自定义进出场动画，并妥善处理焦点管理和键盘避让。
-   **交互与显示**:
    *   `Swiper`需要自定义进度条指示器时，禁用自带`indicator(false)`。
    *   图片预览实现“跟手”效果，利用`matrix4`和`translate`进行精确缩放和平移。
    *   文本展开/折叠功能使用`measureTextSize()`精确计算文本高度和截断位置。

## 禁止做法

-   直接依赖`Swiper`自带指示器实现自定义进度条等复杂视觉效果。
-   将`CustomDialog`作为复杂评论回复弹窗主体，因其软键盘避让行为不可控，可能导致界面抖动。
-   在长列表场景下使用`ForEach`，可能导致性能瓶颈和内存占用过高。
-   对重要提示或需用户确认的弹窗，允许侧滑或点击外部区域关闭，可能导致用户误操作。
-   过度嵌套布局组件，增加UI渲染的计算开销。

## 代码示例

### 推荐写法
```arkts
// Swiper自定义指示器（禁用自带）
Swiper(this.swiperController) {
  LazyForEach(this.data, (item: PhotoData) => {
    Image($r(`app.media.` + item.id))
      .width('100%').height('100%')
  }, (item: PhotoData) => JSON.stringify(item))
}
.autoPlay(true)
.interval(3000)
.indicator(false) // 禁用自带指示器

// 长列表懒加载
List() {
  LazyForEach(this.data, (item: ListItemData, index: number) => {
    ListItem() {
      Text(item.content).fontSize(16)
    }
  }, (item: ListItemData) => item.id.toString())
}
.onReachEnd(() => {
  // 触发加载更多数据
  this.loadMoreData();
})
```

### 避免写法
```arkts
// 避免在长列表中使用 ForEach，可能导致性能问题
List() {
  ForEach(this.data, (item: ListItemData) => {
    ListItem() {
      Text(item.content).fontSize(16)
    }
  })
}

// 避免将 CustomDialog 用于需要复杂软键盘交互的场景（如评论输入），
// 因其软键盘避让行为不可配置，可能导致界面抖动。
// CustomDialog.open({ builder: () => { /* 评论输入UI */ } });
```

## 注意事项

-   充分测试在不同设备形态（如折叠屏）、屏幕尺寸和系统输入法下的弹窗行为和布局表现。
-   所有数据加载操作应为异步且非阻塞，并提供清晰的加载中、加载完成/失败状态反馈。
-   动画效果应自然流畅，时长适中，避免过度或突兀的视觉干扰。
-   精确的UI测量（如文本高度、图片位置）是实现复杂交互（如“跟手”、文本截断）的关键，需合理使用`measureTextSize()`等API。