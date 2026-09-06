/**
 * 搜索选项：解析 filterlist、组装官方 filters / antiFilters JSON。
 * 字段名与 Web bundle 中 kf() / gu() 一致。
 */
import { FnHttpClient } from '../../network/FnHttpClient';
import {
  AiPersonItem,
  FnClientResult,
  MediaCategoryItem,
  PhotoFolderListItem,
  SearchFilterListData,
  SearchFilterListNode
} from '../../model/FnApiTypes';
import { personFace, personId, personName } from '../GalleryAlbumEntityData';
import {
  GallerySearchFilterCatalog,
  GallerySearchFilterSnapshot,
  GallerySearchFilterTreeNode,
  GallerySearchPickerOption
} from './GallerySearchFilterTypes';

function readRawString(raw: Record<string, Object | string | number | boolean | undefined | null>,
  keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const v = raw[keys[i]];
    if (typeof v === 'string' && v.trim().length > 0) {
      return v.trim();
    }
    if (typeof v === 'number' && Number.isFinite(v)) {
      return String(v);
    }
    if (typeof v === 'boolean') {
      return v ? '1' : '0';
    }
  }
  return '';
}

function findListNode(list: SearchFilterListNode[], name: string): SearchFilterListNode | undefined {
  for (let i = 0; i < list.length; i++) {
    const n = list[i];
    const fn = n.filterName;
    if (fn !== undefined && fn === name) {
      return n;
    }
  }
  return undefined;
}

function nodeValues(node: SearchFilterListNode): string[] {
  const values = node.filterValues;
  if (values !== undefined && values.length > 0) {
    return values;
  }
  const empty: string[] = [];
  return empty;
}

function nodeSubs(node: SearchFilterListNode): SearchFilterListNode[] {
  const subs = node.subFilter;
  if (subs !== undefined && subs.length > 0) {
    return subs;
  }
  const empty: SearchFilterListNode[] = [];
  return empty;
}

/**
 * 与官方 `_u` 一致：filterValues 为当前层，subFilter.filterName 对应当前 value。
 */
function treeFromFilterNode(node: SearchFilterListNode, suffixes: string[]): GallerySearchFilterTreeNode[] {
  const values = nodeValues(node);
  const subs = nodeSubs(node);
  const out: GallerySearchFilterTreeNode[] = [];
  for (let i = 0; i < values.length; i++) {
    const val: string = values[i];
    const child = new GallerySearchFilterTreeNode();
    const suffix = suffixes.length > 0 ? suffixes[0] : '';
    child.value = val;
    child.label = `${val}${suffix}`;
    let matched: SearchFilterListNode | undefined = undefined;
    for (let si = 0; si < subs.length; si++) {
      const subName = subs[si].filterName;
      if (subName !== undefined && subName === val) {
        matched = subs[si];
        break;
      }
    }
    if (matched !== undefined) {
      const rest: string[] = [];
      for (let ri = 1; ri < suffixes.length; ri++) {
        rest.push(suffixes[ri]);
      }
      child.children = treeFromFilterNode(matched, rest);
    }
    out.push(child);
  }
  return out;
}

function flattenTree(nodes: GallerySearchFilterTreeNode[], prefixPath: string[], prefixLabel: string,
  out: GallerySearchPickerOption[]): void {
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i];
    const nextPath: string[] = [];
    for (let p = 0; p < prefixPath.length; p++) {
      nextPath.push(prefixPath[p]);
    }
    nextPath.push(node.value);
    const label = prefixLabel.length > 0 ? `${prefixLabel} / ${node.label}` : node.label;
    const opt = new GallerySearchPickerOption();
    opt.label = label;
    opt.value = node.value;
    opt.path = nextPath;
    out.push(opt);
    if (node.children.length > 0) {
      flattenTree(node.children, nextPath, label, out);
    }
  }
}

export function gallerySearchFlattenTree(nodes: GallerySearchFilterTreeNode[]): GallerySearchPickerOption[] {
  const out: GallerySearchPickerOption[] = [];
  flattenTree(nodes, [], '', out);
  return out;
}

function findChildNodes(nodes: GallerySearchFilterTreeNode[], value: string): GallerySearchFilterTreeNode[] {
  for (let i = 0; i < nodes.length; i++) {
    if (nodes[i].value === value) {
      return nodes[i].children;
    }
  }
  const empty: GallerySearchFilterTreeNode[] = [];
  return empty;
}

