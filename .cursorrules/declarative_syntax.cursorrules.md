# HarmonyOS 声明式语法 - Cursor Rules

你正在为HarmonyOS应用开发相关功能。以下是你需要遵循的开发规则。

## 核心原则

-   **UI是状态的函数**: 界面渲染应始终由应用状态驱动。
-   **状态与UI解耦**: 将共享状态管理逻辑从UI组件中分离，提高可维护性。
-   **最小化刷新范围**: 仅在必要时触发UI刷新，避免冗余渲染，优化性能。
-   **单向数据流**: 遵循明确的数据流向，确保状态变更的可预测性。
-   **避免副作用**: 不在UI渲染周期（如`build`方法）内执行状态修改或复杂逻辑。

## 推荐做法

### 代码结构
-   **全局状态管理**: 对于复杂的、多组件共享的状态，推荐使用**StateStore**库进行集中管理，将业务数据、状态更新逻辑（Reducer）与UI分离。
-   **数据模型可观测**: 所有被StateStore管理或需要在UI中响应变化的业务数据，必须使用`@Observed`或`@ObservedV2`装饰器修饰。

### 最佳实践
-   **理解状态变量机制**: 深入理解`@State`, `@Prop`, `@Link`等装饰器的工作原理，明确其改变会触发UI刷新。
-   **合理选择装饰器**:
    -   **`@State`**: 组件内部私有状态，仅影响自身及子组件刷新。
    -   **`@Prop`**: 父组件向子组件单向传递数据，子组件不可修改。适用于仅读取的场景。
    -   **`@Link`**: 父子组件双向绑定，子组件可修改父组件状态。仅在确实需要双向绑定时使用，警惕其可能导致的大范围刷新。
-   **Reducer纯函数**: 将所有状态更新逻辑封装在纯粹的Reducer函数中，根据`Action`指令更新StateStore中的状态。
-   **利用开发工具**: 使用`hidumper`分析运行时状态变量和UI刷新情况；使用`Code Linter`（如`@performance/hp-arkui-remove-redundant-state-var`规则）检查并移除冗余状态变量。

## 禁止做法

-   **在`build`方法中引入副作用**: 绝对禁止在组件的`build`方法或其直接调用的计算属性/函数中修改非状态变量或执行其他副作用操作。
-   **声明冗余状态变量**:
    -   将未在任何UI组件中使用的变量定义为状态变量（如`@State`）。
    -   将仅被读取但从未被修改的变量定义为状态变量。
-   **过度依赖父子组件状态传递**: 在多层级或多组件共享复杂状态的场景下，避免过度使用`@Link`或`@Provide/@Consume`，这会导致状态与UI高度耦合，难以维护。

## 代码示例

### 推荐写法
```arkts
// 仅在UI中被读取且无需触发UI刷新的数据，使用普通变量或@Prop
@Component
struct ChildComponent {
  @Prop value: string; // 父组件传递，子组件只读
  private internalCount: number = 0; // 内部逻辑使用，不触发UI刷新

  build() {
    Column() {
      Text(`Value from Parent: ${this.value}`)
      Text(`Internal Count: ${this.internalCount}`)
    }
  }
}

// StateStore数据模型，确保可观测性
@Observed
class TodoItem {
  id: number = 0;
  content: string = '';
  isCompleted: boolean = false;
}
```

### 避免写法
```arkts
// 反例1：变量未关联任何UI组件，却被定义为状态变量
@Entry
@Component
struct MyComponent {
  @State unusedState: string = 'Hello'; // unusedState未在build中被使用
  @State buttonMsg: string = 'I am button'; // buttonMsg仅被读取，未被修改

  build() {
    Column() {
      Button(this.buttonMsg) // 仅读取buttonMsg
    }
  }
}

// 反例2：在build方法中引入副作用
@Component
struct BadComponent {
  @State opacityNum: number = 0;

  getCalculatedOpacity(): number {
    // ⚠️ 错误：在build周期中修改非状态变量，导致不可预测的行为和性能问题
    this.opacityNum = (this.opacityNum + 1) % 10;
    return this.opacityNum / 10;
  }

  build() {
    Image('icon.png')
      .opacity(this.getCalculatedOpacity()) // 每次build都会调用并修改opacityNum
  }
}
```

## 注意事项

-   **性能开销**: 状态变量的管理会带来一定的性能开销，不合理使用可能导致性能劣化。
-   **调试**: 积极利用HarmonyOS提供的诊断工具（如`hidumper`）和Lint工具，它们是定位和解决冗余刷新及状态管理问题的利器。
-   **数据一致性**: 确保所有需要UI响应的数据都通过正确的状态管理方式进行维护，以避免UI与实际数据不一致。