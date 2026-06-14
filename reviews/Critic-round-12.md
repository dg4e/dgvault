# Critic Review — Round 12

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** KDBX4 header + VariantDictionary binary codecs; collision check;
Phase 1 status.

## Collision — resolved, verified
The R11 double-build of the KDBX header/VariantDictionary (Composer + Performer)
was reconciled to Composer's split form (`variant_dictionary.dart` +
`kdbx_header.dart`); Performer's combined file was superseded. I confirmed master
carries exactly one `VariantDictionary` class — no duplicate symbol, no dead file.

## VariantDictionary codec — APPROVE
Pure little-endian binary, all 7 wire types, insertion-order preserved, version
gate, clean exceptions. Composer's tests cover type round-trips / order / absent /
version. I added `variant_dictionary_audit_test.dart` for interop-critical edges:
- **byte-stability** — `serialize → parse → serialize` must be byte-identical
  because the dictionary's bytes are inside the KDBX header's SHA-256/HMAC; any
  non-determinism would fail header verification against a KeePass-written file;
- value edges — large `uint64` (> 2^32), unicode strings, empty string/bytes,
  both bools;
- multibyte-key framing — `int32 keyLen` is a BYTE length, so a char-vs-byte
  confusion would misframe the whole stream.
All trace clean against the wire format.

### Minor finding — Int32/Int64 lack typed accessors
`typeInt32` (0x0C) / `typeInt64` (0x0D) are decoded and encoded, and round-trip
structurally (preserved in `_Entry`), but there are no `getInt32/setInt32/
getInt64/setInt64` methods — a file value of those types can't be read via the
typed API. KDF params don't use signed types, so it's non-blocking; worth adding
for completeness and to avoid a `value as int` surprise on `getUInt32` of a signed
entry.

## KDBX header codec — APPROVE (spot review)
Composer's header tests cover Argon2id/AES-KDF param mapping, `$UUID`-missing
rejection, AES + ChaCha20 + compression-flag round-trips, bad-magic and
bad-version rejection. Looks structurally sound. I will fold the header into the
golden round-trip suite once the crypto envelope makes a full `.kdbx` openable.

## Phase 1 status — spine is now "crypto-only"
Structural pieces exist on master: domain model, inner-XML codec, outer-header +
VariantDictionary codec. **What remains is the actual cryptography:** Argon2id KDF
transform, AES-256/ChaCha20 cipher, the HMAC block-stream framing, the inner-
stream cipher for protected values (my R11 interop flag), and master-password/
key-file composite key. Until those land and compose into a reader/writer, the app
still cannot open or save a real encrypted database, and acceptance §4.6 (golden
`.kdbx` interop) stays blocked. The remaining work is the security-critical part —
when it lands I will prioritise: KDF/cipher known-answer vectors (R2), the
protected-value inner-stream boundary, and the KeePassXC golden round-trip.

## Prior findings
All resolved (verified through R10). No open REQUEST_CHANGES.

## Honesty note (§0)
Toolchain absent; assertions traced against source + KDBX wire format by hand.
Master suite now ~13 test files incl. 9 Critic adversarial suites.

## Consensus
NO. Encrypted persistence, zero-knowledge, and golden interop remain
undemonstrable until the crypto envelope exists. Structural Phase-1 progress is
real and clean, but the product still cannot open/save an encrypted `.kdbx`.
Phases 2/8 and much of 3/5/6/7 unstarted.
