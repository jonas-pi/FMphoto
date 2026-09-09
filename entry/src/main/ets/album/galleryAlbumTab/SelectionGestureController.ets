import { GalleryListItem } from '../../model/FnApiTypes';
import { GalleryFlowNode } from '../GalleryFlowDataSource';
import { GalleryFingerWindowPoint } from './GalleryAlbumTabTypes';
import { SelectionGestureControllerHost } from './SelectionGestureHost';
import {
  selectionApplyGallerySlideRowRangeSelection as applyGallerySlideRowRangeSelectionImpl,
  selectionBeginGallerySlideSelectGesture as beginGallerySlideSelectGestureImpl,
  selectionBeginGallerySlideSelectGestureAtWindowPx as beginGallerySlideSelectGestureAtWindowPxImpl,
  selectionEndGallerySlideSelectGesture as endGallerySlideSelectGestureImpl,
  selectionHitGalleryThumbDomPx as hitGalleryThumbDomPxImpl,
  selectionIsGalleryIdSelected as isGalleryIdSelectedImpl,
  selectionOnGallerySlidePanUpdate as onGallerySlidePanUpdateImpl,
  selectionOnGallerySlideTouchMoveWindow as onGallerySlideTouchMoveWindowImpl,
  selectionOnGalleryThumbLongPress as onGalleryThumbLongPressImpl,
  selectionOnGalleryThumbTap as onGalleryThumbTapImpl,
  selectionOnSearchThumbTap as onSearchThumbTapImpl,
  selectionPanOffsetVpToPx as panOffsetVpToPxImpl,
  selectionPickGalleryThumbFlatForRowOrCache as pickGalleryThumbFlatForRowOrCacheImpl,
  selectionPickGalleryThumbFlatUnderPoint as pickGalleryThumbFlatUnderPointImpl,
  selectionPickGalleryThumbFlatUnderPointForSlide as pickGalleryThumbFlatUnderPointForSlideImpl,
  selectionReadGestureFingerWindow as readGestureFingerWindowImpl,
  selectionResolveSlidePointerWindowPx as resolveSlidePointerWindowPxImpl,
  selectionToggleGallerySelectedId as toggleGallerySelectedIdImpl
} from './SelectionGestureMainFlow';
import {
  selectionHitSearchThumbDomPx as hitSearchThumbDomPxImpl,
  selectionPickSearchThumbFlatForRow as pickSearchThumbFlatForRowImpl,
  selectionPickSearchThumbFlatUnderPoint as pickSearchThumbFlatUnderPointImpl,
  selectionRecordSearchThumbRect as recordSearchThumbRectImpl,
  selectionSearchThumbDomId as searchThumbDomIdImpl
} from './SelectionGestureSearchGrid';

export { SelectionGestureControllerHost };

export function selectionReadGestureFingerWindow(
  host: SelectionGestureControllerHost,
  ev: GestureEvent
): GalleryFingerWindowPoint | null {
  return readGestureFingerWindowImpl(host, ev);
}

export function selectionPanOffsetVpToPx(
  host: SelectionGestureControllerHost,
  offsetVp: number
): number {
  return panOffsetVpToPxImpl(host, offsetVp);
}

export function selectionBeginGallerySlideSelectGesture(
  host: SelectionGestureControllerHost,
  ev: GestureEvent,
  item: GalleryListItem,
  anchorFlat: number
): void {
  beginGallerySlideSelectGestureImpl(host, ev, item, anchorFlat);
}

export function selectionBeginGallerySlideSelectGestureAtWindowPx(
  host: SelectionGestureControllerHost,
  item: GalleryListItem,
  anchorFlat: number,
  xPx: number,
  yPx: number
): void {
  beginGallerySlideSelectGestureAtWindowPxImpl(host, item, anchorFlat, xPx, yPx);
}

export function selectionEndGallerySlideSelectGesture(host: SelectionGestureControllerHost): void {
  endGallerySlideSelectGestureImpl(host);
}