/** 沿 value 路径走到当前层的子节点列表。 */
export function gallerySearchNodesAtPath(root: GallerySearchFilterTreeNode[],
  walk: string[]): GallerySearchFilterTreeNode[] {
  let cur: GallerySearchFilterTreeNode[] = root;
  for (let i = 0; i < walk.length; i++) {
    cur = findChildNodes(cur, walk[i]);
  }
  return cur;
}

/** 沿 value 路径收集每一层展示名。 */
export function gallerySearchLabelsAtPath(root: GallerySearchFilterTreeNode[], walk: string[]): string[] {
  const labels: string[] = [];
  let cur: GallerySearchFilterTreeNode[] = root;
  for (let i = 0; i < walk.length; i++) {
    let found = false;
    for (let j = 0; j < cur.length; j++) {
      if (cur[j].value === walk[i]) {
        labels.push(cur[j].label);
        cur = cur[j].children;
        found = true;
        break;
      }
    }
    if (!found) {
      break;
    }
  }
  return labels;
}

/** 只生成当前层选项，不把子孙拍扁。 */
export function gallerySearchLevelToOptions(nodes: GallerySearchFilterTreeNode[],
  walk: string[]): GallerySearchPickerOption[] {
  const out: GallerySearchPickerOption[] = [];
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i];
    const opt = new GallerySearchPickerOption();
    opt.label = node.label;
    opt.value = node.value;
    const path: string[] = [];
    for (let p = 0; p < walk.length; p++) {
      path.push(walk[p]);
    }
    path.push(node.value);
    opt.path = path;
    opt.hasChildren = node.children.length > 0;
    out.push(opt);
  }
  return out;
}

function copyStringArray(src: string[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < src.length; i++) {
    out.push(src[i]);
  }
  return out;
}

export function gallerySearchGetApplied(): GallerySearchFilterSnapshot {
  return gallerySearchFilterClone(GallerySearchFilterStore.applied);
}

export function gallerySearchSetApplied(snapshot: GallerySearchFilterSnapshot): void {
  GallerySearchFilterStore.applied = gallerySearchFilterClone(snapshot);
}

class GallerySearchFilterStore {
  static applied: GallerySearchFilterSnapshot = new GallerySearchFilterSnapshot();
}

export function gallerySearchFilterClone(src: GallerySearchFilterSnapshot): GallerySearchFilterSnapshot {
  const out = new GallerySearchFilterSnapshot();
  out.isCollect = src.isCollect;
  out.notAlbum = src.notAlbum;
  out.notTag = src.notTag;
  out.notGeo = src.notGeo;
  out.fileType = src.fileType;
  out.fileTypeLabel = src.fileTypeLabel;
  out.personId = src.personId;
  out.personLabel = src.personLabel;
  out.personAvatar = src.personAvatar;
  out.datePath = copyStringArray(src.datePath);
  out.dateLabel = src.dateLabel;
  out.locationPath = copyStringArray(src.locationPath);
  out.locationLabel = src.locationLabel;
  out.albumPath = copyStringArray(src.albumPath);
  out.albumLabel = src.albumLabel;
  out.folderPath = copyStringArray(src.folderPath);
  out.folderLabel = src.folderLabel;
  out.showShootingInfo = src.showShootingInfo;
  out.makeModelPath = copyStringArray(src.makeModelPath);
  out.makeModelLabel = src.makeModelLabel;
  out.focalLengthPath = copyStringArray(src.focalLengthPath);
  out.focalLengthLabel = src.focalLengthLabel;
  out.exposurePath = copyStringArray(src.exposurePath);
  out.exposureLabel = src.exposureLabel;
  out.aperturePath = copyStringArray(src.aperturePath);
  out.apertureLabel = src.apertureLabel;
  out.isoPath = copyStringArray(src.isoPath);
  out.isoLabel = src.isoLabel;
  return out;
}

export function gallerySearchFilterClear(target: GallerySearchFilterSnapshot): void {
  target.isCollect = false;
  target.notAlbum = false;
  target.notTag = false;
  target.notGeo = false;
  target.fileType = '';
  target.fileTypeLabel = '';
  target.personId = '';
  target.personLabel = '';
  target.personAvatar = '';
  target.datePath = [];
  target.dateLabel = '';
  target.locationPath = [];
  target.locationLabel = '';
  target.albumPath = [];
  target.albumLabel = '';
  target.folderPath = [];
  target.folderLabel = '';
  target.showShootingInfo = false;
  target.makeModelPath = [];
  target.makeModelLabel = '';
  target.focalLengthPath = [];
  target.focalLengthLabel = '';
  target.exposurePath = [];
  target.exposureLabel = '';
  target.aperturePath = [];
  target.apertureLabel = '';
  target.isoPath = [];
  target.isoLabel = '';
}

