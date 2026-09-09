import { AppSession } from '../../auth/AppSession';
import { normalizeGalleryListItem, galleryListFromData } from '../../album/GalleryListItemNormalize';
import {
  GalleryGetListData,
  GalleryListItem,
  MapPreviewAllPointData,
  MapPreviewAllPointItem,
  MapPreviewBoundaryData,
  MapPreviewCenterData,
  MapTimelineData,
  MapTimelineItem
} from '../../model/FnApiTypes';

export type MapLooseRecord = Record<string, Object | string | number | boolean | undefined | null>;

export interface PhotoMapBounds {
  north: number;
  east: number;
  south: number;
  west: number;
}

export interface PhotoMapPoint {
  key: string;
  lat: number;
  lon: number;
  count: number;
  coverRel: string;
  poster?: GalleryListItem;
  embedded: GalleryListItem[];
}

export interface PhotoMapMarker {
  key: string;
  x: number;
  y: number;
  lat: number;
  lon: number;
  count: number;
  coverRel: string;
  bounds: PhotoMapBounds;
  embedded: GalleryListItem[];
}

export interface MapFetchResult {
  items: GalleryListItem[];
  total: number;
  message: string;
}

export interface MapLatLon {
  lat: number;
  lon: number;
}

export const MAP_PAGE_LIMIT = 220;
export function mapAsRecord(value: Object | string | number | boolean | undefined | null): MapLooseRecord | null {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return null;
  }
  return value as MapLooseRecord;
}

export function mapTrimmedString(value: Object | string | number | boolean | undefined | null): string {
  if (typeof value === 'string') {
    return value.trim();
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value).trim();
  }
  return '';
}

export function mapReadString(raw: MapLooseRecord, keys: string[]): string {
  for (let i = 0; i < keys.length; i++) {
    const text = mapTrimmedString(raw[keys[i]]);
    if (text.length > 0 && text !== 'null') {
      return text;
    }
  }
  return '';
}

export function mapReadNumber(raw: MapLooseRecord, keys: string[]): number {
  for (let i = 0; i < keys.length; i++) {
    const value = raw[keys[i]];
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
    if (typeof value === 'string') {
      const n = Number(value.trim());
      if (Number.isFinite(n)) {
        return n;
      }
    }
  }
  return Number.NaN;
}

export function mapPointCount(raw: MapLooseRecord): number {
  const n = mapReadNumber(raw, ['count', 'itemCount', 'item_count', 'photoCount', 'photo_count', 'total']);
  return Number.isFinite(n) ? Math.max(1, Math.floor(n)) : 1;
}

export function mapItemsFromListData(data: GalleryGetListData | undefined): GalleryListItem[] {
  return galleryListFromData(data);
}

export function mapTimelineItemsFromData(data: MapTimelineData | undefined): MapTimelineItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  return data.list ?? data.items ?? data.records ?? data.rows ?? data.points ?? data.markers ?? data.clusters ?? [];
}

export function mapPreviewPointsFromData(data: MapPreviewAllPointData | undefined): MapPreviewAllPointItem[] {
  if (data === undefined || data === null) {
    return [];
  }
  return data.list ?? data.items ?? data.records ?? data.rows ?? data.points ?? data.markers ?? data.clusters ?? [];
}

export function mapPad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

export function mapDayRange(year: number, month: number, day: number): string[] {
  return [
    `${year}:${mapPad2(month)}:${mapPad2(day)} 00:00:00`,
    `${year}:${mapPad2(month)}:${mapPad2(day)} 23:59:59`
  ];
}

export function mapTimelineRange(item: MapTimelineItem): string[] {
  const raw = item as MapLooseRecord;
  const directStart = mapReadString(raw, ['start_time', 'startTime']);
  const directEnd = mapReadString(raw, ['end_time', 'endTime']);
  if (directStart.length > 0 && directEnd.length > 0) {
    return [directStart, directEnd];
  }
  const year = mapReadNumber(raw, ['year']);
  const month = mapReadNumber(raw, ['month']);
  const day = mapReadNumber(raw, ['day']);
  if (Number.isFinite(year) && Number.isFinite(month) && Number.isFinite(day) && day > 0) {
    return mapDayRange(Math.floor(year), Math.floor(month), Math.floor(day));
  }
  if (Number.isFinite(year) && Number.isFinite(month) && month > 0) {
    const y = Math.floor(year);
    const m = Math.floor(month);
    const last = new Date(y, m, 0).getDate();
    return [`${y}:${mapPad2(m)}:01 00:00:00`, `${y}:${mapPad2(m)}:${mapPad2(last)} 23:59:59`];
  }
  if (Number.isFinite(year)) {
    const y = Math.floor(year);
    return [`${y}:01:01 00:00:00`, `${y}:12:31 23:59:59`];
  }
  return ['', ''];
}

