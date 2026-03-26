# HarmonyOS 手势与导航 - Cursor Rules

你正在为HarmonyOS应用开发相关功能。以下是你需要遵循的开发规则。

## 核心原则

-   **用户体验优先**: 确保所有手势和导航逻辑符合用户预期，提供流畅直观的交互体验。
-   **深入理解机制**: 掌握触摸事件分发、手势响应链及页面栈管理等底层原理。
-   **模块化与可维护**: 采用清晰的代码结构和编程模式，提高代码复用性和可维护性。
-   **性能与资源优化**: 合理利用框架特性，避免不必要的资源消耗和性能瓶颈。

## 推荐做法

### 代码结构
-   **页面路由注册**: 所有可跳转的页面都应使用 `@HMRouter` 注解进行注册，并配置唯一的 `pageUrl` 作为路由标识。
-   **UI组件封装**: 对于底部导航栏项等可复用UI元素，建议封装为 `@Builder` 方法，提高代码复用性和可读性。

### 最佳实践
-   **手势事件冲突解决**:
    -   **精准控制触摸测试**: 利用组件的 `hitTestBehavior` 属性（`Default`、`Transparent`、`Block`）来改变组件的触摸测试行为，从而影响事件响应链的构建。
        -   `Transparent`: 允许事件穿透当前组件，继续向底层和父组件传递。
        -   `Block`: 如果命中，独占事件，完全阻塞事件向其他组件传递。
    -   **阻止事件冒泡**: 在触摸或手势事件回调中，调用 `event.stopPropagation()` 可以立即停止事件向上冒泡，阻止父组件响应。
    -   **区分事件类型**: 明确区分基础触摸事件 (`onTouch`) 和高级手势事件 (如 `onClick`, `onPan`)，根据需求选择合适的处理方式。
-   **页面跳转与数据传递**:
    -   **标准跳转**: 使用 `HMRouterMgr.push()` 进行页面入栈跳转，`HMRouterMgr.replace()` 替换当前页面。
    -   **传递参数**: 通过 `push/replace` 方法的 `param` 参数向目标页面传递数据，在目标页面的 `aboutToAppear` 生命周期中通过 `HMRouterMgr.getCurrentParam()` 获取。
    -   **接收返回结果**: 在 `push/replace` 方法的第二个参数中配置 `onResult` 回调函数，用于接收目标页面返回的数据。务必通过 `HMPopInfo.srcPageInfo.name` 判断返回源。
    -   **多栈导航**: 当应用中存在多个 `HMNavigation` 组件时，务必在 `push/replace` 时指定 `navigationId`，确保跳转发生在正确的页面栈中。
-   **底部导航实现**:
    -   **使用 `Tabs` 组件**: 采用 `Tabs` 组件作为底部导航的主要容器，设置 `barPosition: BarPosition.End` 将导航栏固定在底部。
    -   **自定义导航项**: 通过 `TabContent` 的 `tabBar` 属性自定义每个页签的图标（区分选中/未选中态）和文字。
    -   **样式优化**: 合理设置 `Tabs` 的 `barHeight`、`backgroundColor` 和 `barMode` (如 `Fixed`)，以提供良好的视觉和点击区域。
-   **高级路由功能**: 考虑利用 `HMRouter` 提供的路由拦截（如登录校验）、单例页面管理和弹窗页面等功能，提升应用健壮性和用户体验。

## 禁止做法

-   **手势冲突不处理**: 在存在嵌套组件和多手势场景下，不理解触摸事件冒泡机制，不使用 `hitTestBehavior` 或 `stopPropagation()`，导致交互逻辑混乱。
-   **过度阻塞**: 滥用 `HitTestMode.Block` 或 `event.stopPropagation()`，导致用户预期外的交互被阻断，影响可用性。
-   **多导航栈路由混乱**: 在应用存在多个 `HMNavigation` 组件的情况下，进行页面跳转时未指定 `navigationId`，导致页面跳转到错误的导航栈。