function pathSelected(path: string[]): boolean {
  return path.length > 0 && path[0].length > 0;
}

export function gallerySearchFilterActiveCount(s: GallerySearchFilterSnapshot): number {
  let n = 0;
  if (s.isCollect) {
    n += 1;
  }
  if (s.notAlbum) {
    n += 1;
  }
  if (s.notTag) {
    n += 1;
  }
  if (s.notGeo) {
    n += 1;
  }
  if (s.fileType.length > 0) {
    n += 1;
  }
  if (s.personId.length > 0) {
    n += 1;
  }
  if (pathSelected(s.datePath)) {
    n += 1;
  }
  if (pathSelected(s.locationPath)) {
    n += 1;
  }
  if (pathSelected(s.albumPath)) {
    n += 1;
  }
  if (pathSelected(s.folderPath)) {
    n += 1;
  }
  if (s.showShootingInfo) {
    if (pathSelected(s.makeModelPath)) {
      n += 1;
    }
    if (pathSelected(s.focalLengthPath)) {
      n += 1;
    }
    if (pathSelected(s.exposurePath)) {
      n += 1;
    }
    if (pathSelected(s.aperturePath)) {
      n += 1;
    }
    if (pathSelected(s.isoPath)) {
      n += 1;
    }
  }
  return n;
}

export function gallerySearchFilterHasConstraint(s: GallerySearchFilterSnapshot): boolean {
  return gallerySearchFilterActiveCount(s) > 0;
}

export function gallerySearchFilterHasPositive(s: GallerySearchFilterSnapshot): boolean {
  if (s.isCollect || s.fileType.length > 0 || s.personId.length > 0) {
    return true;
  }
  if (pathSelected(s.datePath) || pathSelected(s.locationPath) || pathSelected(s.albumPath) ||
    pathSelected(s.folderPath)) {
    return true;
  }
  if (!s.showShootingInfo) {
    return false;
  }
  return pathSelected(s.makeModelPath) || pathSelected(s.focalLengthPath) || pathSelected(s.exposurePath) ||
    pathSelected(s.aperturePath) || pathSelected(s.isoPath);
}

/**
 * 官方 gu()：path[0] 为 filterValue，后续层 filterName 取上一层 value。
 */
function nestedFilterJson(filterName: string, path: string[]): string {
  if (path.length === 0) {
    return '';
  }
  const first = JSON.stringify(path[0]);
  if (path.length === 1) {
    return `{"filterName":${JSON.stringify(filterName)},"filterValue":${first}}`;
  }
  const rest: string[] = [];
  for (let i = 1; i < path.length; i++) {
    rest.push(path[i]);
  }
  const sub = nestedFilterJson(path[0], rest);
  return `{"filterName":${JSON.stringify(filterName)},"filterValue":${first},"subFilters":[${sub}]}`;
}

function scalarFilterJson(filterName: string, filterValue: string): string {
  return `{"filterName":${JSON.stringify(filterName)},"filterValue":${JSON.stringify(filterValue)}}`;
}

/** 正向 filters JSON 数组（不含 not_album / not_tag / not_geo） */
export function gallerySearchBuildFiltersJson(s: GallerySearchFilterSnapshot): string {
  const parts: string[] = [];
  if (s.fileType.length > 0) {
    parts.push(scalarFilterJson('file_type', s.fileType));
  }
  if (s.isCollect) {
    parts.push(scalarFilterJson('is_collect', '1'));
  }
  if (s.personId.length > 0) {
    parts.push(scalarFilterJson('person', s.personId));
  }
  if (pathSelected(s.datePath)) {
    parts.push(nestedFilterJson('photo_date', s.datePath));
  }
  if (pathSelected(s.locationPath)) {
    parts.push(nestedFilterJson('photo_location', s.locationPath));
  }
  if (pathSelected(s.albumPath)) {
    parts.push(nestedFilterJson('album_name', s.albumPath));
  }
  if (pathSelected(s.folderPath)) {
    parts.push(scalarFilterJson('file_dir', s.folderPath[s.folderPath.length - 1]));
  }
  if (s.showShootingInfo) {
    if (pathSelected(s.makeModelPath)) {
      parts.push(nestedFilterJson('make_model', s.makeModelPath));
    }
    if (pathSelected(s.focalLengthPath)) {
      parts.push(nestedFilterJson('focal_length', s.focalLengthPath));
    }
    if (pathSelected(s.exposurePath)) {
      parts.push(nestedFilterJson('exposure_time', s.exposurePath));
    }
    if (pathSelected(s.aperturePath)) {
      parts.push(nestedFilterJson('fumber', s.aperturePath));
    }
    if (pathSelected(s.isoPath)) {
      parts.push(nestedFilterJson('ISO_speed_ratings', s.isoPath));
    }
  }
  return `[${parts.join(',')}]`;
}

