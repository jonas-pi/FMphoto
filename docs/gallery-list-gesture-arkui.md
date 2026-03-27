# 图库时间轴 List 手势与滚动：问题演进与 ArkUI 底层机制说明

本文档记录「图库主页」在 **LazyForEach + List + Refresh** 场景下，缩略图 **点击 / 长按多选 / 划选** 与 **纵向滚动** 长期冲突的排查结论，以及最终与 **鸿蒙官方文档** 对齐的架构选择。便于后续维护者少走弯路。

---

## 1. 现象与目标

| 现象 | 说明 |
|------|------|
| 仅纵向滚动可用 | 缩略图上的 Tap、LongPress、Pan 等「像没绑上」 |
| 间歇性无法滑动 | 有时整页 List 上下滑失效，过一会或再划几次又恢复 |
| 多选恢复后仍偶发卡滚动 | 在 Row 上绑 `parallelGesture` 后多选正常，但滚动仍不稳定 |

**目标**：在不大改产品交互的前提下，让 **List 滚动** 与 **单元格交互** 在 ArkUI 手势仲裁模型下各司其职、可预期。

---

## 2. ArkUI 里必须区分的两层概念（最容易混）

### 2.1 「回调里 return」≠「不参与手势竞争」

很多修复会在 `PanGesture.onActionStart` 里写：

```text
if (!selectionMode) { return; }
```

这在**业务逻辑**上是对的，但在**手势系统**上不够：

- 手势识别器（Recognizer）在 **判定阶段** 就已经进入竞争；
- `onAction*` 是 **识别成功之后** 的回调；
- 若在判定阶段没有把手势 **拒绝（REJECT）** 或 **从绑定上拿掉**，它仍可能与 List 内置的 **PAN_GESTURE（滚动）** 抢同一触摸序列。

因此会出现：**「回调什么都没做，但 List 有时滑不动」** —— 根因在仲裁层，不在业务回调层。

### 2.2 三种绑定与父子关系（官方能力）

ArkUI 对组件常见有三种手势相关能力（名称以当前工程所用 API 为准）：

| 能力 | 典型语义 |
|------|----------|
| `.gesture(...)` | 子组件相对父级有更高优先级时，容易让 **父 List 的滚动在识别期等待** |
| `.priorityGesture(...)` | 显式提高当前组件相对**子组件**的优先级 |
| `.parallelGesture(...)` | 与响应链上其它识别器 **并行**，减轻与父级滚动的「二选一」阻塞 |

**教训**：在 **List 的子节点（如 ListItem 内的 Row）** 上滥用 `.gesture(Tap/LongPress)`，即便意图是「点按」，也可能让 **List 内置滚动** 在部分帧/部分序列里处于等待或失败重协商状态，表现为 **间歇性滑不动**。

---

## 3. 本项目中踩过的坑（按时间线抽象）

### 3.1 在 `@Builder` 生成的缩略图根节点上绑 `priorityGesture` / `gesture`

- **现象**：整格「点不动、长按无反应」，只有 List 还能滚。
- **推断**：在 **LazyForEach** 内由 `@Builder` 展开的节点，与手势宿主、命中测试的组合在部分版本/结构下 **不可靠**（手势未稳定挂到可命中宿主，或更新时机与复用不一致）。
- **方向**：把「需要稳定注册的手势」挪到 **标准容器组件**（如 `Row`）上；缩略图格只做展示与 `onClick` 等。

### 3.2 用 `onTouch` 模拟「延迟点击」

- **现象**：一旦挂上 `onTouch`，Tap / LongPress / Pan 可能 **全线失效**。
- **机制**：触摸序列在 ArkUI 里由 **触摸测试 + 手势识别** 统一调度；`onTouch` 若参与消费/打断，容易与手势管道冲突。
- **方向**：列表项内 **不要用 onTouch 顶替手势**，除非官方明确推荐该模式。

### 3.3 `HitTestMode` 叠床架屋

- `GalleryNetworkThumb` 内部对根节点使用 `HitTestMode.None`，是为让事件落到外层「图库格」——方向正确。
- 外层再叠多层 `Stack` + 多子节点命中策略时，若宿主与手势不在同一稳定节点，会出现 **「看得见、点不到」** 或 **手势与命中分离**。
- **方向**：**手势宿主 = 明确的一个布局节点**；装饰层统一 `None`，避免抢命中。

### 3.4 `TapGesture` + `PanGesture` 与 List 同行

