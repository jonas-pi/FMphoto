import { http } from '@kit.NetworkKit';
import { FnGalleryGetSignSpec } from '../FnGalleryAuthx';
import { FN_PHOTO_API_PREFIX } from '../FnPhotoRoutes';
import { FnHttpClientGalleryHost } from './FnHttpClientTypes';
import {
  AiPersonItem,
  ExploreGeoItem,
  FnClientResult,
  GalleryListItem,
  MapPreviewAllPointItem,
  MediaCategoryItem,
  PhotoFolderListItem,
  SearchFilterListData,
  SearchFilterListNode,
  SmartCategoryItem,
  UserAlbumItem
} from '../../model/FnApiTypes';
import { normalizeGalleryListItems } from '../../album/GalleryListItemNormalize';

export class FnHttpClientGalleryRequest {
  protected readonly host: FnHttpClientGalleryHost;

  constructor(host: FnHttpClientGalleryHost) {
    this.host = host;
  }

  protected get baseUrl(): string {
    return this.host.getBaseUrl();
  }

  protected get token(): string {
    return this.host.getToken();
  }

  protected get longToken(): string {
    return this.host.getLongToken();
  }

  protected registerPendingRequest(req: http.HttpRequest): void {
    this.host.registerPendingRequest(req);
  }

  protected unregisterPendingRequest(req: http.HttpRequest): void {
    this.host.unregisterPendingRequest(req);
  }

  protected buildGalleryFetchHeaders(authxVal: string, cookieHeader: string): Record<string, string> {
    return this.host.buildGalleryFetchHeaders(authxVal, cookieHeader);
  }

  protected async requestGalleryGetJson<T>(pathCandidates: string[], gallerySign: FnGalleryGetSignSpec, timeoutMs: number, tryTimes: number): Promise<FnClientResult<T>> {
    return this.host.requestGalleryGetJson(pathCandidates, gallerySign, timeoutMs, tryTimes) as Promise<FnClientResult<T>>;
  }

  protected async rawRequest(fullUrl: string, method: http.RequestMethod, header: Record<string, string>, bodyStr: string | undefined, timeoutMs: number, skipRemoteCert: boolean) {
    return this.host.rawRequest(fullUrl, method, header, bodyStr, timeoutMs, skipRemoteCert);
  }

  protected static envelopeErrorLine(body: Record<string, string | number | Object | undefined>): string {
    const tryKeys: string[] = ['msg', 'message', 'errmsg', 'error', 'detail', 'errorMessage', 'reason'];
    for (let i = 0; i < tryKeys.length; i++) {
      const v = body[tryKeys[i]];
      if (typeof v === "string" && v.length > 0) {
        return v;
      }
    }
    const d = body['data'];
    if (d !== undefined && d !== null && typeof d === "object" && !Array.isArray(d)) {
      const o = d as Record<string, string | Object | undefined>;
      for (let j = 0; j < tryKeys.length; j++) {
        const k = tryKeys[j];
        const v2 = o[k];
        if (typeof v2 === "string" && v2.length > 0) {
          return v2;
        }
      }
    }
    return '';
  }

  protected static galleryErrorBodyPreview(rawBody: string | undefined): string {
    if (rawBody === undefined) {
      return '';
    }
    const max = 640;
    if (rawBody.length <= max) {
      return rawBody;
    }
    return `${rawBody.substring(0, max)}...`;
  }

  protected static envelopeCodeNum(body: Record<string, string | number | Object | undefined>): number {
    const c = body['code'];
    if (typeof c === "number" && !isNaN(c)) {
      return c;
    }
    if (typeof c === "string") {
      const n = parseInt(c, 10);
      return isNaN(n) ? -1 : n;
    }
    return -1;
  }

  protected static galleryEnvelopeBizOk(body: Record<string, string | number | Object | undefined>): boolean {
    const c = body['code'];
    if (c === undefined || c === null) {
      const err = FnHttpClientGalleryRequest.envelopeErrorLine(body);
      const data = body['data'];
      const result = body['result'];
      if (err.length > 0 && (data === undefined || data === null) && (result === undefined || result === null)) {
        return false;
      }
      return true;
    }
    if (typeof c === "number" && !isNaN(c)) {
      return c === 0;
    }
    if (typeof c === "string") {
      const n = parseInt(c, 10);
      return !isNaN(n) && n === 0;
    }
    return false;
  }

  protected static galleryEnvelopeData(body: Record<string, string | number | Object | undefined>): Object | undefined {
    const d = body['data'];
    if (d !== undefined && d !== null) {
      return d as Object;
    }
    const r = body['result'];
    if (r !== undefined && r !== null) {
      return r as Object;
    }
    return undefined;
  }

