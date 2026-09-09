# ETS Module Boundaries

Current domain mapping keeps existing historical folders, but responsibilities are now split like this:

- `album/`: gallery domain
- `network/`: HTTP, authx, cookie, upload infrastructure
- `auth/`: session lifecycle and re-auth
- `pages/`: page shells and route entry points
- `common/`: shared UI and generic helpers

Dependency rules:

- `network/` must not depend on `album/` or `pages/`
- `auth/` may depend on `network/`, but not on page shells
- `album/` may depend on `auth/`, `network/`, and `common/`
- `pages/` assemble domain modules, but should not absorb domain internals
- `common/` should stay domain-agnostic

`FnHttpClient` organization:

- [FnHttpClient.ets](/D:/Users/picha/Desktop/project/FMphoto/entry/src/main/ets/network/FnHttpClient.ets): thin outward shell and core request behavior
- `network/fnHttpClient/`: capability split for `cookie`, shared helpers, `gallery`, and `upload`

`GalleryAlbumTab` organization:

- [album/GalleryAlbumTab.ets](/D:/Users/picha/Desktop/project/FMphoto/entry/src/main/ets/album/GalleryAlbumTab.ets): gallery tab shell, state binding, child-component assembly, and small glue code
- `album/galleryAlbumTab/`: gallery orchestration, visible-load control, state/selectors, timeline logic, gestures, and mode-specific loaders

`GalleryPreview` organization:

- [pages/GalleryPreview.ets](/D:/Users/picha/Desktop/project/FMphoto/entry/src/main/ets/pages/GalleryPreview.ets): page shell, state binding, Swiper assembly, and host bridging
- `pages/galleryPreview/`: preview-only `actions`, `details logic`, `details sheet`, `chrome`, and data-source modules

`CategoryGallery` organization:

- [pages/CategoryGallery.ets](/D:/Users/picha/Desktop/project/FMphoto/entry/src/main/ets/pages/CategoryGallery.ets): page shell, state binding, and grouped grid assembly
- `pages/categoryGallery/`: Session runtime, grouped-list view data, selection controller, batch actions, and top chrome modules

`FolderBrowsePage` organization:

- [pages/FolderBrowsePage.ets](/D:/Users/picha/Desktop/project/FMphoto/entry/src/main/ets/pages/FolderBrowsePage.ets): page shell, state binding, cached host adapters, and mixed folder/media grid
- `pages/folderBrowsePage/`: Session runtime, path/data loader, selection controller, and batch actions

`RecycleBinPage` organization:

- [pages/RecycleBinPage.ets](/D:/Users/picha/Desktop/project/FMphoto/entry/src/main/ets/pages/RecycleBinPage.ets): page shell, state binding, cached host adapters, and recycle-bin grid assembly
- `pages/recycleBinPage/`: Session runtime, recycle-bin selection controller, batch actions, chrome, and batch bar modules

Refactor rule for future phases:

- keep request paths, params, response parsing, retries, and error branches semantically unchanged
- prefer adding thin shells and capability modules over expanding page or client entry files

HostBridge / 状态所有权（图库收敛）：

- 禁止新增 `asXxxHost()` 和页面内 HostBridge。新能力进入已有 Session、Coordinator 或窄 Port。
- `searchQuery`、`gallerySelectedIds`、网格 `selectedIds`、滚动/加载热路径不得进入父页响应式树。
- 每个状态字段只有一份存储；禁止 Session 与页面镜像双写。
- Coordinator 只暴露跨领域命令，不做成新的状态总线。
- GalleryAlbumTab / GalleryPreview / CategoryGallery / FolderBrowse / RecycleBin 运行态已进 Session；AuthVideo 仍只禁新增 HostBridge，不迁移。
- 字段、默认值、写入点和副作用基线见 [docs/gallery-state-refactor-baseline.md](../../../../docs/gallery-state-refactor-baseline.md)。
