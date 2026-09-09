import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { fnWebViewBaseUrl, normalizeServerUrl } from '../main/ets/network/ServerUrl';
import { isUnusableIpv6Host } from '../main/ets/network/FnConnectApi';
import { wsDeviceDisplayCode } from '../main/ets/network/FnWsDeviceId';
import {
  buildNasDedupeIndex,
  nasDedupeIndexHasLocal,
  nasDedupeIndexMatchKind,
  nasDedupeMatchIsStrong,
  officialSizeMtimeSetHas
} from '../main/ets/album/GalleryAutoSyncOfficialFingerprint';
import { smartCategoryCount } from '../main/ets/album/GalleryAlbumEntityData';
import { smartCategoryPatchCountByName } from '../main/ets/album/SmartCategoryLayoutPreferences';
import { loginSecretLooksWrapped } from '../main/ets/auth/LoginSecretStore';
import { parseSavedUsersJson } from '../main/ets/auth/SessionPreferences';
import {
  emptyLoginConfig,
  settingsNasMismatchMessage,
  settingsNasTokensFromLogin,
  settingsSameNas
} from '../main/ets/sync/AppSettingsEnvelope';

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

    it('loginSecretLooksWrapped_v1_blob', 0, () => {
      expect(loginSecretLooksWrapped('')).assertFalse();
      expect(loginSecretLooksWrapped('plain-password')).assertFalse();
      expect(loginSecretLooksWrapped('v1.')).assertFalse();
      expect(loginSecretLooksWrapped('v1.aaa.bbb.ccc')).assertTrue();
    });

    it('parseSavedUsersJson_reads_sealed_s_not_password', 0, () => {
      const sealed = 'v1.aaa.bbb.ccc';
      const rows: Object[] = [
        { username: 'alice', rememberPassword: true, s: sealed, password: 'should-not-win' },
        { username: 'bob', rememberPassword: true, password: 'legacy-plain' },
        { username: 'carol', rememberPassword: false, password: 'ignored' }
      ];
      const users = parseSavedUsersJson(JSON.stringify(rows));
      expect(users.length).assertEqual(3);
      expect(users[0].password).assertEqual(sealed);
      expect(users[1].password).assertEqual('legacy-plain');
      expect(users[2].password).assertEqual('');
      expect(users[2].rememberPassword).assertFalse();
    });

    it('settingsSameNas_same_fnid_different_lan', 0, () => {
      const local = emptyLoginConfig();
      local.fnId = 'alpha';
      local.lan = '192.168.1.10';
      const remote = emptyLoginConfig();
      remote.fnId = 'alpha';
      remote.lan = '10.0.0.5';
      expect(settingsSameNas(
        settingsNasTokensFromLogin(local),
        settingsNasTokensFromLogin(remote)
      )).assertTrue();
    });

    it('settingsSameNas_different_fnid_same_lan', 0, () => {
      const local = emptyLoginConfig();
      local.fnId = 'alpha';
      local.lan = '192.168.1.10';
      const remote = emptyLoginConfig();
      remote.fnId = 'bravo';
      remote.lan = '192.168.1.10';
      expect(settingsSameNas(
        settingsNasTokensFromLogin(local),
        settingsNasTokensFromLogin(remote)
      )).assertFalse();
    });

    it('settingsSameNas_no_fnid_same_lan', 0, () => {
      const local = emptyLoginConfig();
      local.lan = '192.168.1.10:5666';
      const remote = emptyLoginConfig();
      remote.lan = 'http://192.168.1.10';
      expect(settingsSameNas(
        settingsNasTokensFromLogin(local),
        settingsNasTokensFromLogin(remote)
      )).assertTrue();
    });

    it('settingsSameNas_empty_rejected', 0, () => {
      expect(settingsSameNas([], ['host:192.168.1.10'])).assertFalse();
      expect(settingsSameNas(
        settingsNasTokensFromLogin(emptyLoginConfig()),
        settingsNasTokensFromLogin(emptyLoginConfig())
      )).assertFalse();
      expect(settingsNasMismatchMessage(
        settingsNasTokensFromLogin(emptyLoginConfig()),
        settingsNasTokensFromLogin(emptyLoginConfig())
      )).assertEqual('配置未标明来源 NAS，未导入');
    });

    it('settingsSameNas_relay_url_matches_fnid', 0, () => {
      const local = emptyLoginConfig();
      local.fnId = 'alpha';
      const remote = emptyLoginConfig();
      remote.fnId = 'https://alpha.fnos.net';
      expect(settingsSameNas(
        settingsNasTokensFromLogin(local),
        settingsNasTokensFromLogin(remote)
      )).assertTrue();
      const fromRelay = settingsNasTokensFromLogin(emptyLoginConfig(), ['https://alpha.5ddd.com']);
      expect(settingsSameNas(fromRelay, settingsNasTokensFromLogin(local))).assertTrue();
    });

    it('settingsNasMismatchMessage_other_nas', 0, () => {
      const local = emptyLoginConfig();
      local.fnId = 'alpha';
      const remote = emptyLoginConfig();
      remote.fnId = 'bravo';
      expect(settingsNasMismatchMessage(
        settingsNasTokensFromLogin(local),
        settingsNasTokensFromLogin(remote)
      )).assertEqual('配置来自其他 NAS，未导入');
    });

    it('wsDeviceDisplayCode_stable_and_readable', 0, () => {
      const a = wsDeviceDisplayCode('m1k2-abc123xyz-def456uvw');
      const b = wsDeviceDisplayCode('M1K2-ABC123XYZ-DEF456UVW');
      const c = wsDeviceDisplayCode('other-device-id');
      expect(a).assertEqual(b);
      expect(a === c).assertFalse();
      expect(a.length).assertEqual(9);
      expect(a.substring(4, 5)).assertEqual('-');
      expect(wsDeviceDisplayCode('')).assertEqual('');
      expect(wsDeviceDisplayCode('   ')).assertEqual('');
    });
  });
}
