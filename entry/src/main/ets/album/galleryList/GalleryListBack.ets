/**
 * 相册子页返回：先关浮层 / 退出多选，再 pop。
 * 各页只声明优先级，不要再各写一遍 if 链。
 */
import { GalleryAlbumNavigation } from '../GalleryAlbumNavigation';

export class GalleryListBackStep {
  active: boolean;
  dismiss: () => void;

  constructor(active: boolean, dismiss: () => void) {
    this.active = active;
    this.dismiss = dismiss;
  }
}

export function galleryListTryConsumeOverlays(steps: GalleryListBackStep[]): boolean {
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    if (step.active) {
      step.dismiss();
      return true;
    }
  }
  return false;
}

export function galleryListPopOrRouterBack(albumNavigationMode: boolean, routerBack: () => void): void {
  if (!albumNavigationMode || !GalleryAlbumNavigation.pop()) {
    routerBack();
  }
}
