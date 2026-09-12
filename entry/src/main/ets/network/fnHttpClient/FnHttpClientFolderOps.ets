import { http } from '@kit.NetworkKit';
import { CertPolicy } from '../CertPolicy';
import { buildGallerySortedQuery, FnGalleryGetSignSpec, genFnGalleryAuthxPostRaw } from '../FnGalleryAuthx';
import { FN_PHOTO_API_PREFIX } from '../FnPhotoRoutes';
import { mergeGalleryWebCookieIntoNativeHeader } from '../FnWebCookies';
import { fnWebViewBaseUrl } from '../ServerUrl';
import { buildFnApiCookieHeader } from './FnHttpClientCookie';
import {
  GALLERY_FOLDER_COVER_SIGN_PATH,
  GALLERY_FOLDER_DIRLIST_PATH_CANDIDATES,
  GALLERY_FOLDER_DIRLIST_SIGN_PATH,
  GALLERY_FOLDER_FILELIST_PATH_CANDIDATES,
  GALLERY_FOLDER_FILELIST_SIGN_PATH,
  PHOTO_FOLDER_LIST_PATH_CANDIDATES,
  PHOTO_FOLDER_LIST_SIGN_PATH,
  escapeJsonString,
} from './FnHttpClientCommon';
import { FnHttpClientGalleryHost } from './FnHttpClientTypes';
import { FnHttpClientGalleryRequest } from './FnHttpClientGalleryRequest';
import {
  FnClientResult,
  FolderViewCoverData,
  FolderViewCoverItem,
  GalleryGetListData,
  GalleryListItem,
  PhotoFolderListData
} from '../../model/FnApiTypes';

export class FnHttpClientFolderOps extends FnHttpClientGalleryRequest {
  constructor(host: FnHttpClientGalleryHost) {
    super(host);
  }

