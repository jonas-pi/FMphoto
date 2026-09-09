import { isVideoItem, itemFileExt, pickOriginal } from '../../album/GalleryAlbumCommon';
import { isLivePhotoItem } from '../../album/livephoto/LivePhotoDetect';
import { GalleryListItem, GalleryPhotoDetailData, PersonInPhotoItem } from '../../model/FnApiTypes';
import { FN_PHOTO_API_PREFIX } from '../../network/FnPhotoRoutes';

/** 详情路径折叠时，从文件所在目录向上保留的最多层级数（超出则在顶部用 … 省略）。 */
const GALLERY_PREVIEW_PATH_MAX_TAIL_SEGMENTS: number = 4;

export function galleryPreviewResolveCollectStateFromItem(item: GalleryListItem | null): number {
  if (item === null) {
    return -1;
  }
  const collectState = item.isCollect;
  if (collectState === 1) {
    return 1;
  }
  if (collectState === 0) {
    return 0;
  }
  return -1;
}

export function galleryPreviewStarFilled(
  currentCollectState: number,
  currentItemId: string,
  detailsPhotoId: string,
  detailsData: GalleryPhotoDetailData | undefined
): boolean {
  if (currentCollectState === 1) {
    return true;
  }
  if (currentCollectState === 0) {
    return false;
  }
  if (currentItemId.length > 0 && detailsPhotoId === currentItemId && detailsData !== undefined) {
    return detailsData.isCollect === 1;
  }
  return false;
}

export function galleryPreviewFavoriteStarTint(): ResourceColor {
  return '#FFD60A';
}

export function galleryPreviewCurrentHasOriginal(item: GalleryListItem | null): boolean {
  if (item === null) {
    return false;
  }
  return pickOriginal(item).length > 0 && !isVideoItem(item);
}

