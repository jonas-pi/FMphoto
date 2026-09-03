import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AiPersonItem,
  GalleryListItem,
  MagicSearchItem,
  MediaCategoryItem,
  SmartCategoryItem
} from '../../model/FnApiTypes';
import { AppSession } from '../../auth/AppSession';
import { BackgroundKeepAliveController } from '../../background/BackgroundKeepAliveController';
import { FN_GLOBAL_TAB_SWITCH_OFFSET_VP, FN_TAB_SWITCH_CURVE, FN_TAB_SWITCH_IN_DURATION } from '../../common/FnMotion';
import { CategoryGalleryNavStore } from '../CategoryGalleryNavStore';
import { GalleryTimelineRefreshStore } from '../GalleryTimelineRefreshStore';
import { GalleryAutoSyncStore } from '../GalleryAutoSyncStore';
import { triggerAutoSyncDetection } from '../GalleryAutoSyncBadge';
import { AutoSyncRunnerCallbacks, runAutoSyncInBackground } from '../GalleryAutoSyncSheet';
import { LocalPhotoEntry } from '../GalleryAutoSyncService';
import {
  filterUnsyncedPickerUrisWithIndex,
  fileNameFromPickerUri,
  localPhotoEntryFromPickerUri
} from '../GalleryAutoSyncPicker';
import { fnEnsureReadImageVideoGranted } from '../../common/FnMediaPermission';
import { FnTransferDirection, fnTransferDirectionLabel } from '../../common/FnTransferProgress';
import { FnTransferQueueStore } from '../../common/FnTransferQueueStore';
import { GalleryAutoSyncLedger } from '../GalleryAutoSyncLedger';
import { GalleryAutoSyncNasIndex } from '../GalleryAutoSyncNasIndex';
import { uploadUriMaybeMovingPhoto } from '../livephoto/LivePhotoUpload';
import { openPersonAlbumById } from '../PersonAlbumOpenHelper';
import { openMediaCategoryGallery, openingTextForCategory } from '../MediaCategoryOpenHelper';
import {
  galleryMediaCategoryModeLoader,
  galleryPersonModeLoader,
  gallerySmartCategoryModeLoader,
  loadCollectGalleryItems,
  loadRecentAddedItems,
  loadSmartCategories
} from './GalleryAlbumModeLoaders';
import { fillAndPersistCustomSmartCategoryCovers, enrichSmartCategoryCountsFromSearch } from '../SmartCategoryMagicSearch';
import { smartCategoryPatchCountByName } from '../SmartCategoryLayoutPreferences';
import { SmartCategoryCountStore } from '../SmartCategoryCountStore';
import {
  categoryTitle,
  personId,
  personName
} from './GalleryAlbumModeData';
import { GALLERY_UPLOAD_RECHECK_MS } from './GalleryAlbumTabConstants';

/** 相册模式编排宿主 */
export interface GalleryAlbumModeOrchestratorHost extends AutoSyncRunnerCallbacks {
  getUIContext(): UIContext;
  baseUrl: string;
  modeSwitchOpacity: number;
  modeSwitchOffsetY: number;
  inSearchMode: boolean;
  inCategoryMode: boolean;
  inSmartCategoryMode: boolean;
  inPersonMode: boolean;
  searchQuery: string;
  searchLoading: boolean;
  searchError: string;
  searchResults: GalleryListItem[];
  categoryLoading: boolean;
  categoryOpening: boolean;
  categoryOpeningText: string;
  categoryError: string;
  categoryItems: MediaCategoryItem[];
  smartCategoryLoading: boolean;
  smartCategoryError: string;
  smartSceneItems: SmartCategoryItem[];
  smartInfoItems: SmartCategoryItem[];
  smartCustomItems: SmartCategoryItem[];
  personLoading: boolean;
  personOpening: boolean;
  personError: string;
  personItems: AiPersonItem[];
  personStatOverrides: Map<string, string>;
  personStatVersion: number;
  personStatGen: number;
  recentOpening: boolean;
  collectOpening: boolean;
  syncBadgeCount: number;
  lastBootstrapSatisfiedRefreshVersion: number;
  exitGallerySelection(): void;
  requestBootstrap(debounced: boolean): void;
  bootstrap(showFullBleedSkeleton?: boolean): Promise<void>;
  itemIdOf(item: GalleryListItem): string;
  createNavigationGuard(): () => boolean;
}

