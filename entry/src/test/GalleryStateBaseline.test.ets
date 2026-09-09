import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import {
  galleryAlbumSelectedCount,
  hasGalleryAlbumSubMode,
  isGalleryAlbumMainMode,
  shouldShowGalleryAlbumTimelineSidebar,
  timelineScrubExpandedChrome,
  timelineScrubScrollRailOnly,
  GalleryAlbumDaySectionModel
} from '../main/ets/album/galleryAlbumTab/GalleryAlbumState';
import {
  galleryAlbumBuildRowNodeKey,
  galleryAlbumGalleryFlowLazyKey
} from '../main/ets/album/galleryAlbumTab/GalleryAlbumFlowLogic';
import { GalleryViewGranularity } from '../main/ets/album/galleryAlbumTab/GalleryAlbumGranularity';
import {
  galleryAlbumMapStringNumToArrays,
  galleryAlbumSerializeTimelineCache
} from '../main/ets/album/galleryAlbumTab/GalleryAlbumCacheSnapshot';
import { GalleryFlowNode } from '../main/ets/album/GalleryFlowDataSource';
import { PreviewItemsDataSource } from '../main/ets/pages/galleryPreview/GalleryPreviewDataSource';
import {
  GalleryPreviewDetailsVisibleEffect,
  galleryPreviewCollectSyncShouldApply,
  galleryPreviewDetailsVisibleSideEffects,
  galleryPreviewIndexAfterDelete
} from '../main/ets/pages/galleryPreview/GalleryPreviewActions';
import { galleryPreviewShouldPauseSlideshowFlags } from '../main/ets/pages/galleryPreview/GalleryPreviewSlideshowRuntime';
import {
  GalleryAlbumLoadRuntime,
  GalleryAlbumModeRuntime,
  GalleryAlbumRootSurfaceRuntime,
  GalleryAlbumSelectionRuntime,
  GalleryAlbumTimelineGestureRuntime,
  GalleryAlbumVisibleRuntime
} from '../main/ets/album/galleryAlbumTab/GalleryAlbumSession';
import { GalleryPreviewSession } from '../main/ets/pages/galleryPreview/GalleryPreviewSession';

