# ADR-0002: Zero-Knowledge & Key-Lifecycle Model

**Status:** Accepted
**Authors:** Composer.

## Context
The product promises a zero-knowledge architecture: only the user's secrets can
decrypt their data, and plaintext credentials must never be persisted or leaked
to logs, swap, or sync providers.

## Decision
1. **No plaintext at rest.** The database file is always encrypted with a key
   derived from the user's `CompositeCredential` (password, key file, YubiKey
   challenge-response) via Argon2 (`KdfParams`). Sync providers only ever see
   ciphertext.
2. **Derived keys live in memory only**, behind `SecureKey`, and are wiped via
   `destroy()` on lock. Secret field values use `ProtectedValue` and are zeroed
   via `dispose()`.
3. **OS keystore wraps, never stores, the master secret.** Biometric/PIN unlock
   stores a *wrapping key* in Keychain/Keystore/libsecret/DPAPI that unwraps a
   cached database key; the master password itself is never written to disk.
4. **Duress paths are first-class** (see plan R5): a duress PIN either opens a
   decoy database or triggers irreversible wipe of the real data and its keys.
5. **No secret logging.** `avoid_print` is lint-enforced; `ProtectedValue` does
   not implement `toString` to reveal contents.

## Key lifecycle
```
unlock:  credential ──Argon2──▶ SecureKey ──▶ Cipher.decrypt ──▶ Database(in mem)
lock:    SecureKey.destroy() + every ProtectedValue.dispose()  ──▶ zeroed
wipe:    delete db file + backups + keystore wrapping key (duress / app-lock)
```

## Consequences
- + Provider compromise yields only ciphertext.
- + Memory-scrape window minimized by explicit zeroing on lock.
- − Requires discipline: every new secret-bearing field must use `ProtectedValue`;
  Critic audits this in security review.