- **TapGesture** 仍是 **手势识别器**，会参与 **手势仲裁**；不是「普通点击事件」。
- **PanGesture({ direction: All })** 与 List **纵向 Pan** 同类竞争；仅 parallel 或仅回调 return **不足以**保证 List 永远优先。
- **方向（官方对齐）**：
  - **点击**：用 **`.onClick()`**（事件通道，不参与手势竞争）。
  - **划选 Pan**：在 **非多选态** 用 **`onGestureJudgeBegin` → `GestureJudgeResult.REJECT`** 把手势从仲裁里拿掉。

---

## 4. 最终架构（与官方文档一致的三段式）

实现落在 `GalleryAlbumTab.ets` 时间轴 **row 节点** 上，逻辑可概括为：

### 4.1 点击：缩略图 `Stack.onClick`

- 预览 / 多选下单击切换：走 **`onGalleryThumbTap`**。
- **原因**：官方材料与社区实践均强调 **List 内点击优先用 `onClick`**，避免 Tap 识别器与滚动抢序列。

### 4.2 长按：`Row.parallelGesture(LongPressGesture)`

- 进入多选、划选起点：仍用 **坐标 → `pickGalleryThumbFlatUnderPoint` → flatIndex → item**。
- **原因**：长按依赖 **时间阈值**，手指一旦明显移动会先失败，与 **纵向拖动滚动** 冲突相对可控；与 `onClick` 分工清晰。

### 4.3 划选：`Row.parallelGesture(PanGesture)` + `onGestureJudgeBegin`

- **多选态**：允许 `PAN_GESTURE` 参与，配合 `beginGallerySlideSelectGesture` / `onGallerySlidePanUpdate` / `endGallerySlideSelectGesture`。
- **非多选态**：在 `onGestureJudgeBegin` 中对 **自定义 Pan** 返回 **`REJECT`**，使其 **根本不进入有效竞争**，List 滚动独占纵向 Pan。
- **注意**：工程里 `onGestureJudgeBegin` 的回调签名以 **当前 SDK 类型定义** 为准（例如 `(gestureInfo: GestureInfo, event: BaseGestureEvent) => GestureJudgeResult`），与部分旧文档示例的三参数形式可能不一致，以 **IDE / 编译器** 为准。

### 4.4 辅助：`galleryMainListScrollEnabled`

- 划选进行时 **关闭 List 的 `enableScrollInteraction`**，避免父级抢走 Pan；结束务必恢复。
- 若异常未收到 End/Cancel，需在 **`onDidScroll` 等路径做兜底**，避免永久锁死滚动（具体见代码注释）。

---

## 5. 「大哥 Opus」式思路 vs 容易走的捷径

| 维度 | 容易走的捷径 | 更稳的底层思路 |
|------|----------------|----------------|
| 问题定性 | 调 `hitTest`、换 `priorityGesture`、加大 `distance` 碰运气 | 先分清 **命中** 与 **手势仲裁** 两层 |
| 点击 | `TapGesture` 或 `GestureGroup` 里塞 Tap | **`onClick`**，绕开识别器竞争 |
| Pan 与 List | 回调里 `if (!mode) return` | **`onGestureJudgeBegin` + REJECT**，在仲裁层出局 |
| 手势挂点 | `@Builder` 里链式绑手势 | **ListItem 内标准 `Row`** 上绑并行手势 + 判定 |
| 文档 | 只看社区片段 | **对照官方：多级手势、手势判定、List 内 Pan 注意点** |

一句话：**先画清「谁在什么时候参与手势竞争」，再写业务；不要只在回调里写分支。**

---

## 6. 参考与延伸阅读（官方入口）

- 鸿蒙文档：**手势事件 / 多级手势 / 手势判定（Gesture Judge）** 相关章节（文档中心搜索 `arkts-gesture-events`、`gesture-judge`）。
- **手势拦截增强**：`shouldBuiltInRecognizerParallelWith`、`GestureRecognizer` 等（API 12+），用于更复杂的 **嵌套滚动** 与 **内外 Pan 协调**；本图库场景以 **`onClick` + `onGestureJudgeBegin`** 已可满足主路径。

---

## 7. 维护清单（改这段代码前自问）

1. 是否在 List 子树引入了新的 **`PanGesture` / `TapGesture`**？若必须，非必要态能否 **REJECT**？
2. 是否新增了 **`onTouch`**？是否会影响手势管道？
3. 手势是否仍绑在 **`@Builder` 匿名树** 上？能否迁到 **`Row` / `ListItem`**？
4. 划选结束后 **`galleryMainListScrollEnabled` 是否必恢复**？有无 **onDidScroll 兜底**？

---

*文档版本：与 `GalleryAlbumTab.ets` 中图库时间轴 row 手势实现同步维护。*