function clearAllSubModeFlags(host: GalleryAlbumModeOrchestratorHost): void {
  host.inSearchMode = false;
  host.inCategoryMode = false;
  host.inSmartCategoryMode = false;
  host.inPersonMode = false;
}

export function galleryAlbumPlayModeSwitchMotion(host: GalleryAlbumModeOrchestratorHost, direction: number = 1): void {
  host.modeSwitchOpacity = 1;
  host.modeSwitchOffsetY = FN_GLOBAL_TAB_SWITCH_OFFSET_VP * (direction >= 0 ? 1 : -1);
  host.getUIContext().animateTo(
    { duration: FN_TAB_SWITCH_IN_DURATION, curve: FN_TAB_SWITCH_CURVE },
    (): void => {
      host.modeSwitchOpacity = 1;
      host.modeSwitchOffsetY = 0;
    }
  );
}

export async function galleryAlbumRunSearch(
  host: GalleryAlbumModeOrchestratorHost,
  keyword: string
): Promise<void> {
  const kw = keyword.trim();
  if (kw.length === 0) {
    return;
  }
  host.exitGallerySelection();
  galleryAlbumPlayModeSwitchMotion(host, 1);
  host.inSearchMode = true;
  host.inCategoryMode = false;
  host.inSmartCategoryMode = false;
  host.inPersonMode = false;
  host.searchLoading = true;
  host.searchError = '';
  host.searchResults = [];
  const client = AppSession.getClient();

  if (client === null) {
    host.searchError = '未登录';
    host.searchLoading = false;
    return;
  }
  try {
    const res = await client.doMagicSearch(kw);
    if (!res.success || res.data === undefined) {
      host.searchError = res.message ?? '搜索失败';
      host.searchLoading = false;
      return;
    }
    const rawList = res.data.list ?? [];
    host.searchResults = rawList.map((item: MagicSearchItem): GalleryListItem => {
      const hasRichMedia =
        item.additional !== undefined ||
        item.thumbnail !== undefined ||
        item.category !== undefined ||
        item.fileType !== undefined;
      if (hasRichMedia) {
        return item as GalleryListItem;
      }
      const id = item.id !== undefined ? String(item.id) : '';
      const session = item.session !== undefined ? item.session : '';
      if (id.length > 0 && session.length > 0) {
        return {
          id: id,
          thumb: `/p/api/v1/stream/p/t/${id}/s/${session}`
        };
      }
      return item as GalleryListItem;
    });
    if (host.searchResults.length === 0) {
      host.searchError = '未找到相关媒体';
    }
  } catch (e) {
    host.searchError = String(e) || '搜索异常';
  }
  host.searchLoading = false;
}

export function galleryAlbumClearSearch(host: GalleryAlbumModeOrchestratorHost): void {
  host.inSearchMode = false;
  host.searchQuery = '';
  host.searchResults = [];
  host.searchError = '';
  host.searchLoading = false;
}

export function galleryAlbumClearCategory(host: GalleryAlbumModeOrchestratorHost): void {
  host.inCategoryMode = false;
  host.categoryLoading = false;
  host.categoryError = '';
  host.categoryItems = [];
}

export function galleryAlbumClearSmartCategory(host: GalleryAlbumModeOrchestratorHost): void {
  host.inSmartCategoryMode = false;
  host.smartCategoryLoading = false;
  host.smartCategoryError = '';
  host.smartSceneItems = [];
  host.smartInfoItems = [];
  host.smartCustomItems = [];
}

export function galleryAlbumClearPerson(host: GalleryAlbumModeOrchestratorHost): void {
  host.inPersonMode = false;
  host.personLoading = false;
  host.personError = '';
  host.personItems = [];
}

