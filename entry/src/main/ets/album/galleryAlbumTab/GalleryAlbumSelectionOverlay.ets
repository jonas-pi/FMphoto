export const GALLERY_ALBUM_SELECTION_VISUAL_MODE_KEY: string = 'galleryAlbumSelectionVisualMode';
export const GALLERY_ALBUM_SELECTION_VISUAL_REVISION_KEY: string = 'galleryAlbumSelectionVisualRevision';

let galleryAlbumSelectedVisualIds: Set<string> = new Set<string>();
let galleryAlbumSelectionVisualStorageReady: boolean = false;

function setAppStorageBool(key: string, value: boolean): void {
  if (AppStorage.has(key)) {
    AppStorage.set<boolean>(key, value);
    return;
  }
  AppStorage.setOrCreate<boolean>(key, value);
}

function setAppStorageNumber(key: string, value: number): void {
  if (AppStorage.has(key)) {
    AppStorage.set<number>(key, value);
    return;
  }
  AppStorage.setOrCreate<number>(key, value);
}

export function galleryAlbumEnsureSelectionVisualStorage(): void {
  if (galleryAlbumSelectionVisualStorageReady) {
    return;
  }
  AppStorage.setOrCreate<boolean>(GALLERY_ALBUM_SELECTION_VISUAL_MODE_KEY, false);
  AppStorage.setOrCreate<number>(GALLERY_ALBUM_SELECTION_VISUAL_REVISION_KEY, 0);
  galleryAlbumSelectionVisualStorageReady = true;
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
  galleryAlbumSelectedVisualIds = next;
  setAppStorageBool(GALLERY_ALBUM_SELECTION_VISUAL_MODE_KEY, selectionMode);
  const oldRevision = AppStorage.get<number>(GALLERY_ALBUM_SELECTION_VISUAL_REVISION_KEY) ?? 0;
  setAppStorageNumber(GALLERY_ALBUM_SELECTION_VISUAL_REVISION_KEY, oldRevision + 1);
}

export function galleryAlbumIsSelectionVisualIdSelected(id: string): boolean {
  return id.length > 0 && galleryAlbumSelectedVisualIds.has(id);
}

@Component
export struct GalleryAlbumSelectionOverlay {
  @Prop itemId: string = '';
  @StorageLink(GALLERY_ALBUM_SELECTION_VISUAL_MODE_KEY) private selectionMode: boolean = false;
  @StorageLink(GALLERY_ALBUM_SELECTION_VISUAL_REVISION_KEY) private selectionRevision: number = 0;

  private isSelected(): boolean {
    if (this.selectionRevision < 0) {
      return false;
    }
    return galleryAlbumIsSelectionVisualIdSelected(this.itemId);
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .aspectRatio(1)
        .backgroundColor('#55000000')
        .opacity(this.selectionMode && this.isSelected() ? 1 : 0)
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
            .opacity(this.isSelected() ? 0 : 1)

          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(24)
            .fontColor([$r('app.color.brand_primary')])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .opacity(this.isSelected() ? 1 : 0)
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
