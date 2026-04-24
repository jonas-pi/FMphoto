import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri as fileUriUtil, picker } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { CategoryGalleryNavStore } from '../../album/CategoryGalleryNavStore';
import { GalleryDeleteSyncStore } from '../../album/GalleryDeleteSyncStore';
import { GalleryPreviewNavStore } from '../../album/GalleryPreviewNavStore';
import { GalleryTimelineRefreshStore } from '../../album/GalleryTimelineRefreshStore';
import { isVideoItem, nasUrl, pickOriginal, pickThumb, pickVideo } from '../../album/GalleryAlbumCommon';
import { openPersonAlbumById } from '../../album/PersonAlbumOpenHelper';
import { AppSession } from '../../auth/AppSession';
import { GalleryListItem, GalleryPhotoDetailData, PersonInPhotoItem } from '../../model/FnApiTypes';
import { PreviewItemsDataSource } from './GalleryPreviewDataSource';
import {
  galleryPreviewCompactFolderTitle,
  galleryPreviewCurrentHasOriginal,
  galleryPreviewCurrentImageExt,
  galleryPreviewCurrentOriginalSizeBytes,
  galleryPreviewCurrentVideoExt,
  galleryPreviewDetailText,
  galleryPreviewNormalizePersonsInPhoto,
  galleryPreviewParentFolderPath,
  galleryPreviewQualitySizeLabel,
  galleryPreviewResolveCollectStateFromItem,
  galleryPreviewStarFilled
} from './GalleryPreviewDetailsLogic';

export interface GalleryPreviewActionsHost {
  getUIContext(): UIContext;
  baseUrl: string;
  swiperIndex: number;
  totalCount: number;
  detailsVisible: boolean;
  detailsLoading: boolean;
  detailsError: string;
  detailsData: GalleryPhotoDetailData | undefined;
  detailsPhotoId: string;
  personsInPhoto: PersonInPhotoItem[];
  folderOpening: boolean;
  personOpening: boolean;
  favoriteToggling: boolean;
  currentCollectState: number;
  originalShowing: boolean;
  deleting: boolean;
  downloading: boolean;
  sharing: boolean;
  previewItems: GalleryListItem[];
  itemSource: PreviewItemsDataSource;
  swiperCtrl: SwiperController;
  collectSyncGen: number;
  currentItem(): GalleryListItem | null;
  currentItemId(): string;
  toast(msg: string): void;
  routerBack(): void;
}

function galleryPreviewCurrentItemIsVideo(host: GalleryPreviewActionsHost): boolean {
  const item = host.currentItem();
  return item !== null && isVideoItem(item);
}

function galleryPreviewCurrentHasOriginalFromHost(host: GalleryPreviewActionsHost): boolean {
  return galleryPreviewCurrentHasOriginal(host.currentItem());
}

function galleryPreviewCurrentImageExtFromHost(host: GalleryPreviewActionsHost): string {
  return galleryPreviewCurrentImageExt(host.currentItem());
}

function galleryPreviewCurrentVideoExtFromHost(host: GalleryPreviewActionsHost): string {
  return galleryPreviewCurrentVideoExt(host.currentItem());
}

function galleryPreviewCurrentOriginalSizeBytesFromHost(host: GalleryPreviewActionsHost): number | undefined {
  return galleryPreviewCurrentOriginalSizeBytes(host.currentItem());
}

function galleryPreviewStarFilledFromHost(host: GalleryPreviewActionsHost): boolean {
  return galleryPreviewStarFilled(
    host.currentCollectState,
    host.currentItemId(),
    host.detailsPhotoId,
    host.detailsData
  );
}

function galleryPreviewRemoveIdFromCategoryGalleryNavStore(photoId: string): void {
  const id = photoId.trim();
  if (id.length === 0 || CategoryGalleryNavStore.items.length === 0) {
    return;
  }
  const kept: GalleryListItem[] = [];
  let hit = false;
  for (let i = 0; i < CategoryGalleryNavStore.items.length; i++) {
    const it = CategoryGalleryNavStore.items[i];
    const nid = it.id !== undefined && it.id !== null ? String(it.id).trim() : '';
    if (nid === id) {
      hit = true;
      continue;
    }
    kept.push(it);
  }
  if (hit) {
    CategoryGalleryNavStore.items = kept;
  }
}

