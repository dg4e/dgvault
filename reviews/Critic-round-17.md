# Critic Review — Round 17

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** TOTP/HOTP module (Phase 3 Critic task); R15 backup-name fix
verification.

## TOTP / HOTP — APPROVE (R2 crypto-adjacent)
`Totp` is correct and cleanly layered — the only crypto primitive (HMAC) is
injected via `OtpHmac`, so all the bug-prone pure logic is headless-testable:
- **Dynamic truncation** (RFC 4226 §5.3): `offset = digest[last] & 0x0f`, 4 bytes
  from `offset` with the high bit masked. Verified by hand against the RFC §5.4
  canonical example (digest `1f86…555a` → offset 10 → `0x50EF7F19` = 1357872921 →
  `872921`).
- **Counter framing**: 8-byte big-endian — correct.
- **TOTP counter**: `floor(unixSeconds / period)` — correct (RFC 6238, T0=0).
- **Steam**: base-26 over the 26-char Steam alphabet, 5 digits — correct.
- **Base32** (RFC 4648): case/padding/whitespace tolerant, rejects invalid chars.
- **otpauth://**: secret/digits/period/algorithm/label parsing, Steam detection
  via `encoder=steam` or `issuer=steam` forcing 5-digit Steam encoding.

Composer's own test suite is genuinely thorough (RFC 4226 Appendix-D counters
0–2, time-stepping, an *exact* Steam value `GG5F5`, base32 vectors, otpauth
parse + rejections). Per §8 I did **not** duplicate it. The one independent gap:
every Appendix-D counter-0 digest truncates at **offset 0**, so the non-zero
offset path wasn't pinned by a second source. I added `totp_audit_test.dart`:
- RFC 4226 **§5.4** canonical example (`872921`) — exercises offset-10 truncation
  independently of Appendix-D;
- digit-slicing (8/4 digits of the same binary → `57872921` / `2921`);
- an exact-multiple base32 boundary (`JBSWY3DP` → `Hello`, 5 bytes / 8 chars, no
  padding) + lowercase tolerance.

This completes my Phase 3 Critic task (generator adversarial audit R3 + TOTP RFC
vectors R17).

## R15 backup-name fix — VERIFIED
`nextBackupName` now uses millisecond resolution (`yyyyMMddTHHmmssSSS`), shrinking
the same-name collision window from 1s to 1ms while keeping lexical = chronological
order. My R15 minor finding is addressed (a counter suffix would fully eliminate
sub-millisecond collisions, but ms-resolution is a reasonable close).

## Status read (§0)
Unchanged from R16: every pure-Dart feature is implemented, reviewed, and signed
off; ~19 test files, ~15 Critic adversarial suites. The sole remaining core gate
is the real `KdbxBodyCipher` (Argon2id + AES/ChaCha + HMAC + protected-value
inner-stream), which cannot be built here (no Dart/pub toolchain to add vetted
crypto). When TOTP's real HMAC-SHA1/256/512 lands from that same crypto layer, my
RFC 6238 Appendix-B end-to-end TOTP vectors are ready to run too.

## Honesty note (§0)
Toolchain absent; truncation math and digit slicing verified by hand against the
RFC.

## Consensus
NO. TOTP signed off and my Phase 3 Critic task complete, but the toolchain-bound
crypto body still blocks encrypted-at-rest / zero-knowledge / KeePassXC golden
interop (§4.6). Phases 2 (platform auth), 6–8 (sync/UI/platform) largely
unstarted.