export function galleryAlbumBackToMain(host: GalleryAlbumModeOrchestratorHost): void {
  host.exitGallerySelection();
  galleryAlbumPlayModeSwitchMotion(host, -1);
  galleryAlbumClearSearch(host);
  galleryAlbumClearCategory(host);
  galleryAlbumClearSmartCategory(host);
  galleryAlbumClearPerson(host);
  if (GalleryTimelineRefreshStore.version > host.lastBootstrapSatisfiedRefreshVersion) {
    host.requestBootstrap(true);
  }
}

export function galleryAlbumTryConsumeHardwareBack(host: GalleryAlbumModeOrchestratorHost): boolean {
  if (!host.inSearchMode && !host.inCategoryMode && !host.inSmartCategoryMode && !host.inPersonMode) {
    return false;
  }
  galleryAlbumBackToMain(host);
  return true;
}

export function galleryAlbumStartUpload(host: GalleryAlbumModeOrchestratorHost): void {
  if (FnTransferQueueStore.hasRunning()) {
    host.toast('已有传输任务进行中');
    return;
  }
  host.exitGallerySelection();
  void galleryAlbumPickAndUpload(host);
}

export async function galleryAlbumPickAndUpload(host: GalleryAlbumModeOrchestratorHost): Promise<void> {
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  let uris: string[] = [];
  try {
    const opt = new photoAccessHelper.PhotoSelectOptions();
    opt.maxSelectNumber = 20;
    opt.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    const out = await new photoAccessHelper.PhotoViewPicker().select(opt);
    uris = out.photoUris ?? [];
  } catch (_e) {
    return;
  }
  if (uris.length === 0) {
    return;
  }
  galleryAlbumUploadUriListInBackground(host, uris, FnTransferDirection.UPLOAD, 'album-upload', '上传');
}

/**
 * 从「更多」菜单启动本地同步。
 * 优先全量扫描（READ_IMAGEVIDEO ACL）；无权限时回退 Picker 选图。
 */
export function galleryAlbumStartAutoSync(
  host: GalleryAlbumModeOrchestratorHost,
  timelineItems: GalleryListItem[]
): void {
  if (FnTransferQueueStore.hasRunning()) {
    host.toast('已有传输任务进行中');
    return;
  }
  host.exitGallerySelection();
  const ctx = host.getUIContext().getHostContext() as common.UIAbilityContext;
  void (async (): Promise<void> => {
    try {
      const client = AppSession.getClient();
      if (client === null) {
        host.toast('未登录');
        return;
      }
      const granted = await fnEnsureReadImageVideoGranted(ctx);
      if (granted) {
        const checkId = FnTransferQueueStore.begin(FnTransferDirection.SYNC, '检查待同步照片', 0);
        const result = await GalleryAutoSyncStore.detectUnsynced(ctx, client, true, timelineItems);
        FnTransferQueueStore.finish(
          checkId,
          true,
          result.unsynced.length === 0
            ? `均已同步（跳过 NAS ${result.skippedOnNas} / 账本 ${result.skippedInLedger}）`
            : `发现 ${result.unsynced.length} 张待同步`
        );
        host.syncBadgeCount = result.unsynced.length;
        if (result.unsynced.length === 0) {
          host.toast('没有需要同步的照片');
          return;
        }
        galleryAlbumRunAutoSync(host, result.unsynced);
        return;
      }
      host.toast('未获得相册读取权限，请手动选择照片');
      await galleryAlbumPickAndSync(host);
    } catch (e) {
      hilog.warn(0xFF00, 'AutoSync', 'galleryAlbumStartAutoSync failed: %{public}s', String(e));
      host.toast('同步失败，请稍后重试');
    }
  })();
}

async function galleryAlbumPickAndSync(host: GalleryAlbumModeOrchestratorHost): Promise<void> {
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  let uris: string[] = [];
  try {
    const opt = new photoAccessHelper.PhotoSelectOptions();
    opt.maxSelectNumber = 500;
    opt.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    const out = await new photoAccessHelper.PhotoViewPicker().select(opt);
    uris = out.photoUris ?? [];
  } catch (_e) {
    return;
  }
  if (uris.length === 0) {
    return;
  }
  const ctx = host.getUIContext().getHostContext() as common.UIAbilityContext;
  const nasIndex = await GalleryAutoSyncNasIndex.getIndex(client, false);
  const ledger = await GalleryAutoSyncLedger.load(ctx);
  const toUpload = filterUnsyncedPickerUrisWithIndex(uris, nasIndex, ledger);
  if (toUpload.length === 0) {
    host.toast('所选照片已在 NAS 中');
    return;
  }
  if (toUpload.length < uris.length) {
    host.toast(`已跳过 ${uris.length - toUpload.length} 张已同步照片`);
  }
  galleryAlbumUploadUriListInBackground(host, toUpload, FnTransferDirection.SYNC, 'auto-sync', '同步');
}

