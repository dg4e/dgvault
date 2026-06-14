# Composer — Round 20 Cross-Review

**Verdict:** Hardened my Critic-found registry gap. **APPROVE** Performer (direct-URL/local-net).
Overall: NO.

## What I did this round (branch `ensemble/Composer`)
- **Hardened Critic R19 🟠 — registry local-only downgrade gap.** `register()` protected the
  local-only flag on *relocate* but not on *re-register*: overwriting an existing local-only id with
  a `localOnly:false` descriptor silently lifted the guarantee and made a once-local-only vault
  syncable. Fix: `register()` now throws `LocalOnlyViolation` when re-registering an existing
  local-only id as non-local-only. Same-guarantee re-register (new local path) and *upgrades*
  (non-local-only → local-only, more restrictive) remain allowed.
- **Flipped Critic's pinned audit** to assert rejection + added the allowed-cases test
  (re-register-local-as-local, upgrade-to-local). Bug-pin → regression guard (R9/R19 pattern).

## Performer — direct URL import + local-network-only guard — APPROVE
- `net/network_import.dart`: a centralized `HostClassifier.isLocal` covering loopback (127/8, ::1),
  RFC1918 (10/8, 192.168/16, 172.16–31/12), link-local (169.254/16, fe80::/10), IPv6 ULA (fc00::/7),
  mDNS `.local`, `localhost`, and single-label LAN names — exactly the SSRF-relevant centralization I
  asked for around favicon. `DirectImportUrl` validates + format-dispatches. Clean and correct.
- **Security note (non-blocking, for the platform fetch layer):** string classification can't stop
  **DNS rebinding** — a public hostname that resolves to a local IP at connect time passes a
  hostname check. So: for *local-network-only* transfer, resolve then re-check the **resolved IP**;
  and for the *outbound* direct-URL/favicon fetch, SSRF-block on the **resolved IP** (not just the
  hostname). The classifier is the right primitive for both; it must run post-DNS at the socket.

## Status — non-platform/non-crypto surface is essentially complete
Every `[ ]` left is either (a) the toolchain-gated crypto body (Argon2/AES/HMAC + gzip, encrypted
storage, CSV-encrypted, KDF), or (b) platform-channel work needing a real device/OS (PIN/biometric/
YubiKey/passkeys/secure-storage/AutoFill/iOS-Files/SSH-agent/cloud-sync/SFTP/WebDAV), or (c)
Critic's golden round-trip which is itself blocked on (a). None are headless-buildable here.

## Honesty note
No Dart/Flutter toolchain → not executed. The fix is a single guard; I traced that downgrade throws,
upgrade/same-guarantee re-register pass, and my prior registry tests are unaffected (no same-id
downgrade among them).

## Vote
Registry hardened; URL fix (R19) and duress/TOTP/key-file all signed off. But acceptance #6 (real
`.kdbx` round-trip) and the R1/R2 crypto gate remain unmet/unbuildable in this sandbox, and Phase 8
+ Phase-2/4 platform items are `[ ]`. **CONSENSUS: NO.**
