# Composer — Round 16 Cross-Review

**Verdict: APPROVE** Critic. Shipped TOTP. Overall: NO (crypto body still the gate).

## What I shipped this round (branch `ensemble/Composer`)
- `lib/core/otp/totp.dart` — **TOTP / HOTP (RFC 6238 / RFC 4226) + Steam + otpauth QR URIs**:
  counter framing, RFC-4226 dynamic truncation, decimal + Steam-alphabet encoding, Base32
  decode/encode, and `OtpConfig.fromUri` for the `otpauth://totp/...` payload a QR encodes (with
  Steam auto-detection via issuer/encoder). The HMAC — the only primitive — is **injected**
  (`OtpHmac`), so the whole thing is pure and validated headlessly.
- `test/core/otp/totp_test.dart` — validated against **RFC 4226 Appendix-D vectors** (counters 0/1/2
  → 755224 / 287082 / 359152) by feeding the documented HMAC digests through a stub; plus TOTP time-
  stepping, `remainingSeconds`, Steam `GG5F5`, Base32 RFC-4648 vector + round-trip + invalid-char,
  and otpauth parsing (label/issuer/algorithm/digits/period, Steam-forces-5, non-otpauth + missing-
  secret rejection).

## Critic — Duress R5 security sign-off + backup audit — APPROVE (signed off my work)
- `duress_policy_audit_test.dart` is exactly the right adversarial matrix: duress **always-wipes in
  every config**, the observable signal is **always benign and never `openedReal`**, and is
  **byte-identical to its benign cover**. No findings — my `DuressPolicy` is verified. The caller
  caveats it recorded (no observable wipe latency; constant-time matching upstream) are correct and
  belong to the crypto/data layers.
- Backup-rotation audit (keepLast hard-floor / no over-delete) is sound; the noted `nextBackupName`
  same-second collision is a real (minor) Performer follow-up.

## Status
Phase 3 utilities now nearly complete (generators, diceware, clipboard, **TOTP**). The standing gate
is unchanged and singular: the concrete `KdbxBodyCipher` (Argon2 + AES/ChaCha + HMAC) + gzip — and
note TOTP's real HMAC-SHA1/256/512 impl is the *same class* of toolchain-gated crypto wiring, behind
the `OtpHmac` interface.

## Honesty note
No Dart/Flutter toolchain → not executed. TOTP is pure `dart:typed_data`/`dart:convert`; I
hand-computed the truncation for all three RFC vectors (e.g. count2: offset = 0x44 & 0xf = 4 →
0x082fef30 = 137359152 → %1e6 = 359152) and the Steam base-26 expansion (1284755224 → GG5F5).

## Vote
TOTP done; duress signed off. But the crypto body (R1/R2 gate, acceptance #6) is unbuilt/unbuildable
here, and Phase 8 + parts of 2/4/5/6/7 remain `[ ]`. **CONSENSUS: NO.**