/**
 * Bootstrap 后后台检测未同步数量（非阻塞）。
 */
export function galleryAlbumTriggerAutoSync(
  host: GalleryAlbumModeOrchestratorHost,
  timelineItems: GalleryListItem[]
): void {
  const ctx = host.getUIContext().getHostContext() as common.UIAbilityContext;
  triggerAutoSyncDetection(ctx, timelineItems, (unsyncedCount: number): void => {
    host.syncBadgeCount = unsyncedCount;
  });
}

export function galleryAlbumRunAutoSync(
  host: GalleryAlbumModeOrchestratorHost,
  photos: LocalPhotoEntry[]
): void {
  const ctx = host.getUIContext().getHostContext() as common.UIAbilityContext;
  runAutoSyncInBackground(ctx, photos, host);
  host.syncBadgeCount = GalleryAutoSyncStore.getUnsyncedCount();
}

function galleryAlbumUploadUriListInBackground(
  host: GalleryAlbumModeOrchestratorHost,
  uris: string[],
  direction: FnTransferDirection,
  keepAliveTag: string,
  doneVerb: string
): void {
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  if (uris.length === 0) {
    return;
  }
  const ctx = host.getUIContext().getHostContext() as common.UIAbilityContext;
  const label = fnTransferDirectionLabel(direction);
  void (async (): Promise<void> => {
    const taskId = FnTransferQueueStore.begin(direction, label, uris.length);
    let ok = 0;
    let firstFailMsg = '';
    const stored = AppSession.getStored();
    const albumDirHint =
      stored !== null && stored.albumParentGuid.trim().length > 0 ? stored.albumParentGuid.trim() : undefined;
    try {
      await BackgroundKeepAliveController.withDataTransfer(ctx, keepAliveTag, async (): Promise<void> => {
        for (let i = 0; i < uris.length; i++) {
          const uri = uris[i];
          FnTransferQueueStore.update(taskId, i + 1, fileNameFromPickerUri(uri));
          const res = await uploadUriMaybeMovingPhoto(client, ctx, uri, 150000, albumDirHint);
          if (res.success) {
            ok++;
            // Picker / 手动上传成功后写入账本，避免下次同步再次判定为未同步
            const entry = localPhotoEntryFromPickerUri(uri);
            await GalleryAutoSyncLedger.markSynced(ctx, [entry]);
            GalleryAutoSyncStore.markSynced([uri]);
            GalleryAutoSyncNasIndex.addLocalEntries([entry]);
          } else if (firstFailMsg.length === 0) {
            const em = res.message ?? '';
            firstFailMsg = em.length > 0 ? em : `${doneVerb}失败`;
          }
        }
      });
    } finally {
      const summary = ok > 0 ? `${doneVerb}完成 ${ok}/${uris.length}` : (firstFailMsg.length > 0 ? firstFailMsg : `${doneVerb}失败`);
      FnTransferQueueStore.finish(taskId, ok > 0, summary);
    }
    if (ok > 0) {
      host.toast(`${doneVerb}完成 ${ok}/${uris.length}`);
      GalleryTimelineRefreshStore.bump();
      host.requestBootstrap(false);
      setTimeout((): void => {
        void host.bootstrap(false);
      }, GALLERY_UPLOAD_RECHECK_MS);
    } else {
      host.toast(firstFailMsg.length > 0 ? firstFailMsg : `${doneVerb}失败，请稍后重试`);
    }
  })();
}

