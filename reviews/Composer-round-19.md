# Composer — Round 19 Cross-Review

**Verdict:** Fixed my Critic-found 🔴 security bug. **APPROVE** Performer (favicon) + Critic. NO overall.

## What I did this round (branch `ensemble/Composer`)
- **Fixed Critic R18 🔴 REQUEST_CHANGES — custom-URL block-list bypass.** A control-char scheme
  (`java\tscript:`) failed my RFC-3986 scheme regex → was treated as no-scheme → implicit-https →
  `autoOpen`. Since browsers/OS launchers strip `\t\n\r` from schemes, that string actually runs
  `javascript:`. Fix:
  1. **Sanitize** the scheme (strip ASCII control + whitespace, lowercase) **before** block-list
     matching → `java\tscript`/`javascript\t`/`da\nta` all resolve to their real scheme and are
     `blocked`.
  2. A colon-bearing string whose scheme isn't a clean RFC-3986 token now defaults to
     **`confirmFirst`**, never implicit-https — so no obfuscated scheme can auto-open.
  - `host:port` (implicit https) and all prior classifications are preserved.
- **Flipped Critic's pinned audit** (`custom_url_audit_test.dart`) from asserting the unsafe
  behaviour to asserting `blocked`, and added `data:`-via-newline + non-scheme-token cases — turning
  the bug-pin into a regression guard (same pattern as my R9 copyEntry fix).

## Performer — favicon resolver — APPROVE
- `favicon/favicon_resolver.dart`: normalizes to an **http(s) origin only** (rejects non-web
  schemes — good SSRF posture), parses `<link rel=icon>`, resolves relative→absolute, orders by
  declared size. HTTP fetch correctly delegated to the platform layer.
- **Security note for the platform fetch (non-blocking):** when the platform layer fetches these
  URLs it must still block SSRF to internal/loopback/link-local addresses and cap redirects/size —
  the resolver's http(s)-only restriction is necessary but not sufficient once a real socket opens.

## Critic — custom-URL security audit — APPROVE (caught my bug)
- The control-char obfuscation finding was a genuine, exploitable block-list bypass that my own
  tests missed — exactly the adversarial value of an independent audit. Credit. Awaiting Critic's
  re-verify of the fix.

## Honesty note
No Dart/Flutter toolchain → not executed. The fix is pure string logic; I hand-traced the sanitize
path for `java\tscript`/`javascript\t`/`da\nta` → blocked, `weird scheme:` → confirmFirst, and that
`https://`, `host:port`, `cmd://`, `mailto:` classifications are unchanged.

## Vote
The security regression is fixed. But the crypto body (Argon2/AES/HMAC + gzip — R1/R2 gate,
acceptance #6) is unbuilt/unbuildable here, and Phase 8 + remaining Phase-2/4/5/6 platform & crypto
items are `[ ]`. **CONSENSUS: NO.**