/** 整理勾选里的反向条件 */
export function gallerySearchBuildAntiFiltersJson(s: GallerySearchFilterSnapshot): string {
  const parts: string[] = [];
  if (s.notAlbum) {
    parts.push(scalarFilterJson('not_album', '1'));
  }
  if (s.notTag) {
    parts.push(scalarFilterJson('not_tag', '1'));
  }
  if (s.notGeo) {
    parts.push(scalarFilterJson('not_geo', '1'));
  }
  return `[${parts.join(',')}]`;
}

function personHidden(item: AiPersonItem): boolean {
  if (item.isHide === true) {
    return true;
  }
  const rec = item as Record<string, Object | string | number | boolean | undefined | null>;
  const v = rec['isHide'];
  const v2 = v !== undefined ? v : rec['is_hide'];
  const v3 = v2 !== undefined ? v2 : rec['hidden'];
  if (v3 === true || v3 === 1) {
    return true;
  }
  if (typeof v3 === 'string') {
    const t = v3.trim().toLowerCase();
    return t === '1' || t === 'true';
  }
  return false;
}

function folderPathOf(item: PhotoFolderListItem): string {
  const rec = item as Record<string, Object | string | number | boolean | undefined | null>;
  return readRawString(rec, ['folderPath', 'path', 'filePath', 'dir']);
}

function folderLabelOf(path: string): string {
  const trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  const idx = trimmed.lastIndexOf('/');
  if (idx < 0 || idx >= trimmed.length - 1) {
    return trimmed;
  }
  return trimmed.substring(idx + 1);
}

function splitPathSegs(rest: string): string[] {
  const raw = rest.split('/');
  const segs: string[] = [];
  for (let i = 0; i < raw.length; i++) {
    if (raw[i].length > 0) {
      segs.push(raw[i]);
    }
  }
  return segs;
}

/**
 * 官方用已选根目录 + filterlist.file_dir 拼文件夹树。
 * 根目录缺失时退回扁平路径列表。
 */
function buildFolderTree(filterValues: string[], roots: string[]): GallerySearchFilterTreeNode[] {
  if (roots.length === 0) {
    const flat: GallerySearchFilterTreeNode[] = [];
    for (let i = 0; i < filterValues.length; i++) {
      const node = new GallerySearchFilterTreeNode();
      node.value = filterValues[i];
      node.label = folderLabelOf(filterValues[i]);
      flat.push(node);
    }
    return flat;
  }
  const nodeMap = new Map<string, GallerySearchFilterTreeNode>();
  for (let i = 0; i < filterValues.length; i++) {
    const full = filterValues[i];
    let bestRoot = '';
    for (let r = 0; r < roots.length; r++) {
      const root = roots[r];
      if (full.startsWith(root) && root.length > bestRoot.length) {
        bestRoot = root;
      }
    }
    if (bestRoot.length === 0) {
      continue;
    }
    const segs = splitPathSegs(full.substring(bestRoot.length));
    let acc = bestRoot;
    for (let s = 0; s < segs.length; s++) {
      const parentPath = acc;
      acc = `${acc}/${segs[s]}`;
      if (nodeMap.has(acc)) {
        continue;
      }
      const node = new GallerySearchFilterTreeNode();
      node.label = segs[s];
      node.value = acc;
      nodeMap.set(acc, node);
      if (parentPath === bestRoot) {
        continue;
      }
      const parent = nodeMap.get(parentPath);
      if (parent !== undefined) {
        parent.children.push(node);
      }
    }
  }
  const out: GallerySearchFilterTreeNode[] = [];
  for (let r = 0; r < roots.length; r++) {
    const root = roots[r];
    const rootNode = new GallerySearchFilterTreeNode();
    rootNode.value = root;
    rootNode.label = folderLabelOf(root);
    const kids: GallerySearchFilterTreeNode[] = [];
    const values: GallerySearchFilterTreeNode[] = [];
    nodeMap.forEach((n: GallerySearchFilterTreeNode) => {
      values.push(n);
    });
    for (let k = 0; k < values.length; k++) {
      const n = values[k];
      if (!n.value.startsWith(root)) {
        continue;
      }
      const rest = splitPathSegs(n.value.substring(root.length));
      if (rest.length === 1) {
        kids.push(n);
      }
    }
    rootNode.children = kids;
    out.push(rootNode);
  }
  return out;
}