export default function galleryStateBaselineTest() {
  describe('galleryStateBaselineTest', () => {
    beforeAll(() => {});
    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    it('isGalleryAlbumMainMode_all_flags_off', 0, () => {
      expect(isGalleryAlbumMainMode({
        inSearchMode: false,
        inCategoryMode: false,
        inSmartCategoryMode: false,
        inPersonMode: false
      })).assertTrue();
      expect(hasGalleryAlbumSubMode({
        inSearchMode: false,
        inCategoryMode: false,
        inSmartCategoryMode: false,
        inPersonMode: false
      })).assertFalse();
    });

    it('isGalleryAlbumMainMode_any_submode_off_main', 0, () => {
      expect(isGalleryAlbumMainMode({
        inSearchMode: true,
        inCategoryMode: false,
        inSmartCategoryMode: false,
        inPersonMode: false
      })).assertFalse();
      expect(isGalleryAlbumMainMode({
        inSearchMode: false,
        inCategoryMode: true,
        inSmartCategoryMode: false,
        inPersonMode: false
      })).assertFalse();
      expect(isGalleryAlbumMainMode({
        inSearchMode: false,
        inCategoryMode: false,
        inSmartCategoryMode: true,
        inPersonMode: false
      })).assertFalse();
      expect(isGalleryAlbumMainMode({
        inSearchMode: false,
        inCategoryMode: false,
        inSmartCategoryMode: false,
        inPersonMode: true
      })).assertFalse();
    });

    it('galleryAlbumSelectedCount_reads_ids_length', 0, () => {
      expect(galleryAlbumSelectedCount({
        gallerySelectionMode: true,
        gallerySelectedIds: ['a', 'b', 'c']
      })).assertEqual(3);
      expect(galleryAlbumSelectedCount({
        gallerySelectionMode: false,
        gallerySelectedIds: []
      })).assertEqual(0);
    });

    it('timeline_chrome_selectors', 0, () => {
      expect(timelineScrubExpandedChrome({
        timelineSidebarDragging: true,
        timelineLongPressExpanded: false,
        timelineBarVisible: false
      })).assertTrue();
      expect(timelineScrubExpandedChrome({
        timelineSidebarDragging: false,
        timelineLongPressExpanded: true,
        timelineBarVisible: true
      })).assertTrue();
      expect(timelineScrubScrollRailOnly({
        timelineSidebarDragging: false,
        timelineLongPressExpanded: false,
        timelineBarVisible: true
      })).assertTrue();
      expect(timelineScrubScrollRailOnly({
        timelineSidebarDragging: true,
        timelineLongPressExpanded: false,
        timelineBarVisible: true
      })).assertFalse();
      expect(shouldShowGalleryAlbumTimelineSidebar(1, 0)).assertTrue();
      expect(shouldShowGalleryAlbumTimelineSidebar(0, 2)).assertTrue();
      expect(shouldShowGalleryAlbumTimelineSidebar(0, 0)).assertFalse();
    });

    it('galleryAlbumBuildRowNodeKey_slot_signature', 0, () => {
      const loaded: GalleryListItem = { id: 'p1' };
      const key = galleryAlbumBuildRowNodeKey(
        GalleryViewGranularity.DAY,
        2026,
        9,
        8,
        0,
        3,
        [loaded, null, loaded]
      );
      expect(key).assertEqual('r_0_2026_9_8_row_0_c3_sidp1xsk1xidp1');
    });

    it('galleryAlbumGalleryFlowLazyKey_returns_node_key', 0, () => {
      const node = new GalleryFlowNode();
      node.key = 'm_0_2026_9_od_0';
      expect(galleryAlbumGalleryFlowLazyKey(node)).assertEqual('m_0_2026_9_od_0');
    });

    it('timeline_cache_snapshot_serializes_sparse_slots_and_maps', 0, () => {
      const section = new GalleryAlbumDaySectionModel();
      section.year = 2026;
      section.month = 9;
      section.day = 8;
      section.itemCount = 4;
      section.nextOffset = 2;
      section.slotByOffset.set(1, { id: 'b' });
      section.slotByOffset.set(0, { id: 'a' });
      const offsets = new Map<string, number>();
      offsets.set('2026-9-8', 2);
      const rounds = new Map<string, number>();
      rounds.set('2026-9-8', 1);
      const emptyRounds = new Map<string, number>();
      const snap = galleryAlbumSerializeTimelineCache({
        orderedDays: [{ year: 2026, month: 9, day: 8, itemCount: 4 }],
        sections: [section],
        dayOffsets: offsets,
        dayRounds: rounds,
        dayEmptyRounds: emptyRounds,
        dayIndex: 0,
        exhausted: false,
        footText: '',
        refreshVersionAtSave: 7
      });
      expect(snap.orderedDays.length).assertEqual(1);
      expect(snap.sections.length).assertEqual(1);
      const plain = snap.sections[0];
      const offs = plain.slotOffsets;
      const items = plain.slotItems;
      expect(offs !== undefined).assertTrue();
      expect(items !== undefined).assertTrue();
      if (offs !== undefined && items !== undefined) {
        expect(offs.length).assertEqual(2);
        expect(offs[0]).assertEqual(0);
        expect(offs[1]).assertEqual(1);
        expect(items[0].id).assertEqual('a');
        expect(items[1].id).assertEqual('b');
      }
      expect(snap.dayOffsetsKeys[0]).assertEqual('2026-9-8');
      expect(snap.dayOffsetsVals[0]).assertEqual(2);
      expect(snap.dayRoundsVals[0]).assertEqual(1);
      expect(snap.dayEmptyKeys.length).assertEqual(0);
      expect(snap.dayIndex).assertEqual(0);
      expect(snap.exhausted).assertFalse();
      expect(snap.refreshVersionAtSave).assertEqual(7);
      const mapped = galleryAlbumMapStringNumToArrays(offsets);
      expect(mapped.keys[0]).assertEqual('2026-9-8');
      expect(mapped.vals[0]).assertEqual(2);
    });

    it('preview_appendItems_notifies_onDataAdd_not_reload', 0, () => {
      const source = new PreviewItemsDataSource();
      const first: GalleryListItem = { id: '1' };
      const second: GalleryListItem = { id: '2' };
      source.reloadAll([first]);
      let reloadCount = 0;
      let addCount = 0;
      const added: number[] = [];
      source.registerDataChangeListener({
        onDataReloaded(): void {
          reloadCount++;
        },
        onDataAdd(index: number): void {
          addCount++;
          added.push(index);
        }
      });
      source.appendItems([second]);
      expect(source.totalCount()).assertEqual(2);
      expect(addCount).assertEqual(1);
      expect(added[0]).assertEqual(1);
      expect(reloadCount).assertEqual(0);
    });

    it('preview_appendItems_empty_is_noop', 0, () => {
      const source = new PreviewItemsDataSource();
      let reloadCount = 0;
      let addCount = 0;
      source.registerDataChangeListener({
        onDataReloaded(): void {
          reloadCount++;
        },
        onDataAdd(_index: number): void {
          addCount++;
        }
      });
      source.appendItems([]);
      expect(source.totalCount()).assertEqual(0);
      expect(addCount).assertEqual(0);
      expect(reloadCount).assertEqual(0);
    });

    it('preview_reloadAll_notifies_onDataReloaded', 0, () => {
      const source = new PreviewItemsDataSource();
      let reloadCount = 0;
      source.registerDataChangeListener({
        onDataReloaded(): void {
          reloadCount++;
        }
      });
      source.reloadAll([{ id: '1' }, { id: '2' }]);
      expect(source.totalCount()).assertEqual(2);
      expect(reloadCount).assertEqual(1);
    });

    it('preview_collect_sync_stale_guard', 0, () => {
      expect(galleryPreviewCollectSyncShouldApply(3, 3, 'p1', 'p1')).assertTrue();
      expect(galleryPreviewCollectSyncShouldApply(3, 4, 'p1', 'p1')).assertFalse();
      expect(galleryPreviewCollectSyncShouldApply(3, 3, 'p1', 'p2')).assertFalse();
    });

    it('preview_index_after_delete', 0, () => {
      expect(galleryPreviewIndexAfterDelete(2, 0)).assertEqual(-1);
      expect(galleryPreviewIndexAfterDelete(0, 2)).assertEqual(0);
      expect(galleryPreviewIndexAfterDelete(2, 2)).assertEqual(1);
      expect(galleryPreviewIndexAfterDelete(1, 2)).assertEqual(1);
    });

    it('preview_details_visible_side_effects', 0, () => {
      expect(galleryPreviewDetailsVisibleSideEffects(false, true, true))
        .assertEqual(GalleryPreviewDetailsVisibleEffect.PAUSE);
      expect(galleryPreviewDetailsVisibleSideEffects(true, false, true))
        .assertEqual(GalleryPreviewDetailsVisibleEffect.RESUME);
      expect(galleryPreviewDetailsVisibleSideEffects(false, true, false))
        .assertEqual(GalleryPreviewDetailsVisibleEffect.NONE);
      expect(galleryPreviewDetailsVisibleSideEffects(true, true, true))
        .assertEqual(GalleryPreviewDetailsVisibleEffect.NONE);
    });

    it('preview_slideshow_pause_flags', 0, () => {
      expect(galleryPreviewShouldPauseSlideshowFlags(false, false, false, false, false, false)).assertFalse();
      expect(galleryPreviewShouldPauseSlideshowFlags(true, false, false, false, false, false)).assertTrue();
      expect(galleryPreviewShouldPauseSlideshowFlags(false, true, false, false, false, false)).assertTrue();
      expect(galleryPreviewShouldPauseSlideshowFlags(false, false, true, false, false, false)).assertTrue();
      expect(galleryPreviewShouldPauseSlideshowFlags(false, false, false, true, false, false)).assertTrue();
      expect(galleryPreviewShouldPauseSlideshowFlags(false, false, false, false, true, false)).assertTrue();
      expect(galleryPreviewShouldPauseSlideshowFlags(false, false, false, false, false, true)).assertTrue();
    });

    it('album_session_runtime_defaults', 0, () => {
      const mode = new GalleryAlbumModeRuntime();
      const selection = new GalleryAlbumSelectionRuntime();
      const visible = new GalleryAlbumVisibleRuntime();
      const timeline = new GalleryAlbumTimelineGestureRuntime();
      const load = new GalleryAlbumLoadRuntime();
      const root = new GalleryAlbumRootSurfaceRuntime();
      expect(mode.searchQuery).assertEqual('');
      expect(selection.gallerySelectedIds.length).assertEqual(0);
      expect(selection.gallerySlideLastAppliedEndFlat).assertEqual(-99999);
      expect(visible.visiblePhotoBufferSlots).assertEqual(12);
      expect(visible.lastScrollDebugState).assertEqual('init');
      expect(timeline.timelineSeekAnchorNodeIdx).assertEqual(-1);
      expect(load.galleryTimelineAtTopForPull).assertTrue();
      expect(load.bootstrapDebounceTimer).assertEqual(-1);
      expect(root.lastHomeSurface).assertEqual('photos');
      expect(root.rootSurfaceSwitchTimer).assertEqual(-1);
    });

    it('preview_session_runtime_defaults', 0, () => {
      const session = new GalleryPreviewSession();
      expect(session.slideshow.slideshowEnabled).assertFalse();
      expect(session.slideshow.slideshowIntervalMs).assertEqual(5000);
      expect(session.slideshow.slideshowTimerId).assertEqual(-1);
      expect(session.slideshow.lastLoggedSlideshowGlobal).assertEqual(-1);
      expect(session.collectSyncGen).assertEqual(0);
      expect(session.overlay.choiceSheetResolver === undefined).assertTrue();
    });
  });
}
