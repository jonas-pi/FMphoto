import localUnitTest from './LocalUnit.test';
import galleryStateBaselineTest from './GalleryStateBaseline.test';
import galleryGridStateBaselineTest from './GalleryGridStateBaseline.test';

export default function testsuite() {
  localUnitTest();
  galleryStateBaselineTest();
  galleryGridStateBaselineTest();
}