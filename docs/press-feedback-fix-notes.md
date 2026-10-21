# 按压反馈（向内收缩动画）修复记录

> 状态：**代码已改完，真机验证未完成**。设备掉线后未能复测，用户手动反馈仍然是「不行」。
> 记录时间：2026-10-21。分支：`main`。

## 1. 问题描述（用户原话）

> 更多按钮以及类似的按钮，只有第一次点击的时候有那种"向内收缩一下的"反馈动画，后面就没有了。

## 2. 已完成的排查（含真机证据）

### 2.1 HDS 标题栏「更多」按钮本身没有「只第一次」的问题

用 `hdc shell snapshot_display` 抓帧 + PIL 像素比对（脚本见第 5 节），在图库网格页与相册页各测两轮：

| 测量项 | 结果 | 结论 |
| --- | --- | --- |
| 静止帧 vs 按住帧 | 8883 / 8901 像素变化 | 按压时确实有视觉变化 |
| 第 1 轮结束 vs 静止帧 | **0 像素差异** | 菜单关闭后按钮逐像素回到静止态，没有卡在按压态 |
| 第 2 轮按住 vs 静止帧 | 8896 / 8902 像素变化 | 按压效果**每次都会重播** |
| 菜单打开快帧 vs 稳定帧（两次打开） | 32657 / 28980 像素变化 | 菜单入场动画两次都有，幅度相当 |
| 两次稳定态对比 | 0 像素差异 | 状态可复现 |

ASCII 渲染（裁剪按钮区域）显示，HDS 标题栏图标按压时是**淡出**（`+@@@.` → `.===.`），几何尺寸不变：

```
=== 静止 ===            === 按住 ===
      =+:          -+-        .            .
     +@@@.        =@@@-      .===.         -==.
     *@@@:        +@@@-      .===.        .===:
     .+*-          +*=        :-:          :-:
```

**结论**：HDS 的「更多」按钮既没有卡在按压态，动画也每次重播；而且它的按压反馈是淡出，**不是**用户描述的「向内收缩」。若用户指的确实是这个按钮，需要换成自绘按钮（见第 4 节）。

### 2.2 菜单不会吃掉抬手事件

`uitest uiInput longClick`（手指按住约 1 秒）+ `uitest dumpLayout` 判定：

- t≈250ms：无菜单
- t≈700ms：菜单已展开

即 HDS 菜单项的 `action` 走的是 **onClick（抬手后触发）**，菜单在抬手之后才弹出，抬手事件不会被菜单遮罩吞掉。

### 2.3 真正的 bug 在我们自绘按钮上

`FnHdsPillButton` / `FnHdsSymbolButton` / `FnHdsOverlay` 选择项 / `FnHdsOverlayCapsule` 的按压态是这样实现的：

```ts
if (event.type === TouchType.Down)      { this.isPressed = true;  ... }
if (event.type === TouchType.Up || Cancel) { this.isPressed = false; ... }
```

**只靠 `Up`/`Cancel` 复位**。按下后如果同时弹出菜单 / 半模态 / 弹窗，抬手事件会被新弹出的遮罩吃掉 → `isPressed` 永久为 `true` → 按钮一直停在收缩态 → **之后每次点击按压态都没有变化，动画自然不再重播**。这正是用户描述的现象。

官方文档《按压阴影》（`devecocli docs read '开发指南/UI_Design_Kit_UI设计套件/视效/按压阴影/ui-design-visual-effect-background-color'`）给的示例也是 `stateEffect: false` + `visualEffect(pressShadow)` + `onTouch` 驱动 `@State`，同样依赖 `Up`/`Cancel` 复位 —— 说明这是这类实现方式的共性坑。

## 3. 本次改动（已提交）

| 文件 | 改动 |
| --- | --- |
| `entry/src/main/ets/common/FnPressWatchdog.ets`（新增） | 按压态看门狗：按下起 800ms 定时器，超时没等到抬手/取消就强制复位 |
| `entry/src/main/ets/common/FnUiCommon.ets` | `FnHdsPillButton`、`FnHdsSymbolButton` 接入看门狗；新增 `FN_PRESSED_SCALE = 0.92`，按下时向内收缩 |
| `entry/src/main/ets/common/FnHdsOverlay.ets` | 选择项接入看门狗 |
| `entry/src/main/ets/common/FnHdsOverlayCapsule.ets` | 接入看门狗 |
| `entry/src/main/ets/common/FnUiCommon.ets`（`FnHdsPressActionGate`） | 菜单弹出延迟 48ms → 160ms：等抬手后再弹，按压回弹先播完 |

