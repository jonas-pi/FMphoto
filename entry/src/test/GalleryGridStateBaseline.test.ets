import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { RecycleBinSession } from '../main/ets/pages/recycleBinPage/RecycleBinSession';
import { FolderBrowseSession } from '../main/ets/pages/folderBrowsePage/FolderBrowseSession';
import { CategoryGallerySession } from '../main/ets/pages/categoryGallery/CategoryGallerySession';

export default function galleryGridStateBaselineTest() {
  describe('galleryGridStateBaselineTest', () => {
    beforeAll(() => {});
    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    it('recycle_session_defaults_and_numeric_selected_ids', 0, () => {
      const session = new RecycleBinSession();
      expect(session.selection.selectedIds.length).assertEqual(0);
      expect(session.selection.rbSlideLastAppliedEndFlat).assertEqual(-99999);
      expect(session.selection.rbSlideAnchorFlat).assertEqual(-1);
      expect(session.overlay.rbThumbResumeTimer).assertEqual(-1);
      expect(session.overlay.choiceSheetResolver === undefined).assertTrue();
      session.selection.selectedIds.push(42);
      expect(session.selection.selectedIds[0]).assertEqual(42);
    });

    it('folder_session_defaults_and_string_selected_ids', 0, () => {
      const session = new FolderBrowseSession();
      expect(session.selection.selectedIds.length).assertEqual(0);
      expect(session.selection.fbSlideLastAppliedEndFlat).assertEqual(-99999);
      expect(session.nav.entryFloorResolved).assertTrue();
      expect(session.nav.lockToEntry).assertFalse();
      expect(session.load.loadGen).assertEqual(0);
      expect(session.load.mediaHasMore).assertFalse();
      expect(session.overlay.slideshowRequestSeq).assertEqual(0);
      expect(session.overlay.thumbResumeTimer).assertEqual(-1);
      session.selection.selectedIds.push('dir:a');
      expect(session.selection.selectedIds[0]).assertEqual('dir:a');
    });

    it('category_session_defaults_page_active_stays_false', 0, () => {
      const session = new CategoryGallerySession();
      expect(session.selection.selectedIds.length).assertEqual(0);
      expect(session.selection.cgSlideLastAppliedEndFlat).assertEqual(-99999);
      expect(session.sync.pageSessionToken).assertEqual(-1);
      expect(session.sync.cgObservedStoreVersion).assertEqual(-1);
      expect(session.sync.cgStorePollTimer).assertEqual(-1);
      expect(session.guard.cgPageActive).assertFalse();
      expect(session.guard.handledDeleteSyncVersion).assertEqual(0);
      expect(session.overlay.cgThumbResumeTimer).assertEqual(-1);
      session.selection.selectedIds.push('p1');
      expect(session.selection.selectedIds[0]).assertEqual('p1');
    });
  });
}
