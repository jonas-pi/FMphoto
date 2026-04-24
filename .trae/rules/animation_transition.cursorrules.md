# HarmonyOS 动画与转场 - Cursor Rules

你正在为HarmonyOS应用开发相关功能。以下是你需要遵循的开发规则。

## 核心原则

-   **用户体验至上**：动画应提升用户感知流畅度，引导操作，而非分散注意力。
-   **性能优先**：动画必须流畅运行，避免卡顿，充分利用系统底层优化。
-   **利用系统能力**：优先使用HarmonyOS提供的原生动画和转场API，它们经过深度优化。
-   **设计意图匹配**：动画实现需准确传达设计师的意图和产品品牌调性。

## 推荐做法

### 代码结构
-   **声明式动画**：利用HarmonyOS的声明式UI特性，将动画逻辑与组件状态绑定，通过 `@State` 变量驱动动画。
-   **动画封装**：对于复杂的或重复使用的动画，考虑封装成独立的函数或自定义组件，提高复用性。

### 最佳实践
-   **提升感知流畅度**：
    *   **及时反馈**：手势操作（如点击、滑动）应立即产生动画反馈，避免视觉延迟。
    *   **符合物理直觉**：物体运动应符合真实世界规律，如使用弹簧曲线 (`Curve.Spring`) 增加自然感。
    *   **场景化选择**：
        *   **页面切换**：常用**左右位移遮罩动效**或**左右间隔位移动效**。
        *   **元素展开/收起**：如列表项展开，推荐**左右位移遮罩动效**；单体卡片/图表展开，推荐**一镜到底动效**。
        *   **搜索转场**：固定搜索区域可使用**淡入淡出**；非固定区域或强调搜索框连续性，使用**一镜到底/共享元素转场**。
-   **提升运行流畅度 (性能优化)**：
    *   **优先使用系统API**：`animateTo`、`PageTransition`、`SharedTransition`、`geometryTransition` 等。
    *   **GPU加速属性**：优先动画 `transform` (位移、旋转、缩放) 和 `opacity` (不透明度)，这些属性在GPU上合成，性能更高。
    *   **统一状态更新**：当多个动画参数相同时，在同一个 `animateTo` 块中更新所有相关状态变量，减少动画对象创建开销。
    *   **`renderGroup`**：对于包含复杂子组件的动画，将动画父组件设置为 `renderGroup(true)`，可优化渲染性能。
    *   **一镜到底动效**：
        *   **区分元素类型**：明确是共享元素（图片、图标）还是共享容器（卡片、列表）。
        *   **`geometryTransition`**：适用于简单的共享元素转场。
        *   **`Navigation` 自定义动画**：适用于复杂的共享容器转场（如卡片展开、图书翻页）。

## 禁止做法

-   **禁止频繁改变布局属性**：在动画过程中频繁改变组件的 `width`、`height`、`padding`、`margin` 等布局相关属性，会导致UI树的重新布局和重绘，严重影响动画性能。
-   **禁止滥用动画**：避免不必要的、过于花哨或分散用户注意力的动画。
-   **禁止内存泄漏**：不及时释放不再需要的动画资源，导致内存占用过高。

## 代码示例

### 推荐写法
```arkts
// 推荐写法：使用animateTo、transform、opacity、renderGroup，并统一状态更新
@Entry
@Component
struct GoodAnimationDemo {
  @State isAnimating: boolean = false;

  build() {
    Column() {
      Button('Toggle Animation')
        .margin(20)
        .onClick(() => {
          // 在一个animateTo中更新多个GPU加速属性
          animateTo({ duration: 500, curve: Curve.Spring }, () => {
            this.isAnimating = !this.isAnimating;
          });
        })
      
      Text('Hello HarmonyOS')
        .fontSize(24)
        .fontColor(Color.White)
        .width(100).height(100)
        .backgroundColor(Color.Blue)
        .borderRadius(this.isAnimating ? 50 : 10) // 动画非布局属性
        .opacity(this.isAnimating ? 0.5 : 1.0)    // 动画非布局属性
        .offset({ x: this.isAnimating ? 100 : 0, y: 0 }) // 动画非布局属性 (transform)
        .rotate({ angle: this.isAnimating ? 360 : 0 })   // 动画非布局属性 (transform)
        .renderGroup(true) // 复杂组件动画时可开启，优化渲染
    }
    .width('100%').height('100%')
  }
}

// 推荐写法：使用geometryTransition进行共享元素转场（概念性示例）
// PageA.ets
/*
Image('assets/thumbnail.jpg')
  .width(100).height(100)
  .geometryTransition('sharedImageId') // 标识共享元素
  .onClick(() => {
    Router.pushUrl({ url: 'pages/PageB' });
  });

// PageB.ets
Image('assets/full_image.jpg')
  .width('100%').height('100%')
  .geometryTransition('sharedImageId'); // 相同ID，系统自动匹配并执行转场
*/
```

### 避免写法
```arkts
// 避免写法：在动画中频繁改变布局属性，导致UI重绘和性能问题
@Entry
@Component
struct BadAnimationDemo {
  @State isExpanded: boolean = false;
  @State currentWidth: number = 100; // 避免直接动画这个属性

  build() {
    Column() {
      Button('Toggle Expand')
        .margin(20)
        .onClick(() => {
          animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
            // 避免：直接改变 width/height 等布局属性
            // 这会导致整个UI树重新计算布局并重绘，性能开销大
            this.currentWidth = this.isExpanded ? 200 : 100; 
            this.isExpanded = !this.isExpanded;
          });
        })
      
      Text('Content')
        .fontSize(20)
        .width(this.currentWidth) // 频繁改变此属性会导致性能下降
        .height(100)
        .backgroundColor(Color.Red)
    }
    .width('100%').height('100%')
  }
}
```

## 注意事项

-   **性能监控**：开发过程中务必使用DevEco Studio的性能分析工具（如CPU Profiler, UI Tracer）监控动画的FPS、CPU和内存占用，确保动画稳定在60 FPS。
-   **可访问性**：考虑为对动画敏感的用户提供关闭或简化动画的选项，提升应用包容性。
-   **内存管理**：对于复杂的自定义动画或资源密集型动画，注意及时释放不再需要的动画对象或图片资源。
-   **跨设备适配**：在不同尺寸和性能的HarmonyOS设备上测试动画效果，确保一致的用户体验。