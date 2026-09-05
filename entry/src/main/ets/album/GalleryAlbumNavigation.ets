/**
 * Home 内相册子页的 Navigation 导航门面。
 *
 * Home 仍是 Router 根页；相册内部使用 NavPathStack，避免每个子页继续叠加
 * 已不推荐的 pageTransition。独立预览页仍走 Router，一镜到底期间会暂时挂起本栈。
 */
export const GALLERY_ALBUM_NAV_DEPTH_KEY: string = 'galleryAlbumNavDepth';

export const GALLERY_ALBUM_ROUTE_CATEGORY: string = 'galleryAlbumCategory';
export const GALLERY_ALBUM_ROUTE_PERSON: string = 'galleryAlbumPerson';
export const GALLERY_ALBUM_ROUTE_SMART: string = 'galleryAlbumSmart';
export const GALLERY_ALBUM_ROUTE_MAP: string = 'galleryAlbumMap';
export const GALLERY_ALBUM_ROUTE_RECYCLE: string = 'galleryAlbumRecycle';

export class GalleryAlbumNavigationParam {
  baseUrl: string = '';
}

AppStorage.setOrCreate(GALLERY_ALBUM_NAV_DEPTH_KEY, 0);

export class GalleryAlbumNavigation {
  private static stack: NavPathStack | null = null;
  private static suspended: boolean = false;
  private static backHandler: (() => boolean) | null = null;
  private static backHandlerToken: number = 0;

  static attach(stack: NavPathStack): void {
    GalleryAlbumNavigation.stack = stack;
    GalleryAlbumNavigation.suspended = false;
    GalleryAlbumNavigation.syncDepth();
  }

  static detach(stack: NavPathStack): void {
    if (GalleryAlbumNavigation.stack !== stack) {
      return;
    }
    GalleryAlbumNavigation.stack = null;
    GalleryAlbumNavigation.backHandler = null;
    AppStorage.setOrCreate(GALLERY_ALBUM_NAV_DEPTH_KEY, 0);
  }

  /** Router 预览覆盖 Home 时暂停入栈，预览内打开文件夹继续走原 Router 兼容页。 */
  static setSuspended(value: boolean): void {
    GalleryAlbumNavigation.suspended = value;
  }

  static isAvailable(): boolean {
    return GalleryAlbumNavigation.stack !== null && !GalleryAlbumNavigation.suspended;
  }

  static push(name: string, param?: Object): boolean {
    if (GalleryAlbumNavigation.stack === null || GalleryAlbumNavigation.suspended) {
      return false;
    }
    try {
      GalleryAlbumNavigation.stack.pushPath({ name: name, param: param });
      GalleryAlbumNavigation.syncDepth();
      return true;
    } catch (_e) {
      return false;
    }
  }

  static pop(): boolean {
    if (GalleryAlbumNavigation.suspended ||
      GalleryAlbumNavigation.stack === null ||
      GalleryAlbumNavigation.stack.size() <= 0) {
      return false;
    }
    try {
      GalleryAlbumNavigation.stack.pop();
      GalleryAlbumNavigation.backHandler = null;
      GalleryAlbumNavigation.syncDepth();
      return true;
    } catch (_e) {
      return false;
    }
  }

  /** 子页注册自己的返回优先级（弹窗/多选/WebView 后退），Home 硬件返回统一转发。 */
  static registerBackHandler(handler: () => boolean): number {
    const token = ++GalleryAlbumNavigation.backHandlerToken;
    GalleryAlbumNavigation.backHandler = handler;
    return token;
  }

  static unregisterBackHandler(token: number): void {
    if (token !== GalleryAlbumNavigation.backHandlerToken) {
      return;
    }
    GalleryAlbumNavigation.backHandler = null;
  }

  static handleBack(): boolean {
    if (GalleryAlbumNavigation.suspended ||
      GalleryAlbumNavigation.stack === null ||
      GalleryAlbumNavigation.stack.size() <= 0) {
      return false;
    }
    if (GalleryAlbumNavigation.backHandler !== null) {
      return GalleryAlbumNavigation.backHandler();
    }
    return GalleryAlbumNavigation.pop();
  }

  private static syncDepth(): void {
    const depth = GalleryAlbumNavigation.stack === null ? 0 : GalleryAlbumNavigation.stack.size();
    AppStorage.setOrCreate(GALLERY_ALBUM_NAV_DEPTH_KEY, depth);
  }
}