## 4. 未完成 / 未验证（需要下一轮处理）

1. **真机未复测**：新包已构建（`BUILD SUCCESSFUL`），但安装后设备掉线（`hdc tconn 192.168.0.18:12345` 连不上），看门狗 + 0.92 收缩比例的实际效果**没有在真机上确认**。
2. **用户仍然说「不行」**：如果用户指的确实是标题栏那个 HDS「更多」，那 HDS 侧无法提供「向内收缩」（它只有淡出），只能自绘替换：
   - 在 `FnHdsMoreMenuAnchor`（`common/FnHdsMoreMenu.ets`）里画 `sys.symbol.dot_grid_2x2`（24vp，`IconStyleMode.NORMAL` 的图标尺寸）；
   - 去掉三个 chrome 里 HDS 的「更多」菜单项（`album/galleryList/GalleryGridChrome.ets:106`、`album/galleryAlbumTab/GalleryAlbumTopBar.ets:601/663`、`pages/galleryPreview/GalleryPreviewChrome.ets:380`）；
   - 位置对齐：真机实测 HDS 按钮 bounds `[1117,158][1252,293]` px，视口 440vp 宽 → 按钮 45×45vp，图标中心距右 **45.2vp**、中心 y **75.2vp**；当前 anchor 用的是 `topSafeInsetVp + 8` + `hds_title_bar_padding_horizontal`，与 HDS 按钮**并不重合**，自绘时需要重新定位。
3. **`FnHdsPressActionGate` 的 160ms 延迟**未评估手感，必要时可以回退到 48ms（实测动作走 onClick，48ms 也够回弹播完）。
4. **不要重蹈的两次失败尝试**（均已回滚）：
   - 把 anchor 的 `hitTestBehavior` 改成 `HitTestMode.Default` → 用户反馈「更多按钮点不动了」：`bindMenu` 需要触摸穿透到系统浮层，遮罩住后 HDS 按钮收不到点击。
   - 用 `@State tapPulse` + 空 Row 缩放做脉冲 → 数值上只有透明度变化：anchor 是**空 Row**，缩放没有任何视觉输出。
5. **相册自动创建/归档等上一批改动**已在 `6a4b7f4` 提交，但**最新构建未做全量真机回归**（相册排序持久化、封面缓存不空白、toast 含「未归档」计数）。
6. **测试残留**：手机里仍有下载的测试照片；NAS 上的测试相册「飞马相册」已删除（现存 风景 32 / 人物 21）。

## 5. 验证方法（尽量少用截图，省 token）

```powershell
# 布局（便宜）：判断菜单是否展开
hdc shell uitest dumpLayout -p /data/local/tmp/x.json
hdc file recv /data/local/tmp/x.json .dsh-tmp/phoneshots/x.json
# 菜单展开标志：dump 里出现「上传」「检查同步」「幻灯片」

# 像素比对（只有需要看动画时才用）
hdc shell snapshot_display -f /data/local/tmp/x.jpeg
hdc file recv /data/local/tmp/x.jpeg .dsh-tmp/phoneshots/x.jpeg
# 用 PIL 对按钮区域 (1140,160)-(1250,260) 求 changed>8 的像素数
```

按下态取帧用 `uitest uiInput longClick x y`（按住约 1 秒），期间并行 `snapshot_display`；普通 `swipe` 太快抓不到按压帧。

构建命令：

```powershell
cd D:\Desktop\project\FMphoto
$env:DEVECO_SDK_HOME="$env:LOCALAPPDATA\Huawei\Sdk"
& 'D:\DevEco Studio\tools\node\node.exe' 'D:\DevEco Studio\tools\hvigor\bin\hvigorw.js' --mode module -p product=default assembleHap --no-daemon
```