export function selectionResolveSlidePointerWindowPx(
  host: SelectionGestureControllerHost,
  ev: GestureEvent
): GalleryFingerWindowPoint | null {
  return resolveSlidePointerWindowPxImpl(host, ev);
}

export function selectionHitGalleryThumbDomPx(
  host: SelectionGestureControllerHost,
  photoId: string,
  xPx: number,
  yPx: number
): boolean {
  return hitGalleryThumbDomPxImpl(host, photoId, xPx, yPx);
}

export function selectionPickGalleryThumbFlatUnderPoint(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): number {
  return pickGalleryThumbFlatUnderPointImpl(host, xPx, yPx);
}

export function selectionPickGalleryThumbFlatUnderPointForSlide(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): number {
  return pickGalleryThumbFlatUnderPointForSlideImpl(host, xPx, yPx);
}

export function selectionPickGalleryThumbFlatForRowOrCache(
  host: SelectionGestureControllerHost,
  node: GalleryFlowNode,
  xPx: number,
  yPx: number
): number {
  return pickGalleryThumbFlatForRowOrCacheImpl(host, node, xPx, yPx);
}

export function selectionSearchThumbDomId(
  host: SelectionGestureControllerHost,
  flatIdx: number
): string {
  return searchThumbDomIdImpl(host, flatIdx);
}

export function selectionRecordSearchThumbRect(
  host: SelectionGestureControllerHost,
  flatIdx: number
): void {
  recordSearchThumbRectImpl(host, flatIdx);
}

export function selectionHitSearchThumbDomPx(
  host: SelectionGestureControllerHost,
  flatIdx: number,
  xPx: number,
  yPx: number
): boolean {
  return hitSearchThumbDomPxImpl(host, flatIdx, xPx, yPx);
}

export function selectionPickSearchThumbFlatUnderPoint(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): number {
  return pickSearchThumbFlatUnderPointImpl(host, xPx, yPx);
}

export function selectionPickSearchThumbFlatForRow(
  host: SelectionGestureControllerHost,
  rowStart: number,
  xPx: number,
  yPx: number
): number {
  return pickSearchThumbFlatForRowImpl(host, rowStart, xPx, yPx);
}

export function selectionApplyGallerySlideRowRangeSelection(
  host: SelectionGestureControllerHost,
  endFlat: number
): void {
  applyGallerySlideRowRangeSelectionImpl(host, endFlat);
}

export function selectionOnGallerySlidePanUpdate(
  host: SelectionGestureControllerHost,
  ev: GestureEvent
): void {
  onGallerySlidePanUpdateImpl(host, ev);
}

export function selectionOnGallerySlideTouchMoveWindow(
  host: SelectionGestureControllerHost,
  xPx: number,
  yPx: number
): void {
  onGallerySlideTouchMoveWindowImpl(host, xPx, yPx);
}

export function selectionIsGalleryIdSelected(
  host: SelectionGestureControllerHost,
  id: string
): boolean {
  return isGalleryIdSelectedImpl(host, id);
}

export function selectionToggleGallerySelectedId(
  host: SelectionGestureControllerHost,
  id: string
): void {
  toggleGallerySelectedIdImpl(host, id);
}

export function selectionOnGalleryThumbLongPress(
  host: SelectionGestureControllerHost,
  item: GalleryListItem
): void {
  onGalleryThumbLongPressImpl(host, item);
}

export function selectionOnGalleryThumbTap(
  host: SelectionGestureControllerHost,
  item: GalleryListItem,
  flatIndex: number
): void {
  onGalleryThumbTapImpl(host, item, flatIndex);
}

export function selectionOnSearchThumbTap(
  host: SelectionGestureControllerHost,
  item: GalleryListItem,
  flatIndex: number
): void {
  onSearchThumbTapImpl(host, item, flatIndex);
}
