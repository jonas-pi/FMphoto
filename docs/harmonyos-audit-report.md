# FMphoto HarmonyOS 官方规范合规与问题审计报告

- **工程**：FMphoto（飞牛 NAS 相册客户端，`com.jonas.fmphoto` v1.3.2-beta.2）
- **范围**：`entry/src/main/ets` 全部 161 个 `.ets` 文件静态审计 + 关键实现逐点核实
- **规范依据**：华为官方文档（经 ohos MCP 检索原文：`ts-transition-animation-shared-elements`、LazyForEach 指南、`js-apis-taskpool`、uicontext 图片缓存、DynamicSyncScene 等）
- **日期**：2026-08-17

---

## 目录

1. [紧急：一镜到底共享转场闪回（P0）](#一紧急一镜到底共享转场闪回p0)
2. [性能与内存（P0/P1）](#二性能与内存p0p1)
3. [动画与沉浸式（P1/P2）](#三动画与沉浸式p1p2)
4. [官方规范引用清单](#四官方规范引用清单)
5. [修复优先级路线图](#五修复优先级路线图)

---

## 一、紧急：一镜到底共享转场闪回（P0）

### 现象

偶发动画调用不生效（动画"越狱"），**连续点击时偶发无动画直接闪回**。用户反馈集中在一镜到底（从哪来回哪去）链路。

### 根因 1：`heroActive` 延迟重置定时器与快速导航竞争

- **问题点**：`pages/GalleryPreview.ets:377-379`
  ```ts
  GalleryPreviewNavStore.clear();
  setTimeout((): void => {
    setGalleryPreviewHeroActive(false);
  }, GALLERY_SHARED_TRANSITION_DURATION + 80);   // 300ms 延迟
  ```
  返回后**延迟 300ms** 才重置 `GALLERY_PREVIEW_HERO_ACTIVE`，且**定时器无会话代次（gen）校验**。
- **后果**：back 后 300ms 内再次进入预览 → 旧会话定时器在新会话转场期间触发 → `previewHeroActive` 突变 → 源页 `pageTransition` 条件分支翻转 → 转场配对失效 → 无动画闪回。
- **官方规范**：官方一镜到底范式（`ts-transition-animation-shared-elements` 示例）中，两页 `pageTransition` 为**无条件**的 `RouteType.None + duration 0`，不存在运行时开关翻转问题。
- **修复（贴近官方）**：
  1. 源页 `pageTransition()` 改为**无条件** `None + duration 0`（删除 `if (this.previewHeroActive)` 分支，见根因 2）；
  2. 若仍需延迟重置，加代次校验（对齐 `GalleryPreviewNavStore.openGen` 模式）：
     ```ts
     private static heroResetGen: number = 0;
     // aboutToDisappear:
     const gen = ++GalleryPreviewNavStore.heroResetGen;
     setTimeout(() => {
       if (gen === GalleryPreviewNavStore.heroResetGen) {
         setGalleryPreviewHeroActive(false);
       }
     }, GALLERY_SHARED_TRANSITION_DURATION + 80);
     ```

### 根因 2：`PageTransitionExit` 用 220ms + 条件分支，偏离官方一镜到底

- **问题点**：`pages/CategoryGallery.ets:1505-1512`
  ```ts
  pageTransition(): void {
    if (this.previewHeroActive) {
      PageTransitionEnter({ type: RouteType.None, duration: 0 })
      PageTransitionExit({ type: RouteType.None, duration: GALLERY_SHARED_TRANSITION_DURATION, ... })  // 220ms
    }
  }
  ```
- **官方规范**（原文）：官方一镜到底示例中源/目标页均写
  ```
  PageTransitionEnter({ type: RouteType.None, duration: 0 })
  PageTransitionExit({ type: RouteType.None, duration: 0 })
  ```
  页面本身**不做位移**，完全由共享元素转场驱动。
- **后果**：`PageTransitionExit` 220ms 整页动效与共享元素转场**双重驱动位置** → 冲突抖动/闪回；`if` 条件使转场类型可在运行中突变。
- **修复（重构，贴近官方）**：改为无条件 `None + 0`，删除 heroActive 依赖：
  ```ts
  pageTransition() {
    PageTransitionEnter({ type: RouteType.None, duration: 0 })
    PageTransitionExit({ type: RouteType.None, duration: 0 })
  }
  ```

### 根因 3：目标页 4 处同 id `sharedTransition` 条件分支

- **问题点**：`album/GalleryPreviewSlide.ets:1169 / 1268 / 1284 / 1307`
  视频封面 / 图片 / GIF / 兜底 4 个 if/else 分支挂**同一个** `heroShareId()`；warmup 揭层（`videoOverlayRevealed`）、GIF 加载完成瞬间组件销毁/重建。
- **官方规范**（原文）：*"两个页面中 id 值相同且**不为空字符串**的组件即为共享元素"*；*"type 为 Exchange 时，效果为对匹配的共享元素产生**位置、大小的过渡，不支持内容的过渡效果**"*。
- **后果**：转场播放窗口内共享元素被整体替换 → 匹配组件突变 → 闪回；id 为空串（见根因 4）时官方定义下不构成共享元素。
- **修复（重构，贴近官方）**：抽**单一稳定 hero 容器**，`sharedTransition` 只挂外层，内层内容切换不动 id：
  ```ts
  // 结构示意：Stack 作为唯一共享元素，内层按需切换封面/图片/视频
  Stack() {
    if (this.isVideo()) { /* 视频封面层 */ }
    else if (this.isGif()) { /* GIF 层 */ }
    else { /* 图片层 */ }
  }
  .width(this.heroFrameW()).height(this.heroFrameH()).clip(true)
  .sharedTransition(this.heroShareId(), gallerySharedTransitionOptions())  // 唯一挂点
  ```

### 根因 4：`heroShareId()` 返回空串 / key 突变导致配对失败

- **问题点**：`album/GalleryPreviewSlide.ets:377-382`
  ```ts
  private heroShareId(): string {
    if (!this.enableSharedTransition || !this.active) {
      return '';   // 官方定义：空串不参与转场
    }
    return gallerySharedTransitionId(this.currentItemKey());
  }
  ```
- **官方规范**（原文）：*"两个页面中 id 值相同且不为空字符串的组件即为共享元素"*。
- **后果**：Swiper 快速滑动时 `active` 翻转 → id 变 `''` → 转场断裂；`currentItemKey` 变化导致两端 id 不一致 → 无动画。
- **修复**：转场窗口内**冻结 key**（进入转场后锁定 `heroShareId` 直到转场结束），`active` 翻转时保持已锁定 id 而非返回空串。

### 根因 5：连续 push 双预览页压栈（数据竞争）

- **问题点**：`album/GalleryPreviewNavStore.ets`（`openPreviewWhenReady`）
  `opening` 闸门仅在 `await pushUrl` 期间生效，resolve 后立即复位；`items/startIndex/slideshow` 为 **static 单例**，两页均从 NavStore 快照（`pages/GalleryPreview.ets:210-229`）。
- **官方规范**（原文）：*"sharedTransition 仅发生在 @ohos.router（页面路由）跳转时"*——同栈双目标页同 id 产生配对歧义。
- **后果**：快速双击 → 两个 `pages/GalleryPreview` 压栈 → 数据互相覆盖 + 返回双层 back 触发两次 heroActive/clear 时序 → 转场错乱闪回。
- **修复**：`openPreview` 入口加**导航锁**（时间戳防抖 ≥ 400ms，独立于 `opening`）：
  ```ts
  private static lastEnterTs: number = 0;
  static openPreview(...) {
    const now = Date.now();
    if (now - GalleryPreviewNavStore.lastEnterTs < 400) { return; }
    GalleryPreviewNavStore.lastEnterTs = now;
    void GalleryPreviewNavStore.openPreviewWhenReady(...);
  }
  ```

---

## 二、性能与内存（P0/P1）

### P0-1 上传时主线程同步读整文件 → UI 冻结

- **问题点**：`network/fnHttpClient/FnHttpClientUploadOps.ets:191-215`（`readUploadFileAndMtime`，`uploadPhotoByUri` 774 行调用）：`openSync + statSync + readSync + closeSync` 同步读**整个照片文件**入内存。
- **官方规范**（原文，relationalStore/TaskPool）：*"对…同步接口获得的结果进行操作时，若逻辑复杂且循环次数过多，可能造成 **freeze 问题**，建议将此步骤放到 **taskpool** 线程中执行"*。
- **修复（贴近官方）**：改用 `fileIo` 异步 `open/read/stat`；或将文件读取移入 `taskpool`（`@kit.ArkTS`）：
  ```ts
  import { taskpool } from '@kit.ArkTS';
  const task = new taskpool.Task(readUploadFileAndMtime, uri);   // 函数体为纯同步 IO
  const filePack = await taskpool.execute(task) as UploadFileReadResult | undefined;
  ```

### P0-2 AVPlayer 事件监听未解绑 → 回调泄漏

- **问题点**：`album/GalleryAuthVideo.ets:1136-1190`（`player.on` ×5：error/timeUpdate/durationUpdate/seekDone/stateChange），`aboutToDisappear`（382 行）仅 `release()` 无 `off()`。
- **官方规范**：AVPlayer 官方 API（`arkts-apis-media-avplayer`）要求事件监听与 `off` 配对、`release` 前解绑。
- **修复**：`release()` 前逐个 `off`：
  ```ts
  player.off('error'); player.off('timeUpdate'); player.off('durationUpdate');
  player.off('seekDone'); player.off('stateChange');
  await player.release();
  ```

### P0-3 displaySync 帧回调未释放 → 持续耗电

- **问题点**：`album/GallerySlideAutoScroll.ets:157-163`：模块级单例 `autoScrollSync` 注册 `sync.on('frame')`，未见 `off('frame')`/`stop()`/置空。
- **官方规范**：`displaySync.DisplaySync` 使用完毕需 `off` 并停止，防止回调持续驱动。
- **修复**：滚动结束/页面销毁时 `autoScrollSync.off('frame'); autoScrollSync.stop(); autoScrollSync = null;`

### P0-4 相册图片缓存未启用 → 网格滑动重复解码

- **问题点**：全工程未调用 `getUIContext().setImageCacheCount`；网格大量同源缩略图（`GalleryAlbumAlbumsHomeView.ets:689/748/922` 等 `Image(pixelMap)`）。
- **官方规范**（原文，uicontext）：*"设置内存中缓存解码后图片的数量上限…默认值为 0，表示不缓存…建议根据应用内存需求，合理设置缓存数量，避免内存使用过高"*。
- **修复**：启动时配置：
  ```ts
  const ctx = this.getUIContext();
  ctx.setImageCacheCount(100);                    // 解码后图片缓存（LRU）
  ctx.setImageRawDataCacheSize(64 * 1024 * 1024); // 解码前数据缓存上限
  ```
  （数值需结合机型内存实测调优，避免与缩略图缓存重复占用）

### P1-5 ForEach 渲染大列表

- **问题点**：`GalleryAlbumAlbumsHomeView.ets:1056`（`ForEach(mediaRowIndexes())`）、`GalleryAlbumMainModeView.ets:531/560/714`（行内 slots 用 ForEach；主网格 749 行已正确用 LazyForEach）。
- **官方规范**（原文，LazyForEach 指南）：*"在大量子组件的场景下，LazyForEach 与缓存列表项、动态预加载、组件复用等方法配合使用，可以进一步提升滑动帧率并降低应用内存占用"*；并建议**优先使用 Repeat**（自带复用，UI 渲染效率更高）。
- **修复**：大列表行改 `LazyForEach`（或迁移 `Repeat` + `@ReusableV2`），配合 `cachedCount`。

### P1-6 @Watch 使用量过大

- **问题点**：全工程 `@Watch` 60 处 vs `@Observed` 2 处 / `@ObjectLink` 0 处。
- **官方规范**：V1 状态管理建议 `@Observed/@ObjectLink` 精确控制对象属性级刷新，避免整链 `@Watch` 连锁刷新。
- **修复**：高频 `@Watch` 下沉到子组件 `@ObjectLink`；长期评估 V2 状态管理（`@ObservedV2/@Trace`）。

### P1-7 同步获取图片信息

- **问题点**：`GalleryAlbumAlbumsHomeView.ets:479`（`pix.getImageInfoSync()`）网格滚动时同步查询。
- **修复**：改异步 `getImageInfo` 或缓存尺寸信息。

---

## 三、动画与沉浸式（P1/P2）

### P1-8 无障碍"减少动效"适配缺失

- **问题点**：全工程 `reduceMotion/shouldSimplify` **0 处**；应用含大量 spring/转场/轮播动画。
- **官方规范**：鸿蒙无障碍设计支持"减少动态效果"（系统设置），应用应监听并简化动画。
- **修复**：封装全局动效开关（读系统设置 + 监听变化），开启时：共享转场降级淡入淡出、禁用 spring 回弹、遮罩直接显示。

### P1-9 动态帧率同步（DynamicSyncScene）未使用

- **问题点**：相册 Swiper（`GalleryPreviewSlide`）与网格滚动未设置期望帧率。
- **官方规范**（原文，uicontext DynamicSyncScene）：`getDynamicSyncScene()` + `setFrameRateRange`，示例 `ANIMATION: {min:0,max:120,expected:90}` / `GESTURE: {min:0,max:120,expected:30}`。
- **修复**：为相册 Swiper/网格注册 DynamicSyncScene，按场景分级设帧率。

### P2-10 createAnimator 生命周期

- **问题点**：`GalleryPreviewSlide.ets:892`、`pages/GalleryPreview.ets:579`、`GalleryPreviewVerticalGesture` 三处 `createAnimator`（已有 `cancelTransformAnimator` 取消机制）。
- **修复**：`aboutToDisappear` 统一 `animator.stop()` 防残留。

### P2-11 隐式动画散布

- **问题点**：`.animation()` 20 处（参数已统一常量，优点）；隐式动画在状态频繁变化时可能意外触发。
- **修复**：低频状态动画收敛到 `animateTo` 显式管理（官方倾向）。

### P2-12 共享转场 id 管理分散

- **问题点**：`sharedTransition` 19 处跨 8 文件；id 由 `gallerySharedTransitionId()` 统一生成（好），但 `GALLERY_PREVIEW_HERO_ACTIVE` 开关覆盖路径多。
- **修复**：hero 开关收敛到 `GalleryPreviewNavStore` 单一入口（配合根因 1/2 修复后移除页面级开关）。

---

## 四、官方规范引用清单

| # | 官方文档 | 关键条款 |
|---|---|---|
| 1 | `ts-transition-animation-shared-elements`（共享元素转场） | id 相同且不为空串；Exchange 仅位置/大小过渡、不支持内容过渡；仅 router 跳转时发生 |
| 2 | 同文档「一镜到底」示例 | 两页 `pageTransition` 均 `RouteType.None + duration 0` |
| 3 | LazyForEach 指南（`arkts-rendering-control-lazyforeach`） | 大量子组件配合 LazyForEach+缓存+复用提升帧率降内存；优先 Repeat |
| 4 | `js-apis-taskpool` / relationalStore | 同步接口复杂循环可能 freeze，建议 taskpool 线程 |
| 5 | uicontext 图片缓存 | `setImageCacheCount` 默认 0 不缓存；建议合理设置 |
| 6 | uicontext DynamicSyncScene | `setFrameRateRange` 分级（ANIMATION 90 / GESTURE 30） |
| 7 | `arkts-apis-media-avplayer` | 事件 on/off 配对、release 前解绑 |
| 8 | 鸿蒙无障碍设计 | 支持"减少动态效果"系统设置 |

## 五、修复优先级路线图

| 优先级 | 问题 | 改动量 | 预期收益 |
|---|---|---|---|
| 1 | 根因 1+2（heroActive 时序 + pageTransition 改 None/0） | 小 | 消除连续点击闪回主因 |
| 2 | 根因 5（导航锁防双压栈） | 小 | 消除双栈数据竞争 |
| 3 | 根因 3+4（单 hero 容器 + id 冻结） | 中 | 消除转场中组件突变/断裂 |
| 4 | P0-1 上传 TaskPool、P0-2 AVPlayer off、P0-3 displaySync 释放 | 小-中 | 消除卡死与泄漏 |
| 5 | P0-4 图片缓存、P1-5 LazyForEach/Repeat | 中 | 网格滑动帧率 |
| 6 | P1-6/7/8/9、P2-10/11/12 | 中-大 | 稳定性与合规 |

---

*本报告问题点均以当前代码（`entry/src/main/ets`）为准；修复建议贴近官方实现，其中根因 2/3 涉及结构调整（pageTransition 无条件化、单 hero 容器），属重构级改动。*