export function mapBoundsToParams(bounds: PhotoMapBounds): Record<string, string | number | boolean> {
  const params: Record<string, string | number | boolean> = {};
  params['north'] = bounds.north;
  params['east'] = bounds.east;
  params['south'] = bounds.south;
  params['west'] = bounds.west;
  params['lonVert'] = 0;
  params['isBlank'] = false;
  return params;
}


export function mapClampLat(value: number): number {
  return Math.max(-85, Math.min(85, value));
}

export function mapClampLon(value: number): number {
  return Math.max(-180, Math.min(180, value));
}

export function mapCenterFromData(data: MapPreviewCenterData | undefined): MapLatLon | null {
  if (data === undefined || data === null) {
    return null;
  }
  const raw = data as MapLooseRecord;
  const lat = mapReadNumber(raw, ['lat', 'latitude', 'centerLat', 'centerLatitude']);
  const lon = mapReadNumber(raw, ['lon', 'lng', 'longitude', 'centerLng', 'centerLongitude']);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    return null;
  }
  return { lat: mapClampLat(lat), lon: mapClampLon(lon) };
}

export function mapBoundsFromData(data: MapPreviewBoundaryData | undefined): PhotoMapBounds | null {
  if (data === undefined || data === null) {
    return null;
  }
  const raw = data as MapLooseRecord;
  let south = mapReadNumber(raw, ['minLat', 'south']);
  let north = mapReadNumber(raw, ['maxLat', 'north']);
  let west = mapReadNumber(raw, ['minLon', 'minLng', 'west']);
  let east = mapReadNumber(raw, ['maxLon', 'maxLng', 'east']);
  const sw = mapAsRecord(raw['southWest']);
  const ne = mapAsRecord(raw['northEast']);
  if ((!Number.isFinite(south) || !Number.isFinite(west)) && sw !== null) {
    south = mapReadNumber(sw, ['lat', 'latitude']);
    west = mapReadNumber(sw, ['lon', 'lng', 'longitude']);
  }
  if ((!Number.isFinite(north) || !Number.isFinite(east)) && ne !== null) {
    north = mapReadNumber(ne, ['lat', 'latitude']);
    east = mapReadNumber(ne, ['lon', 'lng', 'longitude']);
  }
  if (!Number.isFinite(south) || !Number.isFinite(north) ||
    !Number.isFinite(west) || !Number.isFinite(east)) {
    return null;
  }
  const out: PhotoMapBounds = {
    south: mapClampLat(Math.min(south, north)),
    north: mapClampLat(Math.max(south, north)),
    west: mapClampLon(Math.min(west, east)),
    east: mapClampLon(Math.max(west, east))
  };
  if (out.south === out.north && out.west === out.east) {
    out.south = mapClampLat(out.south - 0.05);
    out.north = mapClampLat(out.north + 0.05);
    out.west = mapClampLon(out.west - 0.05);
    out.east = mapClampLon(out.east + 0.05);
  }
  return out;
}

export function mapMergePoints(points: PhotoMapPoint[]): PhotoMapPoint[] {
  const mapByKey: Map<string, PhotoMapPoint> = new Map();
  for (let i = 0; i < points.length; i++) {
    const item = points[i];
    const key = `${item.lat.toFixed(6)},${item.lon.toFixed(6)}`;
    const old = mapByKey.get(key);
    if (old === undefined) {
      mapByKey.set(key, item);
    } else {
      old.count = Math.max(old.count, item.count);
      if (old.coverRel.length <= 0) {
        old.coverRel = item.coverRel;
      }
      if (old.embedded.length <= 0 && item.embedded.length > 0) {
        old.embedded = item.embedded;
      }
    }
  }
  return Array.from(mapByKey.values());
}

export function mapCoverFromPoster(raw: MapLooseRecord): string {
  const direct = mapReadString(raw, ['thumb', 'cover', 'poster', 'url', 'src']);
  if (direct.length > 0) {
    return direct;
  }
  const id = mapReadString(raw, ['id']);
  const uuid = mapReadString(raw, ['photoUUID', 'uuid']);
  if (id.length > 0 && uuid.length > 0) {
    return `/p/api/v1/stream/p/t/${id}/m/${uuid}`;
  }
  return '';
}

export function mapPosterToGalleryItem(item: GalleryListItem): GalleryListItem {
  return normalizeGalleryListItem(item);
}

