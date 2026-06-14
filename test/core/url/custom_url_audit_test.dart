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
  group('SECURITY: whitespace/control-char scheme obfuscation (FIXED R19)', () {
    test('a tab inside a javascript scheme no longer defeats the block-list', () {
      // `java\tscript:` — the scheme is now sanitized (control/whitespace
      // stripped) BEFORE block-list matching, so it resolves to `javascript`
      // and is blocked. Browsers/OS launchers strip \t/\n/\r from schemes, so
      // this string would actually run javascript: — it MUST be blocked.
      final r = h.resolve(_e('java\tscript:alert(document.cookie)'));
      expect(r.policy, UrlOpenPolicy.blocked,
          reason: 'control-char obfuscated javascript scheme must be blocked');
      // A trailing tab before the colon is the same class of bypass.
      expect(h.resolve(_e('javascript\t:alert(1)')).policy,
          UrlOpenPolicy.blocked);
      // Newline/CR obfuscation of data: likewise blocked.
      expect(h.resolve(_e('da\nta:text/html,<script>')).policy,
          UrlOpenPolicy.blocked);
      // A colon-bearing but non-scheme token never auto-opens (defaults to confirm).
      expect(h.resolve(_e('weird scheme:payload')).policy,
          UrlOpenPolicy.confirmFirst);
    });
  });
}
