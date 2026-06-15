# Performer — Round 24 (platform pure-logic: PIN unlock + key vault)

The verifiable half of the platform layer (Phase 2). Device-gated channels
(biometric, OS-keystore impl, YubiKey) stay behind interfaces; everything here is
pure logic over the real crypto and is fully tested.

## Shipped
1. **SecureStore abstraction** — `lib/core/security/secure_store.dart`
   Async key→bytes store (the OS keystore boundary) + `InMemorySecureStore` fake.
   `lib/core` depends only on the interface; the Keychain/Keystore/libsecret/DPAPI
   impl (`flutter_secure_storage`) is the platform layer's job.

2. **KeyVault** — `lib/core/security/key_vault.dart`
   AEAD-wraps the database master key under a key derived from a short unlock
   secret (PIN / biometric-released secret) and persists it via `SecureStore` as
   a self-describing blob (cipher + KDF params + salt + iv + ciphertext). A wrong
   PIN fails authenticated decryption — the "comparison" is the AEAD tag, i.e.
   constant-time, no hand-rolled compare. Uses the real `AesGcmCipher` +
   `Argon2KeyDerivation`.

3. **PinUnlock state machine** — `lib/core/security/pin_unlock.dart`
   Ties `KeyVault` to the existing `AppLockPolicy`: a correct PIN returns the
   master key and resets the persistent failure counter; a wrong PIN increments
   it; exhaustion reports lock-out and, when delete-on-fail is enabled, a due
   wipe. Already-locked-out attempts short-circuit (no derivation) and surface
   `isWipePending` so an interrupted wipe is retried (Critic R14 F2). A corrupt/
   missing blob is not treated as a wrong-PIN guess (doesn't consume an attempt).

## Why this is the foundation for the device-gated features
- **Biometric unlock** is the same `KeyVault` flow — biometrics only gate the
  *release* of the unlock secret; the wrapping/unwrapping is identical. Only the
  `LocalAuthentication` channel is device-gated.
- **Auto-lock / delete-on-fail** reuse `AppLockPolicy` (already built + audited).

## Verification
- `key_vault_test.dart`: enroll→unlock round-trip, wrong PIN →
  `CipherAuthenticationException`, the stored blob contains no plaintext key,
  reset, tamper, bad-magic.
- `pin_unlock_test.dart`: success+counter-reset, decrement, reset-after-failure,
  exhaustion→lockout+wipe signal, no-attempt-when-locked, delete-on-fail off ⇒ no
  wipe, corrupt blob doesn't consume an attempt.

`flutter test`: **461 passing / 0 failing.** `flutter analyze`: **0 issues.**

Also refactored `CipherAuthenticationException` onto the `Cipher` *interface*
(`cipher.dart`) so `core/security` catches it without depending on a concrete
cipher impl (the AEAD impl re-exports it for existing importers).

## Honest scope
Genuinely device/OS-gated and NOT built (interfaces only): the real
OS-keystore-backed `SecureStore`, biometric `LocalAuthentication` channel,
YubiKey HMAC-SHA1 challenge-response, Passkeys/WebAuthn, AutoFill, iOS Files,
SSH-agent, and all cloud/SFTP/WebDAV sync. These need real OS APIs / devices and
can't be honestly verified in this sandbox.
