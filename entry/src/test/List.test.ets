import localUnitTest from './LocalUnit.test';
import galleryStateBaselineTest from './GalleryStateBaseline.test';

export default function testsuite() {
  localUnitTest();
  galleryStateBaselineTest();
}