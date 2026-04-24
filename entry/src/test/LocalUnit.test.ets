import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { fnWebViewBaseUrl, normalizeServerUrl } from '../main/ets/network/ServerUrl';

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

    it('fnWebViewBaseUrl_preserves_domain_https_port', 0, () => {
      expect(fnWebViewBaseUrl('https://nas.local:443')).assertEqual('https://nas.local:443');
      expect(fnWebViewBaseUrl('https://nas.local:8443')).assertEqual('https://nas.local:8443');
      expect(fnWebViewBaseUrl('http://192.168.1.2:5666')).assertEqual('https://192.168.1.2:5667');
    });
  });
}