export async function galleryAlbumLoadMediaCategories(host: GalleryAlbumModeOrchestratorHost): Promise<void> {
  host.exitGallerySelection();
  galleryAlbumPlayModeSwitchMotion(host, 1);
  clearAllSubModeFlags(host);
  host.inCategoryMode = true;
  host.categoryLoading = true;
  host.categoryError = '';
  host.categoryItems = galleryMediaCategoryModeLoader.reset().items;
  const client = AppSession.getClient();
  if (client === null) {
    host.categoryError = '未登录';
    host.categoryLoading = false;
    return;
  }
  const result = await galleryMediaCategoryModeLoader.load(client);
  host.categoryItems = result.data.items;
  host.categoryError = result.error;
  host.categoryLoading = false;
}

export async function galleryAlbumLoadSmartCategories(host: GalleryAlbumModeOrchestratorHost): Promise<void> {
  host.exitGallerySelection();
  galleryAlbumPlayModeSwitchMotion(host, 1);
  clearAllSubModeFlags(host);
  host.inSmartCategoryMode = true;
  host.smartCategoryLoading = true;
  host.smartCategoryError = '';
  const reset = gallerySmartCategoryModeLoader.reset();
  host.smartSceneItems = reset.sceneItems;
  host.smartInfoItems = reset.infoItems;
  host.smartCustomItems = reset.customItems;
  const client = AppSession.getClient();
  if (client === null) {
    host.smartCategoryError = '未登录';
    host.smartCategoryLoading = false;
    return;
  }
  const ctx = host.getUIContext().getHostContext() as common.UIAbilityContext;
  const result = await loadSmartCategories(client, ctx);
  host.smartSceneItems = result.sceneItems;
  host.smartInfoItems = result.infoItems;
  host.smartCustomItems = result.customItems;
  host.smartCategoryError = result.error;
  host.smartCategoryLoading = false;
  void (async (): Promise<void> => {
    const filled = await fillAndPersistCustomSmartCategoryCovers(
      client,
      ctx,
      result.sceneItems,
      result.infoItems,
      result.customItems
    );
    if (!host.inSmartCategoryMode) {
      return;
    }
    host.smartCustomItems = filled;
  })();
  void (async (): Promise<void> => {
    await enrichSmartCategoryCountsFromSearch(client, result.sceneItems, (name: string, count: number): boolean => {
      if (!host.inSmartCategoryMode) {
        return false;
      }
      SmartCategoryCountStore.put(name, count);
      host.smartSceneItems = smartCategoryPatchCountByName(host.smartSceneItems, name, count);
      return true;
    });
    if (!host.inSmartCategoryMode) {
      return;
    }
    await enrichSmartCategoryCountsFromSearch(client, result.infoItems, (name: string, count: number): boolean => {
      if (!host.inSmartCategoryMode) {
        return false;
      }
      SmartCategoryCountStore.put(name, count);
      host.smartInfoItems = smartCategoryPatchCountByName(host.smartInfoItems, name, count);
      return true;
    });
  })();
}

export async function galleryAlbumEnrichPersonStats(
  host: GalleryAlbumModeOrchestratorHost,
  items: AiPersonItem[],
  gen: number
): Promise<void> {
  const client = AppSession.getClient();
  if (client === null) {
    return;
  }
  for (let i = 0; i < items.length; i++) {
    if (gen !== host.personStatGen) {
      return;
    }
    const pid = personId(items[i]);
    if (pid.length === 0) {
      continue;
    }
    if (host.personStatOverrides.has(pid)) {
      continue;
    }
    const one = await client.getAiPersonDetail(pid, 12000);
    if (gen !== host.personStatGen) {
      return;
    }
    if (!one.success || one.data === undefined) {
      continue;
    }
    const pRaw = one.data.photoCount;
    const vRaw = one.data.videoCount;
    if (!Number.isFinite(Number(pRaw)) && !Number.isFinite(Number(vRaw))) {
      continue;
    }
    const p = Number.isFinite(Number(pRaw)) ? Math.max(0, Math.floor(Number(pRaw))) : 0;
    const v = Number.isFinite(Number(vRaw)) ? Math.max(0, Math.floor(Number(vRaw))) : 0;
    host.personStatOverrides.set(pid, `${p} 张照片 · ${v} 个视频`);
    host.personStatVersion++;
  }
}

