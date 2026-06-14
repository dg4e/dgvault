# Composer — Round 10 Cross-Review

**Verdict: APPROVE** Critic and Performer. I took on the **escalated Phase-1 spine gap** with the
KeePass XML codec. Overall: NO (binary KDBX/crypto still pending).

## What I shipped this round (branch `ensemble/Composer`)
- `lib/core/format/keepass_xml.dart` — **KeePass 2.x inner-XML codec** (model ⇄ XML) on the vetted
  `package:xml`. This is the decrypted inner document of a KDBX file; it maps groups, entries,
  standard + custom String fields (with `Protected` flag), tags, icons, ISO-8601 times, attachment
  refs + the binary pool (base64), and flat entry history. **Directly addresses the "KeePass XML
  format compatibility" technical requirement and unblocks two stuck items:** Performer's KDBX
  reader/writer (now only needs header + KDF + cipher around this) and Critic's golden round-trip.
- `test/core/format/keepass_xml_test.dart` — round-trips meta, fields (incl. protected + custom),
  tags/icon/times, attachment refs + pool bytes, and history; asserts well-formed `<KeePassFile>`.
- **Layering kept honest:** documented that the inner-stream cipher for protected values is the
  KDBX layer's job; at this layer values are already plaintext. No hand-rolled XML or crypto.

## Critic — sort adversarial audit — APPROVE
- `entry_sort_audit_test.dart` targets the exact invariants my index-decorated stable sort
  guarantees: descending must NOT reverse equal-key ties, `sorted()` is pure, `moveBefore` handles
  the entry-before-anchor index shift and rejects non-members, nulls last both directions. All hold
  by construction. Good adversarial coverage.

## Performer — merge M1/M2 fixes — APPROVE
- M1 (history-union on LWW) and M2 (attachment diffs) are fixed; Critic's audit now asserts the
  overwritten target version is snapshotted to history (recoverable). This closes the data-loss
  finding I flagged R9 and makes "Advanced Sync & Merge" acceptance-safe. Good.

## The real blocker (unchanged, now narrower)
- The **binary KDBX spine** — outer header codec + VariantDictionary, Argon2 KDF, AES/ChaCha cipher
  block, HMAC block stream, encrypted-at-rest, key files — is still `[ ]` after 10 rounds. My XML
  codec removes one excuse: the remaining work is well-scoped binary + crypto-library wiring against
  the `Cipher`/`KeyDerivation` interfaces. **This must be Performer's top priority next round**; a
  KeePass-compatible manager that cannot read/write a real `.kdbx` file is not done, period.

## Honesty note
No Dart/Flutter toolchain → `flutter analyze`/`flutter test` **not executed**. Codec uses stable
`package:xml` 6.x APIs (`XmlBuilder`, `XmlDocument.parse`, `getElement`/`findElements`/`innerText`/
`getAttribute`); round-trip logic + DateTime/base64/whitespace edges hand-traced.

## Vote
Real progress on KeePass interop (XML codec), but the crypto/KDBX spine — the R1/R2 gate — remains
unbuilt, and Phases 2/8 + much of 3/5/6/7 are untouched. **CONSENSUS: NO.**
