# HarmonyOS 组件封装与复用 - Cursor Rules

你正在为HarmonyOS应用开发相关功能。以下是你需要遵循的开发规则。

## 核心原则

-   **性能优先**: 通过组件复用和动态加载，最小化渲染开销，提升用户体验。
-   **高效复用**: 封装通用组件，减少重复代码，提高开发效率和一致性。
-   **统一封装**: 采用统一的组件封装模式，确保接口简洁，易于维护和扩展。
-   **职责清晰**: 组件职责单一，逻辑内聚，易于理解和测试。

## 推荐做法

### 代码结构
-   **公用组件封装**: 利用ArkTS的 `attributeModifier` 机制，为系统组件提供扩展属性，实现链式调用风格的封装，保持与系统组件一致的使用体验，避免冗长入参。
-   **动态组件管理**: 对于高性能要求的动态布局（如列表流广告、复杂自定义布局），推荐使用 `NodeController` 配合 `FrameNode` 进行组件的动态创建、挂载和卸载，实现局部渲染与高效更新。
-   **可复用组件声明**: 使用 `@Reusable` 装饰器标记可复用的自定义组件，并实现 `aboutToReuse()` 生命周期回调，在此回调中根据新数据刷新组件UI，而非在构造函数中。
-   **弹窗组件封装**: 统一使用 `UIContext` 获取 `PromptAction` 对象来管理自定义弹窗的显示与隐藏，确保弹窗的生命周期和交互行为规范。

### 最佳实践
-   **性能优化**:
    *   复杂动态布局场景优先使用 `FrameNode`，避免声明式范式中 `diff` 算法带来的性能开销。
    *   利用应用空闲时间（如 `onIdle()`）进行组件预创建，减少用户感知到的加载延迟。
-   **数据传递**:
    *   在可复用组件中传递复杂数据时，优先使用 `@Link` 或 `@ObjectLink` 装饰器传递引用，避免 `@Prop` 导致的深拷贝，提升性能。
    *   避免在 `aboutToReuse()` 中重复赋值 `@Link`/`@ObjectLink`/`@Prop` 等自动更新的状态变量。
-   **复用策略**: 为 `@Reusable` 组件设置明确的 `reuseId` 属性，进行精细化的组件复用分组，确保相同类型或结构的组件能被有效复用。

## 禁止做法

-   **过度依赖声明式范式处理复杂动态布局**: 在需要频繁增删改查组件、或组件树深度和复杂度较高时，仅依赖声明式范式可能导致 `diff` 算法开销过大，影响性能和帧率。
-   **将函数作为参数传递给 `@Reusable` 组件**: 这可能导致组件无法有效复用或引起不必要的渲染更新。
-   **为 `@Reusable` 组件的复杂数据使用 `@Prop`**: `@Prop` 会进行深拷贝，在数据量大或更新频繁时导致性能下降。
-   **传统封装方式造成冗长入参**: 避免通过大量 `@Prop` 定义自定义组件属性，导致调用方入参列表过长且与系统组件使用习惯不符。

## 代码示例

### 推荐写法
```arkts
// 推荐的公用组件封装：使用 AttributeModifier 保持链式调用风格
class MyButtonModifier implements AttributeModifier<Button> {
  private text: string;
  private onClickFunc: () => void;

  constructor(text: string, onClick: () => void) {
    this.text = text;
    this.onClickFunc = onClick;
  }

  applyNormalAttribute(instance: Button) {
    instance.backgroundColor(Color.Blue)
            .fontColor(Color.White)
            .fontSize(16)
            .onClick(this.onClickFunc);
  }
}

// 调用方使用方式
@Component
struct MyPage {
  build() {
    Column() {
      Button(this.text) // 保持系统组件调用风格
        .attributeModifier(new MyButtonModifier("点击我", () => console.log("按钮被点击")));
    }
  }
}

// 推荐的可复用组件: 使用 @Reusable 和 aboutToReuse
@Reusable
@Component
struct ReusableListItem {
  private itemData: { id: number, name: string } = { id: 0, name: '' };

  // 构造函数用于首次创建
  constructor(params: { itemData: { id: number, name: string } }) {
    this.itemData = params.itemData;
  }

  // 组件复用时调用，在此处更新数据
  aboutToReuse(params: { itemData: { id: number, name: string } }) {
    this.itemData = params.itemData;
    console.log(`Item ${this.itemData.id} reused.`);
  }

  build() {
    Row() {
      Text(`ID: ${this.itemData.id}`)
      Text(`Name: ${this.itemData.name}`)
    }
    .height(50)
    .width('100%')
    .justifyContent(FlexAlign.SpaceAround)
  }
}
```

### 避免写法
```arkts
// 避免的传统公用组件封装：导致入参过大且与系统组件不一致
@Component
struct MyCustomButton {
  @Prop text: string = '';
  @Prop fontSize: number = 14;
  @Prop fontColor: Color = Color.Black;
  @Prop bgColor: Color = Color.Gray;
  @Prop onClick: () => void = () => {}; // 避免函数作为入参

  build() {
    Button(this.text)
      .fontSize(this.fontSize)
      .fontColor(this.fontColor)
      .backgroundColor(this.bgColor)
      .onClick(this.onClick);
  }
}

// 调用方：需要传入大量参数，不符合系统组件的链式调用风格
@Component
struct MyPageAvoid {
  build() {
    Column() {
      MyCustomButton({
        text: "避免的按钮",
        fontSize: 18,
        fontColor: Color.Red,
        bgColor: Color.Yellow,
        onClick: () => console.log("Avoided button clicked")
      });
    }
  }
}

// 避免在可复用组件中对复杂数据使用 @Prop
@Reusable
@Component
struct ReusableListItemAvoid {
  @Prop complexData: { id: number, name: string, detail: MyLargeObject }; // complexData会被深拷贝

  // ... build 逻辑
}
```

## 注意事项

-   在决定使用 `FrameNode` 还是声明式范式时，权衡性能需求与开发复杂度。 `FrameNode` 适用于对性能和动态操作有极致要求的场景，而声明式范式更适合大部分常规UI。
-   确保 `NodeController` 的生命周期与宿主组件同步，避免内存泄漏或意外行为。
-   `aboutToReuse()` 回调应尽可能轻量，只包含数据刷新逻辑，避免耗时操作。
-   合理规划 `reuseId`，防止不同类型组件之间的误复用，同时提高复用命中率。