async function galleryPreviewFetchCurrentImageBuffer(
  host: GalleryPreviewActionsHost,
  useOriginal: boolean = true
): Promise<ArrayBuffer | undefined> {
  const item = host.currentItem();
  if (item === null) {
    return undefined;
  }
  const originalUrl = nasUrl(host.baseUrl, pickOriginal(item));
  const thumbUrl = nasUrl(host.baseUrl, pickThumb(item));
  let imageUrl = '';
  if (useOriginal && originalUrl.length > 0) {
    imageUrl = originalUrl;
  } else if (thumbUrl.length > 0) {
    imageUrl = thumbUrl;
  }
  if (imageUrl.length === 0) {
    return undefined;
  }
  const client = AppSession.getClient();
  if (client === null) {
    return undefined;
  }
  return client.fetchGalleryImageBuffer(imageUrl, useOriginal ? 60000 : 15000);
}

async function galleryPreviewFetchCurrentVideoBuffer(host: GalleryPreviewActionsHost): Promise<ArrayBuffer | undefined> {
  const item = host.currentItem();
  if (item === null) {
    return undefined;
  }
  const videoUrl = nasUrl(host.baseUrl, pickVideo(item));
  if (videoUrl.length === 0) {
    return undefined;
  }
  const client = AppSession.getClient();
  if (client === null) {
    return undefined;
  }
  return client.fetchGalleryImageBuffer(videoUrl, 120000);
}

export function galleryPreviewSyncCollectStateFromCurrentItem(host: GalleryPreviewActionsHost): void {
  host.currentCollectState = galleryPreviewResolveCollectStateFromItem(host.currentItem());
}

export async function galleryPreviewRefreshCollectStateFromGetOne(
  host: GalleryPreviewActionsHost,
  photoId: string
): Promise<void> {
  const id = photoId.trim();
  if (id.length === 0) {
    return;
  }
  const gen = ++host.collectSyncGen;
  const client = AppSession.getClient();
  if (client === null) {
    return;
  }
  const res = await client.getGalleryPhotoDetail(id, 12000);
  if (gen !== host.collectSyncGen) {
    return;
  }
  if (id !== host.currentItemId()) {
    return;
  }
  if (!res.success || res.data === undefined) {
    return;
  }
  const collectState = res.data.isCollect;
  if (collectState === 1) {
    host.currentCollectState = 1;
  } else if (collectState === 0) {
    host.currentCollectState = 0;
  }
  const idx = host.swiperIndex;
  if (idx >= 0 && idx < host.previewItems.length) {
    const current = host.previewItems[idx];
    const currentId = current.id !== undefined && current.id !== null ? String(current.id).trim() : '';
    if (currentId === id && (collectState === 1 || collectState === 0)) {
      current.isCollect = collectState;
      host.previewItems[idx] = current;
      GalleryPreviewNavStore.items = host.previewItems.slice();
    }
  }
}

export async function galleryPreviewToggleFavorite(host: GalleryPreviewActionsHost): Promise<void> {
  if (host.favoriteToggling) {
    return;
  }
  const id = host.currentItemId();
  if (id.length === 0) {
    host.toast('当前媒体无有效 ID');
    return;
  }
  const wasFilled = galleryPreviewStarFilledFromHost(host);
  host.favoriteToggling = true;
  try {
    const client = AppSession.getClient();
    if (client === null) {
      host.toast('未登录');
      return;
    }
    if (wasFilled) {
      const res = await client.postPreviewCollectCancel(id, 15000);
      if (!res.success) {
        host.toast(res.message ?? '取消收藏失败');
        return;
      }
      host.currentCollectState = 0;
      if (host.detailsData !== undefined && host.detailsPhotoId === id) {
        const details = host.detailsData;
        details.isCollect = 0;
        host.detailsData = details;
      }
      const idx = host.swiperIndex;
      if (idx >= 0 && idx < host.previewItems.length) {
        const item = host.previewItems[idx];
        item.isCollect = 0;
        host.previewItems[idx] = item;
        GalleryPreviewNavStore.items = host.previewItems.slice();
      }
      GalleryTimelineRefreshStore.bump();
      host.toast('已取消收藏');
      return;
    }
    const res = await client.postPreviewCollect(id, 15000);
    if (!res.success) {
      host.toast(res.message ?? '收藏失败');
      return;
    }
    host.currentCollectState = 1;
    if (host.detailsData !== undefined && host.detailsPhotoId === id) {
      const details = host.detailsData;
      details.isCollect = 1;
      host.detailsData = details;
    }
    const idx = host.swiperIndex;
    if (idx >= 0 && idx < host.previewItems.length) {
      const item = host.previewItems[idx];
      item.isCollect = 1;
      host.previewItems[idx] = item;
      GalleryPreviewNavStore.items = host.previewItems.slice();
    }
    GalleryTimelineRefreshStore.bump();
    host.toast('已加入收藏');
  } finally {
    host.favoriteToggling = false;
  }
}

