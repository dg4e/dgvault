# Performer — Round 22 (crypto layer)

**The toolchain-gated crypto spine is built and verified.** With the SDK actually
runnable (R21), the Phase-1 crypto layer that blocked the product's three core
guarantees (KeePass-compatible / zero-knowledge / encrypted) is now real, using
vetted pointycastle primitives only — no hand-rolled crypto (§1.1/§2.2).

## Shipped
1. **Argon2 KDF** — `lib/core/crypto/impl/argon2_kdf.dart`
   `Argon2KeyDerivation` builds the KeePass composite key (SHA-256 of the
   per-factor hashes: password→SHA-256, 32-byte key file verbatim, CR→SHA-256)
   and runs pointycastle's Argon2d/Argon2id. Maps `KdfParams` (iterations/
   memoryKib/parallelism/version) onto Argon2's parameters.

2. **Authenticated ciphers** — `lib/core/crypto/impl/aead_cipher.dart`
   `AesGcmCipher` (AES-256-GCM) and `ChaCha20Poly1305Cipher` implement the
   `Cipher` contract; wrong key / tamper → `CipherAuthenticationException`
   (normalised across GCM's `InvalidCipherTextException` and ChaCha-Poly's
   ArgumentError MAC failure). 12-byte nonce, 16-byte tag appended.

3. **Real KDBX4 body cipher** — `lib/core/crypto/impl/kdbx4_body_cipher.dart`
   `Kdbx4BodyCipher` does the genuine KDBX4 construction behind the existing
   `KdbxBodyCipher` interface: transformedKey = Argon2(composite, kdfSalt);
   masterKey = SHA-256(seed‖tk); hmacBase = SHA-512(seed‖tk‖0x01); per-block key
   = SHA-512(LE64(i)‖hmacBase). Body = SHA-256(header) ‖ HMAC(header, key=block
   0xFFFF…FF) ‖ HMAC-SHA-256 block stream over AES-256-CBC(PKCS7) / ChaCha20
   (RFC 7539) ciphertext. Drops straight into `KdbxCodec` — the pipeline now
   reads/writes real encrypted `.kdbx`.

4. **gzip compressor** — `lib/data/format/gzip_compressor.dart` (`dart:io`
   GZipCodec, CompressionFlags=1) in the data layer; core stays platform-neutral.

## Verification (this is the point — it actually runs now)
- **Argon2:** pointycastle matches the **RFC 9106 §5.3 Argon2id KAT** exactly,
  and independently agrees with the `cryptography` package on a password+salt
  case. Full `deriveKey` path pinned with regression KATs + composite-wiring
  cross-check + determinism/sensitivity. (`argon2_kdf_test.dart`)
- **AEAD:** ChaCha20-Poly1305 matches the **RFC 8439 §2.8.2 KAT**; both ciphers
  cross-checked byte-for-byte against the `cryptography` package; round-trip,
  wrong-key, tamper, IV-length, streaming. (`aead_cipher_test.dart`)
- **KDBX4:** rich DB (nested groups, protected custom fields, history, unicode,
  XML metachars, whitespace) round-trips through real Argon2+AES-CBC+gzip AND
  Argon2+ChaCha20+gzip; magic bytes correct; body not plaintext; wrong password
  fails the header HMAC; body tamper caught by the block HMAC.
  (`kdbx4_body_cipher_test.dart`)
- **Encrypted CSV** (Phase 6) re-tested with REAL crypto wired in, replacing the
  R21 stub doubles. (`encrypted_csv_real_crypto_test.dart`)

`flutter test`: **440 passing / 0 failing.** `flutter analyze`: **0 issues.**

## Honest gaps (not claimed as done)
- **No KeePassXC golden interop yet.** Round-trips are self-consistent; byte-exact
  compatibility with a third-party `.kdbx` needs a real reference fixture to diff
  against (header verification currently re-serialises `KdbxHeader`, which is
  exact for our own files but may not reproduce a foreign header byte-for-byte).
  This is the one remaining Phase-1 KDBX item.
- **AES-KDF** (legacy) not implemented — `supports()` returns false for it;
  Argon2 is the default. Add when a legacy-import path needs it.
- **Streaming for 250MB DBs (R4):** the AEAD `decryptStream` buffers; the KDBX
  block stream is framed for chunking but currently emits a single block. True
  chunked streaming is a follow-up.
- Single-block stream + re-serialised-header verification are documented in-file.

## Next
KeePassXC reference-fixture golden test (Critic); AES-KDF for legacy reads;
chunked block stream for very large DBs; then platform auth (PIN/biometric/
secure-storage) which is device-gated.
