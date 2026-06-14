# Composer — Round 17 Cross-Review

**Verdict: APPROVE** Performer (custom icons) + Critic. Shipped custom URL handling. Overall: NO.

## What I shipped this round (branch `ensemble/Composer`)
- `lib/core/url/custom_url.dart` — **Custom URL handling**: resolves the effective URL for an entry
  with KeePass-faithful **override precedence** (override replaces the URL field; `{URL}` token
  embeds the original, e.g. `cmd://open {URL}`), **placeholder expansion** via the shared
  `PlaceholderResolver`, **scheme classification**, and a **safe-to-open policy**:
  - autoOpen: http/https/ssh/sftp/ftp/mailto (+ bare host → implicit https);
  - confirmFirst: `cmd://` commands, `file:`, unknown schemes;
  - **blocked: `javascript:` / `data:` / `vbscript:`** (injection defense — caught my own bug pre-
    merge where these classified as `unknown`→confirm instead of hard-blocked).
- `test/core/url/custom_url_test.dart` — classification matrix, host:port-not-a-scheme heuristic,
  blocked URIs, empty URL, override replace + `{URL}` embed + empty-override fallback, and
  placeholder resolution (with/without resolver).

## Performer — custom icons + preset icon sets — APPROVE
- `icons/custom_icons.dart`: `IconRef` (preset index | custom UUID), `CustomIconPool` with
  **content-dedup** (`addDeduplicated` returns the existing UUID for identical bytes), and
  `CustomIconService` reference-scan + **orphan prune** across the DB — the same pool-integrity
  pattern as my cross-DB binary relink. Consistent and correct.
- Also landed the `nextBackupName` sub-second fix from Critic's R15 note. Good follow-through.

## Critic — clipboard auto-clear security review — APPROVE
- The supersession end-to-end assertion (stale timer inert past its own clearAt) is the right probe;
  the "verify clipboard still holds the secret before wiping" caller caveat is correct.

## Pending on my work
- TOTP (R16) still needs Critic's RFC-vector + Steam audit (their Phase-3 task, marked PENDING R17).
  My RFC 4226 vectors are baked into the author tests; Critic's independent pass will confirm.

## Honesty note
No Dart/Flutter toolchain → not executed. URL handler is pure string/`RegExp` logic + the resolver;
I hand-traced the scheme heuristic (bare `host:port` → no-scheme → implicit https), the block-list
override, and the `{URL}`-embed-then-resolve order.

## Vote
Custom URL handling done; icons approved. But the crypto body (Argon2/AES/HMAC + gzip) — the R1/R2
gate and acceptance #6 — is unbuilt/unbuildable here, TOTP awaits sign-off, and Phase 8 + parts of
2/4/5/6/7 remain `[ ]`. **CONSENSUS: NO.**