function fileTypeOption(item: MediaCategoryItem): GallerySearchPickerOption | undefined {
  const key = item.key !== undefined ? item.key.trim() : '';
  if (key.length === 0) {
    return undefined;
  }
  const opt = new GallerySearchPickerOption();
  opt.value = key;
  const nameCand = item.name !== undefined ? item.name : (item.title !== undefined ? item.title : item.label);
  const name = nameCand !== undefined && nameCand.length > 0 ? nameCand : key;
  opt.label = name;
  return opt;
}

export async function gallerySearchLoadCatalog(client: FnHttpClient): Promise<GallerySearchFilterCatalog> {
  const catalog = new GallerySearchFilterCatalog();
  const filterRes: FnClientResult<SearchFilterListData> = await client.getSearchFilterList(true);
  const nodes: SearchFilterListNode[] = [];
  if (filterRes.success && filterRes.data !== undefined) {
    const list = filterRes.data.list;
    if (list !== undefined) {
      for (let i = 0; i < list.length; i++) {
        nodes.push(list[i]);
      }
    }
  }
  const dateNode = findListNode(nodes, 'photo_date');
  if (dateNode !== undefined) {
    const suffixes: string[] = ['年', '月'];
    catalog.dates = treeFromFilterNode(dateNode, suffixes);
  }
  const locNode = findListNode(nodes, 'photo_location');
  if (locNode !== undefined) {
    catalog.locations = treeFromFilterNode(locNode, []);
  }
  const albumNode = findListNode(nodes, 'album_name');
  if (albumNode !== undefined) {
    catalog.albums = treeFromFilterNode(albumNode, []);
  }
  const makeNode = findListNode(nodes, 'make_model');
  if (makeNode !== undefined) {
    catalog.makeModels = treeFromFilterNode(makeNode, []);
  }
  const focalNode = findListNode(nodes, 'focal_length');
  if (focalNode !== undefined) {
    catalog.focalLengths = treeFromFilterNode(focalNode, []);
  }
  const expNode = findListNode(nodes, 'exposure_time');
  if (expNode !== undefined) {
    catalog.exposures = treeFromFilterNode(expNode, []);
  }
  const apNode = findListNode(nodes, 'fumber');
  if (apNode !== undefined) {
    catalog.apertures = treeFromFilterNode(apNode, []);
  }
  const isoNode = findListNode(nodes, 'ISO_speed_ratings');
  if (isoNode !== undefined) {
    catalog.isos = treeFromFilterNode(isoNode, []);
  }

  const catRes = await client.getMediaCategoryList();
  if (catRes.success && catRes.data !== undefined) {
    let list = catRes.data.list;
    if (list === undefined) {
      list = catRes.data.items;
    }
    if (list !== undefined) {
      for (let i = 0; i < list.length; i++) {
        const opt = fileTypeOption(list[i]);
        if (opt !== undefined) {
          catalog.fileTypes.push(opt);
        }
      }
    }
  }

  const personRes = await client.getAiPersonList(true, -1, 0);
  if (personRes.success && personRes.data !== undefined) {
    let list = personRes.data.list;
    if (list === undefined) {
      list = personRes.data.items;
    }
    if (list === undefined) {
      list = personRes.data.records;
    }
    if (list !== undefined) {
      for (let i = 0; i < list.length; i++) {
        const item = list[i];
        if (personHidden(item)) {
          continue;
        }
        const pid = personId(item);
        if (pid.length === 0) {
          continue;
        }
        const opt = new GallerySearchPickerOption();
        opt.value = pid;
        opt.label = personName(item);
        opt.avatarUrl = personFace(item);
        catalog.persons.push(opt);
      }
    }
  }

  let folderValues: string[] = [];
  const dirNode = findListNode(nodes, 'file_dir');
  if (dirNode !== undefined) {
    folderValues = nodeValues(dirNode);
  }
  const folderRes = await client.getPhotoFolderList();
  const roots: string[] = [];
  if (folderRes.success && folderRes.data !== undefined) {
    let list = folderRes.data.list;
    if (list === undefined) {
      list = folderRes.data.items;
    }
    if (list !== undefined) {
      for (let i = 0; i < list.length; i++) {
        const p = folderPathOf(list[i]);
        if (p.length > 0) {
          roots.push(p);
        }
      }
    }
  }
  catalog.folders = buildFolderTree(folderValues, roots);
  return catalog;
}