export function galleryPreviewApplyDeleteCurrentItem(host: GalleryPreviewActionsHost): void {
  if (host.swiperIndex < 0 || host.swiperIndex >= host.previewItems.length) {
    return;
  }
  const deleted = host.previewItems[host.swiperIndex];
  const deletedId = deleted?.id !== undefined && deleted?.id !== null ? String(deleted.id).trim() : '';
  const oldIdx = host.swiperIndex;
  host.previewItems.splice(oldIdx, 1);
  const left = host.previewItems.length;
  host.totalCount = left;
  host.detailsVisible = false;
  host.detailsData = undefined;
  host.detailsPhotoId = '';
  host.originalShowing = false;
  if (deletedId.length > 0) {
    GalleryDeleteSyncStore.markDeleted(deletedId);
    GalleryTimelineRefreshStore.bump();
    galleryPreviewRemoveIdFromCategoryGalleryNavStore(deletedId);
  }
  if (left <= 0) {
    host.itemSource.reloadAll([]);
    GalleryPreviewNavStore.items = [];
    GalleryPreviewNavStore.startIndex = 0;
    host.toast('已移入回收站');
    host.routerBack();
    return;
  }
  let targetIdx = oldIdx;
  if (targetIdx >= left) {
    targetIdx = left - 1;
  }
  host.swiperIndex = targetIdx;
  host.itemSource.reloadAll(host.previewItems);
  GalleryPreviewNavStore.items = host.previewItems.slice();
  GalleryPreviewNavStore.startIndex = targetIdx;
  setTimeout((): void => {
    host.swiperCtrl.changeIndex(targetIdx, false);
  }, 50);
  host.toast('已移入回收站');
}

