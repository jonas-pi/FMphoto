import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { fnWebViewBaseUrl, normalizeServerUrl } from '../main/ets/network/ServerUrl';
import { isUnusableIpv6Host } from '../main/ets/network/FnConnectApi';
import {
  buildNasDedupeIndex,
  nasDedupeIndexHasLocal,
  nasDedupeIndexMatchKind,
  nasDedupeMatchIsStrong,
  officialSizeMtimeSetHas
} from '../main/ets/album/GalleryAutoSyncOfficialFingerprint';
import { smartCategoryCount } from '../main/ets/album/GalleryAlbumEntityData';
import { smartCategoryPatchCountByName } from '../main/ets/album/SmartCategoryLayoutPreferences';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      let a = 'abc';
      let b = 'b';
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });

    it('normalizeServerUrl_default_ports', 0, () => {
      expect(normalizeServerUrl('192.168.1.2', true)).assertEqual('https://192.168.1.2:5667');
      expect(normalizeServerUrl('192.168.1.2', false)).assertEqual('http://192.168.1.2:5666');
      expect(normalizeServerUrl('nas.local', true)).assertEqual('https://nas.local:443');
      expect(normalizeServerUrl('nas.local', false)).assertEqual('http://nas.local:80');
      expect(normalizeServerUrl('https://nas.local/', false)).assertEqual('https://nas.local:443');
      expect(normalizeServerUrl('http://nas.local', true)).assertEqual('http://nas.local:80');
    });

    it('normalizeServerUrl_ipv6', 0, () => {
      expect(normalizeServerUrl('fe80::1', false)).assertEqual('http://[fe80::1]:5666');
      expect(normalizeServerUrl('[fe80::1]', true)).assertEqual('https://[fe80::1]:5667');
      expect(normalizeServerUrl('fe80::1:8080', false)).assertEqual('http://[fe80::1]:8080');
      expect(normalizeServerUrl('http://[::1]/', false)).assertEqual('http://[::1]:5666');
    });

    it('fnConnect_skips_unusable_ipv6', 0, () => {
      expect(isUnusableIpv6Host('fe80::1')).assertTrue();
      expect(isUnusableIpv6Host('[fe80::abcd:1]')).assertTrue();
      expect(isUnusableIpv6Host('::1')).assertTrue();
      expect(isUnusableIpv6Host('ff02::1')).assertTrue();
      expect(isUnusableIpv6Host('fd12:3456::1')).assertFalse();
      expect(isUnusableIpv6Host('240e:388:9c06:c500::1')).assertFalse();
    });

    it('autoSync_sizeMtime_matches_without_name', 0, () => {
      const index = {
        fingerprints: new Set<string>(),
        sizeMtimeKeys: new Set<string>(['2048:1000']),
        nameSizeKeys: new Set<string>()
      };
      expect(nasDedupeIndexHasLocal(index, 'renamed.jpg', 2048, 1000)).assertTrue();
      expect(nasDedupeIndexHasLocal(index, 'renamed.jpg', 2048, 1002)).assertTrue();
      expect(nasDedupeIndexHasLocal(index, 'renamed.jpg', 2048, 1003)).assertFalse();
      expect(nasDedupeIndexMatchKind(index, 'renamed.jpg', 2048, 1000)).assertEqual('sizeMtime');
      expect(nasDedupeMatchIsStrong(nasDedupeIndexMatchKind(index, 'renamed.jpg', 2048, 1000))).assertFalse();
    });

    it('autoSync_strong_match_fingerprint_and_nameSize', 0, () => {
      const index = {
        fingerprints: new Set<string>(['IMG_0001.jpg:2048:1000']),
        sizeMtimeKeys: new Set<string>(),
        nameSizeKeys: new Set<string>(['shot.png:4096'])
      };
      expect(nasDedupeIndexMatchKind(index, 'IMG_0001.jpg', 2048, 1000)).assertEqual('fingerprint');
      expect(nasDedupeMatchIsStrong(nasDedupeIndexMatchKind(index, 'IMG_0001.jpg', 2048, 1000))).assertTrue();
      expect(nasDedupeIndexMatchKind(index, 'shot.png', 4096, 0)).assertEqual('nameSize');
      expect(nasDedupeMatchIsStrong(nasDedupeIndexMatchKind(index, 'shot.png', 4096, 0))).assertTrue();
    });

    it('autoSync_sizeMtime_rejects_invalid_values', 0, () => {
      const keys = new Set<string>(['2048:1000']);
      expect(officialSizeMtimeSetHas(keys, 0, 1000)).assertFalse();
      expect(officialSizeMtimeSetHas(keys, 2048, 0)).assertFalse();
    });

    it('autoSync_index_collects_sizeMtime', 0, () => {
      const item = {
        fileName: 'IMG_0001.jpg',
        fileSize: 2048,
        fileCreateTime: 1000
      };
      const index = buildNasDedupeIndex([item]);
      expect(index.sizeMtimeKeys.has('2048:1000')).assertTrue();
    });

    it('smartCategoryCount_reads_official_itemCount', 0, () => {
      expect(smartCategoryCount({ name: '猫', itemCount: 276 })).assertEqual(276);
      expect(smartCategoryCount({ name: '跳舞', itemCount: 106 })).assertEqual(106);
      expect(smartCategoryCount({ name: '证件', count: 12 })).assertEqual(12);
      expect(smartCategoryCount({ name: '空' })).assertEqual(0);
    });

    it('smartCategoryPatchCountByName_updates_matching_item', 0, () => {
      const patched = smartCategoryPatchCountByName(
        [{ name: '猫', itemCount: 1 }, { name: '狗', itemCount: 8 }],
        '猫',
        276
      );
      expect(smartCategoryCount(patched[0])).assertEqual(276);
      expect(smartCategoryCount(patched[1])).assertEqual(8);
    });

    it('fnWebViewBaseUrl_preserves_domain_https_port', 0, () => {
      expect(fnWebViewBaseUrl('https://nas.local:443')).assertEqual('https://nas.local:443');
      expect(fnWebViewBaseUrl('https://nas.local:8443')).assertEqual('https://nas.local:8443');
      expect(fnWebViewBaseUrl('http://192.168.1.2:5666')).assertEqual('https://192.168.1.2:5667');
    });
  });
}
