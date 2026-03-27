# HarmonyOS 主题与样式 - Cursor Rules

你正在为HarmonyOS应用开发相关功能。以下是你需要遵循的开发规则。

## 核心原则

-   **资源驱动**: 优先通过资源文件（如`color.json`, `media`）管理主题和样式，实现动态切换和集中维护。
-   **用户体验至上**: 确保界面在各种模式（深浅色）、场景（视频、支付）下都提供清晰、舒适和一致的视觉体验。
-   **智能适配**: 充分利用HarmonyOS平台提供的能力，实现系统级或页面级的自动适配和管理，减少手动干预。
-   **能效管理**: 合理控制屏幕亮度与常亮状态，优化应用功耗。

## 推荐做法

### 代码结构
-   **深浅色资源分离**: 在`src/main/resources`下创建`base`（浅色模式默认）和`dark`目录，分别存放深浅色模式下的同名资源文件（如`element/color.json`, `media/icon.svg`）。
-   **页面亮度映射**: 使用 `Map<string, number>` 结构维护不同页面（`navDestination`）的专属亮度值，实现页面级亮度记忆与恢复。

### 最佳实践
-   **颜色适配**:
    -   优先使用HarmonyOS提供的系统级颜色资源。
    -   自定义颜色统一在`base/element/color.json`和`dark/element/color.json`中定义，并通过`$('app.color.your_color_name')`引用。
-   **媒体资源适配**:
    -   **SVG图标**: 优先使用SVG，并通过`fillColor()`属性使其颜色随主题自动变化。
    -   **位图**: 在`base/media`和`dark/media`目录下放置深浅模式对应的位图资源，并保持文件名一致。
-   **状态栏适配**: 确保状态栏背景和文字颜色与应用主题保持一致，保证系统信息可见性。
-   **页面亮度管理**:
    -   使用`window.setWindowBrightness()`在特定页面动态设置亮度。
    -   结合`uiObserver.on('navDestinationUpdate')`监听页面跳转，实现亮度自动恢复或加载页面专属亮度。
-   **屏幕常亮控制**:
    -   在沉浸式体验（如视频播放）开始时调用`window.setWindowKeepScreenOn(true)`。
    -   在体验结束（暂停、退出）时立即调用`window.setWindowKeepScreenOn(false)`取消常亮。
    -   将常亮设置与组件生命周期绑定。
-   **用户亮度调节**: 对于需要用户调节亮度的场景，集成`Slider`等UI组件，通过`onChange`事件调用`window.setWindowBrightness()`。

## 禁止做法

-   **硬编码颜色**: 严禁在代码中直接使用`Color.Black`、`#FFFFFF`等硬编码颜色值，这会导致深浅色模式适配困难。
-   **亮度常亮未释放**: 禁止在不需要时仍保持`window.setWindowKeepScreenOn(true)`，这会严重消耗电量。
-   **未适配状态栏**: 忽略状态栏的深浅色适配，导致状态栏内容在特定模式下不可见。

## 代码示例

### 推荐写法
```arkts
// 1. color.json 资源定义 (在 base/element/color.json 和 dark/element/color.json 中定义同名资源)
// base/element/color.json: { "text_primary": "#FF000000" }
// dark/element/color.json: { "text_primary": "#FFFFFFFF" }

// 2. 引用颜色资源
Text('Hello HarmonyOS')
  .fontColor($r('app.color.text_primary')); // 自动适配深浅色

// 3. 设置页面亮度与屏幕常亮
aboutToAppear() {
  // 假设当前页面需要高亮显示
  window.setWindowBrightness(0.8, (err) => {
    if (err) console.error(`Set brightness failed: ${err.message}`);
  });
  // 视频播放时保持屏幕常亮
  window.setWindowKeepScreenOn(true, (err) => {
    if (err) console.error(`Keep screen on failed: ${err.message}`);
  });
}

// 4. 在页面离开时恢复或关闭
aboutToDisappear() {
  // 恢复系统默认亮度 (或上一个页面的亮度)
  window.setWindowBrightness(-1, (err) => { // -1 表示恢复系统亮度
    if (err) console.error(`Restore brightness failed: ${err.message}`);
  });
  // 关闭屏幕常亮
  window.setWindowKeepScreenOn(false, (err) => {
    if (err) console.error(`Close keep screen on failed: ${err.message}`);
  });
}
```

### 避免写法
```arkts
// 1. 硬编码颜色
Text('Avoid Hardcoded Color')
  .fontColor(Color.Black); // 在深色模式下可能不可见

// 2. 未关闭屏幕常亮
aboutToAppear() {
  window.setWindowKeepScreenOn(true);
}
// aboutToDisappear() 中未调用 window.setWindowKeepScreenOn(false); 导致电量持续消耗
```

## 注意事项

-   **资源同名**: 确保`base`和`dark`目录下的同类资源（如`color.json`中的颜色项、`media`中的图片）名称完全一致，以实现自动切换。
-   **Web内容适配**: 如果应用内嵌Web组件，其深色模式适配通常需要Web前端配合，通过CSS媒体查询`prefers-color-scheme`实现。
-   **性能测试**: 在不同设备、不同亮度、不同深浅模式下进行充分测试，确保用户体验和性能表现。
-   **权限**: 亮度调节和屏幕常亮可能需要相关权限，确保在`module.json5`中声明并按需申请。