  protected static buildMapGetPathCandidates(paths: string[], qs: string): string[] {
    const out: string[] = [];
    for (let i = 0; i < paths.length; i++) {
      const rel = paths[i];
      out.push(qs.length > 0 ? `${rel}?${qs}` : rel);
    }
    return out;
  }

  protected static parseSearchFilterListData(payload: Object | undefined): SearchFilterListData {
    const out: SearchFilterListData = { list: [] };
    const nodes: SearchFilterListNode[] = [];
    if (payload === undefined || payload === null) {
      return out;
    }
    let rawList: Object[] = [];
    if (Array.isArray(payload)) {
      rawList = payload as Object[];
    } else {
      const rec = payload as Record<string, Object | undefined>;
      const inner = rec['data'] ?? rec['result'];
      if (inner !== undefined && typeof inner === 'object' && !Array.isArray(inner)) {
        const innerRec = inner as Record<string, Object | undefined>;
        const innerList = innerRec['list'] ?? innerRec['items'] ?? innerRec['filters'];
        if (Array.isArray(innerList)) {
          rawList = innerList as Object[];
        }
      }
      if (rawList.length === 0) {
        const cand = rec['list'] ?? rec['items'] ?? rec['filters'];
        if (Array.isArray(cand)) {
          rawList = cand as Object[];
        }
      }
    }
    for (let i = 0; i < rawList.length; i++) {
      const el = rawList[i];
      if (typeof el === 'object' && el !== null) {
        nodes.push(el as SearchFilterListNode);
      }
    }
    out.list = nodes;
    return out;
  }

  protected static parseFolderListPayload(payload: Object): PhotoFolderListItem[] {
    const items: PhotoFolderListItem[] = [];
    let rawList: Object[] = [];
    if (Array.isArray(payload)) {
      rawList = payload as Object[];
    } else {
      const rec = payload as Record<string, Object | undefined>;
      const cand = rec['list'] ?? rec['items'] ?? rec['folders'];
      if (Array.isArray(cand)) {
        rawList = cand as Object[];
      }
    }
    for (let i = 0; i < rawList.length; i++) {
      const el = rawList[i];
      if (typeof el === 'object' && el !== null) {
        items.push(el as PhotoFolderListItem);
      }
    }
    return items;
  }

  protected static mediaCategoryItemsFromData(dataObj: Object | undefined): MediaCategoryItem[] {
    if (dataObj === undefined || dataObj === null) {
      return [];
    }
    let rawArr: Object[];
    if (Array.isArray(dataObj)) {
      rawArr = dataObj as Object[];
    } else {
      const d = dataObj as Record<string, Object | undefined>;
      const found =
        d['list'] ?? d['items'] ?? d['categoryList'] ?? d['categories'] ??
        d['mediaCategoryList'] ?? d['rows'] ??
        d['records'] ?? d['data'] ?? d['result'];
      if (!Array.isArray(found)) {
        return [];
      }
      rawArr = found as Object[];
    }
    const result: MediaCategoryItem[] = [];
    for (let i = 0; i < rawArr.length; i++) {
      const el = rawArr[i];
      if (typeof el === 'object' && el !== null) {
        result.push(FnHttpClientGalleryRequest.normalizeCategoryItem(el as Record<string, Object | undefined>));
      }
    }
    return result;
  }

  protected static readTrimmedString(
    value: Object | string | number | boolean | undefined | null
  ): string {
    if (typeof value === 'string') {
      return value.trim();
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return String(value).trim();
    }
    return '';
  }

  protected static readFirstNonNegativeNumber(
    raw: Record<string, Object | string | number | boolean | undefined | null>,
    keys: string[]
  ): number {
    for (let i = 0; i < keys.length; i++) {
      const v = raw[keys[i]];
      if (typeof v === 'number' && Number.isFinite(v)) {
        return Math.max(0, Math.floor(v));
      }
      if (typeof v === 'string') {
        const n = Number(v);
        if (Number.isFinite(n)) {
          return Math.max(0, Math.floor(n));
        }
      }
    }
    return -1;
  }

