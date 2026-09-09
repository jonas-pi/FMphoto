# 图库状态收敛基线

本文记录 `GalleryAlbumTab` / `GalleryPreview` 在收敛 HostBridge 前的字段、默认值、写入点和副作用。重构时每个字段只能有一份存储；机器门禁只证明已编码契约，UI/动画等价以真机矩阵为准。

热路径禁区：`searchQuery`、`gallerySelectedIds`、滚动/加载运行态不得进入父页 `@State`。Preview 工具栏/视频继续走 AppStorage，纵向手势继续走 AttributeUpdater。

Slideshow timer、Swiper、`changeIndex(50ms)` 不在阶段 1 用巨型 Host mock 冻结。

## 防扩散

- 禁止新增 `asXxxHost()` 和页面内 HostBridge。
- 新能力进入已有 Session / Coordinator / 窄 Port。
- Category / Folder / Recycle / Video 本轮只禁新增，不迁移。
- Coordinator 只编排跨领域命令，不暴露通用 getter/setter。

## GalleryAlbumTab

入口：[entry/src/main/ets/album/GalleryAlbumTab.ets](../entry/src/main/ets/album/GalleryAlbumTab.ets)

### 外部输入

| 字段 | 装饰器 | 默认 | `@Watch` | 写入 |
|---|---|---|---|---|
| `baseUrl` | `@Prop` | `''` | | 父组件 |
| `albumReloadEpoch` | `@Prop` | `0` | `onEpochChange` | 父组件 |
| `topSafeInsetVp` / `bottomSafeInsetVp` / `floatingDockInsetBottomVp` | `@Prop` | `0` | | 父组件 |
| `homeSurface` | `@Prop` | `'photos'` | `onHomeSurfaceChanged` | 父组件 |
| `viewGranularity` | `@Prop` | `DAY` | `onViewGranularityChanged` | 父组件 |
| `pageShowSignal` | `@Prop` | `0` | `onPageShowSignal` | Home 兜底 |
| `previewOpening` | `@StorageProp` | `false` | | EntryGate |
| `windowWidthBp` | `@StorageProp` | `WIDTH_SM` | `onWindowWidthBpChanged` | 全局断点 |

回调：`onSearchModeVisibilityChange`、`onSelectionDockStateChange`、`onViewGranularityChange`。

### 响应式 UI 状态（阶段 2 不搬家）

| 字段 | 默认 | `@Watch` | 领域 |
|---|---|---|---|
| `bootLoading` / `loadError` / `footText` / `sections` | `false` / `''` / `''` / `[]` | | Load |
| `rootPhotosScrollTitle` | `图库` | | Title |
| `rootModeContentWidthVp` | `360` | | Root |
| `rootPhotosSurfaceTranslateX` / `rootAlbumsSurfaceTranslateX` | `0` | | Root |
| `rootSurfaceSwitchAnimating` | `false` | | Root |
| `searchSeed` | `''` | | Mode |
| `inSearchMode` / `inCategoryMode` / `inSmartCategoryMode` / `inPersonMode` | `false` | `onBottomDockVisibilityChanged` | Mode |
| `searchResults` / `searchLoading` / `searchError` | `[]` / `false` / `''` | | Mode |
| `searchFilterSheetVisible` / `searchFilterActiveCount` | `false` / `0` | | Mode |
| `moreMenuExpanded` / `slideshowSettingsVisible` / `slideshowPreparing` | `false` | 后两者含 dock Watch | Chrome |
| 分类/智能分类/人物/用户相册 loading、error、items | 空/false | opening 类含 dock Watch | Mode |
| `albumsHomeEditMode` 及 commit/cancel signal | `false` / `0` | | Root |
| `personStatVersion` / `autoSyncBadgeCount` | `0` | | Mode |
| `gallerySelectionMode` / `gallerySelectedCount` / `selectionHasLivePhoto` | `false` / `0` / `false` | | Selection |
| sheet / batch busy | `false` | deleting 含 dock Watch | Selection/Batch |
| `galleryMainListScrollEnabled` | `true` | | Selection |
| 时间轴 chrome：`timelineSidebarDragging` 等 | 见下 | | Timeline |
| `modeSwitchOpacity` / `modeSwitchOffsetY` | `1` / `0` | | Mode |
| `renderedViewGranularity` | `DAY` | | Granularity |
| `gallerySlideGestureActive` | `false` | | Selection |
| `galleryTimelineRefreshing` | `false` | | Load |

时间轴 chrome 默认值：`timelineBarVisible=false`、`timelinePressing=false`、`timelineLongPressExpanded=false`、`timelineSliderRatio=0`、`timelineSidebarHighlightIndex=0`、`timelineIndicatorY=12`、`timelineScrubTrackHeightVp=500`。

### 非响应式运行态（阶段 2 迁入 Session，单份所有权）

