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
import { CATEGORY_GALLERY_INITIAL_RENDER_CAP, CategoryGalleryNavStore } from '../CategoryGalleryNavStore';
import { GalleryTimelineRefreshStore } from '../GalleryTimelineRefreshStore';
import { openPersonAlbumById } from '../PersonAlbumOpenHelper';
import {
  galleryMediaCategoryModeLoader,
  galleryPersonModeLoader,
  gallerySmartCategoryModeLoader,
  loadCollectGalleryItems,
  loadRecentAddedItems
} from './GalleryAlbumModeLoaders';
import {
  CATEGORY_GALLERY_PHOTO_INITIAL_RENDER_CAP,
  categoryCount,
  categoryCover,
  categoryLocalMediaCount,
  categoryTitle,
  parseCategoryMedia,
  personId,
  personName
} from './GalleryAlbumModeData';
import { nasUrl } from '../GalleryAlbumCommon';
import { GALLERY_UPLOAD_RECHECK_MS } from './GalleryAlbumTabConstants';

export interface GalleryAlbumModeOrchestratorHost {
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
  personLoading: boolean;
  personOpening: boolean;
  personError: string;
  personItems: AiPersonItem[];
  personStatOverrides: Map<string, string>;
  personStatVersion: number;
  personStatGen: number;
  recentOpening: boolean;
  collectOpening: boolean;
  uploading: boolean;
  uploadText: string;
  lastBootstrapSatisfiedRefreshVersion: number;
  exitGallerySelection(): void;
  requestBootstrap(forceImmediate: boolean): void;
  bootstrap(showFullBleedSkeleton?: boolean): Promise<void>;
  itemIdOf(item: GalleryListItem): string;
  createNavigationGuard(): () => boolean;
  toast(msg: string): void;
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
  if (host.uploading) {
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
  host.uploading = true;
  host.uploadText = `上传中 0/${uris.length}…`;
  let ok = 0;
  let firstFailMsg = '';
  const stored = AppSession.getStored();
  const albumDirHint =
    stored !== null && stored.albumParentGuid.trim().length > 0 ? stored.albumParentGuid.trim() : undefined;
  const ctx = host.getUIContext().getHostContext() as common.UIAbilityContext;
  try {
    await BackgroundKeepAliveController.withDataTransfer(ctx, 'album-upload', async (): Promise<void> => {
  for (let i = 0; i < uris.length; i++) {
    host.uploadText = `上传中 ${i + 1}/${uris.length}…`;
    const res = await client.uploadPhotoByUri(uris[i], 150000, albumDirHint);
    if (res.success) {
      ok++;
    } else if (firstFailMsg.length === 0) {
      const em = res.message ?? '';
      firstFailMsg = em.length > 0 ? em : '上传失败';
    }
  }
    });
  } finally {
    host.uploading = false;
    host.uploadText = '';
  }
  if (ok > 0) {
    host.toast(`上传完成 ${ok}/${uris.length}`);
    GalleryTimelineRefreshStore.bump();
    host.requestBootstrap(false);
    setTimeout((): void => {
      void host.bootstrap(false);
    }, GALLERY_UPLOAD_RECHECK_MS);
  } else {
    host.toast(firstFailMsg.length > 0 ? firstFailMsg : '上传失败，请稍后重试');
  }
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
  const client = AppSession.getClient();
  if (client === null) {
    host.smartCategoryError = '未登录';
    host.smartCategoryLoading = false;
    return;
  }
  const result = await gallerySmartCategoryModeLoader.load(client);
  host.smartSceneItems = result.data.sceneItems;
  host.smartInfoItems = result.data.infoItems;
  host.smartCategoryError = result.error;
  host.smartCategoryLoading = false;
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
  const title = categoryTitle(cat);
  const categoryKey = cat.key !== undefined ? cat.key : '';
  host.categoryOpeningText = categoryKey === 'photo' ? '加载照片中…' : `打开${title}中…`;
  const initialRenderCap = categoryKey === 'photo'
    ? CATEGORY_GALLERY_PHOTO_INITIAL_RENDER_CAP
    : CATEGORY_GALLERY_INITIAL_RENDER_CAP;
  const localMediaCount = categoryLocalMediaCount(cat);
  const local = parseCategoryMedia(
    cat,
    categoryKey.length > 0 ? initialRenderCap : -1
  );
  const heroRel = categoryCover(cat);
  const heroImageUri = heroRel.length > 0 ? nasUrl(host.baseUrl, heroRel) : '';
  const expectedTotalCount = Math.max(categoryCount(cat), localMediaCount, local.length);
  hilog.warn(
    0xFF00,
    'GalleryDiag',
    'openCategory title=%{public}s key=%{public}s localMediaCount=%{public}d localInitial=%{public}d expectedTotal=%{public}d',
    title,
    categoryKey,
    localMediaCount,
    local.length,
    expectedTotalCount
  );
  try {
    if (local.length > 0) {
      if (!isActive()) {
        return;
      }
      CategoryGalleryNavStore.open(
        host.baseUrl,
        title,
        local,
        host.getUIContext(),
        false,
        { expectedTotalCount, categoryKey, heroImageUri }
      );
      return;
    }
    const client = AppSession.getClient();
    if (client === null) {
      host.toast('未登录');
      return;
    }
    const fetched = await client.searchResultsByCategory(cat);
    if (!isActive()) {
      return;
    }
    if (!fetched.success || fetched.data === undefined || fetched.data.length === 0) {
      host.toast(fetched.message ?? '该分类暂无可预览媒体');
      return;
    }
    CategoryGalleryNavStore.open(
      host.baseUrl,
      title,
      fetched.data,
      host.getUIContext(),
      false,
      { expectedTotalCount, categoryKey, heroImageUri }
    );
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
    if (result.items.length <= 0) {
      if (result.error.length > 0) {
        host.toast(result.error);
      }
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
