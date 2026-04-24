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

`GalleryPreview` organization:

- [pages/GalleryPreview.ets](/D:/Users/picha/Desktop/project/FMphoto/entry/src/main/ets/pages/GalleryPreview.ets): page shell, state binding, Swiper assembly, and host bridging
- `pages/galleryPreview/`: preview-only `actions`, `details logic`, `details sheet`, `chrome`, and data-source modules

Refactor rule for future phases:

- keep request paths, params, response parsing, retries, and error branches semantically unchanged
- prefer adding thin shells and capability modules over expanding page or client entry files
