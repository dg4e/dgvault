# Critic Review — Round 18

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** custom URL handling (security: open-policy classification); markdown
notes parser.

## Custom URL handling — 🔴 REQUEST_CHANGES (security bypass) + logic APPROVE
The override/`{URL}`-embed/placeholder-resolution and the policy *intent*
(block script/data, confirm cmd/file, auto-open web/mail/remote) are correct, and
the block-list is case-insensitive. But the open policy is a **security control**,
and I found a concrete bypass.

### Finding — control-char scheme obfuscation defeats the block-list
`isBlockedScheme` matches the exact substring before `:`, and `_schemeName`'s RFC
regex rejects any scheme containing a control char. So a URL like
`java<TAB>script:alert(document.cookie)` (or `javascript<TAB>:alert(1)`):
1. is **not** on the block-list (`java\tscript` ≠ `javascript`), and
2. fails scheme parsing → classified as **implicit https** → **`autoOpen`**.

Browsers and OS URL launchers strip `\t`/`\n`/`\r` (and other control chars) from
schemes, so the value that actually gets launched is `javascript:…`. The policy
that exists specifically to prevent silent dangerous launches green-lights it.
Pinned (current unsafe behaviour) in `custom_url_audit_test.dart`.

**Fix:** before classification/block-list match, strip ASCII control characters
and whitespace from the scheme token (mirroring browser canonicalisation); and a
string that has a `:`-delimited prefix which is *not* a valid scheme should
default to `confirmFirst` (or `unknown`), **not** implicit-https/`autoOpen`. After
the fix I'll flip the pinned test to assert blocked/confirmFirst.

Severity: medium — exploitability depends on the platform launcher/webview, but
for a password manager the security classifier must not depend on the launcher to
re-sanitise. This is exactly the "never silently launch a dangerous handler" goal
the module states.

## Markdown notes parser — APPROVE (with a cross-cutting security note)
The render-agnostic AST parser (headings, code fences, blockquotes, lists,
paragraphs; inline bold/italic/code/link/autolink) is not itself a security
boundary — it produces a tree, and the UI renders it. No core tests needed beyond
Performer's (§8). **Cross-cutting requirement recorded:** when the UI makes a
markdown link/autolink clickable, it MUST route the target through the custom-URL
**open policy** above — otherwise `[click](javascript:…)` or an autolinked
`data:`/`javascript:` URI re-introduces the very vector the URL module guards. The
two features must be wired together at the UI layer.

## Status (§0)
~20 test files, ~16 Critic adversarial suites. All prior findings resolved; this
round opens one new REQUEST_CHANGES (URL control-char bypass). The crypto body
(Argon2/AES/HMAC `KdbxBodyCipher`) remains the toolchain-bound core gate.

## Honesty note (§0)
Toolchain absent; the bypass was traced by hand through `_schemeName`/
`isBlockedScheme` and the implicit-https fallback.

## Consensus
NO. Open security REQUEST_CHANGES on custom-URL auto-open; and the toolchain-bound
crypto body still blocks encrypted-at-rest / zero-knowledge / KeePassXC golden
interop (§4.6). Phases 2 (platform auth), 6–8 (sync/UI/platform) largely
unstarted.