  /**
   * 相册已选根目录：GET /p/api/v1/photo/folder/list
   * 浏览下钻请用 getFolderViewFolderList。desc/orderBy 与官方一致。
   */
  async getPhotoFolderList(
    timeoutMs: number = 20000,
    folderPath: string = '',
    desc: boolean = false,
    orderBy: number = 2
  ): Promise<FnClientResult<PhotoFolderListData>> {
    try {
      const params: Record<string, string | number | boolean> = {};
      params['desc'] = desc;
      params['orderBy'] = orderBy;
      const fp = folderPath.trim();
      if (fp.length > 0) {
        params['folderPath'] = fp;
      }
      const qs = buildGallerySortedQuery(params);
      const pathCandidates: string[] = [];
      for (let i = 0; i < PHOTO_FOLDER_LIST_PATH_CANDIDATES.length; i++) {
        pathCandidates.push(`${PHOTO_FOLDER_LIST_PATH_CANDIDATES[i]}?${qs}`);
      }
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: PHOTO_FOLDER_LIST_SIGN_PATH,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<Object>(
        pathCandidates,
        gallerySign,
        timeoutMs,
        3
      );
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '文件夹列表加载失败' };
      }
      const data: PhotoFolderListData = {
        list: FnHttpClientGalleryRequest.parseFolderListPayload(res.data)
      };
      return { success: true, data: data };
    } catch (e) {
      return { success: false, message: String(e) || '文件夹列表加载异常' };
    }
  }

  /**
   * 子目录列表：GET /p/api/v1/folder_view/getFolderList
   * 与官方文件夹视图一致，必须带 folderPath；根目录仍走 photo/folder/list。
   */
  async getFolderViewFolderList(
    folderPath: string,
    desc: boolean = false,
    orderBy: number = 2,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<PhotoFolderListData>> {
    const fp = folderPath.trim();
    if (fp.length === 0) {
      return { success: false, message: 'folderPath 不能为空' };
    }
    try {
      const params: Record<string, string | number | boolean> = {};
      params['folderPath'] = fp;
      params['desc'] = desc;
      params['orderBy'] = orderBy;
      const qs = buildGallerySortedQuery(params);
      const pathCandidates: string[] = [];
      for (let i = 0; i < GALLERY_FOLDER_DIRLIST_PATH_CANDIDATES.length; i++) {
        pathCandidates.push(`${GALLERY_FOLDER_DIRLIST_PATH_CANDIDATES[i]}?${qs}`);
      }
      const gallerySign: FnGalleryGetSignSpec = {
        signPathOnly: GALLERY_FOLDER_DIRLIST_SIGN_PATH,
        queryParams: params
      };
      const res = await this.requestGalleryGetJson<Object>(
        pathCandidates,
        gallerySign,
        timeoutMs,
        3
      );
      if (!res.success || res.data === undefined) {
        return { success: false, message: res.message ?? '文件夹列表加载失败' };
      }
      const data: PhotoFolderListData = {
        list: FnHttpClientGalleryRequest.parseFolderListPayload(res.data)
      };
      return { success: true, data: data };
    } catch (e) {
      return { success: false, message: String(e) || '文件夹列表加载异常' };
    }
  }

  async getFolderViewCover(
    currentPath: string,
    dirNames: string[],
    timeoutMs: number = 20000
  ): Promise<FnClientResult<FolderViewCoverData>> {
    const names: string[] = [];
    for (let i = 0; i < dirNames.length; i++) {
      const n = dirNames[i].trim();
      if (n.length > 0) {
        names.push(n);
      }
    }
    if (names.length === 0) {
      const empty: FolderViewCoverData = { list: [] };
      return { success: true, data: empty };
    }
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const path = GALLERY_FOLDER_COVER_SIGN_PATH;
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const quoted: string[] = [];
      for (let i = 0; i < names.length; i++) {
        quoted.push(`"${escapeJsonString(names[i])}"`);
      }
      const bodyStr =
        `{"currentPath":"${escapeJsonString(currentPath.trim())}","dirNames":[${quoted.join(',')}]}`;
      const authx = await genFnGalleryAuthxPostRaw(path, bodyStr);
      const headers = this.buildGalleryFetchHeaders(authx, cookie);
      headers['Content-Type'] = 'application/json';
      const raw = await this.rawRequest(
        `${activeBase}${path}`,
        http.RequestMethod.POST,
        headers,
        bodyStr,
        timeoutMs,
        CertPolicy.isTrusted(activeBase)
      );
      if (raw.code < 200 || raw.code >= 300) {
        return { success: false, message: `HTTP ${raw.code}` };
      }
      let parsed: Record<string, string | number | Object | undefined>;
      try {
        parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
      } catch (_e) {
        return { success: false, message: '封面响应无法解析' };
      }
      if (!FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
        const errLine = FnHttpClientGalleryRequest.envelopeErrorLine(parsed);
        return { success: false, message: errLine.length > 0 ? errLine : '获取文件夹封面失败' };
      }
      const payload = parsed['data'];
      const items: FolderViewCoverItem[] = [];
      let rawList: Object[] = [];
      if (Array.isArray(payload)) {
        rawList = payload as Object[];
      } else if (payload !== undefined && typeof payload === 'object' && payload !== null) {
        const rec = payload as Record<string, Object | undefined>;
        const cand = rec['list'] ?? rec['items'];
        if (Array.isArray(cand)) {
          rawList = cand as Object[];
        }
        if (rawList.length === 0) {
          const keys = Object.keys(rec);
          for (let ki = 0; ki < keys.length; ki++) {
            const key = keys[ki];
            if (key === 'list' || key === 'items' || key === 'total' || key === 'count' || key === 'code') {
              continue;
            }
            const el = rec[key];
            if (typeof el === 'object' && el !== null) {
              const one = el as FolderViewCoverItem;
              const hasPath = (one.path !== undefined && one.path.length > 0) ||
                (one.folderPath !== undefined && one.folderPath.length > 0) ||
                (one.dirPath !== undefined && one.dirPath.length > 0);
              if (hasPath) {
                items.push(one);
              } else {
                const patched: FolderViewCoverItem = {
                  id: one.id,
                  uuid: one.uuid,
                  photoUUID: one.photoUUID,
                  dirName: one.dirName,
                  name: one.name,
                  path: key,
                  folderPath: one.folderPath
                };
                items.push(patched);
              }
            }
          }
        }
      }
      if (items.length === 0) {
        for (let i = 0; i < rawList.length; i++) {
          const el = rawList[i];
          if (typeof el === 'object' && el !== null) {
            items.push(el as FolderViewCoverItem);
          }
        }
      }
      const data: FolderViewCoverData = { list: items };
      return { success: true, data: data };
    } catch (e) {
      return { success: false, message: String(e) || '文件夹封面加载异常' };
    }
  }

  /**
   * 目录媒体列表：GET /p/api/v1/folder_view/getFileList
   * 点击详情中的文件夹路径时，用该接口打开同目录下全部媒体。
   */
  async getFolderViewFileList(
    folderPath: string,
    limit: number = 100,
    offset: number = 0,
    desc: boolean = false,
    orderBy: number = 2,
    timeoutMs: number = 20000
  ): Promise<FnClientResult<GalleryListItem[]>> {
    const fp = folderPath.trim();
    if (fp.length === 0) {
      return { success: false, message: 'folderPath 不能为空' };
    }
    const params: Record<string, string | number | boolean> = {};
    params['folderPath'] = fp;
    params['desc'] = desc;
    params['orderBy'] = orderBy;
    params['limit'] = limit;
    params['offset'] = offset;
    const qs = buildGallerySortedQuery(params);
    const pathCandidates: string[] = [];
    for (let i = 0; i < GALLERY_FOLDER_FILELIST_PATH_CANDIDATES.length; i++) {
      pathCandidates.push(`${GALLERY_FOLDER_FILELIST_PATH_CANDIDATES[i]}?${qs}`);
    }
    const gallerySign: FnGalleryGetSignSpec = {
      signPathOnly: GALLERY_FOLDER_FILELIST_SIGN_PATH,
      queryParams: params
    };
    const res = await this.requestGalleryGetJson<GalleryGetListData | GalleryListItem[]>(
      pathCandidates,
      gallerySign,
      timeoutMs,
      3
    );
    if (!res.success || res.data === undefined) {
      return { success: false, message: res.message ?? '文件夹媒体加载失败' };
    }
    const payload = res.data as GalleryGetListData | GalleryListItem[];
    if (Array.isArray(payload)) {
      return { success: true, data: FnHttpClientGalleryRequest.normalizeFolderViewItems(payload as GalleryListItem[]) };
    }
    const dataObj = payload as GalleryGetListData;
    const list = dataObj.list ?? dataObj.items ?? dataObj.photos ?? dataObj.records ?? [];
    if (!Array.isArray(list)) {
      return { success: true, data: [] };
    }
    return { success: true, data: FnHttpClientGalleryRequest.normalizeFolderViewItems(list as GalleryListItem[]) };
  }

  /**
   * 删除当前目录下的文件夹和文件：POST /p/api/v1/file/delete
   * 官方 folderView.removeFolderOrFile：{ path, ids, dirList }，dirList 为子目录名。
   * 含文件夹时不可恢复，与回收站接口不同。
   */
  async deleteFolderOrFile(
    parentPath: string,
    fileIds: string[],
    dirNames: string[],
    timeoutMs: number = 30000
  ): Promise<FnClientResult<Object>> {
    if (fileIds.length === 0 && dirNames.length === 0) {
      return { success: false, message: '没有可删除的项' };
    }
    try {
      const activeBase = fnWebViewBaseUrl(this.baseUrl);
      const path = `${FN_PHOTO_API_PREFIX}/file/delete`;
      const cookie = mergeGalleryWebCookieIntoNativeHeader(
        buildFnApiCookieHeader(this.token, this.longToken),
        activeBase
      );
      const bodyStr = FnHttpClientFolderOps.buildFileDeleteBody(parentPath, fileIds, dirNames);
      const authx = await genFnGalleryAuthxPostRaw(path, bodyStr);
      const headers = this.buildGalleryFetchHeaders(authx, cookie);
      headers['Content-Type'] = 'application/json';
      const raw = await this.rawRequest(
        `${activeBase}${path}`,
        http.RequestMethod.POST,
        headers,
        bodyStr,
        timeoutMs,
        CertPolicy.isTrusted(activeBase)
      );
      if (raw.code < 200 || raw.code >= 300) {
        return { success: false, message: `HTTP ${raw.code}` };
      }
      let parsed: Record<string, string | number | Object | undefined>;
      try {
        parsed = JSON.parse(raw.body) as Record<string, string | number | Object | undefined>;
      } catch (_e) {
        return { success: false, message: '删除响应解析失败' };
      }
      if (FnHttpClientGalleryRequest.galleryEnvelopeBizOk(parsed)) {
        return { success: true, data: parsed['data'] as Object };
      }
      const errLine = FnHttpClientGalleryRequest.envelopeErrorLine(parsed);
      return { success: false, message: errLine.length > 0 ? errLine : '删除失败' };
    } catch (e) {
      return { success: false, message: String(e) || '删除请求异常' };
    }
  }

  private static buildFileDeleteBody(parentPath: string, fileIds: string[], dirNames: string[]): string {
    return `{"path":"${escapeJsonString(parentPath)}","ids":${FnHttpClientFolderOps.jsonIdArray(fileIds)},"dirList":${FnHttpClientFolderOps.jsonStringArray(dirNames)}}`;
  }

  private static jsonIdArray(ids: string[]): string {
    const parts: string[] = [];
    for (let i = 0; i < ids.length; i++) {
      const raw = ids[i].trim();
      if (raw.length === 0) {
        continue;
      }
      const n = Number(raw);
      if (Number.isFinite(n) && n >= 0 && String(Math.floor(n)) === raw) {
        parts.push(`${Math.floor(n)}`);
      } else {
        parts.push(`"${escapeJsonString(raw)}"`);
      }
    }
    return `[${parts.join(',')}]`;
  }

  private static jsonStringArray(values: string[]): string {
    const parts: string[] = [];
    for (let i = 0; i < values.length; i++) {
      const raw = values[i].trim();
      if (raw.length === 0) {
        continue;
      }
      parts.push(`"${escapeJsonString(raw)}"`);
    }
    return `[${parts.join(',')}]`;
  }
}
