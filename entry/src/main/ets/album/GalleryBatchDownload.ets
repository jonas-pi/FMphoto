/**
 * 批量下载 NAS 图库媒体到本机相册（PhotoViewPicker.save + 网络拉流写入）。
 * 与 GalleryPreview 单张下载逻辑对齐：图片可选原图/缩略图，视频始终拉流原文件。
 */
import { fileIo, picker } from '@kit.CoreFileKit';
import { GalleryListItem } from '../model/FnApiTypes';
import { AppSession } from '../auth/AppSession';
import { isVideoItem, itemFileExt, nasUrl, pickOriginal, pickThumb, pickVideo } from './GalleryAlbumCommon';

function itemHasOriginalPhoto(it: GalleryListItem): boolean {
  return !isVideoItem(it) && pickOriginal(it).trim().length > 0;
}

function suggestedSaveExt(it: GalleryListItem): string {
  if (isVideoItem(it)) {
    const ext = itemFileExt(it);
    if (ext === 'mp4' || ext === 'mov' || ext === 'm4v' || ext === 'mkv' || ext === 'avi' || ext === 'webm') {
      return ext;
    }
    return 'mp4';
  }
  const ext = itemFileExt(it);
  if (ext === 'gif') {
    return 'gif';
  }
  if (ext === 'png') {
    return 'png';
  }
  if (ext === 'webp') {
    return 'webp';
  }
  return 'jpg';
}

function suggestedBaseName(it: GalleryListItem, idx: number): string {
  const raw = it.filename ?? it.name ?? it.title ?? '';
  const trimmed = raw.trim();
  if (trimmed.length > 0) {
    const dot = trimmed.lastIndexOf('.');
    const base = dot > 0 ? trimmed.substring(0, dot) : trimmed;
    const safe = base.replace(/[\\/:*?"<>|]/g, '_');
    if (safe.length > 0) {
      return safe.length > 80 ? safe.substring(0, 80) : safe;
    }
  }
  const id = it.id !== undefined && it.id !== null ? String(it.id).trim() : '';
  if (id.length > 0) {
    return `nas_${id}`;
  }
  return `nas_${idx}_${Date.now()}`;
}

/**
 * 按当前列表顺序收集已选 id 对应的条目（去重顺序与列表一致）。
 */
export function galleryItemsMatchingSelectedIds(
  list: GalleryListItem[],
  selectedIds: string[]
): GalleryListItem[] {
  if (selectedIds.length === 0 || list.length === 0) {
    return [];
  }
  const want = new Set<string>();
  for (let i = 0; i < selectedIds.length; i++) {
    const s = selectedIds[i].trim();
    if (s.length > 0) {
      want.add(s);
    }
  }
  const out: GalleryListItem[] = [];
  for (let i = 0; i < list.length; i++) {
    const it = list[i];
    const id = it.id !== undefined && it.id !== null ? String(it.id).trim() : '';
    if (id.length > 0 && want.has(id)) {
      out.push(it);
    }
  }
  return out;
}

/**
 * 批量下载：一次系统保存面板（多文件名），再逐条拉取并写入对应 URI。
 * 使用独立回调参数而非 UI 对象字面量，以满足 arkts-no-untyped-obj-literals。
 */
export async function runBatchDownloadGalleryItems(
  baseUrl: string,
  items: GalleryListItem[],
  toastMsg: (msg: string) => void,
  askBatchImageQuality: () => Promise<'original' | 'thumb' | 'cancel'>
): Promise<void> {
  if (items.length === 0) {
    toastMsg('没有可下载的项');
    return;
  }
  const client = AppSession.getClient();
  if (client === null) {
    toastMsg('未登录');
    return;
  }

  let useOriginalForImages = false;
  let anyOriginal = false;
  for (let i = 0; i < items.length; i++) {
    if (itemHasOriginalPhoto(items[i])) {
      anyOriginal = true;
      break;
    }
  }
  if (anyOriginal) {
    const q = await askBatchImageQuality();
    if (q === 'cancel') {
      return;
    }
    useOriginalForImages = q === 'original';
  }

  const names: string[] = [];
  for (let i = 0; i < items.length; i++) {
    const ext = suggestedSaveExt(items[i]);
    names.push(`${suggestedBaseName(items[i], i)}.${ext}`);
  }

  let uris: string[] = [];
  try {
    const saveOptions = new picker.PhotoSaveOptions();
    saveOptions.newFileNames = names;
    uris = await new picker.PhotoViewPicker().save(saveOptions);
  } catch (_e) {
    toastMsg('保存已取消');
    return;
  }
  if (uris.length === 0) {
    toastMsg('已取消保存');
    return;
  }
  const n = Math.min(items.length, uris.length);
  let ok = 0;
  for (let i = 0; i < n; i++) {
    const it = items[i];
    const uri = uris[i];
    const isVideo = isVideoItem(it);
    let url = '';
    if (isVideo) {
      url = nasUrl(baseUrl, pickVideo(it));
    } else if (useOriginalForImages && pickOriginal(it).trim().length > 0) {
      url = nasUrl(baseUrl, pickOriginal(it));
    } else {
      url = nasUrl(baseUrl, pickThumb(it));
    }
    if (url.length === 0) {
      continue;
    }
    const timeoutMs = isVideo ? 120000 : (useOriginalForImages ? 60000 : 15000);
    const buf = await client.fetchGalleryImageBuffer(url, timeoutMs);
    if (buf === undefined || buf.byteLength === 0) {
      continue;
    }
    try {
      const saveFile = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE);
      await fileIo.write(saveFile.fd, buf);
      await fileIo.close(saveFile.fd);
      ok++;
    } catch (_e) {
    }
  }
  toastMsg(`已保存 ${ok}/${items.length} 项`);
}
