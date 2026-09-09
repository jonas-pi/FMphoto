import {
  MAP_PAGE_LIMIT,
  PhotoMapBounds,
  PhotoMapMarker,
  PhotoMapPoint,
  mapClampLat,
  mapClampLon
} from './MapPageData';

export const MAP_MARKER_GRID_VP = 92;
export const MAP_MARKER_SIZE_VP = 62;
export const MAP_MIN_VP_PER_DEGREE = 1.2;
export const MAP_MAX_VP_PER_DEGREE = 6400;
export const MAP_DEFAULT_WIDTH_VP = 360;
export const MAP_DEFAULT_HEIGHT_VP = 720;
export const MAP_GRID_LINE_SLOTS: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
export const MAP_GRID_STEPS: number[] = [
  0.001, 0.002, 0.005,
  0.01, 0.02, 0.05,
  0.1, 0.2, 0.5,
  1, 2, 5,
  10, 20, 30,
  45, 90
];

export function mapClampScale(value: number): number {
  return Math.max(MAP_MIN_VP_PER_DEGREE, Math.min(MAP_MAX_VP_PER_DEGREE, value));
}

export function mapScreenX(lon: number, viewWidthVp: number, centerLon: number, vpPerDegree: number): number {
  return viewWidthVp / 2 + (lon - centerLon) * vpPerDegree;
}

export function mapScreenY(lat: number, viewHeightVp: number, centerLat: number, vpPerDegree: number): number {
  return viewHeightVp / 2 + (centerLat - lat) * vpPerDegree;
}

export function mapVisibleBounds(
  viewWidthVp: number,
  viewHeightVp: number,
  centerLat: number,
  centerLon: number,
  vpPerDegree: number
): PhotoMapBounds {
  const halfLon = Math.max(0.05, viewWidthVp / Math.max(MAP_MIN_VP_PER_DEGREE, vpPerDegree) / 2);
  const halfLat = Math.max(0.05, viewHeightVp / Math.max(MAP_MIN_VP_PER_DEGREE, vpPerDegree) / 2);
  return {
    north: mapClampLat(centerLat + halfLat),
    south: mapClampLat(centerLat - halfLat),
    east: mapClampLon(centerLon + halfLon),
    west: mapClampLon(centerLon - halfLon)
  };
}

export interface MapFitBoundsResult {
  centerLat: number;
  centerLon: number;
  vpPerDegree: number;
}

export function mapFitBounds(
  bounds: PhotoMapBounds,
  viewWidthVp: number,
  viewHeightVp: number
): MapFitBoundsResult {
  const lonSpan = Math.max(0.05, bounds.east - bounds.west);
  const latSpan = Math.max(0.05, bounds.north - bounds.south);
  const usableW = Math.max(180, viewWidthVp - 80);
  const usableH = Math.max(220, viewHeightVp - 210);
  return {
    centerLat: mapClampLat((bounds.north + bounds.south) / 2),
    centerLon: mapClampLon((bounds.east + bounds.west) / 2),
    vpPerDegree: mapClampScale(Math.min(usableW / lonSpan, usableH / latSpan))
  };
}

export function mapUpdateMarkerProjection(
  points: PhotoMapPoint[],
  viewWidthVp: number,
  viewHeightVp: number,
  centerLat: number,
  centerLon: number,
  vpPerDegree: number
): PhotoMapMarker[] {
  if (points.length === 0 || viewWidthVp <= 1 || viewHeightVp <= 1) {
    return [];
  }
  const buckets: Map<string, PhotoMapMarker> = new Map();
  const margin = MAP_MARKER_SIZE_VP * 2;
  for (let i = 0; i < points.length; i++) {
    const point = points[i];
    const x = mapScreenX(point.lon, viewWidthVp, centerLon, vpPerDegree);
    const y = mapScreenY(point.lat, viewHeightVp, centerLat, vpPerDegree);
    if (x < -margin || x > viewWidthVp + margin || y < -margin || y > viewHeightVp + margin) {
      continue;
    }
    const bx = Math.floor(x / MAP_MARKER_GRID_VP);
    const by = Math.floor(y / MAP_MARKER_GRID_VP);
    const key = `${bx}_${by}`;
    let marker = buckets.get(key);
    if (marker === undefined) {
      marker = {
        key: key,
        x: x - MAP_MARKER_SIZE_VP / 2,
        y: y - MAP_MARKER_SIZE_VP / 2,
        lat: point.lat,
        lon: point.lon,
        count: point.count,
        coverRel: point.coverRel,
        bounds: { north: point.lat, east: point.lon, south: point.lat, west: point.lon },
        embedded: point.embedded
      };
      buckets.set(key, marker);
    } else {
      marker.count += point.count;
      marker.lat = (marker.lat + point.lat) / 2;
      marker.lon = (marker.lon + point.lon) / 2;
      marker.bounds.north = Math.max(marker.bounds.north, point.lat);
      marker.bounds.south = Math.min(marker.bounds.south, point.lat);
      marker.bounds.east = Math.max(marker.bounds.east, point.lon);
      marker.bounds.west = Math.min(marker.bounds.west, point.lon);
      marker.x = mapScreenX(marker.lon, viewWidthVp, centerLon, vpPerDegree) - MAP_MARKER_SIZE_VP / 2;
      marker.y = mapScreenY(marker.lat, viewHeightVp, centerLat, vpPerDegree) - MAP_MARKER_SIZE_VP / 2;
      if (marker.coverRel.length <= 0) {
        marker.coverRel = point.coverRel;
      }
      if (marker.embedded.length < MAP_PAGE_LIMIT && point.embedded.length > 0) {
        marker.embedded = marker.embedded.concat(point.embedded);
      }
    }
  }
  return Array.from(buckets.values());
}

export function mapGridStepDegrees(vpPerDegree: number): number {
  const target = 110 / Math.max(MAP_MIN_VP_PER_DEGREE, vpPerDegree);
  for (let i = 0; i < MAP_GRID_STEPS.length; i++) {
    if (MAP_GRID_STEPS[i] >= target) {
      return MAP_GRID_STEPS[i];
    }
  }
  return 180;
}

export function mapGridLongitude(
  slot: number,
  centerLon: number,
  viewWidthVp: number,
  vpPerDegree: number
): number {
  const step = mapGridStepDegrees(vpPerDegree);
  const leftLon = centerLon - viewWidthVp / 2 / Math.max(MAP_MIN_VP_PER_DEGREE, vpPerDegree);
  return Math.floor(leftLon / step) * step + slot * step;
}

export function mapGridLatitude(
  slot: number,
  centerLat: number,
  viewHeightVp: number,
  vpPerDegree: number
): number {
  const step = mapGridStepDegrees(vpPerDegree);
  const topLat = centerLat + viewHeightVp / 2 / Math.max(MAP_MIN_VP_PER_DEGREE, vpPerDegree);
  return Math.floor(topLat / step) * step - slot * step;
}

export function mapFormatCoord(value: number, lat: boolean): string {
  const abs = Math.abs(value);
  const suffix = lat ? (value >= 0 ? 'N' : 'S') : (value >= 0 ? 'E' : 'W');
  if (abs >= 10) {
    return `${abs.toFixed(0)}°${suffix}`;
  }
  if (abs >= 1) {
    return `${abs.toFixed(1)}°${suffix}`;
  }
  return `${abs.toFixed(2)}°${suffix}`;
}