export async function galleryAlbumLoadPersons(host: GalleryAlbumModeOrchestratorHost): Promise<void> {
  host.exitGallerySelection();
  galleryAlbumPlayModeSwitchMotion(host, 1);
  host.personOpening = false;
  clearAllSubModeFlags(host);
  host.inPersonMode = true;
  host.personLoading = true;
  host.personError = '';
  host.personItems = galleryPersonModeLoader.reset().items;
  host.personStatOverrides.clear();
  host.personStatVersion++;
  host.personStatGen++;
  const client = AppSession.getClient();
  if (client === null) {
    host.personError = '未登录';
    host.personLoading = false;
    return;
  }
  const result = await galleryPersonModeLoader.load(client);
  host.personItems = result.data.items;
  host.personError = result.error;
  if (result.data.items.length > 0) {
    const gen = host.personStatGen;
    void galleryAlbumEnrichPersonStats(host, result.data.items, gen);
  }
  host.personLoading = false;
}

export async function galleryAlbumOpenPerson(
  host: GalleryAlbumModeOrchestratorHost,
  item: AiPersonItem
): Promise<void> {
  if (host.personOpening) {
    return;
  }
  const pid = personId(item);
  if (pid.length === 0) {
    host.toast('人物 ID 无效');
    return;
  }
  host.personOpening = true;
  const isActive = host.createNavigationGuard();
  let keepOpening = false;
  try {
    const result = await openPersonAlbumById(
      host.baseUrl,
      pid,
      personName(item),
      host.getUIContext(),
      isActive
    );
    if (!isActive()) {
      return;
    }
    if (!result.ok) {
      if (result.errorMessage.length > 0) {
        host.toast(result.errorMessage);
      }
      return;
    }
    keepOpening = true;
    setTimeout((): void => {
      host.personOpening = false;
    }, 280);
  } finally {
    if (!keepOpening) {
      host.personOpening = false;
    }
  }
}

export async function galleryAlbumOpenCategory(
  host: GalleryAlbumModeOrchestratorHost,
  cat: MediaCategoryItem
): Promise<void> {
  if (host.categoryOpening) {
    return;
  }
  host.categoryOpening = true;
  const isActive = host.createNavigationGuard();
  const categoryKey = cat.key !== undefined ? cat.key.trim().toLowerCase() : '';
  host.categoryOpeningText = openingTextForCategory(categoryKey, categoryTitle(cat));
  try {
    await openMediaCategoryGallery(host.baseUrl, cat, host.getUIContext(), {
      isActive: isActive,
      onToast: (msg: string): void => {
        host.toast(msg);
      }
    });
  } finally {
    host.categoryOpening = false;
  }
}

export async function galleryAlbumOpenRecentAdded(host: GalleryAlbumModeOrchestratorHost): Promise<void> {
  if (host.recentOpening) {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  host.recentOpening = true;
  const isActive = host.createNavigationGuard();
  try {
    const result = await loadRecentAddedItems(
      client,
      (item: GalleryListItem): string => host.itemIdOf(item),
      isActive
    );
    if (!isActive()) {
      return;
    }
    if (result.items.length <= 0) {
      if (result.error.length > 0) {
        host.toast(result.error);
      }
      return;
    }
    CategoryGalleryNavStore.open(
      host.baseUrl,
      '最近添加',
      result.items,
      host.getUIContext(),
      false,
      { columnsPerRow: 4, sourceKind: 'recent' }
    );
  } finally {
    host.recentOpening = false;
  }
}

export async function galleryAlbumOpenCollectGallery(host: GalleryAlbumModeOrchestratorHost): Promise<void> {
  if (host.collectOpening) {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  host.collectOpening = true;
  const isActive = host.createNavigationGuard();
  try {
    const result = await loadCollectGalleryItems(
      client,
      (item: GalleryListItem): string => host.itemIdOf(item),
      isActive
    );
    if (!isActive()) {
      return;
    }
    if (result.items.length <= 0 && result.error.length > 0) {
      host.toast(result.error);
      return;
    }
    CategoryGalleryNavStore.open(
      host.baseUrl,
      '收藏',
      result.items,
      host.getUIContext(),
      false,
      { sourceKind: 'collect' }
    );
  } finally {
    host.collectOpening = false;
  }
}