export async function galleryPreviewDeleteCurrentItem(host: GalleryPreviewActionsHost): Promise<void> {
  if (host.deleting) {
    return;
  }
  const id = host.currentItemId();
  if (id.length === 0) {
    host.toast('当前媒体无有效 ID');
    return;
  }
  try {
    const choice = await host.getUIContext().getPromptAction().showActionMenu({
      title: '确认删除当前媒体？',
      buttons: [
        { text: '删除（移入回收站）', color: '#E5484D' }
      ]
    });
    if (choice.index !== 0) {
      return;
    }
  } catch (_e) {
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  host.deleting = true;
  try {
    const res = await client.addPhotoToRecycleBin(id, 20000);
    if (!res.success) {
      host.toast(res.message ?? '删除失败');
      return;
    }
    galleryPreviewApplyDeleteCurrentItem(host);
  } finally {
    host.deleting = false;
  }
}

export function galleryPreviewOpenDetailsPanel(host: GalleryPreviewActionsHost): void {
  const id = host.currentItemId();
  if (id.length === 0) {
    host.toast('当前媒体无详情 ID');
    return;
  }
  host.detailsVisible = true;
  host.detailsError = '';
  if (host.detailsData !== undefined && host.detailsPhotoId === id) {
    return;
  }
  host.detailsLoading = true;
  host.detailsData = undefined;
  host.personsInPhoto = [];
  void galleryPreviewLoadPhotoDetails(host, id).finally((): void => {
    host.detailsLoading = false;
  });
}

export async function galleryPreviewLoadPhotoDetails(
  host: GalleryPreviewActionsHost,
  photoId: string
): Promise<void> {
  const client = AppSession.getClient();
  if (client === null) {
    host.detailsError = '未登录';
    return;
  }
  const detailP = client.getGalleryPhotoDetail(photoId, 15000);
  const personP = client.getPersonInPhoto(photoId, 12000);
  const pair = await Promise.all([detailP, personP]);
  const res = pair[0];
  const personRes = pair[1];
  if (!res.success || res.data === undefined) {
    host.detailsError = res.message ?? '详情加载失败';
    host.personsInPhoto = [];
    return;
  }
  host.detailsData = res.data;
  host.detailsPhotoId = photoId;
  if (photoId === host.currentItemId()) {
    const collectState = res.data.isCollect;
    if (collectState === 1) {
      host.currentCollectState = 1;
    } else if (collectState === 0) {
      host.currentCollectState = 0;
    }
  }
  if (personRes.success && personRes.data !== undefined) {
    host.personsInPhoto = galleryPreviewNormalizePersonsInPhoto(personRes.data.list);
  } else {
    host.personsInPhoto = [];
  }
}

export function galleryPreviewCloseDetailsPanel(host: GalleryPreviewActionsHost): void {
  host.detailsVisible = false;
}

export function galleryPreviewOpenFolderFromDetailPath(host: GalleryPreviewActionsHost): void {
  if (host.folderOpening) {
    return;
  }
  const rawPath = galleryPreviewDetailText(host.detailsData?.filePath ?? host.detailsData?.showFilePath);
  const folderPath = galleryPreviewParentFolderPath(rawPath);
  if (folderPath.length === 0) {
    host.toast('文件路径不可用');
    return;
  }
  host.folderOpening = true;
  void galleryPreviewFetchAndOpenFolderMedia(host, folderPath).finally((): void => {
    host.folderOpening = false;
  });
}

export async function galleryPreviewFetchAndOpenFolderMedia(
  host: GalleryPreviewActionsHost,
  folderPath: string
): Promise<void> {
  const client = AppSession.getClient();
  if (client === null) {
    host.toast('未登录');
    return;
  }
  const all: GalleryListItem[] = [];
  const pageSize = 100;
  let offset = 0;
  let rounds = 0;
  while (rounds < 200) {
    const res = await client.getFolderViewFileList(folderPath, pageSize, offset, false, 2, 20000);
    if (!res.success || res.data === undefined) {
      host.toast(res.message ?? '文件夹媒体加载失败');
      return;
    }
    const list = res.data;
    if (list.length === 0) {
      break;
    }
    for (let i = 0; i < list.length; i++) {
      all.push(list[i]);
    }
    offset += list.length;
    rounds++;
    if (list.length < pageSize) {
      break;
    }
  }
  if (all.length === 0) {
    host.toast('该文件夹暂无可预览媒体');
    return;
  }
  host.detailsVisible = false;
  CategoryGalleryNavStore.open(
    host.baseUrl,
    galleryPreviewCompactFolderTitle(folderPath),
    all,
    host.getUIContext()
  );
}

export async function galleryPreviewOnPersonInPhotoClick(
  host: GalleryPreviewActionsHost,
  p: PersonInPhotoItem
): Promise<void> {
  if (host.personOpening) {
    return;
  }
  const pidRaw = p.personId;
  const pid = pidRaw !== undefined && pidRaw !== null ? String(pidRaw) : '';
  if (pid.length === 0) {
    host.toast('人物 ID 无效');
    return;
  }
  const nameRaw = galleryPreviewDetailText(p.name);
  const initialTitle = nameRaw.length > 0 ? nameRaw : '未命名';
  host.detailsVisible = false;
  host.personOpening = true;
  let keepOpening = false;
  try {
    const r = await openPersonAlbumById(
      host.baseUrl,
      pid,
      initialTitle,
      host.getUIContext()
    );
    if (!r.ok) {
      if (r.errorMessage.length > 0) {
        host.toast(r.errorMessage);
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

export function galleryPreviewDownloadCurrentImage(host: GalleryPreviewActionsHost): void {
  if (host.downloading) {
    return;
  }
  host.downloading = true;
  void galleryPreviewDoDownload(host).finally((): void => {
    host.downloading = false;
  });
}

async function galleryPreviewDoDownload(host: GalleryPreviewActionsHost): Promise<void> {
  const isVideo = galleryPreviewCurrentItemIsVideo(host);
  let useOriginal = false;
  let prefetchedOriginal: ArrayBuffer | undefined = undefined;
  let prefetchedThumb: ArrayBuffer | undefined = undefined;
  if (!isVideo && galleryPreviewCurrentHasOriginalFromHost(host)) {
    let originalBytes = galleryPreviewCurrentOriginalSizeBytesFromHost(host);
    let thumbBytes: number | undefined = undefined;
    prefetchedThumb = await galleryPreviewFetchCurrentImageBuffer(host, false);
    if (prefetchedThumb !== undefined && prefetchedThumb.byteLength > 0) {
      thumbBytes = prefetchedThumb.byteLength;
    } else {
      prefetchedThumb = undefined;
    }
    if (originalBytes === undefined) {
      prefetchedOriginal = await galleryPreviewFetchCurrentImageBuffer(host, true);
      if (prefetchedOriginal !== undefined && prefetchedOriginal.byteLength > 0) {
        originalBytes = prefetchedOriginal.byteLength;
      } else {
        prefetchedOriginal = undefined;
      }
    }
    try {
      const choice = await host.getUIContext().getPromptAction().showActionMenu({
        title: '选择下载质量',
        buttons: [
          { text: `原图（${galleryPreviewQualitySizeLabel(originalBytes)}）`, color: '#007AFF' },
          { text: `缩略图（${galleryPreviewQualitySizeLabel(thumbBytes)}）`, color: '#007AFF' }
        ]
      });
      useOriginal = choice.index === 0;
    } catch (_e) {
      return;
    }
  }

  let saveUri = '';
  try {
    const saveOptions = new picker.PhotoSaveOptions();
    const ext = isVideo
      ? galleryPreviewCurrentVideoExtFromHost(host)
      : galleryPreviewCurrentImageExtFromHost(host);
    saveOptions.newFileNames = [`${isVideo ? 'video' : 'photo'}_${Date.now()}.${ext}`];
    const uris = await new picker.PhotoViewPicker().save(saveOptions);
    if (uris.length === 0) {
      host.toast('已取消保存');
      return;
    }
    saveUri = uris[0];
  } catch (_e) {
    host.toast('保存取消');
    return;
  }

  let buf: ArrayBuffer | undefined;
  if (isVideo) {
    buf = await galleryPreviewFetchCurrentVideoBuffer(host);
  } else if (useOriginal) {
    buf = prefetchedOriginal !== undefined ? prefetchedOriginal : await galleryPreviewFetchCurrentImageBuffer(host, true);
  } else {
    buf = prefetchedThumb !== undefined ? prefetchedThumb : await galleryPreviewFetchCurrentImageBuffer(host, false);
  }
  if (buf === undefined || buf.byteLength === 0) {
    host.toast(isVideo ? '视频加载失败，请重试' : '图片加载失败，请重试');
    return;
  }

  try {
    const saveFile = await fileIo.open(saveUri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
    await fileIo.write(saveFile.fd, buf);
    await fileIo.close(saveFile.fd);
    if (isVideo) {
      host.toast('视频已保存到相册');
    } else {
      host.toast(useOriginal ? '原图已保存到相册' : '缩略图已保存到相册');
    }
  } catch (_e) {
    host.toast('写入失败，请重试');
  }
}

export function galleryPreviewShareCurrentImage(host: GalleryPreviewActionsHost): void {
  if (host.sharing) {
    return;
  }
  host.sharing = true;
  void galleryPreviewDoShare(host).finally((): void => {
    host.sharing = false;
  });
}

async function galleryPreviewDoShare(host: GalleryPreviewActionsHost): Promise<void> {
  const ctx = host.getUIContext().getHostContext() as common.UIAbilityContext;
  const isVideo = galleryPreviewCurrentItemIsVideo(host);
  let slowHintTimer: number = 0;
  try {
    slowHintTimer = setTimeout((): void => {
      host.toast('正在准备分享…');
    }, 400);
  } catch (_e) {
    slowHintTimer = 0;
  }

  const buf = isVideo
    ? await galleryPreviewFetchCurrentVideoBuffer(host)
    : await galleryPreviewFetchCurrentImageBuffer(host);
  if (slowHintTimer !== 0) {
    try {
      clearTimeout(slowHintTimer);
    } catch (_e) {
    }
    slowHintTimer = 0;
  }
  if (buf === undefined || buf.byteLength === 0) {
    host.toast(isVideo ? '视频加载失败，请重试' : '图片加载失败，请重试');
    return;
  }

  const ext = isVideo
    ? galleryPreviewCurrentVideoExtFromHost(host)
    : galleryPreviewCurrentImageExtFromHost(host);
  const tempPath = `${ctx.cacheDir}/share_preview.${ext}`;
  try {
    const tmpFile = await fileIo.open(
      tempPath,
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    await fileIo.write(tmpFile.fd, buf);
    await fileIo.close(tmpFile.fd);
  } catch (_e) {
    host.toast('临时文件写入失败');
    return;
  }

  try {
    const shareUri = fileUriUtil.getUriFromPath(tempPath);
    const record: systemShare.SharedRecord = {
      utd: isVideo ? 'general.video' : 'general.image',
      uri: shareUri,
      title: isVideo ? '分享视频' : '分享图片'
    };
    const shareData = new systemShare.SharedData(record);
    const ctrl = new systemShare.ShareController(shareData);
    await ctrl.show(ctx, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    });
  } catch (_e) {
    host.toast('分享失败，请重试');
  }
}
