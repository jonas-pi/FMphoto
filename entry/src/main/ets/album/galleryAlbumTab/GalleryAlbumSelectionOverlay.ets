/**
 * 宫格多选遮罩。
 *
 * 官方建议：频繁变化的选中态不要走列表父组件 @State。
 * 遮罩用自身 @State 刷新，划选只通知状态变化的单元格。
 * visualScope 隔离主图库 / 分类子页 / 回收站，避免路由栈叠页时串选。
 */

export const GALLERY_SELECTION_SCOPE_ALBUM: string = 'album';
export const GALLERY_SELECTION_SCOPE_CATEGORY: string = 'category';
export const GALLERY_SELECTION_SCOPE_RECYCLE: string = 'recycle';

let galleryAlbumSelectedVisualIds: Set<string> = new Set<string>();
const galleryAlbumOverlaySetters: Map<string, ((selected: boolean) => void)[]> =
  new Map<string, ((selected: boolean) => void)[]>();

function visualCellKey(scope: string, id: string): string {
  return `${scope}:${id}`;
}

function notifyCellSelected(key: string, selected: boolean): void {
  const setters = galleryAlbumOverlaySetters.get(key);
  if (setters === undefined) {
    return;
  }
  for (let i = 0; i < setters.length; i++) {
    setters[i](selected);
  }
}

export function galleryAlbumEnsureSelectionVisualStorage(): void {
}

export function galleryAlbumRegisterSelectionOverlay(
  id: string,
  setter: (selected: boolean) => void,
  visualScope: string = GALLERY_SELECTION_SCOPE_ALBUM
): void {
  if (id.length === 0) {
    return;
  }
  const key = visualCellKey(visualScope, id);
  const current = galleryAlbumOverlaySetters.get(key);
  if (current === undefined) {
    galleryAlbumOverlaySetters.set(key, [setter]);
    return;
  }
  current.push(setter);
}

export function galleryAlbumUnregisterSelectionOverlay(
  id: string,
  setter: (selected: boolean) => void,
  visualScope: string = GALLERY_SELECTION_SCOPE_ALBUM
): void {
  const key = visualCellKey(visualScope, id);
  const current = galleryAlbumOverlaySetters.get(key);
  if (current === undefined) {
    return;
  }
  const next: ((selected: boolean) => void)[] = [];
  for (let i = 0; i < current.length; i++) {
    if (current[i] !== setter) {
      next.push(current[i]);
    }
  }
  if (next.length === 0) {
    galleryAlbumOverlaySetters.delete(key);
    return;
  }
  galleryAlbumOverlaySetters.set(key, next);
}

export function galleryAlbumSyncSelectionVisualState(
  selectionMode: boolean,
  selectedIds: string[],
  visualScope: string = GALLERY_SELECTION_SCOPE_ALBUM
): void {
  const next = new Set<string>();
  for (let i = 0; i < selectedIds.length; i++) {
    const id = selectedIds[i];
    if (id.length > 0) {
      next.add(visualCellKey(visualScope, id));
    }
  }
  const prev = galleryAlbumSelectedVisualIds;
  prev.forEach((key: string): void => {
    if (key.indexOf(`${visualScope}:`) !== 0) {
      return;
    }
    if (!next.has(key)) {
      notifyCellSelected(key, false);
    }
  });
  next.forEach((key: string): void => {
    if (!prev.has(key)) {
      notifyCellSelected(key, true);
    }
  });
  const merged = new Set<string>();
  prev.forEach((key: string): void => {
    if (key.indexOf(`${visualScope}:`) !== 0) {
      merged.add(key);
    }
  });
  next.forEach((key: string): void => {
    merged.add(key);
  });
  galleryAlbumSelectedVisualIds = merged;
}

export function galleryAlbumIsSelectionVisualIdSelected(
  id: string,
  visualScope: string = GALLERY_SELECTION_SCOPE_ALBUM
): boolean {
  return id.length > 0 && galleryAlbumSelectedVisualIds.has(visualCellKey(visualScope, id));
}

@Component
export struct GalleryAlbumSelectionOverlay {
  @Prop itemId: string = '';
  @Prop visualScope: string = GALLERY_SELECTION_SCOPE_ALBUM;
  @Prop selectionMode: boolean = false;
  @State private selected: boolean = false;
  private applySelected: (value: boolean) => void = (value: boolean): void => {
    this.selected = value;
  };

  aboutToAppear(): void {
    this.selected = galleryAlbumIsSelectionVisualIdSelected(this.itemId, this.visualScope);
    galleryAlbumRegisterSelectionOverlay(this.itemId, this.applySelected, this.visualScope);
  }

  aboutToDisappear(): void {
    galleryAlbumUnregisterSelectionOverlay(this.itemId, this.applySelected, this.visualScope);
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .aspectRatio(1)
        .backgroundColor('#55000000')
        .opacity(this.selectionMode && this.selected ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
        .animation({ duration: 0, curve: Curve.Linear })

      Row() {
        Blank().layoutWeight(1)
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(22)
            .height(22)
            .fill(Color.Transparent)
            .stroke(Color.White)
            .strokeWidth(2)
            .opacity(this.selected ? 0 : 1)

          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(24)
            .fontColor([$r('app.color.brand_primary')])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .opacity(this.selected ? 1 : 0)
        }
        .width(24)
        .height(24)
        .padding({ top: 6, right: 6 })
        .animation({ duration: 0, curve: Curve.Linear })
      }
      .width('100%')
      .hitTestBehavior(HitTestMode.None)
      .visibility(this.selectionMode ? Visibility.Visible : Visibility.Hidden)
    }
    .width('100%')
    .aspectRatio(1)
    .hitTestBehavior(HitTestMode.None)
  }
}
