/**
 * 宫格多选遮罩。
 *
 * 官方建议：频繁变化的选中态不要走 AppStorage revision / 列表父组件 @State。
 * 遮罩用自身 @State 刷新，划选只通知状态变化的单元格。
 */
export const GALLERY_ALBUM_SELECTION_VISUAL_MODE_KEY: string = 'galleryAlbumSelectionVisualMode';

let galleryAlbumSelectedVisualIds: Set<string> = new Set<string>();
let galleryAlbumSelectionVisualStorageReady: boolean = false;
const galleryAlbumOverlaySetters: Map<string, ((selected: boolean) => void)[]> =
  new Map<string, ((selected: boolean) => void)[]>();

function setAppStorageBool(key: string, value: boolean): void {
  if (AppStorage.has(key)) {
    AppStorage.set<boolean>(key, value);
    return;
  }
  AppStorage.setOrCreate<boolean>(key, value);
}

function notifyCellSelected(id: string, selected: boolean): void {
  const setters = galleryAlbumOverlaySetters.get(id);
  if (setters === undefined) {
    return;
  }
  for (let i = 0; i < setters.length; i++) {
    setters[i](selected);
  }
}

export function galleryAlbumEnsureSelectionVisualStorage(): void {
  if (galleryAlbumSelectionVisualStorageReady) {
    return;
  }
  AppStorage.setOrCreate<boolean>(GALLERY_ALBUM_SELECTION_VISUAL_MODE_KEY, false);
  galleryAlbumSelectionVisualStorageReady = true;
}

export function galleryAlbumRegisterSelectionOverlay(
  id: string,
  setter: (selected: boolean) => void
): void {
  if (id.length === 0) {
    return;
  }
  const current = galleryAlbumOverlaySetters.get(id);
  if (current === undefined) {
    galleryAlbumOverlaySetters.set(id, [setter]);
    return;
  }
  current.push(setter);
}

export function galleryAlbumUnregisterSelectionOverlay(
  id: string,
  setter: (selected: boolean) => void
): void {
  const current = galleryAlbumOverlaySetters.get(id);
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
    galleryAlbumOverlaySetters.delete(id);
    return;
  }
  galleryAlbumOverlaySetters.set(id, next);
}

export function galleryAlbumSyncSelectionVisualState(selectionMode: boolean, selectedIds: string[]): void {
  galleryAlbumEnsureSelectionVisualStorage();
  const next = new Set<string>();
  for (let i = 0; i < selectedIds.length; i++) {
    const id = selectedIds[i];
    if (id.length > 0) {
      next.add(id);
    }
  }
  const prev = galleryAlbumSelectedVisualIds;
  prev.forEach((id: string): void => {
    if (!next.has(id)) {
      notifyCellSelected(id, false);
    }
  });
  next.forEach((id: string): void => {
    if (!prev.has(id)) {
      notifyCellSelected(id, true);
    }
  });
  galleryAlbumSelectedVisualIds = next;
  setAppStorageBool(GALLERY_ALBUM_SELECTION_VISUAL_MODE_KEY, selectionMode);
}

export function galleryAlbumIsSelectionVisualIdSelected(id: string): boolean {
  return id.length > 0 && galleryAlbumSelectedVisualIds.has(id);
}

@Component
export struct GalleryAlbumSelectionOverlay {
  @Prop itemId: string = '';
  @StorageLink(GALLERY_ALBUM_SELECTION_VISUAL_MODE_KEY) private selectionMode: boolean = false;
  @State private selected: boolean = false;
  private applySelected: (value: boolean) => void = (value: boolean): void => {
    this.selected = value;
  };

  aboutToAppear(): void {
    this.selected = galleryAlbumIsSelectionVisualIdSelected(this.itemId);
    galleryAlbumRegisterSelectionOverlay(this.itemId, this.applySelected);
  }

  aboutToDisappear(): void {
    galleryAlbumUnregisterSelectionOverlay(this.itemId, this.applySelected);
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