export function mapEmbeddedPhotos(item: MapPreviewAllPointItem): GalleryListItem[] {
  const arr = item.list ?? item.items ?? item.photos ?? item.records ?? [];
  const out: GalleryListItem[] = [];
  for (let i = 0; i < arr.length; i++) {
    const one = arr[i];
    if (typeof one === 'object' && one !== null) {
      out.push(normalizeGalleryListItem(one as GalleryListItem));
    }
  }
  return out;
}

export function mapPointFromApiItem(item: MapPreviewAllPointItem): PhotoMapPoint | null {
  const raw = item as MapLooseRecord;
  const lat = mapReadNumber(raw, ['lat', 'latitude']);
  const lon = mapReadNumber(raw, ['lon', 'lng', 'longitude']);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) ||
    lat < -90 || lat > 90 || lon < -180 || lon > 180) {
    return null;
  }
  const poster = mapAsRecord(raw['poster']);
  let coverRel = mapReadString(raw, ['cover', 'posterUrl', 'thumb', 'thumbnail']);
  let posterItem: GalleryListItem | undefined = undefined;
  if (poster !== null) {
    posterItem = poster as GalleryListItem;
    if (coverRel.length <= 0) {
      coverRel = mapCoverFromPoster(poster);
    }
  }
  const embedded = mapEmbeddedPhotos(item);
  if (posterItem !== undefined && embedded.length === 0) {
    embedded.push(mapPosterToGalleryItem(posterItem));
  }
  return {
    key: `${lat.toFixed(6)},${lon.toFixed(6)}`,
    lat: lat,
    lon: lon,
    count: mapPointCount(raw),
    coverRel: coverRel,
    poster: posterItem,
    embedded: embedded
  };
}

export async function mapLoadPointsForBounds(
  bounds: PhotoMapBounds,
  existing: PhotoMapPoint[],
  append: boolean
): Promise<PhotoMapPoint[]> {
  const client = AppSession.getClient();
  if (client === null) {
    return existing;
  }
  const out: PhotoMapPoint[] = append ? existing.slice() : [];
  const latParts = Math.max(1, Math.ceil(Math.max(0.01, bounds.north - bounds.south) / 45));
  const lonParts = Math.max(1, Math.ceil(Math.max(0.01, bounds.east - bounds.west) / 60));
  for (let latIdx = 0; latIdx < latParts; latIdx++) {
    for (let lonIdx = 0; lonIdx < lonParts; lonIdx++) {
      const south = bounds.south + latIdx * 45;
      const north = Math.min(south + 45, bounds.north);
      const west = bounds.west + lonIdx * 60;
      const east = Math.min(west + 60, bounds.east);
      const res = await client.getMapPreviewAllPoint(north, east, south, west, 0, 20000);
      if (!res.success || res.data === undefined) {
        continue;
      }
      const items = mapPreviewPointsFromData(res.data);
      for (let i = 0; i < items.length; i++) {
        const point = mapPointFromApiItem(items[i]);
        if (point !== null) {
          out.push(point);
        }
      }
    }
  }
  return mapMergePoints(out);
}

export async function mapFetchMarkerPhotos(marker: PhotoMapMarker): Promise<MapFetchResult> {
  const client = AppSession.getClient();
  if (client === null) {
    return { items: [], total: 0, message: '未登录' };
  }
  const params = mapBoundsToParams(marker.bounds);
  const timeline = await client.getMapTimeline(params, 20000);
  let photos: GalleryListItem[] = [];
  if (timeline.success && timeline.data !== undefined) {
    const ranges = mapTimelineItemsFromData(timeline.data);
    for (let i = 0; i < ranges.length && photos.length < MAP_PAGE_LIMIT; i++) {
      const range = mapTimelineRange(ranges[i]);
      if (range[0].length <= 0 || range[1].length <= 0) {
        continue;
      }
      const res = await client.getMapPhotoList(
        range[0],
        range[1],
        Math.min(80, MAP_PAGE_LIMIT - photos.length),
        0,
        params,
        20000
      );
      if (res.success && res.data !== undefined) {
        photos = photos.concat(mapItemsFromListData(res.data));
      }
    }
  }
  if (photos.length === 0) {
    const direct = await client.getMapPhotoListByBounds(params, MAP_PAGE_LIMIT, 0, 20000);
    if (direct.success && direct.data !== undefined) {
      photos = mapItemsFromListData(direct.data);
    }
  }
  if (photos.length === 0 && marker.embedded.length > 0) {
    photos = marker.embedded;
  }
  const expectedTotal = Math.max(marker.count, photos.length);
  return {
    items: photos,
    total: expectedTotal,
    message: photos.length > 0 ? '' : '该位置暂无可预览媒体'
  };
}

export function mapOpenMarkerTitle(count: number): string {
  return count > 1 ? `地图位置 ${count} 项` : '地图位置';
}