  protected static asLooseJsonRecord(
    value: Object | string | number | boolean | undefined | null
  ): Record<string, Object | string | number | boolean | undefined | null> | null {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      return null;
    }
    return value as Record<string, Object | string | number | boolean | undefined | null>;
  }

  protected static readFirstString(
    raw: Record<string, Object | string | number | boolean | undefined | null>,
    keys: string[]
  ): string {
    for (let i = 0; i < keys.length; i++) {
      const text = FnHttpClientGalleryRequest.readTrimmedString(raw[keys[i]]);
      if (text.length > 0) {
        return text;
      }
    }
    return '';
  }

  protected static readThumbnailLikeUrl(
    raw: Record<string, Object | string | number | boolean | undefined | null>
  ): string {
    const thumbVal = raw['thumbnail'];
    if (typeof thumbVal === 'string') {
      const text = thumbVal.trim();
      if (text.length > 0) {
        return text;
      }
    }
    const thumbObj = FnHttpClientGalleryRequest.asLooseJsonRecord(thumbVal);
    if (thumbObj === null) {
      return '';
    }
    return FnHttpClientGalleryRequest.readFirstString(thumbObj, [
      'mUrl',
      'sUrl',
      'xsUrl',
      'xxsUrl',
      'originalUrl',
      'videoUrl',
      'url',
      'src'
    ]);
  }

  protected static buildPhotoThumbStream(
    raw: Record<string, Object | string | number | boolean | undefined | null>,
    mode: 'm' | 's' = 'm'
  ): string {
    const id = FnHttpClientGalleryRequest.readFirstString(raw, ['photoId', 'id']);
    const uuid = FnHttpClientGalleryRequest.readFirstString(raw, ['uuid', 'photoUUID', 'session']);
    if (id.length === 0 || uuid.length === 0 || id === 'null' || uuid === 'null') {
      return '';
    }
    return `${FN_PHOTO_API_PREFIX}/stream/p/t/${id}/${mode}/${uuid}`;
  }

  protected static pickBestCoverUrl(
    raw: Record<string, Object | string | number | boolean | undefined | null>,
    nestedKeys: string[]
  ): string {
    const direct = FnHttpClientGalleryRequest.readFirstString(raw, [
      'cover',
      'thumb',
      'small_thumb',
      'thumb_url',
      'poster',
      'posterUrl',
      'avatarUrl',
      'faceUrl',
      'imageUrl',
      'imgUrl',
      'photoUrl',
      'url',
      'src',
      'path'
    ]);
    if (direct.length > 0) {
      return direct;
    }
    const thumbnailUrl = FnHttpClientGalleryRequest.readThumbnailLikeUrl(raw);
    if (thumbnailUrl.length > 0) {
      return thumbnailUrl;
    }
    for (let i = 0; i < nestedKeys.length; i++) {
      const nested = FnHttpClientGalleryRequest.asLooseJsonRecord(raw[nestedKeys[i]]);
      if (nested === null) {
        continue;
      }
      const nestedDirect = FnHttpClientGalleryRequest.readFirstString(nested, [
        'cover',
        'thumb',
        'small_thumb',
        'thumb_url',
        'poster',
        'posterUrl',
        'avatarUrl',
        'faceUrl',
        'imageUrl',
        'imgUrl',
        'photoUrl',
        'url',
        'src',
        'path'
      ]);
      if (nestedDirect.length > 0) {
        return nestedDirect;
      }
      const nestedThumbUrl = FnHttpClientGalleryRequest.readThumbnailLikeUrl(nested);
      if (nestedThumbUrl.length > 0) {
        return nestedThumbUrl;
      }
      const nestedPhotoStream = FnHttpClientGalleryRequest.buildPhotoThumbStream(nested);
      if (nestedPhotoStream.length > 0) {
        return nestedPhotoStream;
      }
    }
    return FnHttpClientGalleryRequest.buildPhotoThumbStream(raw);
  }

  protected static normalizeSmartCategoryItem(
    raw: Record<string, Object | string | number | boolean | undefined | null>
  ): SmartCategoryItem {
    const out = raw as SmartCategoryItem;
    // 官方 ai-smart-rec/categories 数量字段为 itemCount
    const count = FnHttpClientGalleryRequest.readFirstNonNegativeNumber(raw, [
      'itemCount',
      'item_count',
      'count',
      'total',
      'photoCount',
      'photo_count'
    ]);
    if (count >= 0) {
      out.itemCount = count;
    }
    const coverUrl = FnHttpClientGalleryRequest.pickBestCoverUrl(raw, ['poster', 'coverInfo', 'coverPhoto']);
    if (coverUrl.length > 0) {
      raw['cover'] = coverUrl;
      if (FnHttpClientGalleryRequest.readTrimmedString(raw['thumb']).length <= 0) {
        raw['thumb'] = coverUrl;
      }
    }
    return out;
  }

  protected static smartCategoryItemsFromData(dataObj: Object | undefined): SmartCategoryItem[] {
    if (dataObj === undefined || dataObj === null) {
      return [];
    }
    let rawArr: Object[];
    if (Array.isArray(dataObj)) {
      rawArr = dataObj as Object[];
    } else {
      const d = dataObj as Record<string, Object | undefined>;
      const found = d['list'] ?? d['items'] ?? d['records'] ?? d['rows'] ?? d['data'] ?? d['result'];
      if (!Array.isArray(found)) {
        return [];
      }
      rawArr = found as Object[];
    }
    const result: SmartCategoryItem[] = [];
    for (let i = 0; i < rawArr.length; i++) {
      const el = rawArr[i];
      const raw = FnHttpClientGalleryRequest.asLooseJsonRecord(el);
      if (raw !== null) {
        result.push(FnHttpClientGalleryRequest.normalizeSmartCategoryItem(raw));
      }
    }
    return result;
  }

  protected static geoItemsFromData(dataObj: Object | undefined): ExploreGeoItem[] {
    if (dataObj === undefined || dataObj === null) {
      return [];
    }
    let rawArr: Object[];
    if (Array.isArray(dataObj)) {
      rawArr = dataObj as Object[];
    } else {
      const d = dataObj as Record<string, Object | undefined>;
      const found = d['list'] ?? d['items'] ?? d['records'] ?? d['rows'] ?? d['data'] ?? d['result'];
      if (!Array.isArray(found)) {
        return [];
      }
      rawArr = found as Object[];
    }
    const result: ExploreGeoItem[] = [];
    for (let i = 0; i < rawArr.length; i++) {
      const el = rawArr[i];
      const raw = FnHttpClientGalleryRequest.asLooseJsonRecord(el);
      if (raw !== null) {
        result.push(raw as ExploreGeoItem);
      }
    }
    return result;
  }

  protected static mapPreviewPointItemsFromData(dataObj: Object | undefined): MapPreviewAllPointItem[] {
    if (dataObj === undefined || dataObj === null) {
      return [];
    }
    let rawArr: Object[];
    if (Array.isArray(dataObj)) {
      rawArr = dataObj as Object[];
    } else {
      const d = dataObj as Record<string, Object | undefined>;
      const found = d['list'] ?? d['items'] ?? d['records'] ?? d['rows'] ??
        d['points'] ?? d['markers'] ?? d['clusters'] ?? d['data'] ?? d['result'];
      if (!Array.isArray(found)) {
        return [];
      }
      rawArr = found as Object[];
    }
    const result: MapPreviewAllPointItem[] = [];
    for (let i = 0; i < rawArr.length; i++) {
      const el = rawArr[i];
      const raw = FnHttpClientGalleryRequest.asLooseJsonRecord(el);
      if (raw !== null) {
        result.push(raw as MapPreviewAllPointItem);
      }
    }
    return result;
  }

  protected static normalizeAiPersonItem(
    raw: Record<string, Object | string | number | boolean | undefined | null>
  ): AiPersonItem {
    const out = raw as AiPersonItem;
    let faceUrl = FnHttpClientGalleryRequest.pickBestCoverUrl(raw, ['face', 'avatar', 'poster', 'coverInfo', 'coverPhoto']);
    if (faceUrl.length <= 0) {
      const faceId = FnHttpClientGalleryRequest.readFirstString(raw, ['faceId', 'avatarId', 'posterId', 'coverId', 'id']);
      if (faceId.length > 0) {
        faceUrl = `${FN_PHOTO_API_PREFIX}/stream/face/${faceId}`;
      }
    }
    if (faceUrl.length > 0) {
      raw['faceUrl'] = faceUrl;
      if (FnHttpClientGalleryRequest.readTrimmedString(raw['cover']).length <= 0) {
        raw['cover'] = faceUrl;
      }
      if (FnHttpClientGalleryRequest.readTrimmedString(raw['thumb']).length <= 0) {
        raw['thumb'] = faceUrl;
      }
    }
    return out;
  }

  protected static aiPersonItemsFromData(dataObj: Object | undefined): AiPersonItem[] {
    if (dataObj === undefined || dataObj === null) {
      return [];
    }
    let rawArr: Object[];
    if (Array.isArray(dataObj)) {
      rawArr = dataObj as Object[];
    } else {
      const d = dataObj as Record<string, Object | undefined>;
      const found = d['list'] ?? d['items'] ?? d['records'] ?? d['rows'] ?? d['data'] ?? d['result'];
      if (!Array.isArray(found)) {
        return [];
      }
      rawArr = found as Object[];
    }
    const result: AiPersonItem[] = [];
    for (let i = 0; i < rawArr.length; i++) {
      const el = rawArr[i];
      const raw = FnHttpClientGalleryRequest.asLooseJsonRecord(el);
      if (raw !== null) {
        result.push(FnHttpClientGalleryRequest.normalizeAiPersonItem(raw));
      }
    }
    return result;
  }

  protected static normalizeUserAlbumItem(
    raw: Record<string, Object | string | number | boolean | undefined | null>
  ): UserAlbumItem {
    const idText = FnHttpClientGalleryRequest.readFirstString(raw, ['albumId', 'id', 'album_id']);
    const nameText = FnHttpClientGalleryRequest.readFirstString(raw, ['albumName', 'name', 'title']);
    const poster = FnHttpClientGalleryRequest.readFirstString(raw, ['posterUrl', 'poster_url', 'cover', 'coverUrl']);
    const categoryRaw = raw['category'] ?? raw['albumType'] ?? raw['album_type'];
    let category: number | undefined = undefined;
    if (typeof categoryRaw === 'number' && Number.isFinite(categoryRaw)) {
      category = Math.floor(categoryRaw);
    } else if (typeof categoryRaw === 'string' && categoryRaw.length > 0) {
      const n = Number(categoryRaw);
      if (Number.isFinite(n)) {
        category = Math.floor(n);
      }
    }
    const photo = FnHttpClientGalleryRequest.readFirstNonNegativeNumber(raw, ['photoCount', 'photo_count']);
    const video = FnHttpClientGalleryRequest.readFirstNonNegativeNumber(raw, ['videoCount', 'video_count']);
    let itemCount = FnHttpClientGalleryRequest.readFirstNonNegativeNumber(raw, ['itemCount', 'item_count', 'count', 'total']);
    if (itemCount < 0 && (photo >= 0 || video >= 0)) {
      itemCount = Math.max(0, photo) + Math.max(0, video);
    }
    const sharedVal = raw['shared'];
    const shared = sharedVal === true || sharedVal === 1 || sharedVal === '1' || sharedVal === 'true';
    const ownerFlag = raw['isOwner'] ?? raw['is_owner'];
    let isOwner: boolean | undefined = undefined;
    if (typeof ownerFlag === 'boolean') {
      isOwner = ownerFlag;
    }
    const item: UserAlbumItem = {
      id: idText.length > 0 ? idText : undefined,
      albumId: idText.length > 0 ? idText : undefined,
      name: nameText.length > 0 ? nameText : undefined,
      albumName: nameText.length > 0 ? nameText : undefined,
      category: category,
      albumType: category,
      posterUrl: poster.length > 0 ? poster : undefined,
      cover: poster.length > 0 ? poster : undefined,
      itemCount: itemCount >= 0 ? itemCount : undefined,
      photoCount: photo >= 0 ? photo : undefined,
      videoCount: video >= 0 ? video : undefined,
      shared: shared,
      ownerName: FnHttpClientGalleryRequest.readFirstString(raw, ['ownerName', 'owner_name']),
      isOwner: isOwner
    };
    const ownerIdText = FnHttpClientGalleryRequest.readFirstString(raw, ['ownerId', 'owner_id']);
    if (ownerIdText.length > 0) {
      item.ownerId = ownerIdText;
    }
    return item;
  }

  protected static userAlbumItemsFromData(dataObj: Object | undefined): UserAlbumItem[] {
    if (dataObj === undefined || dataObj === null) {
      return [];
    }
    let rawArr: Object[];
    if (Array.isArray(dataObj)) {
      rawArr = dataObj as Object[];
    } else {
      const d = dataObj as Record<string, Object | undefined>;
      const found = d['list'] ?? d['items'] ?? d['records'] ?? d['rows'] ?? d['data'] ?? d['result'];
      if (!Array.isArray(found)) {
        return [];
      }
      rawArr = found as Object[];
    }
    const result: UserAlbumItem[] = [];
    for (let i = 0; i < rawArr.length; i++) {
      const raw = FnHttpClientGalleryRequest.asLooseJsonRecord(rawArr[i]);
      if (raw !== null) {
        result.push(FnHttpClientGalleryRequest.normalizeUserAlbumItem(raw));
      }
    }
    return result;
  }

  /**
   * 已知 file_type / 分类 slug → 列表展示名（media_category/list 常不带 name 时的兜底）
   */
  protected static mediaCategoryLabelForKey(key: string): string | undefined {
    const k = key.trim();
    if (k.length === 0) {
      return undefined;
    }
    if (k === 'photo') {
      return '照片';
    }
    if (k === 'video') {
      return '视频';
    }
    if (k === 'live_photo') {
      return '实况 / 动态照片';
    }
    if (k === 'gif') {
      return '动图';
    }
    if (k === 'raw') {
      return 'RAW';
    }
    if (k === 'screenshot') {
      return '屏幕截图';
    }
    /** 与 Web `zp(t)` 一致：searchValue `"360"`、`panorama` */
    if (k === '360') {
      return '360° 全景';
    }
    if (k === 'panorama') {
      return '全景照片';
    }
    return undefined;
  }

  /**
   * 服务端偶发「未命名分类」占位文案：若当作有效名称会挡住后面的 key → 屏幕截图 等兜底。
   */
  protected static isPlaceholderCategoryDisplayName(s: string): boolean {
    const t = s.trim();
    if (t.length === 0) {
      return true;
    }
    const lower = t.toLowerCase();
    return t === '未命名分类' || t === '未命名' ||
      lower === 'unnamed' || lower === 'unknown' || lower === 'n/a' ||
      t === '-' || t === '—' || t === '--';
  }

  /**
   * 接口偶发把枚举包一层对象：mediaCategory: { type: 6 }、{ slug: 'screenshot' } 等，剥一层取标量。
   */
  protected static unwrapCategoryNested(v: Object): Object | undefined {
    if (typeof v !== 'object' || v === null || Array.isArray(v)) {
      return v;
    }
    const o = v as Record<string, Object | undefined>;
    // 不读嵌套里的 name：可能是「未命名分类」等占位，会被误当成 file_type 字符串
    const inner =
      o['category'] ?? o['type'] ?? o['slug'] ?? o['key'] ?? o['code'] ??
      o['value'] ?? o['id'];
    return inner !== undefined && inner !== null ? inner : v;
  }

  /**
   * 分类行上的「类型」原始字段：不同版本字段名不同。
   * 注意：`categoryId` 在部分 payload 里是**封面照片 id**（很大），不能当枚举；仅当值为 **1–8**（飞牛 Web 媒体类型枚举）时才采纳。
   * `type` / `mediaType` 同理，避免把无关数字当成分类。
   */
  protected static pickCategoryScalar(raw: Record<string, Object | undefined>): Object | undefined {
    const preferKeys: string[] = [
      'category', 'categoryType', 'category_type',
      'mediaCategory', 'media_category', 'cat',
      'categoryCode', 'category_code', 'enumValue', 'enum',
    ];
    const narrowKeys: string[] = [
      'type', 'mediaType', 'media_type',
      'categoryId', 'category_id',
    ];
    const tryVal = (v: Object | undefined, onlySmallEnum: boolean): Object | undefined => {
      if (v === undefined || v === null) {
        return undefined;
      }
      if (typeof v === 'string' && v.trim().length === 0) {
        return undefined;
      }
      let x: Object | undefined = FnHttpClientGalleryRequest.unwrapCategoryNested(v as Object);
      if (x === undefined || x === null) {
        return undefined;
      }
      if (typeof x === 'number' && Number.isFinite(x)) {
        const n = Math.floor(x as number);
        if (onlySmallEnum && (n < 1 || n > 8)) {
          return undefined;
        }
        return n;
      }
      return x;
    };
    for (let i = 0; i < preferKeys.length; i++) {
      const got = tryVal(raw[preferKeys[i]], false);
      if (got !== undefined) {
        return got;
      }
    }
    for (let j = 0; j < narrowKeys.length; j++) {
      const gotN = tryVal(raw[narrowKeys[j]], true);
      if (gotN !== undefined) {
        return gotN;
      }
    }
    return undefined;
  }

  /**
   * 飞牛 **Web 前端 `zp(i18n)`**（见 /p/assets 打包）：媒体类型枚举 1–8 → 展示名 + v2 search 的 filterValue（searchValue）。
   * 旧版文档写「1–6 且 6=截图」已过时：**6=360°、7=全景、8=截图**。
   */
  protected static applyMediaCategoryEnumByIndex(out: MediaCategoryItem, idx: number): void {
    if (idx === 1) {
      out.name = '照片';
      out.key = 'photo';
    } else if (idx === 2) {
      out.name = '视频';
      out.key = 'video';
    } else if (idx === 3) {
      out.name = '实况 / 动态照片';
      out.key = 'live_photo';
    } else if (idx === 4) {
      out.name = '动图';
      out.key = 'gif';
    } else if (idx === 5) {
      out.name = 'RAW';
      out.key = 'raw';
    } else if (idx === 6) {
      out.name = '360° 全景';
      out.key = '360';
    } else if (idx === 7) {
      out.name = '全景照片';
      out.key = 'panorama';
    } else if (idx === 8) {
      out.name = '屏幕截图';
      out.key = 'screenshot';
    }
  }

  /**
   * 将原始 JSON 对象规范化为 MediaCategoryItem。
   *
   * 依据飞牛 Web 打包（如 `Cl8WJe889GVKre8N.js` 内 `zp`）：`category` 为整数 **1–8** 或 slug；
   * **8=截图、6=360°**（勿再按旧版把 6 当成截图）。
   *   - `count` 为该分类的媒体数量
   *   - 封面：`id` + `uuid` / `photoUUID`（接口字段不一致）
   *   - 筛选：`/p/api/v2/search/results` 的 body 与 Web 一致：`filters: [{ filterName:"file_type", filterValue:"photo"|"screenshot" ... }]`
   * 新版列表项可能带 `filterValue`、`displayName`；部分设备用 `specialType: 3` 表示截图类（与单张照片上的标记一致）。
   */
  protected static normalizeCategoryItem(raw: Record<string, Object | undefined>): MediaCategoryItem {
    const out: MediaCategoryItem = {};

    let catNum = NaN;
    const catRaw = FnHttpClientGalleryRequest.pickCategoryScalar(raw);
    if (typeof catRaw === 'number' && Number.isFinite(catRaw)) {
      const n = Math.floor(catRaw as number);
      // 枚举段 1–8（与 Web zp 一致）；超出则不当成分类序号
      catNum = (n >= 1 && n <= 8) ? n : NaN;
    } else if (typeof catRaw === 'string') {
      const t = (catRaw as string).trim();
      if (t.length > 0) {
        const asInt = parseInt(t, 10);
        if (Number.isFinite(asInt) && String(asInt) === t && asInt >= 1 && asInt <= 8) {
          catNum = asInt;
        } else {
          // 非纯数字：直接作为 file_type（如 screenshot）
          out.key = t;
        }
      }
    }

    if (Number.isFinite(catNum) && catNum >= 1 && catNum <= 8) {
      FnHttpClientGalleryRequest.applyMediaCategoryEnumByIndex(out, Math.floor(catNum));
    }

    const nameCand =
      raw['name'] ?? raw['title'] ?? raw['label'] ?? raw['categoryName'] ?? raw['displayName'];
    if (typeof nameCand === 'string' && nameCand.trim().length > 0) {
      const nt = nameCand.trim();
      // 占位「未命名分类」不能覆盖已由枚举推出来的「屏幕截图」等
      if (!FnHttpClientGalleryRequest.isPlaceholderCategoryDisplayName(nt)) {
        out.name = nt;
      }
    }
    const keyCand =
      raw['key'] ?? raw['searchValue'] ?? raw['filterValue'] ??
      raw['file_type'] ?? raw['fileType'] ?? raw['mimeCategory'] ?? raw['mime_category'];
    if (typeof keyCand === 'string' && keyCand.trim().length > 0) {
      const kt = keyCand.trim();
      const kInt = parseInt(kt, 10);
      // 列表下发数字枚举时与 Web zp 一致（8=截图，6=360 等）
      if (Number.isFinite(kInt) && String(kInt) === kt && kInt >= 1 && kInt <= 8) {
        FnHttpClientGalleryRequest.applyMediaCategoryEnumByIndex(out, kInt);
      } else {
        out.key = kt;
      }
    }

    // 分类枚举 id（与 file_type 筛选一致）；纯 slug 行不强行写 id，避免与封面照片 id 混淆
    out.id = undefined;
    if (Number.isFinite(catNum) && catNum >= 1 && catNum <= 8) {
      out.id = String(Math.floor(catNum));
    } else if (typeof keyCand === 'string' && keyCand.trim().length > 0) {
      const kInt = parseInt(keyCand.trim(), 10);
      if (Number.isFinite(kInt) && String(kInt) === keyCand.trim() && kInt >= 1 && kInt <= 8) {
        out.id = String(kInt);
      }
    }

    /** 部分版本仅通过 specialType 区分截图（常见值 3），与 v2 search 的 file_type=screenshot 对应 */
    const stRaw = raw['specialType'] ?? raw['special_type'];
    let stNum = NaN;
    if (typeof stRaw === 'number' && Number.isFinite(stRaw)) {
      stNum = Math.floor(stRaw as number);
    } else if (typeof stRaw === 'string' && stRaw.trim().length > 0) {
      const st = parseInt(stRaw.trim(), 10);
      if (Number.isFinite(st)) {
        stNum = st;
      }
    }
    const keyBeforeSpecial = out.key !== undefined ? out.key : '';
    // 照片维度 specialType：常见 3=截图（与 category 枚举 8 并列）；勿再用 6（Web 上 6 已为 360°）
    if (keyBeforeSpecial.length === 0 && stNum === 3) {
      out.key = 'screenshot';
      if (out.name === undefined || out.name.length === 0 ||
        FnHttpClientGalleryRequest.isPlaceholderCategoryDisplayName(out.name)) {
        out.name = '屏幕截图';
      }
    }

    const keyForLabel = out.key !== undefined ? out.key : '';
    const nameNow = out.name !== undefined ? out.name : '';
    if (keyForLabel.length > 0 &&
      (nameNow.length === 0 || FnHttpClientGalleryRequest.isPlaceholderCategoryDisplayName(nameNow))) {
      const lb = FnHttpClientGalleryRequest.mediaCategoryLabelForKey(keyForLabel);
      if (lb !== undefined) {
        out.name = lb;
      }
    }

    const countRaw =
      raw['count'] ?? raw['total'] ?? raw['itemCount'] ?? raw['item_count'] ??
      raw['num'] ?? raw['size'] ?? raw['photoCount'] ?? raw['photo_count'];
    if (countRaw !== undefined) {
      const n = Number(countRaw);
      if (Number.isFinite(n) && n >= 0) {
        const c = Math.floor(n);
        out.count = c;
        out.total = c;
      }
    }

    const photoId = raw['id'];
    const photoUuid = raw['uuid'] ?? raw['photoUUID'];
    if (photoId !== undefined && photoId !== null &&
      photoUuid !== undefined && photoUuid !== null) {
      const idStr = String(photoId);
      const uuidStr = String(photoUuid);
      if (idStr.length > 0 && uuidStr.length > 0 &&
        idStr !== 'null' && uuidStr !== 'null') {
        out.cover = `${FN_PHOTO_API_PREFIX}/stream/p/t/${idStr}/m/${uuidStr}`;
      }
    }

    // v2 filters 与 Web 一致为小写 slug（photo、screenshot、live_photo…）
    if (out.key !== undefined && out.key.length > 0) {
      out.key = out.key.trim().toLowerCase();
    }

    return out;
  }

  protected static searchResultItemsFromData(dataObj: Object | undefined): GalleryListItem[] {
    if (dataObj === undefined || dataObj === null) {
      return [];
    }
    if (Array.isArray(dataObj)) {
      return dataObj as GalleryListItem[];
    }
    const d = dataObj as Record<string, Object | undefined>;
    const topRaw = d['list'];
    const topList: GalleryListItem[] | undefined = Array.isArray(topRaw) ? topRaw as GalleryListItem[] : undefined;
    // 与抓包一致：code=0 且 data.list 为照片数组；优先非空 list，避免误用 timeline
    if (topList !== undefined && topList.length > 0) {
      return topList;
    }
    // list 缺失 / null / [] 时尝试剥内层 data（少数网关或旧版套层）
    const inner = d['data'];
    if (inner !== undefined && typeof inner === 'object' && !Array.isArray(inner)) {
      const nested = FnHttpClientGalleryRequest.searchResultItemsFromData(inner);
      if (nested.length > 0) {
        return nested;
      }
    }
    if (topList !== undefined) {
      return topList;
    }
    if (Array.isArray(d['items'])) {
      return d['items'] as GalleryListItem[];
    }
    const KEYS: string[] = [
      'photos', 'records', 'results', 'photoList', 'photo_list',
      'data', 'mediaList', 'media_list',
      'fileList', 'file_list', 'pageList', 'page_list',
    ];
    for (let ki = 0; ki < KEYS.length; ki++) {
      const v = d[KEYS[ki]];
      if (Array.isArray(v) && (v as Object[]).length > 0) {
        return v as GalleryListItem[];
      }
    }
    return [];
  }

  /**
   * v2 /search/results 下单条与 gallery/getList 字段略有差异（如 fileName、relative mUrl），
   * 补齐后分类相册页日期键、扩展名与标题与主时间线一致。
   */
  protected static normalizeSearchResultGalleryItems(items: GalleryListItem[]): GalleryListItem[] {
    for (let i = 0; i < items.length; i++) {
      const rec = items[i] as Record<string, string | number | Object | undefined>;
      const fileNameVal = rec['fileName'];
      if (typeof fileNameVal === 'string') {
        const baseName = fileNameVal.trim();
        if (baseName.length > 0) {
          const fnLo = rec['filename'];
          if (fnLo === undefined || String(fnLo).trim().length === 0) {
            rec['filename'] = baseName;
          }
          const nm = rec['name'];
          if (nm === undefined || String(nm).trim().length === 0) {
            rec['name'] = baseName;
          }
        }
      }
      // additional.thumbnail 常为站点相对路径；网格里 nasUrl(base, pickThumb) 会拼完整 URL，此处不重复写
      const liveVal = rec['isLive'] ?? rec['is_live'];
      if (typeof liveVal === 'number' && liveVal === 1) {
        rec['isLive'] = 1;
      } else if (typeof liveVal === 'string' && (liveVal.trim() === '1' || liveVal.trim().toLowerCase() === 'true')) {
        rec['isLive'] = 1;
      }
    }
    return items;
  }

  /**
   * folder_view/getFileList 常见只返回 id + photoUUID。
   * 缩略图/原图走与主图库相同的 normalizeGalleryListItems。
   */
  protected static normalizeFolderViewItems(items: GalleryListItem[]): GalleryListItem[] {
    return normalizeGalleryListItems(items);
  }
}