| 切片 | 字段 | 默认 |
|---|---|---|
| `session.mode` | `searchQuery` | `''` |
| | `personStatGen` | `0` |
| | `personStatOverrides` | 空 Map |
| | `navigationGuardEpoch` | `0` |
| `session.selection` | `gallerySelectedIds` | `[]` |
| | 划选会话 / hit bounds / auto-scroll | 见源码初始值 |
| | `galleryLongPressIgnoreClickUntil` | `0` |
| | `galleryMainListDomId` | `gallery_album_main_list` |
| `session.visible` | 滚动/冻结/可视窗口/pump retry | 见源码；`visiblePhotoBufferSlots=12` |
| `session.timeline` | watchdog / seek / hide timer | timer `-1`，gen `0`，anchor `-1` |
| `session.load` | `orderedDays` / offsets maps / `flowDataSource` / `pumpEpoch` / 刷新 epoch | maps 空，`galleryTimelineAtTopForPull=true` |
| `session.root` | 表面切换 timer、相册首页 prefetch gen、标题锚点、粒度 pinch | timer `-1`，surface `'photos'` |
| `session` 根 | `scrollerRef` / `albumsScroller` / `searchScroller` / `titleBarScrollerBindList` | 新 Scroller / `[]` |

### 直接写入点

- `@Watch`：epoch、Home 表面、粒度、pageShow、底栏、窗口断点。
- 生命周期：`aboutToAppear` / `aboutToDisappear` / `onPageShow`。
- Host 适配器 getter/setter：九个 `as*Host()` 是当前隐式状态总线。
- DataSource：`galleryAlbumRebuildFlow` 走 `reloadAll`；下拉原地合并走 `notifyDataChange`。
- 选择视觉：`GalleryAlbumSelectionOverlay` 注册表，不靠 `gallerySelectedIds` 做 `@State`。

### 副作用边界

HTTP（`AppSession.getClient()`）、router / NavStore、toast、Scroller、`GalleryHomeTimelineCache`、`GalleryTimelineRefreshStore`、`GalleryDeleteSyncStore`、缩略图缓存、硬件返回、底栏/选择 dock 回调。

## GalleryPreview

入口：[entry/src/main/ets/pages/GalleryPreview.ets](../entry/src/main/ets/pages/GalleryPreview.ets)

### `@State`（阶段 2 不搬家）

导航：`swiperIndex=0`、`swiperLocked=false`、`pinchGestureActive=false`、`previewZoomLocked=false`、`totalCount=0`、`scrimOpacity=0`、`loadOriginalToken=0`。

Busy：`downloading/sharing/deleting=false`，下载进度 `0/false`。

详情：`detailsVisible=false`、`previewViewportH=780`、loading/error/data/photoId/persons、folder/person opening。

收藏：`favoriteToggling=false`、`currentCollectState=-1`。

其它：`bottomBarHeight=80`、原图三态、`isDarkTheme=false`、Live/choice sheet。

### `@StorageProp`

`baseUrl`、系统 inset、`colorMode`（`@Watch onColorModeChanged`）。工具栏/视频 chrome 在独立 Store，不进本页 `@State`。

### 非响应式运行态（阶段 2 迁入 Session）

| 字段 | 默认 | 切片 |
|---|---|---|
| `slideshowEnabled` | `false` | slideshow |
| `slideshowIntervalMs` | `5000` | slideshow |
| `slideshowLibraryTotal` | `0` | slideshow |
| `slideshowGlobalIndices` | `[]` | slideshow |
| `slideshowTimerId` / `slideshowPrefetchTimer` | `-1` | slideshow |
| `slideshowAdvancePending` | `false` | slideshow |
| `lastLoggedSlideshowGlobal` / `lastLoggedSlideshowKey` | `-1` / `''` | slideshow |
| `collectSyncGen` | `0` | session 根 |
| `choiceSheetResolver` / `liveSaveResolver` | `undefined` | overlay |

仍留在页面：`itemSource`、`previewItems`、`swiperCtrl`、hero 快照/占位、chrome timer、`heroScrimEntered`、`detailsAvoidTargetVp`。

### `detailsVisible` 双路径

- 业务写入（ActionsHost setter）：赋值后 `syncPreviewDetailsLayout()`；若幻灯片开启且值变化，则 `pause` 或 `resume`。纯函数：`galleryPreviewDetailsVisibleSideEffects`。
- 退出清理：`aboutToDisappear` 直接 `this.detailsVisible = false`，无动画、不改幻灯片 timer。

### DataSource 契约

- `reloadAll`：换引用并 `onDataReloaded`。
- `appendItems`：原地 push，每项 `onDataAdd`；监听器没有 add 回调时才退化为 reload。幻灯片补货禁止误走 `onDataReloaded`。
- 删除后 index：`galleryPreviewIndexAfterDelete`；剩余为 0 时 `-1` 表示 `routerBack`；否则 `changeIndex(target, false)` 延迟 50ms。

### 收藏代次

`galleryPreviewCollectSyncShouldApply(startedGen, currentGen, requestedId, currentId)`：gen 或当前 id 不一致则丢弃。

## 真机矩阵（不由单测证明）

Album：启动/缓存恢复、快滑与 scrub、下拉刷新、搜索输入法、模式切换、划选批量、粒度、预览删除增量同步、相册首页。

Preview：共享转场、Swiper/缩放/下滑退出、详情拖拽、图/视频/Live、原图、收藏下载分享删除、幻灯片定时与补货、旋转、返回键覆盖层优先级。

回滚：任一领域出现请求次数、DataSource 通知类型、组件 key、滚动位置、输入法、转场、媒体生命周期差异，回滚该领域，不叠加修补。