export function galleryPreviewCurrentImageExt(item: GalleryListItem | null): string {
  if (item === null) {
    return 'jpg';
  }
  const ext = itemFileExt(item);
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

export function galleryPreviewCurrentVideoExt(item: GalleryListItem | null): string {
  if (item === null) {
    return 'mp4';
  }
  const ext = itemFileExt(item);
  if (ext === 'mp4' || ext === 'mov' || ext === 'm4v' || ext === 'mkv' || ext === 'avi' || ext === 'webm') {
    return ext;
  }
  return 'mp4';
}

export function galleryPreviewTitleCounter(swiperIndex: number, totalCount: number): string {
  return totalCount > 0 ? `${swiperIndex + 1} / ${totalCount}` : '';
}

export function galleryPreviewToolbarAlpha(dismissDragProgress: number): number {
  return Math.max(0, 1 - dismissDragProgress * 1.5);
}

export function galleryPreviewDetailText(v: string | number | undefined): string {
  if (v === undefined || v === null) {
    return '';
  }
  const s = String(v).trim();
  return s.length > 0 ? s : '';
}

export function galleryPreviewMediaKindLabel(data: GalleryPhotoDetailData | undefined): string {
  if (data === undefined) {
    return '';
  }
  if (isLivePhotoItem(data)) {
    return '实况 / 动态照片';
  }
  if (isVideoItem(data)) {
    return '视频';
  }
  const ext = galleryPreviewDetailText(data.fileType);
  return ext;
}

export function galleryPreviewFormatBytes(v: string | number | undefined): string {
  const raw = galleryPreviewDetailText(v);
  if (raw.length === 0) {
    return '';
  }
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0) {
    return raw;
  }
  if (n < 1024) {
    return `${Math.floor(n)} B`;
  }
  if (n < 1024 * 1024) {
    return `${(n / 1024).toFixed(1)} KB`;
  }
  if (n < 1024 * 1024 * 1024) {
    return `${(n / (1024 * 1024)).toFixed(2)} MB`;
  }
  return `${(n / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

export function galleryPreviewParseBytes(v: string | number | undefined): number | undefined {
  const raw = galleryPreviewDetailText(v);
  if (raw.length === 0) {
    return undefined;
  }
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0) {
    return undefined;
  }
  return Math.floor(n);
}

export function galleryPreviewCurrentOriginalSizeBytes(item: GalleryListItem | null): number | undefined {
  if (item === null) {
    return undefined;
  }
  const originalBytes = galleryPreviewParseBytes(item.originalSize);
  if (originalBytes !== undefined) {
    return originalBytes;
  }
  return galleryPreviewParseBytes(item.fileSize);
}

export function galleryPreviewQualitySizeLabel(bytes: number | undefined): string {
  if (bytes === undefined) {
    return '大小未知';
  }
  return galleryPreviewFormatBytes(bytes);
}

export function galleryPreviewJoinPair(left: string, right: string, sep: string): string {
  if (left.length > 0 && right.length > 0) {
    return `${left}${sep}${right}`;
  }
  if (left.length > 0) {
    return left;
  }
  if (right.length > 0) {
    return right;
  }
  return '';
}

export function galleryPreviewParentFolderPath(fullPath: string): string {
  const path = fullPath.trim();
  if (path.length === 0) {
    return '';
  }
  const idx = path.lastIndexOf('/');
  if (idx <= 0) {
    return '';
  }
  return path.substring(0, idx);
}

export function galleryPreviewSplitPathSegments(path: string): string[] {
  const partsRaw = path.split('/');
  const parts: string[] = [];
  for (let i = 0; i < partsRaw.length; i++) {
    const seg = partsRaw[i].trim();
    if (seg.length > 0) {
      parts.push(seg);
    }
  }
  return parts;
}

export function galleryPreviewCompactFolderTitle(folderPath: string): string {
  const path = folderPath.trim();
  if (path.length === 0) {
    return '文件夹';
  }
  const parts = galleryPreviewSplitPathSegments(path);
  if (parts.length === 0) {
    return path;
  }
  if (parts.length <= GALLERY_PREVIEW_PATH_MAX_TAIL_SEGMENTS) {
    return `/${parts.join('/')}`;
  }
  const tail = parts.slice(parts.length - GALLERY_PREVIEW_PATH_MAX_TAIL_SEGMENTS);
  return `/.../${tail.join('/')}`;
}

export function galleryPreviewCompactDisplayPath(fullPath: string): string {
  const path = fullPath.trim();
  if (path.length === 0) {
    return '';
  }
  const folderPath = galleryPreviewParentFolderPath(path);
  if (folderPath.length > 0) {
    return galleryPreviewCompactFolderTitle(folderPath);
  }
  return galleryPreviewCompactFolderTitle(path);
}

export function galleryPreviewPersonInPhotoName(p: PersonInPhotoItem): string {
  const nameRaw = galleryPreviewDetailText(p.name);
  return nameRaw.length > 0 ? nameRaw : '未命名';
}

export function galleryPreviewPersonInPhotoMeta(p: PersonInPhotoItem): string {
  const parts: string[] = [];
  const total = p.total;
  if (total !== undefined && Number.isFinite(Number(total))) {
    parts.push(`图库共 ${Math.max(0, Math.floor(Number(total)))} 张`);
  }
  if (p.isHide === true) {
    parts.push('已隐藏');
  }
  return parts.join(' · ');
}

export function galleryPreviewPersonInPhotoLineText(p: PersonInPhotoItem): string {
  const showName = galleryPreviewPersonInPhotoName(p);
  const meta = galleryPreviewPersonInPhotoMeta(p);
  if (meta.length <= 0) {
    return showName;
  }
  if (p.total !== undefined && Number.isFinite(Number(p.total))) {
    const n = Math.max(0, Math.floor(Number(p.total)));
    let line = `${showName}（图库共 ${n} 张）`;
    if (p.isHide === true) {
      line += ' · 已隐藏';
    }
    return line;
  }
  return `${showName} · ${meta}`;
}

/** 人物列表同款人脸流：优先接口 URL，否则 /p/api/v1/stream/face/{faceId} */
export function galleryPreviewPersonInPhotoFacePath(p: PersonInPhotoItem): string {
  const direct = galleryPreviewDetailText(p.faceUrl);
  if (direct.length > 0) {
    return direct;
  }
  if (p.faceId === undefined || p.faceId === null) {
    return '';
  }
  const idStr = String(p.faceId).trim();
  if (idStr.length <= 0 || idStr === '0') {
    return '';
  }
  return `${FN_PHOTO_API_PREFIX}/stream/face/${idStr}`;
}

export function galleryPreviewPersonInPhotoCacheKey(p: PersonInPhotoItem): string {
  if (p.personId !== undefined && p.personId !== null) {
    const pid = String(p.personId).trim();
    if (pid.length > 0 && pid !== '0') {
      return `person:${pid}`;
    }
  }
  if (p.faceId !== undefined && p.faceId !== null) {
    const fid = String(p.faceId).trim();
    if (fid.length > 0 && fid !== '0') {
      return `face:${fid}`;
    }
  }
  return galleryPreviewPersonInPhotoFacePath(p);
}

export function galleryPreviewNormalizePersonsInPhoto(raw: Array<Object | null> | undefined): PersonInPhotoItem[] {
  const out: PersonInPhotoItem[] = [];
  if (raw === undefined) {
    return out;
  }
  for (let i = 0; i < raw.length; i++) {
    const el = raw[i];
    if (typeof el === 'object' && el !== null) {
      const item = el as PersonInPhotoItem;
      const facePath = galleryPreviewPersonInPhotoFacePath(item);
      if (facePath.length > 0) {
        item.faceUrl = facePath;
      }
      out.push(item);
    }
  }
  return out;
}
