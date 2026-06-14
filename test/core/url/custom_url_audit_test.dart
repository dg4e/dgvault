// Critic-owned SECURITY audit for custom URL open-policy classification.
//
// The open policy is a security control: it must never let the UI auto-launch a
// script/data URI. Composer's suite covers the plain cases. This adds the
// obfuscation edge a block-list of scheme *strings* classically misses, and a
// few policy spot-checks.
//
// Toolchain not installed here; assertions traced against source by hand
// (see reviews/Critic-round-18.md).

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/url/custom_url.dart';
import 'package:test/test.dart';

Entry _e(String url) => Entry(uuid: 'e', fields: {
      Field.url: Field(key: Field.url, value: InMemoryProtectedValue.plain(url)),
    });

void main() {
  const h = CustomUrlHandler();

  group('dangerous schemes are blocked (incl. case)', () {
    test('javascript / data / vbscript, any case, are blocked', () {
      for (final u in [
        'javascript:alert(1)',
        'JavaScript:alert(1)',
        'data:text/html,<script>x</script>',
        'DATA:text/html,x',
        'vbscript:msgbox',
      ]) {
        expect(h.resolve(_e(u)).policy, UrlOpenPolicy.blocked, reason: u);
      }
    });
  });

  group('policy gating for normal schemes', () {
    test('web/remote auto-open; command/file confirm first', () {
      expect(h.resolve(_e('https://example.com')).policy, UrlOpenPolicy.autoOpen);
      expect(h.resolve(_e('ssh://host')).policy, UrlOpenPolicy.autoOpen);
      expect(h.resolve(_e('cmd://run something')).policy, UrlOpenPolicy.confirmFirst);
      expect(h.resolve(_e('file:///etc/passwd')).policy, UrlOpenPolicy.confirmFirst);
    });
  });

  // ---- 🔴 SECURITY FINDING (REQUEST_CHANGES) — pinned current behaviour ----
  group('SECURITY: whitespace/control-char scheme obfuscation', () {
    test('a tab inside a javascript scheme DEFEATS the block-list (current bug)', () {
      // `java\tscript:` — the regex in _schemeName rejects the tab, so the string
      // is treated as having NO scheme → implicit https → autoOpen. Browsers and
      // OS launchers strip \t/\n/\r from schemes, so this would actually run
      // javascript:. The block-list must strip ASCII control/whitespace from the
      // scheme BEFORE matching, and a colon-bearing-but-invalid scheme should
      // default to confirmFirst (not https). REQUEST_CHANGES — see review.
      final r = h.resolve(_e('java\tscript:alert(document.cookie)'));
      expect(r.policy, UrlOpenPolicy.autoOpen,
          reason: 'CURRENT UNSAFE behaviour pinned; must become blocked/confirmFirst after fix');
      // A trailing tab before the colon is the same class of bypass.
      expect(h.resolve(_e('javascript\t:alert(1)')).policy, UrlOpenPolicy.autoOpen);
    });
  });
}