## 代码示例

### 推荐写法
```arkts
// 手势冲突解决：子组件独占点击事件，阻止冒泡
Column()
  .width('100%').height(100).backgroundColor(Color.Blue)
  .onClick(() => console.log('Parent Clicked')) { // 父组件点击事件
    Button('Child Button')
      .width(100).height(40).margin(20)
      .onClick((event: ClickEvent) => { // 子组件点击事件
        console.log('Child Button Clicked');
        event.stopPropagation(); // 阻止事件向上冒泡，父组件不再响应
      })
      .hitTestBehavior(HitTestMode.Block); // 确保子组件区域优先响应
  }

// 页面跳转、传参及接收返回结果
HMRouterMgr.push({
  pageUrl: 'pages/DetailPage', // 目标页面路由
  navigationId: 'mainNav', // 多HMNavigation场景下指定ID
  param: { productId: 101, category: 'Electronics' } // 传递参数
}, {
  onResult: (info: HMPopInfo) => { // 接收返回结果
    if (info.srcPageInfo.name === 'pages/DetailPage') { // 判断返回来源
      console.log(`Returned from DetailPage with result: ${JSON.stringify(info.result)}`);
    }
  }
});

// 底部导航栏项的Builder封装
@Builder TabItem(text: Resource, icon: Resource, isActive: boolean) {
  Column() {
    Image(isActive ? icon : icon) // 根据isActive切换选中/非选中图标
      .width(24).height(24)
    Text(text)
      .fontSize(10)
      .fontColor(isActive ? Color.Blue : Color.Gray)
  }
  .width('100%').height('100%').justifyContent(FlexAlign.Center)
}

// 底部导航Tabs组件结构
Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
  TabContent() { Text('Home Content') }
    .tabBar(this.TabItem($r('app.string.home'), $r('app.media.home_icon'), this.currentIndex === 0))
  TabContent() { Text('Profile Content') }
    .tabBar(this.TabItem($r('app.string.profile'), $r('app.media.profile_icon'), this.currentIndex === 1))
}
.barHeight(56)
.backgroundColor(Color.White)
.barMode(BarMode.Fixed)
.onChange(index => this.currentIndex = index)
```

### 避免写法
```arkts
// 避免：不处理手势冲突，导致父子组件同时响应或响应顺序混乱
Column()
  .width('100%').height(100).backgroundColor(Color.Red)
  .onClick(() => console.log('Parent Clicked Without StopPropagation')) {
    Button('Child Button')
      .width(100).height(40).margin(20)
      .onClick(() => console.log('Child Clicked Without StopPropagation'));
  } // 点击子按钮时，父子组件的onClick都会被触发，可能不符合预期。

// 避免：多导航栈场景下，不指定navigationId，可能导致跳转到错误的栈
// 假设应用中存在多个HMNavigation组件，此处未指定navigationId
HMRouterMgr.push({ pageUrl: 'pages/AnotherPage' }); 
```

## 注意事项

-   **手势控制谨慎**: `hitTestBehavior` 和 `stopPropagation()` 是强大的手势控制工具，但需谨慎使用，过度阻塞可能导致用户交互失效。务必充分测试。
-   **组件树理解**: 深入理解组件树的结构和布局顺序对手势事件的分发和响应链的构建至关重要。
-   **`onResult` 源判断**: `onResult` 回调会在任何页面 `pop` 回当前页面时触发，务必通过 `HMPopInfo.srcPageInfo.name` 属性精确判断返回源，避免处理不相关的返回数据。
-   **导航图标清晰**: 底部导航的图标和文字应保持清晰、简洁，并提供选中和未选中两种状态，以提升用户识别度和交互体验。
-   **调试与性能监控**: 在开发和测试过程中，利用HarmonyOS提供的调试工具和性能分析器，监控手势响应和页面跳转的性能，及时发现并解决潜在问题。